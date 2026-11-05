package api

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"konak-local/internal/audit"
	"konak-local/internal/crm"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/printer"
	"konak-local/internal/wss"
)

type qrSessionInfo struct {
	ID        int
	Token     string
	TableSKU  string
	TableID   int
	ZoneID    int
	Label     string
	Status    string
	CreatedAt time.Time
	ExpiresAt time.Time
}

var qrServiceFeePercent = 10

func SetQRServiceFeePercent(percent int) {
	if percent >= 0 && percent <= 100 {
		qrServiceFeePercent = percent
	}
}

func decodePublicJSON(w http.ResponseWriter, r *http.Request, dst interface{}) error {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(dst)
}

func newSecureToken() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func handleQRSessionCreate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code string `json:"code"`
	}
	if err := decodePublicJSON(w, r, &req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Code = strings.TrimSpace(req.Code)
	if req.Code == "" {
		jsonError(w, 400, "bad_request", "QR kodi kerak")
		return
	}

	var tableID, zoneID int
	var tableSKU, label string
	err := db.Pool.QueryRow(r.Context(), `
		SELECT t.id,t.zone_id,t.sku,t.label
		FROM tables t JOIN zones z ON z.id=t.zone_id
		WHERE t.qr_code=$1 AND z.status='active'`,
		req.Code,
	).Scan(&tableID, &zoneID, &tableSKU, &label)
	if err != nil {
		jsonError(w, 404, "not_found", "QR kodga mos stol topilmadi")
		return
	}
	token, err := newSecureToken()
	if err != nil {
		jsonError(w, 500, "token_error", "Sessiya yaratilmadi")
		return
	}
	expiresAt := time.Now().Add(8 * time.Hour)
	if _, err := db.Pool.Exec(r.Context(), `
		INSERT INTO qr_sessions (table_sku,token,status,expires_at,last_seen_at)
		VALUES ($1,$2,'active',$3,NOW())`,
		tableSKU, token, expiresAt,
	); err != nil {
		jsonError(w, 500, "db_error", "Sessiya yaratilmadi")
		return
	}
	jsonResponse(w, 201, map[string]interface{}{
		"session_token": token,
		"expires_at":    expiresAt.UTC().Format(time.RFC3339),
		"table": map[string]interface{}{
			"table_sku": tableSKU, "table_id": tableID,
			"zone_id": zoneID, "label": label,
		},
	})
}

func loadQRSession(ctx context.Context, token string, allowClosed bool) (*qrSessionInfo, error) {
	statusClause := "s.status='active'"
	if allowClosed {
		statusClause = "s.status IN ('active','closed')"
	}
	var session qrSessionInfo
	err := db.Pool.QueryRow(ctx, `
		SELECT s.id,s.token,s.table_sku,t.id,t.zone_id,t.label,s.status,
		       s.created_at,COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')
		FROM qr_sessions s
		JOIN tables t ON t.sku=s.table_sku
		WHERE s.token=$1 AND `+statusClause+`
		  AND COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')>NOW()`,
		token,
	).Scan(
		&session.ID, &session.Token, &session.TableSKU, &session.TableID,
		&session.ZoneID, &session.Label, &session.Status, &session.CreatedAt,
		&session.ExpiresAt,
	)
	return &session, err
}

func qrTokenFromRequest(r *http.Request) string {
	if token := strings.TrimSpace(r.Header.Get("X-QR-Session")); token != "" {
		return token
	}
	return strings.TrimSpace(r.URL.Query().Get("token"))
}

func handleQRStatus(w http.ResponseWriter, r *http.Request) {
	session, err := loadQRSession(r.Context(), qrTokenFromRequest(r), true)
	if err != nil {
		jsonError(w, 401, "session_invalid", "QR sessiya tugagan yoki yaroqsiz")
		return
	}
	_, _ = db.Pool.Exec(r.Context(),
		"UPDATE qr_sessions SET last_seen_at=NOW() WHERE id=$1", session.ID)

	// Ikki xato bir vaqtda tuzatildi:
	//
	// 1) `created_at::date = CURRENT_DATE` — soat 00:00 da mijozning butun
	//    hisobi ekrandan YO'QOLARDI. 23:30 da o'tirgan mehmon yarim tunda
	//    "Jami hisob: 0 so'm" ko'rar, ofitsiantda esa to'liq chek turardi.
	//
	// 2) YOPILGAN cheklar `updated_at` bo'yicha kirardi. Oldingi mehmon
	//    ketib, ofitsiant chekini yopgan bo'lsa — yangi mehmon QR'ni
	//    skanerlaganda O'ZGA odamning cheki va summasi ko'rinardi.
	//    Endi yopilgan chek faqat SHU sessiya davomida yaratilgan bo'lsa
	//    ko'rinadi.
	//
	// Ochiq cheklar stolniki: ular hali to'lanmagan va aynan shu stolda
	// turgan mijozga tegishli.
	rows, err := db.Pool.Query(r.Context(), `
		SELECT order_number,status,items,subtotal,service_fee,discount,total,
		       payment_status,created_at,updated_at
		FROM orders
		WHERE table_sku=$1
		  AND (
		    status NOT IN ('completed','cancelled')
		    OR (created_at >= $2 AND updated_at >= $2)
		  )
		ORDER BY created_at`,
		session.TableSKU, session.CreatedAt.Add(-time.Minute),
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	orders := []map[string]interface{}{}
	grandTotal := 0
	for rows.Next() {
		var number, status, paymentStatus string
		var items json.RawMessage
		var subtotal, serviceFee, discount, total int
		var createdAt, updatedAt time.Time
		if err := rows.Scan(
			&number, &status, &items, &subtotal, &serviceFee, &discount, &total,
			&paymentStatus, &createdAt, &updatedAt,
		); err != nil {
			continue
		}
		if status != "cancelled" {
			grandTotal += total
		}
		orders = append(orders, map[string]interface{}{
			"order_number": number, "status": status, "items": items,
			"subtotal": subtotal, "service_fee": serviceFee,
			"discount": discount, "total": total, "payment_status": paymentStatus,
			"created_at": createdAt.UTC().Format(time.RFC3339),
			"updated_at": updatedAt.UTC().Format(time.RFC3339),
		})
	}
	jsonResponse(w, 200, map[string]interface{}{
		"session_status": session.Status,
		"expires_at":     session.ExpiresAt.UTC().Format(time.RFC3339),
		"table": map[string]interface{}{
			"table_sku": session.TableSKU, "table_id": session.TableID,
			"zone_id": session.ZoneID, "label": session.Label,
		},
		"orders": orders, "grand_total": grandTotal,
	})
}

func handleSecureQROrderCreate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionToken  string `json:"session_token"`
		Note          string `json:"note"`
		CustomerName  string `json:"customer_name"`
		CustomerPhone string `json:"customer_phone"`
		PromoCode     string `json:"promo_code"`
		Items         []struct {
			ProductID int    `json:"product_id"`
			Quantity  int    `json:"quantity"`
			Note      string `json:"note"`
		} `json:"items"`
	}
	if err := decodePublicJSON(w, r, &req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.SessionToken = strings.TrimSpace(req.SessionToken)
	req.Note = strings.TrimSpace(req.Note)
	req.CustomerName = strings.TrimSpace(req.CustomerName)
	rawCustomerPhone := strings.TrimSpace(req.CustomerPhone)
	req.CustomerPhone = crm.NormalizePhone(rawCustomerPhone)
	req.PromoCode = crm.NormalizePromoCode(req.PromoCode)
	if req.SessionToken == "" || len(req.Items) == 0 || len(req.Items) > 100 {
		jsonError(w, 400, "bad_request", "Sessiya va 1..100 ta mahsulot kerak")
		return
	}
	if len(req.CustomerName) > 120 {
		jsonError(w, 400, "bad_request", "Mijoz ismi juda uzun")
		return
	}
	if rawCustomerPhone != "" && req.CustomerPhone == "" {
		jsonError(w, 400, "bad_request", "Telefon raqami noto'g'ri")
		return
	}
	for _, item := range req.Items {
		if item.ProductID <= 0 || item.Quantity <= 0 || item.Quantity > 50 {
			jsonError(w, 400, "bad_request", "Mahsulot miqdori 1..50 bo'lishi kerak")
			return
		}
	}
	var shiftOpen bool
	_ = db.Pool.QueryRow(r.Context(),
		"SELECT EXISTS(SELECT 1 FROM shifts WHERE status='open')",
	).Scan(&shiftOpen)
	if !shiftOpen {
		jsonError(w, 409, "shift_required", "Hozir buyurtma qabul qilinmayapti")
		return
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	var session qrSessionInfo
	err = tx.QueryRow(r.Context(), `
		SELECT s.id,s.token,s.table_sku,t.id,t.zone_id,t.label,s.status,
		       s.created_at,COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')
		FROM qr_sessions s JOIN tables t ON t.sku=s.table_sku
		WHERE s.token=$1 AND s.status='active'
		  AND COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')>NOW()
		FOR UPDATE OF s`,
		req.SessionToken,
	).Scan(
		&session.ID, &session.Token, &session.TableSKU, &session.TableID,
		&session.ZoneID, &session.Label, &session.Status, &session.CreatedAt,
		&session.ExpiresAt,
	)
	if err != nil {
		jsonError(w, 401, "session_invalid", "QR sessiya tugagan yoki yaroqsiz")
		return
	}

	now := time.Now()
	nowString := now.UTC().Format(time.RFC3339)
	items := make([]map[string]interface{}, 0, len(req.Items))
	stockUpdates := make([]map[string]interface{}, 0, len(req.Items))
	subtotal := 0
	for index, requested := range req.Items {
		var nameUz, nameRu, nameTr string
		var price, categoryID, stockCount int
		var media json.RawMessage
		err := tx.QueryRow(r.Context(), `
			SELECT p.name_uz,p.name_ru,p.name_tr,p.price,p.category_id,p.media,s.count
			FROM products p JOIN stocks s ON s.product_id=p.id
			WHERE p.id=$1 AND p.status='active'
			FOR UPDATE OF s`,
			requested.ProductID,
		).Scan(&nameUz, &nameRu, &nameTr, &price, &categoryID, &media, &stockCount)
		if err != nil {
			jsonError(w, 404, "product_not_found", "Mahsulot topilmadi yoki sotuvda yo'q")
			return
		}
		if stockCount < requested.Quantity {
			jsonError(w, 409, "out_of_stock",
				fmt.Sprintf("%s: faqat %d ta qolgan", nameUz, stockCount))
			return
		}
		newCount := stockCount - requested.Quantity
		if _, err := tx.Exec(r.Context(),
			"UPDATE stocks SET count=$1,updated_at=NOW() WHERE product_id=$2",
			newCount, requested.ProductID,
		); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		itemTotal := price * requested.Quantity
		subtotal += itemTotal
		items = append(items, map[string]interface{}{
			"id": index + 1, "product_id": requested.ProductID,
			"snapshot": map[string]interface{}{
				"name":  map[string]string{"uz": nameUz, "ru": nameRu, "tr": nameTr},
				"price": price, "category_id": categoryID, "media": media,
			},
			"quantity": requested.Quantity, "price": price, "total": itemTotal,
			"note": strings.TrimSpace(requested.Note),
			"added_by": map[string]interface{}{
				"type": "qr", "name": "QR Mijoz", "user_id": nil,
			},
			"added_at": nowString,
		})
		stockUpdates = append(stockUpdates, map[string]interface{}{
			"product_id": requested.ProductID, "count": newCount, "reason": "sold",
		})
	}

	orderNumber, err := db.NextOrderNumber(r.Context(), tx, "qr")
	if err != nil {
		jsonError(w, 500, "order_number_error", err.Error())
		return
	}
	serviceFee := subtotal * qrServiceFeePercent / 100
	discount := 0
	promoCode := ""
	if req.PromoCode != "" {
		promo, err := crm.ApplyPromo(
			r.Context(), tx, req.PromoCode, subtotal, true,
		)
		if err != nil {
			writePromoError(w, err)
			return
		}
		promoCode = promo.Code
		discount = promo.Discount
	}
	total := subtotal + serviceFee - discount
	itemsJSON, _ := json.Marshal(items)
	if _, err := tx.Exec(r.Context(), `
		INSERT INTO orders
			(order_number,type,table_sku,table_id,zone_id,items,subtotal,
			 service_fee,discount,total,payment_status,status,source,note,
			 customer_name,customer_phone,promo_code,created_at,updated_at)
		VALUES ($1,'dine_in',$2,$3,$4,$5,$6,$7,$8,$9,'unpaid','new','qr',
		        $10,$11,$12,NULLIF($13,''),NOW(),NOW())`,
		orderNumber, session.TableSKU, session.TableID, session.ZoneID, itemsJSON,
		subtotal, serviceFee, discount, total, req.Note, req.CustomerName,
		req.CustomerPhone, promoCode,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	_, _ = tx.Exec(r.Context(),
		"UPDATE tables SET status='occupied' WHERE sku=$1", session.TableSKU)
	_, _ = tx.Exec(r.Context(), `
		UPDATE qr_sessions SET order_number=$1,last_seen_at=NOW() WHERE id=$2`,
		orderNumber, session.ID,
	)
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	orderPayload := map[string]interface{}{
		"order_number": orderNumber, "type": "dine_in",
		"table_sku": session.TableSKU, "status": "new", "items": items,
		"subtotal": subtotal, "service_fee": serviceFee, "total": total,
		"discount": discount, "promo_code": promoCode,
		"source": "qr", "created_at": nowString,
	}
	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": orderPayload})
	for _, update := range stockUpdates {
		pid, okID := update["product_id"].(int)
		cnt, okCount := update["count"].(int)
		if okID && okCount {
			wss.BroadcastStock(pid, &cnt, "sold")
			continue
		}
		wss.H.BroadcastEvent("stock:updated", update)
	}
	addSyncQueue("order:created", orderPayload)
	printer.PrintOrder(
		orderNumber, "dine_in", session.TableSKU, nowString,
		"QR Mijoz", items, false,
	)
	audit.Log(context.Background(), audit.Entry{
		ActorName: "QR " + session.Label, ActorRole: "guest",
		Action: "post", Entity: "qr_order", EntityID: orderNumber,
		Request: map[string]interface{}{
			"table_sku": session.TableSKU, "items_count": len(items),
		},
		Response: map[string]interface{}{"total": total}, IP: requestIP(r),
	})
	jsonResponse(w, 201, map[string]interface{}{
		"order_number": orderNumber, "total": total, "discount": discount,
		"promo_code": promoCode,
		"message":    "Buyurtma oshxonaga yuborildi",
	})
}

func handleSecureCallWaiter(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionToken string `json:"session_token"`
	}
	if decodePublicJSON(w, r, &req) != nil || strings.TrimSpace(req.SessionToken) == "" {
		jsonError(w, 400, "bad_request", "Sessiya kerak")
		return
	}
	var sessionID int
	var tableSKU, label string
	err := db.Pool.QueryRow(r.Context(), `
		UPDATE qr_sessions s SET call_waiter_at=NOW(),last_seen_at=NOW()
		FROM tables t
		WHERE s.token=$1 AND s.status='active'
		  AND COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')>NOW()
		  AND (s.call_waiter_at IS NULL OR s.call_waiter_at<NOW()-INTERVAL '60 seconds')
		  AND t.sku=s.table_sku
		RETURNING s.id,t.sku,t.label`,
		strings.TrimSpace(req.SessionToken),
	).Scan(&sessionID, &tableSKU, &label)
	if err != nil {
		jsonError(w, 429, "call_limited", "Ofitsiant allaqachon chaqirilgan, biroz kuting")
		return
	}
	playTableCall(label)
	wss.H.BroadcastEvent("waiter:called", map[string]interface{}{
		"table_sku": tableSKU, "label": label, "session_id": sessionID,
	})
	jsonResponse(w, 200, map[string]interface{}{"message": "Ofitsiant chaqirildi"})
}

func handleQRRequestBill(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionToken string `json:"session_token"`
	}
	if decodePublicJSON(w, r, &req) != nil || strings.TrimSpace(req.SessionToken) == "" {
		jsonError(w, 400, "bad_request", "Sessiya kerak")
		return
	}
	var tableSKU, label string
	err := db.Pool.QueryRow(r.Context(), `
		UPDATE qr_sessions s SET bill_requested_at=NOW(),last_seen_at=NOW()
		FROM tables t
		WHERE s.token=$1 AND s.status='active'
		  AND COALESCE(s.expires_at,s.created_at+INTERVAL '8 hours')>NOW()
		  AND (s.bill_requested_at IS NULL OR s.bill_requested_at<NOW()-INTERVAL '2 minutes')
		  AND t.sku=s.table_sku
		RETURNING t.sku,t.label`,
		strings.TrimSpace(req.SessionToken),
	).Scan(&tableSKU, &label)
	if err != nil {
		jsonError(w, 429, "bill_limited", "Hisob allaqachon so'ralgan, biroz kuting")
		return
	}
	wss.H.BroadcastEvent("bill:requested", map[string]interface{}{
		"table_sku": tableSKU, "label": label,
	})
	jsonResponse(w, 200, map[string]interface{}{"message": "Hisob so'rovi yuborildi"})
}

func requestIP(r *http.Request) string { return middleware.ClientIP(r) }
