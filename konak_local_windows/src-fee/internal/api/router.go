package api

import (
	"log"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"konak-local/internal/middleware"
	"konak-local/internal/sync"
	"konak-local/internal/wss"
)

var customerWebDir = "./customer_web"
var customerPublicURL string

func SetCustomerWeb(dir, publicURL string) {
	if strings.TrimSpace(dir) != "" {
		customerWebDir = dir
	}
	customerPublicURL = strings.TrimRight(strings.TrimSpace(publicURL), "/")
}

// defaultCustomerPublicURL — mijoz sayti (konak_web, React SPA).
// Stollarga chiqariladigan QR havolalar SHU domenga ishoraydi: qaysi
// backend (local/bulut) so'rovga javob berayotgani ahamiyatsiz — mijoz
// doim konak.uz ni ochadi, u yerdan API bulutga boradi.
const defaultCustomerPublicURL = "https://konak.uz"

// customerURLForCode — stol QR havolasi.
//
// Format `/table/{code}` — konak_web SPA deep-link'i shu ko'rinishda
// (nginx `try_files ... /index.html` bilan). Eski `/customer/?code=`
// Flutter web buildi uchun edi, endi ishlatilmaydi.
func customerURLForCode(code string) string {
	base := customerPublicURL
	if base == "" {
		base = defaultCustomerPublicURL
	}
	return strings.TrimRight(base, "/") + "/table/" + url.PathEscape(code)
}

func NewRouter(hub *wss.Hub) http.Handler {
	r := chi.NewRouter()
	r.Use(requestLogger)
	r.Use(chimw.Recoverer)
	r.Use(corsMiddleware)

	// Public (no auth)
	r.Get("/api/menu", handleGetMenu)
	r.Get("/api/menu-web", handleGetMenuWeb)
	r.With(middleware.AuthRequired).Get("/api/table/{sku}", handleGetTable)
	// `/api/stocks` ilgari ochiq edi — istalgan kishi restoran omboridagi
	// har bir taomning qoldig'ini ko'ra olardi. QR mijoz uchun kerak emas:
	// u `/api/menu-web` orqali faqat sotuvdagi taomlarni oladi.
	r.With(middleware.AuthRequired).Get("/api/stocks", handleGetStocks)
	r.Get("/api/health", handleHealth)

	// Auth
	r.Post("/api/auth/login", handleLogin)
	r.Post("/api/auth/pin-login", handlePinLogin)

	// QR mijoz (public)
	r.Get("/api/qr/table/{code}", handleQRTableLookup)
	r.Post("/api/qr/session", handleQRSessionCreate)
	r.Get("/api/qr/status", handleQRStatus)
	r.Post("/api/qr/order", handleSecureQROrderCreate)
	r.Post("/api/qr/call-waiter", handleSecureCallWaiter)
	r.Post("/api/qr/request-bill", handleQRRequestBill)
	r.Post("/api/qr/promo/validate", handleValidatePromo)

	// Online (saboy / dostafka) — Telegram orqali tasdiqlangan mijozlar
	r.Post("/api/online/telegram/verify/start", handleOnlineVerifyStart)
	r.Get("/api/online/telegram/verify/check", handleOnlineVerifyCheck)
	r.Post("/api/online/telegram/webapp", handleOnlineWebappAuth)
	r.Post("/api/online/order", handleOnlineOrderCreate)

	// Protected
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthRequired)
		r.Use(middleware.AuditMutations)

		r.With(middleware.RequirePermission("zones", "read")).Get("/api/zones", handleGetZones)
		r.With(middleware.RequirePermission("zones", "read")).Get("/api/tables/qr-codes", handleGetQRCodes)
		r.With(middleware.RequirePermission("zones", "create")).Post("/api/zone", handleCreateZone)
		r.With(middleware.RequirePermission("zones", "update")).Put("/api/zone/{id}", handleUpdateZone)
		r.With(middleware.RequirePermission("zones", "delete")).Delete("/api/zone/{id}", handleDeleteZone)
		r.With(middleware.RequirePermission("orders", "read")).Get("/api/orders", handleGetOrders)
		r.With(middleware.RequirePermission("shifts", "read")).Get("/api/shift/current", handleGetShift)
		r.With(middleware.RequirePermission("shifts", "open")).Post("/api/shift/open", handleShiftOpen)
		r.With(middleware.RequirePermission("shifts", "close")).Post("/api/shift/close", handleShiftClose)
		r.With(middleware.RequirePermission("expenses", "create")).Post("/api/expense", handleCreateExpense)
		r.With(middleware.RequirePermission("expense_categories", "read")).Get("/api/expense-categories", handleGetExpenseCategories)
		r.With(middleware.RequirePermission("expense_categories", "create")).Post("/api/expense-category", handleCreateExpenseCategory)
		r.With(middleware.RequirePermission("expense_categories", "delete")).Delete("/api/expense-category/{id}", handleDeleteExpenseCategory)
		r.With(middleware.RequireAnyPermission("finance", "read_any_day", "read_today")).Get("/api/finance/daily", handleFinanceDaily)
		r.With(middleware.RequireAnyPermission("finance", "read_any_day", "read_today")).Get("/api/finance/daily/expenses", handleFinanceExpenses)
		r.With(middleware.RequirePermission("users", "read")).Get("/api/users", handleGetUsers)
		r.With(middleware.RequirePermission("users", "create")).Post("/api/user", handleCreateUser)
		r.With(middleware.RequirePermission("users", "update")).Put("/api/user/{id}", handleUpdateUser)
		r.With(middleware.RequirePermission("users", "delete")).Delete("/api/user/{id}", handleDeleteUser)

		// CRM, sodiqlik ballari va promo-kodlar.
		r.With(middleware.RequirePermission("customers", "read")).Get("/api/customers", handleGetCustomers)
		r.With(middleware.RequirePermission("customers", "read")).Get("/api/customers/{id}", handleGetCustomer)
		r.With(middleware.RequirePermission("customers", "create")).Post("/api/customers", handleCreateCustomer)
		r.With(middleware.RequirePermission("customers", "update")).Put("/api/customers/{id}", handleUpdateCustomer)
		r.With(middleware.RequirePermission("customers", "delete")).Delete("/api/customers/{id}", handleDeleteCustomer)
		r.With(middleware.RequireAnyPermission("loyalty", "update", "redeem")).Post("/api/customers/{id}/loyalty", handleCustomerLoyalty)
		r.With(middleware.RequirePermission("loyalty", "read")).Get("/api/promos", handleGetPromos)
		r.With(middleware.RequirePermission("loyalty", "create")).Post("/api/promos", handleCreatePromo)
		r.With(middleware.RequirePermission("loyalty", "update")).Put("/api/promos/{id}", handleUpdatePromo)
		r.With(middleware.RequirePermission("loyalty", "update")).Delete("/api/promos/{id}", handleDeletePromo)
		r.With(middleware.RequirePermission("loyalty", "read")).Post("/api/promos/validate", handleValidatePromo)

		r.With(middleware.RequirePermission("orders", "close")).Post("/api/order/close", handleOrderClose)
		r.With(middleware.RequireAnyPermission("orders", "cancel", "close")).Post("/api/order/cancel", handleOrderCancel)
		r.With(middleware.RequireAnyPermission("orders", "cancel", "close")).Post("/api/order/cancel-item", handleOrderCancelItem)
		r.With(middleware.RequirePermission("orders", "create")).Post("/api/order/create", handleOrderCreateHTTP)
		r.With(middleware.RequirePermission("products", "create")).Post("/api/product", handleCreateProduct)
		r.With(middleware.RequirePermission("products", "update")).Put("/api/product/{id}", handleUpdateProduct)
		r.With(middleware.RequirePermission("products", "delete")).Delete("/api/product/{id}", handleDeleteProduct)
		r.With(middleware.RequirePermission("products", "update")).Post("/api/stock/set", handleStockSetHTTP)
		r.With(middleware.RequirePermission("products", "update")).Post("/api/stock/remove", handleStockRemoveHTTP)
		r.With(middleware.RequirePermission("products", "update")).Post("/api/reorder", handleReorder)

		// Printers
		r.With(middleware.RequirePermission("printers", "read")).Get("/api/printers", handleGetPrinters)
		r.With(middleware.RequirePermission("printers", "create")).Post("/api/printers", handleCreatePrinter)
		r.With(middleware.RequirePermission("printers", "update")).Put("/api/printers/{id}", handleUpdatePrinter)
		r.With(middleware.RequirePermission("printers", "delete")).Delete("/api/printers/{id}", handleDeletePrinter)
		// Chek qaysi printerga chiqishi
		r.With(middleware.RequirePermission("printers", "read")).Get("/api/settings/receipt-printer", handleGetReceiptPrinter)
		r.With(middleware.RequirePermission("printers", "update")).Put("/api/settings/receipt-printer", handleSetReceiptPrinter)

		// Category CRUD
		r.With(middleware.RequirePermission("categories", "create")).Post("/api/category", handleCreateCategory)
		r.With(middleware.RequirePermission("categories", "update")).Put("/api/category/{id}", handleUpdateCategory)
		r.With(middleware.RequirePermission("categories", "delete")).Delete("/api/category/{id}", handleDeleteCategory)
		r.With(middleware.RequirePermission("categories", "update")).Post("/api/upload/category-image/{id}", handleUploadCategoryImage)

		// Print receipt
		r.With(middleware.RequirePermission("orders", "read")).Post("/api/order/print-receipt", handlePrintReceipt)

		// Sozlamalar — cloud sync URL/token (faqat super_admin)
		r.With(middleware.RequirePermission("settings", "read")).Get("/api/settings/cloud", handleGetCloudSettings)
		r.With(middleware.RequirePermission("settings", "update")).Put("/api/settings/cloud", handleSetCloudSettings)

		// Spisaniya (hisobdan chiqarish)
		r.With(middleware.RequirePermission("write_offs", "read")).Get("/api/write-offs", handleGetWriteOffs)
		r.With(middleware.RequirePermission("write_offs", "create")).Post("/api/write-offs", handleCreateWriteOff)

		// Inventarizatsiya (faqat super_admin/admin)
		r.With(middleware.RequirePermission("inventory", "create")).Post("/api/inventory", handleInventory)

		// Ombor — ingredientlar (admin/super_admin)
		r.With(middleware.RequirePermission("ingredients", "read")).Get("/api/ingredients", handleGetIngredients)
		r.With(middleware.RequirePermission("ingredients", "create")).Post("/api/ingredient", handleCreateIngredient)
		r.With(middleware.RequirePermission("ingredients", "update")).Put("/api/ingredient/{id}", handleUpdateIngredient)
		r.With(middleware.RequirePermission("ingredients", "delete")).Delete("/api/ingredient/{id}", handleDeleteIngredient)
		r.With(middleware.RequirePermission("ingredients", "update")).Post("/api/ingredient/adjust", handleAdjustIngredient)
		r.With(middleware.RequirePermission("ingredients", "read")).Get("/api/ingredient/moves", handleGetIngredientMoves)

		// Yetkazib beruvchilar va FIFO kirim partiyalari.
		r.With(middleware.RequirePermission("suppliers", "read")).Get("/api/suppliers", handleGetSuppliers)
		r.With(middleware.RequirePermission("suppliers", "create")).Post("/api/suppliers", handleCreateSupplier)
		r.With(middleware.RequirePermission("suppliers", "update")).Put("/api/suppliers/{id}", handleUpdateSupplier)
		r.With(middleware.RequirePermission("suppliers", "delete")).Delete("/api/suppliers/{id}", handleDeleteSupplier)
		r.With(middleware.RequirePermission("ingredient_batches", "read")).Get("/api/ingredient-batches", handleGetIngredientBatches)
		r.With(middleware.RequirePermission("ingredient_batches", "create")).Post("/api/ingredient-batches", handleCreateIngredientBatch)
		r.With(middleware.RequirePermission("ingredient_batches", "update")).Put("/api/ingredient-batches/{id}", handleUpdateIngredientBatch)
		r.With(middleware.RequirePermission("ingredient_batches", "update")).Post("/api/ingredient-batches/{id}/write-off", handleWriteOffIngredientBatch)
		r.With(middleware.RequirePermission("ingredient_batches", "delete")).Delete("/api/ingredient-batches/{id}", handleDeleteIngredientBatch)

		// Bozor xaridi (admin/super_admin)
		r.With(middleware.RequirePermission("bozor", "read")).Get("/api/bozor/list", handleBozorList)
		r.With(middleware.RequirePermission("bozor", "create")).Post("/api/purchase", handleCreatePurchase)
		r.With(middleware.RequirePermission("bozor", "read")).Get("/api/purchases", handleGetPurchases)
		r.With(middleware.RequirePermission("bozor", "delete")).Delete("/api/purchase/{id}", handleDeletePurchase)

		// Retsept (admin/super_admin)
		r.With(middleware.RequirePermission("recipes", "read")).Get("/api/recipes", handleGetRecipes)
		r.With(middleware.RequirePermission("recipes", "read")).Get("/api/recipe", handleGetRecipe)
		r.With(middleware.RequirePermission("recipes", "update")).Put("/api/recipe", handleUpsertRecipe)
		r.With(middleware.RequirePermission("recipes", "delete")).Delete("/api/recipe/{product_id}", handleDeleteRecipe)
		r.With(middleware.RequirePermission("recipes", "read")).Get("/api/recipe/cost", handleRecipeCost)
		// Audit jurnalidan retseptlarni tiklash: GET — faqat hisobot,
		// POST — haqiqatan yozadi (qarang: handleRecoverRecipes).
		r.With(middleware.RequirePermission("recipes", "read")).Get("/api/recipes/recover", handleRecoverRecipes)
		r.With(middleware.RequirePermission("recipes", "update")).Post("/api/recipes/recover", handleRecoverRecipes)

		// Pishirish (kitchen/admin/super_admin)
		r.With(middleware.RequirePermission("cooking", "read")).Get("/api/cooking/needed", handleCookingNeeded)
		r.With(middleware.RequirePermission("cooking", "create")).Post("/api/cooking/start", handleCookingStart)
		r.With(middleware.RequirePermission("cooking", "update")).Post("/api/cooking/{id}/done", handleCookingDone)
		r.With(middleware.RequirePermission("cooking", "update")).Post("/api/cooking/{id}/cancel", handleCookingCancel)
		r.With(middleware.RequirePermission("cooking", "read")).Get("/api/cookings", handleGetCookings)
		r.With(middleware.RequirePermission("cooking", "update")).Post("/api/stock/limit", handleStockLimit)
		r.With(middleware.RequirePermission("products", "update")).Post("/api/stock/add", handleStockAdd)

		// Analitika (admin/super_admin)
		r.With(middleware.RequirePermission("analytics", "read")).Get("/api/analytics/products", handleAnalyticsProducts)
		r.With(middleware.RequirePermission("analytics", "read")).Get("/api/analytics/overview", handleAnalyticsOverview)
		r.With(middleware.RequirePermission("analytics", "export")).Get("/api/analytics/export.csv", handleAnalyticsCSV)

		// Audit, monitoring va shifrlangan backup.
		r.With(middleware.RequirePermission("monitoring", "read")).Get("/api/operations/summary", handleOperationsSummary)
		r.With(middleware.RequirePermission("audit", "read")).Get("/api/audit", handleGetAuditLogs)
		r.With(middleware.RequirePermission("backups", "read")).Get("/api/backups", handleGetBackups)
		r.With(middleware.RequirePermission("backups", "create")).Post("/api/backups", handleCreateBackup)
		r.With(middleware.RequirePermission("backups", "read")).Get("/api/backups/{filename}/download", handleDownloadBackup)
		r.With(middleware.RequirePermission("backups", "restore")).Post("/api/backups/{filename}/restore", handleScheduleRestore)

		// Sync holati va to'liq tekislash (resync).
		r.With(middleware.RequirePermission("monitoring", "read")).Get("/api/sync/status", handleSyncStatus)
		r.With(middleware.RequirePermission("monitoring", "read")).Get("/api/sync/checksum", handleSyncChecksum)
		r.With(middleware.RequirePermission("backups", "restore")).Post("/api/sync/resync", handleSyncResync)
	})

	// Image upload (auth required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthRequired)
		r.Use(middleware.AuditMutations)
		r.With(middleware.RequirePermission("products", "update")).Post("/api/upload/product-image/{id}", handleUploadProductImage)
	})

	// Static files — rasmlar.
	// `http.FileServer` papka ro'yxatini ochiq ko'rsatadi: /uploads/products/
	// ga kirgan har kim yuklangan hamma faylni sanab chiqa olardi.
	r.Handle("/uploads/*", http.StripPrefix("/uploads/", noDirListing(http.Dir("./uploads"))))

	// QR mijoz Flutter web buildi. Fayl bo'lmasa aniq 404 qaytadi.
	r.Get("/customer", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/customer/", http.StatusTemporaryRedirect)
	})
	r.Handle("/customer/*", http.StripPrefix("/customer/", customerFileServer()))

	// WebSocket
	r.Get("/ws", func(w http.ResponseWriter, r *http.Request) {
		wss.ServeWS(hub, w, r)
	})

	// Sync peer (multi-master) — dialer node shu yerga ulanadi (acceptor rejim).
	// `?token=` sync token bilan himoyalangan.
	r.Get("/sync", sync.ServePeer)

	return r
}

// noDirListing — fayllarni beradi, LEKIN papka ro'yxatini ko'rsatmaydi.
func noDirListing(root http.FileSystem) http.Handler {
	fs := http.FileServer(root)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/") {
			http.NotFound(w, r)
			return
		}
		f, err := root.Open(path.Clean("/" + r.URL.Path))
		if err != nil {
			http.NotFound(w, r)
			return
		}
		defer f.Close()
		if info, err := f.Stat(); err != nil || info.IsDir() {
			http.NotFound(w, r)
			return
		}
		fs.ServeHTTP(w, r)
	})
}

func customerFileServer() http.Handler {
	static := http.FileServer(http.Dir(customerWebDir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cleanPath := strings.TrimPrefix(
			filepath.Clean(string(os.PathSeparator)+r.URL.Path),
			string(os.PathSeparator),
		)
		requested := filepath.Join(customerWebDir, cleanPath)
		info, err := os.Stat(requested)
		if err == nil && !info.IsDir() {
			static.ServeHTTP(w, r)
			return
		}
		index := filepath.Join(customerWebDir, "index.html")
		if _, err := os.Stat(index); err != nil {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, index)
	})
}

// requestLogger — so'rovlar jurnali, LEKIN maxfiy query parametrlari
// yulduzcha bilan almashtiriladi.
//
// NEGA: `chimw.Logger` butun URL'ni yozadi. Bizda esa token `?token=` orqali
// ham yuborilishi mumkin (`middleware.extractToken`, `/sync?token=`,
// `/api/qr/status?token=`). Natijada 12 soatlik JWT, QR sessiya tokeni va
// hatto node'lararo SYNC_TOKEN ochiq matnda `server_local.log` fayliga
// tushardi — logni ko'rgan har kim ular bilan tizimga kira olardi.
func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		ww := chimw.NewWrapResponseWriter(w, r.ProtoMajor)
		defer func() {
			log.Printf("%s %s -> %d (%s)",
				r.Method, redactURL(r.URL), ww.Status(), time.Since(started).Round(time.Millisecond))
		}()
		next.ServeHTTP(ww, r)
	})
}

// secretQueryKeys — jurnalga tushmasligi kerak bo'lgan query parametrlari.
var secretQueryKeys = []string{"token", "session_token", "pin"}

func redactURL(u *url.URL) string {
	q := u.Query()
	changed := false
	for _, key := range secretQueryKeys {
		if q.Has(key) {
			q.Set(key, "***")
			changed = true
		}
	}
	if !changed {
		return u.RequestURI()
	}
	clone := *u
	clone.RawQuery = q.Encode()
	return clone.RequestURI()
}

// corsMiddleware — QR mijoz sahifasi va admin panel istalgan manzildan
// ochilishi mumkin, shuning uchun Origin ochiq qoladi.
//
// LEKIN `Access-Control-Allow-Credentials: true` OLIB TASHLANDI. U reflected
// Origin bilan birga eng klassik CORS teshigi edi: istalgan sayt brauzerda
// ochilgan kassirdan nomidan so'rov yubora olardi. Ilova avtorizatsiyani
// `Authorization: Bearer` sarlavhasi orqali qiladi — cookie ishlatmaydi,
// shuning uchun bu bayroq umuman kerak emas.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-QR-Session, ngrok-skip-browser-warning")
		w.Header().Set("Access-Control-Max-Age", "86400")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
