package api

// Pishirish oqimi — 4-bosqich (S3 qarori: ingredient PISHIRISHDA kamayadi):
//   GET  /api/cooking/needed     — limitdan kam qolganlar ("2 ta pishirish kerak")
//   POST /api/cooking/start      — "X ta pishirilayapti": masalliqlar retsept
//                                  bo'yicha KAMAYADI (qty/batch_qty ga masshtablanadi)
//   POST /api/cooking/{id}/done  — "Tayyor": mahsulot bazaga +qty (POS sotadi)
//   POST /api/cooking/{id}/cancel— bekor: masalliqlar qaytadi
//   GET  /api/cookings           — jarayondagilar + tarix
//   POST /api/stock/limit        — mahsulot limiti (kam qolsa ro'yxatga tushadi)
//
// Ruxsat: kitchen + admin + super_admin (pishiradigan joy alohida bo'ladi).
// Sotuv esa avvalgidek faqat TAYYOR mahsulot sonini (stocks) kamaytiradi.

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

// requireCookingRole — kitchen/admin/super_admin. Bo'lmasa javob yozib nil.
func requireCookingRole(w http.ResponseWriter, r *http.Request) *middleware.TokenClaims {
	claims := middleware.GetUser(r.Context())
	if claims == nil || (claims.Role != "super_admin" && claims.Role != "admin" && claims.Role != "kitchen") {
		jsonError(w, 403, "forbidden", "Faqat oshxona/admin")
		return nil
	}
	return claims
}

// cookingJSON — bitta pishirish yozuvining javob shakli.
func cookingJSON(id, productID int, productName string, qty int, status string,
	ingredients json.RawMessage, createdBy string, createdAt time.Time, doneAt *time.Time) map[string]interface{} {
	m := map[string]interface{}{
		"id": id, "product_id": productID, "product_name": productName,
		"qty": qty, "status": status, "ingredients": ingredients,
		"created_by": createdBy, "created_at": createdAt.UTC().Format(time.RFC3339),
	}
	if doneAt != nil {
		m["done_at"] = doneAt.UTC().Format(time.RFC3339)
	}
	return m
}

// ============ GET /api/cooking/needed ============

func handleCookingNeeded(w http.ResponseWriter, r *http.Request) {
	if requireCookingRole(w, r) == nil {
		return
	}
	rows, err := db.Pool.Query(r.Context(), `
		SELECT s.product_id, COALESCE(p.name_uz, ''), s.count, s.limit_qty,
		       COALESCE(rc.batch_qty, 0)
		FROM stocks s
		JOIN products p ON p.id = s.product_id AND p.status = 'active'
		                AND COALESCE(p.product_type,'cooked') = 'cooked'
		LEFT JOIN recipes rc ON rc.product_id = s.product_id
		WHERE s.limit_qty > 0 AND s.count < s.limit_qty
		ORDER BY (s.limit_qty - s.count) DESC`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var productID, count, limitQty, batchQty int
		var name string
		if err := rows.Scan(&productID, &name, &count, &limitQty, &batchQty); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		items = append(items, map[string]interface{}{
			"product_id": productID, "name": name, "count": count,
			"limit_qty": limitQty, "deficit": limitQty - count,
			"batch_qty": batchQty, "has_recipe": batchQty > 0,
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"items": items})
}

// ============ POST /api/cooking/start ============

func handleCookingStart(w http.ResponseWriter, r *http.Request) {
	claims := requireCookingRole(w, r)
	if claims == nil {
		return
	}
	var req struct {
		ProductID int `json:"product_id"`
		Qty       int `json:"qty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.ProductID <= 0 || req.Qty <= 0 {
		jsonError(w, 400, "bad_request", "product_id va qty (>0) kerak")
		return
	}

	var productName, productType string
	if err := db.Pool.QueryRow(r.Context(),
		"SELECT name_uz, COALESCE(product_type,'cooked') FROM products WHERE id = $1 AND status = 'active'",
		req.ProductID).Scan(&productName, &productType); err != nil {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi")
		return
	}
	// "Tayyor keladi" mahsulot pishirilmaydi — u faqat kirim bilan keladi
	if productType == "ready" {
		jsonError(w, 400, "ready_product",
			"Bu mahsulot \"Tayyor keladi\" turida — pishirilmaydi, kirim qilinadi")
		return
	}

	batchQty, recipeItems, found := loadRecipe(r.Context(), req.ProductID)
	if !found || len(recipeItems) == 0 {
		jsonError(w, 400, "no_recipe", "Bu mahsulotga retsept kiritilmagan")
		return
	}

	// Retsept miqdorlari partiya (batch_qty) uchun — so'ralgan qty ga
	// masshtablab, waste bilan oshiramiz (ombordan tozalanmagani olinadi).
	// Nisbatlar xotirada float, ombordan BUTUN son kamayadi (S8).
	// Xatoni YUTIB YUBORISH mumkin emas: `prices` bo'sh qolsa waste_percent
	// hammaga 0 bo'lib, oshxona toza (net) miqdorni oladi. Amalda oshxona
	// tozalanmagan (gross) miqdorni olgani uchun har pishirishda ayirma
	// hisobdan jimgina yo'qolardi (5000gr o'rniga 6250gr olinadi, kitobda
	// esa 5000gr yoziladi).
	prices, err := loadIngPriceInfo(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", "Ingredient ma'lumotini o'qib bo'lmadi: "+err.Error())
		return
	}
	type deduct struct {
		IngredientID int    `json:"ingredient_id"`
		Name         string `json:"name"`
		Unit         string `json:"unit"`
		Amount       int64  `json:"amount"`
	}
	// Retsept qismlarga bo'lingan bo'lishi mumkin ("Biskvit", "Krem") va
	// bitta masalliq bir necha qismda turadi — chiqim masalliq bo'yicha
	// BITTA bo'lishi uchun avval toza miqdorlar qo'shiladi (izoh:
	// `mergeRecipeParts`).
	deducts := []deduct{}
	for _, it := range mergeRecipeParts(recipeItems) {
		// Yaxlitlash BIR MARTA — oxirida. Ilgari avval masshtab, keyin waste
		// alohida yaxlitlanardi va har pishirishda ikki barobar chetlanish
		// to'planardi.
		waste := 0
		if info, ok := prices[it.IngredientID]; ok {
			waste = info.WastePercent
		}
		gross := grossAmountScaled(it.Amount, req.Qty, batchQty, waste)
		if gross <= 0 {
			// Retsept miqdori shu partiya uchun 1 birlikdan kam chiqdi
			// (masalan 10 taga 4gr za'faron → 1 ta uchun 0.4gr). Jimgina
			// tashlab ketilsa ingredient hech qachon hisobdan chiqmasdi;
			// endi kamida 1 birlik olinadi.
			gross = 1
		}
		deducts = append(deducts, deduct{
			IngredientID: it.IngredientID, Name: it.Name, Unit: it.Unit, Amount: gross,
		})
	}
	if len(deducts) == 0 {
		jsonError(w, 400, "no_recipe", "Retsept miqdorlari bo'sh")
		return
	}
	sort.Slice(deducts, func(i, j int) bool {
		return deducts[i].IngredientID < deducts[j].IngredientID
	})

	// Pishirish yozuvi va barcha FIFO chiqimlar bitta tranzaksiyada.
	ingJSON, _ := json.Marshal(deducts)
	var cookingID int
	now := time.Now()
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	if err := tx.QueryRow(r.Context(),
		"INSERT INTO cookings (product_id, product_name, qty, status, ingredients, created_by) VALUES ($1, $2, $3, 'cooking', $4, $5) RETURNING id",
		req.ProductID, productName, req.Qty, string(ingJSON), claims.Name).Scan(&cookingID); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	ref := fmt.Sprintf("pishirish #%d", cookingID)
	stockUpdates := []map[string]interface{}{}
	for _, d := range deducts {
		newCount, err := applyIngMoveTx(
			r.Context(), tx, d.IngredientID, -d.Amount, "pishirish",
			ref, productName, claims.Name, true,
		)
		if errors.Is(err, errInsufficientIngredientStock) {
			jsonError(w, 409, "insufficient_stock",
				fmt.Sprintf("%s: qoldiq yetarli emas", d.Name))
			return
		}
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		stockUpdates = append(stockUpdates, map[string]interface{}{
			"ingredient_id": d.IngredientID, "count": newCount,
			"reason": "pishirish",
		})
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	for _, update := range stockUpdates {
		wss.H.BroadcastEvent("ingredient:updated", update)
	}

	resp := cookingJSON(cookingID, req.ProductID, productName, req.Qty, "cooking", ingJSON, claims.Name, now, nil)
	wss.H.BroadcastEvent("cooking:updated", resp)
	jsonResponse(w, 200, resp)
}

// ============ POST /api/cooking/{id}/done ============

func handleCookingDone(w http.ResponseWriter, r *http.Request) {
	claims := requireCookingRole(w, r)
	if claims == nil {
		return
	}
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))

	var productID, qty int
	var productName, status string
	var ingJSON []byte
	var createdBy string
	var createdAt time.Time
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	err = tx.QueryRow(r.Context(),
		"SELECT product_id, product_name, qty, status, ingredients, created_by, created_at FROM cookings WHERE id = $1 FOR UPDATE",
		id).Scan(&productID, &productName, &qty, &status, &ingJSON, &createdBy, &createdAt)
	if err != nil {
		jsonError(w, 404, "not_found", "Pishirish topilmadi")
		return
	}
	if status != "cooking" {
		jsonError(w, 409, "wrong_status", "Bu pishirish allaqachon yakunlangan")
		return
	}

	now := time.Now()
	if _, err := tx.Exec(r.Context(),
		"UPDATE cookings SET status='done',done_at=NOW() WHERE id=$1",
		id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	// Tayyor mahsulot bazaga qo'shiladi — POS shu zahoti sota oladi.
	// Qator yo'q bo'lsa yaratiladi (mahsulot shu bilan kuzatuvga kiradi).
	var newCount int
	if err := tx.QueryRow(r.Context(), `
		INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, NOW())
		ON CONFLICT (product_id) DO UPDATE SET count = stocks.count + $2, updated_at = NOW()
		RETURNING count`, productID, qty).Scan(&newCount); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	wss.BroadcastStock(productID, &newCount, "cooked")
	resp := cookingJSON(id, productID, productName, qty, "done", ingJSON, createdBy, createdAt, &now)
	resp["done_by"] = claims.Name
	resp["new_count"] = newCount
	wss.H.BroadcastEvent("cooking:updated", resp)
	jsonResponse(w, 200, resp)
}

// ============ POST /api/cooking/{id}/cancel ============

func handleCookingCancel(w http.ResponseWriter, r *http.Request) {
	claims := requireCookingRole(w, r)
	if claims == nil {
		return
	}
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))

	var productID, qty int
	var productName, status string
	var ingJSON []byte
	var createdBy string
	var createdAt time.Time
	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	err = tx.QueryRow(r.Context(),
		"SELECT product_id, product_name, qty, status, ingredients, created_by, created_at FROM cookings WHERE id = $1 FOR UPDATE",
		id).Scan(&productID, &productName, &qty, &status, &ingJSON, &createdBy, &createdAt)
	if err != nil {
		jsonError(w, 404, "not_found", "Pishirish topilmadi")
		return
	}
	if status != "cooking" {
		jsonError(w, 409, "wrong_status", "Faqat jarayondagi pishirishni bekor qilib bo'ladi")
		return
	}

	// Snapshot bo'yicha masalliqlarni qaytarish
	var deducts []struct {
		IngredientID int   `json:"ingredient_id"`
		Amount       int64 `json:"amount"`
	}
	json.Unmarshal(ingJSON, &deducts)
	ref := fmt.Sprintf("pishirish #%d", id)
	stockUpdates := []map[string]interface{}{}
	for _, d := range deducts {
		newCount, err := applyIngMoveTx(
			r.Context(), tx, d.IngredientID, d.Amount, "qaytarildi",
			ref, "bekor qilindi", claims.Name, true,
		)
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		stockUpdates = append(stockUpdates, map[string]interface{}{
			"ingredient_id": d.IngredientID, "count": newCount,
			"reason": "qaytarildi",
		})
	}

	if _, err := tx.Exec(r.Context(),
		"UPDATE cookings SET status='cancelled',done_at=NOW() WHERE id=$1",
		id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	for _, update := range stockUpdates {
		wss.H.BroadcastEvent("ingredient:updated", update)
	}

	now := time.Now()
	resp := cookingJSON(id, productID, productName, qty, "cancelled", ingJSON, createdBy, createdAt, &now)
	wss.H.BroadcastEvent("cooking:updated", resp)
	jsonResponse(w, 200, resp)
}

// ============ GET /api/cookings ============

func handleGetCookings(w http.ResponseWriter, r *http.Request) {
	if requireCookingRole(w, r) == nil {
		return
	}
	limit := 50
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}

	q := `SELECT id, product_id, product_name, qty, status, ingredients, created_by, created_at, done_at
	      FROM cookings`
	args := []interface{}{}
	if st := r.URL.Query().Get("status"); st != "" {
		q += " WHERE status = $1 ORDER BY id DESC LIMIT $2"
		args = append(args, st, limit)
	} else {
		q += " ORDER BY id DESC LIMIT $1"
		args = append(args, limit)
	}

	rows, err := db.Pool.Query(r.Context(), q, args...)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	cookings := []map[string]interface{}{}
	for rows.Next() {
		var id, productID, qty int
		var productName, status, createdBy string
		var ingJSON []byte
		var createdAt time.Time
		var doneAt *time.Time
		if err := rows.Scan(&id, &productID, &productName, &qty, &status, &ingJSON, &createdBy, &createdAt, &doneAt); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		cookings = append(cookings, cookingJSON(id, productID, productName, qty, status, ingJSON, createdBy, createdAt, doneAt))
	}
	jsonResponse(w, 200, map[string]interface{}{"cookings": cookings})
}

// ============ POST /api/stock/add ============

// handleStockAdd — "Tayyor keladi" mahsulot kirimi: kelgan sonini bazaga
// QO'SHADI (absolute emas). Mahsulot shu bilan sotuvga chiqadi.
func handleStockAdd(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	var req struct {
		ProductID int `json:"product_id"`
		Qty       int `json:"qty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.ProductID <= 0 || req.Qty <= 0 || req.Qty > maxStockArrivalQty {
		jsonError(w, 400, "bad_request",
			fmt.Sprintf("product_id va qty (1..%d) kerak", maxStockArrivalQty))
		return
	}

	// `stocks` da products'ga tashqi kalit yo'q — mavjudligini o'zimiz
	// tekshiramiz, aks holda mavjud bo'lmagan ID bilan "yetim" qoldiq qatori
	// tug'ilardi va u hech qayerda ko'rinmasdi.
	//
	// Tur tekshiruvi ham SHART: bu endpoint faqat "tayyor keladi" mahsulot
	// uchun. Retseptli (cooked) mahsulotga kirim qilinsa, tayyor mahsulot
	// masalliq chiqimisiz sotuvga chiqib, tannarx hisobi butunlay chetlab
	// o'tilardi. `handleCookingStart` teskari tomonni allaqachon bloklaydi.
	var productType string
	if err := db.Pool.QueryRow(r.Context(),
		"SELECT COALESCE(product_type,'cooked') FROM products WHERE id = $1 AND status = 'active'",
		req.ProductID).Scan(&productType); err != nil {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi yoki faol emas")
		return
	}
	if productType != "ready" {
		jsonError(w, 400, "cooked_product",
			"Bu mahsulot retseptli — kirim qilinmaydi, pishiriladi")
		return
	}

	var newCount int
	err := db.Pool.QueryRow(r.Context(), `
		INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, NOW())
		ON CONFLICT (product_id) DO UPDATE SET count = stocks.count + $2, updated_at = NOW()
		RETURNING count`, req.ProductID, req.Qty).Scan(&newCount)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	wss.BroadcastStock(req.ProductID, &newCount, "arrival")
	jsonResponse(w, 200, map[string]interface{}{"ok": true, "product_id": req.ProductID, "count": newCount})
}

// ============ POST /api/stock/limit ============

func handleStockLimit(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	var req struct {
		ProductID int `json:"product_id"`
		LimitQty  int `json:"limit_qty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.ProductID <= 0 || req.LimitQty < 0 || req.LimitQty > maxStockArrivalQty {
		jsonError(w, 400, "bad_request",
			fmt.Sprintf("product_id va limit_qty (0..%d) kerak", maxStockArrivalQty))
		return
	}
	var exists bool
	if db.Pool.QueryRow(r.Context(),
		"SELECT EXISTS(SELECT 1 FROM products WHERE id = $1 AND status <> 'deleted')",
		req.ProductID).Scan(&exists) != nil || !exists {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi")
		return
	}

	// Qator yo'q bo'lsa count=0 bilan yaratiladi (mahsulot kuzatuvga kiradi)
	if _, err := db.Pool.Exec(r.Context(), `
		INSERT INTO stocks (product_id, count, limit_qty, updated_at) VALUES ($1, 0, $2, NOW())
		ON CONFLICT (product_id) DO UPDATE SET limit_qty = $2, updated_at = NOW()`,
		req.ProductID, req.LimitQty); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"ok": true, "product_id": req.ProductID, "limit_qty": req.LimitQty})
}
