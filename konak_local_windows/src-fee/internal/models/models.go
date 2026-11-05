package models

import (
	"encoding/json"
	"fmt"
)

// PrinterStation represents a receipt printer
type PrinterStation struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Address   string `json:"address"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
}

// Category represents a product category
type Category struct {
	ID               int    `json:"id"`
	NameUz           string `json:"name_uz,omitempty"`
	NameRu           string `json:"name_ru,omitempty"`
	NameTr           string `json:"name_tr,omitempty"`
	Icon             string `json:"icon"`
	SortOrder        int    `json:"sort_order"`
	Status           string `json:"status"`
	PrinterStationID *int   `json:"printer_station_id"`
	CreatedAt        string `json:"created_at"`
}

func (c Category) Name() map[string]string {
	return map[string]string{"uz": c.NameUz, "ru": c.NameRu, "tr": c.NameTr}
}

// CategoryJSON is the API response format
type CategoryJSON struct {
	ID               int               `json:"id"`
	Name             map[string]string `json:"name"`
	Icon             string            `json:"icon"`
	SortOrder        int               `json:"sort_order"`
	Status           string            `json:"status"`
	PrinterStationID *int              `json:"printer_station_id"`
}

// Product represents a menu product
type Product struct {
	ID               int     `json:"id"`
	NameUz           string  `json:"name_uz,omitempty"`
	NameRu           string  `json:"name_ru,omitempty"`
	NameTr           string  `json:"name_tr,omitempty"`
	DescriptionUz    *string `json:"description_uz,omitempty"`
	DescriptionRu    *string `json:"description_ru,omitempty"`
	DescriptionTr    *string `json:"description_tr,omitempty"`
	CategoryID       int     `json:"category_id"`
	Price            int     `json:"price"`
	OldPrice         *int    `json:"old_price"`
	Media            string  `json:"media"`
	Status           string  `json:"status"`
	IsRecommended    bool    `json:"is_recommended"`
	Availability     *string `json:"availability"`
	Ingredients      *string `json:"ingredients"`
	SortOrder        int     `json:"sort_order"`
	PrinterStationID *int    `json:"printer_station_id"`
	ProductType      string  `json:"product_type"` // cooked | ready
	CreatedAt        string  `json:"created_at"`
	UpdatedAt        string  `json:"updated_at"`
}

// ProductJSON is the API response format
type ProductJSON struct {
	ID               int               `json:"id"`
	Name             map[string]string `json:"name"`
	SortOrder        int               `json:"sort_order"`
	Description      map[string]string `json:"description"`
	CategoryID       int               `json:"category_id"`
	Price            int               `json:"price"`
	OldPrice         *int              `json:"old_price"`
	Media            json.RawMessage   `json:"media"`
	Status           string            `json:"status"`
	IsRecommended    bool              `json:"is_recommended"`
	Availability     json.RawMessage   `json:"availability"`
	Ingredients      json.RawMessage   `json:"ingredients"`
	PrinterStationID *int              `json:"printer_station_id"`
	ProductType      string            `json:"product_type"` // cooked | ready
}

// Zone represents a table zone
type Zone struct {
	ID        int    `json:"id"`
	Name      string `json:"name"`
	Count     int    `json:"count"`
	SortOrder int    `json:"sort_order"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
}

// Table represents a restaurant table
type Table struct {
	ID        int    `json:"id"`
	ZoneID    int    `json:"zone_id"`
	SKU       string `json:"sku"`
	Number    int    `json:"number"`
	Label     string `json:"label"`
	Seats     int    `json:"seats"`
	Status    string `json:"status"`
	QRCode    string `json:"qr_code"`
	CreatedAt string `json:"created_at"`
}

// TableLock represents an active table lock
type TableLock struct {
	TableSKU string `json:"table_sku"`
	UserID   int    `json:"user_id"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Source   string `json:"source"`
	LockedAt string `json:"locked_at"`
}

// Order represents an order
type Order struct {
	ID            int     `json:"id"`
	OrderNumber   string  `json:"order_number"`
	Type          string  `json:"type"`
	TableSKU      *string `json:"table_sku"`
	TableID       *int    `json:"table_id"`
	ZoneID        *int    `json:"zone_id"`
	Delivery      *string `json:"delivery"`
	Items         string  `json:"items"`
	Subtotal      int     `json:"subtotal"`
	ServiceFee    int     `json:"service_fee"`
	DeliveryFee   int     `json:"delivery_fee"`
	Discount      int     `json:"discount"`
	Total         int     `json:"total"`
	PaymentMethod *string `json:"payment_method"`
	PaymentStatus string  `json:"payment_status"`
	Status        string  `json:"status"`
	Source        string  `json:"source"`
	CreatedBy     *int    `json:"created_by"`
	CustomerName  *string `json:"customer_name"`
	CustomerPhone *string `json:"customer_phone"`
	Note          *string `json:"note"`
	CreatedAt     string  `json:"created_at"`
	UpdatedAt     string  `json:"updated_at"`
}

// OrderItem represents a single item in an order
type OrderItem struct {
	ID        int             `json:"id"`
	ProductID int             `json:"product_id"`
	Snapshot  json.RawMessage `json:"snapshot"`
	Quantity  int             `json:"quantity"`
	Price     int             `json:"price"`
	Total     int             `json:"total"`
	Note      *string         `json:"note"`
	AddedBy   json.RawMessage `json:"added_by"`
	AddedAt   string          `json:"added_at"`
}

// AddedBy represents who added an item
type AddedBy struct {
	Type   string `json:"type"`
	Name   string `json:"name"`
	UserID *int   `json:"user_id"`
}

// ProductSnapshot is the frozen product data at order time
type ProductSnapshot struct {
	Name        map[string]string `json:"name"`
	Description map[string]string `json:"description"`
	Price       int               `json:"price"`
	CategoryID  int               `json:"category_id"`
	Media       json.RawMessage   `json:"media"`
}

// Stock represents product inventory
type Stock struct {
	ProductID int    `json:"product_id"`
	Count     int    `json:"count"`
	LimitQty  int    `json:"limit_qty"`
	UpdatedAt string `json:"updated_at"`
}

// User represents a staff member
type User struct {
	ID                int     `json:"id"`
	Name              string  `json:"name"`
	Phone             string  `json:"phone"`
	Role              string  `json:"role"`
	PIN               string  `json:"-"`
	CustomPermissions *string `json:"custom_permissions"`
	Status            string  `json:"status"`
	CreatedAt         string  `json:"created_at"`
}

// Shift represents a cash register shift
type Shift struct {
	ID          int     `json:"id"`
	Date        string  `json:"date"`
	OpenedBy    string  `json:"opened_by"`
	OpenedAt    string  `json:"opened_at"`
	OpeningCash int     `json:"opening_cash"`
	ClosedBy    *string `json:"closed_by"`
	ClosedAt    *string `json:"closed_at"`
	ClosingCash *int    `json:"closing_cash"`
	Status      string  `json:"status"`
	Summary     *string `json:"summary"`
}

// Expense represents an expense record
type Expense struct {
	ID         int    `json:"id"`
	CategoryID int    `json:"category_id"`
	Amount     int    `json:"amount"`
	Desc       string `json:"description"`
	Date       string `json:"date"`
	CreatedBy  string `json:"created_by"`
	CreatedAt  string `json:"created_at"`
}

// ExpenseCategory represents an expense category
type ExpenseCategory struct {
	ID        int    `json:"id"`
	NameUz    string `json:"name_uz,omitempty"`
	NameRu    string `json:"name_ru,omitempty"`
	NameTr    string `json:"name_tr,omitempty"`
	SortOrder int    `json:"sort_order"`
	Status    string `json:"status"`
	CreatedBy *int   `json:"created_by"`
	CreatedAt string `json:"created_at"`
}

// SyncQueueItem represents a pending sync event
type SyncQueueItem struct {
	ID         int     `json:"id"`
	EventType  string  `json:"event_type"`
	Payload    string  `json:"payload"`
	Status     string  `json:"status"`
	CreatedAt  string  `json:"created_at"`
	SyncedAt   *string `json:"synced_at"`
	RetryCount int     `json:"retry_count"`
}

// WSS Event types
type WSEvent struct {
	Event   string          `json:"event"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Auth
type LoginRequest struct {
	Phone string `json:"phone"`
	PIN   string `json:"pin"`
}

type PinLoginRequest struct {
	PIN string `json:"pin"`
}

type LoginResponse struct {
	Token string   `json:"token"`
	User  UserInfo `json:"user"`
}

type UserInfo struct {
	ID          int             `json:"id"`
	Name        string          `json:"name"`
	Role        string          `json:"role"`
	Permissions json.RawMessage `json:"permissions"`
}

// Shift requests
type ShiftOpenRequest struct {
	OpeningCash int `json:"opening_cash"`
}

type ShiftCloseRequest struct {
	ActualCash int `json:"actual_cash"`
}

// Expense request
type ExpenseCreateRequest struct {
	CategoryID  int    `json:"category_id"`
	Amount      int    `json:"amount"`
	Description string `json:"description"`
}

// Order create via WSS
type OrderCreatePayload struct {
	Type          string             `json:"type"`
	TableSKU      *string            `json:"table_sku"`
	Items         []OrderItemPayload `json:"items"`
	Delivery      json.RawMessage    `json:"delivery"`
	CustomerName  *string            `json:"customer_name"`
	CustomerPhone *string            `json:"customer_phone"`
	Note          *string            `json:"note"`
}

type OrderItemPayload struct {
	ProductID int     `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Note      *string `json:"note"`
}

type OrderAddItemsPayload struct {
	OrderNumber string             `json:"order_number"`
	Items       []OrderItemPayload `json:"items"`
}

type OrderUpdateStatusPayload struct {
	OrderNumber string `json:"order_number"`
	Status      string `json:"status"`
}

type OrderClosePayload struct {
	OrderNumber   string        `json:"order_number"`
	PaymentMethod string        `json:"payment_method"`
	Discount      int           `json:"discount"`
	Payments      []PaymentPart `json:"payments"`
}

// PaymentPart — aralash to'lovda (split) bitta usulning ulushi. Pul — butun so'm.
type PaymentPart struct {
	Method string `json:"method"`
	Amount int    `json:"amount"`
}

var validPaymentMethods = map[string]bool{
	"cash": true, "card": true, "payme": true, "click": true, "other": true,
}

// ValidPaymentMethod — chek yopishda kelgan to'lov usuli hisobotdagi
// bucketlardan biriga tushishi SHART.
//
// NEGA: `orders.payment_method` — oddiy TEXT, hech qanday CHECK yo'q.
// Noma'lum satr (yoki bo'sh qiymat) yozilsa chek "to'langan" bo'ladi va
// `SUM(total)` ga kiradi, lekin `by_payment` bucketlariga tushmaydi —
// ya'ni pul kutilayotgan naqd hisobidan chiqib ketadi va kassir tunda
// kam/ortiqcha bo'lib qoladi.
func ValidPaymentMethod(method string) bool {
	return validPaymentMethods[method]
}

// ValidatePayments — aralash to'lov taqsimotini tekshiradi:
// 2..3 element, usullar {cash,card,payme,click,other} ichida va takrorlanmaydi,
// har amount > 0, SUM(amount) == newTotal.
// Xato bo'lsa (errCode, message), hammasi joyida bo'lsa ("", "") qaytaradi.
func ValidatePayments(parts []PaymentPart, newTotal int) (string, string) {
	if len(parts) < 2 || len(parts) > 3 {
		return "payments_invalid", "Aralash to'lov 2 yoki 3 usuldan iborat bo'lishi kerak"
	}
	seen := map[string]bool{}
	sum := 0
	for _, p := range parts {
		if !validPaymentMethods[p.Method] {
			return "payments_invalid", "Noto'g'ri to'lov usuli: " + p.Method
		}
		if seen[p.Method] {
			return "payments_invalid", "To'lov usuli takrorlangan: " + p.Method
		}
		seen[p.Method] = true
		if p.Amount <= 0 {
			return "payments_invalid", "Har bir to'lov summasi 0 dan katta bo'lishi kerak"
		}
		sum += p.Amount
	}
	if sum != newTotal {
		return "payments_mismatch", fmt.Sprintf("To'lovlar yig'indisi jami summaga teng emas (jami: %d)", newTotal)
	}
	return "", ""
}

type OrderTransferPayload struct {
	OrderNumber  string `json:"order_number"`
	FromTableSKU string `json:"from_table_sku"`
	ToTableSKU   string `json:"to_table_sku"`
}

type StockSetPayload struct {
	ProductID int `json:"product_id"`
	Count     int `json:"count"`
}

type StockRemovePayload struct {
	ProductID int `json:"product_id"`
}
