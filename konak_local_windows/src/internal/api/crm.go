package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"konak-local/internal/crm"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
)

type customerInput struct {
	Name     string   `json:"name"`
	Phone    string   `json:"phone"`
	Birthday string   `json:"birthday"`
	Gender   string   `json:"gender"`
	Tags     []string `json:"tags"`
	Notes    string   `json:"notes"`
}

func handleGetCustomers(w http.ResponseWriter, r *http.Request) {
	search := strings.TrimSpace(r.URL.Query().Get("search"))
	limit := boundedQueryInt(r, "limit", 50, 1, 200)
	offset := boundedQueryInt(r, "offset", 0, 0, 1_000_000)
	pattern := "%" + search + "%"

	rows, err := db.Pool.Query(r.Context(), `
		SELECT id,phone,name,COALESCE(TO_CHAR(birthday,'YYYY-MM-DD'),''),
		       gender,tags,notes,loyalty_points,total_spent,visit_count,
		       last_visit_at,status,created_at,updated_at
		FROM customers
		WHERE status<>'deleted'
		  AND ($1='' OR phone ILIKE $2 OR name ILIKE $2)
		ORDER BY last_visit_at DESC NULLS LAST,created_at DESC
		LIMIT $3 OFFSET $4`,
		search, pattern, limit, offset,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		customer, err := scanCustomer(rows)
		if err == nil {
			items = append(items, customer)
		}
	}
	var total, activeMonth int
	var totalSpent, totalPoints int64
	_ = db.Pool.QueryRow(r.Context(), `
		SELECT COUNT(*),COALESCE(SUM(total_spent),0),
		       COALESCE(SUM(loyalty_points),0),
		       COUNT(*) FILTER (WHERE last_visit_at>=NOW()-INTERVAL '30 days')
		FROM customers
		WHERE status<>'deleted'
		  AND ($1='' OR phone ILIKE $2 OR name ILIKE $2)`,
		search, pattern,
	).Scan(&total, &totalSpent, &totalPoints, &activeMonth)
	jsonResponse(w, 200, map[string]interface{}{
		"items": items, "total": total, "limit": limit, "offset": offset,
		"summary": map[string]interface{}{
			"total_customers": total, "active_30_days": activeMonth,
			"total_spent": totalSpent, "outstanding_points": totalPoints,
		},
	})
}

type rowScanner interface {
	Scan(...any) error
}

func scanCustomer(row rowScanner) (map[string]interface{}, error) {
	var id, loyaltyPoints, totalSpent int64
	var phone, name, birthday, gender, notes, status string
	var tags json.RawMessage
	var visitCount int
	var lastVisit *time.Time
	var createdAt, updatedAt time.Time
	err := row.Scan(
		&id, &phone, &name, &birthday, &gender, &tags, &notes,
		&loyaltyPoints, &totalSpent, &visitCount, &lastVisit, &status,
		&createdAt, &updatedAt,
	)
	if err != nil {
		return nil, err
	}
	result := map[string]interface{}{
		"id": id, "phone": phone, "name": name, "birthday": birthday,
		"gender": gender, "tags": tags, "notes": notes,
		"loyalty_points": loyaltyPoints, "loyalty_value": loyaltyPoints * 100,
		"total_spent": totalSpent, "visit_count": visitCount, "status": status,
		"created_at": createdAt.UTC().Format(time.RFC3339),
		"updated_at": updatedAt.UTC().Format(time.RFC3339),
	}
	if lastVisit != nil {
		result["last_visit_at"] = lastVisit.UTC().Format(time.RFC3339)
	} else {
		result["last_visit_at"] = nil
	}
	return result, nil
}

func handleGetCustomer(w http.ResponseWriter, r *http.Request) {
	id, ok := customerIDFromRequest(w, r)
	if !ok {
		return
	}
	customer, err := scanCustomer(db.Pool.QueryRow(r.Context(), `
		SELECT id,phone,name,COALESCE(TO_CHAR(birthday,'YYYY-MM-DD'),''),
		       gender,tags,notes,loyalty_points,total_spent,visit_count,
		       last_visit_at,status,created_at,updated_at
		FROM customers WHERE id=$1 AND status<>'deleted'`,
		id,
	))
	if err != nil {
		jsonError(w, 404, "not_found", "Mijoz topilmadi")
		return
	}

	transactionRows, _ := db.Pool.Query(r.Context(), `
		SELECT id,order_number,type,points,balance_after,note,created_by,created_at
		FROM loyalty_transactions WHERE customer_id=$1
		ORDER BY created_at DESC LIMIT 100`,
		id,
	)
	transactions := []map[string]interface{}{}
	if transactionRows != nil {
		defer transactionRows.Close()
		for transactionRows.Next() {
			var transactionID, points, balance int64
			var orderNumber, kind, note, createdBy string
			var createdAt time.Time
			if transactionRows.Scan(
				&transactionID, &orderNumber, &kind, &points, &balance,
				&note, &createdBy, &createdAt,
			) == nil {
				transactions = append(transactions, map[string]interface{}{
					"id": transactionID, "order_number": orderNumber,
					"type": kind, "points": points, "balance_after": balance,
					"note": note, "created_by": createdBy,
					"created_at": createdAt.UTC().Format(time.RFC3339),
				})
			}
		}
	}

	orderRows, _ := db.Pool.Query(r.Context(), `
		SELECT order_number,type,total,status,payment_method,created_at
		FROM orders WHERE customer_id=$1
		ORDER BY created_at DESC LIMIT 50`,
		id,
	)
	orders := []map[string]interface{}{}
	if orderRows != nil {
		defer orderRows.Close()
		for orderRows.Next() {
			var number, orderType, status string
			var paymentMethod *string
			var total int
			var createdAt time.Time
			if orderRows.Scan(
				&number, &orderType, &total, &status, &paymentMethod, &createdAt,
			) == nil {
				orders = append(orders, map[string]interface{}{
					"order_number": number, "type": orderType, "total": total,
					"status": status, "payment_method": paymentMethod,
					"created_at": createdAt.UTC().Format(time.RFC3339),
				})
			}
		}
	}
	customer["transactions"] = transactions
	customer["orders"] = orders
	jsonResponse(w, 200, customer)
}

func handleCreateCustomer(w http.ResponseWriter, r *http.Request) {
	var input customerInput
	if err := decodeCRMJSON(w, r, &input); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validateCustomerInput(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	tags, _ := json.Marshal(input.Tags)
	var id int64
	err := db.Pool.QueryRow(r.Context(), `
		INSERT INTO customers (phone,name,birthday,gender,tags,notes)
		VALUES ($1,$2,NULLIF($3,'')::date,$4,$5,$6)
		RETURNING id`,
		input.Phone, input.Name, input.Birthday, input.Gender, tags, input.Notes,
	).Scan(&id)
	if err != nil {
		jsonError(w, 409, "customer_exists", "Bu telefon raqamli mijoz mavjud")
		return
	}
	jsonResponse(w, 201, map[string]interface{}{"id": id, "message": "Mijoz qo'shildi"})
}

func handleUpdateCustomer(w http.ResponseWriter, r *http.Request) {
	id, ok := customerIDFromRequest(w, r)
	if !ok {
		return
	}
	var input customerInput
	if err := decodeCRMJSON(w, r, &input); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validateCustomerInput(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	tags, _ := json.Marshal(input.Tags)
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE customers SET
			phone=$1,name=$2,birthday=NULLIF($3,'')::date,gender=$4,
			tags=$5,notes=$6,updated_at=NOW()
		WHERE id=$7 AND status<>'deleted'`,
		input.Phone, input.Name, input.Birthday, input.Gender, tags, input.Notes, id,
	)
	if err != nil {
		jsonError(w, 409, "customer_exists", "Telefon raqam band")
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Mijoz topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Mijoz yangilandi"})
}

func handleDeleteCustomer(w http.ResponseWriter, r *http.Request) {
	id, ok := customerIDFromRequest(w, r)
	if !ok {
		return
	}
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE customers SET status='deleted',updated_at=NOW()
		WHERE id=$1 AND status<>'deleted'`,
		id,
	)
	if err != nil || tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Mijoz topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Mijoz arxivlandi"})
}

func handleCustomerLoyalty(w http.ResponseWriter, r *http.Request) {
	id, ok := customerIDFromRequest(w, r)
	if !ok {
		return
	}
	var req struct {
		Type   string `json:"type"`
		Points int64  `json:"points"`
		Note   string `json:"note"`
	}
	if decodeCRMJSON(w, r, &req) != nil || req.Points == 0 {
		jsonError(w, 400, "bad_request", "Ball miqdori kerak")
		return
	}
	kind := strings.ToLower(strings.TrimSpace(req.Type))
	delta := req.Points
	switch kind {
	case "earn":
		if delta < 0 {
			delta = -delta
		}
	case "redeem":
		if delta > 0 {
			delta = -delta
		}
	case "adjust":
	default:
		jsonError(w, 400, "bad_request", "Tur: earn, redeem yoki adjust")
		return
	}
	claims := middleware.GetUser(r.Context())
	requiredAction := "update"
	if kind == "redeem" {
		requiredAction = "redeem"
	}
	if claims == nil || !middleware.HasPermission(claims, "loyalty", requiredAction) {
		jsonError(w, 403, "forbidden", "Ruxsat yo'q")
		return
	}
	if delta > 1_000_000 || delta < -1_000_000 {
		jsonError(w, 400, "bad_request", "Ball miqdori juda katta")
		return
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())
	var current int64
	if err := tx.QueryRow(r.Context(), `
		SELECT loyalty_points FROM customers
		WHERE id=$1 AND status<>'deleted' FOR UPDATE`,
		id,
	).Scan(&current); err != nil {
		jsonError(w, 404, "not_found", "Mijoz topilmadi")
		return
	}
	balance := current + delta
	if balance < 0 {
		jsonError(w, 409, "insufficient_points", "Mijozda yetarli ball yo'q")
		return
	}
	createdBy := ""
	if claims != nil {
		createdBy = claims.Name
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE customers SET loyalty_points=$1,updated_at=NOW() WHERE id=$2`,
		balance, id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if _, err := tx.Exec(r.Context(), `
		INSERT INTO loyalty_transactions
			(customer_id,type,points,balance_after,note,created_by)
		VALUES ($1,$2,$3,$4,$5,$6)`,
		id, kind, delta, balance, strings.TrimSpace(req.Note), createdBy,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"message": "Ball balansi yangilandi", "balance": balance,
		"loyalty_value": balance * 100,
	})
}

type promoInput struct {
	Code          string `json:"code"`
	DiscountType  string `json:"discount_type"`
	Value         int    `json:"value"`
	MinOrderTotal int    `json:"min_order_total"`
	MaxDiscount   *int   `json:"max_discount"`
	StartsAt      string `json:"starts_at"`
	EndsAt        string `json:"ends_at"`
	UsageLimit    *int   `json:"usage_limit"`
	Status        string `json:"status"`
}

func handleGetPromos(w http.ResponseWriter, r *http.Request) {
	rows, err := db.Pool.Query(r.Context(), `
		SELECT id,code,discount_type,value,min_order_total,max_discount,
		       starts_at,ends_at,usage_limit,used_count,status,created_by,
		       created_at,updated_at
		FROM promo_codes WHERE status<>'deleted'
		ORDER BY created_at DESC`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()
	items := []map[string]interface{}{}
	for rows.Next() {
		var id int64
		var code, discountType, status, createdBy string
		var value, minTotal, usedCount int
		var maxDiscount, usageLimit *int
		var startsAt, endsAt *time.Time
		var createdAt, updatedAt time.Time
		if rows.Scan(
			&id, &code, &discountType, &value, &minTotal, &maxDiscount,
			&startsAt, &endsAt, &usageLimit, &usedCount, &status, &createdBy,
			&createdAt, &updatedAt,
		) == nil {
			items = append(items, map[string]interface{}{
				"id": id, "code": code, "discount_type": discountType,
				"value": value, "min_order_total": minTotal,
				"max_discount": maxDiscount, "starts_at": formatOptionalTime(startsAt),
				"ends_at": formatOptionalTime(endsAt), "usage_limit": usageLimit,
				"used_count": usedCount, "status": status, "created_by": createdBy,
				"created_at": createdAt.UTC().Format(time.RFC3339),
				"updated_at": updatedAt.UTC().Format(time.RFC3339),
			})
		}
	}
	jsonResponse(w, 200, items)
}

func handleCreatePromo(w http.ResponseWriter, r *http.Request) {
	var input promoInput
	if decodeCRMJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validatePromoInput(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	claims := middleware.GetUser(r.Context())
	createdBy := ""
	if claims != nil {
		createdBy = claims.Name
	}
	var id int64
	err := db.Pool.QueryRow(r.Context(), `
		INSERT INTO promo_codes
			(code,discount_type,value,min_order_total,max_discount,
			 starts_at,ends_at,usage_limit,status,created_by)
		VALUES ($1,$2,$3,$4,$5,NULLIF($6,'')::timestamptz,
		        NULLIF($7,'')::timestamptz,$8,$9,$10)
		RETURNING id`,
		input.Code, input.DiscountType, input.Value, input.MinOrderTotal,
		input.MaxDiscount, input.StartsAt, input.EndsAt, input.UsageLimit,
		input.Status, createdBy,
	).Scan(&id)
	if err != nil {
		jsonError(w, 409, "promo_exists", "Bu promo kod mavjud")
		return
	}
	jsonResponse(w, 201, map[string]interface{}{"id": id, "message": "Promo kod yaratildi"})
}

func handleUpdatePromo(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "ID noto'g'ri")
		return
	}
	var input promoInput
	if decodeCRMJSON(w, r, &input) != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	if message := validatePromoInput(&input); message != "" {
		jsonError(w, 400, "validation_error", message)
		return
	}
	tag, err := db.Pool.Exec(r.Context(), `
		UPDATE promo_codes SET
			code=$1,discount_type=$2,value=$3,min_order_total=$4,
			max_discount=$5,starts_at=NULLIF($6,'')::timestamptz,
			ends_at=NULLIF($7,'')::timestamptz,usage_limit=$8,
			status=$9,updated_at=NOW()
		WHERE id=$10 AND status<>'deleted'`,
		input.Code, input.DiscountType, input.Value, input.MinOrderTotal,
		input.MaxDiscount, input.StartsAt, input.EndsAt, input.UsageLimit,
		input.Status, id,
	)
	if err != nil {
		jsonError(w, 409, "promo_exists", "Promo kod saqlanmadi")
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Promo kod topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Promo kod yangilandi"})
}

func handleDeletePromo(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "ID noto'g'ri")
		return
	}
	tag, _ := db.Pool.Exec(r.Context(), `
		UPDATE promo_codes SET status='deleted',updated_at=NOW()
		WHERE id=$1 AND status<>'deleted'`,
		id,
	)
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Promo kod topilmadi")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{"message": "Promo kod arxivlandi"})
}

func handleValidatePromo(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code         string `json:"code"`
		Subtotal     int    `json:"subtotal"`
		SessionToken string `json:"session_token"`
	}
	if decodeCRMJSON(w, r, &req) != nil || req.Subtotal < 0 {
		jsonError(w, 400, "bad_request", "Promo kod va summa kerak")
		return
	}
	// OCHIQ yo'l (`/api/qr/promo/validate`) uchun stol sessiyasi SHART.
	//
	// Ilgari bu endpoint umuman himoyalanmagan edi va javoblari bir-biridan
	// farq qilardi (404 "yo'q", 409 "minimal summa yetmadi", 200 + chegirma).
	// Ya'ni internetdagi istalgan kishi restoranning barcha promo kodlarini
	// va shartlarini birma-bir topib olishi mumkin edi — QR kodni skanerlash
	// ham shart emas edi.
	if middleware.GetUser(r.Context()) == nil {
		if _, err := loadQRSession(r.Context(), strings.TrimSpace(req.SessionToken), false); err != nil {
			jsonError(w, 401, "session_invalid", "QR sessiya kerak")
			return
		}
	}
	result, err := crm.ApplyPromo(r.Context(), db.Pool, req.Code, req.Subtotal, false)
	if err != nil {
		writePromoError(w, err)
		return
	}
	jsonResponse(w, 200, result)
}

func validateCustomerInput(input *customerInput) string {
	input.Name = strings.TrimSpace(input.Name)
	input.Phone = crm.NormalizePhone(input.Phone)
	input.Birthday = strings.TrimSpace(input.Birthday)
	input.Gender = strings.ToLower(strings.TrimSpace(input.Gender))
	input.Notes = strings.TrimSpace(input.Notes)
	if input.Phone == "" {
		return "Telefon raqami noto'g'ri"
	}
	if len(input.Name) > 120 || len(input.Notes) > 2000 {
		return "Matn juda uzun"
	}
	if input.Birthday != "" {
		birthday, err := time.Parse("2006-01-02", input.Birthday)
		if err != nil || birthday.After(time.Now()) {
			return "Tug'ilgan sana noto'g'ri"
		}
	}
	if input.Gender != "" && input.Gender != "male" && input.Gender != "female" {
		return "Jins qiymati noto'g'ri"
	}
	cleanTags := make([]string, 0, len(input.Tags))
	seen := map[string]bool{}
	for _, raw := range input.Tags {
		tag := strings.TrimSpace(raw)
		if tag == "" || len(tag) > 40 || seen[tag] {
			continue
		}
		seen[tag] = true
		cleanTags = append(cleanTags, tag)
		if len(cleanTags) == 20 {
			break
		}
	}
	input.Tags = cleanTags
	return ""
}

func validatePromoInput(input *promoInput) string {
	input.Code = crm.NormalizePromoCode(input.Code)
	input.DiscountType = strings.ToLower(strings.TrimSpace(input.DiscountType))
	input.Status = strings.ToLower(strings.TrimSpace(input.Status))
	input.StartsAt = strings.TrimSpace(input.StartsAt)
	input.EndsAt = strings.TrimSpace(input.EndsAt)
	if !crm.ValidPromoCode(input.Code) {
		return "Kod 3..32 ta lotin harfi, raqam, - yoki _ dan iborat bo'lsin"
	}
	if input.DiscountType != "percent" && input.DiscountType != "fixed" {
		return "Chegirma turi percent yoki fixed bo'lishi kerak"
	}
	if input.Value <= 0 || (input.DiscountType == "percent" && input.Value > 100) {
		return "Chegirma qiymati noto'g'ri"
	}
	if input.MinOrderTotal < 0 ||
		(input.MaxDiscount != nil && *input.MaxDiscount < 0) ||
		(input.UsageLimit != nil && *input.UsageLimit <= 0) {
		return "Limit qiymati noto'g'ri"
	}
	if input.Status == "" {
		input.Status = "active"
	}
	if input.Status != "active" && input.Status != "inactive" {
		return "Status active yoki inactive bo'lishi kerak"
	}
	var start, end *time.Time
	if input.StartsAt != "" {
		value, err := time.Parse(time.RFC3339, input.StartsAt)
		if err != nil {
			return "Boshlanish vaqti RFC3339 formatida bo'lishi kerak"
		}
		start = &value
	}
	if input.EndsAt != "" {
		value, err := time.Parse(time.RFC3339, input.EndsAt)
		if err != nil {
			return "Tugash vaqti RFC3339 formatida bo'lishi kerak"
		}
		end = &value
	}
	if start != nil && end != nil && !end.After(*start) {
		return "Tugash vaqti boshlanishdan keyin bo'lishi kerak"
	}
	return ""
}

func writePromoError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, crm.ErrPromoInvalid):
		jsonError(w, 404, "promo_invalid", "Promo kod topilmadi")
	case errors.Is(err, crm.ErrPromoMinimum):
		jsonError(w, 409, "promo_minimum", err.Error())
	case errors.Is(err, crm.ErrPromoLimit):
		jsonError(w, 409, "promo_limit", err.Error())
	default:
		jsonError(w, 409, "promo_inactive", err.Error())
	}
}

func decodeCRMJSON(w http.ResponseWriter, r *http.Request, target interface{}) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func customerIDFromRequest(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "ID noto'g'ri")
		return 0, false
	}
	return id, true
}

func boundedQueryInt(
	r *http.Request,
	key string,
	fallback, minimum, maximum int,
) int {
	value, err := strconv.Atoi(r.URL.Query().Get(key))
	if err != nil {
		return fallback
	}
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func formatOptionalTime(value *time.Time) interface{} {
	if value == nil {
		return nil
	}
	return value.UTC().Format(time.RFC3339)
}
