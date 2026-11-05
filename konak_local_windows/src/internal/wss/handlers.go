package wss

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"time"

	"encoding/json"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/crm"
	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/models"
	"konak-local/internal/printer"
)

// HandleEvent routes incoming WSS events to handlers
func HandleEvent(c *Client, event *models.WSEvent) {
	switch event.Event {
	case "subscribe:table":
		handleTableSubscribe(c, event.Payload)
	case "table:enter":
		handleTableEnter(c, event.Payload)
	case "table:leave":
		handleTableLeave(c)
	case "order:create":
		handleOrderCreate(c, event.Payload)
	case "order:add_items":
		handleOrderAddItems(c, event.Payload)
	case "order:update_status":
		handleOrderUpdateStatus(c, event.Payload)
	case "order:close":
		handleOrderClose(c, event.Payload)
	case "order:transfer_table":
		handleOrderTransfer(c, event.Payload)
	case "shift:open":
		handleShiftOpen(c, event.Payload)
	case "shift:close":
		handleShiftClose(c, event.Payload)
	case "stock:set":
		handleStockSet(c, event.Payload)
	case "stock:remove":
		handleStockRemove(c, event.Payload)
	default:
		log.Printf("WSS: unknown event '%s' from %s", event.Event, c.Name)
	}
}

// ============ TABLE HANDLERS ============

func handleTableSubscribe(c *Client, payload json.RawMessage) {
	if c.Role != "guest" {
		H.SendToClient(c, "subscribe:error", map[string]string{"message": "Faqat QR mijoz uchun"})
		return
	}
	var request struct {
		SessionToken string `json:"session_token"`
	}
	if json.Unmarshal(payload, &request) != nil || request.SessionToken == "" {
		H.SendToClient(c, "subscribe:error", map[string]string{"message": "Sessiya kerak"})
		return
	}
	var tableSKU string
	err := db.Pool.QueryRow(context.Background(), `
		SELECT table_sku FROM qr_sessions
		WHERE token=$1 AND status='active'
		  AND COALESCE(expires_at,created_at+INTERVAL '8 hours')>NOW()`,
		request.SessionToken,
	).Scan(&tableSKU)
	if err != nil {
		H.SendToClient(c, "subscribe:error", map[string]string{"message": "Sessiya yaroqsiz"})
		return
	}
	c.setSubscribedTable(tableSKU)
	H.SendToClient(c, "subscribe:ok", map[string]string{"table_sku": tableSKU})
}

func handleTableEnter(c *Client, payload json.RawMessage) {
	// RUXSAT TEKSHIRUVI — ilgari bu handlerda umuman yo'q edi. Oqibati:
	// tokensiz QR mehmoni istalgan stol nomini yuborib, o'sha stolning
	// ochiq chekini (mijoz ismi va telefoni bilan) o'qib olardi va uni
	// "qulflab" xodimlarni stoldan bloklay olardi.
	if !middleware.HasPermission(c.Token, "tables", "read") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var p struct {
		TableSKU string `json:"table_sku"`
	}
	if json.Unmarshal(payload, &p) != nil || p.TableSKU == "" {
		H.SendToClient(c, "error", map[string]string{"message": "table_sku kerak"})
		return
	}

	// Check if table is locked by someone else
	var lock models.TableLock
	var lockedAt time.Time
	err := db.Pool.QueryRow(context.Background(), "SELECT table_sku, user_id, name, role, source, locked_at FROM table_locks WHERE table_sku = $1", p.TableSKU).
		Scan(&lock.TableSKU, &lock.UserID, &lock.Name, &lock.Role, &lock.Source, &lockedAt)

	if err == nil && lock.UserID != c.UserID {
		H.SendToClient(c, "table:locked", map[string]interface{}{
			"table_sku": p.TableSKU,
			"locked_by": map[string]interface{}{
				"user_id": lock.UserID, "name": lock.Name, "role": lock.Role, "source": lock.Source,
			},
			"locked_at": lockedAt.UTC().Format(time.RFC3339),
		})
		return
	}

	// Lock the table.
	// `ON CONFLICT` SHART: `table_sku` — birlamchi kalit. Ilgari oddiy INSERT
	// edi va o'sha xodim stolga qayta kirsa xato berardi (jimgina yutilardi);
	// ikki xodim bir vaqtda kirsa esa yutqazgani o'zini qulf egasi deb
	// o'ylab qolardi. Endi qaysi qator yozilgani aniq ko'rinadi.
	now := time.Now().UTC().Format(time.RFC3339)
	var lockOwner int
	if err := db.Pool.QueryRow(context.Background(), `
		INSERT INTO table_locks (table_sku, user_id, name, role, source, locked_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (table_sku) DO UPDATE
		   SET user_id=EXCLUDED.user_id, name=EXCLUDED.name, role=EXCLUDED.role,
		       source=EXCLUDED.source, locked_at=EXCLUDED.locked_at
		 WHERE table_locks.user_id = EXCLUDED.user_id
		RETURNING user_id`,
		p.TableSKU, c.UserID, c.Name, c.Role, c.Source, now).Scan(&lockOwner); err != nil {
		// Qator boshqa xodimda — biz qulfni ololmadik.
		H.SendToClient(c, "table:locked", map[string]interface{}{
			"table_sku": p.TableSKU,
			"message":   "Stol boshqa xodim tomonidan band qilingan",
		})
		return
	}
	c.SetLockedTable(p.TableSKU)

	// Get active order for this table
	var orderData interface{}
	order, err := getActiveOrderForTable(p.TableSKU)
	if err == nil {
		orderData = order
	}

	H.SendToClient(c, "table:entered", map[string]interface{}{
		"table_sku": p.TableSKU,
		"order":     orderData,
		"locked_by": map[string]interface{}{
			"user_id": c.UserID, "name": c.Name, "role": c.Role, "source": c.Source,
		},
	})
}

func handleTableLeave(c *Client) {
	tableSKU := c.LockedTable()
	if tableSKU == "" {
		return
	}
	UnlockTable(tableSKU)
	c.SetLockedTable("")

	H.SendToRoles("table:unlocked", map[string]interface{}{
		"table_sku":     tableSKU,
		"was_locked_by": map[string]interface{}{"user_id": c.UserID, "name": c.Name},
	}, "cashier", "waiter", "admin", "super_admin")
}

func UnlockTable(tableSKU string) {
	db.Pool.Exec(context.Background(), "DELETE FROM table_locks WHERE table_sku = $1", tableSKU)
}

// ============ ORDER HANDLERS ============

func handleOrderCreate(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "orders", "create") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	// Check shift
	var shiftStatus string
	err := db.Pool.QueryRow(context.Background(), "SELECT status FROM shifts WHERE status = 'open' LIMIT 1").Scan(&shiftStatus)
	if err != nil {
		H.SendToClient(c, "shift:required", map[string]string{"message": "Smena ochilmagan"})
		return
	}

	var p models.OrderCreatePayload
	json.Unmarshal(payload, &p)

	// Bo'sh buyurtma yaratilmasin
	if len(p.Items) == 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtmada mahsulot yo'q"})
		return
	}
	// Miqdor chegarasi. Ilgari bu yerda tekshiruv YO'Q edi: manfiy miqdor
	// yuborilsa chek summasi manfiy chiqib, `decreaseStock` esa qoldiqni
	// KO'PAYTIRIB yuborardi (count - (-5) = count + 5).
	if err := validateItemQuantities(p.Items); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": err.Error()})
		return
	}
	// Chek turi ham tekshiriladi: xato qiymat xizmat haqisiz o'tib ketardi,
	// stol "band" bo'lmasdi va chek abadiy ochiq qolib ketardi.
	if p.Type != "dine_in" && p.Type != "takeaway" && p.Type != "delivery" {
		H.SendToClient(c, "error", map[string]string{"message": "Chek turi noto'g'ri"})
		return
	}
	if len(p.Items) > 200 {
		H.SendToClient(c, "error", map[string]string{"message": "Bitta chekda 200 tadan ko'p qator bo'lmasin"})
		return
	}

	// Concurrency-safe global daily order number.
	orderNumber, err := db.NextOrderNumber(context.Background(), db.Pool, "pos")
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma raqami yaratilmadi"})
		return
	}

	// Build items with snapshots
	items := []models.OrderItem{}
	subtotal := 0
	now := time.Now().UTC().Format(time.RFC3339)

	for _, item := range p.Items {
		product, err := getProduct(item.ProductID)
		if err != nil {
			H.SendToClient(c, "error", map[string]string{"message": fmt.Sprintf("Mahsulot #%d topilmadi", item.ProductID)})
			return
		}

		// Check stock
		if !checkStock(item.ProductID, item.Quantity) {
			H.SendToClient(c, "error", map[string]string{"message": fmt.Sprintf("%s tugagan", product.NameUz)})
			return
		}

		snapshot := models.ProductSnapshot{
			Name:        map[string]string{"uz": product.NameUz, "ru": product.NameRu, "tr": product.NameTr},
			Description: buildDescription(product),
			Price:       product.Price,
			CategoryID:  product.CategoryID,
			Media:       json.RawMessage(product.Media),
		}
		snapshotJSON, _ := json.Marshal(snapshot)

		addedBy := models.AddedBy{Type: c.Source, Name: c.Name, UserID: &c.UserID}
		addedByJSON, _ := json.Marshal(addedBy)

		itemTotal := product.Price * item.Quantity
		subtotal += itemTotal

		items = append(items, models.OrderItem{
			ID:        len(items) + 1,
			ProductID: item.ProductID,
			Snapshot:  snapshotJSON,
			Quantity:  item.Quantity,
			Price:     product.Price,
			Total:     itemTotal,
			Note:      item.Note,
			AddedBy:   addedByJSON,
			AddedAt:   now,
		})
	}

	// Calculate totals
	serviceFee := 0
	if p.Type == "dine_in" {
		serviceFee = subtotal * getServiceFeePercent() / 100
	}
	total := subtotal + serviceFee

	itemsJSON, _ := json.Marshal(items)
	deliveryJSON := "null"
	if p.Delivery != nil {
		deliveryJSON = string(p.Delivery)
	}

	// Save order
	var tableID, zoneID *int
	if p.TableSKU != nil && *p.TableSKU != "" {
		var tid, zid int
		// Xato tekshiriladi — ilgari noto'g'ri stol nomida chek
		// `table_id=0, zone_id=0` bilan yozilib, hech qaysi stolga
		// bog'lanmay qolardi.
		if err := db.Pool.QueryRow(context.Background(),
			"SELECT id, zone_id FROM tables WHERE sku = $1", *p.TableSKU).Scan(&tid, &zid); err != nil {
			H.SendToClient(c, "error", map[string]string{"message": "Stol topilmadi"})
			return
		}
		tableID = &tid
		zoneID = &zid
	}

	// Qoldiq chekdan OLDIN atomar band qilinadi: yetmasa buyurtma umuman
	// yaratilmaydi (ilgari chek yozilib, qoldiq manfiyga tushib ketardi).
	reserved, err := ReserveStock(context.Background(), p.Items)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": err.Error()})
		return
	}

	_, err = db.Pool.Exec(context.Background(), `INSERT INTO orders (order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0, $11, 'unpaid', 'new', $12, $13, $14, $15, $16, $17, $18)`,
		orderNumber, p.Type, p.TableSKU, tableID, zoneID, deliveryJSON, string(itemsJSON),
		subtotal, serviceFee, 0, total, c.Source, c.UserID, p.CustomerName, p.CustomerPhone, p.Note, now, now)
	if err != nil {
		ReleaseStock(context.Background(), p.Items, reserved)
		log.Printf("Order create error: %v", err)
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma yaratishda xato"})
		return
	}

	// Update table status
	if p.TableSKU != nil && p.Type == "dine_in" {
		db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", *p.TableSKU)
	}

	// Build full order response
	order, _ := getOrderByNumber(orderNumber)
	orderResp := buildOrderResponse(order)

	// Broadcast
	H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})

	// Stock updates — yangi qoldiq ReserveStock'dan keladi (qayta SELECT
	// qilinsa orada boshqa kassa sotib, eski son e'lon qilinardi).
	for pid, count := range reserved {
		newCount := count
		BroadcastStock(pid, &newCount, "sold")
	}

	// Print receipt
	tableSKU := ""
	if p.TableSKU != nil {
		tableSKU = *p.TableSKU
	}
	var printItems []map[string]interface{}
	json.Unmarshal(itemsJSON, &printItems)
	printer.PrintOrder(orderNumber, p.Type, tableSKU, now, c.Name, printItems, false)

	// Table status
	if p.TableSKU != nil {
		H.SendToRoles("table:status_changed", map[string]interface{}{
			"table_sku":    *p.TableSKU,
			"status":       "occupied",
			"order_number": orderNumber,
		}, "cashier", "waiter", "admin", "super_admin")
	}

	// Sync to cloud
	addToSyncQueue("order:created", orderResp)

	log.Printf("Order created: %s type=%s source=%s by=%s", orderNumber, p.Type, c.Source, c.Name)
}

func handleOrderAddItems(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "orders", "add_items") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var p models.OrderAddItemsPayload
	json.Unmarshal(payload, &p)

	if len(p.Items) == 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Qo'shiladigan mahsulot yo'q"})
		return
	}
	if err := validateItemQuantities(p.Items); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": err.Error()})
		return
	}

	order, err := getOrderByNumber(p.OrderNumber)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma topilmadi"})
		return
	}
	// Yopilgan/bekor qilingan chekka mahsulot qo'shib bo'lmaydi. Ilgari bu
	// tekshirilmasdi: yopilgan chekka qo'shilgan mahsulot qoldiqdan chiqib
	// ketardi, lekin puli olinmasdi.
	if order.Status == "completed" || order.Status == "cancelled" {
		H.SendToClient(c, "error", map[string]string{"message": "Bu chek allaqachon yakunlangan"})
		return
	}

	// Parse existing items
	var existingItems []models.OrderItem
	json.Unmarshal([]byte(order.Items), &existingItems)

	now := time.Now().UTC().Format(time.RFC3339)
	newItems := []models.OrderItem{}
	addedSubtotal := 0
	nextID := len(existingItems) + 1

	for _, item := range p.Items {
		product, err := getProduct(item.ProductID)
		if err != nil {
			continue
		}
		if !checkStock(item.ProductID, item.Quantity) {
			H.SendToClient(c, "error", map[string]string{"message": fmt.Sprintf("%s tugagan", product.NameUz)})
			return
		}

		snapshot := models.ProductSnapshot{
			Name:        map[string]string{"uz": product.NameUz, "ru": product.NameRu, "tr": product.NameTr},
			Description: buildDescription(product),
			Price:       product.Price,
			CategoryID:  product.CategoryID,
			Media:       json.RawMessage(product.Media),
		}
		snapshotJSON, _ := json.Marshal(snapshot)
		addedBy := models.AddedBy{Type: c.Source, Name: c.Name, UserID: &c.UserID}
		addedByJSON, _ := json.Marshal(addedBy)

		itemTotal := product.Price * item.Quantity
		addedSubtotal += itemTotal

		oi := models.OrderItem{
			ID: nextID, ProductID: item.ProductID, Snapshot: snapshotJSON,
			Quantity: item.Quantity, Price: product.Price, Total: itemTotal,
			Note: item.Note, AddedBy: addedByJSON, AddedAt: now,
		}
		newItems = append(newItems, oi)
		existingItems = append(existingItems, oi)
		nextID++
	}

	newSubtotal := order.Subtotal + addedSubtotal
	newServiceFee := 0
	if order.Type == "dine_in" {
		newServiceFee = newSubtotal * getServiceFeePercent() / 100
	}
	newTotal := newSubtotal + newServiceFee + order.DeliveryFee - order.Discount

	// Avval qoldiq band qilinadi — yetmasa chek o'zgarmaydi.
	reserved, err := ReserveStock(context.Background(), p.Items)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": err.Error()})
		return
	}

	allItemsJSON, _ := json.Marshal(existingItems)
	tag, err := db.Pool.Exec(context.Background(), "UPDATE orders SET items = $1, subtotal = $2, service_fee = $3, total = $4, updated_at = $5 WHERE order_number = $6 AND status NOT IN ('completed','cancelled')",
		string(allItemsJSON), newSubtotal, newServiceFee, newTotal, now, p.OrderNumber)
	if err != nil || tag.RowsAffected() == 0 {
		ReleaseStock(context.Background(), p.Items, reserved)
		H.SendToClient(c, "error", map[string]string{"message": "Chek yangilanmadi — allaqachon yakunlangan bo'lishi mumkin"})
		return
	}

	resp := map[string]interface{}{
		"order_number": p.OrderNumber,
		"new_items":    newItems,
		"new_subtotal": newSubtotal,
		"new_total":    newTotal,
	}
	if order.TableSKU != nil {
		resp["table_sku"] = *order.TableSKU
	}
	H.BroadcastEvent("order:items_added", resp)

	for pid, count := range reserved {
		newCount := count
		BroadcastStock(pid, &newCount, "sold")
	}

	// Print added items
	tableSKU := ""
	if order.TableSKU != nil {
		tableSKU = *order.TableSKU
	}
	newItemsJSON, _ := json.Marshal(newItems)
	var addedPrintItems []map[string]interface{}
	json.Unmarshal(newItemsJSON, &addedPrintItems)
	printer.PrintOrder(p.OrderNumber, order.Type, tableSKU, now, c.Name, addedPrintItems, false)

	addToSyncQueue("order:items_added", resp)
}

func handleOrderUpdateStatus(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "orders", "update_status") && !middleware.HasPermission(c.Token, "orders", "update") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var p models.OrderUpdateStatusPayload
	json.Unmarshal(payload, &p)

	// `completed` BU YERDAN QO'YILMAYDI.
	//
	// Ilgari ruxsat etilgan edi va og'ir teshik ochardi: chek "yakunlangan"
	// bo'lardi, LEKIN `payment_status` 'unpaid' bo'lib qolardi va stol
	// bo'shatilmasdi. Sotuv hisobotdan yo'qolardi (hisobot faqat to'langan
	// cheklarni sanaydi), stol esa abadiy "band" bo'lib, smenani yopib
	// bo'lmasdi. Chekni yopishning yagona to'g'ri yo'li — `order:close`.
	//
	// `delivered` — dostafka "yuborildi" holati. U ilgari ro'yxatda YO'Q edi:
	// kassir chipni bosardi, ekranda rang o'zgarardi, serverga esa hech
	// narsa yozilmasdi va keyingi yangilanishda eski holat qaytardi.
	allowed := map[string]bool{
		"new": true, "preparing": true, "ready": true, "delivered": true,
		"cancelled": true,
	}
	if !allowed[p.Status] {
		H.SendToClient(c, "error", map[string]string{
			"message": "Bu status bu yerdan qo'yilmaydi (chekni yopish alohida amal)",
		})
		return
	}
	// BEKOR QILISH alohida ruxsat talab qiladi.
	//
	// Ilgari u `orders:update_status` ga bog'langan edi — ya'ni OSHXONA
	// ekrani kassaning ochiq chekini bekor qilib, qoldiqni qaytarib,
	// stolni bo'shatib yubora olardi. Endi faqat `orders:cancel` (yoki
	// `orders:close`) egasi bekor qila oladi; oshxona rolida bu yo'q.
	if p.Status == "cancelled" &&
		!middleware.HasPermission(c.Token, "orders", "cancel") &&
		!middleware.HasPermission(c.Token, "orders", "close") {
		H.SendToClient(c, "error", map[string]string{
			"message": "Chekni bekor qilishga ruxsat yo'q",
		})
		return
	}

	ctx := context.Background()
	now := time.Now().UTC().Format(time.RFC3339)

	// Joriy holatni olamiz: yakunlangan/bekor qilingan chek qayta o'zgarmasin
	var currentStatus string
	var tableSKU *string
	if err := db.Pool.QueryRow(ctx,
		"SELECT status, table_sku FROM orders WHERE order_number=$1",
		p.OrderNumber).Scan(&currentStatus, &tableSKU); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma topilmadi"})
		return
	}
	if currentStatus == "completed" || currentStatus == "cancelled" {
		H.SendToClient(c, "error", map[string]string{
			"message": "Bu chek allaqachon yakunlangan",
		})
		return
	}

	tag, err := db.Pool.Exec(ctx,
		"UPDATE orders SET status=$1,updated_at=$2 WHERE order_number=$3 AND status NOT IN ('completed','cancelled')",
		p.Status, now, p.OrderNumber)
	if err != nil || tag.RowsAffected() == 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Status o'zgartirilmadi"})
		return
	}

	// BEKOR QILISH: mahsulotlar omborga QAYTADI va stol bo'shaydi.
	if p.Status == "cancelled" {
		var itemsJSON []byte
		if db.Pool.QueryRow(ctx, "SELECT items FROM orders WHERE order_number=$1",
			p.OrderNumber).Scan(&itemsJSON) == nil {
			var items []models.OrderItem
			json.Unmarshal(itemsJSON, &items)
			for _, it := range items {
				if it.ProductID <= 0 || it.Quantity <= 0 {
					continue
				}
				var newCount int
				if err := db.Pool.QueryRow(ctx,
					"UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2 RETURNING count",
					it.Quantity, it.ProductID).Scan(&newCount); err == nil {
					BroadcastStock(it.ProductID, &newCount, "cancelled")
				}
			}
		}
		if tableSKU != nil && *tableSKU != "" {
			var otherActive int
			db.Pool.QueryRow(ctx,
				"SELECT COUNT(*) FROM orders WHERE table_sku=$1 AND status NOT IN ('completed','cancelled')",
				*tableSKU).Scan(&otherActive)
			if otherActive == 0 {
				db.Pool.Exec(ctx, "UPDATE tables SET status='free' WHERE sku=$1", *tableSKU)
				UnlockTable(*tableSKU)
				H.BroadcastEvent("table:status_changed", map[string]interface{}{
					"table_sku": *tableSKU, "status": "free",
				})
			}
		}
		go BroadcastShiftStatsExported()
	}

	resp := map[string]interface{}{
		"order_number": p.OrderNumber,
		"status":       p.Status,
		"updated_at":   now,
	}
	if tableSKU != nil {
		resp["table_sku"] = *tableSKU
	}
	H.BroadcastEvent("order:updated", resp)
	addToSyncQueue("order:status_updated", resp)
}

func handleOrderClose(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "orders", "close") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var p models.OrderClosePayload
	json.Unmarshal(payload, &p)

	order, err := getOrderByNumber(p.OrderNumber)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma topilmadi"})
		return
	}
	if order.Status == "completed" || order.Status == "cancelled" {
		H.SendToClient(c, "error", map[string]string{"message": "Bu chek allaqachon yakunlangan"})
		return
	}
	if p.Discount < 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Chegirma manfiy bo'lishi mumkin emas"})
		return
	}

	newTotal := order.Total - p.Discount
	if newTotal < 0 {
		newTotal = 0
	}
	now := time.Now().UTC().Format(time.RFC3339)

	// Aralash to'lov (split) — ixtiyoriy; WSS'da har doim bitta chek yopiladi (orderCount == 1)
	payMethod := p.PaymentMethod
	var paymentsJSON []byte
	if len(p.Payments) > 0 {
		if code, msg := models.ValidatePayments(p.Payments, newTotal); code != "" {
			H.SendToClient(c, "error", map[string]string{"error": code, "message": msg})
			return
		}
		payMethod = "split"
		paymentsJSON, _ = json.Marshal(p.Payments)
	}

	// `status NOT IN (...)` — ikki kassa bir chekni bir vaqtda yopsa faqat
	// bittasi o'tadi; ikkinchisi RowsAffected()==0 bilan qaytariladi.
	tag, err := db.Pool.Exec(context.Background(), "UPDATE orders SET payment_method = $1, payments = $2, payment_status = 'paid', status = 'completed', discount = $3, total = $4, updated_at = $5 WHERE order_number = $6 AND status NOT IN ('completed','cancelled')",
		payMethod, paymentsJSON, p.Discount, newTotal, now, p.OrderNumber)
	if err != nil || tag.RowsAffected() == 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Chek yopilmadi — allaqachon yakunlangan bo'lishi mumkin"})
		return
	}
	if err := crm.CompleteOrder(context.Background(), p.OrderNumber); err != nil {
		log.Printf("CRM order %s: %v", p.OrderNumber, err)
	}

	// Free the table
	if order.TableSKU != nil {
		db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'free' WHERE sku = $1", *order.TableSKU)
		UnlockTable(*order.TableSKU)

		H.SendToRoles("table:status_changed", map[string]interface{}{
			"table_sku":    *order.TableSKU,
			"status":       "free",
			"order_number": p.OrderNumber,
		}, "cashier", "waiter", "admin", "super_admin")

		H.SendToRoles("table:unlocked", map[string]interface{}{
			"table_sku": *order.TableSKU,
		}, "cashier", "waiter", "admin", "super_admin")
	}

	// Close QR sessions
	db.Pool.Exec(context.Background(), "UPDATE qr_sessions SET status = 'closed', closed_at = $1 WHERE order_number = $2 AND status = 'active'", now, p.OrderNumber)

	resp := map[string]interface{}{
		"order_number":   p.OrderNumber,
		"total":          newTotal,
		"payment_method": payMethod,
	}
	if order.TableSKU != nil {
		resp["table_sku"] = *order.TableSKU
	}
	if len(p.Payments) > 0 {
		resp["payments"] = p.Payments
	}
	H.BroadcastEvent("order:closed", resp)
	addToSyncQueue("order:closed", resp)

	log.Printf("Order closed: %s payment=%s total=%d", p.OrderNumber, payMethod, newTotal)
}

func handleOrderTransfer(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "table_transfer", "transfer") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var p models.OrderTransferPayload
	json.Unmarshal(payload, &p)

	// Check target table
	var toStatus string
	err := db.Pool.QueryRow(context.Background(), "SELECT status FROM tables WHERE sku = $1", p.ToTableSKU).Scan(&toStatus)
	if err != nil {
		H.SendToClient(c, "order:transfer_failed", map[string]interface{}{"to_table_sku": p.ToTableSKU, "reason": "not_found"})
		return
	}
	if toStatus == "occupied" {
		H.SendToClient(c, "order:transfer_failed", map[string]interface{}{"to_table_sku": p.ToTableSKU, "reason": "occupied", "message": "Bu stolda aktiv buyurtma bor"})
		return
	}

	// Check lock
	var lockUser string
	err = db.Pool.QueryRow(context.Background(), "SELECT name FROM table_locks WHERE table_sku = $1", p.ToTableSKU).Scan(&lockUser)
	if err == nil {
		H.SendToClient(c, "order:transfer_failed", map[string]interface{}{"to_table_sku": p.ToTableSKU, "reason": "locked", "locked_by": map[string]string{"name": lockUser}})
		return
	}

	// Get new table info
	var toTableID, toZoneID int
	var toLabel, toZoneName string
	db.Pool.QueryRow(context.Background(), "SELECT t.id, t.zone_id, t.label, z.name FROM tables t JOIN zones z ON t.zone_id = z.id WHERE t.sku = $1", p.ToTableSKU).
		Scan(&toTableID, &toZoneID, &toLabel, &toZoneName)

	now := time.Now().UTC().Format(time.RFC3339)
	ctx := context.Background()

	// Ko'chirish BITTA tranzaksiyada va chek HAQIQATAN ko'chganini tekshirib.
	//
	// Ilgari `UPDATE orders ... WHERE order_number=$5` da status sharti ham,
	// natija tekshiruvi ham yo'q edi. Mavjud bo'lmagan (yoki allaqachon
	// yopilgan) raqam yuborilsa: hech qanday chek ko'chmasdi, LEKIN eski
	// stol "bo'sh" bo'lib qolardi (u yerda haqiqiy ochiq chek turgan
	// bo'lishi mumkin edi!) va yangi stol abadiy "band" bo'lib, unda
	// yopadigan hech narsa qolmasdi.
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx, `
		UPDATE orders SET table_sku=$1, table_id=$2, zone_id=$3, updated_at=$4
		 WHERE order_number=$5 AND table_sku=$6 AND status NOT IN ('completed','cancelled')`,
		p.ToTableSKU, toTableID, toZoneID, now, p.OrderNumber, p.FromTableSKU)
	if err != nil || tag.RowsAffected() == 0 {
		H.SendToClient(c, "order:transfer_failed", map[string]interface{}{
			"to_table_sku": p.ToTableSKU, "reason": "order_not_found",
			"message": "Bu stolda shunday ochiq chek yo'q",
		})
		return
	}

	// Eski stolni faqat unda BOSHQA ochiq chek qolmagan bo'lsa bo'shatamiz.
	var stillOpen int
	if err := tx.QueryRow(ctx,
		"SELECT COUNT(*) FROM orders WHERE table_sku=$1 AND status NOT IN ('completed','cancelled')",
		p.FromTableSKU).Scan(&stillOpen); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	if stillOpen == 0 {
		if _, err := tx.Exec(ctx, "UPDATE tables SET status='free' WHERE sku=$1", p.FromTableSKU); err != nil {
			H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
			return
		}
	}
	if _, err := tx.Exec(ctx, "UPDATE tables SET status='occupied' WHERE sku=$1", p.ToTableSKU); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	if _, err := tx.Exec(ctx, "DELETE FROM table_locks WHERE table_sku=$1", p.FromTableSKU); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO table_locks (table_sku, user_id, name, role, source, locked_at)
		VALUES ($1,$2,$3,$4,$5,$6)
		ON CONFLICT (table_sku) DO UPDATE
		   SET user_id=EXCLUDED.user_id, name=EXCLUDED.name, role=EXCLUDED.role,
		       source=EXCLUDED.source, locked_at=EXCLUDED.locked_at`,
		p.ToTableSKU, c.UserID, c.Name, c.Role, c.Source, now); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	if err := tx.Commit(ctx); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ko'chirib bo'lmadi"})
		return
	}
	c.SetLockedTable(p.ToTableSKU)

	resp := map[string]interface{}{
		"order_number":   p.OrderNumber,
		"from_table_sku": p.FromTableSKU,
		"to_table_sku":   p.ToTableSKU,
		"to_zone_name":   map[string]string{"uz": toZoneName},
		"to_label":       toLabel,
	}
	H.BroadcastEvent("order:transferred", resp)

	H.SendToRoles("table:status_changed", map[string]interface{}{"table_sku": p.FromTableSKU, "status": "free"}, "cashier", "waiter", "admin")
	H.SendToRoles("table:status_changed", map[string]interface{}{"table_sku": p.ToTableSKU, "status": "occupied", "order_number": p.OrderNumber}, "cashier", "waiter", "admin")

	addToSyncQueue("table:transferred", resp)
}

// ============ SHIFT HANDLERS ============

func handleShiftOpen(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "shifts", "open") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	var existingStatus string
	err := db.Pool.QueryRow(context.Background(), "SELECT status FROM shifts WHERE status = 'open'").Scan(&existingStatus)
	if err == nil {
		H.SendToClient(c, "error", map[string]string{"error": "shift_already_open", "message": "Smena allaqachon ochiq"})
		return
	}

	var p models.ShiftOpenRequest
	json.Unmarshal(payload, &p)
	if p.OpeningCash < 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Kassadagi pul manfiy bo'lmaydi"})
		return
	}

	now := time.Now().UTC()
	openedBy, _ := json.Marshal(map[string]interface{}{"user_id": c.UserID, "name": c.Name, "role": c.Role})

	var shiftID int64
	// Xato TEKSHIRILADI (qarang: HTTP handleShiftOpen). Unikal indeks ikki
	// parallel so'rovdan bittasini shu yerda to'xtatadi.
	if err := db.Pool.QueryRow(context.Background(), "INSERT INTO shifts (date, opened_by, opened_at, opening_cash, status) VALUES ($1, $2, $3, $4, 'open') RETURNING id",
		now.Format("2006-01-02"), string(openedBy), now.Format(time.RFC3339), p.OpeningCash).Scan(&shiftID); err != nil {
		H.SendToClient(c, "error", map[string]string{"error": "shift_already_open", "message": "Smena ochilmadi — allaqachon ochiq bo'lishi mumkin"})
		return
	}

	// Smena boshidagi qoldiq surati — yopilishda solishtirish (recon) uchun
	db.Pool.Exec(context.Background(), `INSERT INTO shift_stock_snapshots (shift_id, product_id, count)
		SELECT $1, product_id, count FROM stocks ON CONFLICT DO NOTHING`, shiftID)

	resp := map[string]interface{}{
		"shift_id":     shiftID,
		"date":         now.Format("2006-01-02"),
		"status":       "open",
		"opened_by":    map[string]interface{}{"user_id": c.UserID, "name": c.Name},
		"opened_at":    now.Format(time.RFC3339),
		"opening_cash": p.OpeningCash,
	}
	H.BroadcastEvent("shift:opened", resp)
	addToSyncQueue("shift:opened", resp)
}

func handleShiftClose(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "shifts", "close") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}

	// Check active orders
	var activeCount int
	// Sana filtri OLIB TASHLANDI: 23:50 da ochilgan chek 00:10 da smenani
	// to'smasdi, keyin esa yangi smenaning oynasiga ham tushmasdi — pul
	// kassada bo'lib, hech qaysi hisobotda ko'rinmasdi.
	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed', 'cancelled')").Scan(&activeCount)
	if activeCount > 0 {
		H.SendToClient(c, "error", map[string]interface{}{
			"error": "active_orders_exist", "message": fmt.Sprintf("%d ta yopilmagan buyurtma bor", activeCount), "active_orders_count": activeCount,
		})
		return
	}

	var p models.ShiftCloseRequest
	json.Unmarshal(payload, &p)
	if p.ActualCash < 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Kassadagi pul manfiy bo'lmaydi"})
		return
	}

	// Ochiq smena bo'lmasa yopish "muvaffaqiyatli" ko'rinib, aslida hech narsa
	// yozilmasdi (shiftID=0) — endi aniq xato qaytadi.
	var openingCash, shiftID int
	var shiftOpenedAt time.Time
	if err := db.Pool.QueryRow(context.Background(),
		"SELECT id, opening_cash, opened_at FROM shifts WHERE status = 'open'").
		Scan(&shiftID, &openingCash, &shiftOpenedAt); err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Ochiq smena yo'q"})
		return
	}

	// Hisobot smena OYNASI bo'yicha (kalendar kuni bo'yicha emas)
	summary, err := CalculateShiftSummarySince(shiftOpenedAt, openingCash, p.ActualCash)
	if err != nil {
		// Hisobot chiqmasa smena YOPILMAYDI — noto'g'ri (nol tushumli)
		// hisobot bazaga abadiy yozilib qolgandan ko'ra shu yaxshi.
		log.Printf("SHIFT: hisobot hisoblanmadi: %v", err)
		H.SendToClient(c, "error", map[string]string{"message": "Smena hisoboti hisoblanmadi — qayta urinib ko'ring"})
		return
	}

	now := time.Now().UTC().Format(time.RFC3339)
	closedBy, _ := json.Marshal(map[string]interface{}{"user_id": c.UserID, "name": c.Name, "role": c.Role})
	summaryJSON, _ := json.Marshal(summary)

	if tag, err := db.Pool.Exec(context.Background(), "UPDATE shifts SET closed_by = $1, closed_at = $2, closing_cash = $3, status = 'closed', summary = $4 WHERE id = $5 AND status = 'open'",
		string(closedBy), now, p.ActualCash, string(summaryJSON), shiftID); err != nil || tag.RowsAffected() == 0 {
		H.SendToClient(c, "error", map[string]string{"message": "Smena yopilmadi — qayta urinib ko'ring"})
		return
	}

	resp := map[string]interface{}{"shift_id": shiftID, "summary": summary}
	H.BroadcastEvent("shift:closed", resp)
	addToSyncQueue("shift:closed", resp)
}

// ============ STOCK HANDLERS ============

// XAVFSIZLIK: bu ikki handlerda ilgari HECH QANDAY ruxsat tekshiruvi yo'q edi.
// WSS'ga ulangan istalgan mijoz — hatto tokensiz QR mehmoni ham — istalgan
// mahsulot qoldig'ini o'zgartira olardi yoki qoldiq qatorini butunlay
// o'chirib, mahsulotni "cheksiz" qilib qo'yardi.
func handleStockSet(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "products", "update") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}
	var p models.StockSetPayload
	if json.Unmarshal(payload, &p) != nil || p.ProductID <= 0 || p.Count < 0 {
		H.SendToClient(c, "error", map[string]string{"message": "product_id va count noto'g'ri"})
		return
	}

	now := time.Now().UTC().Format(time.RFC3339)
	db.Pool.Exec(context.Background(), "INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, $3) ON CONFLICT (product_id) DO UPDATE SET count = $2, updated_at = $3", p.ProductID, p.Count, now)

	broadcastStockUpdate(p.ProductID, "manual_set")
}

func handleStockRemove(c *Client, payload json.RawMessage) {
	if !middleware.HasPermission(c.Token, "products", "update") {
		H.SendToClient(c, "error", map[string]string{"message": "Ruxsat yo'q"})
		return
	}
	var p models.StockRemovePayload
	if json.Unmarshal(payload, &p) != nil || p.ProductID <= 0 {
		H.SendToClient(c, "error", map[string]string{"message": "product_id noto'g'ri"})
		return
	}

	db.Pool.Exec(context.Background(), "DELETE FROM stocks WHERE product_id = $1", p.ProductID)

	BroadcastStock(p.ProductID, nil, "removed")
}

// ============ HELPERS ============

func getProduct(id int) (*models.Product, error) {
	p := &models.Product{}
	err := db.Pool.QueryRow(context.Background(), "SELECT id, name_uz, name_ru, name_tr, description_uz, description_ru, description_tr, category_id, price, old_price, media, status, is_recommended, availability, ingredients, sort_order FROM products WHERE id = $1 AND status = 'active'", id).
		Scan(&p.ID, &p.NameUz, &p.NameRu, &p.NameTr, &p.DescriptionUz, &p.DescriptionRu, &p.DescriptionTr, &p.CategoryID, &p.Price, &p.OldPrice, &p.Media, &p.Status, &p.IsRecommended, &p.Availability, &p.Ingredients, &p.SortOrder)
	return p, err
}

func getOrderByNumber(orderNumber string) (*models.Order, error) {
	o := &models.Order{}
	// created_at/updated_at TIMESTAMPTZ — to'g'ridan-to'g'ri string'ga scan
	// QILINMAYDI (pgx xato beradi). Ilgari shu sabab bu funksiya DOIM xato
	// qaytarardi: WSS orqali chek "topilmadi" bo'lib, stol qulfi ham ishlamasdi.
	var createdAt, updatedAt time.Time
	err := db.Pool.QueryRow(context.Background(), "SELECT id, order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_method, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at FROM orders WHERE order_number = $1", orderNumber).
		Scan(&o.ID, &o.OrderNumber, &o.Type, &o.TableSKU, &o.TableID, &o.ZoneID, &o.Delivery, &o.Items, &o.Subtotal, &o.ServiceFee, &o.DeliveryFee, &o.Discount, &o.Total, &o.PaymentMethod, &o.PaymentStatus, &o.Status, &o.Source, &o.CreatedBy, &o.CustomerName, &o.CustomerPhone, &o.Note, &createdAt, &updatedAt)
	if err != nil {
		return nil, err
	}
	o.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	o.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	return o, nil
}

func getActiveOrderForTable(tableSKU string) (*models.Order, error) {
	return getOrderByTableSKU(tableSKU)
}

func getOrderByTableSKU(tableSKU string) (*models.Order, error) {
	o := &models.Order{}
	var createdAt, updatedAt time.Time
	err := db.Pool.QueryRow(context.Background(), "SELECT id, order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_method, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at FROM orders WHERE table_sku = $1 AND status NOT IN ('completed', 'cancelled') ORDER BY created_at DESC LIMIT 1", tableSKU).
		Scan(&o.ID, &o.OrderNumber, &o.Type, &o.TableSKU, &o.TableID, &o.ZoneID, &o.Delivery, &o.Items, &o.Subtotal, &o.ServiceFee, &o.DeliveryFee, &o.Discount, &o.Total, &o.PaymentMethod, &o.PaymentStatus, &o.Status, &o.Source, &o.CreatedBy, &o.CustomerName, &o.CustomerPhone, &o.Note, &createdAt, &updatedAt)
	if err != nil {
		return nil, err
	}
	o.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	o.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	return o, nil
}

func buildOrderResponse(o *models.Order) map[string]interface{} {
	var items []json.RawMessage
	json.Unmarshal([]byte(o.Items), &items)

	resp := map[string]interface{}{
		"order_number":   o.OrderNumber,
		"type":           o.Type,
		"table_sku":      o.TableSKU,
		"status":         o.Status,
		"items":          items,
		"subtotal":       o.Subtotal,
		"service_fee":    o.ServiceFee,
		"delivery_fee":   o.DeliveryFee,
		"discount":       o.Discount,
		"total":          o.Total,
		"payment_method": o.PaymentMethod,
		"payment_status": o.PaymentStatus,
		"source":         o.Source,
		"note":           o.Note,
		"created_at":     o.CreatedAt,
		"updated_at":     o.UpdatedAt,
	}
	if o.Delivery != nil {
		var del json.RawMessage
		json.Unmarshal([]byte(*o.Delivery), &del)
		resp["delivery"] = del
	}
	if o.CustomerName != nil {
		resp["customer_name"] = *o.CustomerName
	}
	if o.CustomerPhone != nil {
		resp["customer_phone"] = *o.CustomerPhone
	}
	return resp
}

// maxItemQuantity — bitta qatorda ruxsat etilgan eng katta miqdor.
const maxItemQuantity = 999

// validateItemQuantities — chekka kiritilayotgan miqdorlarni tekshiradi.
// Manfiy yoki nol miqdor summani ham, qoldiqni ham buzadi.
func validateItemQuantities(items []models.OrderItemPayload) error {
	for _, it := range items {
		if it.ProductID <= 0 {
			return fmt.Errorf("Mahsulot ID noto'g'ri")
		}
		if it.Quantity <= 0 || it.Quantity > maxItemQuantity {
			return fmt.Errorf("Mahsulot miqdori 1..%d oralig'ida bo'lishi kerak", maxItemQuantity)
		}
	}
	return nil
}

// checkStock — faqat MA'LUMOT uchun (UI xabari). Haqiqiy kafolat
// ReserveStock'da: bu yerdagi SELECT bilan chiqimning orasida boshqa kassa
// sotib ulgurishi mumkin.
func checkStock(productID, quantity int) bool {
	var count int
	err := db.Pool.QueryRow(context.Background(), "SELECT count FROM stocks WHERE product_id = $1", productID).Scan(&count)
	if errors.Is(err, pgx.ErrNoRows) {
		return true // no stock record = unlimited
	}
	if err != nil {
		return true
	}
	return count >= quantity
}

// decreaseStock — qoldiqni kamaytiradi. Stock qatori yo'q = kuzatilmaydigan
// mahsulot (upsert qilinmaydi); count manfiy bo'lishi mumkin — farq ko'rinadi.
func decreaseStock(productID, quantity int) {
	db.Pool.Exec(context.Background(), "UPDATE stocks SET count = count - $1, updated_at = NOW() WHERE product_id = $2", quantity, productID)
}

// ReserveStock — chekdagi hamma mahsulot qoldig'ini BITTA tranzaksiyada,
// atomar kamaytiradi.
//
// NEGA KERAK: ilgari avval `checkStock` (SELECT), keyin `decreaseStock`
// (UPDATE) alohida bajarilardi. Ikki kassa bir vaqtda oxirgi 1 ta taomni
// sotsa, ikkalasi ham tekshiruvdan o'tib qoldiqni -1 ga tushirardi.
// Bu yerda esa qator `FOR UPDATE` bilan qulflanadi va yetmasa BUTUN
// tranzaksiya orqaga qaytadi — yarim yozilgan holat qolmaydi.
//
// Qoldiq qatori yo'q mahsulot — kuzatilmaydi (cheksiz), o'tkazib yuboriladi.
// Qaytaradi: product_id → yangi qoldiq (faqat kuzatiladiganlar uchun).
func ReserveStock(ctx context.Context, items []models.OrderItemPayload) (map[int]int, error) {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	result, err := ReserveStockTx(ctx, tx, items)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return result, nil
}

// ReserveStockTx — ReserveStock ning MAVJUD tranzaksiyada ishlaydigan
// varianti. Chaqiruvchi buyurtmani ham shu tranzaksiyada yozadi, ya'ni
// "qoldiq kamaydi, chek esa saqlanmadi" holati umuman bo'lmaydi.
func ReserveStockTx(ctx context.Context, tx pgx.Tx, items []models.OrderItemPayload) (map[int]int, error) {
	// Deadlock bo'lmasin: qulflar doim product_id o'sish tartibida olinadi.
	need := map[int]int{}
	ids := make([]int, 0, len(items))
	for _, it := range items {
		if _, seen := need[it.ProductID]; !seen {
			ids = append(ids, it.ProductID)
		}
		need[it.ProductID] += it.Quantity
	}
	sort.Ints(ids)

	result := map[int]int{}
	for _, pid := range ids {
		var count int
		err := tx.QueryRow(ctx,
			"SELECT count FROM stocks WHERE product_id = $1 FOR UPDATE", pid).Scan(&count)
		if errors.Is(err, pgx.ErrNoRows) {
			continue // kuzatilmaydigan mahsulot — cheksiz
		}
		if err != nil {
			return nil, err
		}
		if count < need[pid] {
			var name string
			db.Pool.QueryRow(ctx, "SELECT name_uz FROM products WHERE id=$1", pid).Scan(&name)
			if name == "" {
				name = fmt.Sprintf("#%d", pid)
			}
			return nil, fmt.Errorf("%s: faqat %d ta qolgan, %d ta so'raldi", name, count, need[pid])
		}
		newCount := count - need[pid]
		if _, err := tx.Exec(ctx,
			"UPDATE stocks SET count = $1, updated_at = NOW() WHERE product_id = $2",
			newCount, pid); err != nil {
			return nil, err
		}
		result[pid] = newCount
	}
	return result, nil
}

// ReleaseStock — ReserveStock qaytargan miqdorlarni ortga qaytaradi
// (buyurtma saqlanmay qolganda).
func ReleaseStock(ctx context.Context, items []models.OrderItemPayload, reserved map[int]int) {
	for _, it := range items {
		if _, tracked := reserved[it.ProductID]; !tracked {
			continue
		}
		db.Pool.Exec(ctx,
			"UPDATE stocks SET count = count + $1, updated_at = NOW() WHERE product_id = $2",
			it.Quantity, it.ProductID)
	}
}

func broadcastStockUpdate(productID int, reason string) {
	var count *int
	err := db.Pool.QueryRow(context.Background(), "SELECT count FROM stocks WHERE product_id = $1", productID).Scan(&count)
	if err != nil {
		return
	}
	BroadcastStock(productID, count, reason)
}

func buildDescription(p *models.Product) map[string]string {
	desc := map[string]string{}
	if p.DescriptionUz != nil {
		desc["uz"] = *p.DescriptionUz
	}
	if p.DescriptionRu != nil {
		desc["ru"] = *p.DescriptionRu
	}
	if p.DescriptionTr != nil {
		desc["tr"] = *p.DescriptionTr
	}
	return desc
}

var serviceFeePercent = 10

func SetServiceFeePercent(p int) { serviceFeePercent = p }
func getServiceFeePercent() int  { return serviceFeePercent }

// ServiceFeePercent — sozlamadagi xizmat haqi foizi (api paketi ham shundan
// foydalanadi; ilgari bir necha joyda 10% qattiq yozilgan edi).
func ServiceFeePercent() int { return serviceFeePercent }

func buildInitOK(clientMenuVersion int, role string) json.RawMessage {
	ctx := context.Background()

	// Versions
	var menuVersion int
	db.Pool.QueryRow(ctx, "SELECT version FROM menu_version WHERE id = 1").Scan(&menuVersion)
	if role == "guest" {
		data, _ := json.Marshal(map[string]interface{}{
			"versions": map[string]interface{}{"menu": menuVersion},
		})
		return data
	}

	// Tables as map: sku → {status, order_number}
	tablesMap := map[string]interface{}{}
	tRows, _ := db.Pool.Query(ctx, `SELECT t.sku, t.status, o.order_number
		FROM tables t
		LEFT JOIN LATERAL (SELECT order_number FROM orders WHERE table_sku = t.sku AND status NOT IN ('completed','cancelled') LIMIT 1) o ON true`)
	if tRows != nil {
		for tRows.Next() {
			var sku, status string
			var orderNum *string
			tRows.Scan(&sku, &status, &orderNum)
			tablesMap[sku] = map[string]interface{}{"status": status, "order_number": orderNum}
		}
		tRows.Close()
	}

	// Active orders (with items)
	oRows, _ := db.Pool.Query(ctx, "SELECT order_number, type, table_sku, status, items, subtotal, service_fee, total, source, note, created_at FROM orders WHERE status NOT IN ('completed', 'cancelled') ORDER BY created_at")
	orders := []map[string]interface{}{}
	if oRows != nil {
		for oRows.Next() {
			var on, typ, st, source string
			var tsku, note *string
			var items json.RawMessage
			var sub, sf, total int
			var ca time.Time
			oRows.Scan(&on, &typ, &tsku, &st, &items, &sub, &sf, &total, &source, &note, &ca)
			orders = append(orders, map[string]interface{}{
				"order_number": on, "type": typ, "table_sku": tsku, "status": st,
				"items": items, "subtotal": sub, "service_fee": sf, "total": total,
				"source": source, "note": note, "created_at": ca.Format(time.RFC3339),
			})
		}
		oRows.Close()
	}

	// Stocks
	sRows, _ := db.Pool.Query(ctx, "SELECT product_id, count, limit_qty FROM stocks ORDER BY product_id")
	stocks := []map[string]interface{}{}
	if sRows != nil {
		for sRows.Next() {
			var pid, cnt, limitQty int
			sRows.Scan(&pid, &cnt, &limitQty)
			stocks = append(stocks, map[string]interface{}{
				"product_id": pid, "count": cnt, "limit_qty": limitQty,
			})
		}
		sRows.Close()
	}

	// Shift — full stats
	var shiftData interface{}
	var shiftID, shiftOpeningCash int
	var shiftDate, shiftStatus string
	var shiftOpenedBy json.RawMessage
	var shiftOpenedAt time.Time
	err := db.Pool.QueryRow(ctx, "SELECT id, date, opened_by, opened_at, opening_cash, status FROM shifts WHERE status = 'open' LIMIT 1").
		Scan(&shiftID, &shiftDate, &shiftOpenedBy, &shiftOpenedAt, &shiftOpeningCash, &shiftStatus)
	if err == nil {
		// Calculate stats since shift opened
		soa := shiftOpenedAt.Format(time.RFC3339)
		var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, otherRev, expTotal int
		var dineInCount, takeawayCount, deliveryCount, dineInTotal, takeawayTotal, deliveryTotal, activeSD int

		db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", soa).Scan(&totalOrders)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", soa).Scan(&totalRevenue)
		// Usul bo'yicha tushum — split to'lovlar ham o'z bucketlariga qo'shiladi
		payRaw, payErr := db.PaymentTotalsSince(ctx, soa)
		pay := db.PaymentTotalsOrZero(ctx, payRaw, payErr, "init:ok")
		cashRev, cardRev, paymeRev, clickRev, otherRev = pay["cash"], pay["card"], pay["payme"], pay["click"], pay["other"]
		// `date = bugun` sharti olib tashlandi — yarim tundan keyin kechqurungi
		// xarajatlar hisobdan tushib ketardi (qarang: handleGetShift).
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE created_at >= $1", soa).Scan(&expTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'dine_in'", soa).Scan(&dineInCount, &dineInTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'takeaway'", soa).Scan(&takeawayCount, &takeawayTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'delivery'", soa).Scan(&deliveryCount, &deliveryTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')", soa).Scan(&activeSD)

		shiftData = map[string]interface{}{
			"id": shiftID, "date": shiftDate, "status": "open",
			"opened_by": shiftOpenedBy, "opened_at": shiftOpenedAt.Format(time.RFC3339), "opening_cash": shiftOpeningCash,
			"current_stats": map[string]interface{}{
				"total_orders": totalOrders, "total_revenue": totalRevenue,
				"by_payment": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev, "other": otherRev},
				"by_type": map[string]interface{}{
					"dine_in":  map[string]int{"count": dineInCount, "total": dineInTotal},
					"takeaway": map[string]int{"count": takeawayCount, "total": takeawayTotal},
					"delivery": map[string]int{"count": deliveryCount, "total": deliveryTotal},
				},
				"expenses_total": expTotal, "cash_revenue": cashRev,
				"current_expected_cash": shiftOpeningCash + cashRev - expTotal,
				"active_sd_orders":      activeSD,
			},
		}
	} else {
		shiftData = map[string]interface{}{"id": nil, "status": "no_shift"}
	}

	data, _ := json.Marshal(map[string]interface{}{
		"versions": map[string]interface{}{
			"menu":       menuVersion,
			"categories": menuVersion,
			"tables":     1,
		},
		"tables":        tablesMap,
		"active_orders": orders,
		"stocks":        stocks,
		"shift":         shiftData,
	})
	return data
}

func BroadcastShiftStatsExported() { broadcastShiftStats() }
func broadcastShiftStats() {
	ctx := context.Background()
	var shiftOpeningCash int
	var shiftOpenedAt time.Time
	err := db.Pool.QueryRow(ctx, "SELECT opened_at, opening_cash FROM shifts WHERE status = 'open' LIMIT 1").Scan(&shiftOpenedAt, &shiftOpeningCash)
	if err != nil {
		return
	}
	soa := shiftOpenedAt.Format(time.RFC3339)

	var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, otherRev, expTotal int
	var dineInCount, takeawayCount, deliveryCount, dineInTotal, takeawayTotal, deliveryTotal, activeSD int

	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", soa).Scan(&totalOrders)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", soa).Scan(&totalRevenue)
	// Usul bo'yicha tushum — split to'lovlar ham o'z bucketlariga qo'shiladi
	payRaw, payErr := db.PaymentTotalsSince(ctx, soa)
	pay := db.PaymentTotalsOrZero(ctx, payRaw, payErr, "shift:stats")
	cashRev, cardRev, paymeRev, clickRev, otherRev = pay["cash"], pay["card"], pay["payme"], pay["click"], pay["other"]
	// `date = bugun` sharti olib tashlandi — yarim tundan keyin kechqurungi
	// xarajatlar hisobdan tushib ketardi (qarang: handleGetShift).
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE created_at >= $1", soa).Scan(&expTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'dine_in'", soa).Scan(&dineInCount, &dineInTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'takeaway'", soa).Scan(&takeawayCount, &takeawayTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid' AND type = 'delivery'", soa).Scan(&deliveryCount, &deliveryTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')", soa).Scan(&activeSD)

	H.BroadcastEvent("shift:stats", map[string]interface{}{
		"total_orders": totalOrders, "total_revenue": totalRevenue,
		"by_payment": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev, "other": otherRev},
		"by_type": map[string]interface{}{
			"dine_in":  map[string]int{"count": dineInCount, "total": dineInTotal},
			"takeaway": map[string]int{"count": takeawayCount, "total": takeawayTotal},
			"delivery": map[string]int{"count": deliveryCount, "total": deliveryTotal},
		},
		"expenses_total": expTotal, "cash_revenue": cashRev,
		"current_expected_cash": shiftOpeningCash + cashRev - expTotal,
		"active_sd_orders":      activeSD,
		"opening_cash":          shiftOpeningCash,
	})
}

func addToSyncQueue(eventType string, data interface{}) {
	payload, _ := json.Marshal(data)
	db.Pool.Exec(context.Background(), "INSERT INTO sync_queue (event_id, event_type, payload, status, created_at) VALUES ($1, $2, $3, 'pending', NOW())",
		db.NewUUID(), eventType, string(payload))
}

// BroadcastStock — qoldiq o'zgarishining YAGONA e'lon nuqtasi: barcha
// klientlarga (POS, oshxona, sayt) yuboradi VA sync navbatiga qo'yadi.
// Qiymat absolut — replikada (cloud) ham qoldiq to'g'ri bo'ladi; sayt menyusi
// (menu-web) aynan shu qoldiqqa qarab mahsulot ko'rsatadi.
// count nil bo'lsa — mahsulot kuzatuvdan chiqarilgan (qator o'chiriladi).
func BroadcastStock(productID int, count *int, reason string) {
	payload := map[string]interface{}{"product_id": productID, "reason": reason}
	if count == nil {
		payload["count"] = nil
	} else {
		payload["count"] = *count
		var limitQty int
		if err := db.Pool.QueryRow(context.Background(),
			"SELECT limit_qty FROM stocks WHERE product_id = $1", productID).Scan(&limitQty); err == nil {
			payload["limit_qty"] = limitQty
		}
	}
	H.BroadcastEvent("stock:updated", payload)
	addToSyncQueue("stock:updated", payload)
}

// CalculateShiftSummarySince — hisobot AYNAN shu smena oynasi bo'yicha
// (smena ochilgan paytdan hozirgacha). Ilgari kalendar KUNI bo'yicha
// hisoblanardi va ikki xato berardi:
//   - bir kunda ikki smena bo'lsa, kechki smena kunduzgining pulini ham o'ziga
//     olib, kassir yo'q pul uchun javobgar bo'lardi;
//   - smena yarim tundan keyin yopilsa butun kechqurun hisobotdan tushib
//     qolib, soxta "ortiqcha pul" chiqardi.
//
// XATO QAYTARADI — bu hisobot `shifts.summary` ga ABADIY yoziladi. Ilgari
// har qanday baza xatosi jimgina NOL tushum berardi va kassir topshirgan pul
// "kamomad" bo'lib qolardi. Endi xato bo'lsa smena umuman yopilmaydi.
func CalculateShiftSummarySince(since time.Time, openingCash, actualCash int) (map[string]interface{}, error) {
	ctx := context.Background()
	var totalOrders, cancelledOrders int
	if err := db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_status = 'paid'", since).Scan(&totalOrders); err != nil {
		return nil, err
	}
	if err := db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'cancelled'", since).Scan(&cancelledOrders); err != nil {
		return nil, err
	}

	pay, err := db.PaymentTotalsSince(ctx, since)
	if err != nil {
		return nil, err
	}
	cash, card, payme, click, other := pay["cash"], pay["card"], pay["payme"], pay["click"], pay["other"]
	totalRevenue := cash + card + payme + click + other

	// Noma'lum to'lov usuli bilan yopilgan chek bucketlarga tushmaydi va
	// tushumdan jimgina yo'qolardi. Endi u "other" ga yig'iladi va hisobot
	// `SUM(total)` bilan doim mos keladi.
	for method, amount := range pay {
		switch method {
		case "cash", "card", "payme", "click", "other":
		default:
			other += amount
			totalRevenue += amount
			log.Printf("SHIFT: noma'lum to'lov usuli %q — %d so'm 'other' ga qo'shildi", method, amount)
		}
	}

	var expensesTotal int
	if err := db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE created_at >= $1", since).Scan(&expensesTotal); err != nil {
		return nil, err
	}

	expectedCash := openingCash + cash - expensesTotal
	return map[string]interface{}{
		"total_orders":     totalOrders,
		"cancelled_orders": cancelledOrders,
		"revenue": map[string]interface{}{
			"cash": cash, "card": card, "payme": payme, "click": click,
			"other": other, "total": totalRevenue,
		},
		"expenses_total":  expensesTotal,
		"opening_cash":    openingCash,
		"expected_cash":   expectedCash,
		"actual_cash":     actualCash,
		"cash_difference": actualCash - expectedCash,
	}, nil
}
