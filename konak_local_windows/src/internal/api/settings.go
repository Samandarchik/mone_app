package api

// Sozlamalar — cloud sync manzili (faqat super_admin):
//   GET /api/settings/cloud — joriy URL/token + ulanish holati
//   PUT /api/settings/cloud — yangi URL/token; sync keyingi urinishda oladi

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/printer"
	"konak-local/internal/sync"
)

func handleGetCloudSettings(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if claims == nil || claims.Role != "super_admin" {
		jsonError(w, 403, "forbidden", "Faqat super_admin")
		return
	}
	jsonResponse(w, 200, map[string]interface{}{
		"url":       db.GetSetting("cloud_ws_url"),
		"token":     db.GetSetting("cloud_token"),
		"connected": sync.IsConnected(),
	})
}

func handleSetCloudSettings(w http.ResponseWriter, r *http.Request) {
	claims := middleware.GetUser(r.Context())
	if claims == nil || claims.Role != "super_admin" {
		jsonError(w, 403, "forbidden", "Faqat super_admin")
		return
	}

	var req struct {
		URL   string `json:"url"`
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}
	req.URL = strings.TrimSpace(req.URL)
	if req.URL != "" && !strings.HasPrefix(req.URL, "ws://") && !strings.HasPrefix(req.URL, "wss://") {
		jsonError(w, 400, "bad_url", "URL ws:// yoki wss:// bilan boshlanishi kerak")
		return
	}

	if err := db.SetSetting("cloud_ws_url", req.URL); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	if err := db.SetSetting("cloud_token", strings.TrimSpace(req.Token)); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	jsonResponse(w, 200, map[string]interface{}{
		"ok":      true,
		"url":     req.URL,
		"message": "Saqlandi — sync keyingi ulanishda yangi manzilni oladi",
	})
}

// ============ Chek printeri ============
// GET  /api/settings/receipt-printer — chek hozir qaysi printerga chiqadi
// PUT  /api/settings/receipt-printer — printerni tanlash (0/null → avtomatik)

func handleGetReceiptPrinter(w http.ResponseWriter, r *http.Request) {
	resp := map[string]interface{}{
		"printer_id": nil,
		"name":       "",
		"address":    "",
		"auto":       true,
	}
	if v := db.GetSetting(printer.ReceiptPrinterKey); v != "" {
		if id, err := strconv.Atoi(v); err == nil && id > 0 {
			resp["printer_id"] = id
		}
	}
	if rp := printer.ResolveReceiptPrinter(); rp != nil {
		resp["name"] = rp.Name
		resp["address"] = rp.Address
		resp["auto"] = rp.Auto
		if !rp.Auto {
			resp["printer_id"] = rp.ID
		}
	}
	jsonResponse(w, 200, resp)
}

func handleSetReceiptPrinter(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PrinterID *int `json:"printer_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonError(w, 400, "bad_request", "JSON noto'g'ri")
		return
	}

	// null yoki 0 — avtomatik tanlovga qaytarish
	if req.PrinterID == nil || *req.PrinterID == 0 {
		if err := db.SetSetting(printer.ReceiptPrinterKey, ""); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		jsonResponse(w, 200, map[string]interface{}{"ok": true, "printer_id": nil, "message": "Avtomatik tanlovga qaytarildi"})
		return
	}

	var name string
	err := db.Pool.QueryRow(r.Context(),
		"SELECT name FROM printer_stations WHERE id = $1 AND status = 'active'", *req.PrinterID).Scan(&name)
	if err != nil {
		jsonError(w, 404, "not_found", "Bunday aktiv printer yo'q")
		return
	}

	if err := db.SetSetting(printer.ReceiptPrinterKey, strconv.Itoa(*req.PrinterID)); err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	jsonResponse(w, 200, map[string]interface{}{
		"ok":         true,
		"printer_id": *req.PrinterID,
		"name":       name,
		"message":    "Chek endi \"" + name + "\" printeriga chiqadi",
	})
}
