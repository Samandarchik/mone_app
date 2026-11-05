package api

// Spisaniya (hisobdan chiqarish):
//   POST /api/write-offs — stock kamaytirish + write_offs yozuvi
//   GET  /api/write-offs — oxirgi spisaniyalar ro'yxati

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

// ============ POST /api/write-offs ============

func handleCreateWriteOff(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if claims == nil {
		jsonError(w, 401, "unauthorized", "Token kerak")
		return
	}

	var req struct {
		ProductID int    `json:"product_id"`
		Qty       int    `json:"qty"`
		Reason    string `json:"reason"`
		Note      string `json:"note"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Reason = strings.TrimSpace(req.Reason)
	req.Note = strings.TrimSpace(req.Note)
	if req.ProductID <= 0 || req.Qty <= 0 || req.Reason == "" {
		jsonError(w, 400, "bad_request", "product_id, qty (>0) va reason kerak")
		return
	}
	// Chegarasiz qty qoldiqni chuqur manfiyga tushirardi (masalan 1 000 000).
	if req.Qty > maxWriteOffQty {
		jsonError(w, 400, "bad_request",
			fmt.Sprintf("qty %d dan oshmasligi kerak", maxWriteOffQty))
		return
	}
	if len(req.Reason) > 200 || len(req.Note) > 500 {
		jsonError(w, 400, "bad_request", "reason yoki izoh juda uzun")
		return
	}

	// `write_offs` va `stocks` da products'ga tashqi kalit YO'Q. Tekshirmasak
	// mavjud bo'lmagan product_id bilan "arvoh" spisaniya yozuvi tug'ilardi:
	// hisobotda ko'rinadi, qoldiqqa esa hech qanday ta'siri yo'q.
	var exists bool
	if db.Pool.QueryRow(r.Context(),
		"SELECT EXISTS(SELECT 1 FROM products WHERE id = $1 AND status <> 'deleted')",
		req.ProductID).Scan(&exists) != nil || !exists {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi")
		return
	}

	// Qoldiq chiqimi va spisaniya yozuvi BITTA tranzaksiyada.
	//
	// Ilgari ikkisi alohida edi va UPDATE ning xatosi umuman tekshirilmasdi:
	//   - UPDATE yiqilsa yozuv qolardi → qoldiq haqiqatdan yuqori bo'lib qolardi;
	//   - INSERT yiqilsa qoldiq allaqachon kamaygan bo'lardi → kassir qayta
	//     urinib, mahsulot ikki marta hisobdan chiqardi va izsiz yo'qolardi.
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	// Qoldiq qatori yo'q = kuzatilmaydigan mahsulot (upsert qilinmaydi) →
	// new_count null qaytadi. Bu ataylab: sotuv yo'li ham shunday ishlaydi.
	var newCount interface{}
	var cnt int
	err = tx.QueryRow(r.Context(),
		"UPDATE stocks SET count = count - $1, updated_at = NOW() WHERE product_id = $2 RETURNING count",
		req.Qty, req.ProductID).Scan(&cnt)
	switch {
	case err == nil:
		newCount = cnt
	case errors.Is(err, pgx.ErrNoRows):
		// kuzatilmaydigan mahsulot — chiqim yo'q, yozuv baribir qoladi
	default:
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	var note interface{}
	if req.Note != "" {
		note = req.Note
	}
	if _, err := tx.Exec(r.Context(),
		"INSERT INTO write_offs (product_id, qty, reason, note, created_by, created_by_name) VALUES ($1, $2, $3, $4, $5, $6)",
		req.ProductID, req.Qty, req.Reason, note, claims.UserID, claims.Name); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	// Broadcast faqat commit'dan KEYIN: ilgari tranzaksiya yiqilsa ham
	// klientlarga yangi qoldiq e'lon qilinib ulgurardi.
	if c, ok := newCount.(int); ok {
		v := c
		wss.BroadcastStock(req.ProductID, &v, "write_off")
	}

	jsonResponse(w, 200, map[string]interface{}{"ok": true, "new_count": newCount})
}

// maxWriteOffQty — bitta spisaniyada ruxsat etilgan eng katta miqdor.
const maxWriteOffQty = 100000

// maxStockArrivalQty — bitta kirimda/limitda ruxsat etilgan eng katta son.
const maxStockArrivalQty = 1000000

// ============ GET /api/write-offs ============

func handleGetWriteOffs(w http.ResponseWriter, r *http.Request) {
	limit := 50
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			limit = n
		}
	}
	if limit < 1 {
		limit = 1
	}
	if limit > 500 {
		limit = 500
	}

	rows, err := db.Pool.Query(r.Context(), `
		SELECT wo.id, wo.product_id, COALESCE(p.name_uz, ''), wo.qty, wo.reason,
		       wo.note, wo.created_by_name, wo.created_at
		FROM write_offs wo
		LEFT JOIN products p ON p.id = wo.product_id
		ORDER BY wo.id DESC
		LIMIT $1`, limit)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	writeOffs := []map[string]interface{}{}
	for rows.Next() {
		var id, productID, qty int
		var productName, reason string
		var note, createdByName *string
		var createdAt time.Time
		if err := rows.Scan(&id, &productID, &productName, &qty, &reason, &note, &createdByName, &createdAt); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		writeOffs = append(writeOffs, map[string]interface{}{
			"id":              id,
			"product_id":      productID,
			"product_name":    productName,
			"qty":             qty,
			"reason":          reason,
			"note":            note,
			"created_by_name": createdByName,
			"created_at":      createdAt.UTC().Format(time.RFC3339),
		})
	}
	if err := rows.Err(); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	jsonResponse(w, 200, map[string]interface{}{"write_offs": writeOffs})
}
