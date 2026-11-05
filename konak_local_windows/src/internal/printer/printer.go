package printer

import (
	"context"
	"encoding/json"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"konak-local/internal/db"
)

// logoESCPOS holds pre-processed ESC/POS raster bytes for the logo
var logoESCPOS []byte

func init() {
	loadLogo("data/Konak_bw3.jpeg", 400)
}

// loadLogo reads a PNG, resizes to targetWidth, converts to monochrome raster
func loadLogo(path string, targetWidth int) {
	f, err := os.Open(path)
	if err != nil {
		log.Printf("PRINTER logo not found: %v", err)
		return
	}
	defer f.Close()

	img, _, err := image.Decode(f)
	if err != nil {
		log.Printf("PRINTER logo decode error: %v", err)
		return
	}

	bounds := img.Bounds()
	origW := bounds.Dx()
	origH := bounds.Dy()

	// Trim top/bottom whitespace from original image
	topY, bottomY := bounds.Min.Y, bounds.Max.Y-1
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		hasPixel := false
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			_, _, _, a := img.At(x, y).RGBA()
			if a >= 0x8000 {
				r, g, b, _ := img.At(x, y).RGBA()
				gray := (r*299 + g*587 + b*114) / 1000
				if gray < 0x8000 {
					hasPixel = true
					break
				}
			}
		}
		if hasPixel {
			topY = y
			break
		}
	}
	for y := bounds.Max.Y - 1; y >= topY; y-- {
		hasPixel := false
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			_, _, _, a := img.At(x, y).RGBA()
			if a >= 0x8000 {
				r, g, b, _ := img.At(x, y).RGBA()
				gray := (r*299 + g*587 + b*114) / 1000
				if gray < 0x8000 {
					hasPixel = true
					break
				}
			}
		}
		if hasPixel {
			bottomY = y
			break
		}
	}

	trimmedH := bottomY - topY + 1
	targetHeight := trimmedH * targetWidth / origW

	bytesPerLine := (targetWidth + 7) / 8
	data := make([]byte, 0, bytesPerLine*targetHeight)

	for y := 0; y < targetHeight; y++ {
		for xByte := 0; xByte < bytesPerLine; xByte++ {
			var b byte
			for bit := 0; bit < 8; bit++ {
				px := xByte*8 + bit
				if px < targetWidth {
					srcX := px*origW/targetWidth + bounds.Min.X
					srcY := y*trimmedH/targetHeight + topY
					r, g, bl, a := img.At(srcX, srcY).RGBA()
					if a < 0x8000 {
						continue // transparent → white
					}
					gray := (r*299 + g*587 + bl*114) / 1000
					if gray < 0x8000 {
						b |= 0x80 >> uint(bit) // black dot
					}
				}
			}
			data = append(data, b)
		}
	}

	// GS v 0 — print raster bit image
	xL := byte(bytesPerLine % 256)
	xH := byte(bytesPerLine / 256)
	yL := byte(targetHeight % 256)
	yH := byte(targetHeight / 256)

	var buf []byte
	buf = append(buf, 0x1B, 0x61, 0x01)                       // center
	buf = append(buf, 0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH) // GS v 0
	buf = append(buf, data...)

	logoESCPOS = buf
	log.Printf("PRINTER logo loaded: %dx%d trimmed→%dx%d (%d bytes)", origW, origH, targetWidth, targetHeight, len(buf))
}

// ReceiptPrinterKey — chek (mijoz uchun) printeri saqlanadigan sozlama kaliti
const ReceiptPrinterKey = "receipt_printer_id"

// ReceiptPrinter — chek chiqadigan printer
type ReceiptPrinter struct {
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Address string `json:"address"`
	// Auto=true — sozlamada tanlanmagan, nomi/tartibi bo'yicha avtomatik topildi
	Auto bool `json:"auto"`
}

// ResolveReceiptPrinter — chek qaysi printerga chiqishini aniqlaydi:
//  1. sozlamada tanlangan printer (receipt_printer_id)
//  2. nomida "chek" bor aktiv printer
//  3. birinchi aktiv printer
//
// Hech biri topilmasa nil qaytaradi.
func ResolveReceiptPrinter() *ReceiptPrinter {
	if v := db.GetSetting(ReceiptPrinterKey); v != "" {
		if id, err := strconv.Atoi(v); err == nil && id > 0 {
			if ps := getPrinterStation(id); ps != nil {
				return &ReceiptPrinter{ID: id, Name: ps.Name, Address: ps.Address}
			}
		}
	}

	var rp ReceiptPrinter
	err := db.Pool.QueryRow(context.Background(),
		`SELECT id, name, address FROM printer_stations
		 WHERE status = 'active' AND lower(name) LIKE '%chek%' ORDER BY id LIMIT 1`).
		Scan(&rp.ID, &rp.Name, &rp.Address)
	if err == nil {
		rp.Auto = true
		return &rp
	}

	err = db.Pool.QueryRow(context.Background(),
		`SELECT id, name, address FROM printer_stations
		 WHERE status = 'active' ORDER BY id LIMIT 1`).
		Scan(&rp.ID, &rp.Name, &rp.Address)
	if err != nil {
		return nil
	}
	rp.Auto = true
	return &rp
}

// normalizeAddr — port ko'rsatilmagan manzilga standart ESC/POS portini (9100) qo'shadi
func normalizeAddr(addr string) string {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return addr
	}
	if _, _, err := net.SplitHostPort(addr); err != nil {
		return addr + ":9100"
	}
	return addr
}

// PrintItem represents one item to print
type PrintItem struct {
	Name     string
	Quantity int
	Price    int
	Total    int
}

// PrintJob groups items for one printer station
type PrintJob struct {
	PrinterName    string
	PrinterAddress string
	OrderNumber    string
	OrderType      string
	TableSKU       string
	WaiterName     string
	Items          []PrintItem
	IsCancelled    bool
	CreatedAt      string
}

// --- CP866 encoding for Cyrillic on thermal printers ---

// toCP866 converts a UTF-8 string to CP866 encoded bytes.
// ASCII chars pass through unchanged; Cyrillic is mapped to CP866 positions.
func toCP866(s string) []byte {
	var result []byte
	for _, r := range s {
		switch {
		case r >= 'А' && r <= 'П':
			result = append(result, byte(0x80+(r-'А')))
		case r >= 'Р' && r <= 'Я':
			result = append(result, byte(0x90+(r-'Р')))
		case r >= 'а' && r <= 'п':
			result = append(result, byte(0xA0+(r-'а')))
		case r >= 'р' && r <= 'я':
			result = append(result, byte(0xE0+(r-'р')))
		case r == 'Ё':
			result = append(result, 0xF0)
		case r == 'ё':
			result = append(result, 0xF1)
		case r == '№':
			result = append(result, 0xFC)
		// O'zbek kirillchasi CP866 da yo'q — eng yaqin ruscha harfga
		// tushiriladi. Ilgari faqat ў/Ў qo'shilgan edi va qолган harflar
		// chekda `?` bo'lib chiqardi: "Қозон кабоб" → "?озон кабоб".
		case r == 'ў':
			result = append(result, byte(0xE0+('у'-'р')))
		case r == 'Ў':
			result = append(result, byte(0x90+('У'-'Р')))
		case r == 'қ':
			result = append(result, byte(0xA0+('к'-'а')))
		case r == 'Қ':
			result = append(result, byte(0x80+('К'-'А')))
		case r == 'ғ':
			result = append(result, byte(0xA0+('г'-'а')))
		case r == 'Ғ':
			result = append(result, byte(0x80+('Г'-'А')))
		case r == 'ҳ':
			result = append(result, byte(0xE0+('х'-'р')))
		case r == 'Ҳ':
			result = append(result, byte(0x90+('Х'-'Р')))
		case r == 'ҷ':
			result = append(result, byte(0xA0+('ж'-'а')))
		case r == 'Ҷ':
			result = append(result, byte(0x80+('Ж'-'А')))
		// O'zbek lotinchasidagi tutuq belgilari (oʻ, gʻ, ma'no) — chekda
		// oddiy apostrofga aylanadi, `?` emas.
		case r == 'ʻ' || r == 'ʼ' || r == '‘' || r == '’' || r == '`' || r == '´':
			result = append(result, '\'')
		case r == '“' || r == '”' || r == '«' || r == '»':
			result = append(result, '"')
		case r == '–' || r == '—':
			result = append(result, '-')
		case r < 128:
			result = append(result, byte(r))
		default:
			result = append(result, '?')
		}
	}
	return result
}

// cp866f formats and encodes to CP866
func cp866f(format string, args ...interface{}) []byte {
	return toCP866(fmt.Sprintf(format, args...))
}

// padR pads string to width based on rune count (not byte count)
func padR(s string, w int) string {
	n := utf8.RuneCountInString(s)
	if n >= w {
		return s
	}
	return s + strings.Repeat(" ", w-n)
}

// padL right-aligns string to width based on rune count
func padL(s string, w int) string {
	n := utf8.RuneCountInString(s)
	if n >= w {
		return s
	}
	return strings.Repeat(" ", w-n) + s
}

// line builds a label-value line with correct Cyrillic padding
func line(label string, value string) []byte {
	return toCP866(padR(label, 14) + value + "\n")
}

// --- Table info ---

type tableInfo struct {
	TableID  int
	ZoneName string
}

func resolveTableInfo(tableSKU string) *tableInfo {
	if tableSKU == "" {
		return nil
	}
	var ti tableInfo
	err := db.Pool.QueryRow(context.Background(),
		"SELECT t.id, z.name FROM tables t JOIN zones z ON z.id = t.zone_id WHERE t.sku = $1", tableSKU).
		Scan(&ti.TableID, &ti.ZoneName)
	if err != nil {
		return nil
	}
	return &ti
}

// --- Russian date ---

var ruMonths = []string{
	"", "января", "февраля", "марта", "апреля", "мая", "июня",
	"июля", "августа", "сентября", "октября", "ноября", "декабря",
}

func formatDateRu(t time.Time) string {
	return fmt.Sprintf("%02d %s %d %s", t.Day(), ruMonths[int(t.Month())], t.Year(), t.Format("15:04"))
}

func orderTypeLabel(orderType string) string {
	switch orderType {
	case "dine_in":
		return "В заведении"
	case "takeaway":
		return "Навынос"
	case "delivery":
		return "Доставка"
	}
	return orderType
}

// PrintOrder sends kitchen ticket to appropriate printers
func PrintOrder(orderNumber, orderType, tableSKU, createdAt, waiterName string, items []map[string]interface{}, cancelled bool) {
	jobs := map[int]*PrintJob{}

	for _, item := range items {
		productID := toInt(item["product_id"])
		quantity := toInt(item["quantity"])
		price := toInt(item["price"])
		total := toInt(item["total"])

		name := "—"
		if snap, ok := item["snapshot"]; ok {
			name = extractName(snap)
		}

		printerID := resolveProductPrinter(productID)
		if printerID == 0 {
			continue
		}

		job, exists := jobs[printerID]
		if !exists {
			ps := getPrinterStation(printerID)
			if ps == nil {
				continue
			}
			job = &PrintJob{
				PrinterName:    ps.Name,
				PrinterAddress: ps.Address,
				OrderNumber:    orderNumber,
				OrderType:      orderType,
				TableSKU:       tableSKU,
				WaiterName:     waiterName,
				IsCancelled:    cancelled,
				CreatedAt:      createdAt,
			}
			jobs[printerID] = job
		}

		job.Items = append(job.Items, PrintItem{
			Name:     name,
			Quantity: quantity,
			Price:    price,
			Total:    total,
		})
	}

	for _, job := range jobs {
		go sendToPrinter(job)
	}
}

// sendToPrinter — kitchen ticket
func sendToPrinter(job *PrintJob) {
	conn, err := net.DialTimeout("tcp", normalizeAddr(job.PrinterAddress), 5*time.Second)
	if err != nil {
		log.Printf("PRINTER [%s] connection failed (%s): %v", job.PrinterName, job.PrinterAddress, err)
		return
	}
	defer conn.Close()
	conn.SetWriteDeadline(time.Now().Add(10 * time.Second))

	var buf []byte

	// Disable Chinese mode, then set code page CP866 for Cyrillic
	buf = append(buf, 0x1C, 0x2E)       // FS . — disable Chinese character mode
	buf = append(buf, 0x1B, 0x74, 0x11) // ESC t 17 — CP866 Cyrillic

	// Center align
	buf = append(buf, 0x1B, 0x61, 0x01)

	// Title
	if job.IsCancelled {
		buf = append(buf, 0x1B, 0x21, 0x30)
		buf = append(buf, toCP866("BEKOR QILINDI\n")...)
		buf = append(buf, 0x1B, 0x21, 0x00)
	} else if job.OrderType == "takeaway" {
		buf = append(buf, 0x1B, 0x21, 0x30)
		buf = append(buf, toCP866("SABOY\n")...)
		buf = append(buf, 0x1B, 0x21, 0x00)
	} else if job.OrderType == "delivery" {
		buf = append(buf, 0x1B, 0x21, 0x30)
		buf = append(buf, toCP866("DOSTAFKA\n")...)
		buf = append(buf, 0x1B, 0x21, 0x00)
	} else {
		// Ichki buyurtma — oddiy o'lcham, bold yo'q (kichik header)
		buf = append(buf, toCP866("YANGI BUYURTMA\n")...)
	}
	buf = append(buf, '\n')

	// Left align
	buf = append(buf, 0x1B, 0x61, 0x00)

	// Waiter
	if job.WaiterName != "" {
		buf = append(buf, 0x1B, 0x21, 0x08)
		buf = append(buf, line("Официант", job.WaiterName)...)
		buf = append(buf, 0x1B, 0x21, 0x00)
	}

	// Send time
	t, err := time.Parse(time.RFC3339, job.CreatedAt)
	if err != nil {
		t = time.Now()
	}
	buf = append(buf, 0x1B, 0x21, 0x08)
	buf = append(buf, line("Отправлено", formatDateRu(t))...)
	buf = append(buf, 0x1B, 0x21, 0x00)

	// Station
	buf = append(buf, 0x1B, 0x21, 0x08)
	buf = append(buf, line("Цех", job.PrinterName)...)
	buf = append(buf, 0x1B, 0x21, 0x00)

	// Table
	ti := resolveTableInfo(job.TableSKU)
	if ti != nil {
		buf = append(buf, 0x1B, 0x21, 0x08)
		buf = append(buf, line("Стол №", fmt.Sprintf("%d (%s)", ti.TableID, ti.ZoneName))...)
		buf = append(buf, 0x1B, 0x21, 0x00)
	}

	// Order number
	buf = append(buf, 0x1B, 0x21, 0x08)
	buf = append(buf, line("Чек №", job.OrderNumber)...)
	buf = append(buf, 0x1B, 0x21, 0x00)

	// Order type
	buf = append(buf, 0x1B, 0x21, 0x08)
	buf = append(buf, line("Тип заказа", orderTypeLabel(job.OrderType))...)
	buf = append(buf, 0x1B, 0x21, 0x00)

	// Separator
	buf = append(buf, toCP866("................................\n")...)

	// Items header
	buf = append(buf, toCP866(padR("Наименование", 28)+"Кол-во\n")...)
	buf = append(buf, '\n')

	// Items — bekor qilingan bo'lsa minus belgi qo'shamiz
	buf = append(buf, 0x1B, 0x21, 0x08)
	for _, item := range job.Items {
		var qtyStr string
		if job.IsCancelled {
			qtyStr = fmt.Sprintf("-%d", item.Quantity)
		} else {
			qtyStr = fmt.Sprintf("%d", item.Quantity)
		}
		buf = append(buf, toCP866(padR(item.Name, 28)+qtyStr+"\n")...)
	}
	buf = append(buf, 0x1B, 0x21, 0x00)

	// Feed + cut
	buf = append(buf, '\n', '\n', '\n')
	buf = append(buf, 0x1D, 0x56, 0x42, 0x03)

	_, err = conn.Write(buf)
	if err != nil {
		log.Printf("PRINTER [%s] write failed: %v", job.PrinterName, err)
		return
	}

	log.Printf("PRINTER [%s] OK: %s %s (%d items)", job.PrinterName, job.OrderNumber, map[bool]string{true: "CANCEL", false: "NEW"}[job.IsCancelled], len(job.Items))
}

// PrintReceipt — customer payment receipt
func PrintReceipt(printerAddress, orderNumber, orderType, tableSKU string, items []map[string]interface{}, subtotal, serviceFee, discount, total int, paymentMethod string, serviceFeeCancelled bool) {
	go func() {
		conn, err := net.DialTimeout("tcp", normalizeAddr(printerAddress), 5*time.Second)
		if err != nil {
			log.Printf("RECEIPT print failed (%s): %v", printerAddress, err)
			return
		}
		defer conn.Close()
		conn.SetWriteDeadline(time.Now().Add(10 * time.Second))

		// Query waiter + created_at from order
		var waiterName string
		var createdAt time.Time
		db.Pool.QueryRow(context.Background(),
			"SELECT COALESCE(u.name, 'Kassir'), o.created_at FROM orders o LEFT JOIN users u ON u.id = o.created_by WHERE o.order_number = $1",
			orderNumber).Scan(&waiterName, &createdAt)

		var buf []byte

		// Disable Chinese mode, set CP866 Cyrillic
		buf = append(buf, 0x1C, 0x2E)
		buf = append(buf, 0x1B, 0x74, 0x11)

		// Logo (centered raster image)
		if len(logoESCPOS) > 0 {
			buf = append(buf, logoESCPOS...)
			buf = append(buf, 0x1B, 0x4A, 30)
		} else {
			buf = append(buf, 0x1B, 0x61, 0x01)
			buf = append(buf, 0x1B, 0x21, 0x30)
			buf = append(buf, toCP866("Konak\n")...)
			buf = append(buf, 0x1B, 0x21, 0x00)
		}

		// Left
		buf = append(buf, 0x1B, 0x61, 0x00)

		// Order info
		buf = append(buf, line("Чек №", orderNumber)...)
		buf = append(buf, line("Тип заказа", orderTypeLabel(orderType))...)
		buf = append(buf, line("Открыт", formatDateRu(createdAt))...)

		// Table
		ti := resolveTableInfo(tableSKU)
		if ti != nil {
			buf = append(buf, line("Стол №", fmt.Sprintf("%d (%s)", ti.TableID, ti.ZoneName))...)
		}

		// Separator
		buf = append(buf, toCP866("................................\n")...)

		// Items header
		buf = append(buf, 0x1B, 0x21, 0x08)
		buf = append(buf, toCP866(padR("Наименование", 16)+padL("Кол-во", 4)+padL("Цена", 10)+padL("Итого", 10)+"\n")...)
		buf = append(buf, 0x1B, 0x21, 0x00)
		buf = append(buf, '\n')

		// Items
		for _, item := range items {
			name := "—"
			if snap, ok := item["snapshot"]; ok {
				name = extractName(snap)
			}
			qty := toInt(item["quantity"])
			price := toInt(item["price"])
			itemTotal := toInt(item["total"])
			if qty <= 0 {
				continue
			}
			buf = append(buf, toCP866(padR(name, 16)+padL(fmt.Sprintf("%d", qty), 4)+padL(formatPrice(price), 10)+padL(formatPrice(itemTotal), 10)+"\n")...)
		}

		buf = append(buf, '\n')
		buf = append(buf, toCP866("................................\n")...)

		// Subtotal — right margin ~5mm (add 5 spaces padding right)
		buf = append(buf, toCP866(padR("  Итого", 20)+padL(formatPrice(subtotal)+" сум", 20)+"\n")...)
		buf = append(buf, '\n')

		// Service fee
		if serviceFeeCancelled {
			buf = append(buf, toCP866(padR("  Обслуживание", 20)+padL("BEKOR", 20)+"\n")...)
		} else if serviceFee > 0 {
			buf = append(buf, toCP866(padR("  Обслуживание", 20)+padL(formatPrice(serviceFee)+" сум", 20)+"\n")...)
		}
		buf = append(buf, '\n')

		// Discount
		if discount > 0 {
			buf = append(buf, toCP866(padR("  Скидка", 20)+padL("-"+formatPrice(discount)+" сум", 20)+"\n")...)
			buf = append(buf, '\n')
		}

		// Grand total (big + bold)
		buf = append(buf, 0x1B, 0x21, 0x30)
		buf = append(buf, toCP866("К оплате "+formatPrice(total)+" сум\n")...)
		buf = append(buf, 0x1B, 0x21, 0x00)

		// Separator
		buf = append(buf, toCP866("================================\n")...)

		// Footer centered
		buf = append(buf, 0x1B, 0x61, 0x01) // center
		buf = append(buf, '\n')

		buf = append(buf, toCP866("Bir lokma mutluluk\n")...)
		buf = append(buf, toCP866("Кусочек счастья\n")...)
		buf = append(buf, '\n')

		// QR instruction
		buf = append(buf, toCP866("Отсканируйте QR-код\n")...)
		buf = append(buf, toCP866("откройте меню, закажите\n")...)
		buf = append(buf, toCP866("с собой или оформите доставку!\n")...)
		buf = append(buf, '\n')

		// QR Code — konak.uz
		qrData := []byte("https://konak.uz")
		qrLen := len(qrData) + 3
		buf = append(buf, 0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00) // Model 2
		buf = append(buf, 0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x08)       // Size 8
		buf = append(buf, 0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31)       // Error M
		pL := byte(qrLen % 256)
		pH := byte(qrLen / 256)
		buf = append(buf, 0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30)
		buf = append(buf, qrData...)
		buf = append(buf, 0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30) // Print QR

		buf = append(buf, '\n')
		buf = append(buf, toCP866("konak.uz\n")...)

		// Feed + cut
		buf = append(buf, '\n', '\n')
		buf = append(buf, 0x1D, 0x56, 0x42, 0x03)

		_, err = conn.Write(buf)
		if err != nil {
			log.Printf("RECEIPT write failed: %v", err)
			return
		}
		log.Printf("RECEIPT OK: %s → %s", orderNumber, printerAddress)
	}()
}

func formatPrice(amount int) string {
	if amount < 1000 {
		return fmt.Sprintf("%d", amount)
	}
	s := fmt.Sprintf("%d", amount)
	// Insert space every 3 digits from right
	n := len(s)
	var result []byte
	for i, ch := range s {
		if i > 0 && (n-i)%3 == 0 {
			result = append(result, ' ')
		}
		result = append(result, byte(ch))
	}
	return string(result)
}

// --- helpers ---

func resolveProductPrinter(productID int) int {
	var productPrinterID, categoryPrinterID *int
	db.Pool.QueryRow(context.Background(),
		`SELECT p.printer_station_id, c.printer_station_id
		 FROM products p
		 JOIN categories c ON c.id = p.category_id
		 WHERE p.id = $1`, productID).Scan(&productPrinterID, &categoryPrinterID)
	if productPrinterID != nil && *productPrinterID > 0 {
		return *productPrinterID
	}
	if categoryPrinterID != nil && *categoryPrinterID > 0 {
		return *categoryPrinterID
	}
	return 0
}

type printerStation struct {
	Name    string
	Address string
}

func getPrinterStation(id int) *printerStation {
	var ps printerStation
	err := db.Pool.QueryRow(context.Background(),
		"SELECT name, address FROM printer_stations WHERE id = $1 AND status = 'active'", id).
		Scan(&ps.Name, &ps.Address)
	if err != nil {
		return nil
	}
	return &ps
}

func toInt(v interface{}) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

func extractName(snap interface{}) string {
	switch s := snap.(type) {
	case map[string]interface{}:
		// Nom map[string]string ham bo'lishi mumkin: QR buyurtmasi snapshotni
		// JSON'ga aylantirmasdan uzatadi. Bu hisobga olinmagani uchun QR
		// cheklarida mahsulot nomi o'rniga "—" chiqib, oshxona nima
		// pishirishni bilmasdi.
		if strMap, ok := s["name"].(map[string]string); ok {
			if ru := strMap["ru"]; ru != "" {
				return ru
			}
			if uz := strMap["uz"]; uz != "" {
				return uz
			}
			for _, v := range strMap {
				if v != "" {
					return v
				}
			}
		}
		if nameMap, ok := s["name"].(map[string]interface{}); ok {
			if ru, ok := nameMap["ru"].(string); ok && ru != "" {
				return ru
			}
			if uz, ok := nameMap["uz"].(string); ok && uz != "" {
				return uz
			}
			for _, v := range nameMap {
				if str, ok := v.(string); ok && str != "" {
					return str
				}
			}
		}
	case json.RawMessage:
		var m map[string]interface{}
		json.Unmarshal(s, &m)
		return extractName(m)
	case string:
		var m map[string]interface{}
		json.Unmarshal([]byte(s), &m)
		return extractName(m)
	}
	return "—"
}
