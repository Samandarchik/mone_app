package sync

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"

	"konak-local/internal/db"
)

var (
	cloudLink   *wsLink
	isConnected bool
)

// Start — cloud sync sikli. URL/token har urinishda settings jadvalidan
// o'qiladi (cloud_ws_url, cloud_token): super_admin UI'da o'zgartirsa keyingi
// qayta-ulanishda kuchga kiradi; URL bo'sh bo'lsa server to'liq offline ishlaydi.
func Start() {
	StartFailedRetry()
	StartQueueJanitor()
	StartFileWatcher()

	// acceptor (cloud) rejimida bu node ulanishni QABUL qiladi (/sync endpoint),
	// o'zi ulanmaydi — shu sabab dialer sikli ishga tushmaydi.
	if syncMode != "dialer" {
		log.Printf("SYNC: rejim=%s (node=%s) — dialer o'chirilgan", syncMode, nodeID)
		return
	}

	go func() {
		loggedOffline := false
		for {
			url := db.GetSetting("cloud_ws_url")
			token := db.GetSetting("cloud_token")
			if url == "" {
				if !loggedOffline {
					log.Println("SYNC: cloud URL kiritilmagan — offline rejim (sozlamadan kiritilsa avto-ulanadi)")
					loggedOffline = true
				}
				isConnected = false
				time.Sleep(5 * time.Second)
				continue
			}
			loggedOffline = false
			connect(url, token)
			log.Println("SYNC: cloud connection lost, reconnecting in 3s...")
			isConnected = false
			time.Sleep(3 * time.Second)
		}
	}()
}

func connect(url, token string) {
	conn, _, err := websocket.DefaultDialer.Dial(url+"?token="+token, nil)
	if err != nil {
		log.Printf("SYNC: failed to connect to cloud: %v", err)
		return
	}
	defer conn.Close()

	link := &wsLink{conn: conn}
	cloudLink = link
	isConnected = true
	log.Println("SYNC: connected to cloud")

	var pendingCount int
	db.Pool.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM sync_queue WHERE status IN ('pending','sending')").Scan(&pendingCount)
	msg, _ := json.Marshal(map[string]interface{}{
		"event": "sync:reconnect",
		"payload": map[string]interface{}{
			"node_id":       nodeID,
			"pending_count": pendingCount,
		},
	})
	_ = link.send(msg)

	// Chiquvchi outbox — ack asosida (at-least-once).
	stop := make(chan struct{})
	go pumpOutbox(link, stop, false)
	defer close(stop)

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			cloudLink = nil
			return
		}
		handleCloudMessage(link, message)
	}
}

func handleCloudMessage(link *wsLink, message []byte) {
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
		applyIncoming(link, event.Payload)

	case "sync:batch":
		var batch struct {
			Events []json.RawMessage `json:"events"`
		}
		json.Unmarshal(event.Payload, &batch)
		for _, e := range batch.Events {
			applyIncoming(link, e)
		}

	case "sync:ack":
		var a struct {
			EventID string `json:"event_id"`
		}
		json.Unmarshal(message, &a)
		ackEvent(a.EventID)

	case "ping":
		_ = link.send([]byte(`{"event":"pong"}`))
	}
}

func IsConnected() bool {
	return isConnected
}
