package audit

import (
	"context"
	"encoding/json"
	"log"
	"strings"

	"konak-local/internal/db"
)

type Entry struct {
	ActorID   *int
	ActorName string
	ActorRole string
	Action    string
	Entity    string
	EntityID  string
	Request   interface{}
	Response  interface{}
	Metadata  interface{}
	IP        string
}

func Log(ctx context.Context, entry Entry) {
	if db.Pool == nil {
		return
	}
	requestJSON, _ := json.Marshal(entry.Request)
	responseJSON, _ := json.Marshal(entry.Response)
	metadataJSON, _ := json.Marshal(entry.Metadata)
	if len(requestJSON) == 0 {
		requestJSON = []byte("{}")
	}
	if len(responseJSON) == 0 {
		responseJSON = []byte("{}")
	}
	if len(metadataJSON) == 0 {
		metadataJSON = []byte("{}")
	}
	if _, err := db.Pool.Exec(ctx, `
		INSERT INTO audit_logs
			(actor_id,actor_name,actor_role,action,entity_type,entity_id,
			 request_data,response_data,metadata,ip_address)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
		entry.ActorID, entry.ActorName, entry.ActorRole, entry.Action, entry.Entity,
		entry.EntityID, requestJSON, responseJSON, metadataJSON, entry.IP,
	); err != nil {
		log.Printf("AUDIT: yozishda xato: %v", err)
	}
}

func SanitizeJSON(data []byte) interface{} {
	if len(data) == 0 {
		return map[string]interface{}{}
	}
	var value interface{}
	if err := json.Unmarshal(data, &value); err != nil {
		return map[string]interface{}{"non_json": true, "size": len(data)}
	}
	return sanitize(value)
}

func sanitize(value interface{}) interface{} {
	switch typed := value.(type) {
	case map[string]interface{}:
		out := make(map[string]interface{}, len(typed))
		for key, child := range typed {
			lower := strings.ToLower(key)
			if strings.Contains(lower, "pin") ||
				strings.Contains(lower, "password") ||
				strings.Contains(lower, "secret") ||
				strings.Contains(lower, "token") ||
				strings.Contains(lower, "authorization") {
				out[key] = "[REDACTED]"
				continue
			}
			out[key] = sanitize(child)
		}
		return out
	case []interface{}:
		out := make([]interface{}, len(typed))
		for i, child := range typed {
			out[i] = sanitize(child)
		}
		return out
	default:
		return value
	}
}
