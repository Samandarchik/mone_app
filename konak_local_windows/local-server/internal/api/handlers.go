package api

import (
	"context"
	"encoding/json"
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
	jsonResponse(w, 200, map[string]interface{}{
		"status": "ok",
		"time":   time.Now().UTC().Format(time.RFC3339),
		"db":     "connected",
	})
}

// ============ GET /api/menu ============

func handleGetMenu(w http.ResponseWriter, r *http.Request) {
	var version int
	db.Pool.QueryRow(r.Context(), "SELECT version FROM menu_version WHERE id = 1").Scan(&version)

	// Categories
	catRows, err := db.Pool.Query(r.Context(), "SELECT id, name_uz, name_ru, name_tr, icon, sort_order, status, printer_station_id FROM categories WHERE status = 'active' ORDER BY sort_order")
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
		       p.availability, p.ingredients, p.sort_order, p.printer_station_id
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE p.status = 'active'
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
			&p.CategoryID, &p.Price, &p.OldPrice, &p.Media, &p.Status, &p.IsRecommended, &p.Availability, &p.Ingredients, &p.SortOrder, &p.PrinterStationID)

		desc := map[string]string{}
		if p.DescriptionUz != nil { desc["uz"] = *p.DescriptionUz }
		if p.DescriptionRu != nil { desc["ru"] = *p.DescriptionRu }
		if p.DescriptionTr != nil { desc["tr"] = *p.DescriptionTr }

		var avail, ingr json.RawMessage
		if p.Availability != nil { avail = json.RawMessage(*p.Availability) } else { avail = json.RawMessage("null") }
		if p.Ingredients != nil { ingr = json.RawMessage(*p.Ingredients) } else { ingr = json.RawMessage("null") }

		products = append(products, models.ProductJSON{
			ID: p.ID,
			Name: map[string]string{"uz": p.NameUz, "ru": p.NameRu, "tr": p.NameTr},
			SortOrder: p.SortOrder,
			Description: desc,
			CategoryID: p.CategoryID,
			Price: p.Price,
			OldPrice: p.OldPrice,
			Media: json.RawMessage(p.Media),
			Status: p.Status,
			IsRecommended: p.IsRecommended,
			Availability: avail,
			Ingredients: ingr,
			PrinterStationID: p.PrinterStationID,
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

	// Products — POS bilan bir xil tartib (category sort_order → product sort_order → id)
	prodRows, err := db.Pool.Query(r.Context(), `
		SELECT p.id, p.name_uz, p.name_ru, p.name_tr, p.description_uz, p.description_ru, p.description_tr,
		       p.category_id, p.price, p.old_price, p.media, p.status, p.is_recommended,
		       p.availability, p.ingredients, p.sort_order, p.printer_station_id
		FROM products p
		JOIN categories c ON c.id = p.category_id
		WHERE p.status = 'active' AND c.status = 'active'
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
			&p.CategoryID, &p.Price, &p.OldPrice, &p.Media, &p.Status, &p.IsRecommended, &p.Availability, &p.Ingredients, &p.SortOrder, &p.PrinterStationID)

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
		})
	}

	jsonResponse(w, 200, map[string]interface{}{
		"version":    version,
		"categories": categories,
		"products":   products,
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
			"id": id, "sku": sku, "label": label, "qr_code": qrCode, "zone_name": zoneName,
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
		"table_sku": t.SKU,
		"table_id":  t.ID,
		"zone_id":   t.ZoneID,
		"zone_name": map[string]string{"uz": zoneName},
		"label":     t.Label,
		"seats":     t.Seats,
		"status":    t.Status,
		"locked_by": nil,
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
	checkRows, _ := db.Pool.Query(r.Context(), "SELECT order_number, type, status, items, subtotal, service_fee, discount, total, note, created_at FROM orders WHERE table_sku = $1 AND status != 'completed' ORDER BY created_at", sku)
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
	rows, _ := db.Pool.Query(r.Context(), "SELECT product_id, count, updated_at FROM stocks")
	defer rows.Close()

	stocks := []models.Stock{}
	for rows.Next() {
		var s models.Stock
		rows.Scan(&s.ProductID, &s.Count, &s.UpdatedAt)
		stocks = append(stocks, s)
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

func valOrEmpty(s *string) string { if s != nil { return *s }; return "" }
func valOrZero(n *int) int { if n != nil { return *n }; return 0 }

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
	today := time.Now().Format("2006-01-02")

	var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, expensesTotal int
	var dineInCount, takeawayCount, deliveryCount int
	var dineInTotal, takeawayTotal, deliveryTotal int

	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed'", shiftOpenedAt).Scan(&totalOrders)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed'", shiftOpenedAt).Scan(&totalRevenue)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'cash'", shiftOpenedAt).Scan(&cashRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'card'", shiftOpenedAt).Scan(&cardRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'payme'", shiftOpenedAt).Scan(&paymeRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'click'", shiftOpenedAt).Scan(&clickRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE date = $1 AND created_at >= $2", today, shiftOpenedAt).Scan(&expensesTotal)

	// By order type
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'dine_in'", shiftOpenedAt).Scan(&dineInCount, &dineInTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'takeaway'", shiftOpenedAt).Scan(&takeawayCount, &takeawayTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'delivery'", shiftOpenedAt).Scan(&deliveryCount, &deliveryTotal)

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
			"expenses_total":       expensesTotal,
			"cash_revenue":         cashRev,
			"current_expected_cash": openingCash + cashRev - expensesTotal,
			"active_sd_orders":     activeSD,
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

	var user models.User
	var pin string
	err := db.Pool.QueryRow(r.Context(), "SELECT id, name, phone, role, pin, custom_permissions, status FROM users WHERE phone = $1 AND status = 'active'", req.Phone).
		Scan(&user.ID, &user.Name, &user.Phone, &user.Role, &pin, &user.CustomPermissions, &user.Status)
	if err != nil || pin != req.PIN {
		jsonError(w, 401, "invalid_credentials", "Telefon raqam yoki PIN noto'g'ri")
		return
	}

	// Build permissions
	perms := middleware.RolePermissions[user.Role]
	if user.CustomPermissions != nil {
		var custom map[string][]string
		if json.Unmarshal([]byte(*user.CustomPermissions), &custom) == nil {
			merged := make(map[string][]string)
			for k, v := range perms { merged[k] = v }
			for k, v := range custom { merged[k] = v }
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

	var user models.User
	var pin string
	err := db.Pool.QueryRow(r.Context(), "SELECT id, name, phone, role, pin, custom_permissions, status FROM users WHERE pin = $1 AND status = 'active'", req.PIN).
		Scan(&user.ID, &user.Name, &user.Phone, &user.Role, &pin, &user.CustomPermissions, &user.Status)
	if err != nil {
		jsonError(w, 401, "invalid_credentials", "PIN noto'g'ri")
		return
	}

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

	now := time.Now().UTC()
	openedBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})

	var shiftID int64
	db.Pool.QueryRow(r.Context(), "INSERT INTO shifts (date, opened_by, opened_at, opening_cash, status) VALUES ($1, $2, $3, $4, 'open') RETURNING id",
		now.Format("2006-01-02"), string(openedBy), now.Format(time.RFC3339), req.OpeningCash).Scan(&shiftID)

	resp := map[string]interface{}{
		"shift_id": shiftID, "date": now.Format("2006-01-02"), "status": "open",
		"opened_by": map[string]interface{}{"user_id": claims.UserID, "name": claims.Name},
		"opened_at": now.Format(time.RFC3339), "opening_cash": req.OpeningCash,
	}
	wss.H.BroadcastEvent("shift:opened", resp)
	wss.H.BroadcastEvent("", nil) // trigger sync
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
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery') AND created_at::date = CURRENT_DATE").Scan(&activeSDCount)
	if activeSDCount > 0 {
		jsonError(w, 400, "active_orders_exist", fmt.Sprintf("%d ta yopilmagan saboy/dostafka buyurtma bor", activeSDCount))
		return
	}

	var req models.ShiftCloseRequest
	json.NewDecoder(r.Body).Decode(&req)

	var shiftID, openingCash int
	err := db.Pool.QueryRow(r.Context(), "SELECT id, opening_cash FROM shifts WHERE status = 'open'").Scan(&shiftID, &openingCash)
	if err != nil {
		jsonError(w, 400, "no_open_shift", "Ochiq smena yo'q")
		return
	}

	today := time.Now().Format("2006-01-02")
	summary := wss.CalculateShiftSummaryExported(today, openingCash, req.ActualCash)

	now := time.Now().UTC().Format(time.RFC3339)
	closedBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})
	summaryJSON, _ := json.Marshal(summary)

	db.Pool.Exec(r.Context(), "UPDATE shifts SET closed_by = $1, closed_at = $2, closing_cash = $3, status = 'closed', summary = $4 WHERE id = $5",
		string(closedBy), now, req.ActualCash, string(summaryJSON), shiftID)

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
	json.NewDecoder(r.Body).Decode(&req)

	today := time.Now().Format("2006-01-02")
	createdBy, _ := json.Marshal(map[string]interface{}{"user_id": claims.UserID, "name": claims.Name, "role": claims.Role})

	var id int64
	db.Pool.QueryRow(r.Context(), "INSERT INTO expenses (category_id, amount, description, date, created_by) VALUES ($1, $2, $3, $4, $5) RETURNING id",
		req.CategoryID, req.Amount, req.Description, today, string(createdBy)).Scan(&id)

	// Get category name
	var catName string
	db.Pool.QueryRow(r.Context(), "SELECT name_uz FROM expense_categories WHERE id = $1", req.CategoryID).Scan(&catName)

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

	jsonResponse(w, 200, map[string]interface{}{"id": id, "name_uz": req.NameUz, "name_ru": req.NameRu, "name_tr": req.NameTr})
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

	var totalOrders, cancelledOrders, cashRev, cardRev, paymeRev, clickRev, expTotal int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'completed'", date).Scan(&totalOrders)
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'cancelled'", date).Scan(&cancelledOrders)
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at::date = $1 AND status='completed' AND payment_method='cash'", date).Scan(&cashRev)
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at::date = $1 AND status='completed' AND payment_method='card'", date).Scan(&cardRev)
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at::date = $1 AND status='completed' AND payment_method='payme'", date).Scan(&paymeRev)
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at::date = $1 AND status='completed' AND payment_method='click'", date).Scan(&clickRev)
	db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date = $1", date).Scan(&expTotal)

	totalRev := cashRev + cardRev + paymeRev + clickRev

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
			"by_payment_method": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev},
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
		NameUz     string `json:"name_uz"`
		NameRu     string `json:"name_ru"`
		NameTr     string `json:"name_tr"`
		DescUz     string `json:"description_uz"`
		DescRu     string `json:"description_ru"`
		DescTr     string `json:"description_tr"`
		Price      int    `json:"price"`
		OldPrice   *int   `json:"old_price"`
		CategoryID int    `json:"category_id"`
		Status     string `json:"status"`
		SortOrder  int    `json:"sort_order"`
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
	if p.Status == "" {
		p.Status = "active"
	}

	var id int
	err := db.Pool.QueryRow(r.Context(),
		`INSERT INTO products (name_uz, name_ru, name_tr, description_uz, description_ru, description_tr, price, old_price, category_id, status, sort_order, created_at, updated_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,NOW(),NOW()) RETURNING id`,
		p.NameUz, p.NameRu, p.NameTr, p.DescUz, p.DescRu, p.DescTr, p.Price, p.OldPrice, p.CategoryID, p.Status, p.SortOrder).Scan(&id)
	if err != nil {
		jsonError(w, 500, "db_error", "Mahsulot yaratishda xato: "+err.Error())
		return
	}

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_created"})

	jsonResponse(w, 201, map[string]interface{}{"message": "Mahsulot yaratildi", "id": id})
}

// ============ DELETE /api/product/:id ============

func handleDeleteProduct(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	db.Pool.Exec(r.Context(), "UPDATE products SET status = 'deleted', updated_at = NOW() WHERE id = $1", id)

	db.Pool.Exec(r.Context(), "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_deleted"})

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
		PrinterStationID *int    `json:"printer_station_id"`
	}
	json.NewDecoder(r.Body).Decode(&p)

	ctx := r.Context()

	if p.NameUz != nil { db.Pool.Exec(ctx, "UPDATE products SET name_uz = $1, updated_at = NOW() WHERE id = $2", *p.NameUz, id) }
	if p.NameRu != nil { db.Pool.Exec(ctx, "UPDATE products SET name_ru = $1, updated_at = NOW() WHERE id = $2", *p.NameRu, id) }
	if p.NameTr != nil { db.Pool.Exec(ctx, "UPDATE products SET name_tr = $1, updated_at = NOW() WHERE id = $2", *p.NameTr, id) }
	if p.DescUz != nil { db.Pool.Exec(ctx, "UPDATE products SET description_uz = $1, updated_at = NOW() WHERE id = $2", *p.DescUz, id) }
	if p.DescRu != nil { db.Pool.Exec(ctx, "UPDATE products SET description_ru = $1, updated_at = NOW() WHERE id = $2", *p.DescRu, id) }
	if p.DescTr != nil { db.Pool.Exec(ctx, "UPDATE products SET description_tr = $1, updated_at = NOW() WHERE id = $2", *p.DescTr, id) }
	if p.Price != nil { db.Pool.Exec(ctx, "UPDATE products SET price = $1, updated_at = NOW() WHERE id = $2", *p.Price, id) }
	if p.OldPrice != nil { db.Pool.Exec(ctx, "UPDATE products SET old_price = $1, updated_at = NOW() WHERE id = $2", *p.OldPrice, id) }
	if p.CategoryID != nil { db.Pool.Exec(ctx, "UPDATE products SET category_id = $1, updated_at = NOW() WHERE id = $2", *p.CategoryID, id) }
	if p.Status != nil { db.Pool.Exec(ctx, "UPDATE products SET status = $1, updated_at = NOW() WHERE id = $2", *p.Status, id) }
	if p.PrinterStationID != nil {
		if *p.PrinterStationID == 0 {
			db.Pool.Exec(ctx, "UPDATE products SET printer_station_id = NULL, updated_at = NOW() WHERE id = $1", id)
		} else {
			db.Pool.Exec(ctx, "UPDATE products SET printer_station_id = $1, updated_at = NOW() WHERE id = $2", *p.PrinterStationID, id)
		}
	}

	// menu_version++
	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "product_updated"})

	jsonResponse(w, 200, map[string]interface{}{"message": "Mahsulot yangilandi", "id": id})
}

// ============ POST /api/stock/set ============

func handleStockSetHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProductID int `json:"product_id"`
		Count     int `json:"count"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	db.Pool.Exec(r.Context(), "INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, NOW()) ON CONFLICT (product_id) DO UPDATE SET count = $2, updated_at = NOW()", req.ProductID, req.Count)
	wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": req.ProductID, "count": req.Count, "reason": "manual_set"})

	jsonResponse(w, 200, map[string]interface{}{"message": "Stock yangilandi", "product_id": req.ProductID, "count": req.Count})
}

// ============ POST /api/stock/remove ============

func handleStockRemoveHTTP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		ProductID int `json:"product_id"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	db.Pool.Exec(r.Context(), "DELETE FROM stocks WHERE product_id = $1", req.ProductID)
	wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": req.ProductID, "count": nil, "reason": "removed"})

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

	jsonResponse(w, 200, map[string]interface{}{
		"message":    "Rasm yuklandi",
		"product_id": productID,
		"image_url":  imageURL,
	})
}

func splitSKU(sku string) int {
	// "1-2" → 2, "2-3" → 3
	parts := strings.Split(sku, "-")
	if len(parts) >= 2 {
		n, _ := strconv.Atoi(parts[len(parts)-1])
		return n
	}
	return 0
}

func splitOrderNumber(orderNum string) [2]int {
	// "26-04-05-03-02" → [3, 2] (XX=3, YY=2)
	parts := strings.Split(orderNum, "-")
	if len(parts) >= 5 {
		xx, _ := strconv.Atoi(parts[3])
		yy, _ := strconv.Atoi(parts[4])
		return [2]int{xx, yy}
	}
	return [2]int{1, 0}
}

// ============ POST /api/order/close ============

func handleOrderClose(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if !middleware.HasPermission(claims, "orders", "close") {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}

	var req struct {
		TableSKU      string `json:"table_sku"`
		OrderNumber   string `json:"order_number"`
		PaymentMethod string `json:"payment_method"`
		Discount      int    `json:"discount"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	var totalSum int
	var orderCount int

	if req.OrderNumber != "" {
		// Close by order_number (Saboy/Dostafka)
		err := db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total), 0), COUNT(*) FROM orders WHERE order_number = $1 AND status NOT IN ('completed', 'cancelled')", req.OrderNumber).Scan(&totalSum, &orderCount)
		if err != nil || orderCount == 0 {
			jsonError(w, 404, "not_found", "Ochiq buyurtma topilmadi")
			return
		}

		newTotal := totalSum - req.Discount
		if newTotal < 0 {
			newTotal = 0
		}

		db.Pool.Exec(r.Context(), "UPDATE orders SET payment_method = $1, payment_status = 'paid', status = 'completed', updated_at = NOW() WHERE order_number = $2 AND status NOT IN ('completed', 'cancelled')",
			req.PaymentMethod, req.OrderNumber)

		resp := map[string]interface{}{
			"order_number": req.OrderNumber, "total": newTotal, "payment_method": req.PaymentMethod, "checks_closed": orderCount,
		}
		wss.H.BroadcastEvent("order:closed", resp)
		go wss.BroadcastShiftStatsExported()
		addSyncQueue("order:closed", resp)

		jsonResponse(w, 200, map[string]interface{}{"message": "Buyurtma yopildi", "total": newTotal, "checks_closed": orderCount, "discount": req.Discount})
		return
	}

	// Close by table_sku (dine_in — all open checks for table)
	err := db.Pool.QueryRow(r.Context(), "SELECT COALESCE(SUM(total), 0), COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed', 'cancelled')", req.TableSKU).Scan(&totalSum, &orderCount)
	if err != nil || orderCount == 0 {
		jsonError(w, 404, "not_found", "Ochiq buyurtma topilmadi")
		return
	}

	newTotal := totalSum - req.Discount
	if newTotal < 0 {
		newTotal = 0
	}

	db.Pool.Exec(r.Context(), "UPDATE orders SET payment_method = $1, payment_status = 'paid', status = 'completed', updated_at = NOW() WHERE table_sku = $2 AND status NOT IN ('completed', 'cancelled')",
		req.PaymentMethod, req.TableSKU)

	// Cancelled cheklarni ham completed qilish (sessiya tugadi)
	db.Pool.Exec(r.Context(), "UPDATE orders SET status = 'completed', updated_at = NOW() WHERE table_sku = $1 AND status = 'cancelled'", req.TableSKU)

	// Free table
	db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'free' WHERE sku = $1", req.TableSKU)

	// Close QR sessions
	db.Pool.Exec(r.Context(), "UPDATE qr_sessions SET status = 'closed', closed_at = NOW() WHERE table_sku = $1 AND status = 'active'", req.TableSKU)

	// WSS broadcast
	resp := map[string]interface{}{
		"table_sku": req.TableSKU, "total": newTotal, "payment_method": req.PaymentMethod, "checks_closed": orderCount,
	}
	wss.H.BroadcastEvent("order:closed", resp)
	wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": req.TableSKU, "status": "free"})
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:closed", resp)

	jsonResponse(w, 200, map[string]interface{}{"message": "Buyurtma yopildi", "total": newTotal, "checks_closed": orderCount, "discount": req.Discount})
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

	// Buyurtma mavjudligini tekshirish
	var status, orderType string
	var tableSKU *string
	var itemsJSON []byte
	err := db.Pool.QueryRow(r.Context(), "SELECT status, type, table_sku, items FROM orders WHERE order_number = $1", req.OrderNumber).
		Scan(&status, &orderType, &tableSKU, &itemsJSON)
	if err != nil {
		jsonError(w, 404, "not_found", "Buyurtma topilmadi")
		return
	}
	if status == "completed" || status == "cancelled" {
		jsonError(w, 400, "already_closed", "Buyurtma allaqachon yopilgan")
		return
	}

	// Stock qaytarish
	var items []struct {
		ProductID int `json:"product_id"`
		Quantity  int `json:"quantity"`
	}
	json.Unmarshal(itemsJSON, &items)
	for _, item := range items {
		var stockExists bool
		db.Pool.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM stocks WHERE product_id = $1)", item.ProductID).Scan(&stockExists)
		if stockExists {
			db.Pool.Exec(r.Context(), "UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2", item.Quantity, item.ProductID)
			var newCount int
			db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&newCount)
			wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": item.ProductID, "count": newCount, "reason": "cancelled"})
		}
	}

	// Buyurtmani cancelled qilish
	db.Pool.Exec(r.Context(), "UPDATE orders SET status = 'cancelled', updated_at = NOW() WHERE order_number = $1", req.OrderNumber)

	// Agar stol buyurtmasi bo'lsa — boshqa ochiq chek bormi tekshirish
	if tableSKU != nil && orderType == "dine_in" {
		var otherActive int
		db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed','cancelled') AND order_number != $2", *tableSKU, req.OrderNumber).Scan(&otherActive)
		if otherActive == 0 {
			db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'free' WHERE sku = $1", *tableSKU)
			wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": *tableSKU, "status": "free"})
		}
	}

	resp := map[string]interface{}{"order_number": req.OrderNumber, "status": "cancelled"}
	wss.H.BroadcastEvent("order:updated", resp)
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:cancelled", resp)

	// Print cancel receipt
	tableSKUStr := ""
	if tableSKU != nil { tableSKUStr = *tableSKU }
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

	// Buyurtmani olish
	var itemsJSON []byte
	var status string
	err := db.Pool.QueryRow(r.Context(), "SELECT items, status FROM orders WHERE order_number = $1", req.OrderNumber).Scan(&itemsJSON, &status)
	if err != nil {
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
		pid, _ := item["product_id"].(float64)
		if int(pid) == req.ProductID {
			qty, _ := item["quantity"].(float64)
			cancelledQty, _ := item["cancelled_qty"].(float64)

			canCancel := int(qty)
			if req.CancelQty > canCancel {
				req.CancelQty = canCancel
			}
			if canCancel <= 0 {
				jsonError(w, 400, "nothing_to_cancel", "Bu mahsulot allaqachon bekor qilingan")
				return
			}

			price, _ := item["price"].(float64)
			newQty := int(qty) - req.CancelQty
			newCancelled := int(cancelledQty) + req.CancelQty

			items[i]["quantity"] = newQty
			items[i]["cancelled_qty"] = newCancelled
			items[i]["total"] = int(price) * newQty

			// Stock qaytarish
			var stockExists bool
			db.Pool.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM stocks WHERE product_id = $1)", req.ProductID).Scan(&stockExists)
			if stockExists {
				db.Pool.Exec(r.Context(), "UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2", req.CancelQty, req.ProductID)
				var newCount int
				db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", req.ProductID).Scan(&newCount)
				wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": req.ProductID, "count": newCount, "reason": "item_cancelled"})
			}

			found = true
			break
		}
	}
	if !found {
		jsonError(w, 404, "item_not_found", "Mahsulot topilmadi")
		return
	}

	// Subtotal va total qayta hisoblash
	subtotal := 0
	allCancelled := true
	for _, item := range items {
		t, _ := item["total"].(int)
		if t == 0 {
			tf, _ := item["total"].(float64)
			t = int(tf)
		}
		subtotal += t
		q, _ := item["quantity"].(float64)
		qi, ok := item["quantity"].(int)
		if ok && qi > 0 {
			allCancelled = false
		} else if !ok && int(q) > 0 {
			allCancelled = false
		}
	}

	newItemsJSON, _ := json.Marshal(items)

	// Agar barcha itemlar bekor bo'lsa — butun buyurtmani cancel
	if allCancelled {
		db.Pool.Exec(r.Context(), "UPDATE orders SET items = $1, subtotal = 0, total = 0, status = 'cancelled', updated_at = NOW() WHERE order_number = $2",
			string(newItemsJSON), req.OrderNumber)

		// Stolni tekshirish
		var tableSKU *string
		db.Pool.QueryRow(r.Context(), "SELECT table_sku FROM orders WHERE order_number = $1", req.OrderNumber).Scan(&tableSKU)
		if tableSKU != nil {
			var otherActive int
			db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed','cancelled') AND order_number != $2", *tableSKU, req.OrderNumber).Scan(&otherActive)
			if otherActive == 0 {
				db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'free' WHERE sku = $1", *tableSKU)
				wss.H.BroadcastEvent("table:status_changed", map[string]interface{}{"table_sku": *tableSKU, "status": "free"})
			}
		}

		resp := map[string]interface{}{"order_number": req.OrderNumber, "status": "cancelled"}
		wss.H.BroadcastEvent("order:updated", resp)
		go wss.BroadcastShiftStatsExported()
		addSyncQueue("order:cancelled", resp)

		// Print cancel receipt (full cancel via cancel-item)
		var ciTableSKU *string
		var ciOrderType string
		db.Pool.QueryRow(r.Context(), "SELECT table_sku, type FROM orders WHERE order_number = $1", req.OrderNumber).Scan(&ciTableSKU, &ciOrderType)
		ciTableStr := ""
		if ciTableSKU != nil { ciTableStr = *ciTableSKU }
		var ciPrintItems []map[string]interface{}
		json.Unmarshal(itemsJSON, &ciPrintItems)
		printer.PrintOrder(req.OrderNumber, ciOrderType, ciTableStr, time.Now().UTC().Format(time.RFC3339), claims.Name, ciPrintItems, true)

		jsonResponse(w, 200, map[string]interface{}{"message": "Barcha mahsulotlar bekor — chek bekor qilindi", "order_number": req.OrderNumber, "fully_cancelled": true})
		return
	}

	// Oddiy yangilash
	serviceFee := subtotal / 10
	total := subtotal + serviceFee
	db.Pool.Exec(r.Context(), "UPDATE orders SET items = $1, subtotal = $2, service_fee = $3, total = $4, updated_at = NOW() WHERE order_number = $5",
		string(newItemsJSON), subtotal, serviceFee, total, req.OrderNumber)

	resp := map[string]interface{}{"order_number": req.OrderNumber, "subtotal": subtotal, "total": total}
	wss.H.BroadcastEvent("order:updated", resp)
	go wss.BroadcastShiftStatsExported()
	addSyncQueue("order:item_cancelled", resp)

	// Print cancel receipt for cancelled item
	var icTableSKU *string
	var icOrderType string
	db.Pool.QueryRow(r.Context(), "SELECT table_sku, type FROM orders WHERE order_number = $1", req.OrderNumber).Scan(&icTableSKU, &icOrderType)
	icTableStr := ""
	if icTableSKU != nil { icTableStr = *icTableSKU }
	// Build a single-item list for the cancelled product
	cancelledItem := []map[string]interface{}{
		{"product_id": req.ProductID, "quantity": req.CancelQty, "price": 0, "total": 0, "snapshot": findSnapshot(itemsJSON, req.ProductID)},
	}
	printer.PrintOrder(req.OrderNumber, icOrderType, icTableStr, time.Now().UTC().Format(time.RFC3339), claims.Name, cancelledItem, true)

	jsonResponse(w, 200, map[string]interface{}{
		"message": "Mahsulot bekor qilindi", "order_number": req.OrderNumber,
		"product_id": req.ProductID, "cancel_qty": req.CancelQty,
		"subtotal": subtotal, "total": total, "fully_cancelled": false,
	})
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
		Type     string `json:"type"`
		TableSKU *string `json:"table_sku"`
		Items    []struct {
			ProductID int     `json:"product_id"`
			Quantity  int     `json:"quantity"`
			Note      *string `json:"note"`
		} `json:"items"`
		Note *string `json:"note"`
	}
	json.NewDecoder(r.Body).Decode(&p)

	// Generate order number: YY-MM-DD-XX-YY
	// XX = bugun nechanchi sessiya (global, barcha stollar)
	// YY = shu sessiya ichida nechanchi chek
	// Saboy: 26-04-05-S-XX, Dostafka: 26-04-05-D-XX (har biri 1 sessiya = 1 chek)
	now := time.Now()
	datePrefix := now.Format("06-01-02")

	var orderNumber string

	if p.Type == "takeaway" || p.Type == "delivery" {
		// Saboy/Dostafka — har biri alohida sessiya
		prefix := "S"
		if p.Type == "delivery" {
			prefix = "D"
		}
		// Bugungi global sessiya soni
		var sessionCount int
		db.Pool.QueryRow(r.Context(), "SELECT COUNT(DISTINCT SPLIT_PART(order_number, '-', 4)) FROM orders WHERE created_at::date = CURRENT_DATE").Scan(&sessionCount)
		orderNumber = fmt.Sprintf("%s-%s-%02d", datePrefix, prefix, sessionCount+1)
	} else {
		// Dine-in — sessiya = bitta stolga to'lovgacha bo'lgan barcha cheklar
		// Bu stol uchun hozirgi aktiv sessiya bormi?
		var activeCount int
		db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed') AND created_at::date = CURRENT_DATE", p.TableSKU).Scan(&activeCount)

		if activeCount > 0 {
			// Sessiya davom etyapti — mavjud sessiya XX ni olish, YY ni oshirish
			var existingNum string
			db.Pool.QueryRow(r.Context(), "SELECT order_number FROM orders WHERE table_sku = $1 AND status NOT IN ('completed') AND created_at::date = CURRENT_DATE ORDER BY created_at DESC LIMIT 1", p.TableSKU).Scan(&existingNum)
			// Parse XX va YY
			parts := splitOrderNumber(existingNum)
			orderNumber = fmt.Sprintf("%s-%02d-%02d", datePrefix, parts[0], parts[1]+1)
		} else {
			// Yangi sessiya — XX ni hisoblash (bugungi global sessiya soni + 1)
			var sessionCount int
			db.Pool.QueryRow(r.Context(), "SELECT COUNT(DISTINCT SPLIT_PART(order_number, '-', 4)) FROM orders WHERE created_at::date = CURRENT_DATE").Scan(&sessionCount)
			orderNumber = fmt.Sprintf("%s-%02d-01", datePrefix, sessionCount+1)
		}
	}

	// Build items
	items := []map[string]interface{}{}
	subtotal := 0
	nowStr := now.UTC().Format(time.RFC3339)

	for i, item := range p.Items {
		var nameUz, nameRu, nameTr string
		var price, catID int
		var media json.RawMessage
		err := db.Pool.QueryRow(r.Context(), "SELECT name_uz, name_ru, name_tr, price, category_id, media FROM products WHERE id = $1 AND status = 'active'", item.ProductID).
			Scan(&nameUz, &nameRu, &nameTr, &price, &catID, &media)
		if err != nil { continue }

		// Stock tekshirish
		var stockCount *int
		db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&stockCount)
		if stockCount != nil && *stockCount < item.Quantity {
			jsonError(w, 400, "out_of_stock", fmt.Sprintf("%s: faqat %d ta qolgan, %d ta so'raldi", nameUz, *stockCount, item.Quantity))
			return
		}

		snapshot, _ := json.Marshal(map[string]interface{}{
			"name": map[string]string{"uz": nameUz, "ru": nameRu, "tr": nameTr},
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
			"note": item.Note,
			"added_by": json.RawMessage(addedBy),
			"added_at": nowStr,
		})
	}

	serviceFee := 0
	if p.Type == "dine_in" { serviceFee = subtotal * 10 / 100 }
	total := subtotal + serviceFee

	itemsJSON, _ := json.Marshal(items)

	// Get table info
	var tableID, zoneID *int
	if p.TableSKU != nil {
		var tid, zid int
		db.Pool.QueryRow(r.Context(), "SELECT id, zone_id FROM tables WHERE sku = $1", *p.TableSKU).Scan(&tid, &zid)
		tableID = &tid
		zoneID = &zid
	}

	db.Pool.Exec(r.Context(), `INSERT INTO orders (order_number, type, table_sku, table_id, zone_id, items, subtotal, service_fee, total, payment_status, status, source, created_by, note, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'unpaid', 'new', 'pos', $10, $11, NOW(), NOW())`,
		orderNumber, p.Type, p.TableSKU, tableID, zoneID, itemsJSON, subtotal, serviceFee, total, claims.UserID, p.Note)

	// Update table status
	if p.TableSKU != nil && p.Type == "dine_in" {
		db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", *p.TableSKU)
	}

	// Decrease stock + broadcast
	for _, item := range p.Items {
		db.Pool.Exec(r.Context(), "UPDATE stocks SET count = count - $1, updated_at = NOW() WHERE product_id = $2 AND count >= $1", item.Quantity, item.ProductID)
		// Broadcast new count
		var newCount *int
		err := db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&newCount)
		if err == nil && newCount != nil {
			wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": item.ProductID, "count": *newCount, "reason": "sold"})
		}
	}

	// WSS broadcast
	orderResp := map[string]interface{}{
		"order_number": orderNumber, "type": p.Type, "table_sku": p.TableSKU,
		"status": "new", "items": json.RawMessage(itemsJSON),
		"subtotal": subtotal, "service_fee": serviceFee, "total": total,
		"source": "pos", "created_at": nowStr,
	}
	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})
	addSyncQueue("order:created", orderResp)

	// Print receipt
	tableSKUStr := ""
	if p.TableSKU != nil { tableSKUStr = *p.TableSKU }
	var printItems []map[string]interface{}
	json.Unmarshal(itemsJSON, &printItems)
	printer.PrintOrder(orderNumber, p.Type, tableSKUStr, nowStr, claims.Name, printItems, false)

	jsonResponse(w, 200, map[string]interface{}{
		"order_number": orderNumber, "total": total, "message": "Buyurtma yaratildi",
	})
}

// ============ POST /api/qr/order ============
// QR mijoz uchun — auth kerak emas
func handleQROrderCreate(w http.ResponseWriter, r *http.Request) {
	// Check shift
	var shiftStatus string
	err := db.Pool.QueryRow(r.Context(), "SELECT status FROM shifts WHERE status = 'open' LIMIT 1").Scan(&shiftStatus)
	if err != nil {
		jsonError(w, 400, "shift_required", "Smena ochilmagan")
		return
	}

	var p struct {
		TableSKU string `json:"table_sku"`
		Items    []struct {
			ProductID int `json:"product_id"`
			Quantity  int `json:"quantity"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if p.TableSKU == "" || len(p.Items) == 0 {
		jsonError(w, 400, "bad_request", "table_sku va items kerak")
		return
	}

	// Verify table exists
	var tableExists bool
	db.Pool.QueryRow(r.Context(), "SELECT EXISTS(SELECT 1 FROM tables WHERE sku = $1)", p.TableSKU).Scan(&tableExists)
	if !tableExists {
		jsonError(w, 404, "not_found", "Stol topilmadi")
		return
	}

	now := time.Now()
	datePrefix := now.Format("06-01-02")

	// Generate order number (dine_in)
	var orderNumber string
	var activeCount int
	db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM orders WHERE table_sku = $1 AND status NOT IN ('completed') AND created_at::date = CURRENT_DATE", p.TableSKU).Scan(&activeCount)

	if activeCount > 0 {
		var existingNum string
		db.Pool.QueryRow(r.Context(), "SELECT order_number FROM orders WHERE table_sku = $1 AND status NOT IN ('completed') AND created_at::date = CURRENT_DATE ORDER BY created_at DESC LIMIT 1", p.TableSKU).Scan(&existingNum)
		parts := splitOrderNumber(existingNum)
		orderNumber = fmt.Sprintf("%s-%02d-%02d", datePrefix, parts[0], parts[1]+1)
	} else {
		var sessionCount int
		db.Pool.QueryRow(r.Context(), "SELECT COUNT(DISTINCT SPLIT_PART(order_number, '-', 4)) FROM orders WHERE created_at::date = CURRENT_DATE").Scan(&sessionCount)
		orderNumber = fmt.Sprintf("%s-%02d-01", datePrefix, sessionCount+1)
	}

	// Build items
	items := []map[string]interface{}{}
	subtotal := 0
	nowStr := now.UTC().Format(time.RFC3339)

	for i, item := range p.Items {
		var nameUz, nameRu, nameTr string
		var price, catID int
		var media json.RawMessage
		err := db.Pool.QueryRow(r.Context(), "SELECT name_uz, name_ru, name_tr, price, category_id, media FROM products WHERE id = $1 AND status = 'active'", item.ProductID).
			Scan(&nameUz, &nameRu, &nameTr, &price, &catID, &media)
		if err != nil {
			continue
		}

		// Stock check
		var stockCount *int
		db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&stockCount)
		if stockCount != nil && *stockCount < item.Quantity {
			jsonError(w, 400, "out_of_stock", fmt.Sprintf("%s: faqat %d ta qolgan", nameUz, *stockCount))
			return
		}

		snapshot, _ := json.Marshal(map[string]interface{}{
			"name": map[string]string{"uz": nameUz, "ru": nameRu, "tr": nameTr},
			"price": price, "category_id": catID, "media": media,
		})
		addedBy, _ := json.Marshal(map[string]interface{}{
			"type": "qr", "name": "QR Mijoz", "user_id": nil,
		})

		itemTotal := price * item.Quantity
		subtotal += itemTotal

		items = append(items, map[string]interface{}{
			"id": i + 1, "product_id": item.ProductID,
			"snapshot": json.RawMessage(snapshot),
			"quantity": item.Quantity, "price": price, "total": itemTotal,
			"note": nil,
			"added_by": json.RawMessage(addedBy),
			"added_at": nowStr,
		})
	}

	if len(items) == 0 {
		jsonError(w, 400, "no_items", "Hech qanday mahsulot topilmadi")
		return
	}

	serviceFee := subtotal * 10 / 100
	total := subtotal + serviceFee
	itemsJSON, _ := json.Marshal(items)

	var tableID, zoneID int
	db.Pool.QueryRow(r.Context(), "SELECT id, zone_id FROM tables WHERE sku = $1", p.TableSKU).Scan(&tableID, &zoneID)

	db.Pool.Exec(r.Context(), `INSERT INTO orders (order_number, type, table_sku, table_id, zone_id, items, subtotal, service_fee, total, payment_status, status, source, note, created_at, updated_at)
		VALUES ($1, 'dine_in', $2, $3, $4, $5, $6, $7, $8, 'unpaid', 'new', 'qr', NULL, NOW(), NOW())`,
		orderNumber, p.TableSKU, tableID, zoneID, itemsJSON, subtotal, serviceFee, total)

	// Update table status
	db.Pool.Exec(r.Context(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", p.TableSKU)

	// Decrease stock + broadcast
	for _, item := range p.Items {
		db.Pool.Exec(r.Context(), "UPDATE stocks SET count = count - $1, updated_at = NOW() WHERE product_id = $2 AND count >= $1", item.Quantity, item.ProductID)
		var newCount *int
		err := db.Pool.QueryRow(r.Context(), "SELECT count FROM stocks WHERE product_id = $1", item.ProductID).Scan(&newCount)
		if err == nil && newCount != nil {
			wss.H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": item.ProductID, "count": *newCount, "reason": "sold"})
		}
	}

	// WSS broadcast
	orderResp := map[string]interface{}{
		"order_number": orderNumber, "type": "dine_in", "table_sku": p.TableSKU,
		"status": "new", "items": json.RawMessage(itemsJSON),
		"subtotal": subtotal, "service_fee": serviceFee, "total": total,
		"source": "qr", "created_at": nowStr,
	}
	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})
	addSyncQueue("order:created", orderResp)

	// Print receipt (QR order)
	var qrPrintItems []map[string]interface{}
	json.Unmarshal(itemsJSON, &qrPrintItems)
	printer.PrintOrder(orderNumber, "dine_in", p.TableSKU, nowStr, "QR Mijoz", qrPrintItems, false)

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
		// Find first active printer
		db.Pool.QueryRow(r.Context(), "SELECT address FROM printer_stations WHERE status = 'active' ORDER BY id LIMIT 1").Scan(&req.PrinterAddress)
		if req.PrinterAddress == "" {
			jsonError(w, 400, "no_printer", "Printer topilmadi")
			return
		}
	}

	// Get orders
	var rows interface{ Close() }
	var err error
	if req.OrderNumber != "" {
		r2, e := db.Pool.Query(r.Context(), "SELECT order_number, type, table_sku, items, subtotal, service_fee, discount, total, payment_method FROM orders WHERE order_number = $1", req.OrderNumber)
		rows = r2
		err = e
		if err == nil {
			defer r2.Close()
			for r2.Next() {
				var orderNum, orderType, pm string
				var tsku *string
				var itemsJSON []byte
				var sub, sf, disc, tot int
				r2.Scan(&orderNum, &orderType, &tsku, &itemsJSON, &sub, &sf, &disc, &tot, &pm)
				tableSKU := ""
				if tsku != nil { tableSKU = *tsku }
				var items []map[string]interface{}
				json.Unmarshal(itemsJSON, &items)
				serviceFeeCancelled := disc > 0 && sf == 0
				printer.PrintReceipt(req.PrinterAddress, orderNum, orderType, tableSKU, items, sub, sf, disc, tot, pm, serviceFeeCancelled)
			}
		}
	} else if req.TableSKU != "" {
		r2, e := db.Pool.Query(r.Context(), "SELECT order_number, type, table_sku, items, subtotal, service_fee, discount, total, payment_method FROM orders WHERE table_sku = $1 AND status NOT IN ('cancelled', 'completed') ORDER BY created_at", req.TableSKU)
		rows = r2
		err = e
		if err == nil {
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
				if tsku != nil { tableSKU = *tsku }
				var items []map[string]interface{}
				json.Unmarshal(itemsJSON, &items)
				allItems = append(allItems, items...)
				totalSub += sub
				totalSF += sf
				totalDisc += disc
				totalTot += tot
			}
			if len(allItems) > 0 {
				serviceFeeCancelled := totalDisc > 0 && totalSF == 0
				printer.PrintReceipt(req.PrinterAddress, orderNum, orderType, tableSKU, allItems, totalSub, totalSF, totalDisc, totalTot, pm, serviceFeeCancelled)
			}
		}
	} else {
		jsonError(w, 400, "bad_request", "order_number yoki table_sku kerak")
		return
	}
	_ = rows
	_ = err

	jsonResponse(w, 200, map[string]interface{}{"message": "Chek chiqarilmoqda"})
}

// ============ POST /api/qr/call-waiter ============

func handleCallWaiter(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TableSKU string `json:"table_sku"`
	}
	json.NewDecoder(r.Body).Decode(&req)
	if req.TableSKU == "" {
		jsonError(w, 400, "bad_request", "table_sku kerak")
		return
	}

	// Get table label
	var label string
	err := db.Pool.QueryRow(r.Context(), "SELECT label FROM tables WHERE sku = $1", req.TableSKU).Scan(&label)
	if err != nil {
		jsonError(w, 404, "not_found", "Stol topilmadi")
		return
	}

	// Stolni ovoz bilan chaqirish: zone audio + raqam audio
	// Masalan: "ZAL-3" → zal.m4a + 3.m4a
	playTableCall(label)

	// Broadcast to staff via WSS
	wss.H.BroadcastEvent("waiter:called", map[string]interface{}{
		"table_sku": req.TableSKU,
		"label":     label,
	})

	log.Printf("WAITER CALLED: %s (%s)", label, req.TableSKU)

	jsonResponse(w, 200, map[string]interface{}{"message": "Ofitsiant chaqirildi"})
}

func addSyncQueue(eventType string, data interface{}) {
	payload, _ := json.Marshal(data)
	db.Pool.Exec(context.Background(), "INSERT INTO sync_queue (event_type, payload, status, created_at) VALUES ($1, $2, 'pending', NOW())",
		eventType, string(payload))
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
	if req.Name != nil { db.Pool.Exec(ctx, "UPDATE printer_stations SET name = $1 WHERE id = $2", *req.Name, id) }
	if req.Address != nil { db.Pool.Exec(ctx, "UPDATE printer_stations SET address = $1 WHERE id = $2", *req.Address, id) }
	if req.Status != nil { db.Pool.Exec(ctx, "UPDATE printer_stations SET status = $1 WHERE id = $2", *req.Status, id) }

	jsonResponse(w, 200, map[string]interface{}{"message": "Printer yangilandi", "id": id})
}

// ============ DELETE /api/printers/:id ============

func handleDeletePrinter(w http.ResponseWriter, r *http.Request) {
	id, _ := strconv.Atoi(chi.URLParam(r, "id"))
	db.Pool.Exec(r.Context(), "UPDATE printer_stations SET status = 'inactive' WHERE id = $1", id)
	// Clear references
	db.Pool.Exec(r.Context(), "UPDATE categories SET printer_station_id = NULL WHERE printer_station_id = $1", id)
	db.Pool.Exec(r.Context(), "UPDATE products SET printer_station_id = NULL WHERE printer_station_id = $1", id)
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
	if req.NameUz != nil { db.Pool.Exec(ctx, "UPDATE categories SET name_uz = $1 WHERE id = $2", *req.NameUz, id) }
	if req.NameRu != nil { db.Pool.Exec(ctx, "UPDATE categories SET name_ru = $1 WHERE id = $2", *req.NameRu, id) }
	if req.NameTr != nil { db.Pool.Exec(ctx, "UPDATE categories SET name_tr = $1 WHERE id = $2", *req.NameTr, id) }
	if req.Icon != nil { db.Pool.Exec(ctx, "UPDATE categories SET icon = $1 WHERE id = $2", *req.Icon, id) }
	if req.Status != nil { db.Pool.Exec(ctx, "UPDATE categories SET status = $1 WHERE id = $2", *req.Status, id) }
	if req.PrinterStationID != nil {
		if *req.PrinterStationID == 0 {
			db.Pool.Exec(ctx, "UPDATE categories SET printer_station_id = NULL WHERE id = $1", id)
		} else {
			db.Pool.Exec(ctx, "UPDATE categories SET printer_station_id = $1 WHERE id = $2", *req.PrinterStationID, id)
		}
	}

	db.Pool.Exec(ctx, "UPDATE menu_version SET version = version + 1, updated_at = NOW() WHERE id = 1")
	wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "category_updated"})

	jsonResponse(w, 200, map[string]interface{}{"message": "Kategoriya yangilandi", "id": id})
}
