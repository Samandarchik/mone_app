package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"strings"

	"konak-local/internal/api"
	"konak-local/internal/config"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/sync"
	"konak-local/internal/telegram"
	"konak-local/internal/wss"
)

func main() {
	log.Println("KONAK LOCAL SERVER starting...")

	// Load config
	cfg := config.Load()

	// Init JWT
	middleware.SetJWTSecret(cfg.JWTSecret)

	// Init database
	log.Println("Connecting to PostgreSQL...")
	if err := db.Init(cfg.DBURL); err != nil {
		log.Fatalf("Database init failed: %v", err)
	}
	defer db.Close()
	db.Seed()
	log.Println("Database ready")

	// Set service fee
	wss.SetServiceFeePercent(cfg.ServiceFeePercent)

	// Start WSS hub
	hub := wss.NewHub()
	go hub.Run()
	log.Println("WSS hub started")

	// Connect to cloud (async)
	if cfg.LocalServerToken != "" {
		log.Println("Connecting to cloud server...")
		sync.ConnectToCloud(cfg.CloudWSURL, cfg.LocalServerToken)
	} else {
		log.Println("WARNING: No LOCAL_SERVER_TOKEN, running in offline mode")
	}

	// Telegram bot (saboy / dostafka verifikatsiya + buyurtma xabarnomalari)
	if cfg.TelegramBotToken != "" {
		bot := telegram.New(cfg.TelegramBotToken, cfg.TelegramAdminChatID, cfg.TelegramBotUsername)
		api.SetOnlineBot(bot)
		go bot.Run(context.Background())
		api.StartOnlineVerificationCleanup(context.Background())
	} else {
		log.Println("WARNING: TELEGRAM_BOT_TOKEN bo'sh — online buyurtma o'chirilgan")
	}

	// HTTP + WSS router
	router := api.NewRouter(hub)

	addr := ":" + cfg.Port
	log.Println("Assalomu alaykum! Backend ishga tushdi")
	go announceStartup()
	log.Printf("LOCAL SERVER READY on %s", addr)
	log.Printf("  HTTP: http://192.168.1.100%s/api", addr)
	log.Printf("  WSS:  ws://192.168.1.100%s/ws", addr)

	if err := http.ListenAndServe(addr, router); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func announceStartup() {
	var tables []string
	rows, err := db.Pool.Query(context.Background(), "SELECT z.name, t.number FROM tables t JOIN zones z ON z.id = t.zone_id WHERE z.status = 'active' AND z.name = 'ZAL' ORDER BY t.number")
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var name string
			var num int
			rows.Scan(&name, &num)
			tables = append(tables, name+" "+strings.TrimSpace(fmt.Sprintf("%d", num)))
		}
	}
	if len(tables) > 0 {
		exec.Command("say", strings.Join(tables, ", ")).Run()
	}
}
