package wss

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/models"
	"konak-local/internal/printer"
)

// HandleEvent routes incoming WSS events to handlers
func HandleEvent(c *Client, event *models.WSEvent) {
	switch event.Event {
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

func handleTableEnter(c *Client, payload json.RawMessage) {
	var p struct {
		TableSKU string `json:"table_sku"`
	}
	json.Unmarshal(payload, &p)

	// Check if table is locked by someone else
	var lock models.TableLock
	err := db.Pool.QueryRow(context.Background(), "SELECT table_sku, user_id, name, role, source, locked_at FROM table_locks WHERE table_sku = $1", p.TableSKU).
		Scan(&lock.TableSKU, &lock.UserID, &lock.Name, &lock.Role, &lock.Source, &lock.LockedAt)

	if err == nil && lock.UserID != c.UserID {
		H.SendToClient(c, "table:locked", map[string]interface{}{
			"table_sku": p.TableSKU,
			"locked_by": map[string]interface{}{
				"user_id": lock.UserID, "name": lock.Name, "role": lock.Role, "source": lock.Source,
			},
			"locked_at": lock.LockedAt,
		})
		return
	}

	// Lock the table
	now := time.Now().UTC().Format(time.RFC3339)
	db.Pool.Exec(context.Background(), "INSERT INTO table_locks (table_sku, user_id, name, role, source, locked_at) VALUES ($1, $2, $3, $4, $5, $6)",
		p.TableSKU, c.UserID, c.Name, c.Role, c.Source, now)
	c.LockedTable = p.TableSKU

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
	if c.LockedTable == "" {
		return
	}
	tableSKU := c.LockedTable
	UnlockTable(tableSKU)
	c.LockedTable = ""

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

	// Generate order number
	orderNumber := generateOrderNumber()

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
	if p.TableSKU != nil {
		var tid, zid int
		db.Pool.QueryRow(context.Background(), "SELECT id, zone_id FROM tables WHERE sku = $1", *p.TableSKU).Scan(&tid, &zid)
		tableID = &tid
		zoneID = &zid
	}

	_, err = db.Pool.Exec(context.Background(), `INSERT INTO orders (order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 0, $11, 'unpaid', 'new', $12, $13, $14, $15, $16, $17, $18)`,
		orderNumber, p.Type, p.TableSKU, tableID, zoneID, deliveryJSON, string(itemsJSON),
		subtotal, serviceFee, 0, total, c.Source, c.UserID, p.CustomerName, p.CustomerPhone, p.Note, now, now)
	if err != nil {
		log.Printf("Order create error: %v", err)
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma yaratishda xato"})
		return
	}

	// Update table status
	if p.TableSKU != nil && p.Type == "dine_in" {
		db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", *p.TableSKU)
	}

	// Decrease stock
	for _, item := range p.Items {
		decreaseStock(item.ProductID, item.Quantity)
	}

	// Build full order response
	order, _ := getOrderByNumber(orderNumber)
	orderResp := buildOrderResponse(order)

	// Broadcast
	H.BroadcastEvent("order:new", map[string]interface{}{"order": orderResp})

	// Stock updates
	for _, item := range p.Items {
		broadcastStockUpdate(item.ProductID, "sold")
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

	order, err := getOrderByNumber(p.OrderNumber)
	if err != nil {
		H.SendToClient(c, "error", map[string]string{"message": "Buyurtma topilmadi"})
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

	allItemsJSON, _ := json.Marshal(existingItems)
	db.Pool.Exec(context.Background(), "UPDATE orders SET items = $1, subtotal = $2, service_fee = $3, total = $4, updated_at = $5 WHERE order_number = $6",
		string(allItemsJSON), newSubtotal, newServiceFee, newTotal, now, p.OrderNumber)

	for _, item := range p.Items {
		decreaseStock(item.ProductID, item.Quantity)
	}

	resp := map[string]interface{}{
		"order_number": p.OrderNumber,
		"new_items":    newItems,
		"new_subtotal": newSubtotal,
		"new_total":    newTotal,
	}
	H.BroadcastEvent("order:items_added", resp)

	for _, item := range p.Items {
		broadcastStockUpdate(item.ProductID, "sold")
	}

	// Print added items
	tableSKU := ""
	if order.TableSKU != nil { tableSKU = *order.TableSKU }
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

	now := time.Now().UTC().Format(time.RFC3339)
	db.Pool.Exec(context.Background(), "UPDATE orders SET status = $1, updated_at = $2 WHERE order_number = $3", p.Status, now, p.OrderNumber)

	resp := map[string]interface{}{
		"order_number": p.OrderNumber,
		"status":       p.Status,
		"updated_at":   now,
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

	newTotal := order.Total - p.Discount
	if newTotal < 0 {
		newTotal = 0
	}
	now := time.Now().UTC().Format(time.RFC3339)

	db.Pool.Exec(context.Background(), "UPDATE orders SET payment_method = $1, payment_status = 'paid', status = 'completed', discount = $2, total = $3, updated_at = $4 WHERE order_number = $5",
		p.PaymentMethod, p.Discount, newTotal, now, p.OrderNumber)

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
		"payment_method": p.PaymentMethod,
	}
	H.BroadcastEvent("order:closed", resp)
	addToSyncQueue("order:closed", resp)

	log.Printf("Order closed: %s payment=%s total=%d", p.OrderNumber, p.PaymentMethod, newTotal)
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

	// Update order
	db.Pool.Exec(context.Background(), "UPDATE orders SET table_sku = $1, table_id = $2, zone_id = $3, updated_at = $4 WHERE order_number = $5",
		p.ToTableSKU, toTableID, toZoneID, now, p.OrderNumber)

	// Free old table, occupy new
	db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'free' WHERE sku = $1", p.FromTableSKU)
	db.Pool.Exec(context.Background(), "UPDATE tables SET status = 'occupied' WHERE sku = $1", p.ToTableSKU)

	// Transfer lock
	UnlockTable(p.FromTableSKU)
	db.Pool.Exec(context.Background(), "INSERT INTO table_locks (table_sku, user_id, name, role, source, locked_at) VALUES ($1, $2, $3, $4, $5, $6)",
		p.ToTableSKU, c.UserID, c.Name, c.Role, c.Source, now)
	c.LockedTable = p.ToTableSKU

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

	now := time.Now().UTC()
	openedBy, _ := json.Marshal(map[string]interface{}{"user_id": c.UserID, "name": c.Name, "role": c.Role})

	var shiftID int64
	db.Pool.QueryRow(context.Background(), "INSERT INTO shifts (date, opened_by, opened_at, opening_cash, status) VALUES ($1, $2, $3, $4, 'open') RETURNING id",
		now.Format("2006-01-02"), string(openedBy), now.Format(time.RFC3339), p.OpeningCash).Scan(&shiftID)

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
	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed', 'cancelled') AND created_at::date = CURRENT_DATE").Scan(&activeCount)
	if activeCount > 0 {
		H.SendToClient(c, "error", map[string]interface{}{
			"error": "active_orders_exist", "message": fmt.Sprintf("%d ta yopilmagan buyurtma bor", activeCount), "active_orders_count": activeCount,
		})
		return
	}

	var p models.ShiftCloseRequest
	json.Unmarshal(payload, &p)

	// Calculate summary
	today := time.Now().UTC().Format("2006-01-02")
	var openingCash int
	var shiftID int
	db.Pool.QueryRow(context.Background(), "SELECT id, opening_cash FROM shifts WHERE status = 'open'").Scan(&shiftID, &openingCash)

	summary := calculateShiftSummary(today, openingCash, p.ActualCash)

	now := time.Now().UTC().Format(time.RFC3339)
	closedBy, _ := json.Marshal(map[string]interface{}{"user_id": c.UserID, "name": c.Name, "role": c.Role})
	summaryJSON, _ := json.Marshal(summary)

	db.Pool.Exec(context.Background(), "UPDATE shifts SET closed_by = $1, closed_at = $2, closing_cash = $3, status = 'closed', summary = $4 WHERE id = $5",
		string(closedBy), now, p.ActualCash, string(summaryJSON), shiftID)

	resp := map[string]interface{}{"shift_id": shiftID, "summary": summary}
	H.BroadcastEvent("shift:closed", resp)
	addToSyncQueue("shift:closed", resp)
}

// ============ STOCK HANDLERS ============

func handleStockSet(c *Client, payload json.RawMessage) {
	var p models.StockSetPayload
	json.Unmarshal(payload, &p)

	now := time.Now().UTC().Format(time.RFC3339)
	db.Pool.Exec(context.Background(), "INSERT INTO stocks (product_id, count, updated_at) VALUES ($1, $2, $3)", p.ProductID, p.Count, now)

	broadcastStockUpdate(p.ProductID, "manual_set")
	addToSyncQueue("stock:updated", map[string]interface{}{"product_id": p.ProductID, "count": p.Count})
}

func handleStockRemove(c *Client, payload json.RawMessage) {
	var p models.StockRemovePayload
	json.Unmarshal(payload, &p)

	db.Pool.Exec(context.Background(), "DELETE FROM stocks WHERE product_id = $1", p.ProductID)

	H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": p.ProductID, "count": nil, "reason": "removed"})
	addToSyncQueue("stock:updated", map[string]interface{}{"product_id": p.ProductID, "count": nil, "reason": "removed"})
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
	err := db.Pool.QueryRow(context.Background(), "SELECT id, order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_method, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at FROM orders WHERE order_number = $1", orderNumber).
		Scan(&o.ID, &o.OrderNumber, &o.Type, &o.TableSKU, &o.TableID, &o.ZoneID, &o.Delivery, &o.Items, &o.Subtotal, &o.ServiceFee, &o.DeliveryFee, &o.Discount, &o.Total, &o.PaymentMethod, &o.PaymentStatus, &o.Status, &o.Source, &o.CreatedBy, &o.CustomerName, &o.CustomerPhone, &o.Note, &o.CreatedAt, &o.UpdatedAt)
	return o, err
}

func getActiveOrderForTable(tableSKU string) (*models.Order, error) {
	return getOrderByTableSKU(tableSKU)
}

func getOrderByTableSKU(tableSKU string) (*models.Order, error) {
	o := &models.Order{}
	err := db.Pool.QueryRow(context.Background(), "SELECT id, order_number, type, table_sku, table_id, zone_id, delivery, items, subtotal, service_fee, delivery_fee, discount, total, payment_method, payment_status, status, source, created_by, customer_name, customer_phone, note, created_at, updated_at FROM orders WHERE table_sku = $1 AND status NOT IN ('completed', 'cancelled') ORDER BY created_at DESC LIMIT 1", tableSKU).
		Scan(&o.ID, &o.OrderNumber, &o.Type, &o.TableSKU, &o.TableID, &o.ZoneID, &o.Delivery, &o.Items, &o.Subtotal, &o.ServiceFee, &o.DeliveryFee, &o.Discount, &o.Total, &o.PaymentMethod, &o.PaymentStatus, &o.Status, &o.Source, &o.CreatedBy, &o.CustomerName, &o.CustomerPhone, &o.Note, &o.CreatedAt, &o.UpdatedAt)
	return o, err
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

func generateOrderNumber() string {
	now := time.Now()
	datePrefix := now.Format("06-01-02")

	var totalToday int
	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM orders WHERE created_at::date = CURRENT_DATE").Scan(&totalToday)
	return fmt.Sprintf("%s-%d", datePrefix, totalToday+1)
}

func checkStock(productID, quantity int) bool {
	var count int
	err := db.Pool.QueryRow(context.Background(), "SELECT count FROM stocks WHERE product_id = $1", productID).Scan(&count)
	if err == sql.ErrNoRows {
		return true // no stock record = unlimited
	}
	if err != nil {
		return true
	}
	return count >= quantity
}

func decreaseStock(productID, quantity int) {
	db.Pool.Exec(context.Background(), "UPDATE stocks SET count = count - $1, updated_at = NOW() WHERE product_id = $2 AND count >= $3", quantity, productID, quantity)
}

func broadcastStockUpdate(productID int, reason string) {
	var count *int
	err := db.Pool.QueryRow(context.Background(), "SELECT count FROM stocks WHERE product_id = $1", productID).Scan(&count)
	if err != nil {
		return
	}
	H.BroadcastEvent("stock:updated", map[string]interface{}{"product_id": productID, "count": count, "reason": reason})
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

func buildInitOK(clientMenuVersion int) json.RawMessage {
	ctx := context.Background()

	// Versions
	var menuVersion int
	db.Pool.QueryRow(ctx, "SELECT version FROM menu_version WHERE id = 1").Scan(&menuVersion)

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
	sRows, _ := db.Pool.Query(ctx, "SELECT product_id, count FROM stocks")
	stocks := []map[string]interface{}{}
	if sRows != nil {
		for sRows.Next() {
			var pid, cnt int
			sRows.Scan(&pid, &cnt)
			stocks = append(stocks, map[string]interface{}{"product_id": pid, "count": cnt})
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
		today := time.Now().Format("2006-01-02")
		var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, otherRev, expTotal int
		var dineInCount, takeawayCount, deliveryCount, dineInTotal, takeawayTotal, deliveryTotal, activeSD int

		db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed'", soa).Scan(&totalOrders)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed'", soa).Scan(&totalRevenue)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'cash'", soa).Scan(&cashRev)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'card'", soa).Scan(&cardRev)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'payme'", soa).Scan(&paymeRev)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'click'", soa).Scan(&clickRev)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'other'", soa).Scan(&otherRev)
		db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date = $1 AND created_at >= $2", today, soa).Scan(&expTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'dine_in'", soa).Scan(&dineInCount, &dineInTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'takeaway'", soa).Scan(&takeawayCount, &takeawayTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'delivery'", soa).Scan(&deliveryCount, &deliveryTotal)
		db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')", soa).Scan(&activeSD)

		shiftData = map[string]interface{}{
			"id": shiftID, "date": shiftDate, "status": "open",
			"opened_by": shiftOpenedBy, "opened_at": shiftOpenedAt.Format(time.RFC3339), "opening_cash": shiftOpeningCash,
			"current_stats": map[string]interface{}{
				"total_orders": totalOrders, "total_revenue": totalRevenue,
				"by_payment": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev, "other": otherRev},
				"by_type": map[string]interface{}{
					"dine_in": map[string]int{"count": dineInCount, "total": dineInTotal},
					"takeaway": map[string]int{"count": takeawayCount, "total": takeawayTotal},
					"delivery": map[string]int{"count": deliveryCount, "total": deliveryTotal},
				},
				"expenses_total": expTotal, "cash_revenue": cashRev,
				"current_expected_cash": shiftOpeningCash + cashRev - expTotal,
				"active_sd_orders": activeSD,
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
	today := time.Now().Format("2006-01-02")

	var totalOrders, totalRevenue, cashRev, cardRev, paymeRev, clickRev, otherRev, expTotal int
	var dineInCount, takeawayCount, deliveryCount, dineInTotal, takeawayTotal, deliveryTotal, activeSD int

	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status = 'completed'", soa).Scan(&totalOrders)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed'", soa).Scan(&totalRevenue)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'cash'", soa).Scan(&cashRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'card'", soa).Scan(&cardRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'payme'", soa).Scan(&paymeRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'click'", soa).Scan(&clickRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND payment_method = 'other'", soa).Scan(&otherRev)
	db.Pool.QueryRow(ctx, "SELECT COALESCE(SUM(amount),0) FROM expenses WHERE date = $1 AND created_at >= $2", today, soa).Scan(&expTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'dine_in'", soa).Scan(&dineInCount, &dineInTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'takeaway'", soa).Scan(&takeawayCount, &takeawayTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*), COALESCE(SUM(total),0) FROM orders WHERE created_at >= $1 AND status = 'completed' AND type = 'delivery'", soa).Scan(&deliveryCount, &deliveryTotal)
	db.Pool.QueryRow(ctx, "SELECT COUNT(*) FROM orders WHERE created_at >= $1 AND status NOT IN ('completed','cancelled') AND type IN ('takeaway','delivery')", soa).Scan(&activeSD)

	H.BroadcastEvent("shift:stats", map[string]interface{}{
		"total_orders": totalOrders, "total_revenue": totalRevenue,
		"by_payment": map[string]int{"cash": cashRev, "card": cardRev, "payme": paymeRev, "click": clickRev, "other": otherRev},
		"by_type": map[string]interface{}{
			"dine_in": map[string]int{"count": dineInCount, "total": dineInTotal},
			"takeaway": map[string]int{"count": takeawayCount, "total": takeawayTotal},
			"delivery": map[string]int{"count": deliveryCount, "total": deliveryTotal},
		},
		"expenses_total": expTotal, "cash_revenue": cashRev,
		"current_expected_cash": shiftOpeningCash + cashRev - expTotal,
		"active_sd_orders": activeSD,
		"opening_cash": shiftOpeningCash,
	})
}

func addToSyncQueue(eventType string, data interface{}) {
	payload, _ := json.Marshal(data)
	db.Pool.Exec(context.Background(), "INSERT INTO sync_queue (event_type, payload, status, created_at) VALUES ($1, $2, 'pending', NOW())",
		eventType, string(payload))
}

func CalculateShiftSummaryExported(date string, openingCash, actualCash int) map[string]interface{} {
	return calculateShiftSummary(date, openingCash, actualCash)
}

func calculateShiftSummary(date string, openingCash, actualCash int) map[string]interface{} {
	var totalOrders, cancelledOrders int
	var cashRevenue, cardRevenue, paymeRevenue, clickRevenue, otherRevenue int

	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'completed'", date).Scan(&totalOrders)
	db.Pool.QueryRow(context.Background(), "SELECT COUNT(*) FROM orders WHERE created_at::date = $1 AND status = 'cancelled'", date).Scan(&cancelledOrders)
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_method = 'cash'", date).Scan(&cashRevenue)
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_method = 'card'", date).Scan(&cardRevenue)
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_method = 'payme'", date).Scan(&paymeRevenue)
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_method = 'click'", date).Scan(&clickRevenue)
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(total), 0) FROM orders WHERE created_at::date = $1 AND status = 'completed' AND payment_method = 'other'", date).Scan(&otherRevenue)

	totalRevenue := cashRevenue + cardRevenue + paymeRevenue + clickRevenue + otherRevenue

	var expensesTotal int
	db.Pool.QueryRow(context.Background(), "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE date = $1", date).Scan(&expensesTotal)

	expectedCash := openingCash + cashRevenue - expensesTotal

	return map[string]interface{}{
		"total_orders":     totalOrders,
		"cancelled_orders": cancelledOrders,
		"revenue": map[string]interface{}{
			"cash": cashRevenue, "card": cardRevenue, "payme": paymeRevenue, "click": clickRevenue, "other": otherRevenue, "total": totalRevenue,
		},
		"expenses_total": expensesTotal,
		"opening_cash":   openingCash,
		"expected_cash":  expectedCash,
		"actual_cash":    actualCash,
		"cash_difference": actualCash - expectedCash,
	}
}
