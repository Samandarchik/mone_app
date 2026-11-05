package db

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var Pool *pgxpool.Pool

// NewUUID — UUIDv4 (crypto/rand). Sync eventlariga idempotent ID beradi;
// tashqi kutubxona yoki DB funksiyasiga bog'liq emas.
func NewUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40 // versiya 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// Init — ulanish hovuzini ochadi.
//
// `timeZone` HAR IKKALA node'da BIR XIL bo'lishi shart. Sabab: hisobotlar
// `created_at::date` va `CURRENT_DATE` bilan kun chegarasini Postgres SESSIYA
// mintaqasida hisoblaydi, Go tomoni esa sanani `time.Now()` bilan yozadi.
// Ilgari hech qayerda mintaqa o'rnatilmasdi: restorandagi Windows mashinasi
// UTC+5 da, bulutdagi Ubuntu esa UTC da ishlardi. Natijada soat 00:00–05:00
// oralig'idagi har bir chek bulutda OLDINGI kunga tushardi — ikkala node bir
// xil ma'lumotdan ikki xil kunlik tushum chiqarardi.
func Init(dbURL, timeZone string) error {
	cfg, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		return err
	}
	if timeZone != "" {
		if cfg.ConnConfig.RuntimeParams == nil {
			cfg.ConnConfig.RuntimeParams = map[string]string{}
		}
		cfg.ConnConfig.RuntimeParams["timezone"] = timeZone
	}
	// Standart hovuz max(4, NumCPU) ta ulanish beradi. Kassa notbukida bu 4 ta
	// bo'lishi mumkin: POS + WSS + sync + analitika bir vaqtda ishlaganda
	// so'rovlar navbatga tushib, butun kassa muzlab qolardi.
	if cfg.MaxConns < 20 {
		cfg.MaxConns = 20
	}
	cfg.MinConns = 2
	cfg.MaxConnLifetime = time.Hour
	cfg.MaxConnIdleTime = 30 * time.Minute
	cfg.HealthCheckPeriod = time.Minute

	Pool, err = pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		return err
	}

	// Postgres xizmati serverdan sekinroq ko'tarilishi mumkin (Windows'da
	// odatiy hol). Ilgari birinchi Ping muvaffaqiyatsiz bo'lsa server
	// `log.Fatal` bilan o'lib, restoran qo'lda qayta ishga tushirilgunicha
	// ishlamay turardi.
	var lastErr error
	for attempt := 1; attempt <= 30; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		lastErr = Pool.Ping(ctx)
		cancel()
		if lastErr == nil {
			break
		}
		log.Printf("PostgreSQL hali tayyor emas (%d/30): %v", attempt, lastErr)
		time.Sleep(2 * time.Second)
	}
	if lastErr != nil {
		return lastErr
	}

	var tz string
	Pool.QueryRow(context.Background(), "SHOW timezone").Scan(&tz)
	log.Printf("PostgreSQL connected (timezone=%s)", tz)
	return runMigrations()
}

func Close() {
	if Pool != nil {
		Pool.Close()
	}
}

// ============ SETTINGS (key/value) ============

// SeedSetting — sozlamani faqat hali YO'Q bo'lsa va qiymat bo'sh bo'lmasa yozadi
// (.env dagi qiymat birinchi ishga tushishda urug' bo'ladi, keyin UI hukmron).
func SeedSetting(key, value string) {
	if value == "" {
		return
	}
	Pool.Exec(context.Background(),
		"INSERT INTO settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING", key, value)
}

// GetSetting — sozlama qiymati (yo'q bo'lsa bo'sh satr).
func GetSetting(key string) string {
	var v string
	Pool.QueryRow(context.Background(), "SELECT value FROM settings WHERE key = $1", key).Scan(&v)
	return v
}

// SetSetting — sozlamani yozadi/yangilaydi.
func SetSetting(key, value string) error {
	_, err := Pool.Exec(context.Background(),
		`INSERT INTO settings (key, value, updated_at) VALUES ($1, $2, NOW())
		 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`, key, value)
	return err
}
