package middleware

import (
	"encoding/json"
	"net/http"
)

// Default role permissions
var RolePermissions = map[string]map[string][]string{
	"super_admin": {
		"restaurant":         {"create", "read", "update", "delete"},
		"zones":              {"create", "read", "update", "delete"},
		"tables":             {"create", "read", "update", "delete"},
		"categories":         {"create", "read", "update", "delete"},
		"products":           {"create", "read", "update", "delete"},
		"orders":             {"create", "read", "update", "delete", "cancel", "close", "add_items"},
		"payments":           {"create", "read", "refund"},
		"users":              {"create", "read", "update", "delete"},
		"reports":            {"read", "export"},
		"settings":           {"read", "update"},
		"menu_version":       {"update"},
		"permissions":        {"read", "update"},
		"expense_categories": {"create", "read", "update", "delete"},
		"expenses":           {"create", "read", "update", "delete"},
		"finance":            {"read_any_day"},
		"shifts":             {"open", "close", "read"},
		"table_transfer":     {"transfer"},
		"ingredients":        {"create", "read", "update", "delete"},
		"bozor":              {"create", "read", "delete"},
		"recipes":            {"create", "read", "update", "delete"},
		"cooking":            {"create", "read", "update"},
		"analytics":          {"read", "export"},
		"printers":           {"create", "read", "update", "delete"},
		"inventory":          {"create", "read"},
		"write_offs":         {"create", "read"},
		"audit":              {"read"},
		"backups":            {"create", "read", "restore"},
		"customers":          {"create", "read", "update", "delete"},
		"loyalty":            {"create", "read", "update", "redeem"},
		"suppliers":          {"create", "read", "update", "delete"},
		"ingredient_batches": {"create", "read", "update", "delete"},
		"monitoring":         {"read"},
	},
	"admin": {
		"zones":              {"create", "read", "update"},
		"tables":             {"create", "read", "update"},
		"categories":         {"create", "read", "update"},
		"products":           {"create", "read", "update"},
		"orders":             {"create", "read", "update", "cancel", "close", "add_items"},
		"payments":           {"create", "read"},
		"expense_categories": {"read"},
		"expenses":           {"create", "read", "delete"},
		"finance":            {"read_today"},
		"shifts":             {"open", "close", "read"},
		"table_transfer":     {"transfer"},
		"ingredients":        {"create", "read", "update", "delete"},
		"bozor":              {"create", "read", "delete"},
		"recipes":            {"create", "read", "update", "delete"},
		"cooking":            {"create", "read", "update"},
		"analytics":          {"read", "export"},
		"printers":           {"create", "read", "update"},
		"inventory":          {"create", "read"},
		"write_offs":         {"create", "read"},
		"customers":          {"create", "read", "update"},
		"loyalty":            {"create", "read", "update", "redeem"},
		"suppliers":          {"create", "read", "update"},
		"ingredient_batches": {"create", "read", "update"},
		"monitoring":         {"read"},
	},
	"cashier": {
		"zones":              {"read"},
		"tables":             {"read", "update"},
		"categories":         {"read"},
		"products":           {"read"},
		"orders":             {"create", "read", "update", "close", "cancel", "add_items"},
		"payments":           {"create", "read"},
		"expense_categories": {"read"},
		"expenses":           {"create", "read"},
		"reports":            {"read"},
		"shifts":             {"open", "close", "read"},
		"table_transfer":     {"transfer"},
		"write_offs":         {"create", "read"},
		"customers":          {"create", "read", "update"},
		"loyalty":            {"read", "redeem"},
	},
	"waiter": {
		"zones":      {"read"},
		"tables":     {"read"},
		"categories": {"read"},
		"products":   {"read"},
		"orders":     {"create", "read", "add_items"},
		"customers":  {"create", "read"},
		"loyalty":    {"read"},
	},
	"kitchen": {
		"categories":         {"read"},
		"products":           {"read"},
		"orders":             {"read", "update_status"},
		"cooking":            {"create", "read", "update"},
		"ingredient_batches": {"read"},
	},
}

// HasPermission checks if a user has a specific permission.
// claims nil bo'lishi MUMKIN: tokensiz WSS klienti (QR mijoz) "guest" bo'lib
// ulanadi va Token'i nil qoladi. Nil tekshiruvsiz bu yerda panic bo'lib,
// readPump goroutine'ida butun SERVER YIQILARDI — har qanday qurilma bir
// xabar bilan kassani to'xtata olardi.
func HasPermission(claims *TokenClaims, resource, action string) bool {
	if claims == nil {
		return false
	}

	// Tokendagi ruxsatlar — HUKMRON.
	//
	// MUHIM: bu yerda ilgari rol standartiga QAYTISH (fallback) bor edi va u
	// cheklashni butunlay ishlamas qilardi. Login paytida (handleLogin)
	// `custom_permissions` allaqachon rol standartlari USTIGA qo'yib,
	// birlashtirilgan ro'yxat tokenga yoziladi. Ya'ni token ichidagi ro'yxat
	// — yakuniy haqiqat.
	//
	// Fallback bo'lgani uchun: super_admin shubhali kassirdan `close`/`cancel`
	// ni olib tashlasa, tekshiruv tokendan topolmay rol standartiga qarardi
	// va u yerda `close` bor edi — xodim chek yopishda va chegirma berishda
	// davom etardi, admin esa uni to'xtatdim deb o'ylardi.
	if len(claims.Permissions) > 0 && string(claims.Permissions) != "null" {
		var custom map[string][]string
		if err := json.Unmarshal(claims.Permissions, &custom); err == nil {
			for _, a := range custom[resource] {
				if a == action {
					return true
				}
			}
			return false
		}
	}

	// Tokenda ruxsatlar yo'q (eski token) — rol standartiga qaraymiz.
	for _, a := range RolePermissions[claims.Role][resource] {
		if a == action {
			return true
		}
	}
	return false
}

// RequirePermission is HTTP middleware
func RequirePermission(resource, action string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := GetUser(r.Context())
			if claims == nil {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}
			if !HasPermission(claims, resource, action) {
				http.Error(w, `{"error":"forbidden","message":"Ruxsat yo'q"}`, http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r.WithContext(r.Context()))
		})
	}
}

// RequireAnyPermission allows endpoints whose accepted actions intentionally
// overlap (for example finance read_today/read_any_day or order cancel/close).
func RequireAnyPermission(resource string, actions ...string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := GetUser(r.Context())
			if claims == nil {
				http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
				return
			}
			for _, action := range actions {
				if HasPermission(claims, resource, action) {
					next.ServeHTTP(w, r)
					return
				}
			}
			http.Error(w, `{"error":"forbidden","message":"Ruxsat yo'q"}`, http.StatusForbidden)
		})
	}
}
