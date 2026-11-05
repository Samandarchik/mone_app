package api

// Ombor (ingredientlar) — 1-bosqich:
//   GET  /api/ingredients        — ro'yxat (qoldiq, min, oxirgi narx, low flag)
//   POST /api/ingredient         — yaratish
//   PUT  /api/ingredient/{id}    — tahrirlash
//   DELETE /api/ingredient/{id}  — soft delete (status=deleted)
//   POST /api/ingredient/adjust  — qo'lda korreksiya (haqiqiy songa tenglash)
//   GET  /api/ingredient/moves   — harakatlar tarixi
//
// QOIDA: hamma miqdor saqlash birligida BUTUN son (kg→gr, l→ml, dona, m).
// Har bir o'zgarish ing_moves ga yoziladi — applyIngMove yagona mutatsiya nuqtasi.

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

var validIngUnits = map[string]bool{"gr": true, "ml": true, "dona": true, "m": true}

// requireAdminRole — faqat super_admin/admin (S7 qarori). Ruxsat bo'lmasa
// javob yozib nil qaytaradi.
func requireAdminRole(w http.ResponseWriter, r *http.Request) *middleware.TokenClaims {
	claims := middleware.GetUser(r.Context())
	if claims == nil || (claims.Role != "super_admin" && claims.Role != "admin") {
		jsonError(w, 403, "forbidden", "Faqat admin/super_admin")
		return nil
	}
	return claims
}

// applyIngMove — ombor qoldig'ining YAGONA mutatsiya nuqtasi: count o'zgaradi,
// ing_moves ga yoziladi, WSS broadcast ketadi. qty musbat=kirim, manfiy=chiqim.
// Qoldiq manfiy bo'lishi mumkin (bloklamaydi) — farq ko'rinib turadi.
func applyIngMove(ctx context.Context, ingredientID int, qty int64, reason, ref, comment, createdBy string) (int64, error) {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)
	newCount, err := applyIngMoveTx(
		ctx, tx, ingredientID, qty, reason, ref, comment, createdBy, true,
	)
	if err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	wss.H.BroadcastEvent("ingredient:updated", map[string]interface{}{
		"ingredient_id": ingredientID, "count": newCount, "reason": reason,
	})
	return newCount, nil
}

func applyIngMoveTx(
	ctx context.Context,
	tx pgx.Tx,
	ingredientID int,
	qty int64,
	reason, ref, comment, createdBy string,
	manageBatches bool,
) (int64, error) {
	var current int64
	if err := tx.QueryRow(ctx, `
		SELECT count FROM ingredients
		WHERE id=$1 AND status<>'deleted'
		FOR UPDATE`,
		ingredientID,
	).Scan(&current); err != nil {
		return 0, err
	}
	if manageBatches {
		if qty < 0 {
			if err := consumeIngredientBatchesTx(
				ctx, tx, ingredientID, -qty, current, reason, ref,
			); err != nil {
				return 0, err
			}
		} else if qty > 0 {
			if reason == "qaytarildi" && ref != "" {
				if err := restoreIngredientBatchesTx(
					ctx, tx, ingredientID, qty, reason, ref,
				); err != nil {
					return 0, err
				}
			} else if reason != "kirim" {
				if _, err := tx.Exec(ctx, `
					INSERT INTO ingredient_batches
						(ingredient_id,batch_code,received_qty,remaining_qty,
						 status,note,created_by)
					VALUES ($1,$2,$3,$3,'active',$4,$5)`,
					ingredientID, automaticBatchCode(reason), qty, comment, createdBy,
				); err != nil {
					return 0, err
				}
			}
		}
	}
	newCount := current + qty
	if newCount < 0 {
		return 0, errInsufficientIngredientStock
	}
	if _, err := tx.Exec(ctx,
		"UPDATE ingredients SET count=$1 WHERE id=$2",
		newCount, ingredientID,
	); err != nil {
		return 0, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO ing_moves
			(ingredient_id,qty,reason,ref,comment,created_by)
		VALUES ($1,$2,$3,$4,$5,$6)`,
		ingredientID, qty, reason, ref, comment, createdBy,
	); err != nil {
		return 0, err
	}
	return newCount, nil
}

// ingUnitPrice — 1 ko'rsatish birligi narxi (butun so'm): gr/ml uchun 1 kg/l
// (×1000), dona/m uchun 1 dona/m. Nisbat xotirada float, javobda butun son.
func ingUnitPrice(unit string, qty, subtotal int64) int64 {
	if qty <= 0 {
		return 0
	}
	factor := float64(1)
	if unit == "gr" || unit == "ml" {
		factor = 1000
	}
	return int64(math.Round(float64(subtotal) / float64(qty) * factor))
}

// ============ GET /api/ingredients ============

func handleGetIngredients(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	rows, err := db.Pool.Query(r.Context(), `
		SELECT i.id, i.name, i.unit, i.count, i.min_qty, i.waste_percent, i.status,
		       COALESCE(pi.qty, 0), COALESCE(pi.subtotal, 0),
		       COALESCE(bt.total_qty,0),COALESCE(bt.active_batches,0)
		FROM ingredients i
		LEFT JOIN LATERAL (
			SELECT qty, subtotal FROM purchase_items
			WHERE ingredient_id = i.id ORDER BY id DESC LIMIT 1
		) pi ON true
		LEFT JOIN LATERAL (
			SELECT
			  COALESCE(SUM(remaining_qty) FILTER (
			    WHERE status='active' AND remaining_qty>0
			  ),0) AS total_qty,
			  COUNT(*) FILTER (
			    WHERE status='active' AND remaining_qty>0
			  ) AS active_batches
			FROM ingredient_batches WHERE ingredient_id=i.id
		) bt ON true
		WHERE i.status <> 'deleted'
		ORDER BY i.name`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var id, waste int
		var count, minQty, lastQty, lastSubtotal int64
		var batchQty int64
		var activeBatches int
		var name, unit, status string
		if err := rows.Scan(
			&id, &name, &unit, &count, &minQty, &waste, &status,
			&lastQty, &lastSubtotal, &batchQty, &activeBatches,
		); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		items = append(items, map[string]interface{}{
			"id": id, "name": name, "unit": unit, "count": count,
			"min_qty": minQty, "waste_percent": waste, "status": status,
			"unit_price":  ingUnitPrice(unit, lastQty, lastSubtotal),
			"low":         minQty > 0 && count < minQty,
			"tracked_qty": batchQty, "active_batches": activeBatches,
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"ingredients": items})
}

// ============ POST /api/ingredient ============

func handleCreateIngredient(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	var req struct {
		Name         string `json:"name"`
		Unit         string `json:"unit"`
		MinQty       int64  `json:"min_qty"`
		WastePercent int    `json:"waste_percent"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || !validIngUnits[req.Unit] {
		jsonError(w, 400, "bad_request", "name va unit (gr|ml|dona|m) kerak")
		return
	}
	if req.MinQty < 0 || req.WastePercent < 0 || req.WastePercent > 90 {
		jsonError(w, 400, "bad_request", "min_qty >= 0, waste_percent 0..90")
		return
	}

	var exists int
	db.Pool.QueryRow(r.Context(),
		"SELECT COUNT(*) FROM ingredients WHERE LOWER(name) = LOWER($1) AND status <> 'deleted'",
		req.Name).Scan(&exists)
	if exists > 0 {
		jsonError(w, 409, "duplicate", "Bu nomli ingredient allaqachon bor")
		return
	}

	var id int
	err := db.Pool.QueryRow(r.Context(),
		"INSERT INTO ingredients (name, unit, min_qty, waste_percent) VALUES ($1, $2, $3, $4) RETURNING id",
		req.Name, req.Unit, req.MinQty, req.WastePercent).Scan(&id)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"id": id, "name": req.Name, "unit": req.Unit, "count": 0,
		"min_qty": req.MinQty, "waste_percent": req.WastePercent, "status": "active",
	})
}

// ============ PUT /api/ingredient/{id} ============

func handleUpdateIngredient(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	if id <= 0 {
		jsonError(w, 400, "bad_request", "id noto'g'ri")
		return
	}
	var req struct {
		Name         string `json:"name"`
		MinQty       *int64 `json:"min_qty"`
		WastePercent *int   `json:"waste_percent"`
		Status       string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		jsonError(w, 400, "bad_request", "name kerak")
		return
	}
	if req.Status != "" && req.Status != "active" && req.Status != "inactive" {
		jsonError(w, 400, "bad_request", "status faqat active|inactive")
		return
	}
	if req.WastePercent != nil && (*req.WastePercent < 0 || *req.WastePercent > 90) {
		jsonError(w, 400, "bad_request", "waste_percent 0..90")
		return
	}
	if req.MinQty != nil && *req.MinQty < 0 {
		jsonError(w, 400, "bad_request", "min_qty >= 0")
		return
	}

	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE ingredients SET
			name = $1,
			min_qty = COALESCE($2, min_qty),
			waste_percent = COALESCE($3, waste_percent),
			status = CASE WHEN $4 = '' THEN status ELSE $4 END
		WHERE id = $5 AND status <> 'deleted'`,
		req.Name, req.MinQty, req.WastePercent, req.Status, id)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Ingredient topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"ok": true})
}

// ============ DELETE /api/ingredient/{id} ============

func handleDeleteIngredient(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	if id <= 0 {
		jsonError(w, 400, "bad_request", "id noto'g'ri")
		return
	}

	// Retseptda ishlatilayotgan ingredientni o'chirish tannarxni buzadi — bloklaymiz
	var usedIn int
	db.Pool.QueryRow(r.Context(), `
		SELECT COUNT(*) FROM recipes r, jsonb_array_elements(r.items) it
		WHERE (it->>'ingredient_id')::int = $1`, id).Scan(&usedIn)
	if usedIn > 0 {
		jsonError(w, 409, "in_use", "Bu ingredient retseptlarda ishlatilgan — avval retseptdan olib tashlang")
		return
	}

	tag, err := db.Pool.Exec(r.Context(),
		"UPDATE ingredients SET status = 'deleted' WHERE id = $1 AND status <> 'deleted'", id)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Ingredient topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"ok": true})
}

// ============ POST /api/ingredient/adjust ============

func handleAdjustIngredient(w http.ResponseWriter, r *http.Request) {
	claims := requireAdminRole(w, r)
	if claims == nil {
		return
	}
	var req struct {
		IngredientID int    `json:"ingredient_id"`
		NewCount     int64  `json:"new_count"`
		Comment      string `json:"comment"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.IngredientID <= 0 || req.NewCount < 0 {
		jsonError(w, 400, "bad_request", "ingredient_id va new_count (>=0) kerak")
		return
	}
	if req.NewCount > maxIngredientCount {
		jsonError(w, 400, "bad_request", "new_count juda katta")
		return
	}

	// MUHIM: `delta` AYNAN o'sha tranzaksiya ichida, qator qulflangandan keyin
	// hisoblanadi.
	//
	// Ilgari joriy qoldiq qulfsiz o'qilib, delta tashqarida hisoblanardi va
	// nisbiy harakat sifatida qo'llanardi. Oqibati: admin "9800 gr" deb
	// kiritadi (joriy 10000, delta −200); so'rov timeout bo'lib qayta
	// yuborilsa, ikkinchi marta 9800 dan yana −200 olinib 9600 chiqardi —
	// javonda esa 9800 turardi. Ikki admin bir vaqtda bir xil sanoqni
	// kiritsa ham xuddi shu bo'lardi.
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	var current int64
	if err := tx.QueryRow(r.Context(),
		"SELECT count FROM ingredients WHERE id = $1 AND status <> 'deleted' FOR UPDATE",
		req.IngredientID).Scan(&current); err != nil {
		jsonError(w, 404, "not_found", "Ingredient topilmadi")
		return
	}

	delta := req.NewCount - current
	if delta == 0 {
		jsonResponse(w, 200, map[string]interface{}{"ok": true, "count": current, "changed": false})
		return
	}
	newCount, err := applyIngMoveTx(
		r.Context(), tx, req.IngredientID, delta, "korreksiya", "", req.Comment, claims.Name, true,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	wss.H.BroadcastEvent("ingredient:updated", map[string]interface{}{
		"ingredient_id": req.IngredientID, "count": newCount, "reason": "korreksiya",
	})
	jsonResponse(w, 200, map[string]interface{}{"ok": true, "count": newCount, "changed": true})
}

// maxIngredientCount — ombordagi eng katta mantiqiy qoldiq (10 000 tonna gr/ml
// hisobida). Chegarasiz qiymat keyinchalik retsept hisobida int64 to'lib
// ketishiga olib kelardi.
const maxIngredientCount int64 = 10_000_000_000

// ============ GET /api/ingredient/moves ============

func handleGetIngredientMoves(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	limit := 100
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 1000 {
			limit = n
		}
	}

	q := `SELECT m.id, m.ingredient_id, i.name, i.unit, m.qty, m.reason, m.ref,
	             m.comment, m.created_by, m.created_at
	      FROM ing_moves m JOIN ingredients i ON i.id = m.ingredient_id`
	args := []interface{}{}
	if s := r.URL.Query().Get("ingredient_id"); s != "" {
		ingID, err := strconv.Atoi(s)
		if err != nil || ingID <= 0 {
			jsonError(w, 400, "bad_request", "ingredient_id noto'g'ri")
			return
		}
		q += " WHERE m.ingredient_id = $1 ORDER BY m.id DESC LIMIT $2"
		args = append(args, ingID, limit)
	} else {
		q += " ORDER BY m.id DESC LIMIT $1"
		args = append(args, limit)
	}

	rows, err := db.Pool.Query(r.Context(), q, args...)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	moves := []map[string]interface{}{}
	for rows.Next() {
		var id, ingID int
		var qty int64
		var name, unit, reason, ref, comment, createdBy string
		var createdAt time.Time
		if err := rows.Scan(&id, &ingID, &name, &unit, &qty, &reason, &ref, &comment, &createdBy, &createdAt); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		moves = append(moves, map[string]interface{}{
			"id": id, "ingredient_id": ingID, "name": name, "unit": unit,
			"qty": qty, "reason": reason, "ref": ref, "comment": comment,
			"created_by": createdBy, "created_at": createdAt.UTC().Format(time.RFC3339),
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"moves": moves})
}
