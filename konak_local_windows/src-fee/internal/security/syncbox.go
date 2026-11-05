package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"sync"
)

// Sync kanali orqali maxfiy qiymat (masalan PIN) uzatish uchun AES-256-GCM
// konverti.
//
// Nega kerak: node'lar PINni `pin` (fingerprint) va `pin_hash` ko'rinishida
// saqlaydi, ikkalasi ham o'sha node'ning PIN_PEPPER siriga bog'liq. Local va
// cloud'da pepper har xil, shuning uchun tayyor hashni ko'chirish foydasiz —
// qabul qiluvchi uni tekshira olmaydi. Yechim: PIN sync payloadida shifrlangan
// holda ketadi, qabul qiluvchi ochib, O'ZINING pepperi bilan qaytadan hash
// qiladi. Shu tariqa hech qayerda ochiq PIN saqlanmaydi.
//
// Kalit — ikkala node'da allaqachon umumiy bo'lgan SYNC_TOKEN'dan chiqariladi,
// ya'ni qo'shimcha sir tarqatish shart emas.

const syncBoxInfo = "konak-pin-sync-v1"

var (
	syncSecret   []byte
	syncSecretMu sync.RWMutex
)

// ConfigureSyncSecret sync konverti kalitini o'rnatadi (SYNC_TOKEN).
func ConfigureSyncSecret(secret string) {
	syncSecretMu.Lock()
	syncSecret = []byte(secret)
	syncSecretMu.Unlock()
}

// SyncSecretReady — kalit yetarlicha uzunmi (shifrlash mumkinmi).
func SyncSecretReady() bool {
	syncSecretMu.RLock()
	defer syncSecretMu.RUnlock()
	return len(syncSecret) >= 16
}

func syncAEAD() (cipher.AEAD, error) {
	syncSecretMu.RLock()
	secret := make([]byte, len(syncSecret))
	copy(secret, syncSecret)
	syncSecretMu.RUnlock()

	if len(secret) < 16 {
		return nil, errors.New("SYNC_TOKEN kamida 16 belgidan iborat bo'lishi kerak")
	}
	sum := sha256.Sum256(append(secret, []byte(syncBoxInfo)...))
	block, err := aes.NewCipher(sum[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// SealForSync — matnni shifrlab, base64 (std) satr qaytaradi.
func SealForSync(plaintext string) (string, error) {
	aead, err := syncAEAD()
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	sealed := aead.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// OpenFromSync — SealForSync natijasini ochadi.
func OpenFromSync(encoded string) (string, error) {
	aead, err := syncAEAD()
	if err != nil {
		return "", err
	}
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return "", err
	}
	if len(raw) < aead.NonceSize() {
		return "", errors.New("sync konverti juda qisqa")
	}
	nonce, body := raw[:aead.NonceSize()], raw[aead.NonceSize():]
	plaintext, err := aead.Open(nil, nonce, body, nil)
	if err != nil {
		return "", err
	}
	return string(plaintext), nil
}
