package api

// Inventarizatsiya:
//   POST /api/inventory (faqat super_admin/admin) — haqiqiy sanoq bo'yicha
//   stocks tuzatiladi, inventory_corrections yoziladi.

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

// invChange — bitta o'zgargan mahsulot (lokal id bilan).
type invChange struct {
	productID int
	oldCount  *int
	newCount  int
}

// ============ POST /api/inventory ============

func handleInventory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if claims == nil || (claims.Role != "super_admin" && claims.Role != "admin") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req struct {
		Items []struct {
			ProductID   int `json:"product_id"`
			ActualCount int `json:"actual_count"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if len(req.Items) == 0 {
		jsonError(w, 400, "bad_request", "items bo'sh")
		return
	}
	if len(req.Items) > maxInventoryItems {
		jsonError(w, 400, "bad_request",
			fmt.Sprintf("bir marotabada %d tadan ko'p mahsulot bo'lmasin", maxInventoryItems))
		return
	}
	seen := map[int]bool{}
	for _, it := range req.Items {
		if it.ProductID <= 0 || it.ActualCount < 0 {
			jsonError(w, 400, "bad_request", "har bir itemda product_id va actual_count (>=0) kerak")
			return
		}
		// Bir mahsulot ikki marta kelsa qaysi biri yozilgani tasodifiy bo'lardi.
		if seen[it.ProductID] {
			jsonError(w, 400, "bad_request",
				fmt.Sprintf("Mahsulot #%d ro'yxatda ikki marta", it.ProductID))
			return
		}
		seen[it.ProductID] = true
	}

	// Butun sanoq BITTA tranzaksiyada. Ilgari har bir mahsulot alohida
	// yozilardi va 30 tadan 7-chisida xato chiqsa, birinchi 6 tasi bazada
	// qolib ketardi — sanoq yarim qo'llanilgan holatda muzlab qolardi.
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	// Deadlock bo'lmasin: qulflar doim product_id o'sish tartibida olinadi
	// (chek yaratishdagi ReserveStock ham shunday ishlaydi).
	items := make([]struct {
		ProductID   int
		ActualCount int
	}, 0, len(req.Items))
	for _, it := range req.Items {
		items = append(items, struct {
			ProductID   int
			ActualCount int
		}{it.ProductID, it.ActualCount})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].ProductID < items[j].ProductID })

	changed := []invChange{}
	respItems := []map[string]interface{}{}

	for _, it := range items {
		// `FOR UPDATE` — SHART. Ilgari qoldiq qulfsiz o'qilardi va SELECT bilan
		// UPSERT orasida sotuv bo'lib ulgursa, sanoq eski songa qaytarib
		// yozardi: sotilgan taom qoldiqda "tirilib", POS mavjud bo'lmagan
		// mahsulotni sotishga ruxsat berardi.
		var old *int
		var current int
		err := tx.QueryRow(r.Context(),
			"SELECT count FROM stocks WHERE product_id = $1 FOR UPDATE", it.ProductID).Scan(&current)
		switch {
		case err == nil:
			old = &current
		case errors.Is(err, pgx.ErrNoRows):
			// kuzatilmaydigan mahsulot — sanoq uni kuzatuvga oladi
		default:
			jsonError(w, 500, "db_error", err.Error())
			return
		}

		if old != nil && *old == it.ActualCount {
			continue // o'zgarish yo'q
		}

		if _, err := tx.Exec(r.Context(),
			`INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, NOW())
			 ON CONFLICT (product_id) DO UPDATE SET count = EXCLUDED.count, updated_at = NOW()`,
			it.ProductID, it.ActualCount); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		if _, err := tx.Exec(r.Context(),
			"INSERT INTO inventory_corrections (product_id, old_count, new_count, created_by, created_by_name) VALUES ($1, $2, $3, $4, $5)",
			it.ProductID, old, it.ActualCount, claims.UserID, claims.Name); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}

		oldVal := 0
		var oldJSON interface{}
		if old != nil {
			oldVal = *old
			oldJSON = *old
		}
		changed = append(changed, invChange{productID: it.ProductID, oldCount: old, newCount: it.ActualCount})
		respItems = append(respItems, map[string]interface{}{
			"product_id": it.ProductID,
			"old_count":  oldJSON,
			"new_count":  it.ActualCount,
			"diff":       it.ActualCount - oldVal,
		})
	}

	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	// Broadcast faqat commit'dan keyin — aks holda orqaga qaytgan sanoq ham
	// klientlarga yangi qoldiq bo'lib e'lon qilinardi.
	for _, c := range changed {
		count := c.newCount
		wss.BroadcastStock(c.productID, &count, "inventory")
	}

	jsonResponse(w, 200, map[string]interface{}{
		"ok":      true,
		"changed": len(changed),
		"items":   respItems,
	})
}

// maxInventoryItems — bitta sanoqda yuboriladigan eng ko'p mahsulot.
const maxInventoryItems = 2000
