package api

import (
	"context"
	"crypto/subtle"
	"strings"

	"konak-local/internal/db"
	"konak-local/internal/models"
	"konak-local/internal/security"
)

// Kirish urinishlari chegarasi (5 xatodan keyin 5 daqiqa blok) OLIB
// TASHLANDI: restoranda xodim PINni 2-3 marta adashtirsa kassa 5 daqiqa
// qulflanib qolardi — ish paytida bunga yo'l qo'yib bo'lmaydi.

type authRecord struct {
	user      models.User
	pinLookup string
	pinHash   string
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
