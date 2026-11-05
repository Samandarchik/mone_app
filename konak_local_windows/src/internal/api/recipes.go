package api

// Retsept (tex-karta, PARTIYA asosida) — 3-bosqich:
//   GET  /api/recipes             — hammasi (retsept editorlari uchun)
//   GET  /api/recipe?product_id=  — bitta mahsulot retsepti
//   PUT  /api/recipe              — upsert (items: butun partiya uchun miqdorlar)
//   DELETE /api/recipe/{product_id}
//   GET  /api/recipe/cost?product_id= — partiya/dona tannarxi
//
// S4 qarori: amount — BUTUN PARTIYA uchun ("10 ta cheesecake'ga 2 kg tvorog"),
// 1 dona hisoblash noqulay. batch_qty = partiyada nechta chiqadi.
// Tannarx: oxirgi xarid narxi × waste bilan oshirilgan miqdor (S9),
// nisbat xotirada float, natija butun so'm (S8).

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"fmt"
	"konak-local/internal/db"
	"sort"
	"strings"
	"time"
)

// RecipeItem — retseptdagi bitta ingredient (amount — butun partiya uchun).
//
// PART — retsept QISMI ("Biskvit", "Krem"). Desert bir necha qismdan yig'iladi
// va bitta masalliq (tuxum) bir necha qismga kirishi mumkin. Bo'sh `part` =
// qismsiz retsept — eski retseptlar aynan shunday va o'zgarishsiz ishlaydi.
// Ro'yxat TEKIS qoladi (qismlar ichma-ich emas, faqat yorliq): tannarx,
// pishirish, analitika va sync kodi item'larni ilgarigidek aylanaveradi.
type RecipeItem struct {
	IngredientID int    `json:"ingredient_id"`
	Name         string `json:"name"`
	Unit         string `json:"unit"`
	Amount       int64  `json:"amount"`
	Part         string `json:"part,omitempty"`
}

// maxRecipePartLen — qism nomi uzunligi chegarasi (ekranga sig'sin va
// JSONB cheksiz o'smasin).
const maxRecipePartLen = 40

// ingPriceInfo — tannarx uchun ingredient ma'lumoti.
type ingPriceInfo struct {
	Name         string
	Unit         string
	WastePercent int
	LastQty      int64
	LastSubtotal int64
}

// loadIngPriceInfo — barcha (o'chirilmagan) ingredientlar: oxirgi xarid
// narxi + waste. Tannarx va analitika shu bitta so'rovdan foydalanadi.
func loadIngPriceInfo(ctx context.Context) (map[int]ingPriceInfo, error) {
	rows, err := db.Pool.Query(ctx, `
		SELECT i.id, i.name, i.unit, i.waste_percent,
		       COALESCE(pi.qty, 0), COALESCE(pi.subtotal, 0)
		FROM ingredients i
		LEFT JOIN LATERAL (
			SELECT qty, subtotal FROM purchase_items
			WHERE ingredient_id = i.id ORDER BY id DESC LIMIT 1
		) pi ON true
		WHERE i.status <> 'deleted'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := map[int]ingPriceInfo{}
	for rows.Next() {
		var id int
		var info ingPriceInfo
		if err := rows.Scan(&id, &info.Name, &info.Unit, &info.WastePercent, &info.LastQty, &info.LastSubtotal); err != nil {
			return nil, err
		}
		out[id] = info
	}
	return out, rows.Err()
}

// normalizeRecipePart — qism nomini tozalaydi: chetdagi bo'shliqlar olinadi
// ("Krem " va "Krem" ikki xil qism bo'lib qolmasin), uzunligi chegaralanadi.
func normalizeRecipePart(s string) string {
	s = strings.TrimSpace(s)
	if len([]rune(s)) > maxRecipePartLen {
		s = string([]rune(s)[:maxRecipePartLen])
		s = strings.TrimSpace(s)
	}
	return s
}

// recipePartTotals — qism bo'yicha tannarx yig'indisi, retseptdagi TARTIBDA
// (birinchi uchragan qism birinchi bo'lib chiqadi). Retsept qismsiz bo'lsa
// bo'sh ro'yxat qaytadi — ekran hech narsa ko'rsatmaydi.
func recipePartTotals(items []RecipeItem, detail []map[string]interface{}) []map[string]interface{} {
	hasPart := false
	for _, it := range items {
		if it.Part != "" {
			hasPart = true
			break
		}
	}
	if !hasPart {
		return []map[string]interface{}{}
	}
	order := []string{}
	sums := map[string]int64{}
	counts := map[string]int{}
	for i, it := range items {
		if _, ok := sums[it.Part]; !ok {
			order = append(order, it.Part)
		}
		if i < len(detail) {
			if c, ok := detail[i]["cost"].(int64); ok {
				sums[it.Part] += c
			}
		}
		counts[it.Part]++
	}
	out := make([]map[string]interface{}, 0, len(order))
	for _, name := range order {
		out = append(out, map[string]interface{}{
			"part": name, "cost": sums[name], "items_count": counts[name],
		})
	}
	return out
}

// mergeRecipeParts — retsept qatorlarini MASALLIQ bo'yicha birlashtiradi.
//
// Desert retsepti qismlarga bo'linadi ("Biskvit", "Krem") va bitta masalliq
// bir necha qismda turishi mumkin — tuxum ikkalasiga ham kiradi. Ombordan
// chiqim esa masalliq bo'yicha BITTA bo'lishi kerak: avval TOZA miqdorlar
// qo'shiladi, masshtab/waste/yaxlitlash keyin bir marta qo'llanadi.
//
// NEGA BIRLASHTIRILADI: har qism alohida hisoblansa, `grossAmountScaled`
// izohidagi yaxlitlash chetlanishi qism soniga ko'payib to'planardi, va
// "1 birlikdan kam bo'lsa 1 ta" qoidasi ham har qismda alohida ishlab
// ombordan haqiqiydan ko'proq chiqim yozilardi.
//
// Tartib — birinchi uchrash tartibi (natija barqaror bo'lsin). Qaytgan
// qatorlarda `Part` bo'sh: bu endi bitta umumiy chiqim, qismga tegishli emas.
func mergeRecipeParts(items []RecipeItem) []RecipeItem {
	out := make([]RecipeItem, 0, len(items))
	at := map[int]int{} // ingredient_id → out dagi indeks
	for _, it := range items {
		if i, ok := at[it.IngredientID]; ok {
			out[i].Amount += it.Amount
			continue
		}
		at[it.IngredientID] = len(out)
		out = append(out, RecipeItem{
			IngredientID: it.IngredientID, Name: it.Name,
			Unit: it.Unit, Amount: it.Amount,
		})
	}
	return out
}

// grossAmount — waste bilan oshirilgan sarf: ombordan TOZALANMAGAN mahsulot
// olinadi, shuning uchun amount × 100/(100−waste). Natija butun son.
func grossAmount(amount int64, wastePercent int) int64 {
	if wastePercent <= 0 {
		return amount
	}
	return int64(math.Round(float64(amount) * 100.0 / float64(100-wastePercent)))
}

// grossAmountScaled — retsept miqdorini so'ralgan `qty` ga masshtablab, waste
// bilan oshiradi va FAQAT BIR MARTA yaxlitlaydi.
//
// NEGA BIR MARTA: ilgari avval `Round(amount*qty/batchQty)`, so'ng natijaga
// `Round(scaled*100/(100-waste))` qo'llanardi. Ikki yaxlitlash chetlanishni
// qo'shib yuborardi va u har pishirishda BIR TOMONGA to'planardi — ya'ni
// ombor kitobi javondagi haqiqiy qoldiqdan asta-sekin uzoqlashardi.
func grossAmountScaled(amount int64, qty, batchQty, wastePercent int) int64 {
	if batchQty <= 0 {
		batchQty = 1
	}
	if wastePercent < 0 || wastePercent >= 100 {
		wastePercent = 0
	}
	v := float64(amount) * float64(qty) / float64(batchQty)
	if wastePercent > 0 {
		v = v * 100.0 / float64(100-wastePercent)
	}
	if v <= 0 {
		return 0
	}
	// Cheksiz katta retsept miqdori int64 ga sig'masligi mumkin — chegaralaymiz.
	if v > float64(maxIngredientCount) {
		return maxIngredientCount
	}
	return int64(math.Round(v))
}

// recipeCost — bitta retsept tannarxi. Qaytadi: partiya tannarxi, dona tannarxi,
// har item hisobi, narxi yo'q ingredient bormi (incomplete).
func recipeCost(batchQty int, items []RecipeItem, prices map[int]ingPriceInfo) (int64, int64, []map[string]interface{}, bool) {
	var batchCost int64
	incomplete := false
	detail := []map[string]interface{}{}

	for _, it := range items {
		info, ok := prices[it.IngredientID]
		gross := grossAmount(it.Amount, info.WastePercent)
		var cost int64
		if !ok || info.LastQty <= 0 {
			incomplete = true
		} else {
			cost = int64(math.Round(float64(gross) * float64(info.LastSubtotal) / float64(info.LastQty)))
		}
		batchCost += cost
		detail = append(detail, map[string]interface{}{
			"ingredient_id": it.IngredientID, "name": it.Name, "unit": it.Unit,
			"amount": it.Amount, "gross_amount": gross, "cost": cost,
			"has_price": ok && info.LastQty > 0, "part": it.Part,
		})
	}

	pieceCost := batchCost
	if batchQty > 1 {
		pieceCost = int64(math.Round(float64(batchCost) / float64(batchQty)))
	}
	return batchCost, pieceCost, detail, incomplete
}

// loadRecipe — retseptni o'qiydi (yo'q bo'lsa found=false).
func loadRecipe(ctx context.Context, productID int) (int, []RecipeItem, bool) {
	var batchQty int
	var itemsJSON []byte
	err := db.Pool.QueryRow(ctx,
		"SELECT batch_qty, items FROM recipes WHERE product_id = $1", productID).Scan(&batchQty, &itemsJSON)
	if err != nil {
		return 0, nil, false
	}
	items := []RecipeItem{}
	json.Unmarshal(itemsJSON, &items)
	return batchQty, items, true
}

// ============ GET /api/recipes ============

func handleGetRecipes(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	rows, err := db.Pool.Query(r.Context(), `
		SELECT r.product_id, COALESCE(p.name_uz, ''), r.batch_qty, r.items
		FROM recipes r LEFT JOIN products p ON p.id = r.product_id
		ORDER BY p.name_uz`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	recipes := []map[string]interface{}{}
	for rows.Next() {
		var productID, batchQty int
		var name string
		var itemsJSON []byte
		if err := rows.Scan(&productID, &name, &batchQty, &itemsJSON); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		recipes = append(recipes, map[string]interface{}{
			"product_id": productID, "product_name": name,
			"batch_qty": batchQty, "items": json.RawMessage(itemsJSON),
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"recipes": recipes})
}

// ============ GET /api/recipe?product_id= ============

func handleGetRecipe(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	productID, _ := strconv.Atoi(r.URL.Query().Get("product_id"))
	if productID <= 0 {
		jsonError(w, 400, "bad_request", "product_id kerak")
		return
	}
	batchQty, items, found := loadRecipe(r.Context(), productID)
	if !found {
		jsonResponse(w, 200, map[string]interface{}{
			"product_id": productID, "batch_qty": 0, "items": []RecipeItem{}, "exists": false,
		})
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"product_id": productID, "batch_qty": batchQty, "items": items, "exists": true,
	})
}

// ============ PUT /api/recipe ============

func handleUpsertRecipe(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	var req struct {
		ProductID int `json:"product_id"`
		BatchQty  int `json:"batch_qty"`
		Items     []struct {
			IngredientID int    `json:"ingredient_id"`
			Amount       int64  `json:"amount"`
			Part         string `json:"part"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	// BATCH_QTY MAJBURIY EMAS.
	//
	// Ko'p mahsulot (kofe, choy) buyurtma kelganda BITTALAB tayyorlanadi —
	// "bir pishirishda nechta chiqadi" degan savol ular uchun ma'nosiz.
	// Bo'sh/0 kelsa 1 deb olamiz: retsept miqdorlari 1 dona uchun bo'ladi va
	// pishirishda masshtablash (qty/batch_qty) o'zgarishsiz ishlaydi.
	if req.BatchQty <= 0 {
		req.BatchQty = 1
	}
	if req.ProductID <= 0 || len(req.Items) == 0 {
		jsonError(w, 400, "bad_request", "product_id va kamida 1 item kerak")
		return
	}

	var exists int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM products WHERE id = $1", req.ProductID).Scan(&exists)
	if exists == 0 {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi")
		return
	}

	// Ingredient nomi/birligi server tomonda hal qilinadi (snapshot emas —
	// ko'rsatish uchun; tannarx doim jonli ingredients dan oladi)
	//
	// TAKRORLANISH endi QISM bilan birga tekshiriladi: tuxum "Biskvit"da ham,
	// "Krem"da ham bo'lishi mumkin, lekin BITTA qism ichida ikki marta — yo'q
	// (u ikki qatorni qo'shib yozish kerak, aks holda qaysi biri to'g'ri
	// ekani noaniq bo'lardi).
	items := []RecipeItem{}
	seen := map[string]bool{}
	for _, it := range req.Items {
		if it.IngredientID <= 0 || it.Amount <= 0 {
			jsonError(w, 400, "bad_request", "har itemda ingredient_id va amount (>0) kerak")
			return
		}
		part := normalizeRecipePart(it.Part)
		key := part + "\x00" + strconv.Itoa(it.IngredientID)
		if seen[key] {
			msg := "Ingredient takrorlangan"
			if part != "" {
				msg = "\"" + part + "\" qismida ingredient takrorlangan"
			}
			jsonError(w, 400, "bad_request", msg)
			return
		}
		seen[key] = true

		var name, unit, status string
		if err := db.Pool.QueryRow(r.Context(),
			"SELECT name, unit, status FROM ingredients WHERE id = $1",
			it.IngredientID).Scan(&name, &unit, &status); err != nil || status == "deleted" {
			jsonError(w, 400, "bad_request", "Ingredient topilmadi: "+strconv.Itoa(it.IngredientID))
			return
		}
		items = append(items, RecipeItem{
			IngredientID: it.IngredientID, Name: name, Unit: unit,
			Amount: it.Amount, Part: part,
		})
	}

	itemsJSON, _ := json.Marshal(items)
	if _, err := db.Pool.Exec(r.Context(), `
		INSERT INTO recipes (product_id, batch_qty, items, updated_at) VALUES ($1, $2, $3, NOW())
		ON CONFLICT (product_id) DO UPDATE SET batch_qty = $2, items = $3, updated_at = NOW()`,
		req.ProductID, req.BatchQty, string(itemsJSON)); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"ok": true, "product_id": req.ProductID, "batch_qty": req.BatchQty, "items": items,
	})
}

// ============ DELETE /api/recipe/{product_id} ============

func handleDeleteRecipe(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	productID, _ := strconv.Atoi(chi.URLParam(r, "product_id"))
	if productID <= 0 {
		jsonError(w, 400, "bad_request", "product_id noto'g'ri")
		return
	}
	tag, err := db.Pool.Exec(r.Context(), "DELETE FROM recipes WHERE product_id = $1", productID)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Retsept topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"ok": true})
}

// ============ GET /api/recipe/cost?product_id= ============

func handleRecipeCost(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	productID, _ := strconv.Atoi(r.URL.Query().Get("product_id"))
	if productID <= 0 {
		jsonError(w, 400, "bad_request", "product_id kerak")
		return
	}
	batchQty, items, found := loadRecipe(r.Context(), productID)
	if !found {
		jsonError(w, 404, "not_found", "Retsept yo'q")
		return
	}
	prices, err := loadIngPriceInfo(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	batchCost, pieceCost, detail, incomplete := recipeCost(batchQty, items, prices)
	jsonResponse(w, 200, map[string]interface{}{
		"product_id": productID, "batch_qty": batchQty,
		"batch_cost": batchCost, "piece_cost": pieceCost,
		"items": detail, "incomplete": incomplete,
		"parts": recipePartTotals(items, detail),
	})
}

// ============ GET|POST /api/recipes/recover ============
//
// RETSEPTLARNI AUDIT JURNALIDAN TIKLASH.
//
// NEGA KERAK: retsept saqlash `PUT /api/recipe` orqali ketadi va
// `AuditMutations` oraliq qatlami HAR BIR bunday so'rovning TO'LIQ tanasini
// `audit_logs.request_data` ga yozib qo'yadi. Ya'ni kiritilgan retsept
// yo'qolgan bo'lsa ham (boshqa node'ga tushib ketgan, sync yetkazmagan,
// prune o'chirgan) — uning asl mazmuni jurnalda turadi.
//
// GET  — faqat hisobot: nima yo'q, nima farq qiladi (hech narsa yozilmaydi).
// POST — tiklash. `?mode=missing` (standart) faqat YO'Q retseptlarni
//
//	tiklaydi; `?mode=all` farq qilayotganlarini ham jurnaldagi
//	oxirgi holatga qaytaradi.
func handleRecoverRecipes(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}
	apply := r.Method == http.MethodPost
	overwrite := r.URL.Query().Get("mode") == "all"

	rows, err := db.Pool.Query(r.Context(), `
		SELECT request_data, created_at, actor_name
		  FROM audit_logs
		 WHERE entity_type = 'recipe' AND action = 'put'
		 ORDER BY created_at`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	type auditRecipe struct {
		BatchQty int
		Items    []struct {
			IngredientID int    `json:"ingredient_id"`
			Amount       int64  `json:"amount"`
			Part         string `json:"part"`
		}
		At    time.Time
		Actor string
	}
	// Har mahsulot uchun jurnaldagi ENG OXIRGI yozuv.
	latest := map[int]auditRecipe{}
	for rows.Next() {
		var raw []byte
		var at time.Time
		var actor string
		if err := rows.Scan(&raw, &at, &actor); err != nil {
			continue
		}
		var body struct {
			ProductID int `json:"product_id"`
			BatchQty  int `json:"batch_qty"`
			Items     []struct {
				IngredientID int    `json:"ingredient_id"`
				Amount       int64  `json:"amount"`
				Part         string `json:"part"`
			} `json:"items"`
		}
		if json.Unmarshal(raw, &body) != nil || body.ProductID <= 0 || len(body.Items) == 0 {
			continue
		}
		if body.BatchQty <= 0 {
			body.BatchQty = 1 // partiya majburiy emas — bittalab tayyorlanadi
		}
		latest[body.ProductID] = auditRecipe{
			BatchQty: body.BatchQty, Items: body.Items, At: at, Actor: actor,
		}
	}
	rowsErr := rows.Err()
	rows.Close()
	if rowsErr != nil {
		jsonError(w, 500, "db_error", rowsErr.Error())
		return
	}

	ids := make([]int, 0, len(latest))
	for id := range latest {
		ids = append(ids, id)
	}
	sort.Ints(ids)

	report := []map[string]interface{}{}
	restored, skipped := 0, 0

	for _, productID := range ids {
		rec := latest[productID]

		var productName string
		if err := db.Pool.QueryRow(r.Context(),
			"SELECT name_uz FROM products WHERE id = $1", productID).Scan(&productName); err != nil {
			report = append(report, map[string]interface{}{
				"product_id": productID, "state": "product_missing",
				"logged_at": rec.At.Format(time.RFC3339),
			})
			skipped++
			continue
		}

		curBatch, curItems, found := loadRecipe(r.Context(), productID)
		same := found && curBatch == rec.BatchQty && len(curItems) == len(rec.Items)
		if same {
			// Kalit QISM bilan birga: bir masalliq bir necha qismda
			// (tuxum — "Biskvit" va "Krem") turishi mumkin, faqat
			// ingredient_id bo'yicha solishtirsak ular ustma-ust tushib,
			// farqli retsept "bir xil" ko'rinardi.
			byKey := map[string]int64{}
			for _, it := range curItems {
				byKey[it.Part+"\x00"+strconv.Itoa(it.IngredientID)] = it.Amount
			}
			for _, it := range rec.Items {
				key := normalizeRecipePart(it.Part) + "\x00" + strconv.Itoa(it.IngredientID)
				if byKey[key] != it.Amount {
					same = false
					break
				}
			}
		}

		state := "missing"
		switch {
		case same:
			state = "ok"
		case found:
			state = "different"
		}

		entry := map[string]interface{}{
			"product_id": productID, "product_name": productName,
			"state": state, "logged_at": rec.At.Format(time.RFC3339),
			"logged_by": rec.Actor,
			"batch_qty": rec.BatchQty, "items_count": len(rec.Items),
		}

		needsWrite := state == "missing" || (state == "different" && overwrite)
		if apply && needsWrite {
			items := []RecipeItem{}
			bad := ""
			for _, it := range rec.Items {
				var name, unit, status string
				if err := db.Pool.QueryRow(r.Context(),
					"SELECT name, unit, status FROM ingredients WHERE id = $1",
					it.IngredientID).Scan(&name, &unit, &status); err != nil || status == "deleted" {
					bad = fmt.Sprintf("ingredient #%d topilmadi", it.IngredientID)
					break
				}
				items = append(items, RecipeItem{
					IngredientID: it.IngredientID, Name: name, Unit: unit,
					Amount: it.Amount, Part: normalizeRecipePart(it.Part),
				})
			}
			if bad != "" {
				entry["state"] = "ingredient_missing"
				entry["error"] = bad
				skipped++
				report = append(report, entry)
				continue
			}
			itemsJSON, _ := json.Marshal(items)
			if _, err := db.Pool.Exec(r.Context(), `
				INSERT INTO recipes (product_id, batch_qty, items, updated_at)
				VALUES ($1, $2, $3, NOW())
				ON CONFLICT (product_id) DO UPDATE
				   SET batch_qty = $2, items = $3, updated_at = NOW()`,
				productID, rec.BatchQty, string(itemsJSON)); err != nil {
				entry["state"] = "write_failed"
				entry["error"] = err.Error()
				skipped++
				report = append(report, entry)
				continue
			}
			entry["state"] = "restored"
			restored++
		} else if needsWrite {
			// dry-run: tiklanishi mumkin
			entry["recoverable"] = true
		}
		report = append(report, entry)
	}

	jsonResponse(w, 200, map[string]interface{}{
		"applied":      apply,
		"mode":         map[bool]string{true: "all", false: "missing"}[overwrite],
		"in_audit_log": len(latest),
		"restored":     restored,
		"skipped":      skipped,
		"recipes":      report,
	})
}
