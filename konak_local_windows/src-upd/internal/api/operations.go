package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"konak-local/internal/backup"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/sync"
	"konak-local/internal/version"
)

var serverStartedAt = time.Now()

func buildHealth(parent context.Context) (int, map[string]interface{}) {
	ctx, cancel := context.WithTimeout(parent, 2*time.Second)
	defer cancel()

	dbStatus := "connected"
	statusCode := http.StatusOK
	started := time.Now()
	if db.Pool == nil || db.Pool.Ping(ctx) != nil {
		dbStatus = "disconnected"
		statusCode = http.StatusServiceUnavailable
	}
	dbLatency := time.Since(started).Milliseconds()

	var pendingSync int
	if db.Pool != nil && dbStatus == "connected" {
		_ = db.Pool.QueryRow(ctx,
			"SELECT COUNT(*) FROM sync_queue WHERE status='pending'",
		).Scan(&pendingSync)
	}
	status := "ok"
	if statusCode != http.StatusOK {
		status = "degraded"
	}
	return statusCode, map[string]interface{}{
		"status":         status,
		"version":        version.Version,
		"time":           time.Now().UTC().Format(time.RFC3339),
		"uptime_seconds": int64(time.Since(serverStartedAt).Seconds()),
		"db":             dbStatus,
		"db_latency_ms":  dbLatency,
		"sync_connected": sync.IsConnected(),
		"sync_pending":   pendingSync,
		"backup":         backup.Status(),
	}
}

func handleOperationsSummary(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()

	var activeOrders, pendingSync, failedSync, lowIngredients, cooking, openShifts int
	queries := []struct {
		target *int
		query  string
	}{
		{&activeOrders, "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed','cancelled')"},
		{&pendingSync, "SELECT COUNT(*) FROM sync_queue WHERE status='pending'"},
		{&failedSync, "SELECT COUNT(*) FROM sync_queue WHERE status='pending' AND retry_count>3"},
		{&lowIngredients, "SELECT COUNT(*) FROM ingredients WHERE status='active' AND count<min_qty"},
		{&cooking, "SELECT COUNT(*) FROM cookings WHERE status='cooking'"},
		{&openShifts, "SELECT COUNT(*) FROM shifts WHERE status='open'"},
	}
	for _, item := range queries {
		_ = db.Pool.QueryRow(ctx, item.query).Scan(item.target)
	}
	stats := db.Pool.Stat()
	jsonResponse(w, 200, map[string]interface{}{
		"active_orders":   activeOrders,
		"open_shifts":     openShifts,
		"cooking":         cooking,
		"low_ingredients": lowIngredients,
		"sync": map[string]interface{}{
			"connected": sync.IsConnected(),
			"pending":   pendingSync,
			"failed":    failedSync,
		},
		"database": map[string]interface{}{
			"total_connections":    stats.TotalConns(),
			"acquired_connections": stats.AcquiredConns(),
			"idle_connections":     stats.IdleConns(),
		},
		"backup":         backup.Status(),
		"uptime_seconds": int64(time.Since(serverStartedAt).Seconds()),
	})
}

func handleGetAuditLogs(w http.ResponseWriter, r *http.Request) {
	limit := 100
	if parsed, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && parsed > 0 {
		limit = parsed
	}
	if limit > 500 {
		limit = 500
	}
	actorID, _ := strconv.Atoi(r.URL.Query().Get("actor_id"))
	entity := strings.TrimSpace(r.URL.Query().Get("entity_type"))

	var from, to *time.Time
	if parsed, ok := parseAuditTime(r.URL.Query().Get("from"), false); ok {
		from = &parsed
	}
	if parsed, ok := parseAuditTime(r.URL.Query().Get("to"), true); ok {
		to = &parsed
	}

	rows, err := db.Pool.Query(r.Context(), `
		SELECT id,actor_id,actor_name,actor_role,action,entity_type,entity_id,
		       request_data,response_data,metadata,ip_address,created_at
		FROM audit_logs
		WHERE ($1::integer=0 OR actor_id=$1)
		  AND ($2::text='' OR entity_type=$2)
		  AND ($3::timestamptz IS NULL OR created_at >= $3)
		  AND ($4::timestamptz IS NULL OR created_at <= $4)
		ORDER BY id DESC LIMIT $5`,
		actorID, entity, from, to, limit,
	)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	items := []map[string]interface{}{}
	for rows.Next() {
		var id int64
		var actorID *int
		var actorName, actorRole, action, entityType, entityID, ip string
		var requestData, responseData, metadata json.RawMessage
		var createdAt time.Time
		if err := rows.Scan(
			&id, &actorID, &actorName, &actorRole, &action, &entityType, &entityID,
			&requestData, &responseData, &metadata, &ip, &createdAt,
		); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		items = append(items, map[string]interface{}{
			"id": id, "actor_id": actorID, "actor_name": actorName,
			"actor_role": actorRole, "action": action, "entity_type": entityType,
			"entity_id": entityID, "request_data": requestData,
			"response_data": responseData, "metadata": metadata,
			"ip_address": ip, "created_at": createdAt.UTC().Format(time.RFC3339),
		})
	}
	jsonResponse(w, 200, map[string]interface{}{"items": items})
}

func parseAuditTime(value string, endOfDay bool) (time.Time, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, false
	}
	if parsed, err := time.Parse(time.RFC3339, value); err == nil {
		return parsed, true
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, false
	}
	if endOfDay {
		parsed = parsed.Add(24*time.Hour - time.Nanosecond)
	}
	return parsed, true
}

func handleGetBackups(w http.ResponseWriter, r *http.Request) {
	items, err := backup.List()
	if err != nil {
		jsonError(w, 500, "backup_error", err.Error())
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"items": items, "status": backup.Status(),
	})
}

func handleCreateBackup(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	createdBy := "system"
	if claims != nil {
		createdBy = claims.Name
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Minute)
	defer cancel()
	meta, err := backup.Create(ctx, "manual", createdBy)
	if err != nil {
		jsonError(w, 500, "backup_error", err.Error())
		return
	}
	jsonResponse(w, 201, meta)
}

func handleDownloadBackup(w http.ResponseWriter, r *http.Request) {
	filename := chi.URLParam(r, "filename")
	path, err := backup.FilePath(filename)
	if err != nil {
		jsonError(w, 404, "not_found", "Backup topilmadi")
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, filename))
	http.ServeFile(w, r, path)
}

func handleScheduleRestore(w http.ResponseWriter, r *http.Request) {
	filename := chi.URLParam(r, "filename")
	if err := backup.ScheduleRestore(filename); err != nil {
		jsonError(w, 400, "restore_error", err.Error())
		return
	}
	jsonResponse(w, 202, map[string]interface{}{
		"message":          "Tiklash rejalashtirildi. Backendni qayta ishga tushiring.",
		"filename":         filename,
		"restart_required": true,
	})
}

func canReadFinanceDate(r *http.Request, date string) bool {
	claims := middleware.GetUser(r.Context())
	if middleware.HasPermission(claims, "finance", "read_any_day") {
		return true
	}
	return middleware.HasPermission(claims, "finance", "read_today") &&
		date == time.Now().Format("2006-01-02")
}
