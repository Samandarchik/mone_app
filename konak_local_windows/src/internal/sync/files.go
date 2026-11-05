package sync

// ============================================================================
// MENYU RASMLARINI (uploads/) REPLIKATSIYA QILISH
// ============================================================================
//
// Mahsulot/kategoriya rasmi bazada faqat URL sifatida turadi
// ("/uploads/products/1.jpg"), faylning o'zi esa yuklangan node'ning
// diskida. Shu sababli bazalar bir xil bo'lsa ham sayt menyusida rasmlar
// ochilmasdi — cloud'da fayl yo'q edi.
//
// Yechim: `uploads/` papkasi davriy skanerlanadi, o'zgargan/yangi fayl
// `file:upsert` eventi bilan (base64) peer'ga yuboriladi. Handler'larga
// tayanmaymiz — qaysi kod yo'li bilan fayl paydo bo'lishidan qat'i nazar
// skaner uni topadi (bazadagi trigger bilan bir xil mantiq).

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"konak-local/internal/db"
)

const (
	uploadsRoot = "./uploads"
	// Bitta event bilan uzatiladigan eng katta fayl. POS rasmlari ~50-200 KB.
	maxSyncFileBytes = 8 << 20
)

type fileEvent struct {
	Path    string `json:"path"` // uploads ichidagi nisbiy yo'l ("products/1.jpg")
	SHA256  string `json:"sha256"`
	Size    int64  `json:"size"`
	Content string `json:"content"` // base64
	Deleted bool   `json:"deleted"`
}

// StartFileWatcher — uploads papkasini davriy skanerlaydi.
func StartFileWatcher() {
	if _, err := db.Pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS sync_files (
			path TEXT PRIMARY KEY,
			sha256 TEXT NOT NULL DEFAULT '',
			size BIGINT NOT NULL DEFAULT 0,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`); err != nil {
		log.Printf("SYNC: sync_files jadvali yaratilmadi: %v", err)
		return
	}
	go func() {
		for {
			scanUploadsOnce(false)
			time.Sleep(60 * time.Second)
		}
	}()
}

// ResyncFiles — hamma rasmni qaytadan yuboradi (to'liq tekislash uchun).
func ResyncFiles() int { return scanUploadsOnce(true) }

// scanUploadsOnce — o'zgargan fayllarni topib outbox'ga qo'yadi.
// force=true bo'lsa hamma fayl qaytadan yuboriladi (to'liq snapshot).
func scanUploadsOnce(force bool) int {
	ctx := context.Background()

	known := map[string]string{} // path → sha256
	rows, err := db.Pool.Query(ctx, `SELECT path, sha256 FROM sync_files`)
	if err == nil {
		for rows.Next() {
			var p, h string
			if rows.Scan(&p, &h) == nil {
				known[p] = h
			}
		}
		rows.Close()
	}

	seen := map[string]bool{}
	sent := 0

	filepath.Walk(uploadsRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil || info == nil || info.IsDir() {
			return nil
		}
		rel, relErr := filepath.Rel(uploadsRoot, path)
		if relErr != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		seen[rel] = true

		if info.Size() > maxSyncFileBytes {
			log.Printf("SYNC: %s juda katta (%d bayt) — yuborilmadi", rel, info.Size())
			return nil
		}
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return nil
		}
		sum := sha256.Sum256(data)
		hash := hex.EncodeToString(sum[:])
		if !force && known[rel] == hash {
			return nil
		}

		payload, _ := json.Marshal(fileEvent{
			Path:    rel,
			SHA256:  hash,
			Size:    int64(len(data)),
			Content: base64.StdEncoding.EncodeToString(data),
		})
		if err := enqueueEvent(ctx, "file:upsert", payload); err != nil {
			log.Printf("SYNC: %s fayl eventi yozilmadi: %v", rel, err)
			return nil
		}
		db.Pool.Exec(ctx, `
			INSERT INTO sync_files (path, sha256, size, updated_at) VALUES ($1,$2,$3,NOW())
			ON CONFLICT (path) DO UPDATE SET sha256=EXCLUDED.sha256, size=EXCLUDED.size, updated_at=NOW()`,
			rel, hash, len(data))
		sent++
		return nil
	})

	// Diskdan o'chirilgan fayllar.
	for p := range known {
		if seen[p] {
			continue
		}
		payload, _ := json.Marshal(fileEvent{Path: p, Deleted: true})
		if err := enqueueEvent(ctx, "file:upsert", payload); err == nil {
			db.Pool.Exec(ctx, `DELETE FROM sync_files WHERE path=$1`, p)
			sent++
		}
	}

	if sent > 0 {
		log.Printf("SYNC: %d ta fayl o'zgarishi navbatga qo'yildi", sent)
	}
	return sent
}

// enqueueEvent — Go tomonidan tug'ilgan eventni outbox'ga yozadi
// (trigger orqali kelmaydigan eventlar uchun: fayllar, snapshot).
func enqueueEvent(ctx context.Context, eventType string, payload []byte) error {
	_, err := db.Pool.Exec(ctx, `
		INSERT INTO sync_queue (event_id, origin, event_type, payload, status)
		VALUES ($1 || '-' || nextval('sync_event_seq')::text, $1, $2, $3::jsonb, 'pending')`,
		nodeID, eventType, string(payload))
	return err
}

// applyFileUpsert — kelgan faylni shu node'ning uploads papkasiga yozadi.
func applyFileUpsert(data json.RawMessage) error {
	var e fileEvent
	if err := json.Unmarshal(data, &e); err != nil {
		return fmt.Errorf("file:upsert payload: %w", err)
	}
	clean, err := safeUploadPath(e.Path)
	if err != nil {
		return err
	}

	if e.Deleted {
		os.Remove(clean)
		db.Pool.Exec(context.Background(), `DELETE FROM sync_files WHERE path=$1`, e.Path)
		return nil
	}

	raw, err := base64.StdEncoding.DecodeString(e.Content)
	if err != nil {
		return fmt.Errorf("file:upsert base64: %w", err)
	}
	sum := sha256.Sum256(raw)
	if got := hex.EncodeToString(sum[:]); e.SHA256 != "" && got != e.SHA256 {
		return fmt.Errorf("file:upsert %s — sha256 mos kelmadi", e.Path)
	}
	if err := os.MkdirAll(filepath.Dir(clean), 0o755); err != nil {
		return err
	}
	// Avval vaqtinchalik faylga, keyin joyiga — yarim yozilgan rasm qolmasin.
	tmp := clean + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, clean); err != nil {
		os.Remove(tmp)
		return err
	}
	// Shu node o'z skanerida buni "yangi fayl" deb qayta yubormasin.
	db.Pool.Exec(context.Background(), `
		INSERT INTO sync_files (path, sha256, size, updated_at) VALUES ($1,$2,$3,NOW())
		ON CONFLICT (path) DO UPDATE SET sha256=EXCLUDED.sha256, size=EXCLUDED.size, updated_at=NOW()`,
		e.Path, e.SHA256, len(raw))
	logApplied("fayl qo'llandi — %s (%d bayt)", e.Path, len(raw))
	return nil
}

// safeUploadPath — peer'dan kelgan yo'l uploads papkasidan tashqariga
// chiqmasligini kafolatlaydi ("../../etc/passwd" kabi urinishlar).
func safeUploadPath(rel string) (string, error) {
	if rel == "" {
		return "", fmt.Errorf("fayl yo'li bo'sh")
	}
	rel = strings.TrimPrefix(filepath.ToSlash(rel), "/")
	if strings.Contains(rel, "..") {
		return "", fmt.Errorf("fayl yo'li ruxsat etilmagan: %s", rel)
	}
	root, err := filepath.Abs(uploadsRoot)
	if err != nil {
		return "", err
	}
	full := filepath.Join(root, filepath.FromSlash(rel))
	if !strings.HasPrefix(full, root+string(os.PathSeparator)) {
		return "", fmt.Errorf("fayl yo'li ruxsat etilmagan: %s", rel)
	}
	return full, nil
}
