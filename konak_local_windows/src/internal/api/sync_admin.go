package api

// Sync holatini ko'rish va ikkala bazani to'liq tekislash (resync).

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"konak-local/internal/db"
	"konak-local/internal/sync"
)

// handleSyncStatus — GET /api/sync/status
// Peer bilan aloqa, navbatdagi/tasdiq kutayotgan/qo'llanmagan eventlar soni.
func handleSyncStatus(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var pending, sending, failed, applied int
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM sync_queue WHERE status='pending'").Scan(&pending)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM sync_queue WHERE status='sending'").Scan(&sending)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM sync_failed").Scan(&failed)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM sync_applied").Scan(&applied)

	type failedRow struct {
		EventID   string `json:"event_id"`
		EventType string `json:"event_type"`
		LastError string `json:"last_error"`
		Retries   int    `json:"retry_count"`
	}
	recent := []failedRow{}
	rows, err := db.Pool.Query(ctx,
		`SELECT event_id, event_type, last_error, retry_count
		   FROM sync_failed ORDER BY created_at DESC LIMIT 20`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var fr failedRow
			if rows.Scan(&fr.EventID, &fr.EventType, &fr.LastError, &fr.Retries) == nil {
				recent = append(recent, fr)
			}
		}
	}

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"node_id":   sync.NodeID(),
		"mode":      sync.SyncMode(),
		"connected": sync.IsConnected(),
		"queue": map[string]int{
			"pending": pending, // yuborilishi kutilmoqda
			"sending": sending, // yuborilgan, tasdiq (ack) kutilmoqda
			"failed":  failed,  // qo'llanmadi — qayta uriniladi
			"applied": applied,
		},
		"failed_events": recent,
	})
}

// handleSyncChecksum — GET /api/sync/checksum
// Har bir replikatsiya jadvali uchun qator soni va MAZMUN XESHI. Ikkala
// node'dan olingan javob bir xil bo'lsa — bazalar oxirgi maydonigacha
// aynan bir xil. Node'ga xos ustunlar (users.pin/pin_hash — har node'ning
// o'z PIN_PEPPER'i bilan hisoblangan) hisobga olinmaydi.
func handleSyncChecksum(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	tables := map[string]map[string]interface{}{}
	overall := make([]string, 0, len(db.ReplTables))

	for _, t := range db.ReplTables {
		expr := "to_jsonb(x)"
		for _, c := range t.Skip {
			expr += " - '" + c + "'"
		}
		// COLLATE "C" — MAJBURIY. Windows va Linux serverlarining matn
		// tartiblash qoidalari (collation) har xil: bir xil ma'lumot turli
		// tartibda yig'ilib, xesh boshqacha chiqardi va bazalar "farq
		// qilyapti"dek ko'rinardi. "C" — sof bayt tartibi, har joyda bir xil.
		q := fmt.Sprintf(
			`SELECT COUNT(*), COALESCE(md5(string_agg((%s)::text, ',' ORDER BY (%s)::text COLLATE "C")),'-') FROM %s x`,
			expr, expr, db.QuoteIdent(t.Name))

		var count int
		var sum string
		if err := db.Pool.QueryRow(ctx, q).Scan(&count, &sum); err != nil {
			tables[t.Name] = map[string]interface{}{"error": err.Error()}
			continue
		}
		tables[t.Name] = map[string]interface{}{"count": count, "md5": sum}
		overall = append(overall, t.Name+":"+strconv.Itoa(count)+":"+sum)
	}

	sort.Strings(overall)
	total := md5.Sum([]byte(strings.Join(overall, "|")))

	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"node_id": sync.NodeID(),
		"overall": hex.EncodeToString(total[:]),
		"tables":  tables,
	})
}

// handleSyncResync — POST /api/sync/resync
// Shu node'dagi HAMMA ma'lumotni (va uploads rasmlarini) peer'ga to'liq
// qaytadan yuboradi: har bir qator + jadval oxirida "ortiqchasini o'chir"
// buyrug'i. Natijada peer 100% shu node'ning nusxasiga aylanadi.
//
// Bu — MANBA node'da ishga tushiriladi (odatda local/master).
func handleSyncResync(w http.ResponseWriter, r *http.Request) {
	events, err := sync.EnqueueFullSnapshot()
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "resync_failed", err.Error())
		return
	}
	files := sync.ResyncFiles()
	jsonResponse(w, http.StatusOK, map[string]interface{}{
		"ok":           true,
		"node_id":      sync.NodeID(),
		"queued_rows":  events,
		"queued_files": files,
		"message":      "To'liq snapshot navbatga qo'yildi — peer shu node holatiga tekislanadi",
	})
}
