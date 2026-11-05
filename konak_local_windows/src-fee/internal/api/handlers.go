package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"konak-local/internal/crm"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/models"
	"konak-local/internal/printer"
	"konak-local/internal/wss"
)

func jsonResponse(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func jsonError(w http.ResponseWriter, status int, err, message string) {
	jsonResponse(w, status, map[string]string{"error": err, "message": message})
}

// ============ GET /api/health ============

func handleHealth(w http.ResponseWriter, r *http.Request) {
	status, payload := buildHealth(r.Context())
	jsonResponse(w, status, payload)
}

// ============ GET /api/menu ============

func handleGetMenu(w http.ResponseWriter, r *http.Request) {
	var version int
	db.Pool.QueryRow(r.Context(), "SELECT version FROM menu_version WHERE id = 1").Scan(&version)

	// `?include_inactive=1` — admin menyusi uchun.
	//
	// NEGA KERAK: mahsulotni "Nofaol" qilish BIR TOMONLAMA tuzoq edi.
	// Ro'yxat faqat `status='active'` ni qaytargani uchun nofaol mahsulot
	// ilovadan butunlay yo'qolardi va uni QAYTA YOQIB bo'lmasdi — mavsumiy
	// taomni yashirgan admin bahorda uni qaytadan yaratishga majbur edi
	// (yangi id, yo'qolgan retsept va sotuv tarixi).
	includeInactive := r.URL.Query().Get("include_inactive") == "1"
	statusFilter := "status = 'active'"
	if includeInactive {
		statusFilter = "status <> 'deleted'"
	}

	// Categories
	catRows, err := db.Pool.Query(r.Context(), "SELECT id, name_uz, name_ru, name_tr, icon, sort_order, status, printer_station_id FROM categories WHERE "+statusFilter+" ORDER BY sort_order")
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer catRows.Close()

	categories := []models.CategoryJSON{}
	for catRows.Next() {
		var c models.Category
		catRows.Scan(&c.ID, &c.NameUz, &c.NameRu, &c.NameTr, &c.Icon, &c.SortOrder, &c.Status, &c.PrinterStationID)
		categories = append(categories, models.CategoryJSON{
			ID: c.ID, Name: c.Name(), Icon: c.Icon, SortOrder: c.SortOrder, Status: c.Status, PrinterStationID: c.PrinterStationID,
		})
	}

	// Products — kategoriya tartibida guruhlangan, har kategoriya ichida sort_order bo'yicha
	prodRows, err := db.Pool.Query(r.Context(), `
		SELECT p.id, p.name_uz, p.name_ru, p.name_tr, p.description_uz, p.description_ru, p.description_tr,
		       p.category_id, p.price, p.old_price, p.media, p.status, p.is_recommended,
		       p.availability, p.ingredients, p.sort_order, p.printer_station_id, p.product_type
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE p.`+statusFilter+`
		ORDER BY COALESCE(c.sort_order, 999999), p.category_id, p.sort_order, p.id`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer prodRows.Close()

	products := []models.ProductJSON{}
	for prodRows.Next() {
		var p models.Product
		prodRows.Scan(&p.ID, &p.NameUz, &p.NameRu, &p.NameTr, &p.DescriptionUz, &p.DescriptionRu, &p.DescriptionTr,
			&p.CategoryID, &p.Price, &p.OldPrice, &p.Media, &p.Status, &p.IsRecommended, &p.Availability, &p.Ingredients, &p.SortOrder, &p.PrinterStationID, &p.ProductType)

		desc := map[string]string{}
		if p.DescriptionUz != nil {
			desc["uz"] = *p.DescriptionUz
		}
		if p.DescriptionRu != nil {
			desc["ru"] = *p.DescriptionRu
		}
		if p.DescriptionTr != nil {
			desc["tr"] = *p.DescriptionTr
		}

		var avail, ingr json.RawMessage
		if p.Availability != nil {
			avail = json.RawMessage(*p.Availability)
		} else {
			avail = json.RawMessage("null")
		}
		if p.Ingredients != nil {
			ingr = json.RawMessage(*p.Ingredients)
		} else {
			ingr = json.RawMessage("null")
		}

		products = append(products, models.ProductJSON{
			ID:               p.ID,
			Name:             map[string]string{"uz": p.NameUz, "ru": p.NameRu, "tr": p.NameTr},
			SortOrder:        p.SortOrder,
			Description:      desc,
			CategoryID:       p.CategoryID,
			Price:            p.Price,
			OldPrice:         p.OldPrice,
			Media:            json.RawMessage(p.Media),
			Status:           p.Status,
			IsRecommended:    p.IsRecommended,
			Availability:     avail,
			Ingredients:      ingr,
			PrinterStationID: p.PrinterStationID,
			ProductType:      p.ProductType,
		})
	}

	jsonResponse(w, 200, map[string]interface{}{
		"version":    version,
		"categories": categories,
		"products":   products,
	})
}

// ============ GET /api/menu-web ============
//
// QR mijoz (konak_web) uchun maxsus menyu endpoint.
// /api/menu bilan AYNAN bir xil DB ma'lumotlarini qaytaradi, lekin:
//   - bo'sh kategoriyalar (aktiv mahsuloti yo'q) chiqarib tashlanadi
//   - tartib POS bilan 1-1: categories ASC by sort_order, products ASC by
//     (category.sort_order, product.sort_order, product.id)
//   - public, auth talab qilinmaydi
//
// POS dan drag-drop bilan reorder qilinsa (POST /api/reorder) DB dagi
// sort_order o'zgaradi → bu endpoint avtomatik yangi tartibni qaytaradi.
// WSS event "menu:outdated" web ga yuborilganda u qayta /api/menu-web ni
// chaqiradi va yangi tartibda render qiladi.
func handleGetMenuWeb(w http.ResponseWriter, r *http.Request) {
	var version int
	db.Pool.QueryRow(r.Context(), "SELECT version FROM menu_version WHERE id = 1").Scan(&version)

	// Categories — faqat aktiv VA ichida aktiv mahsuloti bor
	catRows, err := db.Pool.Query(r.Context(), `
		SELECT c.id, c.name_uz, c.name_ru, c.name_tr, c.icon, c.sort_order, c.status, c.printer_station_id
		FROM categories c
		WHERE c.status = 'active'
		  AND EXISTS (SELECT 1 FROM products p WHERE p.category_id = c.id AND p.status = 'active')
		ORDER BY c.sort_order, c.id`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer catRows.Close()

	categories := []models.CategoryJSON{}
	for catRows.Next() {
		var c models.Category
		catRows.Scan(&c.ID, &c.NameUz, &c.NameRu, &c.NameTr, &c.Icon, &c.SortOrder, &c.Status, &c.PrinterStationID)
		categories = append(categories, models.CategoryJSON{
			ID: c.ID, Name: c.Name(), Icon: c.Icon, SortOrder: c.SortOrder, Status: c.Status, PrinterStationID: c.PrinterStationID,
		})
	}

	// Products — POS bilan bir xil tartib (category sort_order → product sort_order → id).
	// Qoldig'i 0 (yoki manfiy) mahsulot QR mijozga KO'RSATILMAYDI — hamma
	// mahsulot 0 dan boshlanadi, bazaga qo'shilgandagina sotuvga chiqadi.
	prodRows, err := db.Pool.Query(r.Context(), `
		SELECT p.id, p.name_uz, p.name_ru, p.name_tr, p.description_uz, p.description_ru, p.description_tr,
		       p.category_id, p.price, p.old_price, p.media, p.status, p.is_recommended,
		       p.availability, p.ingredients, p.sort_order, p.printer_station_id, p.product_type
		FROM products p
		JOIN categories c ON c.id = p.category_id
		LEFT JOIN stocks s ON s.product_id = p.id
		WHERE p.status = 'active' AND c.status = 'active' AND COALESCE(s.count, 0) > 0
		ORDER BY c.sort_order, p.category_id, p.sort_order, p.id`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer prodRows.Close()

	products := []models.ProductJSON{}
	for prodRows.Next() {
		var p models.Product
		prodRows.Scan(&p.ID, &p.NameUz, &p.NameRu, &p.NameTr, &p.DescriptionUz, &p.DescriptionRu, &p.DescriptionTr,
			&p.CategoryID, &p.Price, &p.OldPrice, &p.Media, &p.Status, &p.IsRecommended, &p.Availability, &p.Ingredients, &p.SortOrder, &p.PrinterStationID, &p.ProductType)

		desc := map[string]string{}
		if p.DescriptionUz != nil {
			desc["uz"] = *p.DescriptionUz
		}
		if p.DescriptionRu != nil {
			desc["ru"] = *p.DescriptionRu
		}
		if p.DescriptionTr != nil {
			desc["tr"] = *p.DescriptionTr
		}

		var avail, ingr json.RawMessage
		if p.Availability != nil {
			avail = json.RawMessage(*p.Availability)
		} else {
			avail = json.RawMessage("null")
		}
		if p.Ingredients != nil {
			ingr = json.RawMessage(*p.Ingredients)
		} else {
			ingr = json.RawMessage("null")
		}

		products = append(products, models.ProductJSON{
			ID:               p.ID,
			Name:             map[string]string{"uz": p.NameUz, "ru": p.NameRu, "tr": p.NameTr},
			SortOrder:        p.SortOrder,
			Description:      desc,
			CategoryID:       p.CategoryID,
			Price:            p.Price,
			OldPrice:         p.OldPrice,
			Media:            json.RawMessage(p.Media),
			Status:           p.Status,
			IsRecommended:    p.IsRecommended,
			Availability:     avail,
			Ingredients:      ingr,
			PrinterStationID: p.PrinterStationID,
			ProductType:      p.ProductType,
		})
	}

	jsonResponse(w, 200, map[string]interface{}{
		"version":    version,
		"categories": categories,
		"products":   products,
		// Xizmat haqi olib tashlangan — eski web buildlar 0 ni e'tiborsiz
		// qoldiradi, server esa baribir hech narsa undirmaydi.
		"service_fee_percent": 0,
	})
}

// ============ GET /api/table/:sku ============

// ============ GET /api/tables/qr-codes ============
func handleGetQRCodes(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), "SELECT t.id, t.sku, t.label, t.qr_code, z.name FROM tables t JOIN zones z ON t.zone_id = z.id ORDER BY t.zone_id, t.number")
	if err != nil {
		jsonError(w, 500, "db_error", "Ma'lumot olishda xato")
		return
	}
	defer rows.Close()

	var tables []map[string]interface{}
	for rows.Next() {
		var id int
		var sku, label, qrCode, zoneName string
		rows.Scan(&id, &sku, &label, &qrCode, &zoneName)
		tables = append(tables, map[string]interface{}{
			"id": id, "sku": sku, "label": label, "qr_code": qrCode,
			"qr_url": customerURLForCode(qrCode), "zone_name": zoneName,
		})
	}
	jsonResponse(w, 200, tables)
}

// ============ GET /api/qr/table/:code ============
func handleQRTableLookup(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	var sku, label string
	var zoneID, tableID int
	err := db.Pool.QueryRow(r.Context(), "SELECT id, sku, label, zone_id FROM tables WHERE qr_code = $1", code).
		Scan(&tableID, &sku, &label, &zoneID)
	if err != nil {
		jsonError(w, 404, "not_found", "Stol topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"table_sku": sku, "table_id": tableID, "label": label, "zone_id": zoneID, "code": code,
	})
}

func handleGetTable(w http.ResponseWriter, r *http.Request) {
	sku := chi.URLParam(r, "sku")

	var t models.Table
	var zoneName string
	err := db.Pool.QueryRow(r.Context(), "SELECT t.id, t.zone_id, t.sku, t.number, t.label, t.seats, t.status, z.name FROM tables t JOIN zones z ON t.zone_id = z.id WHERE t.sku = $1", sku).
		Scan(&t.ID, &t.ZoneID, &t.SKU, &t.Number, &t.Label, &t.Seats, &t.Status, &zoneName)
	if err != nil {
		jsonError(w, 404, "not_found", "Stol topilmadi")
		return
	}

	resp := map[string]interface{}{
		"table_sku":    t.SKU,
		"table_id":     t.ID,
		"zone_id":      t.ZoneID,
		"zone_name":    map[string]string{"uz": zoneName},
		"label":        t.Label,
		"seats":        t.Seats,
		"status":       t.Status,
		"locked_by":    nil,
		"active_order": nil,
	}

	// Lock info
	var lock models.TableLock
	err = db.Pool.QueryRow(r.Context(), "SELECT user_id, name, role, source FROM table_locks WHERE table_sku = $1", sku).
		Scan(&lock.UserID, &lock.Name, &lock.Role, &lock.Source)
	if err == nil {
		resp["locked_by"] = map[string]interface{}{
			"user_id": lock.UserID, "name": lock.Name, "role": lock.Role, "source": lock.Source,
		}
	}

	// All active checks for this table
	checkRows, _ := db.Pool.Query(r.Context(), "SELECT order_number, type, status, items, subtotal, service_fee, discount, total, note, created_at FROM orders WHERE table_sku = $1 AND status NOT IN ('completed','cancelled') ORDER BY created_at", sku)
	checks := []map[string]interface{}{}
	grandTotal := 0
	if checkRows != nil {
		for checkRows.Next() {
			var oNum, oType, oStatus string
			var oItems json.RawMessage
			var oSub, oSF, oDisc, oTotal int
			var oNote *string
			var oCreated time.Time
			checkRows.Scan(&oNum, &oType, &oStatus, &oItems, &oSub, &oSF, &oDisc, &oTotal, &oNote, &oCreated)
			checks = append(checks, map[string]interface{}{
				"order_number": oNum, "type": oType, "status": oStatus,
				"items": oItems, "subtotal": oSub, "service_fee": oSF,
				"discount": oDisc, "total": oTotal, "note": oNote,
				"created_at": oCreated.Format(time.RFC3339),
			})
			if oStatus != "cancelled" {
				grandTotal += oTotal
			}
		}
		checkRows.Close()
	}
	resp["checks"] = checks
	resp["checks_count"] = len(checks)
	resp["grand_total"] = grandTotal

	jsonResponse(w, 200, resp)
}

// ============ GET /api/stocks ============

func handleGetStocks(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(),
		"SELECT product_id, count, limit_qty, updated_at FROM stocks ORDER BY product_id")
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	stocks := []models.Stock{}
	for rows.Next() {
		var s models.Stock
		// updated_at TIMESTAMPTZ — to'g'ridan-to'g'ri string'ga scan qilinmaydi;
		// xato bo'lsa pgx qolgan qatorlarni ham to'xtatib qo'yardi (ro'yxat 1 ta
		// nol qatorga aylanib, POS hamma mahsulotni "tugagan" deb ko'rsatardi).
		var updated time.Time
		if err := rows.Scan(&s.ProductID, &s.Count, &s.LimitQty, &updated); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		s.UpdatedAt = updated.UTC().Format(time.RFC3339)
		stocks = append(stocks, s)
	}
	if err := rows.Err(); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 200, stocks)
}

// ============ GET /api/zones ============

func handleGetZones(w http.ResponseWriter, r *http.Request) {
	// Single query — no N+1
	// DISTINCT ON requires its keys to lead ORDER BY, so we wrap in a subquery
	// and re-order by zone sort_order + table number for natural ordering
	// (ZAL-1, ZAL-2 ... ZAL-10 instead of alphabetical ZAL-1, ZAL-10, ZAL-2).
	rows, err := db.Pool.Query(r.Context(), `
		SELECT z_id, z_name, z_sort, t_sku, t_label, t_seats, t_status, t_number, lock_name, lock_source, has_order
		FROM (
			SELECT DISTINCT ON (z.id, t.sku)
				z.id AS z_id, z.name AS z_name, z.sort_order AS z_sort,
				t.sku AS t_sku, t.label AS t_label, t.seats AS t_seats, t.status AS t_status, t.number AS t_number,
				tl.name AS lock_name, tl.source AS lock_source,
				CASE WHEN EXISTS(SELECT 1 FROM orders o WHERE o.table_sku = t.sku AND o.status NOT IN ('completed','cancelled')) THEN 1 ELSE 0 END AS has_order
			FROM zones z
			LEFT JOIN tables t ON t.zone_id = z.id
			LEFT JOIN table_locks tl ON t.sku = tl.table_sku
			WHERE z.status = 'active'
			ORDER BY z.id, t.sku
		) sub
		ORDER BY z_sort, z_id, t_number NULLS FIRST`)
	if err != nil {
		jsonResponse(w, 200, []interface{}{})
		return
	}
	defer rows.Close()

	type tableInfo struct {
		SKU            string      `json:"sku"`
		Label          string      `json:"label"`
		Seats          int         `json:"seats"`
		Status         string      `json:"status"`
		Number         int         `json:"number"`
		LockedBy       interface{} `json:"locked_by"`
		HasActiveOrder bool        `json:"has_active_order"`
	}
	type zoneInfo struct {
		ID        int               `json:"id"`
		Name      map[string]string `json:"name"`
		SortOrder int               `json:"sort_order"`
		Tables    []tableInfo       `json:"tables"`
	}

	zonesMap := map[int]*zoneInfo{}
	var zonesOrder []int

	for rows.Next() {
		var zid, zso int
		var zname string
		var tsku, tlabel, tstatus *string
		var tseats, tnumber *int
		var lockName, lockSource *string
		var hasOrder int

		rows.Scan(&zid, &zname, &zso, &tsku, &tlabel, &tseats, &tstatus, &tnumber, &lockName, &lockSource, &hasOrder)

		if _, ok := zonesMap[zid]; !ok {
			zonesMap[zid] = &zoneInfo{ID: zid, Name: map[string]string{"uz": zname}, SortOrder: zso, Tables: []tableInfo{}}
			zonesOrder = append(zonesOrder, zid)
		}

		if tsku != nil {
			ti := tableInfo{SKU: *tsku, Label: valOrEmpty(tlabel), Seats: valOrZero(tseats), Status: valOrEmpty(tstatus), Number: valOrZero(tnumber), HasActiveOrder: hasOrder == 1}
			if lockName != nil {
				ti.LockedBy = map[string]string{"name": *lockName, "source": valOrEmpty(lockSource)}
			}
			zonesMap[zid].Tables = append(zonesMap[zid].Tables, ti)
		}
	}

	zones := make([]zoneInfo, 0, len(zonesOrder))
	for _, id := range zonesOrder {
		zones = append(zones, *zonesMap[id])
	}
	jsonResponse(w, 200, zones)
}

func valOrEmpty(s *string) string {
	if s != nil {
		return *s
	}
	return ""
}
func valOrZero(n *int) int {
	if n != nil {
		return *n
	}
	return 0
}

// ============ GET /api/orders ============
// Query params:
//   status: "active" (default), "all", "completed", "cancelled"
//   date:   "YYYY-MM-DD" — optional, filters by DATE(created_at)

func handleGetOrders(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "active"
	}
	date := strings.TrimSpace(r.URL.Query().Get("date"))

	var conditions []string
	var args []interface{}
	argIdx := 0

	if status == "active" {
		conditions = append(conditions, "status NOT IN ('completed', 'cancelled')")
	} else if status != "all" {
		argIdx++
		conditions = append(conditions, fmt.Sprintf("status = $%d", argIdx))
		args = append(args, status)
	}

	if date != "" {
		argIdx++
		conditions = append(conditions, fmt.Sprintf("DATE(created_at) = $%d::date", argIdx))
		args = append(args, date)
	}

	baseSelect := "SELECT id, order_number, type, table_sku, status, items, subtotal, service_fee, delivery_fee, discount, total, payment_method, payment_status, source, customer_name, customer_phone, delivery, note, created_at, updated_at FROM orders"

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = " WHERE " + strings.Join(conditions, " AND ")
	}

	// Bir kunlik filterda limit qo'ymaymiz, aks holda 100 ta cheklash
	limitClause := ""
	if date == "" && status != "active" {
		limitClause = " LIMIT 100"
	}

	query := baseSelect + whereClause + " ORDER BY created_at DESC" + limitClause

	rows, err := db.Pool.Query(r.Context(), query, args...)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	orders := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var orderNum, typ, st, payStatus, source string
		var items json.RawMessage
		var tsku, payMethod, custName, custPhone, note *string
		var delivery *json.RawMessage
		var sub, sf, df, disc, total int
		var createdAt, updatedAt time.Time

		err := rows.Scan(&id, &orderNum, &typ, &tsku, &st, &items, &sub, &sf, &df, &disc, &total,
			&payMethod, &payStatus, &source, &custName, &custPhone, &delivery, &note, &createdAt, &updatedAt)
		if err != nil {
			continue
		}

		o := map[string]interface{}{
			"order_number": orderNum, "type": typ, "table_sku": tsku, "status": st,
			"items": items, "subtotal": sub, "service_fee": sf, "delivery_fee": df,
			"discount": disc, "total": total, "payment_method": payMethod,
			"payment_status": payStatus, "source": source,
			"customer_name": custName, "customer_phone": custPhone,
			"note": note, "created_at": createdAt.Format(time.RFC3339), "updated_at": updatedAt.Format(time.RFC3339),
		}
		if delivery != nil {
			o["delivery"] = delivery
		}
		orders = append(orders, o)
	}
	jsonResponse(w, 200, orders)
}

// ============ GET /api/shift/current ============

func handleGetShift(w http.ResponseWriter, r *http.Request) {
	var id, openingCash int
	var date, status string
	var openedBy json.RawMessage
	var openedAt time.Time
	err := db.Pool.QueryRow(r.Context(), "SELECT id, date, opened_by, opened_at, opening_cash, status FROM shifts WHERE status = 'open' LIMIT 1").
		Scan(&id, &date, &openedBy, &openedAt, &openingCash, &status)
	if err != nil {
		jsonResponse(w, 200, map[string]interface{}{"id": nil, "status": "no_shift", "message": "Smena ochilmagan"})
		return
	}

	ctx := r.Context()
	// Smena ochilgan vaqtdan keyingi buyurtmalar
	shiftOpenedAt := openedAt.Format(time.RFC3339)

	var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, expensesTotal int
	var dineInCount, takeawayCount, deliveryCount int
	var dineInTotal, takeawayTotal, deliveryTotal int

	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", shiftOpenedAt).Scan(&totalOrders)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", shiftOpenedAt).Scan(&totalRevenue)
	// Usul bo'yicha tushum — split to'lovlar ham o'z bucketlariga qo'shiladi
	payRaw, payErr := db.PaymentTotalsSince(ctx, shiftOpenedAt)
	pay := db.PaymentTotalsOrZero(ctx, payRaw, payErr, "shift/current")
	cashRev, cardRev, paymeRev, clickRev = pay["cash"], pay["card"], pay["payme"], pay["click"]
	// `date = bugun` sharti OLIB TASHLANDI: soat 00:00 dan keyin bugungi sana
	// o'zgarib, kechqurun yozilgan xarajatlar hisobdan tushib ketardi va
	// "kutilayotgan naqd" birdan ko'tarilib ketardi. Smena hisoboti esa
	// faqat `created_at >= ochilish` bo'yicha hisoblanadi — endi ikkalasi mos.
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE created_at >= $1", shiftOpenedAt).Scan(&expensesTotal)

	// By order type
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'dine_in'", shiftOpenedAt).Scan(&dineInCount, &dineInTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'takeaway'", shiftOpenedAt).Scan(&takeawayCount, &takeawayTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'delivery'", shiftOpenedAt).Scan(&deliveryCount, &deliveryTotal)

	// Active S/D count
	var activeSD int
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')", shiftOpenedAt).Scan(&activeSD)

	jsonResponse(w, 200, map[string]interface{}{
		"id": id, "date": date, "status": "open",
		"opened_by": openedBy, "opened_at": openedAt.Format(time.RFC3339), "opening_cash": openingCash,
		"current_stats": map[string]interface{}{
			"total_orders":  totalOrders,
			"total_revenue": totalRevenue,
			"by_payment": map[string]int{
				"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev,
			},
			"by_type": map[string]interface{}{
				"dine_in":  map[string]int{"count": dineInCount, "total": dineInTotal},
				"takeaway": map[string]int{"count": takeawayCount, "total": takeawayTotal},
				"delivery": map[string]int{"count": deliveryCount, "total": deliveryTotal},
			},
			"expenses_total":        expensesTotal,
			"cash_revenue":          cashRev,
			"current_expected_cash": openingCash + cashRev - expensesTotal,
			"active_sd_orders":      activeSD,
		},
	})
}

// ============ POST /api/auth/login ============

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}

	rec, err := loadAuthByPhone(r.Context(), req.Phone)
	if err != nil || !verifyAuthPIN(r.Context(), rec, req.PIN) {
		jsonError(w, 401, "invalid_credentials", "Telefon raqam yoki PIN noto'g'ri")
		return
	}
	user := rec.user

	// Build permissions
	perms := middleware.RolePermissions[user.Role]
	if user.CustomPermissions != nil {
		var custom map[string][]string
		if json.Unmarshal([]byte(*user.CustomPermissions), &custom) == nil {
			merged := make(map[string][]string)
			for k, v := range perms {
				merged[k] = v
			}
			for k, v := range custom {
				merged[k] = v
			}
			perms = merged
		}
	}
	permsJSON, _ := json.Marshal(perms)

	claims := &middleware.TokenClaims{
		UserID:      user.ID,
		Name:        user.Name,
		Role:        user.Role,
		Permissions: permsJSON,
	}
	token, err := middleware.GenerateToken(claims)
	if err != nil {
		jsonError(w, 500, "token_error", "Token yaratishda xato")
		return
	}
	// `updated_at` ham suriladi: node'lar orasidagi "kim oxirgi yozdi"
	// qoidasi shunga qaraydi. Aks holda ikki node bir vaqtda kirishni
	// qayd etsa, qator ikki bazada abadiy farq qilib qolardi.
	db.Pool.Exec(r.Context(), "UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1", user.ID)

	jsonResponse(w, 200, models.LoginResponse{
		Token: token,
		User:  models.UserInfo{ID: user.ID, Name: user.Name, Role: user.Role, Permissions: permsJSON},
	})
}

// ============ POST /api/auth/pin-login ============

func handlePinLogin(w http.ResponseWriter, r *http.Request) {
	var req models.PinLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}

	if len(req.PIN) != 4 {
		jsonError(w, 400, "bad_request", "PIN 4 xonali bo'lishi kerak")
		return
	}

	rec, err := loadAuthByPIN(r.Context(), req.PIN)
	if err != nil || !verifyAuthPIN(r.Context(), rec, req.PIN) {
		jsonError(w, 401, "invalid_credentials", "PIN noto'g'ri")
		return
	}
	user := rec.user

	perms := middleware.RolePermissions[user.Role]
	if user.CustomPermissions != nil {
		var custom map[string][]string
		if json.Unmarshal([]byte(*user.CustomPermissions), &custom) == nil {
			merged := make(map[string][]string)
			for k, v := range perms {
				merged[k] = v
			}
			for k, v := range custom {
				merged[k] = v
			}
			perms = merged
		}
	}
	permsJSON, _ := json.Marshal(perms)

	claims := &middleware.TokenClaims{
		UserID:      user.ID,
		Name:        user.Name,
		Role:        user.Role,
		Permissions: permsJSON,
	}
	token, err := middleware.GenerateToken(claims)
	if err != nil {
		jsonError(w, 500, "token_error", "Token yaratishda xato")
		return
	}
	// `updated_at` ham suriladi: node'lar orasidagi "kim oxirgi yozdi"
	// qoidasi shunga qaraydi. Aks holda ikki node bir vaqtda kirishni
	// qayd etsa, qator ikki bazada abadiy farq qilib qolardi.
	db.Pool.Exec(r.Context(), "UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1", user.ID)

	jsonResponse(w, 200, models.LoginResponse{
		Token: token,
		User:  models.UserInfo{ID: user.ID, Name: user.Name, Role: user.Role, Permissions: permsJSON},
	})
}

// ============ POST /api/shift/open ============

func handleShiftOpen(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "shifts", "open") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var existingStatus string
	if db.Pool.QueryRow(r.Context(), "SELECT status FROM shifts WHERE status = 'open'").Scan(&existingStatus) == nil {
		jsonError(w, 400, "shift_already_open", "Smena allaqachon ochiq")
		return
	}

	var req models.ShiftOpenRequest
	json.NewDecoder(r.Body).Decode(&req)
	if req.OpeningCash < 0 {
		jsonError(w, 400, "bad_request", "Kassadagi pul manfiy bo'lmaydi")
		return
	}

	now := time.Now().UTC()
	openedBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})

	var shiftID int64
	// Xato TEKSHIRILADI. Ilgari e'tiborsiz qoldirilardi: baza xatosida
	// handler "shift_id: 0" bilan 200 qaytarib, `shift:opened` e'lon qilardi
	// — POS smena ochiq deb o'ylab, chek yaratmoqchi bo'lganda esa
	// "Smena ochilmagan" xatosini olardi.
	//
	// Unikal indeks (idx_shifts_single_open) tufayli ikkinchi parallel
	// so'rov ham aynan shu yerda to'xtaydi.
	if err := db.Pool.QueryRow(r.Context(), "INSERT INTO shifts (date, opened_by, opened_at, opening_cash, status) VALUES ($1, $2, $3, $4, 'open') RETURNING id",
		now.Format("2006-01-02"), string(openedBy), now.Format(time.RFC3339), req.OpeningCash).Scan(&shiftID); err != nil {
		jsonError(w, 409, "shift_already_open", "Smena ochilmadi — allaqachon ochiq bo'lishi mumkin")
		return
	}

	// Smena boshidagi qoldiq surati — yopilishda solishtirish (recon) uchun
	db.Pool.Exec(r.Context(), `INSERT INTO shift_stock_snapshots (shift_id, product_id, count)
		SELECT $1, product_id, count FROM stocks ON CONFLICT DO NOTHING`, shiftID)

	resp := map[string]interface{}{
		"shift_id": shiftID, "date": now.Format("2006-01-02"), "status": "open",
		"opened_by": map[string]interface{}{"user_id": claims.UserID, "name": claims.Name},
		"opened_at": now.Format(time.RFC3339), "opening_cash": req.OpeningCash,
	}
	wss.H.BroadcastEvent("shift:opened", resp)
	addSyncQueue("shift:opened", resp)

	jsonResponse(w, 200, resp)
}

// ============ POST /api/shift/close ============

func handleShiftClose(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "shifts", "close") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	// Band stollar tekshirish
	var occupiedTables int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM tables WHERE status = 'occupied'").Scan(&occupiedTables)
	if occupiedTables > 0 {
		jsonError(w, 400, "occupied_tables", fmt.Sprintf("%d ta band stol bor. Avval stollarni yoping.", occupiedTables))
		return
	}

	// Saboy/dostafka tekshirish
	var activeSDCount int
	// Sana filtri OLIB TASHLANDI: 23:50 da ochilgan saboy/dostafka 00:10 da
	// smenani to'smasdi va keyin hech qaysi smena oynasiga tushmasdi.
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')").Scan(&activeSDCount)
	if activeSDCount > 0 {
		jsonError(w, 400, "active_orders_exist", fmt.Sprintf("%d ta yopilmagan saboy/dostafka buyurtma bor", activeSDCount))
		return
	}

	var req models.ShiftCloseRequest
	json.NewDecoder(r.Body).Decode(&req)
	if req.ActualCash < 0 {
		jsonError(w, 400, "bad_request", "Kassadagi pul manfiy bo'lmaydi")
		return
	}

	var shiftID, openingCash int
	var shiftOpenedAt time.Time
	err := db.Pool.QueryRow(r.Context(), "SELECT id, opening_cash, opened_at FROM shifts WHERE status = 'open'").
		Scan(&shiftID, &openingCash, &shiftOpenedAt)
	if err != nil {
		jsonError(w, 400, "no_open_shift", "Ochiq smena yo'q")
		return
	}

	// Hisobot smena OYNASI bo'yicha (kalendar kuni bo'yicha emas)
	summary, err := wss.CalculateShiftSummarySince(shiftOpenedAt, openingCash, req.ActualCash)
	if err != nil {
		// Hisobot chiqmasa smena YOPILMAYDI (qarang: CalculateShiftSummarySince).
		jsonError(w, 500, "summary_failed", "Smena hisoboti hisoblanmadi — qayta urinib ko'ring")
		return
	}

	now := time.Now().UTC().Format(time.RFC3339)
	closedBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})
	summaryJSON, _ := json.Marshal(summary)

	if tag, err := db.Pool.Exec(r.Context(), "UPDATE shifts SET closed_by = $1, closed_at = $2, closing_cash = $3, status = 'closed', summary = $4 WHERE id = $5 AND status = 'open'",
		string(closedBy), now, req.ActualCash, string(summaryJSON), shiftID); err != nil || tag.RowsAffected() == 0 {
		jsonError(w, 500, "db_error", "Smena yopilmadi — qayta urinib ko'ring")
		return
	}

	resp := map[string]interface{}{"shift_id": shiftID, "status": "closed", "summary": summary}
	wss.H.BroadcastEvent("shift:closed", resp)
	addSyncQueue("shift:closed", resp)

	jsonResponse(w, 200, resp)
}

// ============ POST /api/expense ============

func handleCreateExpense(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "expenses", "create") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req models.ExpenseCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	// Ilgari hech qanday tekshiruv yo'q edi: manfiy summa kassa hisobini
	// KO'PAYTIRIB yuborardi (expected_cash = ochilish + naqd - xarajat),
	// mavjud bo'lmagan kategoriya esa FK xatosiga uchrab, xato ham
	// tekshirilmagani uchun "id: 0" bilan muvaffaqiyat qaytarardi.
	if req.Amount <= 0 {
		jsonError(w, 400, "bad_request", "Summa 0 dan katta bo'lishi kerak")
		return
	}
	var catName string
	if db.Pool.QueryRow(r.Context(),
		"SELECT name_uz FROM expense_categories WHERE id = $1 AND status = 'active'",
		req.CategoryID).Scan(&catName) != nil {
		jsonError(w, 400, "bad_request", "Xarajat kategoriyasi topilmadi")
		return
	}

	today := time.Now().Format("2006-01-02")
	createdBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})

	var id int64
	if err := db.Pool.QueryRow(r.Context(), "INSERT INTO expenses (category_id, amount, description, date, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id",
		req.CategoryID, req.Amount, req.Description, today, string(createdBy)).Scan(&id); err != nil {
		jsonError(w, 500, "db_error", "Xarajat saqlanmadi: "+err.Error())
		return
	}

	resp := map[string]interface{}{
		"id": id, "category_id": req.CategoryID, "category_name": map[string]string{"uz": catName},
		"amount": req.Amount, "description": req.Description, "date": today,
		"created_by": map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role},
		"created_at": time.Now().UTC().Format(time.RFC3339),
	}
	addSyncQueue("expense:created", resp)

	jsonResponse(w, 200, resp)
}

// ============ GET /api/expense-categories ============

func handleGetExpenseCategories(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), "SELECT id, name_uz, name_ru, name_tr, sort_order FROM expense_categories WHERE status = 'active' ORDER BY sort_order")
	if err != nil {
		jsonResponse(w, 200, []interface{}{})
		return
	}
	defer rows.Close()

	cats := []map[string]interface{}{}
	for rows.Next() {
		var id, sortOrder int
		var uz, ru, tr string
		rows.Scan(&id, &uz, &ru, &tr, &sortOrder)
		cats = append(cats, map[string]interface{}{
			"id":         id,
			"name_uz":    uz,
			"name_ru":    ru,
			"name_tr":    tr,
			"sort_order": sortOrder,
		})
	}
	jsonResponse(w, 200, cats)
}

// ============ POST /api/expense-category ============

func handleCreateExpenseCategory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "expense_categories", "create") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}
	var req struct {
		NameUz string `json:"name_uz"`
		NameRu string `json:"name_ru"`
		NameTr string `json:"name_tr"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.NameUz == "" {
		jsonError(w, 400, "bad_request", "name_uz kerak")
		return
	}

	var id int
	var maxSort int
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(MAX(sort_order),0) FROM expense_categories").Scan(&maxSort)
	db.Pool.QueryRow(r.Context(), "INSERT INTO expense_categories (name_uz, name_ru, name_tr, sort_order, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id",
		req.NameUz, req.NameRu, req.NameTr, maxSort+1, claims.UserID).Scan(&id)

	// expenses.category_id -> expense_categories(id) FK. Kategoriya sync
	// qilinmasa, unga bog'liq "expense:created" replikada FK xatosi bilan
	// jimgina yo'qoladi — shuning uchun kategoriya ham navbatga qo'yiladi.
	resp := map[string]interface{}{"id": id, "name_uz": req.NameUz, "name_ru": req.NameRu,
		"name_tr": req.NameTr, "sort_order": maxSort + 1}
	addSyncQueue("expense_category:created", resp)

	jsonResponse(w, 200, resp)
}

// ============ DELETE /api/expense-category/:id ============

func handleDeleteExpenseCategory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "expense_categories", "delete") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}
	id := chi.URLParam(r, "id")
	db.Pool.Exec(r.Context(), "UPDATE expense_categories SET status = 'inactive' WHERE id = $1", id)
	jsonResponse(w, 200, map[string]interface{}{"message": "O'chirildi"})
}

// ============ GET /api/finance/daily ============

func handleFinanceDaily(w http.ResponseWriter, r *http.Request) {
	date := r.URL.Query().Get("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}
	if !canReadFinanceDate(r, date) {
		jsonError(w, 403, "forbidden", "Faqat bugungi moliyani ko'rishga ruxsat bor")
		return
	}

	var totalOrders, cancelledOrders, expTotal int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_status = 'paid'", date).Scan(&totalOrders)
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'cancelled'", date).Scan(&cancelledOrders)
	// Usul bo'yicha tushum — split to'lovlar ham o'z bucketlariga qo'shiladi
	payRaw, payErr := db.PaymentTotalsByDate(r.Context(), date)
	if payErr != nil {
		jsonError(w, 500, "db_error", "Moliya hisobotini o'qib bo'lmadi: "+payErr.Error())
		return
	}
	pay := payRaw
	cashRev, cardRev, paymeRev, clickRev, otherRev := pay["cash"], pay["card"], pay["payme"], pay["click"], pay["other"]
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date = $1", date).Scan(&expTotal)

	totalRev := cashRev + cardRev + paymeRev + clickRev + otherRev

	// Expenses by category
	eRows, _ := db.Pool.Query(r.Context(), "SELECT e.category_id, ec.name_uz, COALESCE(SUM(e.amount),0), COUNT(*) FROM expenses e JOIN expense_categories ec ON e.category_id = ec.id WHERE e.date = $1 GROUP BY e.category_id, ec.name_uz", date)
	defer eRows.Close()
	expCats := []map[string]interface{}{}
	for eRows.Next() {
		var cid, total, cnt int
		var name string
		eRows.Scan(&cid, &name, &total, &cnt)
		expCats = append(expCats, map[string]interface{}{"category_id": cid, "category_name": map[string]string{"uz": name}, "total": total, "count": cnt})
	}

	jsonResponse(w, 200, map[string]interface{}{
		"date": date,
		"income": map[string]interface{}{
			"total_orders": totalOrders, "cancelled_orders": cancelledOrders, "total_revenue": totalRev,
			"by_payment_method": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev, "other": otherRev},
		},
		"expenses": map[string]interface{}{"total": expTotal, "by_category": expCats},
		"profit":   map[string]int{"gross_revenue": totalRev, "total_expenses": expTotal, "net_profit": totalRev - expTotal},
	})
}

// ============ GET /api/finance/daily/expenses ============

func handleFinanceExpenses(w http.ResponseWriter, r *http.Request) {
	date := r.URL.Query().Get("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}
	if !canReadFinanceDate(r, date) {
		jsonError(w, 403, "forbidden", "Faqat bugungi xarajatlarni ko'rishga ruxsat bor")
		return
	}

	catFilter := r.URL.Query().Get("category_id")
	var query string
	var qargs []interface{}
	if catFilter != "" {
		query = "SELECT e.id, e.category_id, ec.name_uz, e.amount, e.description, e.created_by, e.created_at FROM expenses e JOIN expense_categories ec ON e.category_id = ec.id WHERE e.date = $1 AND e.category_id = $2 ORDER BY e.created_at"
		qargs = []interface{}{date, catFilter}
	} else {
		query = "SELECT e.id, e.category_id, ec.name_uz, e.amount, e.description, e.created_by, e.created_at FROM expenses e JOIN expense_categories ec ON e.category_id = ec.id WHERE e.date = $1 ORDER BY e.created_at"
		qargs = []interface{}{date}
	}
	rows, err := db.Pool.Query(r.Context(), query, qargs...)
	if err != nil {
		jsonResponse(w, 200, []interface{}{})
		return
	}
	defer rows.Close()

	exps := []map[string]interface{}{}
	for rows.Next() {
		var id, cid, amt int
		var catName, desc, createdBy string
		var createdAt time.Time
		rows.Scan(&id, &cid, &catName, &amt, &desc, &createdBy, &createdAt)
		var cb json.RawMessage
		json.Unmarshal([]byte(createdBy), &cb)
		exps = append(exps, map[string]interface{}{
			"id": id, "category_id": cid, "category_name": map[string]string{"uz": catName},
			"amount": amt, "description": desc, "created_by": cb, "created_at": createdAt.Format(time.RFC3339),
		})
	}
	jsonResponse(w, 200, exps)
}

// ============ GET /api/users ============

func handleGetUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), "SELECT id, name, phone, role, custom_permissions, status, created_at FROM users WHERE status = 'active' ORDER BY id")
	if err != nil {
		jsonResponse(w, 200, []interface{}{})
		return
	}
	defer rows.Close()
	users := []map[string]interface{}{}
	for rows.Next() {
		var id int
		var name, phone, role, status string
		var cp *json.RawMessage
		var createdAt time.Time
		rows.Scan(&id, &name, &phone, &role, &cp, &status, &createdAt)
		u := map[string]interface{}{"id": id, "name": name, "phone": phone, "role": role, "status": status, "created_at": createdAt.Format(time.RFC3339)}
		if cp != nil {
			u["custom_permissions"] = cp
		}
		users = append(users, u)
	}
	jsonResponse(w, 200, users)
}

// ============ PUT /api/product/:id ============

// ============ POST /api/product ============

func handleCreateProduct(w http.ResponseWriter, r *http.Request) {
	var p struct {
		NameUz        string `json:"name_uz"`
		NameRu        string `json:"name_ru"`
		NameTr        string `json:"name_tr"`
		DescUz        string `json:"description_uz"`
		DescRu        string `json:"description_ru"`
		DescTr        string `json:"description_tr"`
		Price         int    `json:"price"`
		OldPrice      *int   `json:"old_price"`
		CategoryID    int    `json:"category_id"`
		Status        string `json:"status"`
		SortOrder     int    `json:"sort_order"`
		ProductType   string `json:"product_type"`
		IsRecommended bool   `json:"is_recommended"`
	}
	json.NewDecoder(r.Body).Decode(&p)

	if p.NameUz == "" && p.NameRu == "" {
		jsonError(w, 400, "bad_request", "Nom kerak (uz yoki ru)")
		return
	}
	if p.CategoryID == 0 {
		jsonError(w, 400, "bad_request", "Kategoriya kerak")
		return
	}
	// Manfiy narx chek summasini KAMAYTIRARDI: bunday mahsulot qo'shilgan
	// har bir chekdan pul "chegirilardi".
	if p.Price < 0 || (p.OldPrice != nil && *p.OldPrice < 0) {
		jsonError(w, 400, "bad_request", "Narx manfiy bo'lishi mumkin emas")
		return
	}
	if p.Status != "" && !allowedProductStatus[p.Status] {
		jsonError(w, 400, "bad_request", "Status noto'g'ri")
		return
	}
	if p.Status == "" {
		p.Status = "active"
	}
	if p.ProductType != "ready" {
		p.ProductType = "cooked" // asosiy tur — tayyorlanadigan (retseptli)
	}

	var id int
	err := db.Pool.QueryRow(r.Context(),
		`INSERT INTO products (name_uz, name_ru, name_tr, description_uz, description_ru, description_tr, price, old_price, category_id, status, sort_order, product_type, is_recommended, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,NOW(),NOW()) RETURNING id`,
		p.NameUz, p.NameRu, p.NameTr, p.DescUz, p.DescRu, p.DescTr, p.Price, p.OldPrice, p.CategoryID, p.Status, p.SortOrder, p.ProductType, p.IsRecommended).Scan(&id)
	if err != nil {
		jsonError(w, 500, "db_error", "Mahsulot yaratishda xato: "+err.Error())
		return
	}

	// Har yangi mahsulot 0 qoldiq bilan boshlanadi — bazaga qo'shilgandagina sotiladi
	db.Pool.Exec(r.Context(),
		"INSERT INTO stocks (product_id, count) VALUES ($1, 0) ON CONFLICT (product_id) DO NOTHING", id)

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_created"})
	syncProductSnapshot(r.Context(), id)

	jsonResponse(w, 201, map[string]interface{}{"message": "Mahsulot yaratildi", "id": id})
}

// ============ DELETE /api/product/:id ============

func handleDeleteProduct(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	db.Pool.Exec(r.Context(), "UPDATE products SET status = 'deleted', updated_at = NOW() WHERE id = $1", id)

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_deleted"})
	syncProductSnapshot(r.Context(), id)

	jsonResponse(w, 200, map[string]interface{}{"message": "Mahsulot o'chirildi", "id": id})
}

// ============ PUT /api/product/:id ============

func handleUpdateProduct(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))

	var p struct {
		NameUz           *string `json:"name_uz"`
		NameRu           *string `json:"name_ru"`
		NameTr           *string `json:"name_tr"`
		DescUz           *string `json:"description_uz"`
		DescRu           *string `json:"description_ru"`
		DescTr           *string `json:"description_tr"`
		Price            *int    `json:"price"`
		OldPrice         *int    `json:"old_price"`
		CategoryID       *int    `json:"category_id"`
		Status           *string `json:"status"`
		IsRecommended    *bool   `json:"is_recommended"`
		PrinterStationID *int    `json:"printer_station_id"`
		ProductType      *string `json:"product_type"`
	}
	json.NewDecoder(r.Body).Decode(&p)

	ctx := r.Context()
	if id <= 0 {
		jsonError(w, 400, "bad_request", "Mahsulot ID noto'g'ri")
		return
	}
	if p.Price != nil && *p.Price < 0 {
		jsonError(w, 400, "bad_request", "Narx manfiy bo'lishi mumkin emas")
		return
	}
	if p.Status != nil && !allowedProductStatus[*p.Status] {
		jsonError(w, 400, "bad_request", "Status noto'g'ri (active/inactive/deleted)")
		return
	}

	// BITTA UPDATE. Ilgari har bir maydon uchun alohida so'rov ketardi:
	//   - 11 ta borish-kelish (atomar emas — yarmi o'tib, yarmi qolishi mumkin);
	//   - replikatsiya triggeri har biriga ALOHIDA event yozardi, ya'ni bitta
	//     tahrir 11 ta sync eventiga aylanib, ikkinchi node'ga 11 marta
	//     "menu:outdated" yuborilardi va ilova menyuni 11 marta qayta yuklardi.
	set := []string{"updated_at = NOW()"}
	args := []interface{}{}
	add := func(expr string, val interface{}) {
		args = append(args, val)
		set = append(set, fmt.Sprintf("%s = $%d", expr, len(args)))
	}
	if p.ProductType != nil && (*p.ProductType == "cooked" || *p.ProductType == "ready") {
		add("product_type", *p.ProductType)
	}
	if p.NameUz != nil {
		add("name_uz", *p.NameUz)
	}
	if p.NameRu != nil {
		add("name_ru", *p.NameRu)
	}
	if p.NameTr != nil {
		add("name_tr", *p.NameTr)
	}
	if p.DescUz != nil {
		add("description_uz", *p.DescUz)
	}
	if p.DescRu != nil {
		add("description_ru", *p.DescRu)
	}
	if p.DescTr != nil {
		add("description_tr", *p.DescTr)
	}
	if p.Price != nil {
		add("price", *p.Price)
	}
	if p.OldPrice != nil {
		// 0 — "chegirmani olib tashlash" degani. Ilgari buni ifodalashning
		// iloji yo'q edi: JSON `null` Go tomonda "yuborilmadi" bo'lib
		// tushunilardi va chizilgan eski narx menyuda abadiy qolib ketardi.
		if *p.OldPrice == 0 {
			set = append(set, "old_price = NULL")
		} else {
			add("old_price", *p.OldPrice)
		}
	}
	if p.CategoryID != nil {
		add("category_id", *p.CategoryID)
	}
	if p.Status != nil {
		add("status", *p.Status)
	}
	// `is_recommended` klientdan kelardi, lekin serverda YOZILMASDI: admin
	// mahsulotni "tavsiya etiladi" qilib belgilaydi, saqlash 200 qaytaradi,
	// ekran yangilangach bayroq jimgina o'chib ketardi.
	if p.IsRecommended != nil {
		add("is_recommended", *p.IsRecommended)
	}
	if p.PrinterStationID != nil {
		if *p.PrinterStationID == 0 {
			set = append(set, "printer_station_id = NULL")
		} else {
			add("printer_station_id", *p.PrinterStationID)
		}
	}
	if len(set) == 1 {
		jsonError(w, 400, "bad_request", "O'zgartirish uchun maydon yuborilmadi")
		return
	}

	args = append(args, id)
	if _, err := db.Pool.Exec(ctx,
		fmt.Sprintf("UPDATE products SET %s WHERE id = $%d", strings.Join(set, ", "), len(args)),
		args...); err != nil {
		jsonError(w, 500, "db_error", "Mahsulot yangilanmadi: "+err.Error())
		return
	}

	// menu_version++
	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_updated"})
	syncProductSnapshot(ctx, id)

	jsonResponse(w, 200, map[string]interface{}{"message": "Mahsulot yangilandi", "id": id})
}

// ============ POST /api/stock/set ============

func handleStockSetHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProductID int `json:"product_id"`
		Count     int `json:"count"`
	}
	// Ilgari bu yerda HECH QANDAY tekshiruv yo'q edi: buzuq JSON
	// `(product_id=0, count=0)` qatorini yaratardi, manfiy son esa qoldiqni
	// minusga tushirib, mahsulotni QR menyudan yashirar va pishirish
	// limitini buzardi. Natija ham tekshirilmasdi — 200 qaytardi-yu, bazaga
	// hech narsa yozilmasligi mumkin edi.
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.ProductID <= 0 || req.Count < 0 || req.Count > maxStockArrivalQty {
		jsonError(w, 400, "bad_request",
			fmt.Sprintf("product_id va count (0..%d) kerak", maxStockArrivalQty))
		return
	}
	var exists bool
	if db.Pool.QueryRow(r.Context(),
		"SELECT EXISTS(SELECT 1 FROM products WHERE id = $1 AND status <> 'deleted')",
		req.ProductID).Scan(&exists) != nil || !exists {
		jsonError(w, 404, "not_found", "Mahsulot topilmadi")
		return
	}

	if _, err := db.Pool.Exec(r.Context(),
		"INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, NOW()) ON CONFLICT (product_id) DO UPDATE SET count = $2, updated_at = NOW()",
		req.ProductID, req.Count); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	wss.BroadcastStock(req.ProductID, &req.Count, "manual_set")

	jsonResponse(w, 200, map[string]interface{}{"message": "Stock yangilandi", "product_id": req.ProductID, "count": req.Count})
}

// ============ POST /api/stock/remove ============

func handleStockRemoveHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProductID int `json:"product_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	db.Pool.Exec(r.Context(), "DELETE FROM stocks WHERE product_id = $1", req.ProductID)
	wss.BroadcastStock(req.ProductID, nil, "removed")

	jsonResponse(w, 200, map[string]interface{}{"message": "Limit olib tashlandi (cheksiz)", "product_id": req.ProductID})
}

// ============ POST /api/reorder ============

func handleReorder(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Categories []struct {
			ID        int `json:"id"`
			SortOrder int `json:"sort_order"`
		} `json:"categories"`
		Products []struct {
			ID         int `json:"id"`
			SortOrder  int `json:"sort_order"`
			CategoryID int `json:"category_id"`
		} `json:"products"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	ctx := r.Context()

	for _, c := range req.Categories {
		db.Pool.Exec(ctx, "UPDATE categories SET sort_order = $1 WHERE id = $2", c.SortOrder, c.ID)
	}
	for _, p := range req.Products {
		db.Pool.Exec(ctx, "UPDATE products SET sort_order = $1, category_id = $2, updated_at = NOW() WHERE id = $3", p.SortOrder, p.CategoryID, p.ID)
	}

	// menu_version++
	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "reorder"})

	jsonResponse(w, 200, map[string]interface{}{"message": "Tartib yangilandi"})
}

// ============ POST /api/upload/product-image/:id ============

func handleUploadProductImage(w http.ResponseWriter, r *http.Request) {
	productID, _ := strconv.Atoi(chi.URLParam(r, "id"))

	// Max 10MB
	r.ParseMultipartForm(10 << 20)

	file, header, err := r.FormFile("image")
	if err != nil {
		jsonError(w, 400, "bad_request", "Rasm fayli kerak (image field)")
		return
	}
	defer file.Close()

	// Fayl kengaytmasi
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
		jsonError(w, 400, "bad_format", "Faqat jpg, png, webp")
		return
	}

	// Eski rasmlarni o'chirish
	ctx := r.Context()
	var oldMedia json.RawMessage
	db.Pool.QueryRow(ctx, "SELECT media FROM products WHERE id = $1", productID).Scan(&oldMedia)
	if oldMedia != nil {
		var mediaList []map[string]interface{}
		json.Unmarshal(oldMedia, &mediaList)
		for _, m := range mediaList {
			if url, ok := m["url"].(string); ok {
				oldPath := "." + url // ./uploads/products/1.jpg
				os.Remove(oldPath)
			}
		}
	}

	// Papka yaratish
	uploadDir := "./uploads/products"
	os.MkdirAll(uploadDir, 0755)

	// Fayl nomi: product_id + timestamp
	fileName := fmt.Sprintf("%d_%d%s", productID, time.Now().Unix(), ext)
	filePath := filepath.Join(uploadDir, fileName)

	// Saqlash
	dst, err := os.Create(filePath)
	if err != nil {
		jsonError(w, 500, "save_error", "Faylni saqlashda xato")
		return
	}
	defer dst.Close()
	io.Copy(dst, file)

	// URL
	imageURL := fmt.Sprintf("/uploads/products/%s", fileName)

	// DB yangilash
	newMedia, _ := json.Marshal([]map[string]interface{}{
		{"type": "image", "url": imageURL, "sort_order": 1},
	})
	db.Pool.Exec(ctx, "UPDATE products SET media = $1, updated_at = NOW() WHERE id = $2", newMedia, productID)

	// menu_version++
	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_image_updated"})
	syncProductSnapshot(r.Context(), productID)

	jsonResponse(w, 200, map[string]interface{}{
		"message":    "Rasm yuklandi",
		"product_id": productID,
		"image_url":  imageURL,
	})
}

// ============ POST /api/order/close ============

func handleOrderClose(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "orders", "close") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req struct {
		TableSKU      string               `json:"table_sku"`
		OrderNumber   string               `json:"order_number"`
		PaymentMethod string               `json:"payment_method"`
		Discount      int                  `json:"discount"`
		Payments      []models.PaymentPart `json:"payments"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if req.OrderNumber == "" && req.TableSKU == "" {
		jsonError(w, 400, "bad_request", "order_number yoki table_sku kerak")
		return
	}
	// Manfiy chegirma summani OSHIRIB yuborardi: mijozdan menyu narxidan
	// ko'proq undirilardi va hisobotda "tushum" haqiqiy sotuvdan katta chiqardi.
	if req.Discount < 0 {
		jsonError(w, 400, "bad_request", "Chegirma manfiy bo'lishi mumkin emas")
		return
	}
	// Noma'lum to'lov usuli hisobot bucketlaridan tushib qolardi (qarang:
	// models.ValidPaymentMethod). Split bo'lsa usul quyida "split" ga o'zgaradi.
	if len(req.Payments) == 0 && !models.ValidPaymentMethod(req.PaymentMethod) {
		jsonError(w, 400, "bad_payment_method",
			"To'lov usuli noto'g'ri (cash, card, payme, click, other)")
		return
	}

	ctx := r.Context()
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(ctx)

	// Yopiladigan cheklar BIR MARTA, qulf bilan o'qiladi va keyin AYNAN shular
	// yopiladi.
	//
	// Ilgari avval SUM olinardi, keyin alohida `WHERE table_sku=... AND status
	// NOT IN (...)` bilan hammasi yopilardi. Ikkisi orasida ofitsiant yangi
	// chek qo'shsa, u ham "to'langan" bo'lib ketardi — mahsuloti pishirilib,
	// puli esa olinmasdi. Endi qulflangan ro'yxatdan tashqaridagi chek
	// TEGILMAYDI: u ochiq qoladi va kassir uni ko'radi.
	type openOrder struct {
		Number   string
		Total    int
		TableSKU *string
	}
	var (
		rows   pgx.Rows
		qerr   error
		orders []openOrder
	)
	if req.OrderNumber != "" {
		rows, qerr = tx.Query(ctx, `
			SELECT order_number, total, table_sku FROM orders
			WHERE order_number = $1 AND status NOT IN ('completed','cancelled')
			ORDER BY created_at DESC
			FOR UPDATE`, req.OrderNumber)
	} else {
		rows, qerr = tx.Query(ctx, `
			SELECT order_number, total, table_sku FROM orders
			WHERE table_sku = $1 AND status NOT IN ('completed','cancelled')
			ORDER BY created_at DESC
			FOR UPDATE`, req.TableSKU)
	}
	if qerr != nil {
		jsonError(w, 500, "db_error", qerr.Error())
		return
	}
	for rows.Next() {
		var o openOrder
		if err := rows.Scan(&o.Number, &o.Total, &o.TableSKU); err != nil {
			rows.Close()
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		orders = append(orders, o)
	}
	rowsErr := rows.Err()
	rows.Close()
	if rowsErr != nil {
		jsonError(w, 500, "db_error", rowsErr.Error())
		return
	}
	if len(orders) == 0 {
		jsonError(w, 404, "not_found", "Ochiq buyurtma topilmadi")
		return
	}

	totalSum := 0
	orderNumbers := make([]string, 0, len(orders))
	orderTotals := make(map[string]int, len(orders))
	tableSKUs := map[string]bool{}
	for _, o := range orders {
		totalSum += o.Total
		orderNumbers = append(orderNumbers, o.Number)
		orderTotals[o.Number] = o.Total
		if o.TableSKU != nil && *o.TableSKU != "" {
			tableSKUs[*o.TableSKU] = true
		}
	}
	orderCount := len(orders)

	// Chegirma jami summadan oshmasin — aks holda "0 so'mga yopish" cheksiz
	// ruxsat bo'lardi.
	if req.Discount > totalSum {
		jsonError(w, 400, "discount_too_big",
			fmt.Sprintf("Chegirma jami summadan (%d) katta bo'lishi mumkin emas", totalSum))
		return
	}
	newTotal := totalSum - req.Discount

	payMethod := req.PaymentMethod
	var paymentsJSON []byte
	if len(req.Payments) > 0 {
		if orderCount != 1 {
			jsonError(w, 400, "split_single_only", "Aralash to'lov faqat bitta chek uchun")
			return
		}
		if code, msg := models.ValidatePayments(req.Payments, newTotal); code != "" {
			jsonError(w, 400, code, msg)
			return
		}
		payMethod = "split"
		paymentsJSON, _ = json.Marshal(req.Payments)
	}

	// Chegirmani cheklar bo'ylab taqsimlab, HAR BIR chekni alohida yopamiz.
	remainingDiscount := req.Discount
	for _, number := range orderNumbers {
		share := remainingDiscount
		if share > orderTotals[number] {
			share = orderTotals[number]
		}
		if share < 0 {
			share = 0
		}
		remainingDiscount -= share
		if _, err := tx.Exec(ctx, `
			UPDATE orders
			SET payment_method=$1, payments=$2, payment_status='paid', status='completed',
			    discount=discount+$3, total=GREATEST(total-$3,0), updated_at=NOW()
			WHERE order_number=$4 AND status NOT IN ('completed','cancelled')`,
			payMethod, paymentsJSON, share, number); err != nil {
			jsonError(w, 500, "db_error", "Chek yopilmadi: "+err.Error())
			return
		}
	}

	// Stolni faqat unda BOSHQA ochiq chek qolmagan bo'lsa bo'shatamiz.
	// Ilgari order_number bo'yicha yopishda stol umuman bo'shatilmasdi —
	// stol "band" bo'lib qolib, smenani yopib bo'lmasdi.
	if req.TableSKU != "" {
		tableSKUs[req.TableSKU] = true
	}
	freed := []string{}
	for sku := range tableSKUs {
		var stillOpen int
		if err := tx.QueryRow(ctx,
			"SELECT COUNT(*) FROM orders WHERE table_sku=$1 AND status NOT IN ('completed','cancelled')",
			sku).Scan(&stillOpen); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		if stillOpen > 0 {
			continue
		}
		if _, err := tx.Exec(ctx, "UPDATE tables SET status='free' WHERE sku=$1", sku); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		if _, err := tx.Exec(ctx,
			"UPDATE qr_sessions SET status='closed', closed_at=NOW() WHERE table_sku=$1 AND status='active'",
			sku); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		freed = append(freed, sku)
	}

	if err := tx.Commit(ctx); err != nil {
		jsonError(w, 500, "db_error", "Chek yopilmadi: "+err.Error())
		return
	}

	// Sodiqlik ballari commit'dan KEYIN (o'z tranzaksiyasida, idempotent).
	for _, number := range orderNumbers {
		if err := crm.CompleteOrder(ctx, number); err != nil {
			log.Printf("CRM order %s: %v", number, err)
		}
	}

	// WSS broadcast.
	// order_number(lar) SHART: klient yopilgan chekni aynan shu bo'yicha faol
	// ro'yxatdan olib tashlaydi. Yuborilmagani uchun yopilgan cheklar POS'da
	// "faol" bo'lib qolib ketardi (smena davomida yig'ilib borardi).
	resp := map[string]interface{}{
		"total": newTotal, "payment_method": payMethod,
		"checks_closed": orderCount, "order_numbers": orderNumbers,
		"order_number": orderNumbers[0],
	}
	if req.TableSKU != "" {
		resp["table_sku"] = req.TableSKU
	}
	httpResp := map[string]interface{}{"message": "Buyurtma yopildi", "total": newTotal, "checks_closed": orderCount, "discount": req.Discount}
	if len(req.Payments) > 0 {
		resp["payments"] = req.Payments
		httpResp["payments"] = req.Payments
	}
	wss.H.BroadcastEvent("order:closed", resp)
	for _, sku := range freed {
		wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": sku, "status": "free"})
	}
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:closed", resp)

	jsonResponse(w, 200, httpResp)
}

// ============ POST /api/order/cancel ============

func handleOrderCancel(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "orders", "cancel") && !middleware.HasPermission(claims, "orders", "close") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req struct {
		OrderNumber string `json:"order_number"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.OrderNumber == "" {
		jsonError(w, 400, "bad_request", "order_number kerak")
		return
	}

	ctx := r.Context()
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(ctx)

	// `FOR UPDATE` — SHART. Ilgari holat qulfsiz o'qilib, keyin alohida
	// UPDATE bajarilardi (statussiz!). Ikki oqibati bor edi:
	//   - kassir ikki marta bossa (yoki ikki terminal bir chekni bekor qilsa)
	//     ikkalasi ham tekshiruvdan o'tib, qoldiq IKKI MARTA qaytarilardi —
	//     kechqurun omborda yo'q mahsulot "bor" bo'lib chiqardi;
	//   - bir kassir yopayotganda ikkinchisi bekor qilsa, ALLAQACHON TO'LANGAN
	//     chek "cancelled" bo'lib qolardi: pul kassada, sotuv esa hisobotdan
	//     yo'qolardi.
	var status, orderType string
	var tableSKU *string
	var itemsJSON []byte
	if err := tx.QueryRow(ctx,
		"SELECT status, type, table_sku, items FROM orders WHERE order_number = $1 FOR UPDATE",
		req.OrderNumber).Scan(&status, &orderType, &tableSKU, &itemsJSON); err != nil {
		jsonError(w, 404, "not_found", "Buyurtma topilmadi")
		return
	}
	if status == "completed" || status == "cancelled" {
		jsonError(w, 400, "already_closed", "Buyurtma allaqachon yopilgan")
		return
	}

	// Qoldiqni qaytarish — o'sha tranzaksiyada, yangi son RETURNING bilan.
	var items []struct {
		ProductID int `json:"product_id"`
		Quantity  int `json:"quantity"`
	}
	json.Unmarshal(itemsJSON, &items)
	restored := map[int]int{}
	for _, item := range items {
		if item.ProductID <= 0 || item.Quantity <= 0 {
			continue
		}
		var newCount int
		err := tx.QueryRow(ctx,
			"UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2 RETURNING count",
			item.Quantity, item.ProductID).Scan(&newCount)
		if errors.Is(err, pgx.ErrNoRows) {
			continue // kuzatilmaydigan mahsulot
		}
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		restored[item.ProductID] = newCount
	}

	if _, err := tx.Exec(ctx,
		"UPDATE orders SET status = 'cancelled', updated_at = NOW() WHERE order_number = $1",
		req.OrderNumber); err != nil {
		jsonError(w, 500, "db_error", "Chek bekor qilinmadi: "+err.Error())
		return
	}

	// Agar stol buyurtmasi bo'lsa — boshqa ochiq chek bormi tekshirish
	tableFreed := ""
	if tableSKU != nil && *tableSKU != "" && orderType == "dine_in" {
		var otherActive int
		if err := tx.QueryRow(ctx,
			"SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed','cancelled') AND order_number != $2",
			*tableSKU, req.OrderNumber).Scan(&otherActive); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		if otherActive == 0 {
			if _, err := tx.Exec(ctx, "UPDATE tables SET status = 'free' WHERE sku = $1", *tableSKU); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
			tableFreed = *tableSKU
		}
	}

	if err := tx.Commit(ctx); err != nil {
		jsonError(w, 500, "db_error", "Chek bekor qilinmadi: "+err.Error())
		return
	}

	// E'lonlar faqat commit'dan keyin — orqaga qaytgan tranzaksiya klientlarga
	// "bekor qilindi" deb ko'rinmasin.
	for pid, count := range restored {
		c := count
		wss.BroadcastStock(pid, &c, "cancelled")
	}
	if tableFreed != "" {
		wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": tableFreed, "status": "free"})
	}

	resp := map[string]interface{}{"order_number": req.OrderNumber, "status": "cancelled"}
	wss.H.BroadcastEvent("order:updated", resp)
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:cancelled", resp)

	// Print cancel receipt
	tableSKUStr := ""
	if tableSKU != nil {
		tableSKUStr = *tableSKU
	}
	var cancelItems []map[string]interface{}
	json.Unmarshal(itemsJSON, &cancelItems)
	printer.PrintOrder(req.OrderNumber, orderType, tableSKUStr, time.Now().UTC().Format(time.RFC3339), claims.Name, cancelItems, true)

	jsonResponse(w, 200, map[string]interface{}{"message": "Chek bekor qilindi", "order_number": req.OrderNumber})
}

// ============ POST /api/order/cancel-item ============

func handleOrderCancelItem(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "orders", "cancel") && !middleware.HasPermission(claims, "orders", "close") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req struct {
		OrderNumber string `json:"order_number"`
		ProductID   int    `json:"product_id"`
		CancelQty   int    `json:"cancel_qty"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.OrderNumber == "" || req.ProductID == 0 {
		jsonError(w, 400, "bad_request", "order_number va product_id kerak")
		return
	}
	if req.CancelQty <= 0 {
		req.CancelQty = 1
	}

	ctx := r.Context()
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(ctx)

	// `FOR UPDATE` — SHART. Bu handler chek `items` JSON'ini o'qib, Go'da
	// o'zgartirib, qaytadan yozadi. Qulfsiz uchta xato bo'lardi:
	//   - bir chekning IKKI xil mahsuloti bir vaqtda bekor qilinsa, oxirgi
	//     yozuv birinchisini o'chirib yuborardi — mijoz bekor qilingan
	//     taom uchun pul to'lardi, qoldiq esa allaqachon qaytarilgan bo'lardi;
	//   - BIR mahsulot ikki marta bekor qilinsa qoldiq ikki marta qaytardi;
	//   - chek yopilayotgan payt bekor qilinsa, TO'LANGAN chekning summasi
	//     kamaytirilib, hisobot pul olingandan keyin pasayib ketardi.
	var itemsJSON []byte
	var status, orderType string
	var tableSKU *string
	var deliveryFee, discount int
	if err := tx.QueryRow(ctx, `
		SELECT items, status, type, table_sku, COALESCE(delivery_fee,0), COALESCE(discount,0)
		  FROM orders WHERE order_number = $1 FOR UPDATE`,
		req.OrderNumber).Scan(&itemsJSON, &status, &orderType, &tableSKU, &deliveryFee, &discount); err != nil {
		jsonError(w, 404, "not_found", "Buyurtma topilmadi")
		return
	}
	if status == "completed" || status == "cancelled" {
		jsonError(w, 400, "already_closed", "Buyurtma allaqachon yopilgan")
		return
	}

	// Items parse
	var items []map[string]interface{}
	json.Unmarshal(itemsJSON, &items)

	found := false
	for i, item := range items {
		if jsonNum(item["product_id"]) != req.ProductID {
			continue
		}
		qty := jsonNum(item["quantity"])
		if qty <= 0 {
			jsonError(w, 400, "nothing_to_cancel", "Bu mahsulot allaqachon bekor qilingan")
			return
		}
		if req.CancelQty > qty {
			req.CancelQty = qty
		}
		price := jsonNum(item["price"])
		newQty := qty - req.CancelQty

		items[i]["quantity"] = newQty
		items[i]["cancelled_qty"] = jsonNum(item["cancelled_qty"]) + req.CancelQty
		items[i]["total"] = price * newQty
		found = true
		break
	}
	if !found {
		jsonError(w, 404, "item_not_found", "Mahsulot topilmadi")
		return
	}

	// Qoldiqni qaytarish — o'sha tranzaksiyada.
	var restoredCount *int
	var rc int
	switch err := tx.QueryRow(ctx,
		"UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2 RETURNING count",
		req.CancelQty, req.ProductID).Scan(&rc); {
	case err == nil:
		restoredCount = &rc
	case errors.Is(err, pgx.ErrNoRows):
		// kuzatilmaydigan mahsulot
	default:
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	// Subtotal va total qayta hisoblash
	subtotal := 0
	allCancelled := true
	for _, item := range items {
		subtotal += jsonNum(item["total"])
		if jsonNum(item["quantity"]) > 0 {
			allCancelled = false
		}
	}

	newItemsJSON, _ := json.Marshal(items)
	tableFreed := ""

	// Agar barcha itemlar bekor bo'lsa — butun buyurtmani cancel
	if allCancelled {
		if _, err := tx.Exec(ctx,
			"UPDATE orders SET items = $1, subtotal = 0, total = 0, status = 'cancelled', updated_at = NOW() WHERE order_number = $2",
			string(newItemsJSON), req.OrderNumber); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		if tableSKU != nil && *tableSKU != "" {
			var otherActive int
			if err := tx.QueryRow(ctx,
				"SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed','cancelled') AND order_number != $2",
				*tableSKU, req.OrderNumber).Scan(&otherActive); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
			if otherActive == 0 {
				if _, err := tx.Exec(ctx, "UPDATE tables SET status = 'free' WHERE sku = $1", *tableSKU); err != nil {
					jsonError(w, 500, "db_error", err.Error())
					return
				}
				tableFreed = *tableSKU
			}
		}
		if err := tx.Commit(ctx); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}

		if restoredCount != nil {
			wss.BroadcastStock(req.ProductID, restoredCount, "item_cancelled")
		}
		if tableFreed != "" {
			wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": tableFreed, "status": "free"})
		}
		resp := map[string]interface{}{"order_number": req.OrderNumber, "status": "cancelled"}
		wss.H.BroadcastEvent("order:updated", resp)
		go wss.BroadcastShiftStatsExported()
		addSyncQueue("order:cancelled", resp)

		tableStr := ""
		if tableSKU != nil {
			tableStr = *tableSKU
		}
		var ciPrintItems []map[string]interface{}
		json.Unmarshal(itemsJSON, &ciPrintItems)
		printer.PrintOrder(req.OrderNumber, orderType, tableStr, time.Now().UTC().Format(time.RFC3339), claims.Name, ciPrintItems, true)

		jsonResponse(w, 200, map[string]interface{}{"message": "Barcha mahsulotlar bekor — chek bekor qilindi", "order_number": req.OrderNumber, "fully_cancelled": true})
		return
	}

	// Oddiy yangilash. Xizmat haqi olib tashlangan — qayta hisobda service_fee
	// doim 0, chekning o'z chegirma/yetkazib berish summalari saqlanadi.
	total := subtotal + deliveryFee - discount
	if total < 0 {
		total = 0
	}
	if _, err := tx.Exec(ctx,
		"UPDATE orders SET items = $1, subtotal = $2, service_fee = 0, total = $3, updated_at = NOW() WHERE order_number = $4",
		string(newItemsJSON), subtotal, total, req.OrderNumber); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(ctx); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	if restoredCount != nil {
		wss.BroadcastStock(req.ProductID, restoredCount, "item_cancelled")
	}
	// status ham yuboriladi: klient uni payloaddan o'qiydi, bo'lmasa chek
	// holati "null" bo'lib, ekranda eski/noto'g'ri holat ko'rinardi
	resp := map[string]interface{}{
		"order_number": req.OrderNumber, "subtotal": subtotal,
		"total": total, "service_fee": 0, "status": status,
	}
	wss.H.BroadcastEvent("order:updated", resp)
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:item_cancelled", resp)

	// Print cancel receipt for cancelled item
	icTableStr := ""
	if tableSKU != nil {
		icTableStr = *tableSKU
	}
	// Build a single-item list for the cancelled product
	cancelledItem := []map[string]interface{}{
		{"product_id": req.ProductID, "quantity": req.CancelQty, "price": 0, "total": 0, "snapshot": findSnapshot(itemsJSON, req.ProductID)},
	}
	printer.PrintOrder(req.OrderNumber, orderType, icTableStr, time.Now().UTC().Format(time.RFC3339), claims.Name, cancelledItem, true)

	jsonResponse(w, 200, map[string]interface{}{
		"message": "Mahsulot bekor qilindi", "order_number": req.OrderNumber,
		"product_id": req.ProductID, "cancel_qty": req.CancelQty,
		"subtotal": subtotal, "total": total, "fully_cancelled": false,
	})
}

// jsonNum — JSON'dan kelgan sonni int ga aylantiradi.
//
// `items` JSONB'dan `map[string]interface{}` ga o'qilganda hamma son float64
// bo'ladi; shu maydonlarni Go'da o'zgartirsak esa int bo'lib qoladi. Ilgari
// har joyda ikkala turni qo'lda tekshirish kerak edi va bitta joyda
// (`total`) qiymat 0 bo'lsa noto'g'ri tarmoqqa tushib ketardi.
func jsonNum(v interface{}) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

// findSnapshot extracts snapshot for a product from order items JSON
func findSnapshot(itemsJSON []byte, productID int) interface{} {
	var items []map[string]interface{}
	json.Unmarshal(itemsJSON, &items)
	for _, item := range items {
		pid, _ := item["product_id"].(float64)
		if int(pid) == productID {
			return item["snapshot"]
		}
	}
	return nil
}

// ============ POST /api/order/create ============

func handleOrderCreateHTTP(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "orders", "create") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	// Check shift
	var shiftStatus string
	err := db.Pool.QueryRow(r.Context(), "SELECT status FROM shifts WHERE status = 'open' LIMIT 1").Scan(&shiftStatus)
	if err != nil {
		jsonError(w, 400, "shift_required", "Smena ochilmagan")
		return
	}

	var p struct {
		Type     string  `json:"type"`
		TableSKU *string `json:"table_sku"`
		Items    []struct {
			ProductID int     `json:"product_id"`
			Quantity  int     `json:"quantity"`
			Note      *string `json:"note"`
		} `json:"items"`
		Note *string `json:"note"`
	}
	json.NewDecoder(r.Body).Decode(&p)

	// Chek turi tekshirilmasa: "dine-in" kabi xato qiymat xizmat haqisiz
	// o'tib ketardi, stol "band" bo'lmasdi, hisobotdagi turlar bo'yicha
	// taqsimotga tushmasdi va smena yopilishini ham to'smasdi — ya'ni
	// mahsuloti ishlatilgan chek abadiy ochiq qolib ketardi.
	if !allowedOrderTypes[p.Type] {
		jsonError(w, 400, "bad_request", "type: dine_in, takeaway yoki delivery")
		return
	}
	if p.Type == "dine_in" && (p.TableSKU == nil || *p.TableSKU == "") {
		jsonError(w, 400, "bad_request", "Zal buyurtmasi uchun stol kerak")
		return
	}

	now := time.Now()
	orderNumber, err := db.NextOrderNumber(r.Context(), db.Pool, "pos")
	if err != nil {
		jsonError(w, 500, "order_number_error", "Buyurtma raqami yaratilmadi")
		return
	}

	// Build items
	items := []map[string]interface{}{}
	subtotal := 0
	nowStr := now.UTC().Format(time.RFC3339)

	// Qabul qilingan mahsulotlar — qoldiq FAQAT shular bo'yicha kamayadi.
	// Ilgari chiqim so'rovdagi butun ro'yxat bo'yicha yurardi: topilmagan
	// mahsulot chekdan tushib qolsa ham, uning qoldig'i kamayaverardi.
	accepted := []models.OrderItemPayload{}

	for i, item := range p.Items {
		// Miqdor chegarasi: manfiy son jami summani manfiy qilib, qoldiqni
		// OSHIRIB yuborardi
		if item.Quantity <= 0 || item.Quantity > 999 {
			jsonError(w, 400, "bad_request", "Mahsulot miqdori 1..999 oralig'ida bo'lishi kerak")
			return
		}

		var nameUz, nameRu, nameTr string
		var price, catID int
		var media json.RawMessage
		err := db.Pool.QueryRow(r.Context(), "SELECT name_uz, name_ru, name_tr, price, category_id, media FROM products WHERE id = $1 AND status = 'active'", item.ProductID).
			Scan(&nameUz, &nameRu, &nameTr, &price, &catID, &media)
		if err != nil {
			// Jimgina o'tkazib yuborilsa, kassir 5 ta yozgan chek 4 ta bo'lib
			// ketardi va u buni bilmasdi
			jsonError(w, 400, "product_not_found",
				fmt.Sprintf("Mahsulot #%d topilmadi yoki faol emas", item.ProductID))
			return
		}

		// Qoldiq kafolati quyida — ReserveStock (atomar). Bu yerdagi tekshiruv
		// faqat kassirga aniq xabar berish uchun (qaysi taom yetmadi).
		var stockCount *int
		db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&stockCount)
		if stockCount != nil && *stockCount < item.Quantity {
			jsonError(w, 400, "out_of_stock", fmt.Sprintf("%s: faqat %d ta qolgan, %d ta so'raldi", nameUz, *stockCount, item.Quantity))
			return
		}
		accepted = append(accepted, models.OrderItemPayload{
			ProductID: item.ProductID, Quantity: item.Quantity,
		})

		snapshot, _ := json.Marshal(map[string]interface{}{
			"name":  map[string]string{"uz": nameUz, "ru": nameRu, "tr": nameTr},
			"price": price, "category_id": catID, "media": media,
		})
		addedBy, _ := json.Marshal(map[string]interface{}{
			"type": "pos", "name": claims.Name, "user_id": claims.UserID,
		})

		itemTotal := price * item.Quantity
		subtotal += itemTotal

		items = append(items, map[string]interface{}{
			"id": i + 1, "product_id": item.ProductID,
			"snapshot": json.RawMessage(snapshot),
			"quantity": item.Quantity, "price": price, "total": itemTotal,
			"note":     item.Note,
			"added_by": json.RawMessage(addedBy),
			"added_at": nowStr,
		})
	}

	// Bironta ham yaroqli item yo'q — bo'sh (0 so'mlik) buyurtma yaratilmasin
	if len(items) == 0 {
		jsonError(w, 400, "empty_order", "Buyurtmada yaroqli mahsulot yo'q")
		return
	}

	// Xizmat haqi olib tashlangan — service_fee doim 0.
	total := subtotal

	itemsJSON, _ := json.Marshal(items)

	// Get table info
	var tableID, zoneID *int
	if p.TableSKU != nil && *p.TableSKU != "" {
		var tid, zid int
		// Xato tekshiriladi: ilgari mavjud bo'lmagan stol nomi yuborilsa
		// chek `table_id=0, zone_id=0` bilan yozilardi — u hech qaysi
		// stolga bog'lanmagan bo'lib, stol bo'yicha yopib bo'lmasdi.
		if err := db.Pool.QueryRow(r.Context(),
			"SELECT id, zone_id FROM tables WHERE sku = $1", *p.TableSKU).Scan(&tid, &zid); err != nil {
			jsonError(w, 404, "table_not_found", "Stol topilmadi: "+*p.TableSKU)
			return
		}
		tableID = &tid
		zoneID = &zid
	}

	// Qoldiq chekdan OLDIN atomar band qilinadi (bitta tranzaksiya, FOR
	// UPDATE). Ilgari tekshiruv va chiqim alohida bo'lgani uchun ikki kassa
	// bir vaqtda sotsa qoldiq manfiyga tushib ketardi.
	reserved, err := wss.ReserveStock(r.Context(), accepted)
	if err != nil {
		jsonError(w, 409, "out_of_stock", err.Error())
		return
	}

	if _, err := db.Pool.Exec(r.Context(), `INSERT INTO orders (order_number, type, table_sku, table_id, zone_id, items, subtotal, service_fee, total, payment_status, status, source, created_by, note, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'unpaid', 'new', 'pos', $10, $11, NOW(), NOW())`,
		orderNumber, p.Type, p.TableSKU, tableID, zoneID, itemsJSON, subtotal, 0, total, claims.UserID, p.Note); err != nil {
		wss.ReleaseStock(r.Context(), accepted, reserved)
		jsonError(w, 500, "db_error", "Buyurtma saqlanmadi: "+err.Error())
		return
	}

	// Update table status
	if p.TableSKU != nil && p.Type == "dine_in" {
		db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", *p.TableSKU)
	}

	for pid, count := range reserved {
		newCount := count
		wss.BroadcastStock(pid, &newCount, "sold")
	}

	// WSS broadcast
	orderResp := map[string]interface{}{
		"order_number": orderNumber, "type": p.Type, "table_sku": p.TableSKU,
		"status": "new", "items": json.RawMessage(itemsJSON),
		"subtotal": subtotal, "service_fee": 0, "total": total,
		"source": "pos", "created_at": nowStr,
	}
	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})
	addSyncQueue("order:created", orderResp)

	// Print receipt
	tableSKUStr := ""
	if p.TableSKU != nil {
		tableSKUStr = *p.TableSKU
	}
	var printItems []map[string]interface{}
	json.Unmarshal(itemsJSON, &printItems)
	printer.PrintOrder(orderNumber, p.Type, tableSKUStr, nowStr, claims.Name, printItems, false)

	jsonResponse(w, 200, map[string]interface{}{
		"order_number": orderNumber, "total": total, "message": "Buyurtma yaratildi",
	})
}

// ============ POST /api/order/print-receipt ============

func handlePrintReceipt(w http.ResponseWriter, r *http.Request) {
	var req struct {
		OrderNumber    string `json:"order_number"`
		TableSKU       string `json:"table_sku"`
		PrinterAddress string `json:"printer_address"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	if req.PrinterAddress == "" {
		// Sozlamada tanlangan chek printeri (yo'q bo'lsa "chek" nomlisi → birinchi aktiv)
		rp := printer.ResolveReceiptPrinter()
		if rp == nil {
			jsonError(w, 400, "no_printer", "Chek printeri topilmadi")
			return
		}
		req.PrinterAddress = rp.Address
	}

	// Get orders
	if req.OrderNumber != "" {
		r2, err := db.Pool.Query(r.Context(), "SELECT order_number, type, table_sku, items, subtotal, service_fee, discount, total, payment_method FROM orders WHERE order_number = $1", req.OrderNumber)
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		{
			defer r2.Close()
			for r2.Next() {
				var orderNum, orderType, pm string
				var tsku *string
				var itemsJSON []byte
				var sub, sf, disc, tot int
				r2.Scan(&orderNum, &orderType, &tsku, &itemsJSON, &sub, &sf, &disc, &tot, &pm)
				tableSKU := ""
				if tsku != nil {
					tableSKU = *tsku
				}
				var items []map[string]interface{}
				json.Unmarshal(itemsJSON, &items)
				printer.PrintReceipt(req.PrinterAddress, orderNum, orderType, tableSKU, items, sub, sf, disc, tot, pm)
			}
		}
	} else if req.TableSKU != "" {
		r2, err := db.Pool.Query(r.Context(), "SELECT order_number, type, table_sku, items, subtotal, service_fee, discount, total, payment_method FROM orders WHERE table_sku = $1 AND status NOT IN ('cancelled', 'completed') ORDER BY created_at", req.TableSKU)
		if err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		{
			defer r2.Close()
			// Aggregate all checks into one receipt
			allItems := []map[string]interface{}{}
			var totalSub, totalSF, totalDisc, totalTot int
			var orderNum, orderType, pm, tableSKU string
			for r2.Next() {
				var on, ot, p string
				var tsku *string
				var itemsJSON []byte
				var sub, sf, disc, tot int
				r2.Scan(&on, &ot, &tsku, &itemsJSON, &sub, &sf, &disc, &tot, &p)
				orderNum = on
				orderType = ot
				pm = p
				if tsku != nil {
					tableSKU = *tsku
				}
				var items []map[string]interface{}
				json.Unmarshal(itemsJSON, &items)
				allItems = append(allItems, items...)
				totalSub += sub
				totalSF += sf
				totalDisc += disc
				totalTot += tot
			}
			if len(allItems) > 0 {
				printer.PrintReceipt(req.PrinterAddress, orderNum, orderType, tableSKU, allItems, totalSub, totalSF, totalDisc, totalTot, pm)
			}
		}
	} else {
		jsonError(w, 400, "bad_request", "order_number yoki table_sku kerak")
		return
	}

	jsonResponse(w, 200, map[string]interface{}{"message": "Chek chiqarilmoqda"})
}

func addSyncQueue(eventType string, data interface{}) {
	payload, _ := json.Marshal(data)
	db.Pool.Exec(context.Background(), "INSERT INTO sync_queue (event_id, event_type, payload, status, created_at) VALUES ($1, $2, $3, 'pending', NOW())",
		db.NewUUID(), eventType, string(payload))
}

// syncProductSnapshot — mahsulotning joriy holatini boshqa node'ga (cloud)
// yuboradi. Sayt menyusi cloud bazasidan o'qigani uchun busiz kassada
// qo'shilgan yangi taom yoki o'zgargan narx saytda umuman ko'rinmasdi.
func syncProductSnapshot(ctx context.Context, id int) {
	var (
		nameUz, nameRu, nameTr       string
		descUz, descRu, descTr       *string
		media, status, productType   string
		categoryID, price, sortOrder int
		isRecommended                bool
	)
	err := db.Pool.QueryRow(ctx, `
		SELECT name_uz, name_ru, name_tr, description_uz, description_ru, description_tr,
		       category_id, price, media, status, is_recommended, sort_order,
		       COALESCE(product_type,'cooked')
		  FROM products WHERE id=$1`, id).
		Scan(&nameUz, &nameRu, &nameTr, &descUz, &descRu, &descTr,
			&categoryID, &price, &media, &status, &isRecommended, &sortOrder, &productType)
	if err != nil {
		log.Printf("SYNC: product %d snapshotini o'qib bo'lmadi: %v", id, err)
		return
	}
	str := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	addSyncQueue("product:upserted", map[string]interface{}{
		"id": id, "name_uz": nameUz, "name_ru": nameRu, "name_tr": nameTr,
		"description_uz": str(descUz), "description_ru": str(descRu),
		"description_tr": str(descTr), "category_id": categoryID, "price": price,
		"media": media, "status": status, "is_recommended": isRecommended,
		"sort_order": sortOrder, "product_type": productType,
	})
}

// syncCategorySnapshot — kategoriya holatini boshqa node'ga yuboradi.
func syncCategorySnapshot(ctx context.Context, id int) {
	var nameUz, nameRu, nameTr, icon, status string
	var sortOrder int
	err := db.Pool.QueryRow(ctx,
		"SELECT name_uz, name_ru, name_tr, icon, sort_order, status FROM categories WHERE id=$1", id).
		Scan(&nameUz, &nameRu, &nameTr, &icon, &sortOrder, &status)
	if err != nil {
		log.Printf("SYNC: category %d snapshotini o'qib bo'lmadi: %v", id, err)
		return
	}
	addSyncQueue("category:upserted", map[string]interface{}{
		"id": id, "name_uz": nameUz, "name_ru": nameRu, "name_tr": nameTr,
		"icon": icon, "sort_order": sortOrder, "status": status,
	})
}

// ============ GET /api/printers ============

func handleGetPrinters(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), "SELECT id, name, address, status, created_at::text FROM printer_stations WHERE status = 'active' ORDER BY id")
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	printers := []models.PrinterStation{}
	for rows.Next() {
		var p models.PrinterStation
		rows.Scan(&p.ID, &p.Name, &p.Address, &p.Status, &p.CreatedAt)
		printers = append(printers, p)
	}
	jsonResponse(w, 200, printers)
}

// ============ POST /api/printers ============

func handleCreatePrinter(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name    string `json:"name"`
		Address string `json:"address"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.Name == "" || req.Address == "" {
		jsonError(w, 400, "bad_request", "name va address kerak")
		return
	}

	var id int
	db.Pool.QueryRow(r.Context(), "INSERT INTO printer_stations (name, address) VALUES ($1, $2) RETURNING id",
		req.Name, req.Address).Scan(&id)

	jsonResponse(w, 200, map[string]interface{}{"id": id, "name": req.Name, "address": req.Address, "message": "Printer qo'shildi"})
}

// ============ PUT /api/printers/:id ============

func handleUpdatePrinter(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	var req struct {
		Name    *string `json:"name"`
		Address *string `json:"address"`
		Status  *string `json:"status"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	ctx := r.Context()
	if req.Name != nil {
		db.Pool.Exec(ctx, "UPDATE printer_stations SET name = $1 WHERE id = $2", *req.Name, id)
	}
	if req.Address != nil {
		db.Pool.Exec(ctx, "UPDATE printer_stations SET address = $1 WHERE id = $2", *req.Address, id)
	}
	if req.Status != nil {
		db.Pool.Exec(ctx, "UPDATE printer_stations SET status = $1 WHERE id = $2", *req.Status, id)
	}

	jsonResponse(w, 200, map[string]interface{}{"message": "Printer yangilandi", "id": id})
}

// ============ DELETE /api/printers/:id ============

func handleDeletePrinter(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	db.Pool.Exec(r.Context(), "UPDATE printer_stations SET status = 'inactive' WHERE id = $1", id)
	// Clear references
	db.Pool.Exec(r.Context(), "UPDATE categories SET printer_station_id = NULL WHERE printer_station_id = $1", id)
	db.Pool.Exec(r.Context(), "UPDATE products SET printer_station_id = NULL WHERE printer_station_id = $1", id)
	// Chek printeri shu bo'lsa — avtomatik tanlovga qaytariladi
	if db.GetSetting(printer.ReceiptPrinterKey) == strconv.Itoa(id) {
		db.SetSetting(printer.ReceiptPrinterKey, "")
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Printer o'chirildi"})
}

// ============ PUT /api/category/:id ============

// ============ POST /api/category ============

func handleCreateCategory(w http.ResponseWriter, r *http.Request) {
	var req struct {
		NameUz           string `json:"name_uz"`
		NameRu           string `json:"name_ru"`
		NameTr           string `json:"name_tr"`
		Icon             string `json:"icon"`
		Status           string `json:"status"`
		PrinterStationID *int   `json:"printer_station_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	if req.NameUz == "" && req.NameRu == "" {
		jsonError(w, 400, "bad_request", "Nom kerak (uz yoki ru)")
		return
	}
	if req.Status == "" {
		req.Status = "active"
	}

	// Sort order — eng oxirgi + 1
	var maxSort int
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(MAX(sort_order), 0) FROM categories").Scan(&maxSort)

	var id int
	err := db.Pool.QueryRow(r.Context(),
		`INSERT INTO categories (name_uz, name_ru, name_tr, icon, sort_order, status, printer_station_id)
		 VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
		req.NameUz, req.NameRu, req.NameTr, req.Icon, maxSort+1, req.Status, req.PrinterStationID).Scan(&id)
	if err != nil {
		jsonError(w, 500, "db_error", "Kategoriya yaratishda xato: "+err.Error())
		return
	}

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "category_created"})
	syncCategorySnapshot(r.Context(), id)

	jsonResponse(w, 201, map[string]interface{}{"message": "Kategoriya yaratildi", "id": id})
}

// ============ DELETE /api/category/:id ============

func handleDeleteCategory(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))

	// Kategoriya ichida mahsulot bo'lsa — xato
	var count int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM products WHERE category_id = $1 AND status != 'deleted'", id).Scan(&count)
	if count > 0 {
		jsonError(w, 400, "has_products", fmt.Sprintf("Kategoriyada %d ta mahsulot bor. Avval ularni o'chiring", count))
		return
	}

	db.Pool.Exec(r.Context(), "UPDATE categories SET status = 'deleted' WHERE id = $1", id)

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "category_deleted"})
	syncCategorySnapshot(r.Context(), id)

	jsonResponse(w, 200, map[string]interface{}{"message": "Kategoriya o'chirildi", "id": id})
}

// ============ POST /api/upload/category-image/:id ============

func handleUploadCategoryImage(w http.ResponseWriter, r *http.Request) {
	catID, _ := strconv.Atoi(chi.URLParam(r, "id"))

	r.ParseMultipartForm(10 << 20)
	file, header, err := r.FormFile("image")
	if err != nil {
		jsonError(w, 400, "bad_request", "Rasm fayli kerak (image field)")
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
		jsonError(w, 400, "bad_format", "Faqat jpg, png, webp")
		return
	}

	// Eski iconni o'chirish
	ctx := r.Context()
	var oldIcon *string
	db.Pool.QueryRow(ctx, "SELECT icon FROM categories WHERE id = $1", catID).Scan(&oldIcon)
	if oldIcon != nil && strings.HasPrefix(*oldIcon, "/uploads/") {
		os.Remove("." + *oldIcon)
	}

	uploadDir := "./uploads/categories"
	os.MkdirAll(uploadDir, 0755)

	fileName := fmt.Sprintf("%d_%d%s", catID, time.Now().Unix(), ext)
	filePath := filepath.Join(uploadDir, fileName)

	dst, err := os.Create(filePath)
	if err != nil {
		jsonError(w, 500, "save_error", "Faylni saqlashda xato")
		return
	}
	defer dst.Close()
	io.Copy(dst, file)

	iconURL := fmt.Sprintf("/uploads/categories/%s", fileName)
	db.Pool.Exec(ctx, "UPDATE categories SET icon = $1 WHERE id = $2", iconURL, catID)

	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "category_image_updated"})

	jsonResponse(w, 200, map[string]interface{}{
		"message":     "Rasm yuklandi",
		"category_id": catID,
		"icon_url":    iconURL,
	})
}

// ============ PUT /api/category/:id ============

func handleUpdateCategory(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	var req struct {
		NameUz           *string `json:"name_uz"`
		NameRu           *string `json:"name_ru"`
		NameTr           *string `json:"name_tr"`
		Icon             *string `json:"icon"`
		Status           *string `json:"status"`
		PrinterStationID *int    `json:"printer_station_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	ctx := r.Context()
	if id <= 0 {
		jsonError(w, 400, "bad_request", "Kategoriya ID noto'g'ri")
		return
	}
	if req.Status != nil && !allowedProductStatus[*req.Status] {
		jsonError(w, 400, "bad_request", "Status noto'g'ri (active/inactive/deleted)")
		return
	}

	// Mahsulotdagi kabi — bitta atomar UPDATE (qarang: handleUpdateProduct).
	// `updated_at` ham suriladi: node'lararo "kim oxirgi yozdi" qoidasi shunga
	// qaraydi, busiz kechikib kelgan eski event yangi nomni bosib ketardi.
	set := []string{"updated_at = NOW()"}
	args := []interface{}{}
	add := func(col string, val interface{}) {
		args = append(args, val)
		set = append(set, fmt.Sprintf("%s = $%d", col, len(args)))
	}
	if req.NameUz != nil {
		add("name_uz", *req.NameUz)
	}
	if req.NameRu != nil {
		add("name_ru", *req.NameRu)
	}
	if req.NameTr != nil {
		add("name_tr", *req.NameTr)
	}
	if req.Icon != nil {
		add("icon", *req.Icon)
	}
	if req.Status != nil {
		add("status", *req.Status)
	}
	if req.PrinterStationID != nil {
		if *req.PrinterStationID == 0 {
			set = append(set, "printer_station_id = NULL")
		} else {
			add("printer_station_id", *req.PrinterStationID)
		}
	}
	if len(set) == 1 {
		jsonError(w, 400, "bad_request", "O'zgartirish uchun maydon yuborilmadi")
		return
	}

	args = append(args, id)
	if _, err := db.Pool.Exec(ctx,
		fmt.Sprintf("UPDATE categories SET %s WHERE id = $%d", strings.Join(set, ", "), len(args)),
		args...); err != nil {
		jsonError(w, 500, "db_error", "Kategoriya yangilanmadi: "+err.Error())
		return
	}

	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "category_updated"})
	syncCategorySnapshot(ctx, id)

	jsonResponse(w, 200, map[string]interface{}{"message": "Kategoriya yangilandi", "id": id})
}

// allowedProductStatus — mahsulot/kategoriya uchun ruxsat etilgan holatlar.
// Ilgari istalgan satr yozilardi: xato yozilgan status mahsulotni menyudan
// ham, hisobotdan ham yo'q qilib qo'yardi va uni faqat baza orqali tuzatish
// mumkin edi.
var allowedProductStatus = map[string]bool{
	"active": true, "inactive": true, "deleted": true,
}

// allowedOrderTypes — chek turlari. Boshqa qiymat xizmat haqi, stol holati
// va hisobot taqsimotini jimgina chetlab o'tadi.
var allowedOrderTypes = map[string]bool{
	"dine_in": true, "takeaway": true, "delivery": true,
}
