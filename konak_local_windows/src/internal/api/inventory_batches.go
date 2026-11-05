package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

type supplierInput struct {
	Name    string `json:"name"`
	Phone   string `json:"phone"`
	Address string `json:"address"`
	Notes   string `json:"notes"`
	Status  string `json:"status"`
}

func handleGetSuppliers(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), `
		SELECT s.id,s.name,s.phone,s.address,s.notes,s.status,s.created_at,s.updated_at,
		       (SELECT COUNT(*) FROM purchases p
		        WHERE p.supplier_id=s.id AND p.status='active'),
		       (SELECT COALESCE(SUM(p.total),0) FROM purchases p
		        WHERE p.supplier_id=s.id AND p.status='active'),
		       (SELECT COUNT(*) FROM ingredient_batches b
		        WHERE b.supplier_id=s.id AND b.status='active' AND b.remaining_qty>0)
		FROM suppliers s
		WHERE s.status<>'deleted'
		ORDER BY s.name`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()
	items := []map[string]interface{}{}
	for rows.Next() {
		var id int64
		var name, phone, address, notes, status string
		var createdAt, updatedAt time.Time
		var purchaseCount, activeBatches int
		var purchaseTotal int64
		if rows.Scan(
			&id, &name, &phone, &address, &notes, &status, &createdAt,
			&updatedAt, &purchaseCount, &purchaseTotal, &activeBatches,
		) == nil {
			items = append(items, map[string]interface{}{
				"id": id, "name": name, "phone": phone, "address": address,
				"notes": notes, "status": status, "purchase_count": purchaseCount,
				"purchase_total": purchaseTotal, "active_batches": activeBatches,
				"created_at": createdAt.UTC().Format(time.RFC3339),
				"updated_at": updatedAt.UTC().Format(time.RFC3339),
			})
		}
	}
	jsonResponse(w, 200, items)
}

func handleCreateSupplier(w http.ResponseWriter, r *http.Request) {
	var input supplierInput
	if decodeInventoryJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validateSupplier(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	var id int64
	err := db.Pool.QueryRow(r.Context(), `
		INSERT INTO suppliers (name,phone,address,notes,status)
		VALUES ($1,$2,$3,$4,$5) RETURNING id`,
		input.Name, input.Phone, input.Address, input.Notes, input.Status,
	).Scan(&id)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 201, map[string]interface{}{"id": id, "message": "Yetkazib beruvchi qo'shildi"})
}

func handleUpdateSupplier(w http.ResponseWriter, r *http.Request) {
	id, ok := inventoryID(w, r)
	if !ok {
		return
	}
	var input supplierInput
	if decodeInventoryJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validateSupplier(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE suppliers SET name=$1,phone=$2,address=$3,notes=$4,
		       status=$5,updated_at=NOW()
		WHERE id=$6 AND status<>'deleted'`,
		input.Name, input.Phone, input.Address, input.Notes, input.Status, id,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Yetkazib beruvchi topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Yetkazib beruvchi yangilandi"})
}

func handleDeleteSupplier(w http.ResponseWriter, r *http.Request) {
	id, ok := inventoryID(w, r)
	if !ok {
		return
	}
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE suppliers SET status='deleted',updated_at=NOW()
		WHERE id=$1 AND status<>'deleted'`,
		id,
	)
	if err != nil || tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Yetkazib beruvchi topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Yetkazib beruvchi arxivlandi"})
}

type ingredientBatchInput struct {
	IngredientID int64  `json:"ingredient_id"`
	SupplierID   *int64 `json:"supplier_id"`
	BatchCode    string `json:"batch_code"`
	Qty          int64  `json:"qty"`
	TotalCost    int64  `json:"total_cost"`
	Note         string `json:"note"`
}

func handleGetIngredientBatches(w http.ResponseWriter, r *http.Request) {
	ingredientID := boundedQueryInt(r, "ingredient_id", 0, 0, 1_000_000_000)
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	rows, err := db.Pool.Query(r.Context(), `
		SELECT b.id,b.ingredient_id,i.name,i.unit,b.supplier_id,
		       COALESCE(s.name,''),b.batch_code,b.received_qty,b.remaining_qty,
		       b.total_cost,b.received_at,b.status,b.note,b.created_by,
		       b.created_at,b.updated_at
		FROM ingredient_batches b
		JOIN ingredients i ON i.id=b.ingredient_id
		LEFT JOIN suppliers s ON s.id=b.supplier_id
		WHERE b.status<>'deleted'
		  AND ($1=0 OR b.ingredient_id=$1)
		  AND ($2='' OR b.status=$2)
		ORDER BY b.received_at DESC,b.id DESC`,
		ingredientID, status,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()
	items := []map[string]interface{}{}
	for rows.Next() {
		var id, ingredientID int64
		var supplierID *int64
		var ingredientName, unit, supplierName, code, status, note, createdBy string
		var receivedQty, remainingQty, totalCost int64
		var receivedAt, createdAt, updatedAt time.Time
		if rows.Scan(
			&id, &ingredientID, &ingredientName, &unit, &supplierID,
			&supplierName, &code, &receivedQty, &remainingQty, &totalCost,
			&receivedAt, &status, &note, &createdBy, &createdAt, &updatedAt,
		) == nil {
			unitCost := int64(0)
			if receivedQty > 0 {
				unitCost = totalCost / receivedQty
			}
			items = append(items, map[string]interface{}{
				"id": id, "ingredient_id": ingredientID,
				"ingredient_name": ingredientName, "unit": unit,
				"supplier_id": supplierID, "supplier_name": supplierName,
				"batch_code": code, "received_qty": receivedQty,
				"remaining_qty": remainingQty, "total_cost": totalCost,
				"unit_cost":   unitCost,
				"received_at": receivedAt.UTC().Format(time.RFC3339),
				"status":      status, "note": note, "created_by": createdBy,
				"created_at": createdAt.UTC().Format(time.RFC3339),
				"updated_at": updatedAt.UTC().Format(time.RFC3339),
			})
		}
	}

	var activeCount int
	var remainingQty, remainingValue int64
	_ = db.Pool.QueryRow(r.Context(), `
		SELECT COUNT(*),COALESCE(SUM(remaining_qty),0),
		       COALESCE(SUM(
		         CASE WHEN received_qty>0
		           THEN total_cost*remaining_qty/received_qty ELSE 0 END
		       ),0)
		FROM ingredient_batches
		WHERE status='active' AND remaining_qty>0`,
	).Scan(&activeCount, &remainingQty, &remainingValue)
	jsonResponse(w, 200, map[string]interface{}{
		"items": items,
		"summary": map[string]interface{}{
			"active_count": activeCount, "remaining_qty": remainingQty,
			"remaining_value": remainingValue,
		},
	})
}

func handleCreateIngredientBatch(w http.ResponseWriter, r *http.Request) {
	var input ingredientBatchInput
	if decodeInventoryJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	message := validateBatchInput(&input, true)
	if message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	claims := middleware.GetUser(r.Context())
	createdBy := ""
	if claims != nil {
		createdBy = claims.Name
	}
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	var id int64
	err = tx.QueryRow(r.Context(), `
		INSERT INTO ingredient_batches
			(ingredient_id,supplier_id,batch_code,received_qty,remaining_qty,
			 total_cost,note,created_by)
		VALUES ($1,$2,$3,$4,$4,$5,$6,$7)
		RETURNING id`,
		input.IngredientID, input.SupplierID, input.BatchCode, input.Qty,
		input.TotalCost, input.Note, createdBy,
	).Scan(&id)
	if err != nil {
		jsonError(w, 400, "bad_request", "Ingredient yoki yetkazib beruvchi topilmadi")
		return
	}
	newCount, err := applyIngMoveTx(
		r.Context(), tx, int(input.IngredientID), input.Qty, "kirim",
		fmt.Sprintf("partiya #%d", id), input.Note, createdBy, false,
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
		"ingredient_id": input.IngredientID, "count": newCount, "reason": "kirim",
	})
	jsonResponse(w, 201, map[string]interface{}{
		"id": id, "count": newCount, "message": "Partiya qabul qilindi",
	})
}

func handleUpdateIngredientBatch(w http.ResponseWriter, r *http.Request) {
	id, ok := inventoryID(w, r)
	if !ok {
		return
	}
	var input ingredientBatchInput
	if decodeInventoryJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	message := validateBatchInput(&input, false)
	if message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE ingredient_batches SET
			supplier_id=$1,batch_code=$2,note=$3,updated_at=NOW()
		WHERE id=$4 AND status<>'deleted'`,
		input.SupplierID, input.BatchCode, input.Note, id,
	)
	if err != nil {
		jsonError(w, 400, "bad_request", "Partiya saqlanmadi")
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Partiya topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Partiya yangilandi"})
}

func handleWriteOffIngredientBatch(w http.ResponseWriter, r *http.Request) {
	id, ok := inventoryID(w, r)
	if !ok {
		return
	}
	var req struct {
		Note string `json:"note"`
	}
	if decodeInventoryJSON(w, r, &req) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	claims := middleware.GetUser(r.Context())
	createdBy := ""
	if claims != nil {
		createdBy = claims.Name
	}
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	var ingredientID int
	if err := tx.QueryRow(r.Context(), `
		SELECT ingredient_id
		FROM ingredient_batches
		WHERE id=$1 AND status='active'`,
		id,
	).Scan(&ingredientID); err != nil {
		jsonError(w, 409, "empty_batch", "Partiyada qoldiq yo'q")
		return
	}
	var current int64
	if err := tx.QueryRow(r.Context(), `
		SELECT count FROM ingredients WHERE id=$1 FOR UPDATE`,
		ingredientID,
	).Scan(&current); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	var qty int64
	if err := tx.QueryRow(r.Context(), `
		SELECT remaining_qty
		FROM ingredient_batches
		WHERE id=$1 AND status='active'
		FOR UPDATE`,
		id,
	).Scan(&qty); err != nil || qty <= 0 {
		jsonError(w, 409, "empty_batch", "Partiyada qoldiq yo'q")
		return
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE ingredient_batches SET
			remaining_qty=0,status='written_off',note=$1,updated_at=NOW()
		WHERE id=$2`,
		strings.TrimSpace(req.Note), id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	ref := fmt.Sprintf("partiya #%d", id)
	newCount, err := applyIngMoveTx(
		r.Context(), tx, ingredientID, -qty, "partiya_spisaniya",
		ref, req.Note, createdBy, false,
	)
	if err != nil {
		jsonError(w, 409, "stock_mismatch", err.Error())
		return
	}
	if _, err := tx.Exec(r.Context(), `
		INSERT INTO ing_batch_moves
			(batch_id,ingredient_id,qty,reason,ref)
		VALUES ($1,$2,$3,'partiya_spisaniya',$4)`,
		id, ingredientID, -qty, ref,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	wss.H.BroadcastEvent("ingredient:updated", map[string]interface{}{
		"ingredient_id": ingredientID, "count": newCount,
		"reason": "partiya_spisaniya",
	})
	jsonResponse(w, 200, map[string]interface{}{
		"message": "Partiya hisobdan chiqarildi", "written_off_qty": qty,
	})
}

func handleDeleteIngredientBatch(w http.ResponseWriter, r *http.Request) {
	id, ok := inventoryID(w, r)
	if !ok {
		return
	}
	claims := middleware.GetUser(r.Context())
	createdBy := ""
	if claims != nil {
		createdBy = claims.Name
	}
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	var ingredientID int
	if err := tx.QueryRow(r.Context(), `
		SELECT ingredient_id
		FROM ingredient_batches
		WHERE id=$1 AND status='active'`,
		id,
	).Scan(&ingredientID); err != nil {
		jsonError(w, 404, "not_found", "Partiya topilmadi")
		return
	}
	var current int64
	if err := tx.QueryRow(r.Context(), `
		SELECT count FROM ingredients WHERE id=$1 FOR UPDATE`,
		ingredientID,
	).Scan(&current); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	var receivedQty, remainingQty int64
	if err := tx.QueryRow(r.Context(), `
		SELECT received_qty,remaining_qty
		FROM ingredient_batches
		WHERE id=$1 AND status='active'
		FOR UPDATE`,
		id,
	).Scan(&receivedQty, &remainingQty); err != nil {
		jsonError(w, 404, "not_found", "Partiya topilmadi")
		return
	}
	if receivedQty != remainingQty {
		jsonError(w, 409, "batch_in_use", "Ishlatilgan partiyani o'chirib bo'lmaydi")
		return
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE ingredient_batches SET
			remaining_qty=0,status='deleted',updated_at=NOW()
		WHERE id=$1`,
		id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	ref := fmt.Sprintf("partiya #%d", id)
	newCount, err := applyIngMoveTx(
		r.Context(), tx, ingredientID, -remainingQty, "partiya_bekor",
		ref, "Partiya bekor qilindi", createdBy, false,
	)
	if err != nil {
		jsonError(w, 409, "stock_mismatch", err.Error())
		return
	}
	if _, err := tx.Exec(r.Context(), `
		INSERT INTO ing_batch_moves
			(batch_id,ingredient_id,qty,reason,ref)
		VALUES ($1,$2,$3,'partiya_bekor',$4)`,
		id, ingredientID, -remainingQty, ref,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	wss.H.BroadcastEvent("ingredient:updated", map[string]interface{}{
		"ingredient_id": ingredientID, "count": newCount,
		"reason": "partiya_bekor",
	})
	jsonResponse(w, 200, map[string]interface{}{"message": "Partiya bekor qilindi"})
}

func validateSupplier(input *supplierInput) string {
	input.Name = strings.TrimSpace(input.Name)
	input.Phone = strings.TrimSpace(input.Phone)
	input.Address = strings.TrimSpace(input.Address)
	input.Notes = strings.TrimSpace(input.Notes)
	input.Status = strings.ToLower(strings.TrimSpace(input.Status))
	if input.Status == "" {
		input.Status = "active"
	}
	if input.Name == "" || len(input.Name) > 160 {
		return "Nomi 1..160 ta belgi bo'lishi kerak"
	}
	if len(input.Phone) > 40 || len(input.Address) > 500 || len(input.Notes) > 2000 {
		return "Matn juda uzun"
	}
	if input.Status != "active" && input.Status != "inactive" {
		return "Status active yoki inactive bo'lishi kerak"
	}
	return ""
}

func validateBatchInput(input *ingredientBatchInput, requireQty bool) string {
	input.BatchCode = strings.TrimSpace(input.BatchCode)
	input.Note = strings.TrimSpace(input.Note)
	if requireQty && (input.IngredientID <= 0 || input.Qty <= 0) {
		return "Ingredient va musbat miqdor kerak"
	}
	if input.TotalCost < 0 || len(input.BatchCode) > 80 || len(input.Note) > 1000 {
		return "Partiya qiymati noto'g'ri"
	}
	if input.SupplierID != nil && *input.SupplierID <= 0 {
		return "Yetkazib beruvchi ID noto'g'ri"
	}
	return ""
}

func decodeInventoryJSON(w http.ResponseWriter, r *http.Request, target interface{}) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func inventoryID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "ID noto'g'ri")
		return 0, false
	}
	return id, true
}
