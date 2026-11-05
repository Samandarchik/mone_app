package db

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"
	"time"

	"konak-local/internal/security"
)

// Seed — bo'sh bazaga faqat birinchi super_admin'ni qo'shadi.
// Menyu, kategoriya, zona/stol, ombor va boshqa hamma narsa ilova ichidan kiritiladi.
func Seed() {
	ctx := context.Background()
	// Always clean locks on startup
	Pool.Exec(ctx, "DELETE FROM table_locks")

	var count int
	// Xato TEKSHIRILADI. Ilgari e'tiborsiz qoldirilgan: transient xatoda
	// `count` 0 bo'lib qolib, urug'lash ishga tushardi.
	if err := Pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&count); err != nil {
		log.Printf("Seed: xodimlar sonini o'qib bo'lmadi, urug'lash o'tkazib yuborildi: %v", err)
		return
	}
	if count > 0 {
		return
	}

	// PIN har o'rnatishda TASODIFIY. Ilgari "1234" qattiq yozilgan edi va
	// `users` jadvali bo'shab qolgan har qanday holatda (yangi o'rnatish,
	// muvaffaqiyatsiz tiklash, xodimlarni tozalash) tizim ma'lum PIN bilan
	// ochilib qolardi — bulut node'i esa internetdan ochiq.
	const (
		adminName  = "Samandar"
		adminPhone = "+998901234567"
	)
	adminPIN := randomPIN()

	fingerprint, fpErr := security.PINFingerprint(adminPIN)
	hash, hashErr := security.HashPIN(adminPIN)
	if fpErr != nil || hashErr != nil {
		log.Printf("Super admin PIN xavfsizligini tayyorlashda xato: %v %v", fpErr, hashErr)
		return
	}

	// pin_sync — PINning node'lararo ko'chiriladigan (SYNC_TOKEN bilan
	// shifrlangan) nusxasi. SYNC_TOKEN yo'q bo'lsa bo'sh qoladi.
	sealed, _ := security.SealForSync(adminPIN)

	if _, err := Pool.Exec(ctx, `INSERT INTO users (id, name, phone, role, pin, pin_hash, pin_sync, status)
		VALUES (1,$1,$2,'super_admin',$3,$4,$5,'active')`,
		adminName, adminPhone, fingerprint, hash, sealed); err != nil {
		log.Printf("Super admin yaratishda xato: %v", err)
		return
	}
	Pool.Exec(ctx, "SELECT setval('users_id_seq', (SELECT MAX(id) FROM users))")

	log.Printf("========================================================")
	log.Printf(" Birinchi super_admin yaratildi")
	log.Printf("   telefon: %s", adminPhone)
	log.Printf("   PIN:     %s   <-- YOZIB OLING, boshqa ko'rsatilmaydi", adminPIN)
	log.Printf("   Kirgandan keyin PINni darhol o'zgartiring.")
	log.Printf("========================================================")
}

// randomPIN — 4 xonali tasodifiy PIN (crypto/rand).
func randomPIN() string {
	var b [4]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand ishlamasa ham qattiq yozilgan qiymat qaytarmaymiz.
		return fmt.Sprintf("%04d", time.Now().UnixNano()%10000)
	}
	n := (int(b[0])<<24 | int(b[1])<<16 | int(b[2])<<8 | int(b[3])) & 0x7fffffff
	return fmt.Sprintf("%04d", n%10000)
}
