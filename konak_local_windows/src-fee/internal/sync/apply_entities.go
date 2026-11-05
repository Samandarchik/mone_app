package sync

// Xodim PINini node'lar orasida ko'chirish.
//
// NEGA ALOHIDA: `users.pin` (HMAC barmoq izi) va `users.pin_hash` (PBKDF2)
// har bir node'ning O'Z PIN_PEPPER siriga bog'liq — tayyor hashni ko'chirish
// mumkin emas, ikkinchi node'da u hech qachon mos kelmaydi. Shuning uchun
// qator replikatsiyasi bu ikki ustunni umuman uzatmaydi (db.ReplTables →
// users.Skip), PINning o'zi esa shu yerda SYNC_TOKEN bilan shifrlangan
// konvertda (`pin_enc`) keladi va qabul qiluvchi node uni O'Z pepperi bilan
// qaytadan hisoblaydi.

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/security"
)

func asString(v interface{}) string {
	s, _ := v.(string)
	return s
}

// applyUserPIN — `user:*` eventidan faqat PINni oladi. Xodimning qolgan
// maydonlari (ism, telefon, rol, huquqlar, status) qator replikatsiyasi
// orqali keladi — bu yerda ularga tegilmaydi.
func applyUserPIN(data json.RawMessage) error {
	var p map[string]interface{}
	if err := json.Unmarshal(data, &p); err != nil {
		return fmt.Errorf("user payload: %w", err)
	}
	id := toInt(p["id"])
	if id <= 0 {
		return fmt.Errorf("user eventida id yo'q")
	}
	enc := asString(p["pin_enc"])
	if enc == "" {
		// PIN o'zgarmagan (yoki SYNC_TOKEN sozlanmagan) — bu xato emas.
		return nil
	}

	pin, err := security.OpenFromSync(enc)
	if err != nil {
		return fmt.Errorf("user %d PINini ochib bo'lmadi (SYNC_TOKEN mos emasmi?): %w", id, err)
	}
	if !security.ValidatePIN(pin) {
		return fmt.Errorf("user %d uchun kelgan PIN formati noto'g'ri", id)
	}
	fp, err := security.PINFingerprint(pin)
	if err != nil {
		return fmt.Errorf("user %d PIN fingerprint: %w", id, err)
	}
	hash, err := security.HashPIN(pin)
	if err != nil {
		return fmt.Errorf("user %d PIN hash: %w", id, err)
	}

	ctx := context.Background()
	// Xodim qatori hali kelmagan bo'lishi mumkin (eventlar tartibi) — bunda
	// xato qaytariladi va event `sync_failed` orqali qayta uriniladi.
	return withApply(ctx, func(tx pgx.Tx) error {
		// `updated_at`ga TEGILMAYDI: u qator replikatsiyasi orqali asl
		// node'dagi qiymat bilan keladi. Bu yerda NOW() qo'yilsa xodim
		// qatori ikki bazada abadiy farq qilib qolardi.
		tag, err := tx.Exec(ctx,
			`UPDATE users SET pin=$2, pin_hash=$3 WHERE id=$1`, id, fp, hash)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return fmt.Errorf("user %d hali bu node'da yo'q — PIN keyinroq qo'llanadi", id)
		}
		logApplied("xodim %d PINi qo'llandi", id)
		return nil
	})
}

// derivePINFromRow — kelgan xodim qatoridagi `pin_sync` (SYNC_TOKEN bilan
// shifrlangan PIN) dan SHU node'ning `pin` (barmoq izi) va `pin_hash`
// qiymatlarini hisoblaydi.
//
// Bu qator replikatsiyasining bir qismi bo'lgani uchun to'liq resync ham
// PINlarni tiklaydi — ilgari PIN faqat bir martalik `user:*` eventida
// ketardi va o'sha event o'tib ketgach xodim ikkinchi node'da PINsiz
// qolardi.
func derivePINFromRow(ctx context.Context, tx pgx.Tx, row map[string]json.RawMessage) error {
	raw, ok := row["pin_sync"]
	if !ok {
		return nil
	}
	var sealed string
	if err := json.Unmarshal(raw, &sealed); err != nil || sealed == "" {
		return nil
	}
	idRaw, ok := row["id"]
	if !ok {
		return nil
	}
	var id int
	if err := json.Unmarshal(idRaw, &id); err != nil || id <= 0 {
		return nil
	}

	pin, err := security.OpenFromSync(sealed)
	if err != nil {
		// SYNC_TOKEN mos emas — xodimning qolgan maydonlari baribir yozildi.
		logApplied("xodim %d PINini ochib bo'lmadi (SYNC_TOKEN mos emasmi?): %v", id, err)
		return nil
	}
	if !security.ValidatePIN(pin) {
		return nil
	}
	fp, err := security.PINFingerprint(pin)
	if err != nil {
		return err
	}

	// Allaqachon shu PIN bo'lsa qimmat PBKDF2 hisobini takrorlamaymiz.
	var current string
	if err := tx.QueryRow(ctx, `SELECT pin FROM users WHERE id=$1`, id).Scan(&current); err == nil && current == fp {
		return nil
	}
	hash, err := security.HashPIN(pin)
	if err != nil {
		return err
	}
	// `updated_at`ga tegilmaydi — u asl node'dan kelgan qiymatda qoladi,
	// aks holda xodim qatori ikki bazada abadiy farq qilardi.
	if _, err := tx.Exec(ctx, `UPDATE users SET pin=$2, pin_hash=$3 WHERE id=$1`, id, fp, hash); err != nil {
		return err
	}
	logApplied("xodim %d PINi qator bilan birga qo'llandi", id)
	return nil
}
