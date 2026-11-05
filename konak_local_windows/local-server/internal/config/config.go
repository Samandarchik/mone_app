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
	CloudURL          string
	CloudWSURL        string
	LocalServerToken  string
	PrinterType       string
	PrinterAddress    string
	ServiceFeePercent int

	// Telegram bot (online: saboy / dostafka)
	TelegramBotToken    string
	TelegramAdminChatID string
	TelegramBotUsername string // ex: "konak_navoi_bot" — used to build deep-link
}

func Load() *Config {
	godotenv.Load()

	sfp, _ := strconv.Atoi(getEnv("SERVICE_FEE_PERCENT", "10"))

	return &Config{
		Port:              getEnv("PORT", "3000"),
		DBURL:             getEnv("DB_URL", "postgres://konak:konak@localhost:5432/konak_local?sslmode=disable"),
		JWTSecret:         getEnv("JWT_SECRET", "default-secret"),
		CloudURL:          getEnv("CLOUD_URL", "http://localhost:8080"),
		CloudWSURL:        getEnv("CLOUD_WS_URL", "ws://localhost:8080/internal/ws"),
		LocalServerToken:  getEnv("LOCAL_SERVER_TOKEN", ""),
		PrinterType:       getEnv("PRINTER_TYPE", "usb"),
		PrinterAddress:    getEnv("PRINTER_ADDRESS", "/dev/usb/lp0"),
		ServiceFeePercent: sfp,

		TelegramBotToken:    getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramAdminChatID: getEnv("TELEGRAM_ADMIN_CHAT_ID", ""),
		TelegramBotUsername: getEnv("TELEGRAM_BOT_USERNAME", "konak_navoi_bot"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
