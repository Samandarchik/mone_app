package sync

import (
	"crypto/subtle"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var peerUpgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// ServePeer — /sync endpoint. Local (dialer) shu yerga ulanadi.
// `?token=` sync token bilan mos kelishi kerak.
func ServePeer(w http.ResponseWriter, r *http.Request) {
	// Doimiy vaqtli solishtirish: oddiy `!=` birinchi mos kelmagan baytdayoq
	// to'xtaydi va javob vaqti orqali tokenni belgima-belgi topish mumkin.
	// Bu token butun bazaga yozish huquqini beradi — arzon himoya.
	given := r.URL.Query().Get("token")
	if syncToken == "" || subtle.ConstantTimeCompare([]byte(given), []byte(syncToken)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	conn, err := peerUpgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("SYNC(acceptor): upgrade xato: %v", err)
		return
	}
	defer conn.Close()
	// Rasm (file:upsert) eventlari base64 bilan bir necha MB bo'lishi mumkin.
	conn.SetReadLimit(16 << 20)
	link := &wsLink{conn: conn}
	log.Printf("SYNC(acceptor): peer ulandi (%s)", r.RemoteAddr)

	// Chiquvchi outbox'ni shu peer'ga uzatuvchi goroutine (keepalive bilan).
	stop := make(chan struct{})
	go pumpOutbox(link, stop, true)
	defer close(stop)

	conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("SYNC(acceptor): peer uzildi: %v", err)
			return
		}
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		handlePeerMessage(link, message)
	}
}

func handlePeerMessage(link *wsLink, message []byte) {
	var event struct {
		Event   string          `json:"event"`
		Payload json.RawMessage `json:"payload"`
	}
	if err := json.Unmarshal(message, &event); err != nil {
		return
	}

	switch event.Event {
	case "sync:reconnect":
		_ = link.send([]byte(`{"event":"sync:reconnect_ack"}`))

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

	case "pong":
		// e'tiborsiz

	default:
		log.Printf("SYNC(acceptor): noma'lum event '%s'", event.Event)
	}
}

// applyIncoming — kelgan eventni qo'llaydi va TASDIQ (ack) qaytaradi.
//
// Ack faqat event muvaffaqiyatli qo'llanganda (yoki keyinroq qayta urinish
// uchun `sync_failed`ga saqlanganda) yuboriladi — jo'natuvchi shundan keyingina
// uni `synced` deb belgilaydi.
func applyIncoming(link *wsLink, payload json.RawMessage) {
	var e struct {
		EventID string          `json:"event_id"`
		Origin  string          `json:"origin"`
		Type    string          `json:"type"`
		Data    json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(payload, &e); err != nil {
		return
	}
	_ = ApplyEvent(e.EventID, e.Origin, e.Type, e.Data)
	ack, _ := json.Marshal(map[string]string{"event": "sync:ack", "event_id": e.EventID})
	_ = link.send(ack)
}
