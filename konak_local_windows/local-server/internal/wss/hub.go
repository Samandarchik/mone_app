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
	broadcast  chan []byte
	mu         sync.RWMutex
}

var H *Hub

func NewHub() *Hub {
	H = &Hub{
		clients:    make(map[*Client]bool),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		broadcast:  make(chan []byte, 512),
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
			handleClientDisconnect(client)

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.clients, client)
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
		select {
		case client.Send <- msg:
		default:
		}
	}
	h.mu.RUnlock()
}

// BroadcastEvent sends an event to all clients
func (h *Hub) BroadcastEvent(event string, payload interface{}) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})
	h.broadcast <- msg
}

// SendToRoles sends an event to clients with specific roles
func (h *Hub) SendToRoles(event string, payload interface{}, roles ...string) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})

	roleSet := make(map[string]bool)
	for _, r := range roles {
		roleSet[r] = true
	}

	h.mu.RLock()
	for client := range h.clients {
		if roleSet[client.Role] || roleSet[client.Source] {
			select {
			case client.Send <- msg:
			default:
			}
		}
	}
	h.mu.RUnlock()
}

// SendToClient sends an event to a specific client
func (h *Hub) SendToClient(client *Client, event string, payload interface{}) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})
	select {
	case client.Send <- msg:
	default:
	}
}

// SendToTableSubscribers sends to clients that have locked or subscribed to a table
func (h *Hub) SendToTableSubscribers(event string, payload interface{}, tableSKU string) {
	data, _ := json.Marshal(payload)
	msg, _ := json.Marshal(models.WSEvent{Event: event, Payload: data})

	h.mu.RLock()
	for client := range h.clients {
		if client.LockedTable == tableSKU || client.Role == "cashier" || client.Role == "admin" || client.Role == "super_admin" {
			select {
			case client.Send <- msg:
			default:
			}
		}
	}
	h.mu.RUnlock()
}

func handleClientDisconnect(client *Client) {
	if client.LockedTable != "" {
		UnlockTable(client.LockedTable)
		// Notify others that table is unlocked
		H.SendToRoles("table:unlocked", map[string]interface{}{
			"table_sku":     client.LockedTable,
			"was_locked_by": map[string]interface{}{"user_id": client.UserID, "name": client.Name},
		}, "cashier", "waiter", "admin", "super_admin")
	}
}
