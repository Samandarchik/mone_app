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
	},
	"waiter": {
		"zones":      {"read"},
		"tables":     {"read"},
		"categories": {"read"},
		"products":   {"read"},
		"orders":     {"create", "read", "add_items"},
	},
	"kitchen": {
		"categories": {"read"},
		"products":   {"read"},
		"orders":     {"read", "update_status"},
	},
}

// HasPermission checks if a user has a specific permission
func HasPermission(claims *TokenClaims, resource, action string) bool {
	// Check custom permissions first
	if claims.Permissions != nil {
		var custom map[string][]string
		if err := json.Unmarshal(claims.Permissions, &custom); err == nil {
			if actions, ok := custom[resource]; ok {
				for _, a := range actions {
					if a == action {
						return true
					}
				}
			}
		}
	}

	// Fall back to role permissions
	if perms, ok := RolePermissions[claims.Role]; ok {
		if actions, ok := perms[resource]; ok {
			for _, a := range actions {
				if a == action {
					return true
				}
			}
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
