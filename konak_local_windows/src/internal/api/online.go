package api

// Online (saboy / dostafka) endpoints. Bot suhbati alohida `internal/telegram`
// paketda ishlaydi va shu jadval — `online_verifications` — orqali frontend
// (konak.uz/order/*) bilan bog'lanadi.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"konak-local/internal/crm"
	"konak-local/internal/db"
	"konak-local/internal/models"
	"konak-local/internal/printer"
	"konak-local/internal/telegram"
	"konak-local/internal/wss"
)

// onlineBot is set from main.go. Nil-safe: handlers degrade gracefully when
// the bot isn't configured (token unset).
var onlineBot *telegram.Bot

func SetOnlineBot(b *telegram.Bot) { onlineBot = b }

// ---------- POST /api/online/telegram/verify/start -------------------------

func handleOnlineVerifyStart(w http.ResponseWriter, r *http.Request) {
	if onlineBot == nil || onlineBot.Username == "" {
		jsonError(w, 503, "telegram_disabled", "Telegram bot sozlanmagan")
		return
	}
	var req struct {
		TgInitData *string `json:"tg_init_data"`
		PhoneHint  *string `json:"phone_hint"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req) // body ixtiyoriy

	code := telegram.NewCode()
	pendingToken := telegram.NewToken()
	const expiresInSec = 300

	_, err := db.Pool.Exec(r.Context(),
		`INSERT INTO online_verifications (code, pending_token, status, expires_at)
		 VALUES ($1, $2, 'pending', NOW() + ($3 || ' seconds')::interval)`,
		code, pendingToken, fmt.Sprintf("%d", expiresInSec))
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	jsonResponse(w, 200, map[string]interface{}{
		"code":          code,
		"bot_link":      onlineBot.DeepLink(code),
		"pending_token": pendingToken,
		"expires_in":    expiresInSec,
	})
}

// ---------- GET  /api/online/telegram/verify/check?token=... ---------------

func handleOnlineVerifyCheck(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		jsonError(w, 400, "bad_request", "token kerak")
		return
	}

	var (
		status     string
		verToken   *string
		tgUserID   *int64
		tgUsername *string
		phone      *string
		lat, lng   *float64
		expiresAt  time.Time
	)
	err := db.Pool.QueryRow(r.Context(),
		`SELECT status, verification_token, tg_user_id, tg_username, phone,
		        location_lat, location_lng, expires_at
		   FROM online_verifications WHERE pending_token = $1`, token).
		Scan(&status, &verToken, &tgUserID, &tgUsername, &phone, &lat, &lng, &expiresAt)
	if err != nil {
		jsonResponse(w, 200, map[string]string{"status": "expired"})
		return
	}
	if time.Now().After(expiresAt) && status == "pending" {
		jsonResponse(w, 200, map[string]string{"status": "expired"})
		return
	}
	if status == "pending" {
		jsonResponse(w, 200, map[string]string{"status": "pending"})
		return
	}
	// confirmed (or used — also fine to return back to client; verification_token won't work twice)
	resp := map[string]interface{}{
		"status":             "confirmed",
		"verification_token": stringPtrOr(verToken, ""),
		"tg_user_id":         int64PtrOr(tgUserID, 0),
		"tg_username":        stringPtrOr(tgUsername, ""),
		"phone":              stringPtrOr(phone, ""),
	}
	if lat != nil && lng != nil {
		resp["location"] = map[string]float64{"lat": *lat, "lng": *lng}
	}
	jsonResponse(w, 200, resp)
}

// ---------- POST /api/online/telegram/webapp ------------------------------
//
// Auto-login when the page is opened from inside the Telegram WebApp.
// Body: { "tg_init_data": "<raw initData query string>" }

func handleOnlineWebappAuth(w http.ResponseWriter, r *http.Request) {
	if onlineBot == nil {
		jsonError(w, 503, "telegram_disabled", "Telegram bot sozlanmagan")
		return
	}
	var req struct {
		TgInitData string `json:"tg_init_data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TgInitData == "" {
		jsonError(w, 400, "bad_request", "tg_init_data kerak")
		return
	}
	info, err := onlineBot.VerifyInitData(req.TgInitData)
	if err != nil {
		jsonError(w, 401, "invalid_init_data", err.Error())
		return
	}

	// Look up the latest contact this Telegram user already shared with the bot.
	var phone *string
	_ = db.Pool.QueryRow(r.Context(),
		`SELECT phone FROM online_verifications
		  WHERE tg_user_id = $1 AND phone IS NOT NULL
		  ORDER BY confirmed_at DESC NULLS LAST LIMIT 1`, info.UserID).Scan(&phone)

	verToken := telegram.NewToken()
	code := telegram.NewCode()
	pendingToken := telegram.NewToken()
	_, err = db.Pool.Exec(r.Context(),
		`INSERT INTO online_verifications
		    (code, pending_token, verification_token, status,
		     tg_user_id, tg_username, phone, expires_at, confirmed_at)
		 VALUES ($1, $2, $3, 'confirmed', $4, $5, $6, NOW() + INTERVAL '15 minutes', NOW())`,
		code, pendingToken, verToken, info.UserID, info.Username, phone)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	resp := map[string]interface{}{
		"verification_token": verToken,
		"tg_user_id":         info.UserID,
		"tg_username":        info.Username,
		"phone":              nil,
	}
	if phone != nil {
		resp["phone"] = *phone
	}
	jsonResponse(w, 200, resp)
}

// ---------- POST /api/online/order ----------------------------------------

func handleOnlineOrderCreate(w http.ResponseWriter, r *http.Request) {
	// Shift check (same as POS / QR)
	var shiftStatus string
	if err := db.Pool.QueryRow(r.Context(), "SELECT status FROM shifts WHERE status = 'open' LIMIT 1").Scan(&shiftStatus); err != nil {
		jsonError(w, 400, "shift_required", "Smena ochilmagan")
		return
	}

	var p struct {
		Type  string `json:"type"`
		Items []struct {
			ProductID int `json:"product_id"`
			Quantity  int `json:"quantity"`
		} `json:"items"`
		Customer struct {
			Phone             string `json:"phone"`
			TgUserID          int64  `json:"tg_user_id"`
			TgUsername        string `json:"tg_username"`
			VerificationToken string `json:"verification_token"`
		} `json:"customer"`
		Location *struct {
			Lat     float64 `json:"lat"`
			Lng     float64 `json:"lng"`
			Address string  `json:"address"`
		} `json:"location"`
		Note string `json:"note"`
	}
	// Bu endpoint OCHIQ (auth talab qilmaydi). Ilgari tana hajmi cheklanmagan
	// edi: istalgan kishi yuz megabaytli JSON yuborib serverni bo'g'ib
	// qo'ya olardi (QR yo'lida 64 KB chegara allaqachon bor edi).
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if p.Type != "takeaway" && p.Type != "delivery" {
		jsonError(w, 400, "bad_request", "type 'takeaway' yoki 'delivery' bo'lishi kerak")
		return
	}
	if len(p.Items) == 0 || len(p.Items) > 100 {
		jsonError(w, 400, "bad_request", "1..100 ta mahsulot kerak")
		return
	}
	if len(p.Note) > 500 || len(p.Customer.Phone) > 32 {
		jsonError(w, 400, "bad_request", "Izoh yoki telefon juda uzun")
		return
	}
	// Miqdor chegarasi. Tekshiruvsiz manfiy son yuborilsa jami summa MANFIY
	// bo'lardi va "count - (-100)" qoldiqni OSHIRIB yuborardi — ya'ni tashqi
	// foydalanuvchi o'ziga tekin mahsulot "yarata" olardi.
	for _, it := range p.Items {
		if it.Quantity <= 0 || it.Quantity > 50 {
			jsonError(w, 400, "bad_request", "har bir mahsulot miqdori 1..50 oralig'ida bo'lishi kerak")
			return
		}
	}
	if p.Customer.VerificationToken == "" {
		jsonError(w, 401, "verification_required", "verification_token kerak")
		return
	}
	if p.Type == "delivery" && p.Location == nil {
		jsonError(w, 400, "location_required", "Dostafka uchun manzil ko'rsatilmagan")
		return
	}

	// BUTUN buyurtma bitta tranzaksiyada. Ilgari tasdiqlash tokenini
	// tekshirish, chekni yozish, tokenni "used" qilish va qoldiqni kamaytirish
	// alohida so'rovlar edi. Ikki og'ir oqibati bor edi:
	//   - bir tokendan bir vaqtda N ta so'rov yuborilsa, hammasi tekshiruvdan
	//     o'tib N ta HAQIQIY buyurtma yaratardi (oshxonaga N ta chek);
	//   - qoldiq shartsiz kamaytirilardi: bitta so'rovda bir mahsulotni ikki
	//     qator qilib yuborish qoldiqni manfiyga tushirardi.
	ctx := r.Context()
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(ctx)

	// Token AYNI SHU YERDA iste'mol qilinadi: `status='confirmed'` sharti
	// bilan UPDATE — ikkinchi parallel so'rovga qator qolmaydi.
	var verID int
	var verPhone *string
	var verTgID *int64
	var verUsername *string
	var verNote *string
	var verLat, verLng *float64
	err = tx.QueryRow(ctx,
		`UPDATE online_verifications SET status = 'used'
		  WHERE verification_token = $1
		    AND status = 'confirmed'
		    AND expires_at > NOW()
		 RETURNING id, phone, tg_user_id, tg_username, note, location_lat, location_lng`,
		p.Customer.VerificationToken).
		Scan(&verID, &verPhone, &verTgID, &verUsername, &verNote, &verLat, &verLng)
	if err != nil {
		jsonError(w, 401, "verification_token_invalid", "Tasdiqlash muddati o'tgan, qayta urinib ko'ring")
		return
	}

	// Telefon — tasdiqlangani hukmron. Ilgari mijoz yuborgan satr to'g'ridan
	// to'g'ri chekka, kuryer QR'iga va admin xabariga tushardi (normalizatsiya
	// ham, uzunlik chegarasi ham yo'q edi).
	phone := crm.NormalizePhone(p.Customer.Phone)
	if phone == "" && verPhone != nil {
		phone = crm.NormalizePhone(*verPhone)
	}
	if phone == "" {
		jsonError(w, 400, "phone_required", "Telefon raqam kerak. Botga kontaktni yuboring.")
		return
	}
	// Telegram ID ham TASDIQLANGAN yozuvdan olinadi, mijoz tanasidan emas —
	// aks holda buyurtmani boshqa odamning Telegram hisobiga yozib qo'yish
	// mumkin edi.
	var tgUserID *int64 = verTgID

	now := time.Now()
	orderNumber, err := db.NextOrderNumber(ctx, tx, "online")
	if err != nil {
		jsonError(w, 500, "order_number_error", "Buyurtma raqami yaratilmadi")
		return
	}

	// Items + stock
	items := []map[string]interface{}{}
	subtotal := 0
	nowStr := now.UTC().Format(time.RFC3339)
	// Qabul qilingan qatorlar — qoldiq FAQAT shular bo'yicha kamayadi.
	accepted := []models.OrderItemPayload{}
	for i, item := range p.Items {
		var nameUz, nameRu, nameTr string
		var price, catID int
		var media json.RawMessage
		if err := tx.QueryRow(ctx,
			"SELECT name_uz, name_ru, name_tr, price, category_id, media FROM products WHERE id = $1 AND status = 'active'",
			item.ProductID).Scan(&nameUz, &nameRu, &nameTr, &price, &catID, &media); err != nil {
			continue
		}
		accepted = append(accepted, models.OrderItemPayload{
			ProductID: item.ProductID, Quantity: item.Quantity,
		})

		snapshot, _ := json.Marshal(map[string]interface{}{
			"name":        map[string]string{"uz": nameUz, "ru": nameRu, "tr": nameTr},
			"price":       price,
			"category_id": catID,
			"media":       media,
		})
		addedBy, _ := json.Marshal(map[string]interface{}{
			"type": "online", "name": "Online " + p.Type, "user_id": nil,
		})
		itemTotal := price * item.Quantity
		subtotal += itemTotal
		items = append(items, map[string]interface{}{
			"id":         i + 1,
			"product_id": item.ProductID,
			"snapshot":   json.RawMessage(snapshot),
			"quantity":   item.Quantity,
			"price":      price,
			"total":      itemTotal,
			"name":       nameUz,
			"note":       nil,
			"added_by":   json.RawMessage(addedBy),
			"added_at":   nowStr,
		})
	}
	if len(items) == 0 {
		jsonError(w, 400, "no_items", "Hech qanday mahsulot topilmadi")
		return
	}

	serviceFee := subtotal * wss.ServiceFeePercent() / 100
	deliveryFee := 0 // bepul; admin keyin yangilashi mumkin
	total := subtotal + serviceFee + deliveryFee
	itemsJSON, _ := json.Marshal(items)

	// Comment fallback — if user didn't send via web but did via bot, use bot.note
	note := strings.TrimSpace(p.Note)
	if note == "" && verNote != nil {
		note = strings.TrimSpace(*verNote)
	}

	// Location: prefer body, else verification.location_lat/lng (bot fallback)
	var lat, lng *float64
	var address string
	if p.Location != nil {
		latV := p.Location.Lat
		lngV := p.Location.Lng
		lat = &latV
		lng = &lngV
		address = strings.TrimSpace(p.Location.Address)
	} else if p.Type == "delivery" && verLat != nil && verLng != nil {
		lat = verLat
		lng = verLng
	}

	var deliveryJSON []byte
	if p.Type == "delivery" && lat != nil && lng != nil {
		deliveryJSON, _ = json.Marshal(map[string]interface{}{
			"lat":     *lat,
			"lng":     *lng,
			"address": address,
		})
	}

	// Qoldiq — ATOMAR, o'sha tranzaksiyada.
	reserved, err := wss.ReserveStockTx(ctx, tx, accepted)
	if err != nil {
		jsonError(w, 409, "stock_unavailable", err.Error())
		return
	}

	// Insert order
	if _, err := tx.Exec(ctx,
		`INSERT INTO orders
		   (order_number, type, table_sku, table_id, zone_id, delivery, items,
		    subtotal, service_fee, delivery_fee, total, payment_status, status, source,
		    customer_phone, tg_user_id, note, created_at, updated_at)
		 VALUES ($1, $2, NULL, NULL, NULL, $3, $4,
		         $5, $6, $7, $8, 'unpaid', 'new', 'online',
		         $9, $10, NULLIF($11, ''), NOW(), NOW())`,
		orderNumber, p.Type, nullableJSON(deliveryJSON), itemsJSON,
		subtotal, serviceFee, deliveryFee, total,
		phone, tgUserID, note); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	if _, err := tx.Exec(ctx,
		`UPDATE online_verifications SET used_for_order_number = $1 WHERE id = $2`,
		orderNumber, verID); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	if err := tx.Commit(ctx); err != nil {
		jsonError(w, 500, "db_error", "Buyurtma saqlanmadi: "+err.Error())
		return
	}

	// E'lonlar faqat commit'dan keyin.
	for pid, count := range reserved {
		newCount := count
		wss.BroadcastStock(pid, &newCount, "sold")
	}

	// QR payload — what the courier app will scan
	qrPayload := buildCourierPayload(orderNumber, phone, lat, lng)

	// WSS: tell POS / kitchen
	orderResp := map[string]interface{}{
		"order_number":   orderNumber,
		"type":           p.Type,
		"status":         "new",
		"items":          json.RawMessage(itemsJSON),
		"subtotal":       subtotal,
		"service_fee":    serviceFee,
		"delivery_fee":   deliveryFee,
		"total":          total,
		"source":         "online",
		"customer_phone": phone,
		"note":           note,
		"created_at":     nowStr,
	}
	if deliveryJSON != nil {
		orderResp["delivery"] = json.RawMessage(deliveryJSON)
	}
	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})
	addSyncQueue("order:created", orderResp)

	// Print receipt for kitchen
	printItems := []map[string]interface{}{}
	_ = json.Unmarshal(itemsJSON, &printItems)
	customerLabel := "Online " + p.Type
	tableLabel := "" // takeaway / delivery — stol yo'q
	printer.PrintOrder(orderNumber, p.Type, tableLabel, nowStr, customerLabel, printItems, false)

	// Telegram admin guruhga xabar
	if onlineBot != nil {
		go onlineBot.NotifyOnlineOrder(orderNumber, p.Type, phone, lat, lng, total, items, note)
	}

	jsonResponse(w, 200, map[string]interface{}{
		"order_number": orderNumber,
		"total":        total,
		"qr_payload":   qrPayload,
		"message":      "Buyurtma qabul qilindi",
	})
}

// ---------- helpers --------------------------------------------------------

func buildCourierPayload(orderNumber, phone string, lat, lng *float64) string {
	q := url.Values{}
	q.Set("phone", phone)
	if lat != nil && lng != nil {
		q.Set("lat", strconv.FormatFloat(*lat, 'f', 6, 64))
		q.Set("lng", strconv.FormatFloat(*lng, 'f', 6, 64))
	}
	return fmt.Sprintf("konak://order/%s?%s", orderNumber, q.Encode())
}

func nullableJSON(b []byte) interface{} {
	if b == nil {
		return nil
	}
	return b
}

func stringPtrOr(p *string, fallback string) string {
	if p == nil {
		return fallback
	}
	return *p
}

func int64PtrOr(p *int64, fallback int64) int64 {
	if p == nil {
		return fallback
	}
	return *p
}

// Background cleanup — expire pending verifications older than their TTL.
// Call periodically from main.go (every minute).
func StartOnlineVerificationCleanup(ctx context.Context) {
	go func() {
		t := time.NewTicker(60 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				_, _ = db.Pool.Exec(ctx,
					`UPDATE online_verifications SET status = 'expired'
					   WHERE status = 'pending' AND expires_at < NOW()`)
			}
		}
	}()
}
