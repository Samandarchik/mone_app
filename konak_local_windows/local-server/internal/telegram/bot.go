// Package telegram is a tiny self-contained Bot API client + long-poll worker.
//
// We deliberately avoid github.com/go-telegram-bot-api/* so go.mod stays stable
// and the surface area is small enough to audit. Only the methods we actually
// use are wrapped:
//
//   sendMessage       — text + reply keyboard
//   getUpdates        — long poll
//   answerCallback    — (unused for now)
//
// The bot's job here is verification and order intake for online (saboy /
// dostafka) customers. State lives in `online_verifications` (postgres). The
// HTTP API hands out 6-char codes; the bot watches for /start CODE and the
// contact + location keyboard buttons.
package telegram

import (
	"bytes"
	"context"
	crand "crypto/rand"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"konak-local/internal/db"
)

const apiBase = "https://api.telegram.org"

type Bot struct {
	Token       string
	AdminChatID string
	Username    string
	httpc       *http.Client
}

func New(token, adminChatID, username string) *Bot {
	return &Bot{
		Token:       token,
		AdminChatID: adminChatID,
		Username:    username,
		httpc:       &http.Client{Timeout: 65 * time.Second},
	}
}

// ---------- Bot API DTOs (only fields we read) -----------------------------

type Update struct {
	UpdateID      int64          `json:"update_id"`
	Message       *Message       `json:"message,omitempty"`
	EditedMessage *Message       `json:"edited_message,omitempty"`
	CallbackQuery *CallbackQuery `json:"callback_query,omitempty"`
}

type Message struct {
	MessageID int      `json:"message_id"`
	From      *User    `json:"from,omitempty"`
	Chat      Chat     `json:"chat"`
	Date      int64    `json:"date"`
	Text      string   `json:"text,omitempty"`
	Contact   *Contact `json:"contact,omitempty"`
	Location  *Loc     `json:"location,omitempty"`
}

type User struct {
	ID        int64  `json:"id"`
	IsBot     bool   `json:"is_bot"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name,omitempty"`
	Username  string `json:"username,omitempty"`
}

type Chat struct {
	ID   int64  `json:"id"`
	Type string `json:"type"`
}

type Contact struct {
	PhoneNumber string `json:"phone_number"`
	FirstName   string `json:"first_name"`
	LastName    string `json:"last_name,omitempty"`
	UserID      int64  `json:"user_id,omitempty"`
}

type Loc struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type CallbackQuery struct {
	ID      string   `json:"id"`
	From    *User    `json:"from"`
	Data    string   `json:"data"`
	Message *Message `json:"message,omitempty"`
}

// ---------- Reply keyboards ------------------------------------------------

type ReplyKeyboardButton struct {
	Text            string `json:"text"`
	RequestContact  bool   `json:"request_contact,omitempty"`
	RequestLocation bool   `json:"request_location,omitempty"`
	WebApp          *WebAppInfo `json:"web_app,omitempty"`
}

type WebAppInfo struct {
	URL string `json:"url"`
}

type ReplyKeyboardMarkup struct {
	Keyboard        [][]ReplyKeyboardButton `json:"keyboard"`
	ResizeKeyboard  bool                    `json:"resize_keyboard,omitempty"`
	OneTimeKeyboard bool                    `json:"one_time_keyboard,omitempty"`
}

// ---------- API calls ------------------------------------------------------

func (b *Bot) call(method string, params url.Values) ([]byte, error) {
	if b.Token == "" {
		return nil, errors.New("telegram: token not configured")
	}
	endpoint := fmt.Sprintf("%s/bot%s/%s", apiBase, b.Token, method)
	resp, err := b.httpc.PostForm(endpoint, params)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		return body, fmt.Errorf("telegram %s: HTTP %d: %s", method, resp.StatusCode, string(body))
	}
	return body, nil
}

func (b *Bot) SendMessage(chatID int64, text string, kb *ReplyKeyboardMarkup) error {
	v := url.Values{}
	v.Set("chat_id", fmt.Sprintf("%d", chatID))
	v.Set("text", text)
	v.Set("parse_mode", "HTML")
	if kb != nil {
		raw, _ := json.Marshal(kb)
		v.Set("reply_markup", string(raw))
	}
	_, err := b.call("sendMessage", v)
	return err
}

// SendAdmin posts a message to the admin chat (group / channel / private).
// Silently no-ops when AdminChatID is unset.
func (b *Bot) SendAdmin(text string) {
	if b.AdminChatID == "" {
		return
	}
	v := url.Values{}
	v.Set("chat_id", b.AdminChatID)
	v.Set("text", text)
	v.Set("parse_mode", "HTML")
	if _, err := b.call("sendMessage", v); err != nil {
		log.Printf("telegram: SendAdmin failed: %v", err)
	}
}

// ---------- Long-poll worker -----------------------------------------------

type updateResp struct {
	OK     bool     `json:"ok"`
	Result []Update `json:"result"`
}

func (b *Bot) Run(ctx context.Context) {
	if b.Token == "" {
		log.Println("telegram: TELEGRAM_BOT_TOKEN empty — bot disabled")
		return
	}
	log.Printf("telegram: bot started (@%s)", b.Username)

	var offset int64
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		v := url.Values{}
		v.Set("timeout", "55")
		v.Set("offset", fmt.Sprintf("%d", offset))
		v.Set("allowed_updates", `["message","callback_query"]`)

		body, err := b.call("getUpdates", v)
		if err != nil {
			log.Printf("telegram: getUpdates: %v", err)
			time.Sleep(3 * time.Second)
			continue
		}
		var ur updateResp
		if err := json.Unmarshal(body, &ur); err != nil {
			log.Printf("telegram: parse: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}
		for _, u := range ur.Result {
			if u.UpdateID >= offset {
				offset = u.UpdateID + 1
			}
			b.handleUpdate(ctx, u)
		}
	}
}

// ---------- Update routing -------------------------------------------------

const (
	statusPending   = "pending"
	statusConfirmed = "confirmed"
	statusUsed      = "used"
)

func (b *Bot) handleUpdate(ctx context.Context, u Update) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("telegram: handler panic: %v", r)
		}
	}()
	if u.Message == nil {
		return
	}
	m := u.Message
	if m.From == nil {
		return
	}

	// /start [CODE]
	if strings.HasPrefix(m.Text, "/start") {
		parts := strings.Fields(m.Text)
		var code string
		if len(parts) >= 2 {
			code = strings.ToUpper(strings.TrimSpace(parts[1]))
		}
		b.handleStart(ctx, m, code)
		return
	}

	// Contact (button)
	if m.Contact != nil {
		b.handleContact(ctx, m)
		return
	}

	// Location (button)
	if m.Location != nil {
		b.handleLocation(ctx, m)
		return
	}

	// Plain text after /start CODE → comment for the latest pending verification
	if m.Text != "" {
		b.handleText(ctx, m)
		return
	}
}

// /start (no code) — greeting; offer button to start verification or open WebApp.
// /start CODE   — bind this telegram user to that pending verification, ask for contact.
func (b *Bot) handleStart(ctx context.Context, m *Message, code string) {
	if code == "" {
		kb := &ReplyKeyboardMarkup{
			Keyboard: [][]ReplyKeyboardButton{
				{{Text: "📱 Telefon raqamni yuborish", RequestContact: true}},
				{{Text: "📍 Lokatsiyani yuborish", RequestLocation: true}},
			},
			ResizeKeyboard: true,
		}
		b.SendMessage(m.Chat.ID,
			"Assalomu alekum! 👋\n"+
				"Konak — buyurtma berish uchun saytdagi koddan foydalaning yoki <b>📱 Telefon raqamni yuborish</b> tugmasini bosing.\n\n"+
				"Sayt: https://konak.uz", kb)
		return
	}

	// Bind code → tg_user
	cmd := `UPDATE online_verifications SET tg_user_id = $1, tg_username = $2
	         WHERE code = $3 AND status = $4 AND expires_at > NOW()`
	tag, err := db.Pool.Exec(ctx, cmd, m.From.ID, m.From.Username, code, statusPending)
	if err != nil || tag.RowsAffected() == 0 {
		b.SendMessage(m.Chat.ID, "❗ Kod topilmadi yoki muddati tugagan. <b>konak.uz</b> dan yangi kod oling.", nil)
		return
	}

	kb := &ReplyKeyboardMarkup{
		Keyboard: [][]ReplyKeyboardButton{
			{{Text: "📱 Telefon raqamni yuborish", RequestContact: true}},
			{{Text: "📍 Lokatsiyani yuborish", RequestLocation: true}},
		},
		ResizeKeyboard: true,
	}
	b.SendMessage(m.Chat.ID,
		fmt.Sprintf("Assalomu alekum, %s! 👋\n"+
			"Buyurtmani tasdiqlash uchun <b>📱 Telefon raqamni yuborish</b> tugmasini bosing.\n"+
			"Dostafka uchun lokatsiyani ham yuborishingiz mumkin.\n\n"+
			"Kod: <code>%s</code>", htmlEscape(m.From.FirstName), code), kb)
}

func (b *Bot) handleContact(ctx context.Context, m *Message) {
	c := m.Contact
	// SECURITY: only accept the user's *own* contact, not someone else's they
	// happen to have saved.
	if c.UserID == 0 || c.UserID != m.From.ID {
		b.SendMessage(m.Chat.ID,
			"❗ Iltimos, <b>📱 Telefon raqamni yuborish</b> tugmasini bosing. "+
				"Boshqa odamning raqami yoki qo'lda yozilgan raqam qabul qilinmaydi.", contactKeyboard())
		return
	}
	phone := normalizePhone(c.PhoneNumber)

	// Update most recent pending verification for this user.
	verToken := randomHex(24)
	cmd := `UPDATE online_verifications
	          SET phone = $1,
	              verification_token = $2,
	              status = $3,
	              confirmed_at = NOW()
	          WHERE id = (
	            SELECT id FROM online_verifications
	            WHERE tg_user_id = $4 AND status = $5 AND expires_at > NOW()
	            ORDER BY created_at DESC LIMIT 1
	          )`
	tag, err := db.Pool.Exec(ctx, cmd, phone, verToken, statusConfirmed, m.From.ID, statusPending)
	if err != nil || tag.RowsAffected() == 0 {
		// No active verification — but we still keep the contact for next time.
		// Insert a "standalone" confirmed record so /webapp can find the phone.
		_, _ = db.Pool.Exec(ctx,
			`INSERT INTO online_verifications (code, pending_token, status, tg_user_id, tg_username, phone, expires_at, confirmed_at)
			 VALUES ($1, $2, 'used', $3, $4, $5, NOW() + INTERVAL '30 days', NOW())
			 ON CONFLICT (code) DO NOTHING`,
			randomHex(6), randomHex(16), m.From.ID, m.From.Username, phone)
		b.SendMessage(m.Chat.ID,
			fmt.Sprintf("✅ Raqam saqlandi: <code>%s</code>\nSaytda buyurtma berishni davom ettiring.", phone), nil)
		return
	}
	b.SendMessage(m.Chat.ID,
		fmt.Sprintf("✅ Tasdiqlandi: <code>%s</code>\nEndi <b>konak.uz</b> ga qaytib, buyurtmani yakunlang.", phone), nil)
}

func (b *Bot) handleLocation(ctx context.Context, m *Message) {
	loc := m.Location
	// Save to most recent pending OR confirmed verification of this user
	cmd := `UPDATE online_verifications
	          SET location_lat = $1, location_lng = $2
	          WHERE id = (
	            SELECT id FROM online_verifications
	            WHERE tg_user_id = $3 AND status IN ($4, $5) AND expires_at > NOW()
	            ORDER BY created_at DESC LIMIT 1
	          )`
	tag, err := db.Pool.Exec(ctx, cmd, loc.Latitude, loc.Longitude, m.From.ID, statusPending, statusConfirmed)
	if err != nil || tag.RowsAffected() == 0 {
		b.SendMessage(m.Chat.ID, "📍 Lokatsiya saqlandi, lekin aktiv buyurtma yo'q. Saytdan qayta urinib ko'ring.", nil)
		return
	}
	b.SendMessage(m.Chat.ID, "📍 Lokatsiya qabul qilindi. Saytda buyurtmani yakunlang.", nil)
}

func (b *Bot) handleText(ctx context.Context, m *Message) {
	// Reject hand-typed phone numbers (force button)
	t := strings.TrimSpace(m.Text)
	if looksLikePhone(t) {
		b.SendMessage(m.Chat.ID,
			"❗ Qo'lda yozilgan raqam qabul qilinmaydi. Iltimos, <b>📱 Telefon raqamni yuborish</b> tugmasini bosing.",
			contactKeyboard())
		return
	}
	// Otherwise — treat as note for the latest pending/confirmed verification.
	cmd := `UPDATE online_verifications
	          SET note = $1
	          WHERE id = (
	            SELECT id FROM online_verifications
	            WHERE tg_user_id = $2 AND status IN ($3, $4) AND expires_at > NOW()
	            ORDER BY created_at DESC LIMIT 1
	          )`
	tag, err := db.Pool.Exec(ctx, cmd, t, m.From.ID, statusPending, statusConfirmed)
	if err != nil || tag.RowsAffected() == 0 {
		return
	}
	b.SendMessage(m.Chat.ID, "📝 Izoh saqlandi. Buyurtmaga qo'shiladi.", nil)
}

// ---------- Helpers --------------------------------------------------------

func contactKeyboard() *ReplyKeyboardMarkup {
	return &ReplyKeyboardMarkup{
		Keyboard: [][]ReplyKeyboardButton{
			{{Text: "📱 Telefon raqamni yuborish", RequestContact: true}},
		},
		ResizeKeyboard: true,
	}
}

func looksLikePhone(s string) bool {
	digits := 0
	for _, r := range s {
		if r >= '0' && r <= '9' {
			digits++
		}
	}
	return digits >= 9 && digits <= 15
}

func normalizePhone(p string) string {
	if p == "" {
		return ""
	}
	if strings.HasPrefix(p, "+") {
		return p
	}
	return "+" + p
}

func htmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")
	return r.Replace(s)
}

// ---------- WebApp initData verification (HMAC-SHA256) ---------------------
//
// https://core.telegram.org/bots/webapps#validating-data-received-via-the-mini-app

type WebAppInitData struct {
	UserID    int64  `json:"user_id"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
	AuthDate  int64  `json:"auth_date"`
}

// VerifyInitData returns parsed user info if the signature is valid AND the
// auth_date is recent (within 24h).
func (b *Bot) VerifyInitData(initData string) (*WebAppInitData, error) {
	if b.Token == "" {
		return nil, errors.New("telegram: token not configured")
	}
	values, err := url.ParseQuery(initData)
	if err != nil {
		return nil, err
	}
	givenHash := values.Get("hash")
	if givenHash == "" {
		return nil, errors.New("telegram: hash missing")
	}
	values.Del("hash")

	keys := make([]string, 0, len(values))
	for k := range values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b1 bytes.Buffer
	for i, k := range keys {
		if i > 0 {
			b1.WriteByte('\n')
		}
		b1.WriteString(k)
		b1.WriteByte('=')
		b1.WriteString(values.Get(k))
	}

	// secret_key = HMAC_SHA256("WebAppData", bot_token)
	mac := hmac.New(sha256.New, []byte("WebAppData"))
	mac.Write([]byte(b.Token))
	secret := mac.Sum(nil)

	mac2 := hmac.New(sha256.New, secret)
	mac2.Write(b1.Bytes())
	expected := hex.EncodeToString(mac2.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(givenHash)) {
		return nil, errors.New("telegram: bad signature")
	}

	authDate, _ := parseInt(values.Get("auth_date"))
	if authDate == 0 || time.Now().Unix()-authDate > 86400 {
		return nil, errors.New("telegram: auth_date stale")
	}

	// user is JSON-encoded
	userJSON := values.Get("user")
	var u struct {
		ID        int64  `json:"id"`
		FirstName string `json:"first_name"`
		Username  string `json:"username"`
	}
	if err := json.Unmarshal([]byte(userJSON), &u); err != nil {
		return nil, err
	}
	return &WebAppInitData{
		UserID:    u.ID,
		Username:  u.Username,
		FirstName: u.FirstName,
		AuthDate:  authDate,
	}, nil
}

func parseInt(s string) (int64, error) {
	if s == "" {
		return 0, nil
	}
	var n int64
	_, err := fmt.Sscanf(s, "%d", &n)
	return n, err
}

// ---------- Random / code generators (used by HTTP layer too) --------------

func randomHex(nBytes int) string {
	b := make([]byte, nBytes)
	if _, err := io.ReadFull(crand.Reader, b); err != nil {
		return fmt.Sprintf("%x%d", time.Now().UnixNano(), nBytes)
	}
	return hex.EncodeToString(b)
}

// NewCode returns a user-facing 6-character code (excludes ambiguous chars).
func NewCode() string {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	b := make([]byte, 6)
	if _, err := io.ReadFull(crand.Reader, b); err != nil {
		return "ABCD12"
	}
	for i, x := range b {
		b[i] = alphabet[int(x)%len(alphabet)]
	}
	return string(b)
}

// NewToken returns a long random hex token (verification_token / pending_token).
func NewToken() string { return randomHex(24) }

// DeepLink returns the t.me/<bot>?start=CODE link.
func (b *Bot) DeepLink(code string) string {
	if b.Username == "" {
		return ""
	}
	return fmt.Sprintf("https://t.me/%s?start=%s", b.Username, code)
}

// ---------- HTTP-friendly notifier -----------------------------------------

// NotifyOnlineOrder posts a formatted message to the admin chat.
func (b *Bot) NotifyOnlineOrder(orderNumber, orderType, phone string, lat, lng *float64, total int, items []map[string]interface{}, note string) {
	if b.AdminChatID == "" {
		return
	}
	var sb strings.Builder
	if orderType == "delivery" {
		sb.WriteString("🆕 <b>Yangi DOSTAFKA buyurtmasi</b>\n")
	} else {
		sb.WriteString("🆕 <b>Yangi SABOY buyurtmasi</b>\n")
	}
	fmt.Fprintf(&sb, "№ <code>%s</code>\n", orderNumber)
	fmt.Fprintf(&sb, "📱 %s\n", phone)
	if lat != nil && lng != nil {
		fmt.Fprintf(&sb, "📍 %.6f, %.6f\nhttps://maps.google.com/?q=%.6f,%.6f\n", *lat, *lng, *lat, *lng)
	}
	if len(items) > 0 {
		sb.WriteString("\n<b>Mahsulotlar:</b>\n")
		for _, it := range items {
			name, _ := it["name"].(string)
			if name == "" {
				if snap, ok := it["snapshot"].(map[string]interface{}); ok {
					if nm, ok := snap["name"].(map[string]interface{}); ok {
						if uz, ok := nm["uz"].(string); ok {
							name = uz
						}
					}
				}
			}
			qty, _ := it["quantity"].(float64)
			tot, _ := it["total"].(float64)
			fmt.Fprintf(&sb, "• %s × %d — %.0f\n", htmlEscape(name), int(qty), tot)
		}
	}
	fmt.Fprintf(&sb, "\n💰 <b>Jami: %d</b>", total)
	if note != "" {
		fmt.Fprintf(&sb, "\n📝 %s", htmlEscape(note))
	}
	b.SendAdmin(sb.String())
}
