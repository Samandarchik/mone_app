package db

// ============================================================================
// TO'LIQ QATOR REPLIKATSIYASI (row-level replication)
// ============================================================================
//
// MUAMMO (2026-08-16 gacha): sync eventlari Go handlerlari ichida qo'lda
// (`addSyncQueue(...)`) yoziladi. Har bir handler o'zi qaysi maydonlarni
// solishni "eslab qolishi" kerak edi. Natijada:
//   - narx/product_type/printer_station kabi maydonlar umuman yuborilmasdi;
//   - `service_fee` buyurtma OCHILGANDA 0 bo'lgani uchun replikada 0 bo'lib
//     qolardi (keyingi o'zgarish event yaratmasdi);
//   - `created_at` replikada NOW() bilan yozilib, 1–2 soniya farq qilardi;
//   - eventni emit qilishni butunlay unutgan handlerlar (ingredient, retsept,
//     mijoz, promo, spisaniye...) jimgina ikki bazani ajratib yuborardi.
//
// YECHIM: emit qilishni Go handlerlaridan olib tashlab, Postgres TRIGGER'iga
// beramiz. Har qanday INSERT/UPDATE/DELETE — qaysi kod yo'li orqali bo'lishidan
// qat'i nazar — `sync_queue`ga TO'LIQ qatorni (`to_jsonb(NEW)`) yozadi.
// Shuning uchun hech bir maydon (narx, vaqt, id, izoh) tushib qolmaydi va
// kelajakda yangi handler qo'shilsa ham replikatsiya avtomatik ishlaydi.
//
// AYLANMA (ping-pong) OLDINI OLISH: kelgan eventni qo'llashda tranzaksiyada
// `SET LOCAL konak.sync_apply='on'` qo'yiladi — trigger buni ko'rib emit
// qilmaydi. Shuning uchun event faqat asl node'da bir marta tug'iladi.
//
// ID TO'QNASHUVI: ikkala node ham SERIAL id beradi. "local" bo'lmagan node
// ketma-ketliklari 1_000_000_000 dan boshlanadi — shunda cloud'da tug'ilgan
// qator local'dagi boshqa qator ustiga yozilmaydi.

import (
	"context"
	"fmt"
	"log"
	"strings"
)

// NonLocalIDOffset — "local" bo'lmagan node'lar id fazosi shu qiymatdan
// boshlanadi. Prune (ortiqcha qatorni o'chirish) ham shu chegaraga tayanadi.
const NonLocalIDOffset int64 = 1_000_000_000

// ReplTable — replikatsiya qilinadigan jadval.
type ReplTable struct {
	Name string
	PK   []string
	// Skip — sync'ga CHIQMAYDIGAN ustunlar. `users.pin`/`pin_hash` har bir
	// node'ning o'z PIN_PEPPER'i bilan hisoblangan — ularni ko'chirish
	// mumkin emas, PIN `pin_sync` ustunida shifrlangan holda ketadi.
	Skip []string
	// Natural — birlamchi kalitdan TASHQARI unikal ustunlar.
	//
	// NEGA KERAK: upsert `id` bo'yicha ketadi. Agar replikada o'sha yozuv
	// BOSHQA id bilan yotgan bo'lsa (eski, buzuq sync davridan qolgan),
	// insert `orders_order_number_key` kabi unikal cheklovni buzadi va
	// qator hech qachon tekislanmaydi. Shuning uchun upsertdan oldin
	// boshqa id ostidagi eski nusxa olib tashlanadi.
	Natural []string
}

// ReplTables — tartib MUHIM: snapshot shu ketma-ketlikda yuboriladi, ya'ni
// tashqi kalit (FK) bog'liqligi buzilmaydi (avval kategoriya, keyin mahsulot).
//
// Ataylab TASHQARIDA qoldirilgan jadvallar va sababi:
//
//	settings              — cloud_token/cloud_ws_url sir va node'ga xos
//	sync_queue/applied/failed/node — sync mexanizmining o'zi
//	order_daily_counters  — har node o'z raqamini sanaydi (nodeTag ajratadi)
//	table_locks, qr_sessions, online_verifications — vaqtinchalik sessiya holati
//	backups               — o'sha mashinaning diskidagi fayllarga ishora qiladi
var ReplTables = []ReplTable{
	{Name: "printer_stations", PK: []string{"id"}},
	{Name: "categories", PK: []string{"id"}},
	{Name: "products", PK: []string{"id"}},
	{Name: "zones", PK: []string{"id"}},
	{Name: "tables", PK: []string{"id"}, Natural: []string{"sku"}},
	{Name: "users", PK: []string{"id"}, Skip: []string{"pin", "pin_hash"}, Natural: []string{"phone"}},
	{Name: "expense_categories", PK: []string{"id"}},
	{Name: "shifts", PK: []string{"id"}},
	{Name: "expenses", PK: []string{"id"}},
	{Name: "customers", PK: []string{"id"}, Natural: []string{"phone"}},
	{Name: "promo_codes", PK: []string{"id"}, Natural: []string{"code"}},
	{Name: "orders", PK: []string{"id"}, Natural: []string{"order_number"}},
	{Name: "stocks", PK: []string{"product_id"}},
	{Name: "recipes", PK: []string{"product_id"}},
	{Name: "ingredients", PK: []string{"id"}},
	{Name: "ing_moves", PK: []string{"id"}},
	{Name: "suppliers", PK: []string{"id"}},
	{Name: "purchases", PK: []string{"id"}},
	{Name: "purchase_items", PK: []string{"id"}},
	{Name: "ingredient_batches", PK: []string{"id"}},
	{Name: "ing_batch_moves", PK: []string{"id"}},
	{Name: "cookings", PK: []string{"id"}},
	{Name: "write_offs", PK: []string{"id"}},
	{Name: "inventory_corrections", PK: []string{"id"}},
	{Name: "shift_stock_snapshots", PK: []string{"shift_id", "product_id"}},
	{Name: "loyalty_transactions", PK: []string{"id"}},
	{Name: "menu_version", PK: []string{"id"}},
	{Name: "audit_logs", PK: []string{"id"}},
}

// ReplTableByName — nomi bo'yicha tavsif (oq ro'yxat vazifasini ham bajaradi:
// peer faqat shu jadvallarga yoza oladi).
func ReplTableByName(name string) (ReplTable, bool) {
	for _, t := range ReplTables {
		if t.Name == name {
			return t, true
		}
	}
	return ReplTable{}, false
}

// columnTypes — jadval → ustun → aniq PG turi ("integer", "jsonb",
// "timestamp with time zone" ...). Kelgan qator qiymatlari MATN sifatida
// uzatilib, SQL'da shu turga aniq CAST qilinadi. Aks holda pgx matnni text
// OID bilan jo'natadi va "column is of type integer but expression is of type
// text" xatosi chiqadi.
var columnTypes = map[string]map[string]string{}

// ColumnType — ustunning PG turi; ustun bu node'da yo'q bo'lsa false.
// (Peer yangiroq versiyada bo'lib, biz bilmaydigan ustun yuborsa — o'tkazib
// yuboriladi, xato bermaydi.)
func ColumnType(table, column string) (string, bool) {
	cols, ok := columnTypes[table]
	if !ok {
		return "", false
	}
	t, ok := cols[column]
	return t, ok
}

// SetupReplication — migratsiyalardan keyin, sync ishga tushishidan oldin
// chaqiriladi. Trigger funksiyasini yaratadi, jadvallarga ulaydi, node
// identifikatorini yozadi va ketma-ketliklarni node fazosiga suradi.
func SetupReplication(nodeID string) error {
	ctx := context.Background()
	if nodeID == "" {
		nodeID = "local"
	}

	stmts := []string{
		// event_id endi "<node>-<n>" ko'rinishida (UUID emas) — global unikal,
		// tartiblangan va tashqi kutubxonasiz.
		//
		// MUHIM: eski o'rnatishlarda bu ustunlar `uuid` turida yaratilgan.
		// Cloud'da aynan shunday edi va oqibati og'ir edi: trigger
		// `sync_queue`ga matnli id yoza olmay XATO berardi — ya'ni o'sha
		// node'da har qanday yozuv (masalan saytdan tushgan buyurtma)
		// yiqilardi; `sync_applied` ham to'lmay, idempotentlik ishlamasdi.
		// Shuning uchun tur matnga o'tkaziladi (allaqachon matn bo'lsa —
		// hech narsa qilinmaydi).
		`DO $konak$
		 BEGIN
		 	IF EXISTS (SELECT 1 FROM information_schema.columns
		 	           WHERE table_schema='public' AND table_name='sync_queue'
		 	             AND column_name='event_id' AND data_type='uuid') THEN
		 		ALTER TABLE sync_queue ALTER COLUMN event_id TYPE TEXT USING event_id::text;
		 	END IF;
		 	IF EXISTS (SELECT 1 FROM information_schema.columns
		 	           WHERE table_schema='public' AND table_name='sync_applied'
		 	             AND column_name='event_id' AND data_type='uuid') THEN
		 		ALTER TABLE sync_applied ALTER COLUMN event_id TYPE TEXT USING event_id::text;
		 	END IF;
		 END
		 $konak$;`,
		`CREATE TABLE IF NOT EXISTS sync_node (
			id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
			node_id TEXT NOT NULL DEFAULT 'local'
		)`,
		`INSERT INTO sync_node (id, node_id) VALUES (1, 'local') ON CONFLICT (id) DO NOTHING`,
		// event_id manbasi: "<node>-<n>" — global unikal, tashqi kutubxonasiz.
		`CREATE SEQUENCE IF NOT EXISTS sync_event_seq`,
		// Qo'llanmagan (xato bergan) eventlar — jimgina yo'qolmasin, keyin
		// qayta urinib ko'riladi. Masalan mahsulot o'z kategoriyasidan oldin
		// kelib qolsa FK xatosi bo'ladi — bu vaqtinchalik.
		`CREATE TABLE IF NOT EXISTS sync_failed (
			event_id TEXT PRIMARY KEY,
			origin TEXT NOT NULL DEFAULT '',
			event_type TEXT NOT NULL DEFAULT '',
			payload JSONB NOT NULL DEFAULT '{}',
			last_error TEXT NOT NULL DEFAULT '',
			retry_count INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			next_try_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_sync_failed_next ON sync_failed(next_try_at)`,
		`CREATE INDEX IF NOT EXISTS idx_sync_queue_pending ON sync_queue(status, id)`,
	}
	for _, s := range stmts {
		if _, err := Pool.Exec(ctx, s); err != nil {
			return fmt.Errorf("replikatsiya sxemasi: %w", err)
		}
	}

	if _, err := Pool.Exec(ctx, `UPDATE sync_node SET node_id = $1 WHERE id = 1`, nodeID); err != nil {
		return fmt.Errorf("sync_node yozilmadi: %w", err)
	}

	// ---- Trigger funksiyasi ----
	// AFTER trigger: qator allaqachon yozilgan, to'liq holat qo'lda.
	// `konak.sync_apply='on'` — kelgan eventni qo'llash tranzaksiyasi; bunda
	// emit qilinmaydi (aks holda event asl node'ga qaytib, cheksiz aylanardi).
	triggerFn := `
CREATE OR REPLACE FUNCTION konak_sync_emit() RETURNS trigger
LANGUAGE plpgsql AS $konak$
DECLARE
	v_node TEXT;
	v_row  JSONB;
	v_type TEXT;
BEGIN
	IF coalesce(current_setting('konak.sync_apply', true), '') = 'on' THEN
		RETURN NULL;
	END IF;

	SELECT node_id INTO v_node FROM sync_node WHERE id = 1;
	IF v_node IS NULL THEN
		v_node := 'local';
	END IF;

	IF TG_OP = 'DELETE' THEN
		v_row  := to_jsonb(OLD);
		v_type := 'row:delete';
	ELSE
		v_row  := to_jsonb(NEW);
		v_type := 'row:upsert';
	END IF;

	-- Sir ustunlar hech qachon kanalga chiqmaydi.
	IF TG_TABLE_NAME = 'users' THEN
		v_row := v_row - 'pin' - 'pin_hash';
	END IF;

	INSERT INTO sync_queue (event_id, origin, event_type, payload, status)
	VALUES (v_node || '-' || nextval('sync_event_seq')::text,
	        v_node, v_type,
	        jsonb_build_object('table', TG_TABLE_NAME, 'row', v_row),
	        'pending');
	RETURN NULL;
END;
$konak$;`
	if _, err := Pool.Exec(ctx, triggerFn); err != nil {
		return fmt.Errorf("konak_sync_emit yaratilmadi: %w", err)
	}

	// ---- Triggerlarni jadvallarga ulash ----
	for _, t := range ReplTables {
		var exists bool
		if err := Pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM information_schema.tables
			   WHERE table_schema='public' AND table_name=$1)`, t.Name).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			log.Printf("SYNC: '%s' jadvali yo'q — replikatsiyasiz o'tkazildi", t.Name)
			continue
		}
		if _, err := Pool.Exec(ctx,
			fmt.Sprintf(`DROP TRIGGER IF EXISTS trg_konak_sync ON %s`, t.Name)); err != nil {
			return err
		}
		if _, err := Pool.Exec(ctx, fmt.Sprintf(
			`CREATE TRIGGER trg_konak_sync AFTER INSERT OR UPDATE OR DELETE ON %s
			 FOR EACH ROW EXECUTE FUNCTION konak_sync_emit()`, t.Name)); err != nil {
			return fmt.Errorf("%s triggeri: %w", t.Name, err)
		}
	}

	if err := loadColumnTypes(ctx); err != nil {
		return err
	}
	if err := shiftSequences(ctx, nodeID); err != nil {
		return err
	}
	if err := verifyEmit(ctx); err != nil {
		return err
	}

	log.Printf("SYNC: qator replikatsiyasi tayyor (node=%s, %d jadval)", nodeID, len(ReplTables))
	return nil
}

// verifyEmit — trigger HAQIQATAN ishlayotganini ishga tushishda tekshiradi.
//
// NEGA KERAK: 2026-08-16 da cloud'da `sync_queue.event_id` ustuni `uuid`
// turida ekani aniqlandi. Trigger unga matnli id yoza olmasdi — natijada
// o'sha node'dagi har qanday yozuv xato berardi va hech narsa sync
// bo'lmasdi, LEKIN server bemalol ishga tushib, "hammasi joyida"dek
// ko'rinardi. Bunday jimgina buzilish qaytarilmasin: yozuv qilib ko'ramiz
// va event tug'ilganini tasdiqlaymiz. Tekshiruv tranzaksiyasi ORQAGA
// QAYTARILADI — bazada iz qolmaydi.
func verifyEmit(ctx context.Context) error {
	tx, err := Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var before, after int
	if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM sync_queue`).Scan(&before); err != nil {
		return fmt.Errorf("replikatsiya o'z-o'zini tekshiruvi: %w", err)
	}
	if _, err := tx.Exec(ctx,
		`UPDATE menu_version SET updated_at = updated_at WHERE id = 1`); err != nil {
		return fmt.Errorf("replikatsiya o'z-o'zini tekshiruvi (yozuv): %w", err)
	}
	if err := tx.QueryRow(ctx, `SELECT COUNT(*) FROM sync_queue`).Scan(&after); err != nil {
		return fmt.Errorf("replikatsiya o'z-o'zini tekshiruvi: %w", err)
	}
	if after <= before {
		return fmt.Errorf("replikatsiya triggeri event yaratmadi — sync ishlamaydi")
	}
	log.Println("SYNC: trigger tekshirildi — o'zgarish event tug'diryapti")
	return nil
}

// loadColumnTypes — har bir jadvalning ustun turlarini o'qib oladi.
func loadColumnTypes(ctx context.Context) error {
	for _, t := range ReplTables {
		rows, err := Pool.Query(ctx, `
			SELECT a.attname, format_type(a.atttypid, a.atttypmod)
			  FROM pg_attribute a
			  JOIN pg_class c ON c.oid = a.attrelid
			  JOIN pg_namespace n ON n.oid = c.relnamespace
			 WHERE n.nspname = 'public' AND c.relname = $1
			   AND a.attnum > 0 AND NOT a.attisdropped`, t.Name)
		if err != nil {
			return err
		}
		cols := map[string]string{}
		for rows.Next() {
			var name, typ string
			if err := rows.Scan(&name, &typ); err == nil {
				cols[name] = typ
			}
		}
		rows.Close()
		if len(cols) > 0 {
			columnTypes[t.Name] = cols
		}
	}
	return nil
}

// shiftSequences — "local" bo'lmagan node'da SERIAL ketma-ketliklarini
// NonLocalIDOffset dan boshlaydi. Shunda cloud'da tug'ilgan qator id'si
// local'dagi boshqa qator id'si bilan hech qachon to'qnashmaydi.
func shiftSequences(ctx context.Context, nodeID string) error {
	if nodeID == "local" {
		return nil
	}
	shifted := 0
	for _, t := range ReplTables {
		if len(t.PK) != 1 {
			continue
		}
		var seq *string
		if err := Pool.QueryRow(ctx,
			`SELECT pg_get_serial_sequence($1, $2)`, t.Name, t.PK[0]).Scan(&seq); err != nil || seq == nil {
			continue
		}
		// Faqat SHU node fazasidagi (offset'dan katta) id'lar hisobga olinadi:
		// replikadagi local qatorlari (kichik id) ketma-ketlikni surmasin.
		var last int64
		if err := Pool.QueryRow(ctx, fmt.Sprintf(
			`SELECT GREATEST(COALESCE((SELECT MAX(%s) FROM %s WHERE %s >= %d), 0), %d)`,
			QuoteIdent(t.PK[0]), QuoteIdent(t.Name), QuoteIdent(t.PK[0]),
			NonLocalIDOffset, NonLocalIDOffset)).Scan(&last); err != nil {
			continue
		}
		if _, err := Pool.Exec(ctx, `SELECT setval($1, $2)`, *seq, last); err != nil {
			log.Printf("SYNC: %s ketma-ketligi surilmadi: %v", t.Name, err)
			continue
		}
		shifted++
	}
	log.Printf("SYNC: node=%s — %d ta ketma-ketlik %d dan boshlandi (id to'qnashuvi bo'lmasin)",
		nodeID, shifted, NonLocalIDOffset)
	return nil
}

// QuoteIdent — identifikatorni xavfsiz qo'shtirnoqqa oladi. Jadval/ustun
// nomlari oq ro'yxatdan keladi, lekin bu qo'shimcha himoya.
func QuoteIdent(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
}
