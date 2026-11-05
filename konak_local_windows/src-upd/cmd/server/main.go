package main

import (
	"context"
	"log"
	"net/http"
	"time"

	// Windows'da OS darajasida IANA vaqt mintaqalari bazasi yo'q — Mac/Linux'da
	// cross-compile qilingan binar "Asia/Tashkent"ni topolmay o'lardi (Windows'ning
	// o'zida build qilinganda Go o'z GOROOT'idagi zoneinfo.zip'dan topib olardi).
	// Bu import bazani binarning ichiga joylaydi (~450KB) — qayerda build
	// qilinishidan qat'i nazar ishlaydi.
	_ "time/tzdata"

	"konak-local/internal/api"
	"konak-local/internal/backup"
	"konak-local/internal/config"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/security"
	"konak-local/internal/sync"
	"konak-local/internal/telegram"
	"konak-local/internal/update"
	"konak-local/internal/version"
	"konak-local/internal/wss"
)

func main() {
	log.Println("KONAK LOCAL SERVER starting...")

	// Load config
	cfg := config.Load()
	if len(cfg.JWTSecret) < 32 {
		log.Fatal("JWT_SECRET kiritilishi va kamida 32 belgidan iborat bo'lishi kerak")
	}
	if len(cfg.PINPepper) < 16 {
		log.Fatal("PIN_PEPPER kiritilishi va kamida 16 belgidan iborat bo'lishi kerak")
	}

	// Init JWT
	middleware.SetJWTSecret(cfg.JWTSecret)
	security.ConfigurePINPepper(cfg.PINPepper)
	middleware.TrustProxyHeaders = cfg.TrustProxyHeaders
	// Sync kanalida PIN uzatish uchun umumiy konvert kaliti (SYNC_TOKEN).
	// Bo'sh/qisqa bo'lsa xodim sync'i PINsiz ketadi — sync.applyUser buni
	// aniq log qiladi.
	security.ConfigureSyncSecret(cfg.SyncToken)
	if cfg.SyncMode != "off" && !security.SyncSecretReady() {
		log.Println("OGOHLANTIRISH: SYNC_TOKEN qisqa yoki yo'q — xodim PINi node'lar orasida sync qilinmaydi")
	}
	backup.Configure(backup.Config{
		Enabled:       cfg.BackupEnabled,
		DBURL:         cfg.DBURL,
		Dir:           cfg.BackupDir,
		EncryptionKey: cfg.BackupEncryptionKey,
		RetentionDays: cfg.BackupRetentionDays,
		Hour:          cfg.BackupHour,
		PgDumpPath:    cfg.PgDumpPath,
		PgRestorePath: cfg.PgRestorePath,
	})
	if err := backup.ApplyPendingRestore(context.Background()); err != nil {
		log.Fatalf("Rejalashtirilgan backupni tiklashda xato: %v", err)
	}

	// Vaqt mintaqasi — Go va Postgres BIR XIL kunni ko'rishi uchun.
	//
	// Ilgari hech qayerda o'rnatilmasdi: Go sanani mashinaning local vaqtida
	// yozardi, Postgres esa `created_at::date` / `CURRENT_DATE` ni o'z sessiya
	// mintaqasida hisoblardi. Bulutdagi Ubuntu UTC da ishlagani uchun soat
	// 00:00–05:00 oralig'idagi har bir chek u yerda OLDINGI kunga tushardi —
	// ikkala node bir xil ma'lumotdan ikki xil kunlik hisobot chiqarardi.
	if loc, err := time.LoadLocation(cfg.TimeZone); err != nil {
		log.Fatalf("Vaqt mintaqasi noto'g'ri (TZ_NAME=%q): %v", cfg.TimeZone, err)
	} else {
		time.Local = loc
		log.Printf("Vaqt mintaqasi: %s", cfg.TimeZone)
	}

	// Init database
	log.Println("Connecting to PostgreSQL...")
	if err := db.Init(cfg.DBURL, cfg.TimeZone); err != nil {
		log.Fatalf("Database init failed: %v", err)
	}
	defer db.Close()
	db.Seed()
	log.Println("Database ready")
	backup.Start(context.Background())

	// Start WSS hub
	hub := wss.NewHub()
	go hub.Run()
	log.Println("WSS hub started")

	// Cloud sync — URL/token settings jadvalidan (super_admin UI orqali bir marta
	// kiritiladi, .env dagi qiymatlar birinchi ishga tushishda urug' bo'ladi).
	// URL bo'sh bo'lsa to'liq offline ishlayveradi.
	db.SeedSetting("cloud_ws_url", cfg.CloudWSURL)
	db.SeedSetting("cloud_token", cfg.LocalServerToken)
	// Buyurtma raqamlari node'lararo unikal bo'lsin (cloud → C26-08-07-P000001)
	db.SetNodeTag(cfg.NodeID)
	// Qator replikatsiyasi: har qanday INSERT/UPDATE/DELETE Postgres trigger
	// orqali to'liq qator bilan outbox'ga tushadi. Shu sababli hech bir
	// maydon (narx, vaqt, izoh) tushib qolmaydi va yangi handler qo'shilsa
	// ham replikatsiya avtomatik ishlaydi.
	if err := db.SetupReplication(cfg.NodeID); err != nil {
		log.Fatalf("Replikatsiya sozlanmadi: %v", err)
	}
	sync.Configure(cfg.NodeID, cfg.SyncMode, cfg.SyncToken)
	sync.Start()

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
	api.SetCustomerWeb(cfg.CustomerWebDir, cfg.CustomerPublicURL)
	api.ConfigureUpdates(cfg.UpdateDir, cfg.SyncToken)
	router := api.NewRouter(hub)

	// Avto-yangilanish: local (Windows) node bulutdan yangi binar chiqqanini
	// bilib, o'zini o'zi yangilaydi. Bulut/dev'da hech narsa qilmaydi.
	update.Start(cfg.SyncMode)

	addr := cfg.BindAddr
	if addr == "" {
		addr = ":" + cfg.Port
	}
	log.Println("Assalomu alaykum! Backend ishga tushdi")
	log.Printf("SERVER READY on %s (node=%s, sync=%s, versiya=%s)", addr, cfg.NodeID, cfg.SyncMode, version.Version)
	log.Printf("  HTTP: %s/api", addr)
	log.Printf("  WSS:  %s/ws", addr)

	// VPN (Tailscale) orqali sync peer uchun qo'shimcha listener.
	// Bu manzil public'ga chiqmaydi — faqat Tailscale interfeysida.
	if cfg.SyncListen != "" {
		go func() {
			log.Printf("SYNC listener (VPN) on %s", cfg.SyncListen)
			if err := newServer(cfg.SyncListen, router).ListenAndServe(); err != nil {
				log.Printf("SYNC listener failed: %v", err)
			}
		}()
	}

	if err := newServer(addr, router).ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// newServer — vaqt chegaralari bilan HTTP server.
//
// `http.ListenAndServe` HECH QANDAY timeout qo'ymaydi: sekin (yoki qasddan
// sekin) klient ulanishni cheksiz ushlab tura oladi va ular yig'ilib serverni
// bo'g'ib qo'yadi (Slowloris). WriteTimeout QO'YILMAYDI — /ws va /sync
// WebSocket ulanishlari soatlab ochiq turadi.
func newServer(addr string, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
}
