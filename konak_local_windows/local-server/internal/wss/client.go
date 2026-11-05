package wss

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/gorilla/websocket"

	"konak-local/internal/middleware"
	"konak-local/internal/models"
)

const (
	writeWait      = 5 * time.Second
	pongWait       = 15 * time.Second
	pingPeriod     = 3 * time.Second
	maxMessageSize = 65536
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// Client represents a single WebSocket connection
type Client struct {
	Hub         *Hub
	Conn        *websocket.Conn
	Send        chan []byte
	UserID      int
	Name        string
	Role        string
	Source      string
	LockedTable string
	Token       *middleware.TokenClaims
}

// ServeWS handles WebSocket upgrade and creates a new client
func ServeWS(hub *Hub, w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WSS upgrade error: %v", err)
		return
	}

	// Disable compression overhead for localhost
	conn.EnableWriteCompression(false)

	client := &Client{
		Hub:  hub,
		Conn: conn,
		Send: make(chan []byte, 512),
	}

	// Wait for init event with token
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	_, msg, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		return
	}

	var initEvent struct {
		Event   string `json:"event"`
		Payload struct {
			Token       string `json:"token"`
			MenuVersion int    `json:"menu_version"`
			Source      string `json:"source"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(msg, &initEvent); err != nil || initEvent.Event != "init" {
		sendError(conn, "init:error", "init event kerak")
		conn.Close()
		return
	}

	// Parse token (optional for QR clients)
	tokenStr := initEvent.Payload.Token
	if tokenStr != "" {
		if len(tokenStr) > 7 && tokenStr[:7] == "Bearer " {
			tokenStr = tokenStr[7:]
		}
		claims, err := middleware.ParseToken(tokenStr)
		if err != nil {
			sendError(conn, "init:error", "Token yaroqsiz")
			conn.Close()
			return
		}
		client.UserID = claims.UserID
		client.Name = claims.Name
		client.Role = claims.Role
		client.Token = claims
	} else {
		client.Name = "QR Mijoz"
		client.Role = "guest"
	}
	client.Source = initEvent.Payload.Source

	// Send init:ok
	initOK := buildInitOK(initEvent.Payload.MenuVersion)
	initOKData, _ := json.Marshal(models.WSEvent{Event: "init:ok", Payload: initOK})
	conn.WriteMessage(websocket.TextMessage, initOKData)

	hub.register <- client

	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.Hub.unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(maxMessageSize)
	c.Conn.SetReadDeadline(time.Now().Add(pongWait))

	// Protocol-level pong handler — resets deadline on each pong
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		c.Conn.SetReadDeadline(time.Now().Add(pongWait))

		var event models.WSEvent
		if err := json.Unmarshal(message, &event); err != nil {
			continue
		}

		if event.Event == "pong" {
			continue
		}

		HandleEvent(c, &event)
	}
}

func (c *Client) writePump() {
	// Protocol-level ping ticker
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.Conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
			// Drain all queued messages in one batch
			n := len(c.Send)
			for i := 0; i < n; i++ {
				if err := c.Conn.WriteMessage(websocket.TextMessage, <-c.Send); err != nil {
					return
				}
			}

		case <-ticker.C:
			// Send protocol-level ping frame (handled by gorilla automatically)
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func sendError(conn *websocket.Conn, event, message string) {
	data, _ := json.Marshal(models.WSEvent{
		Event:   event,
		Payload: json.RawMessage(`{"error":"` + message + `"}`),
	})
	conn.WriteMessage(websocket.TextMessage, data)
}
