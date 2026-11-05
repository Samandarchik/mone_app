package config

import (
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	Port              string
	DBURL             string
	JWTSecret         string
	PINPepper         string
	ServiceFeePercent int

	// TimeZone — kun chegarasi (smena, kunlik hisobot, buyurtma raqami)
	// AYNAN shu mintaqada hisoblanadi. Ikkala node'da bir xil bo'lishi SHART:
	// aks holda restorandagi Windows (UTC+5) va bulutdagi Ubuntu (UTC) bir xil
	// ma'lumotdan ikki xil kunlik tushum chiqaradi.
	TimeZone string

	// TrustProxyHeaders — server reverse-proxy (nginx/Caddy) orqasida
	// turganda `X-Forwarded-For` ga ishonish. To'g'ridan-to'g'ri ochiq
	// serverda YOQILMASIN: bu sarlavhani istalgan kishi soxtalashtirib,
	// kirish urinishlari chegarasini chetlab o'ta oladi.
	TrustProxyHeaders bool

	// Cloud sync — .env dagi qiymat faqat birinchi ishga tushishda settings
	// jadvaliga urug' bo'ladi; keyin super_admin UI orqali o'zgartiriladi.
	CloudWSURL       string
	LocalServerToken string

	// Multi-master sync — node identity + rol
	NodeID     string // event origin belgisi: "local" | "cloud"
	SyncMode   string // "dialer" (local ulanadi) | "acceptor" (cloud qabul qiladi) | "off"
	SyncListen string // acceptor: VPN peer WS uchun qo'shimcha listen (masalan 100.74.167.39:3100)
	SyncToken  string // /sync peer auth uchun umumiy maxfiy kalit
	BindAddr   string // asosiy HTTP listen manzili (bo'sh bo'lsa ":"+Port)

	// Telegram bot (online: saboy / dostafka)
	TelegramBotToken    string
	TelegramAdminChatID string
	TelegramBotUsername string // ex: "konak_navoi_bot" — used to build deep-link

	// Shifrlangan PostgreSQL backup.
	BackupEnabled       bool
	BackupDir           string
	BackupEncryptionKey string
	BackupRetentionDays int
	BackupHour          int
	PgDumpPath          string
	PgRestorePath       string

	// Flutter QR mijoz web buildi.
	CustomerWebDir    string
	CustomerPublicURL string
}

func Load() *Config {
	godotenv.Load()

	sfp, _ := strconv.Atoi(getEnv("SERVICE_FEE_PERCENT", "10"))
	jwtSecret := getEnv("JWT_SECRET", "")
	pinPepper := getEnv("PIN_PEPPER", jwtSecret)
	backupRetention, _ := strconv.Atoi(getEnv("BACKUP_RETENTION_DAYS", "30"))
	backupHour, _ := strconv.Atoi(getEnv("BACKUP_HOUR", "3"))
	backupEnabled, _ := strconv.ParseBool(getEnv("BACKUP_ENABLED", "true"))
	trustProxy, _ := strconv.ParseBool(getEnv("TRUST_PROXY_HEADERS", "false"))

	return &Config{
		Port:              getEnv("PORT", "3000"),
		DBURL:             getEnv("DB_URL", "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable"),
		JWTSecret:         jwtSecret,
		PINPepper:         pinPepper,
		ServiceFeePercent: sfp,
		TimeZone:          getEnv("TZ_NAME", "Asia/Tashkent"),
		TrustProxyHeaders: trustProxy,

		CloudWSURL:       getEnv("CLOUD_WS_URL", ""),
		LocalServerToken: getEnv("LOCAL_SERVER_TOKEN", ""),

		NodeID:     getEnv("NODE_ID", "local"),
		SyncMode:   getEnv("SYNC_MODE", "dialer"),
		SyncListen: getEnv("SYNC_LISTEN_ADDR", ""),
		SyncToken:  getEnv("SYNC_TOKEN", getEnv("LOCAL_SERVER_TOKEN", "")),
		BindAddr:   getEnv("BIND_ADDR", ""),

		TelegramBotToken:    getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramAdminChatID: getEnv("TELEGRAM_ADMIN_CHAT_ID", ""),
		TelegramBotUsername: getEnv("TELEGRAM_BOT_USERNAME", "konak_navoi_bot"),

		BackupEnabled:       backupEnabled,
		BackupDir:           getEnv("BACKUP_DIR", "./backups"),
		BackupEncryptionKey: getEnv("BACKUP_ENCRYPTION_KEY", pinPepper),
		BackupRetentionDays: backupRetention,
		BackupHour:          backupHour,
		PgDumpPath:          getEnv("PG_DUMP_PATH", "pg_dump"),
		PgRestorePath:       getEnv("PG_RESTORE_PATH", "pg_restore"),
		CustomerWebDir:      getEnv("CUSTOMER_WEB_DIR", "./customer_web"),
		CustomerPublicURL:   getEnv("CUSTOMER_PUBLIC_URL", ""),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
