package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"

	"konak-local/internal/middleware"
	"konak-local/internal/wss"
)

func NewRouter(hub *wss.Hub) http.Handler {
	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(corsMiddleware)

	// Public (no auth)
	r.Get("/api/menu", handleGetMenu)
	r.Get("/api/menu-web", handleGetMenuWeb)
	r.Get("/api/table/{sku}", handleGetTable)
	r.Get("/api/stocks", handleGetStocks)
	r.Get("/api/health", handleHealth)

	// Auth
	r.Post("/api/auth/login", handleLogin)
	r.Post("/api/auth/pin-login", handlePinLogin)

	// QR mijoz (public)
	r.Get("/api/qr/table/{code}", handleQRTableLookup)
	r.Post("/api/qr/order", handleQROrderCreate)
	r.Post("/api/qr/call-waiter", handleCallWaiter)

	// Online (saboy / dostafka) — Telegram orqali tasdiqlangan mijozlar
	r.Post("/api/online/telegram/verify/start", handleOnlineVerifyStart)
	r.Get("/api/online/telegram/verify/check", handleOnlineVerifyCheck)
	r.Post("/api/online/telegram/webapp", handleOnlineWebappAuth)
	r.Post("/api/online/order", handleOnlineOrderCreate)

	// Protected
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthRequired)

		r.Get("/api/zones", handleGetZones)
		r.Get("/api/tables/qr-codes", handleGetQRCodes)
		r.Get("/api/orders", handleGetOrders)
		r.Get("/api/shift/current", handleGetShift)
		r.Post("/api/shift/open", handleShiftOpen)
		r.Post("/api/shift/close", handleShiftClose)
		r.Post("/api/expense", handleCreateExpense)
		r.Get("/api/expense-categories", handleGetExpenseCategories)
		r.Post("/api/expense-category", handleCreateExpenseCategory)
		r.Delete("/api/expense-category/{id}", handleDeleteExpenseCategory)
		r.Get("/api/finance/daily", handleFinanceDaily)
		r.Get("/api/finance/daily/expenses", handleFinanceExpenses)
		r.Get("/api/users", handleGetUsers)
		r.Post("/api/order/close", handleOrderClose)
		r.Post("/api/order/cancel", handleOrderCancel)
		r.Post("/api/order/cancel-item", handleOrderCancelItem)
		r.Post("/api/order/create", handleOrderCreateHTTP)
		r.Post("/api/product", handleCreateProduct)
		r.Put("/api/product/{id}", handleUpdateProduct)
		r.Delete("/api/product/{id}", handleDeleteProduct)
		r.Post("/api/stock/set", handleStockSetHTTP)
		r.Post("/api/stock/remove", handleStockRemoveHTTP)
		r.Post("/api/reorder", handleReorder)

		// Printers
		r.Get("/api/printers", handleGetPrinters)
		r.Post("/api/printers", handleCreatePrinter)
		r.Put("/api/printers/{id}", handleUpdatePrinter)
		r.Delete("/api/printers/{id}", handleDeletePrinter)

		// Category CRUD
		r.Post("/api/category", handleCreateCategory)
		r.Put("/api/category/{id}", handleUpdateCategory)
		r.Delete("/api/category/{id}", handleDeleteCategory)
		r.Post("/api/upload/category-image/{id}", handleUploadCategoryImage)

		// Print receipt
		r.Post("/api/order/print-receipt", handlePrintReceipt)
	})

	// Image upload (auth required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthRequired)
		r.Post("/api/upload/product-image/{id}", handleUploadProductImage)
	})

	// Static files — rasmlar
	fileServer := http.FileServer(http.Dir("./uploads"))
	r.Handle("/uploads/*", http.StripPrefix("/uploads/", fileServer))

	// WebSocket
	r.Get("/ws", func(w http.ResponseWriter, r *http.Request) {
		wss.ServeWS(hub, w, r)
	})

	return r
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, ngrok-skip-browser-warning")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Max-Age", "86400")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
