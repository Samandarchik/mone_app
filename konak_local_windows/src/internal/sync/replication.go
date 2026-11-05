package sync

// ============================================================================
// Qator replikatsiyasini QO'LLASH (apply) + to'liq snapshot (resync)
// ============================================================================
//
// Emit tomoni Postgres triggerida (internal/db/replication.go). Bu yerda
// kelgan `row:upsert` / `row:delete` / `table:prune` eventlari bazaga
// yoziladi.
//
// Har bir yozuv `SET LOCAL konak.sync_apply='on'` tranzaksiyasida bajariladi —
// shu sababli trigger qayta emit qilmaydi va event asl node'ga qaytmaydi.

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"strings"
	stdsync "sync"
	"time"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/db"
	"konak-local/internal/printer"
	"konak-local/internal/wss"
)

// rowEvent — `row:upsert` / `row:delete` payloadi.
type rowEvent struct {
	Table string                     `json:"table"`
	Row   map[string]json.RawMessage `json:"row"`
	// Force — snapshot (resync) eventi: `updated_at` bo'yicha "eskisi ustiga
	// yozmaslik" himoyasini chetlab o'tadi, chunki snapshot manba node'ning
	// haqiqiy holati va u hukmron.
	Force bool `json:"force"`
}

// pruneEvent — `table:prune`: manba node'da MAVJUD BO'LMAGAN qatorlarni
// replikadan o'chiradi. To'liq bir xillik uchun shart: aks holda replikada
// allaqachon o'chirilgan eski qatorlar abadiy qolib ketadi.
type pruneEvent struct {
	Table string   `json:"table"`
	Keys  []string `json:"keys"`
}

// insertDefaults — payloadda kelmaydigan, lekin INSERT uchun majburiy
// (NOT NULL) ustunlar. Faqat YANGI qator yaratilganda ishlatiladi.
func insertDefaults(table string) map[string]string {
	if table == "users" {
		// pin/pin_hash node'ga xos (PIN_PEPPER har xil) — kanalga chiqmaydi.
		// Yangi xodim hech qanday PINga mos kelmaydigan qiymat bilan
		// yaratiladi; haqiqiy PIN alohida `user:*` eventida (pin_enc,
		// SYNC_TOKEN bilan shifrlangan) keladi.
		return map[string]string{
			"pin":      "nosync-" + db.NewUUID(),
			"pin_hash": "",
		}
	}
	return nil
}

// withApply — kelgan eventni qo'llash tranzaksiyasi (trigger jim turadi).
func withApply(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, "SET LOCAL konak.sync_apply = 'on'"); err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// jsonToParam — JSON qiymatini SQL parametriga aylantiradi.
// Hamma qiymat MATN sifatida beriladi, SQL'da esa ustunning aniq turiga
// CAST qilinadi (`$1::jsonb`, `$1::timestamptz`, ...). Shu sababli son,
// vaqt, jsonb — hammasi bir xil yo'l bilan, turini yo'qotmasdan o'tadi.
func jsonToParam(raw json.RawMessage) interface{} {
	s := strings.TrimSpace(string(raw))
	if s == "" || s == "null" {
		return nil
	}
	if s[0] == '"' {
		var v string
		if err := json.Unmarshal(raw, &v); err == nil {
			return v
		}
	}
	return s
}

// applyRowUpsert — bitta qatorni to'liq (hamma ustuni bilan) yozadi.
func applyRowUpsert(origin string, data json.RawMessage) error {
	var e rowEvent
	if err := json.Unmarshal(data, &e); err != nil {
		return fmt.Errorf("row:upsert payload: %w", err)
	}
	meta, ok := db.ReplTableByName(e.Table)
	if !ok {
		// Oq ro'yxatda yo'q jadval — peer ixtiyoriy jadvalga yoza olmaydi.
		return fmt.Errorf("row:upsert — '%s' jadvali replikatsiya ro'yxatida yo'q", e.Table)
	}
	if len(e.Row) == 0 {
		return fmt.Errorf("row:upsert — '%s' uchun qator bo'sh", e.Table)
	}

	skip := map[string]bool{}
	for _, c := range meta.Skip {
		skip[c] = true
	}

	var cols []string
	var placeholders []string
	var args []interface{}
	for col, raw := range e.Row {
		if skip[col] {
			continue
		}
		typ, known := db.ColumnType(e.Table, col)
		if !known {
			// Peer yangiroq versiyada — bizda yo'q ustunni jimgina tashlaymiz.
			continue
		}
		args = append(args, jsonToParam(raw))
		cols = append(cols, db.QuoteIdent(col))
		placeholders = append(placeholders, fmt.Sprintf("$%d::%s", len(args), typ))
	}
	if len(cols) == 0 {
		return fmt.Errorf("row:upsert — '%s' uchun mos ustun topilmadi", e.Table)
	}

	// INSERT uchun majburiy, lekin kanaldan kelmaydigan ustunlar.
	present := map[string]bool{}
	for col := range e.Row {
		present[col] = true
	}
	for col, val := range insertDefaults(e.Table) {
		if present[col] {
			continue
		}
		if typ, known := db.ColumnType(e.Table, col); known {
			args = append(args, val)
			cols = append(cols, db.QuoteIdent(col))
			placeholders = append(placeholders, fmt.Sprintf("$%d::%s", len(args), typ))
		}
	}

	pkSet := map[string]bool{}
	quotedPK := make([]string, 0, len(meta.PK))
	for _, c := range meta.PK {
		pkSet[c] = true
		quotedPK = append(quotedPK, db.QuoteIdent(c))
	}

	var sets []string
	for col := range e.Row {
		if skip[col] || pkSet[col] {
			continue
		}
		if _, known := db.ColumnType(e.Table, col); !known {
			continue
		}
		q := db.QuoteIdent(col)
		sets = append(sets, q+"=EXCLUDED."+q)
	}

	tbl := db.QuoteIdent(e.Table)
	var q strings.Builder
	fmt.Fprintf(&q, "INSERT INTO %s (%s) VALUES (%s)",
		tbl, strings.Join(cols, ","), strings.Join(placeholders, ","))
	if len(sets) == 0 {
		fmt.Fprintf(&q, " ON CONFLICT (%s) DO NOTHING", strings.Join(quotedPK, ","))
	} else {
		fmt.Fprintf(&q, " ON CONFLICT (%s) DO UPDATE SET %s",
			strings.Join(quotedPK, ","), strings.Join(sets, ","))
		// Kechikib kelgan eski event yangi holat ustiga yozmasin.
		// Snapshot (force) bundan mustasno — u manba node'ning hukmron holati.
		//
		// TENGLIK HOLATI: ikkala node bitta qatorni deyarli bir vaqtda
		// yozsa (masalan ikkalasida ham kirish qayd etilsa), `updated_at`
		// bir xil bo'lib qoladi va "kim oxirgi qo'lladi" tasodifiy hal
		// bo'lardi — natijada qator ikki bazada ABADIY farq qilib qolardi.
		// Shuning uchun tenglikda hakam bitta: `local` node hukmron.
		// Shunda ikkala tomon ham bir xil natijaga keladi.
		if _, hasUpdated := db.ColumnType(e.Table, "updated_at"); hasUpdated && !e.Force && present["updated_at"] {
			cmp := ">"
			if origin == "local" {
				cmp = ">="
			}
			fmt.Fprintf(&q, " WHERE COALESCE(EXCLUDED.updated_at, '-infinity'::timestamptz)"+
				" %s COALESCE(%s.updated_at, '-infinity'::timestamptz)", cmp, tbl)
		}
	}
	q.WriteString(" RETURNING (xmax = 0)")

	ctx := context.Background()
	inserted := false
	err := withApply(ctx, func(tx pgx.Tx) error {
		if err := clearNaturalKeyConflict(ctx, tx, meta, e.Row); err != nil {
			return err
		}
		row := tx.QueryRow(ctx, q.String(), args...)
		if err := row.Scan(&inserted); err != nil {
			if err == pgx.ErrNoRows {
				// Konflikt bo'ldi-yu, LWW himoyasi yoki DO NOTHING to'sdi —
				// bu xato emas, holat allaqachon to'g'ri.
				inserted = false
				return nil
			}
			return err
		}
		if len(meta.PK) == 1 {
			// Aniq id bilan yozildi — ketma-ketlik orqada qolmasin.
			bumpSequence(ctx, tx, meta.Name, meta.PK[0])
		}
		if e.Table == "users" {
			// PIN shu node'ning PIN_PEPPER'i bilan qaytadan hisoblanadi.
			return derivePINFromRow(ctx, tx, e.Row)
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("%s upsert: %w", e.Table, err)
	}

	afterRowApplied(origin, e, inserted)
	return nil
}

// clearNaturalKeyConflict — kelayotgan qatorning tabiiy unikal kaliti
// (masalan `orders.order_number`) replikada BOSHQA id ostida yotgan bo'lsa,
// eski nusxani olib tashlaydi.
//
// Busiz upsert `orders_order_number_key` cheklovini buzardi va o'sha qator
// hech qachon tekislanmasdi — eski, buzuq sync davridan qolgan yozuvlar
// aynan shu holatda.
func clearNaturalKeyConflict(ctx context.Context, tx pgx.Tx, meta db.ReplTable, row map[string]json.RawMessage) error {
	if len(meta.Natural) == 0 || len(meta.PK) != 1 {
		return nil
	}
	pkRaw, ok := row[meta.PK[0]]
	if !ok {
		return nil
	}
	pkType, ok := db.ColumnType(meta.Name, meta.PK[0])
	if !ok {
		return nil
	}

	for _, col := range meta.Natural {
		raw, ok := row[col]
		if !ok {
			continue
		}
		colType, known := db.ColumnType(meta.Name, col)
		if !known {
			continue
		}
		val := jsonToParam(raw)
		if val == nil {
			continue
		}
		sql := fmt.Sprintf("DELETE FROM %s WHERE %s = $1::%s AND %s <> $2::%s",
			db.QuoteIdent(meta.Name), db.QuoteIdent(col), colType,
			db.QuoteIdent(meta.PK[0]), pkType)
		tag, err := tx.Exec(ctx, sql, val, jsonToParam(pkRaw))
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			log.Printf("SYNC: %s.%s=%v boshqa id ostida edi — eski nusxa olib tashlandi",
				meta.Name, col, val)
		}
	}
	return nil
}

// bumpSequence — aniq id bilan yozgandan keyin SERIAL ketma-ketligini
// oldinga suradi, LEKIN faqat SHU node'ning id fazasi ichida.
//
// MUHIM: oddiy `MAX(id)` ishlatib bo'lmaydi. Cloud'dan kelgan qator id'si
// 1_000_000_000 dan katta — local'da MAX bo'yicha setval qilinsa, local
// keyingi buyurtmaga cloud fazasidagi id berardi va ikki node bir id'ni
// ikki xil yozuvga bergan bo'lardi. Shuning uchun local faqat o'z
// oralig'idagi (offset'dan kichik) eng katta id'ga qaraydi.
func bumpSequence(ctx context.Context, tx pgx.Tx, table, pk string) {
	var seq *string
	if err := tx.QueryRow(ctx, `SELECT pg_get_serial_sequence($1,$2)`, table, pk).Scan(&seq); err != nil || seq == nil {
		return
	}
	qPK, qTbl := db.QuoteIdent(pk), db.QuoteIdent(table)

	if nodeID == "local" {
		tx.Exec(ctx, fmt.Sprintf(
			`SELECT setval($1, GREATEST(COALESCE((SELECT MAX(%s) FROM %s WHERE %s < %d),0), 1))`,
			qPK, qTbl, qPK, db.NonLocalIDOffset), *seq)
		return
	}
	tx.Exec(ctx, fmt.Sprintf(
		`SELECT setval($1, GREATEST(COALESCE((SELECT MAX(%s) FROM %s WHERE %s >= %d),0), %d))`,
		qPK, qTbl, qPK, db.NonLocalIDOffset, db.NonLocalIDOffset), *seq)
}

// afterRowApplied — qator yozilgandan keyingi jonli ta'sirlar: UI'ni
// yangilash va oshxona chekini chop etish.
//
// Chek MUHIM: sayt/QR buyurtmasi boshqa node'da tug'iladi, restorandagi
// printerga esa faqat shu yerda chiqadi. Ilgari bu `order:created` eventida
// edi; endi buyurtma qatori replikatsiya orqali kelgani uchun shu yerda.
func afterRowApplied(origin string, e rowEvent, inserted bool) {
	// To'liq snapshot (resync) — minglab qator ketma-ket keladi. Har biriga
	// alohida xabar yuborilsa ilova menyuni MINGLAB marta qayta yuklaydi va
	// WSS kanali tiqilib qoladi. Shuning uchun snapshot paytida faqat bitta
	// umumlashtirilgan "yangilan" xabari yuboriladi.
	if e.Force {
		coalescedRefresh(e.Table)
		return
	}
	switch e.Table {
	case "orders":
		var o map[string]interface{}
		b, _ := json.Marshal(e.Row)
		json.Unmarshal(b, &o)
		wss.H.BroadcastEvent("order:updated", map[string]interface{}{"order": o})
		if inserted && origin != nodeID {
			printOrderFromRow(o)
		}
	case "products", "categories":
		wss.H.BroadcastEvent("menu:outdated", map[string]interface{}{"reason": "sync"})
	case "stocks":
		var s map[string]interface{}
		b, _ := json.Marshal(e.Row)
		json.Unmarshal(b, &s)
		wss.H.BroadcastEvent("stock:updated", s)
	case "zones", "tables":
		wss.H.BroadcastEvent("zones:updated", map[string]interface{}{"table": e.Table})
	}
}

// coalescedRefresh — snapshot davomida bir xil turdagi xabarlarni yig'ib,
// 2 soniyada BIR MARTA yuboradi.
var refreshPending struct {
	mu     stdsync.Mutex
	timers map[string]bool
}

func coalescedRefresh(table string) {
	var event string
	switch table {
	case "products", "categories":
		event = "menu:outdated"
	case "zones", "tables":
		event = "zones:updated"
	case "stocks":
		event = "stock:refresh"
	case "orders":
		event = "orders:refresh"
	default:
		return
	}

	refreshPending.mu.Lock()
	if refreshPending.timers == nil {
		refreshPending.timers = map[string]bool{}
	}
	if refreshPending.timers[event] {
		refreshPending.mu.Unlock()
		return
	}
	refreshPending.timers[event] = true
	refreshPending.mu.Unlock()

	time.AfterFunc(2*time.Second, func() {
		refreshPending.mu.Lock()
		delete(refreshPending.timers, event)
		refreshPending.mu.Unlock()
		wss.H.BroadcastEvent(event, map[string]interface{}{"reason": "resync"})
	})
}

func printOrderFromRow(o map[string]interface{}) {
	status, _ := o["status"].(string)
	if status == "completed" || status == "cancelled" {
		return
	}
	orderNumber, _ := o["order_number"].(string)
	if orderNumber == "" {
		return
	}
	var items []map[string]interface{}
	switch v := o["items"].(type) {
	case string:
		json.Unmarshal([]byte(v), &items)
	case []interface{}:
		for _, it := range v {
			if m, ok := it.(map[string]interface{}); ok {
				items = append(items, m)
			}
		}
	}
	if len(items) == 0 {
		return
	}
	orderType, _ := o["type"].(string)
	tableSKU, _ := o["table_sku"].(string)
	createdAt, _ := o["created_at"].(string)
	if createdAt == "" {
		createdAt = time.Now().UTC().Format(time.RFC3339)
	}
	waiter, _ := o["customer_name"].(string)
	if waiter == "" {
		waiter = "Online"
	}
	printer.PrintOrder(orderNumber, orderType, tableSKU, createdAt, waiter, items, false)
}

// applyRowDelete — qatorni birlamchi kalit bo'yicha o'chiradi.
func applyRowDelete(data json.RawMessage) error {
	var e rowEvent
	if err := json.Unmarshal(data, &e); err != nil {
		return fmt.Errorf("row:delete payload: %w", err)
	}
	meta, ok := db.ReplTableByName(e.Table)
	if !ok {
		return fmt.Errorf("row:delete — '%s' jadvali ro'yxatda yo'q", e.Table)
	}

	var where []string
	var args []interface{}
	for _, pk := range meta.PK {
		raw, ok := e.Row[pk]
		if !ok {
			return fmt.Errorf("row:delete — '%s' uchun %s yo'q", e.Table, pk)
		}
		typ, known := db.ColumnType(e.Table, pk)
		if !known {
			return fmt.Errorf("row:delete — '%s'.%s ustuni yo'q", e.Table, pk)
		}
		args = append(args, jsonToParam(raw))
		where = append(where, fmt.Sprintf("%s=$%d::%s", db.QuoteIdent(pk), len(args), typ))
	}

	ctx := context.Background()
	sql := fmt.Sprintf("DELETE FROM %s WHERE %s", db.QuoteIdent(e.Table), strings.Join(where, " AND "))
	if err := withApply(ctx, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, sql, args...)
		return err
	}); err != nil {
		return fmt.Errorf("%s delete: %w", e.Table, err)
	}
	return nil
}

// applyTablePrune — manbada yo'q qatorlarni o'chiradi (to'liq bir xillik).
//
// Faqat MANBA node'ning id fazosidagi qatorlar o'chiriladi: "local" node
// 1..999_999_999 oralig'iga, boshqa node'lar undan yuqorisiga javobgar.
// Shu sababli local snapshot cloud'da tug'ilgan (hali local'ga yetib
// bormagan) online buyurtmani o'chirib yubormaydi.
func applyTablePrune(origin string, data json.RawMessage) error {
	var e pruneEvent
	if err := json.Unmarshal(data, &e); err != nil {
		return fmt.Errorf("table:prune payload: %w", err)
	}
	meta, ok := db.ReplTableByName(e.Table)
	if !ok {
		return fmt.Errorf("table:prune — '%s' jadvali ro'yxatda yo'q", e.Table)
	}
	if len(meta.PK) != 1 {
		return nil // murakkab kalit — prune qilinmaydi
	}
	pk := meta.PK[0]
	typ, known := db.ColumnType(e.Table, pk)
	if !known || !strings.Contains(typ, "int") {
		return nil // faqat butun sonli kalitda id fazosi ma'noga ega
	}

	rangeCond := fmt.Sprintf("%s < %d", db.QuoteIdent(pk), db.NonLocalIDOffset)
	if origin != "local" {
		rangeCond = fmt.Sprintf("%s >= %d", db.QuoteIdent(pk), db.NonLocalIDOffset)
	}

	keys := make([]int64, 0, len(e.Keys))
	for _, k := range e.Keys {
		if n, err := strconv.ParseInt(k, 10, 64); err == nil {
			keys = append(keys, n)
		}
	}

	ctx := context.Background()
	sql := fmt.Sprintf("DELETE FROM %s WHERE %s AND NOT (%s = ANY($1::bigint[]))",
		db.QuoteIdent(e.Table), rangeCond, db.QuoteIdent(pk))
	var removed int64
	if err := withApply(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, sql, keys)
		if err != nil {
			return err
		}
		removed = tag.RowsAffected()
		return nil
	}); err != nil {
		return fmt.Errorf("%s prune: %w", e.Table, err)
	}
	if removed > 0 {
		log.Printf("SYNC: %s — %d ortiqcha qator o'chirildi (manba: %s)", e.Table, removed, origin)
	}
	return nil
}

// ============================================================================
// TO'LIQ SNAPSHOT (resync)
// ============================================================================

// EnqueueFullSnapshot — shu node'dagi HAMMA replikatsiya jadvalini outbox'ga
// soladi: har bir qator `row:upsert` (force) + jadval oxirida `table:prune`.
// Peer shundan keyin 100% shu node'ning nusxasiga aylanadi.
//
// Bir marta ishlatish uchun: eski (buzilgan) sync natijasida ajralib ketgan
// bazani tekislaydi.
// snapshotFilter — to'liq snapshotga TUSHMAYDIGAN eski qatorlarni chiqarib
// tashlaydi.
//
// NEGA: snapshot HAR BIR qatorni alohida event qilib `sync_queue`ga yozadi.
// `audit_logs` va `ing_batch_moves` — cheksiz o'suvchi jurnal jadvallari;
// bir yildan keyin ular yuz minglab qatorga yetadi va bitta "resync" tugmasi
// butun navbatni bo'g'ib, haqiqiy ma'lumot (chek, qoldiq) orqada qolardi.
// Ular baribir trigger orqali jonli replikatsiya bo'ladi — snapshotga
// faqat yaqin oraliq kifoya.
func snapshotFilter(table string) string {
	switch table {
	case "audit_logs", "ing_batch_moves", "ing_moves", "loyalty_transactions":
		return " WHERE x.created_at > NOW() - INTERVAL '30 days'"
	}
	return ""
}

func EnqueueFullSnapshot() (int64, error) {
	ctx := context.Background()
	var total int64

	// 1-bosqich: hamma qator — bog'liqlik tartibida (avval kategoriya,
	// keyin mahsulot), aks holda tashqi kalit (FK) buziladi.
	for _, t := range db.ReplTables {
		var rowExpr strings.Builder
		rowExpr.WriteString("to_jsonb(x)")
		for _, c := range t.Skip {
			fmt.Fprintf(&rowExpr, " - '%s'", c)
		}

		tag, err := db.Pool.Exec(ctx, fmt.Sprintf(`
			INSERT INTO sync_queue (event_id, origin, event_type, payload, status)
			SELECT $1 || '-' || nextval('sync_event_seq')::text, $1, 'row:upsert',
			       jsonb_build_object('table', $2::text, 'row', %s, 'force', true),
			       'pending'
			  FROM %s x%s`, rowExpr.String(), db.QuoteIdent(t.Name), snapshotFilter(t.Name)),
			nodeID, t.Name)
		if err != nil {
			return total, fmt.Errorf("%s snapshot: %w", t.Name, err)
		}
		total += tag.RowsAffected()
	}

	// 2-bosqich: ortiqcha qatorlarni o'chirish — TESKARI tartibda.
	//nolint:gocritic // tartib ataylab teskari
	// Zona stollaridan oldin o'chirilsa `tables_zone_id_fkey` buziladi;
	// teskari yurish bolani otasidan oldin tozalaydi.
	for i := len(db.ReplTables) - 1; i >= 0; i-- {
		t := db.ReplTables[i]
		if len(t.PK) != 1 {
			continue
		}
		if _, err := db.Pool.Exec(ctx, fmt.Sprintf(`
			INSERT INTO sync_queue (event_id, origin, event_type, payload, status)
			SELECT $1 || '-' || nextval('sync_event_seq')::text, $1, 'table:prune',
			       jsonb_build_object('table', $2::text,
			                          'keys', COALESCE(jsonb_agg(x.%s::text), '[]'::jsonb)),
			       'pending'
			  FROM %s x`, db.QuoteIdent(t.PK[0]), db.QuoteIdent(t.Name)), nodeID, t.Name); err != nil {
			return total, fmt.Errorf("%s prune: %w", t.Name, err)
		}
		total++
	}

	log.Printf("SYNC: to'liq snapshot navbatga qo'yildi — %d event", total)
	return total, nil
}

// ============================================================================
// QO'LLANMAGAN EVENTLARNI QAYTA URINISH
// ============================================================================

// recordFailure — xato bergan eventni saqlaydi. `sync_applied`ga YOZILMAYDI,
// ya'ni event "qo'llandi" deb hisoblanmaydi.
func recordFailure(eventID, origin, eventType string, data json.RawMessage, cause error) {
	if eventID == "" {
		log.Printf("SYNC: %s qo'llanmadi (event_id yo'q): %v", eventType, cause)
		return
	}
	db.Pool.Exec(context.Background(), `
		INSERT INTO sync_failed (event_id, origin, event_type, payload, last_error, next_try_at)
		VALUES ($1,$2,$3,$4::jsonb,$5, NOW() + INTERVAL '20 seconds')
		ON CONFLICT (event_id) DO UPDATE SET
			last_error = EXCLUDED.last_error,
			retry_count = sync_failed.retry_count + 1,
			next_try_at = NOW() + LEAST(sync_failed.retry_count + 1, 30) * INTERVAL '20 seconds'`,
		eventID, origin, eventType, string(data), cause.Error())
	log.Printf("SYNC: %s qo'llanmadi, qayta urinishga qo'yildi: %v", eventType, cause)
}

// StartFailedRetry — qo'llanmagan eventlarni davriy qayta uriniladi.
// Masalan mahsulot o'z kategoriyasidan oldin kelib qolsa (FK xatosi) —
// keyingi urinishda o'tadi. Ilgari bunday event jimgina yo'qolardi.
func StartFailedRetry() {
	go func() {
		for {
			time.Sleep(20 * time.Second)
			retryFailedOnce()
		}
	}()
}

func retryFailedOnce() {
	ctx := context.Background()
	rows, err := db.Pool.Query(ctx, `
		SELECT event_id, origin, event_type, payload::text
		  FROM sync_failed WHERE next_try_at <= NOW()
		 ORDER BY created_at LIMIT 100`)
	if err != nil {
		return
	}
	type item struct{ id, origin, etype, payload string }
	var items []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.id, &it.origin, &it.etype, &it.payload); err == nil {
			items = append(items, it)
		}
	}
	rows.Close()

	for _, it := range items {
		if err := dispatchEvent(it.origin, it.etype, json.RawMessage(it.payload)); err != nil {
			db.Pool.Exec(ctx, `
				UPDATE sync_failed
				   SET last_error=$2, retry_count=retry_count+1,
				       next_try_at = NOW() + LEAST(retry_count + 1, 30) * INTERVAL '20 seconds'
				 WHERE event_id=$1`, it.id, err.Error())
			continue
		}
		db.Pool.Exec(ctx, `INSERT INTO sync_applied (event_id, origin, event_type)
			VALUES ($1,$2,$3) ON CONFLICT (event_id) DO NOTHING`, it.id, it.origin, it.etype)
		db.Pool.Exec(ctx, `DELETE FROM sync_failed WHERE event_id=$1`, it.id)
		log.Printf("SYNC: kechikkan event qo'llandi — %s (%s)", it.etype, it.id)
	}
}

// StartQueueJanitor — yuborilgan eventlarni tozalab turadi (outbox cheksiz
// o'smasin). Trigger har o'zgarishga qator yozgani uchun bu shart.
func StartQueueJanitor() {
	go func() {
		for {
			time.Sleep(1 * time.Hour)
			db.Pool.Exec(context.Background(),
				`DELETE FROM sync_queue WHERE status='synced' AND synced_at < NOW() - INTERVAL '3 days'`)
			db.Pool.Exec(context.Background(),
				`DELETE FROM sync_applied WHERE applied_at < NOW() - INTERVAL '30 days'`)
		}
	}()
}
