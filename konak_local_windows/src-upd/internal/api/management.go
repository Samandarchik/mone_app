package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"unicode"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/security"
	"konak-local/internal/wss"
)

var allowedUserRoles = map[string]bool{
	"super_admin": true,
	"admin":       true,
	"cashier":     true,
	"waiter":      true,
	"kitchen":     true,
}

// canGrantRole — `super_admin` rolini FAQAT super_admin bera oladi.
//
// NEGA KERAK: `HasPermission` avval `custom_permissions` ga qaraydi. Ya'ni
// super_admin biror kassirga `{"users":["create","update"]}` bersa, o'sha
// kassir yangi super_admin yaratib yoki o'zini super_admin qilib, butun
// tizimni egallab olardi. Rol darajasi hech qayerda tekshirilmasdi.
func canGrantRole(r *http.Request, role string) bool {
	if role != "super_admin" {
		return true
	}
	claims := middleware.GetUser(r.Context())
	return claims != nil && claims.Role == "super_admin"
}

// canModifyTarget — mavjud super_admin hisobiga (rol/PIN) faqat super_admin
// tega oladi. Aks holda `users:update` berilgan oddiy xodim super_admin'ning
// PINini almashtirib, uning nomidan tizimga kirib olardi.
func canModifyTarget(r *http.Request, targetID int) bool {
	var targetRole string
	if err := db.Pool.QueryRow(r.Context(),
		"SELECT role FROM users WHERE id=$1", targetID).Scan(&targetRole); err != nil {
		return true // xodim topilmadi — quyidagi UPDATE baribir hech nima qilmaydi
	}
	if targetRole != "super_admin" {
		return true
	}
	claims := middleware.GetUser(r.Context())
	return claims != nil && claims.Role == "super_admin"
}

func normalizePhone(phone string) string {
	var digits strings.Builder
	for _, r := range phone {
		if unicode.IsDigit(r) && r <= unicode.MaxASCII {
			digits.WriteRune(r)
		}
	}
	value := digits.String()
	if len(value) == 9 {
		value = "998" + value
	}
	if len(value) == 12 && strings.HasPrefix(value, "998") {
		return "+" + value
	}
	return ""
}

func validateCustomPermissions(raw json.RawMessage) bool {
	if len(raw) == 0 || string(raw) == "null" {
		return true
	}
	var perms map[string][]string
	return json.Unmarshal(raw, &perms) == nil
}

// userSyncPayload — xodimning TO'LIQ holatini bazadan qayta o'qib, sync
// payloadini tuzadi. Ilgari `user:updated` faqat {"id":N} yuborardi, ya'ni
// qabul qiluvchi nima o'zgarganini bila olmasdi. To'liq snapshot yuborilsa
// qabul qiluvchidagi upsert idempotent bo'ladi.
//
// rawPIN bo'sh bo'lmasa — PIN shifrlangan holda `pin_enc` maydonida ketadi
// (qara: security.SealForSync). Ochiq PIN hech qachon yuborilmaydi.
func userSyncPayload(ctx context.Context, id int, rawPIN string) map[string]interface{} {
	var (
		name, phone, role, status string
		custom                    *string
	)
	err := db.Pool.QueryRow(ctx,
		"SELECT name, phone, role, status, custom_permissions::text FROM users WHERE id=$1", id,
	).Scan(&name, &phone, &role, &status, &custom)
	if err != nil {
		log.Printf("SYNC: user %d snapshotini o'qib bo'lmadi: %v", id, err)
		return map[string]interface{}{"id": id}
	}

	payload := map[string]interface{}{
		"id": id, "name": name, "phone": phone, "role": role, "status": status,
	}
	if custom != nil && *custom != "" && *custom != "null" {
		payload["custom_permissions"] = json.RawMessage(*custom)
	}
	if rawPIN != "" {
		if sealed, err := security.SealForSync(rawPIN); err == nil {
			payload["pin_enc"] = sealed
		} else {
			log.Printf("SYNC: user %d PINini shifrlab bo'lmadi: %v", id, err)
		}
	}
	return payload
}

// zoneSyncPayload — zonaning to'liq holati (stol soni bilan birga).
func zoneSyncPayload(ctx context.Context, id int) map[string]interface{} {
	var (
		name, status     string
		count, sortOrder int
	)
	err := db.Pool.QueryRow(ctx,
		"SELECT name, count, sort_order, status FROM zones WHERE id=$1", id,
	).Scan(&name, &count, &sortOrder, &status)
	if err != nil {
		log.Printf("SYNC: zone %d snapshotini o'qib bo'lmadi: %v", id, err)
		return map[string]interface{}{"id": id}
	}
	return map[string]interface{}{
		"id": id, "name": name, "count": count, "sort_order": sortOrder, "status": status,
	}
}

func handleCreateUser(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name              string          `json:"name"`
		Phone             string          `json:"phone"`
		Role              string          `json:"role"`
		PIN               string          `json:"pin"`
		CustomPermissions json.RawMessage `json:"custom_permissions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	req.Phone = normalizePhone(req.Phone)
	if req.Name == "" || len(req.Name) > 120 || req.Phone == "" || !allowedUserRoles[req.Role] ||
		!security.ValidatePIN(req.PIN) || !validateCustomPermissions(req.CustomPermissions) {
		jsonError(w, 400, "bad_request", "Ism, +998 telefon, rol va 4 xonali PINni to'g'ri kiriting")
		return
	}
	if !canGrantRole(r, req.Role) {
		jsonError(w, 403, "forbidden", "super_admin rolini faqat super_admin bera oladi")
		return
	}

	fingerprint, err := security.PINFingerprint(req.PIN)
	if err != nil {
		jsonError(w, 500, "security_error", err.Error())
		return
	}
	hash, err := security.HashPIN(req.PIN)
	if err != nil {
		jsonError(w, 500, "security_error", err.Error())
		return
	}

	var custom interface{}
	if len(req.CustomPermissions) > 0 && string(req.CustomPermissions) != "null" {
		custom = req.CustomPermissions
	}
	// PINning node'lararo ko'chiriladigan shifrlangan nusxasi — qator
	// replikatsiyasi bilan birga boradi, shu sababli to'liq resync'dan
	// keyin ham xodim ikkinchi node'da o'z PINi bilan kira oladi.
	sealedPIN, _ := security.SealForSync(req.PIN)

	var id int
	err = db.Pool.QueryRow(r.Context(), `
		INSERT INTO users (name, phone, role, pin, pin_hash, pin_sync, custom_permissions, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,'active') RETURNING id`,
		req.Name, req.Phone, req.Role, fingerprint, hash, sealedPIN, custom,
	).Scan(&id)
	if err != nil {
		jsonError(w, 409, "user_conflict", "Bu telefon yoki PIN boshqa faol xodimda mavjud")
		return
	}

	payload := map[string]interface{}{
		"id": id, "name": req.Name, "phone": req.Phone, "role": req.Role, "status": "active",
	}
	wss.H.BroadcastEvent("user:updated", payload)
	addSyncQueue("user:created", userSyncPayload(r.Context(), id, req.PIN))
	jsonResponse(w, 201, payload)
}

func handleUpdateUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "Xodim ID noto'g'ri")
		return
	}
	var req struct {
		Name              *string          `json:"name"`
		Phone             *string          `json:"phone"`
		Role              *string          `json:"role"`
		PIN               *string          `json:"pin"`
		CustomPermissions *json.RawMessage `json:"custom_permissions"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}

	claims := middleware.GetUser(r.Context())
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			jsonError(w, 400, "bad_request", "Ism bo'sh bo'lmasligi kerak")
			return
		}
		if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET name=$1, updated_at=NOW() WHERE id=$2 AND status='active'", name, id); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}
	if req.Phone != nil {
		phone := normalizePhone(*req.Phone)
		if phone == "" {
			jsonError(w, 400, "bad_request", "Telefon formati noto'g'ri")
			return
		}
		if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET phone=$1, updated_at=NOW() WHERE id=$2 AND status='active'", phone, id); err != nil {
			jsonError(w, 409, "phone_conflict", "Bu telefon boshqa xodimda mavjud")
			return
		}
	}
	if req.Role != nil {
		if !allowedUserRoles[*req.Role] {
			jsonError(w, 400, "bad_request", "Rol noto'g'ri")
			return
		}
		if !canGrantRole(r, *req.Role) {
			jsonError(w, 403, "forbidden", "super_admin rolini faqat super_admin bera oladi")
			return
		}
		// Mavjud super_admin'ni faqat super_admin o'zgartira oladi — aks holda
		// `users:update` berilgan oddiy xodim super_admin'ni pastga tushirib
		// (yoki PINini almashtirib) tizimni egallab olardi.
		if !canModifyTarget(r, id) {
			jsonError(w, 403, "forbidden", "super_admin hisobini faqat super_admin o'zgartira oladi")
			return
		}
		if claims != nil && claims.UserID == id && *req.Role != "super_admin" {
			jsonError(w, 409, "self_role_change", "O'zingizning super admin rolingizni olib tashlay olmaysiz")
			return
		}
		if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET role=$1, updated_at=NOW() WHERE id=$2 AND status='active'", *req.Role, id); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}
	if req.PIN != nil {
		if !security.ValidatePIN(*req.PIN) {
			jsonError(w, 400, "bad_request", "PIN 4 xonali raqam bo'lishi kerak")
			return
		}
		if !canModifyTarget(r, id) {
			jsonError(w, 403, "forbidden", "super_admin PINini faqat super_admin o'zgartira oladi")
			return
		}
		fingerprint, fpErr := security.PINFingerprint(*req.PIN)
		hash, hashErr := security.HashPIN(*req.PIN)
		if fpErr != nil || hashErr != nil {
			jsonError(w, 500, "security_error", "PINni xavfsiz saqlashda xato")
			return
		}
		sealedPIN, _ := security.SealForSync(*req.PIN)
		if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET pin=$1, pin_hash=$2, pin_sync=$3, updated_at=NOW() WHERE id=$4 AND status='active'", fingerprint, hash, sealedPIN, id); err != nil {
			jsonError(w, 409, "pin_conflict", "Bu PIN boshqa faol xodimda mavjud")
			return
		}
	}
	if req.CustomPermissions != nil {
		if !validateCustomPermissions(*req.CustomPermissions) {
			jsonError(w, 400, "bad_request", "custom_permissions formati noto'g'ri")
			return
		}
		if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET custom_permissions=$1, updated_at=NOW() WHERE id=$2 AND status='active'", *req.CustomPermissions, id); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}

	payload := map[string]interface{}{"id": id}
	wss.H.BroadcastEvent("user:updated", payload)
	rawPIN := ""
	if req.PIN != nil {
		rawPIN = *req.PIN
	}
	addSyncQueue("user:updated", userSyncPayload(r.Context(), id, rawPIN))
	jsonResponse(w, 200, map[string]interface{}{"message": "Xodim yangilandi", "id": id})
}

func handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "Xodim ID noto'g'ri")
		return
	}
	claims := middleware.GetUser(r.Context())
	if claims != nil && claims.UserID == id {
		jsonError(w, 409, "self_delete", "O'zingizni o'chira olmaysiz")
		return
	}

	var role string
	if err := db.Pool.QueryRow(r.Context(), "SELECT role FROM users WHERE id=$1 AND status='active'", id).Scan(&role); err != nil {
		jsonError(w, 404, "not_found", "Xodim topilmadi")
		return
	}
	if role == "super_admin" {
		var count int
		db.Pool.QueryRow(r.Context(), "SELECT COUNT(*) FROM users WHERE role='super_admin' AND status='active'").Scan(&count)
		if count <= 1 {
			jsonError(w, 409, "last_super_admin", "Oxirgi super adminni o'chirib bo'lmaydi")
			return
		}
	}
	if _, err := db.Pool.Exec(r.Context(), "UPDATE users SET status='deleted', updated_at=NOW() WHERE id=$1", id); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	payload := map[string]interface{}{"id": id, "status": "deleted"}
	wss.H.BroadcastEvent("user:updated", payload)
	addSyncQueue("user:updated", userSyncPayload(r.Context(), id, ""))
	jsonResponse(w, 200, map[string]interface{}{"message": "Xodim o'chirildi", "id": id})
}

func handleCreateZone(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name      string `json:"name"`
		Count     int    `json:"count"`
		SortOrder int    `json:"sort_order"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || req.Count < 0 || req.Count > 200 {
		jsonError(w, 400, "bad_request", "Zona nomi va 0..200 oralig'idagi stol soni kerak")
		return
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	if req.SortOrder == 0 {
		_ = tx.QueryRow(r.Context(), "SELECT COALESCE(MAX(sort_order),0)+1 FROM zones").Scan(&req.SortOrder)
	}
	var id int
	if err := tx.QueryRow(r.Context(),
		"INSERT INTO zones (name,count,sort_order,status) VALUES ($1,$2,$3,'active') RETURNING id",
		req.Name, req.Count, req.SortOrder,
	).Scan(&id); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	for number := 1; number <= req.Count; number++ {
		sku := fmt.Sprintf("Z%d-%d", id, number)
		label := fmt.Sprintf("%s-%d", strings.ToUpper(req.Name), number)
		if _, err := tx.Exec(r.Context(), `
			INSERT INTO tables (zone_id,sku,number,label,seats,status,qr_code)
			VALUES ($1,$2,$3,$4,4,'free',$5)`,
			id, sku, number, label, db.NewUUID(),
		); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	payload := map[string]interface{}{"id": id, "name": req.Name, "count": req.Count, "sort_order": req.SortOrder}
	wss.H.BroadcastEvent("zones:updated", payload)
	addSyncQueue("zone:created", zoneSyncPayload(r.Context(), id))
	jsonResponse(w, 201, payload)
}

func handleUpdateZone(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "Zona ID noto'g'ri")
		return
	}
	var req struct {
		Name      string `json:"name"`
		Count     int    `json:"count"`
		SortOrder int    `json:"sort_order"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || req.Count < 0 || req.Count > 200 {
		jsonError(w, 400, "bad_request", "Zona nomi va 0..200 oralig'idagi stol soni kerak")
		return
	}

	tx, err := db.Pool.Begin(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	var oldCount int
	if err := tx.QueryRow(r.Context(), "SELECT count FROM zones WHERE id=$1 AND status='active' FOR UPDATE", id).Scan(&oldCount); err != nil {
		jsonError(w, 404, "not_found", "Zona topilmadi")
		return
	}
	if req.Count < oldCount {
		var busy int
		_ = tx.QueryRow(r.Context(), `
			SELECT COUNT(*) FROM tables t
			WHERE t.zone_id=$1 AND t.number>$2 AND (
				t.status='occupied'
				OR EXISTS (SELECT 1 FROM table_locks l WHERE l.table_sku=t.sku)
				OR EXISTS (SELECT 1 FROM orders o WHERE o.table_sku=t.sku AND o.status NOT IN ('completed','cancelled'))
			)`, id, req.Count,
		).Scan(&busy)
		if busy > 0 {
			jsonError(w, 409, "tables_busy", "Kamaytirilayotgan stollardan biri band")
			return
		}
		if _, err := tx.Exec(r.Context(), "DELETE FROM tables WHERE zone_id=$1 AND number>$2", id, req.Count); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
	}
	if req.Count > oldCount {
		for number := oldCount + 1; number <= req.Count; number++ {
			sku := fmt.Sprintf("Z%d-%d", id, number)
			label := fmt.Sprintf("%s-%d", strings.ToUpper(req.Name), number)
			if _, err := tx.Exec(r.Context(), `
				INSERT INTO tables (zone_id,sku,number,label,seats,status,qr_code)
				VALUES ($1,$2,$3,$4,4,'free',$5)`,
				id, sku, number, label, db.NewUUID(),
			); err != nil {
				jsonError(w, 500, "db_error", err.Error())
				return
			}
		}
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE zones SET name=$1,count=$2,
			sort_order=CASE WHEN $3=0 THEN sort_order ELSE $3 END
		WHERE id=$4`,
		req.Name, req.Count, req.SortOrder, id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if _, err := tx.Exec(r.Context(), `
		UPDATE tables SET label=$1 || '-' || number WHERE zone_id=$2`,
		strings.ToUpper(req.Name), id,
	); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	payload := map[string]interface{}{"id": id, "name": req.Name, "count": req.Count, "sort_order": req.SortOrder}
	wss.H.BroadcastEvent("zones:updated", payload)
	addSyncQueue("zone:updated", zoneSyncPayload(r.Context(), id))
	jsonResponse(w, 200, payload)
}

func handleDeleteZone(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil || id <= 0 {
		jsonError(w, 400, "bad_request", "Zona ID noto'g'ri")
		return
	}
	var busy int
	_ = db.Pool.QueryRow(r.Context(), `
		SELECT COUNT(*) FROM tables t WHERE t.zone_id=$1 AND (
			t.status='occupied'
			OR EXISTS (SELECT 1 FROM table_locks l WHERE l.table_sku=t.sku)
			OR EXISTS (SELECT 1 FROM orders o WHERE o.table_sku=t.sku AND o.status NOT IN ('completed','cancelled'))
		)`, id,
	).Scan(&busy)
	if busy > 0 {
		jsonError(w, 409, "zone_busy", "Zonada band stol yoki ochiq buyurtma bor")
		return
	}
	tag, err := db.Pool.Exec(r.Context(), "UPDATE zones SET status='deleted' WHERE id=$1 AND status='active'", id)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		jsonError(w, 404, "not_found", "Zona topilmadi")
		return
	}
	payload := map[string]interface{}{"id": id, "status": "deleted"}
	wss.H.BroadcastEvent("zones:updated", payload)
	addSyncQueue("zone:updated", zoneSyncPayload(r.Context(), id))
	jsonResponse(w, 200, map[string]interface{}{"message": "Zona o'chirildi", "id": id})
}
