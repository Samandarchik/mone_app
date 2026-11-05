package sync

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"konak-local/internal/db"
	"konak-local/internal/wss"
)

// Node identity + rol (main.go dan Configure orqali beriladi).
var (
	nodeID    = "local"
	syncMode  = "dialer" // "dialer" | "acceptor" | "off"
	syncToken = ""
)

// Configure — main.go ishga tushishida chaqiriladi.
func Configure(id, mode, token string) {
	if id != "" {
		nodeID = id
	}
	if mode != "" {
		syncMode = mode
	}
	syncToken = token
}

// NodeID — shu node origin belgisi.
func NodeID() string { return nodeID }

// SyncMode — "dialer" | "acceptor" | "off".
func SyncMode() string { return syncMode }

// ApplyEvent — kelgan eventni idempotent (bir marta) qo'llaydi.
//
// TARTIB MUHIM (2026-08-16 da tuzatildi): ilgari `sync_applied`ga yozuv
// handler ishga tushishidan OLDIN qo'yilardi. Handler xato bersa (masalan
// mahsulot o'z kategoriyasidan oldin kelsa — FK xatosi) event abadiy
// "qo'llangan" deb belgilanardi va qayta urinish imkoni yo'q edi — aynan
// shu sabab cloud'da xodim "Fotima" va ZAL/TASHQARI zonalari paydo
// bo'lmagan. Endi: avval qo'llanadi, MUVAFFAQIYATLI bo'lsagina belgilanadi;
// xato bo'lsa `sync_failed`ga tushib qayta uriniladi.
func ApplyEvent(eventID, origin, eventType string, data json.RawMessage) error {
	ctx := context.Background()

	if eventID != "" {
		var applied bool
		db.Pool.QueryRow(ctx,
			"SELECT EXISTS(SELECT 1 FROM sync_applied WHERE event_id=$1)", eventID).Scan(&applied)
		if applied {
			return nil
		}
	}

	if err := dispatchEvent(origin, eventType, data); err != nil {
		recordFailure(eventID, origin, eventType, data, err)
		return err
	}

	if eventID != "" {
		db.Pool.Exec(ctx,
			`INSERT INTO sync_applied (event_id, origin, event_type) VALUES ($1,$2,$3)
			 ON CONFLICT (event_id) DO NOTHING`, eventID, origin, eventType)
		db.Pool.Exec(ctx, `DELETE FROM sync_failed WHERE event_id=$1`, eventID)
	}
	return nil
}

// dispatchEvent — eventni tegishli handlerga uzatadi.
//
// Bazadagi HOLAT endi faqat `row:*` eventlari orqali ko'chadi (to'liq qator,
// hamma ustuni bilan). Eski nomli eventlar esa faqat JONLI xabar sifatida
// qoldi: ular ilova ekranini yangilaydi, bazaga tegmaydi. Sabab: bitta
// o'zgarishni ikki yo'l bilan yozish qaysi biri "to'g'ri"ligini noaniq
// qilardi va replikadagi yozuv qaytadan event tug'dirib, aylanma hosil
// qilardi.
func dispatchEvent(origin, eventType string, data json.RawMessage) error {
	switch eventType {
	// ---- Holat (baza) ----
	case "row:upsert":
		return applyRowUpsert(origin, data)
	case "row:delete":
		return applyRowDelete(data)
	case "table:prune":
		return applyTablePrune(origin, data)
	case "file:upsert":
		return applyFileUpsert(data)

	// ---- Xodim PINi (alohida: pin_hash node'ga xos, ko'chirib bo'lmaydi) ----
	case "user:created", "user:updated", "user:deleted":
		return applyUserPIN(data)

	// ---- Jonli xabarlar: faqat ekranni yangilaydi ----
	case "order:created":
		return broadcastLive("order:new", data, true)
	case "order:items_added", "order:item_cancelled":
		return broadcastLive("order:items_added", data, false)
	case "order:closed":
		return broadcastLive("order:closed", data, false)
	case "order:cancelled":
		return broadcastLive("order:cancelled", data, false)
	case "order:status_updated":
		return broadcastLive("order:status_updated", data, false)
	case "table:transferred":
		return broadcastLive("table:transferred", data, false)
	case "shift:opened":
		return broadcastLive("shift:opened", data, false)
	case "shift:closed":
		return broadcastLive("shift:closed", data, false)
	case "stock:updated":
		return broadcastLive("stock:updated", data, false)
	case "expense:created", "expense_category:created":
		return broadcastLive("expenses:updated", data, false)
	case "category:upserted", "product:upserted", "menu:updated":
		return broadcastLive("menu:outdated", data, false)
	case "zone:created", "zone:updated", "zone:deleted":
		return broadcastLive("zones:updated", data, false)

	default:
		// Noma'lum event — "qo'llandi" deb belgilanMAYDI, `sync_failed`ga
		// tushadi. Peer yangiroq versiyada bo'lsa, biz yangilangach qayta
		// urinishda qo'llanadi.
		return fmt.Errorf("noma'lum event turi: %s", eventType)
	}
}

// broadcastLive — eventni shu node'ning WSS mijozlariga uzatadi.
func broadcastLive(name string, data json.RawMessage, wrapOrder bool) error {
	var p map[string]interface{}
	if err := json.Unmarshal(data, &p); err != nil {
		return nil // buzuq jonli xabar holatga ta'sir qilmaydi
	}
	if wrapOrder {
		wss.H.BroadcastEvent(name, map[string]interface{}{"order": p})
		return nil
	}
	wss.H.BroadcastEvent(name, p)
	return nil
}

// buildSyncEventMsg — chiquvchi sync eventini envelope bilan tuzadi.
func buildSyncEventMsg(eventID, eventType, payload string) []byte {
	msg, _ := json.Marshal(map[string]interface{}{
		"event": "sync:event",
		"payload": map[string]interface{}{
			"event_id": eventID,
			"origin":   nodeID,
			"type":     eventType,
			"data":     json.RawMessage(payload),
		},
	})
	return msg
}

// toInt — JSON son (float64) yoki int ni int ga aylantiradi.
func toInt(v interface{}) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

func logApplied(what string, args ...interface{}) {
	log.Printf("SYNC: "+what, args...)
}
