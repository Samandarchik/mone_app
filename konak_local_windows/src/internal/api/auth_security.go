package api

import (
	"context"
	"crypto/subtle"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"konak-local/internal/db"
	"konak-local/internal/middleware"
	"konak-local/internal/models"
	"konak-local/internal/security"
)

const (
	maxLoginFailures = 5
	loginWindow      = 15 * time.Minute
	loginBlock       = 5 * time.Minute
)

type loginAttempt struct {
	failures     int
	windowStart  time.Time
	blockedUntil time.Time
}

var authAttempts = struct {
	sync.Mutex
	items map[string]loginAttempt
}{items: make(map[string]loginAttempt)}

// Eskirgan urinishlarni davriy tozalash. Ilgari yozuv faqat SHU kalit qayta
// urinilganda o'chirilardi — ya'ni har bir yangi IP/telefon juftligi xotirada
// abadiy qolib, uzoq ishlagan serverda sekin-asta o'sib borardi.
func init() {
	go func() {
		for {
			time.Sleep(10 * time.Minute)
			now := time.Now()
			authAttempts.Lock()
			for key, a := range authAttempts.items {
				expired := now.Sub(a.windowStart) > loginWindow &&
					(a.blockedUntil.IsZero() || now.After(a.blockedUntil))
				if expired {
					delete(authAttempts.items, key)
				}
			}
			authAttempts.Unlock()
		}
	}()
}

type authRecord struct {
	user      models.User
	pinLookup string
	pinHash   string
}

func loginAttemptKey(r *http.Request, subject string) string {
	// `middleware.ClientIP` — proxy orqasida haqiqiy manzilni beradi.
	// Ilgari faqat `RemoteAddr` olinardi va bulutda hamma so'rov bitta
	// manzilda ko'rinib, chegara butun internetga umumiy bo'lib qolardi.
	return middleware.ClientIP(r) + "|" + strings.ToLower(strings.TrimSpace(subject))
}

func checkLoginLimit(w http.ResponseWriter, key string) bool {
	now := time.Now()
	authAttempts.Lock()
	defer authAttempts.Unlock()

	a, ok := authAttempts.items[key]
	if !ok {
		return true
	}
	if !a.blockedUntil.IsZero() && now.Before(a.blockedUntil) {
		seconds := int(time.Until(a.blockedUntil).Seconds()) + 1
		w.Header().Set("Retry-After", strconv.Itoa(seconds))
		jsonError(w, http.StatusTooManyRequests, "too_many_attempts",
			"Ko'p noto'g'ri urinish. Bir necha daqiqadan keyin qayta urinib ko'ring")
		return false
	}
	if now.Sub(a.windowStart) > loginWindow {
		delete(authAttempts.items, key)
	}
	return true
}

func recordLoginFailure(key string) {
	now := time.Now()
	authAttempts.Lock()
	defer authAttempts.Unlock()

	a := authAttempts.items[key]
	if a.windowStart.IsZero() || now.Sub(a.windowStart) > loginWindow {
		a = loginAttempt{windowStart: now}
	}
	a.failures++
	if a.failures >= maxLoginFailures {
		a.blockedUntil = now.Add(loginBlock)
		a.failures = 0
		a.windowStart = now
	}
	authAttempts.items[key] = a
}

func clearLoginFailures(key string) {
	authAttempts.Lock()
	delete(authAttempts.items, key)
	authAttempts.Unlock()
}

func loadAuthByPhone(ctx context.Context, phone string) (*authRecord, error) {
	var rec authRecord
	err := db.Pool.QueryRow(ctx, `
		SELECT id, name, phone, role, pin, COALESCE(pin_hash,''), custom_permissions, status
		FROM users WHERE phone = $1 AND status = 'active'`,
		strings.TrimSpace(phone),
	).Scan(
		&rec.user.ID, &rec.user.Name, &rec.user.Phone, &rec.user.Role,
		&rec.pinLookup, &rec.pinHash, &rec.user.CustomPermissions, &rec.user.Status,
	)
	return &rec, err
}

func loadAuthByPIN(ctx context.Context, pin string) (*authRecord, error) {
	fingerprint, err := security.PINFingerprint(pin)
	if err != nil {
		return nil, err
	}
	var rec authRecord
	err = db.Pool.QueryRow(ctx, `
		SELECT id, name, phone, role, pin, COALESCE(pin_hash,''), custom_permissions, status
		FROM users
		WHERE status = 'active' AND (pin = $1 OR (pin_hash = '' AND pin = $2))
		ORDER BY id LIMIT 1`,
		fingerprint, pin,
	).Scan(
		&rec.user.ID, &rec.user.Name, &rec.user.Phone, &rec.user.Role,
		&rec.pinLookup, &rec.pinHash, &rec.user.CustomPermissions, &rec.user.Status,
	)
	return &rec, err
}

func verifyAuthPIN(ctx context.Context, rec *authRecord, pin string) bool {
	if rec.pinHash != "" {
		if !security.VerifyPIN(pin, rec.pinHash) {
			return false
		}
		backfillPINSync(ctx, rec.user.ID, pin)
		return true
	}

	// Legacy migration: old databases stored the four digits in users.pin.
	if len(rec.pinLookup) != len(pin) ||
		subtle.ConstantTimeCompare([]byte(rec.pinLookup), []byte(pin)) != 1 {
		return false
	}
	fingerprint, fpErr := security.PINFingerprint(pin)
	hash, hashErr := security.HashPIN(pin)
	if fpErr != nil || hashErr != nil {
		return false
	}
	sealed, _ := security.SealForSync(pin)
	if _, err := db.Pool.Exec(ctx,
		"UPDATE users SET pin = $1, pin_hash = $2, pin_sync = $3, updated_at = NOW() WHERE id = $4",
		fingerprint, hash, sealed, rec.user.ID,
	); err != nil {
		return false
	}
	rec.pinLookup = fingerprint
	rec.pinHash = hash
	return true
}

// backfillPINSync — `pin_sync` ustuni bo'sh xodimga uni to'ldiradi.
//
// NEGA SHU YERDA: pin_sync — PINning SYNC_TOKEN bilan shifrlangan nusxasi,
// u node'lararo ko'chadi. Hash'dan PINni tiklab bo'lmaydi, shuning uchun
// ustun qo'shilgunga qadar yaratilgan xodimlar uchun yagona imkoniyat —
// xodim PINini kiritgan payt. Muvaffaqiyatli kirishdan keyin bir marta
// yoziladi va shundan so'ng xodim ikkinchi node'da ham o'z PINi bilan
// kira oladi.
func backfillPINSync(ctx context.Context, userID int, pin string) {
	var existing string
	if err := db.Pool.QueryRow(ctx,
		"SELECT COALESCE(pin_sync,'') FROM users WHERE id=$1", userID).Scan(&existing); err != nil || existing != "" {
		return
	}
	sealed, err := security.SealForSync(pin)
	if err != nil || sealed == "" {
		return
	}
	// `updated_at`ga tegilmaydi: bu ichki to'ldirish, xodim ma'lumoti
	// o'zgargani yo'q.
	db.Pool.Exec(ctx, "UPDATE users SET pin_sync=$2 WHERE id=$1", userID, sealed)
}
