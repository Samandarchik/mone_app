package sync

// ============================================================================
// OUTBOX — chiquvchi eventlarni peer'ga kafolatli yetkazish
// ============================================================================
//
// ILGARI: event WebSocket'ga yozilishi bilanoq `status='synced'` qilinardi
// (at-most-once). Ulanish uzilib, xabar TCP buferida qolib ketsa event
// abadiy yo'qolardi — qayta yuborilmasdi.
//
// ENDI: yuborilgan event `sending` holatida turadi va faqat peer'dan
// `sync:ack` kelganda `synced` bo'ladi. Ulanish uzilsa `sending` yozuvlar
// `pending`ga qaytariladi va qaytadan yuboriladi (at-least-once). Takror
// yuborish xavfsiz — qabul qiluvchi `sync_applied` orqali idempotent.

import (
	"context"
	"log"
	stdsync "sync"
	"time"

	"github.com/gorilla/websocket"

	"konak-local/internal/db"
)

// peerLink — bitta peer ulanishi (dialer yoki acceptor tomonida).
type peerLink interface {
	send(msg []byte) error
}

// wsLink — WebSocket ulanishi. Yozishlar mutex bilan seriyalanadi: outbox
// pompasi va `sync:ack` javoblari turli goroutine'lardan yozadi, gorilla
// esa bir vaqtda ko'p yozuvchiga ruxsat bermaydi.
type wsLink struct {
	conn *websocket.Conn
	mu   stdsync.Mutex
}

func (l *wsLink) send(msg []byte) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return l.conn.WriteMessage(websocket.TextMessage, msg)
}

const (
	outboxBatch     = 200 // bir aylanishda yuboriladigan event
	outboxMaxFlight = 2000
)

// resetInFlight — ulanish boshida/uzilganda tasdiqlanmagan eventlarni
// qaytadan navbatga qo'yadi.
func resetInFlight() {
	db.Pool.Exec(context.Background(),
		`UPDATE sync_queue SET status='pending' WHERE status='sending'`)
}

// ackEvent — peer eventni qabul qilib qo'lladi.
func ackEvent(eventID string) {
	if eventID == "" {
		return
	}
	db.Pool.Exec(context.Background(),
		`UPDATE sync_queue SET status='synced', synced_at=NOW() WHERE event_id=$1`, eventID)
}

// pumpOutbox — outbox'ni peer'ga uzatuvchi sikl. `stop` yopilganda tugaydi.
// keepalive=true bo'lsa ~10 soniyada bir marta ping yuboradi.
func pumpOutbox(link peerLink, stop <-chan struct{}, keepalive bool) {
	resetInFlight()
	ticks := 0
	for {
		select {
		case <-stop:
			resetInFlight()
			return
		default:
		}

		ticks++
		if keepalive && ticks%10 == 0 {
			if err := link.send([]byte(`{"event":"ping"}`)); err != nil {
				resetInFlight()
				return
			}
		}

		sent, err := flushOutbox(link)
		if err != nil {
			resetInFlight()
			return
		}
		if sent >= outboxBatch {
			// Orqada to'planib qolgan bo'lsa kutmaymiz (snapshot/resync).
			continue
		}

		select {
		case <-stop:
			resetInFlight()
			return
		case <-time.After(1 * time.Second):
		}
	}
}

// flushOutbox — navbatdagi eventlarni yuboradi. Xato qaytarsa ulanish uzilgan.
func flushOutbox(link peerLink) (int, error) {
	ctx := context.Background()

	var inFlight int
	db.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM sync_queue WHERE status='sending'`).Scan(&inFlight)
	if inFlight >= outboxMaxFlight {
		// Peer ack bermayapti — bosim o'tkazmaymiz.
		return 0, nil
	}

	rows, err := db.Pool.Query(ctx, `
		SELECT id, COALESCE(event_id,''), event_type, payload::text
		  FROM sync_queue WHERE status='pending' ORDER BY id LIMIT $1`, outboxBatch)
	if err != nil {
		return 0, nil
	}
	type item struct {
		id             int
		eid, etype, pl string
	}
	var pending []item
	for rows.Next() {
		var it item
		if rows.Scan(&it.id, &it.eid, &it.etype, &it.pl) == nil {
			pending = append(pending, it)
		}
	}
	rows.Close()

	sent := 0
	for _, it := range pending {
		if err := link.send(buildSyncEventMsg(it.eid, it.etype, it.pl)); err != nil {
			db.Pool.Exec(ctx,
				`UPDATE sync_queue SET retry_count=retry_count+1 WHERE id=$1`, it.id)
			return sent, err
		}
		// Ack kutiladi; kelmasa uzilishda `pending`ga qaytadi.
		db.Pool.Exec(ctx, `UPDATE sync_queue SET status='sending' WHERE id=$1`, it.id)
		sent++
	}
	if sent > 0 {
		log.Printf("SYNC: %d event yuborildi (ack kutilmoqda)", sent)
	}
	return sent, nil
}
