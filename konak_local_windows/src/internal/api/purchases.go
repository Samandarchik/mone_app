package api

// Bozor xaridi — 2-bosqich (super admin buyurtmasiz "oldim" deb kiritadi):
//   GET  /api/bozor/list       — nimalar olish kerak (min_qty dan kam qolganlar)
//   POST /api/purchase         — xarid: ombor kirim + narx manbai + avto-xarajat
//   GET  /api/purchases        — xarid tarixi (items bilan)
//   DELETE /api/purchase/{id}  — xaridni bekor qilish (hammasi qaytadi)
//
// Xarid puli "Bozor" xarajat kategoriyasiga avto-yoziladi (S6 qarori) —
// smena/kunlik moliya hisobotida ko'rinadi.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/db"
	"konak-local/internal/wss"
)

// bozorExpenseCategoryID — "Bozor" xarajat kategoriyasi id sini topadi,
// bo'lmasa yaratadi.
func bozorExpenseCategoryID(ctx context.Context) (int, error) {
	var id int
	err := db.Pool.QueryRow(ctx,
		"SELECT id FROM expense_categories WHERE LOWER(name_uz) = 'bozor' AND status = 'active' LIMIT 1").Scan(&id)
	if err == nil {
		return id, nil
	}
	err = db.Pool.QueryRow(ctx,
		"INSERT INTO expense_categories (name_uz, name_ru, name_tr, sort_order) VALUES ('Bozor', 'Базар', 'Pazar', 99) RETURNING id").Scan(&id)
	return id, err
}

// ============ GET /api/bozor/list ============

func handleBozorList(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	rows, err := db.Pool.Query(r.Context(), `
		SELECT id, name, unit, count, min_qty
		FROM ingredients
		WHERE status = 'active' AND min_qty > 0 AND count < min_qty
		ORDER BY name`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var count, minQty int64
		var name, unit string
		if err := rows.Scan(&id, &name, &unit, &count, &minQty); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		items = append(items, map[string]interface{}{
			"ingredient_id": id, "name": name, "unit": unit,
			"count": count, "min_qty": minQty, "deficit": minQty - count,
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"items": items})
}

// ============ POST /api/purchase ============

func handleCreatePurchase(w http.ResponseWriter, r *http.Request) {
	claims := requireAdminRole(w, r)
	if claims == nil {
		return
	}
	var req struct {
		Note       string `json:"note"`
		SupplierID *int64 `json:"supplier_id"`
		Items      []struct {
			IngredientID int    `json:"ingredient_id"`
			Qty          int64  `json:"qty"`
			Subtotal     int64  `json:"subtotal"`
			BatchCode    string `json:"batch_code"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if len(req.Items) == 0 {
		jsonError(w, 400, "bad_request", "Kamida 1 ta item kerak")
		return
	}
	if req.SupplierID != nil {
		var exists bool
		_ = db.Pool.QueryRow(r.Context(), `
			SELECT EXISTS(
				SELECT 1 FROM suppliers WHERE id=$1 AND status='active'
			)`,
			*req.SupplierID,
		).Scan(&exists)
		if !exists {
			jsonError(w, 400, "bad_request", "Yetkazib beruvchi topilmadi")
			return
		}
	}
	var total int64
	for index := range req.Items {
		it := &req.Items[index]
		it.BatchCode = strings.TrimSpace(it.BatchCode)
		if it.IngredientID <= 0 || it.Qty <= 0 || it.Subtotal < 0 {
			jsonError(w, 400, "bad_request", "har itemda ingredient_id, qty (>0), subtotal (>=0) kerak")
			return
		}
		if len(it.BatchCode) > 80 {
			jsonError(w, 400, "bad_request", "Partiya kodi juda uzun")
			return
		}
		var st string
		if err := db.Pool.QueryRow(r.Context(),
			"SELECT status FROM ingredients WHERE id = $1", it.IngredientID).Scan(&st); err != nil || st == "deleted" {
			jsonError(w, 400, "bad_request", fmt.Sprintf("Ingredient %d topilmadi", it.IngredientID))
			return
		}
		total += it.Subtotal
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	// Xarid, partiyalar va ombor kirimi bitta tranzaksiyada.
	var purchaseID int
	if err := tx.QueryRow(r.Context(), `
		INSERT INTO purchases (note,total,created_by,supplier_id)
		VALUES ($1,$2,$3,$4) RETURNING id`,
		req.Note, total, claims.Name, req.SupplierID,
	).Scan(&purchaseID); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	ref := fmt.Sprintf("xarid #%d", purchaseID)

	stockUpdates := []map[string]interface{}{}
	for _, it := range req.Items {
		var purchaseItemID int
		if err := tx.QueryRow(r.Context(), `
			INSERT INTO purchase_items (purchase_id,ingredient_id,qty,subtotal)
			VALUES ($1,$2,$3,$4) RETURNING id`,
			purchaseID, it.IngredientID, it.Qty, it.Subtotal,
		).Scan(&purchaseItemID); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		var batchID int64
		if err := tx.QueryRow(r.Context(), `
			INSERT INTO ingredient_batches
				(ingredient_id,supplier_id,purchase_item_id,batch_code,
				 received_qty,remaining_qty,total_cost,created_by)
			VALUES ($1,$2,$3,$4,$5,$5,$6,$7)
			RETURNING id`,
			it.IngredientID, req.SupplierID, purchaseItemID, it.BatchCode,
			it.Qty, it.Subtotal, claims.Name,
		).Scan(&batchID); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		newCount, err := applyIngMoveTx(
			r.Context(), tx, it.IngredientID, it.Qty, "kirim", ref,
			fmt.Sprintf("partiya #%d", batchID), claims.Name, false,
		)
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		stockUpdates = append(stockUpdates, map[string]interface{}{
			"ingredient_id": it.IngredientID, "count": newCount,
			"reason": "kirim",
		})
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	for _, update := range stockUpdates {
		wss.H.BroadcastEvent("ingredient:updated", update)
	}

	// Avto-xarajat ("Bozor" kategoriyasi) — moliya hisobotlarida ko'rinadi.
	if total > 0 {
		if catID, err := bozorExpenseCategoryID(r.Context()); err == nil {
			desc := "Bozor xaridi #" + strconv.Itoa(purchaseID)
			if req.Note != "" {
				desc += " — " + req.Note
			}
			createdBy, _ := json.Marshal(map[string]interface{}{
				"user_id": claims.UserID, "name": claims.Name, "role": claims.Role,
			})
			var expID int
			if err := db.Pool.QueryRow(r.Context(),
				"INSERT INTO expenses (category_id, amount, description, date, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id",
				catID, total, desc, time.Now().Format("2006-01-02"), string(createdBy)).Scan(&expID); err == nil {
				db.Pool.Exec(r.Context(), "UPDATE purchases SET expense_id = $1 WHERE id = $2", expID, purchaseID)
			}
		}
	}

	jsonResponse(w, 200, map[string]interface{}{
		"ok": true, "id": purchaseID, "total": total, "items": len(req.Items),
	})
}

// ============ GET /api/purchases ============

func handleGetPurchases(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	limit := 50
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	rows, err := db.Pool.Query(r.Context(), `
		SELECT p.id,p.note,p.total,p.created_by,p.created_at,p.supplier_id,
		       COALESCE(s.name,'')
		FROM purchases p
		LEFT JOIN suppliers s ON s.id=p.supplier_id
		WHERE p.status='active'
		ORDER BY p.id DESC LIMIT $1`,
		limit,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	purchases := []map[string]interface{}{}
	ids := []int{}
	for rows.Next() {
		var id int
		var total int64
		var supplierID *int64
		var note, createdBy, supplierName string
		var createdAt time.Time
		if err := rows.Scan(
			&id, &note, &total, &createdBy, &createdAt, &supplierID,
			&supplierName,
		); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		ids = append(ids, id)
		purchases = append(purchases, map[string]interface{}{
			"id": id, "note": note, "total": total, "created_by": createdBy,
			"created_at":  createdAt.UTC().Format(time.RFC3339),
			"supplier_id": supplierID, "supplier_name": supplierName,
			"items": []map[string]interface{}{},
		})
	}
	rows.Close()

	if len(ids) > 0 {
		itemRows, err := db.Pool.Query(r.Context(), `
			SELECT pi.purchase_id,pi.ingredient_id,i.name,i.unit,pi.qty,pi.subtotal,
			       b.id,COALESCE(b.batch_code,''),b.remaining_qty,b.status
			FROM purchase_items pi
			JOIN ingredients i ON i.id=pi.ingredient_id
			LEFT JOIN ingredient_batches b ON b.purchase_item_id=pi.id
			WHERE pi.purchase_id = ANY($1) ORDER BY pi.id`, ids)
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		defer itemRows.Close()

		byPurchase := map[int][]map[string]interface{}{}
		for itemRows.Next() {
			var pid, ingID int
			var batchID *int64
			var qty, subtotal int64
			var remainingQty *int64
			var name, unit, batchCode string
			var batchStatus *string
			if err := itemRows.Scan(
				&pid, &ingID, &name, &unit, &qty, &subtotal, &batchID,
				&batchCode, &remainingQty, &batchStatus,
			); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
			byPurchase[pid] = append(byPurchase[pid], map[string]interface{}{
				"ingredient_id": ingID, "name": name, "unit": unit,
				"qty": qty, "subtotal": subtotal, "batch_id": batchID,
				"batch_code":    batchCode,
				"remaining_qty": remainingQty, "batch_status": batchStatus,
			})
		}
		for _, p := range purchases {
			if items, ok := byPurchase[p["id"].(int)]; ok {
				p["items"] = items
			}
		}
	}

	jsonResponse(w, 200, map[string]interface{}{"purchases": purchases})
}

// ============ DELETE /api/purchase/{id} ============

func handleDeletePurchase(w http.ResponseWriter, r *http.Request) {
	claims := requireAdminRole(w, r)
	if claims == nil {
		return
	}
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	if id <= 0 {
		jsonError(w, 400, "bad_request", "id noto'g'ri")
		return
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	var expenseID *int
	if err := tx.QueryRow(r.Context(), `
		SELECT expense_id FROM purchases
		WHERE id=$1 AND status='active' FOR UPDATE`,
		id,
	).Scan(&expenseID); err != nil {
		jsonError(w, 404, "not_found", "Xarid topilmadi")
		return
	}

	rows, err := tx.Query(r.Context(), `
		SELECT pi.ingredient_id,pi.qty,b.id,b.received_qty,b.remaining_qty
		FROM purchase_items pi
		LEFT JOIN ingredient_batches b ON b.purchase_item_id=pi.id
		WHERE pi.purchase_id=$1`,
		id,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	type pi struct {
		ingID     int
		qty       int64
		batchID   *int64
		received  *int64
		remaining *int64
	}
	items := []pi{}
	for rows.Next() {
		var it pi
		if err := rows.Scan(
			&it.ingID, &it.qty, &it.batchID, &it.received, &it.remaining,
		); err != nil {
			rows.Close()
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		items = append(items, it)
	}
	rows.Close()

	ingredientIDs := make([]int, 0, len(items))
	seenIngredients := map[int]bool{}
	for _, item := range items {
		if !seenIngredients[item.ingID] {
			seenIngredients[item.ingID] = true
			ingredientIDs = append(ingredientIDs, item.ingID)
		}
	}
	sort.Ints(ingredientIDs)
	for _, ingredientID := range ingredientIDs {
		var current int64
		if err := tx.QueryRow(r.Context(), `
			SELECT count FROM ingredients WHERE id=$1 FOR UPDATE`,
			ingredientID,
		).Scan(&current); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}
	for index := range items {
		item := &items[index]
		if item.batchID == nil {
			continue
		}
		var received, remaining int64
		if err := tx.QueryRow(r.Context(), `
			SELECT received_qty,remaining_qty
			FROM ingredient_batches
			WHERE id=$1 AND status='active'
			FOR UPDATE`,
			*item.batchID,
		).Scan(&received, &remaining); err != nil || received != remaining {
			jsonError(w, 409, "purchase_in_use",
				"Partiyasi ishlatilgan xaridni bekor qilib bo'lmaydi")
			return
		}
		item.received = &received
		item.remaining = &remaining
	}

	comment := fmt.Sprintf("Xarid #%d bekor qilindi", id)
	ref := fmt.Sprintf("xarid #%d", id)
	stockUpdates := []map[string]interface{}{}
	for _, it := range items {
		if it.batchID != nil {
			if _, err := tx.Exec(r.Context(), `
				UPDATE ingredient_batches SET
					remaining_qty=0,status='returned',updated_at=NOW()
				WHERE id=$1`,
				*it.batchID,
			); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
			if _, err := tx.Exec(r.Context(), `
				INSERT INTO ing_batch_moves
					(batch_id,ingredient_id,qty,reason,ref)
				VALUES ($1,$2,$3,'xarid_bekor',$4)`,
				*it.batchID, it.ingID, -it.qty, ref,
			); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
		}
		newCount, err := applyIngMoveTx(
			r.Context(), tx, it.ingID, -it.qty, "xarid_bekor",
			ref, comment, claims.Name, false,
		)
		if err != nil {
			jsonError(w, 409, "stock_mismatch", err.Error())
			return
		}
		stockUpdates = append(stockUpdates, map[string]interface{}{
			"ingredient_id": it.ingID, "count": newCount,
			"reason": "xarid_bekor",
		})
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE purchases SET status='cancelled' WHERE id=$1`,
		id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	if expenseID != nil {
		_, _ = db.Pool.Exec(r.Context(), "DELETE FROM expenses WHERE id=$1", *expenseID)
	}
	for _, update := range stockUpdates {
		wss.H.BroadcastEvent("ingredient:updated", update)
	}
	jsonResponse(w, 200, map[string]interface{}{"ok": true, "reversed_items": len(items)})
}
