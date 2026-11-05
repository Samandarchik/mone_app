package sync

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"

	"konak-local/internal/db"
	"konak-local/internal/wss"
)

var cloudConn *websocket.Conn
var isConnected bool

// ConnectToCloud establishes WSS connection to cloud server
func ConnectToCloud(cloudWSURL, token string) {
	go func() {
		for {
			connect(cloudWSURL, token)
			log.Println("SYNC: cloud connection lost, reconnecting in 3s...")
			isConnected = false
			time.Sleep(3 * time.Second)
		}
	}()

	// Start sync queue processor
	go processSyncQueue()
}

func connect(url, token string) {
	fullURL := url + "?token=" + token
	var err error
	cloudConn, _, err = websocket.DefaultDialer.Dial(fullURL, nil)
	if err != nil {
		log.Printf("SYNC: failed to connect to cloud: %v", err)
		return
	}
	defer cloudConn.Close()
	isConnected = true
	log.Println("SYNC: connected to cloud")

	// Send reconnect with last sync time
	var lastSync string
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(MAX(synced_at), '') FROM sync_queue WHERE status = 'synced'").Scan(&lastSync)

	var pendingCount int
	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'").Scan(&pendingCount)

	msg, _ := json.Marshal(map[string]interface{}{
		"event": "sync:reconnect",
		"payload": map[string]interface{}{
			"last_sync_at":   lastSync,
			"pending_count":  pendingCount,
		},
	})
	cloudConn.WriteMessage(websocket.TextMessage, msg)

	// Listen for cloud events
	for {
		_, message, err := cloudConn.ReadMessage()
		if err != nil {
			return
		}
		handleCloudMessage(message)
	}
}

func handleCloudMessage(message []byte) {
	var event struct {
		Event   string          `json:"event"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(message, &event); err != nil {
		return
	}

	switch event.Event {
	case "sync:reconnect_ack":
		log.Println("SYNC: reconnect acknowledged by cloud")

	case "sync:event":
		handleSyncEvent(event.Payload)

	case "sync:batch":
		var batch struct {
			Events []json.RawMessage `json:"events"`
		}
		json.Unmarshal(event.Payload, &batch)
		for _, e := range batch.Events {
			handleSyncEvent(e)
		}

	case "ping":
		cloudConn.WriteMessage(websocket.TextMessage, []byte(`{"event":"pong"}`))
	}
}

func handleSyncEvent(payload json.RawMessage) {
	var syncEvent struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	json.Unmarshal(payload, &syncEvent)

	switch syncEvent.Type {
	case "order:created":
		// QR or delivery order from cloud → save locally → notify POS/kitchen
		handleCloudOrderCreated(syncEvent.Data)

	case "order:items_added":
		handleCloudOrderItemsAdded(syncEvent.Data)

	case "menu:updated":
		handleCloudMenuUpdated(syncEvent.Data)

	case "zone:created":
		handleCloudZoneCreated(syncEvent.Data)

	case "user:updated", "user:created":
		handleCloudUserUpdated(syncEvent.Data)

	case "expense_category:created":
		handleCloudExpenseCategoryCreated(syncEvent.Data)

	case "expense:created":
		handleCloudExpenseCreated(syncEvent.Data)

	default:
		log.Printf("SYNC: unknown event type: %s", syncEvent.Type)
	}

	// Send ack
	if cloudConn != nil {
		ack, _ := json.Marshal(map[string]string{"event": "sync:ack", "type": syncEvent.Type})
		cloudConn.WriteMessage(websocket.TextMessage, ack)
	}
}

func handleCloudOrderCreated(data json.RawMessage) {
	var order map[string]interface{}
	json.Unmarshal(data, &order)

	orderNumber, _ := order["order_number"].(string)
	orderType, _ := order["type"].(string)
	tableSKU, _ := order["table_sku"].(string)
	source, _ := order["source"].(string)
	itemsJSON, _ := json.Marshal(order["items"])
	total := int(order["total"].(float64))
	subtotal := int(order["subtotal"].(float64))

	var tskuPtr *string
	if tableSKU != "" {
		tskuPtr = &tableSKU
	}

	db.Pool.Exec(context.Background(), `INSERT INTO orders (order_number, type, table_sku, items, subtotal, service_fee, total, payment_status, status, source, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, 0, $6, 'unpaid', 'new', $7, NOW(), NOW()) ON CONFLICT (order_number) DO NOTHING`,
		orderNumber, orderType, tskuPtr, string(itemsJSON), subtotal, total, source)

	if tableSKU != "" {
		db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", tableSKU)
	}

	wss.H.BroadcastEvent("order:new", map[string]interface{}{"order": order})
	log.Printf("SYNC: cloud order received: %s type=%s source=%s", orderNumber, orderType, source)
}

func handleCloudOrderItemsAdded(data json.RawMessage) {
	var payload map[string]interface{}
	json.Unmarshal(data, &payload)
	wss.H.BroadcastEvent("order:items_added", payload)
}

func handleCloudMenuUpdated(data json.RawMessage) {
	// Re-fetch menu from cloud would be ideal, for now broadcast outdated
	var payload map[string]interface{}
	json.Unmarshal(data, &payload)
	if v, ok := payload["new_version"]; ok {
		db.Pool.Exec(context.Background(), "UPDATE menu_version SET version = $1, updated_at = NOW() WHERE id = 1", v)
	}
	wss.H.BroadcastEvent("menu:outdated", payload)
	log.Println("SYNC: menu updated from cloud")
}

func handleCloudZoneCreated(data json.RawMessage) {
	log.Println("SYNC: zone created from cloud — needs full sync")
}

func handleCloudUserUpdated(data json.RawMessage) {
	log.Println("SYNC: user updated from cloud — needs implementation")
}

func handleCloudExpenseCategoryCreated(data json.RawMessage) {
	log.Println("SYNC: expense category created from cloud")
}

func handleCloudExpenseCreated(data json.RawMessage) {
	var exp map[string]interface{}
	json.Unmarshal(data, &exp)

	catID := int(exp["category_id"].(float64))
	amount := int(exp["amount"].(float64))
	desc, _ := exp["description"].(string)
	date, _ := exp["date"].(string)
	createdByJSON, _ := json.Marshal(exp["created_by"])

	db.Pool.Exec(context.Background(), "INSERT INTO expenses (category_id, amount, description, date, created_by) VALUES ($1, $2, $3, $4, $5)",
		catID, amount, desc, date, string(createdByJSON))
	log.Printf("SYNC: expense received from cloud: %d so'm", amount)
}

// processSyncQueue sends pending events to cloud
func processSyncQueue() {
	for {
		time.Sleep(2 * time.Second)
		if !isConnected || cloudConn == nil {
			continue
		}

		rows, err := db.Pool.Query(context.Background(), "SELECT id, event_type, payload FROM sync_queue WHERE status = 'pending' ORDER BY id LIMIT 10")
		if err != nil {
			continue
		}

		for rows.Next() {
			var id int
			var eventType, payload string
			rows.Scan(&id, &eventType, &payload)

			msg, _ := json.Marshal(map[string]interface{}{
				"event": "sync:event",
				"payload": map[string]interface{}{
					"type":            eventType,
					"data":            json.RawMessage(payload),
					"local_timestamp": time.Now().UTC().Format(time.RFC3339),
				},
			})

			if err := cloudConn.WriteMessage(websocket.TextMessage, msg); err != nil {
				db.Pool.Exec(context.Background(), "UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = $1", id)
				break
			}

			db.Pool.Exec(context.Background(), "UPDATE sync_queue SET status = 'synced', synced_at = NOW() WHERE id = $1", id)
		}
		rows.Close()
	}
}

func IsConnected() bool {
	return isConnected
}
