package wss

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"konak-local/internal/models"
)

// Hub manages all WebSocket connections
type Hub struct {
	clients    map[*Client]bool
	register   chan *Client
	unregister chan *Client
	broadcast  chan broadcastMessage
	mu         sync.RWMutex
}

type broadcastMessage struct {
	data     []byte
	event    string
	tableSKU string
}

var H *Hub

func NewHub() *Hub {
	H = &Hub{
		clients:    make(map[*Client]bool),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		broadcast:  make(chan broadcastMessage, 512),
	}
	return H
}

func (h *Hub) Run() {
	pingTicker := time.NewTicker(3 * time.Second)
	defer pingTicker.Stop()

	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("WSS: client connected [%s] role=%s, total=%d", client.Source, client.Role, len(h.clients))

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.Send)
			}
			h.mu.Unlock()
			log.Printf("WSS: client disconnected [%s] role=%s, total=%d", client.Source, client.Role, len(h.clients))
			// ALOHIDA goroutine'da. `handleClientDisconnect` bazaga yozadi
			// (stol qulfini o'chiradi). Ilgari u SHU yerda, Hub'ning yagona
			// siklida bajarilardi: bitta sekin DELETE butun realtime qatlamni
			// muzlatib qo'yardi — hech kimga xabar bormasdi va yangi
			// ulanishlar ham `register` da qotib qolardi.
			go handleClientDisconnect(client)

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				if client.Role == "guest" &&
					!guestCanReceive(client, message.event, message.tableSKU) {
					continue
				}
				select {
				case client.Send <- message.data:
				default:
					// Klient javob bermayapti (buferi to'ldi). Ilgari bu yerda
					// close(Send) + delete(map) bo'lgan: RLock ostida map'ga
					// yozish Go'ning FATAL "concurrent map iteration and map
					// write" xatosini berib serverni o'ldirardi, yopilgan
					// kanalga yozish esa panic berardi. Endi faqat ulanishni
					// yopamiz — readPump chiqadi, unregister esa map'ni va
					// kanalni to'liq Lock ostida bir marta tozalaydi.
					client.Conn.Close()
				}
			}
			h.mu.RUnlock()

		case <-pingTicker.C:
			h.sendPing()
		}
	}
}

func (h *Hub) sendPing() {
	msg, _ := json.Marshal(models.WSEvent{
		Event:   "ping",
		Payload: json.RawMessage(`{"timestamp":"` + time.Now().UTC().Format(time.RFC3339) + `"}`),
	})
	h.mu.RLock()
	for client := range h.clients {
		safeSend(client, msg)
	}
	h.mu.RUnlock()
}

// BroadcastEvent sends an event to all clients
func (h *Hub) BroadcastEvent(event string, payload interface{}) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})
	h.broadcast <- broadcastMessage{
		data: msg, event: event, tableSKU: payloadTableSKU(payload),
	}
}

func guestCanReceive(client *Client, event, tableSKU string) bool {
	switch event {
	case "stock:updated", "menu:outdated":
		return true
	}
	return tableSKU != "" && client.subscribedTableSKU() == tableSKU
}

func payloadTableSKU(payload interface{}) string {
	root, ok := payload.(map[string]interface{})
	if !ok {
		return ""
	}
	if value, ok := root["table_sku"].(string); ok {
		return value
	}
	if nested, ok := root["order"].(map[string]interface{}); ok {
		if value, ok := nested["table_sku"].(string); ok {
			return value
		}
	}
	return ""
}

// SendToRoles sends an event to clients with specific roles
func (h *Hub) SendToRoles(event string, payload interface{}, roles ...string) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})

	roleSet := make(map[string]bool)
	for _, r := range roles {
		roleSet[r] = true
	}

	// FAQAT `Role` bo'yicha. Ilgari `client.Source` ham tekshirilardi, lekin
	// `Source` init xabarida KLIENT tomonidan yuboriladi va hech qayerda
	// tasdiqlanmaydi. Ya'ni tokensiz QR mehmoni `source:"admin"` deb
	// ulanib, xodimlarga mo'ljallangan xabarlarni (stol holati, qulflar)
	// olib turardi. `Role` esa imzolangan JWT dan keladi.
	h.mu.RLock()
	for client := range h.clients {
		if roleSet[client.Role] {
			safeSend(client, msg)
		}
	}
	h.mu.RUnlock()
}

// safeSend — klientga xabar yuboradi. Klient aynan shu lahzada uzilib,
// unregister uning kanalini yopib ulgurgan bo'lsa, yopilgan kanalga yozish
// panic beradi — shuning uchun recover bilan himoyalangan.
func safeSend(client *Client, msg []byte) {
	defer func() { _ = recover() }()
	select {
	case client.Send <- msg:
	default:
	}
}

// SendToClient sends an event to a specific client
func (h *Hub) SendToClient(client *Client, event string, payload interface{}) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})
	safeSend(client, msg)
}

func handleClientDisconnect(client *Client) {
	locked := client.LockedTable()
	if locked != "" {
		UnlockTable(locked)
		// Notify others that table is unlocked
		H.SendToRoles("table:unlocked", map[string]interface{}{
			"table_sku":     locked,
			"was_locked_by": map[string]interface{}{"user_id": client.UserID, "name": client.Name},
		}, "cashier", "waiter", "admin", "super_admin")
	}
}
