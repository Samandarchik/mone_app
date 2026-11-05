package backup

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"konak-local/internal/db"
)

const (
	backupMagic      = "KONAKB1\n"
	backupSaltSize   = 16
	backupNonceBase  = 8
	backupChunkSize  = 1 << 20
	backupIterations = 250_000
	restoreMarker    = ".restore-pending.json"
)

type Config struct {
	Enabled       bool
	DBURL         string
	Dir           string
	EncryptionKey string
	RetentionDays int
	Hour          int
	PgDumpPath    string
	PgRestorePath string
}

type Metadata struct {
	Filename  string `json:"filename"`
	SizeBytes int64  `json:"size_bytes"`
	Checksum  string `json:"checksum"`
	Trigger   string `json:"trigger"`
	Status    string `json:"status"`
	Error     string `json:"error,omitempty"`
	CreatedAt string `json:"created_at"`
}

var state = struct {
	sync.RWMutex
	cfg       Config
	running   bool
	last      Metadata
	lastRunAt time.Time
}{}

func Configure(cfg Config) {
	if cfg.Dir == "" {
		cfg.Dir = "./backups"
	}
	if cfg.RetentionDays <= 0 {
		cfg.RetentionDays = 30
	}
	if cfg.Hour < 0 || cfg.Hour > 23 {
		cfg.Hour = 3
	}
	cfg.PgDumpPath = resolveTool(cfg.PgDumpPath, "pg_dump")
	cfg.PgRestorePath = resolveTool(cfg.PgRestorePath, "pg_restore")
	state.Lock()
	state.cfg = cfg
	state.Unlock()
}

// resolveTool — pg_dump/pg_restore ning haqiqiy yo'lini topadi.
//
// NEGA KERAK: Windows master'da PostgreSQL o'rnatuvchisi `bin` papkasini
// PATH ga qo'shmaydi. Natijada har kechagi avtomatik backup
// `pg_dump: executable file not found in %PATH%` bilan jimgina yiqilib
// turardi — ya'ni backup umuman olinmasdi. Endi PATH da topilmasa
// PostgreSQL ning odatdagi o'rnatish papkalari qidiriladi (eng yangi
// versiya tanlanadi), shu sababli hech qanday sozlamasiz ishlaydi.
//
// `configured` (.env dagi PG_DUMP_PATH) berilgan va mavjud bo'lsa —
// doim u ustun.
func resolveTool(configured, name string) string {
	if configured != "" && configured != name {
		if _, err := os.Stat(configured); err == nil {
			return configured
		}
		log.Printf("BACKUP: %s sozlamadagi yo'lda topilmadi (%s) — o'zim qidiraman", name, configured)
	}
	if p, err := exec.LookPath(name); err == nil {
		return p
	}
	if found := searchPostgresBin(name); found != "" {
		log.Printf("BACKUP: %s topildi — %s", name, found)
		return found
	}
	log.Printf("OGOHLANTIRISH: %s topilmadi — backup ishlamaydi. .env ga %s_PATH kiriting",
		name, strings.ToUpper(name))
	return name
}

// searchPostgresBin — PostgreSQL ning odatdagi o'rnatish papkalarini
// qidiradi va eng yangi versiyadagisini qaytaradi.
func searchPostgresBin(name string) string {
	exe := name
	var patterns []string
	if runtime.GOOS == "windows" {
		exe = name + ".exe"
		patterns = []string{
			`C:\Program Files\PostgreSQL\*\bin\` + exe,
			`C:\Program Files (x86)\PostgreSQL\*\bin\` + exe,
		}
	} else {
		patterns = []string{
			"/usr/lib/postgresql/*/bin/" + exe,
			"/usr/pgsql-*/bin/" + exe,
			"/Library/PostgreSQL/*/bin/" + exe,
			"/opt/homebrew/opt/postgresql*/bin/" + exe,
			"/usr/local/opt/postgresql*/bin/" + exe,
		}
	}

	var found []string
	for _, p := range patterns {
		matches, err := filepath.Glob(p)
		if err != nil {
			continue
		}
		found = append(found, matches...)
	}
	if len(found) == 0 {
		return ""
	}
	// Eng YANGI versiyani tanlaymiz.
	//
	// Ilgari oddiy matn tartibi ishlatilardi va u TESKARI natija berardi:
	// "9.6" matn sifatida "18" dan KATTA ('9' > '1'), ya'ni PostgreSQL 9.6 va
	// 18 birga o'rnatilgan mashinada eng eskisi tanlanardi. pg_dump esa
	// o'zidan yangi serverni zaxiralashdan bosh tortadi — natijada har
	// kechagi backup jimgina yiqilardi.
	sort.Slice(found, func(i, j int) bool {
		return pgVersionOf(found[i]) > pgVersionOf(found[j])
	})
	return found[0]
}

func CurrentConfig() Config {
	state.RLock()
	defer state.RUnlock()
	return state.cfg
}

func Start(ctx context.Context) {
	cfg := CurrentConfig()
	if !cfg.Enabled {
		log.Println("BACKUP: avtomatik backup o'chirilgan")
		return
	}
	if len(cfg.EncryptionKey) < 16 {
		log.Println("BACKUP: shifrlash kaliti yetarli emas, avtomatik backup ishga tushmadi")
		return
	}

	go func() {
		runIfDue(ctx)
		ticker := time.NewTicker(30 * time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				runIfDue(ctx)
			}
		}
	}()
}

func runIfDue(ctx context.Context) {
	cfg := CurrentConfig()
	now := time.Now()
	if now.Hour() < cfg.Hour {
		return
	}
	state.RLock()
	lastRunAt := state.lastRunAt
	state.RUnlock()
	if sameLocalDay(lastRunAt, now) {
		return
	}
	if latest, ok := latestFile(cfg.Dir); ok {
		if created, err := time.Parse(time.RFC3339, latest.CreatedAt); err == nil &&
			sameLocalDay(created.Local(), now) {
			state.Lock()
			state.lastRunAt = now
			state.last = latest
			state.Unlock()
			return
		}
	}
	if _, err := Create(ctx, "automatic", "system"); err != nil {
		log.Printf("BACKUP: avtomatik nusxa xatosi: %v", err)
	}
}

func sameLocalDay(a, b time.Time) bool {
	if a.IsZero() {
		return false
	}
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}

func Create(ctx context.Context, trigger, createdBy string) (Metadata, error) {
	state.Lock()
	if state.running {
		state.Unlock()
		return Metadata{}, errors.New("backup hozir yaratilmoqda")
	}
	state.running = true
	cfg := state.cfg
	state.Unlock()
	defer func() {
		state.Lock()
		state.running = false
		state.lastRunAt = time.Now()
		state.Unlock()
	}()

	if !cfg.Enabled {
		return Metadata{}, errors.New("backup o'chirilgan")
	}
	if len(cfg.EncryptionKey) < 16 {
		return Metadata{}, errors.New("BACKUP_ENCRYPTION_KEY kamida 16 belgidan iborat bo'lishi kerak")
	}
	if err := os.MkdirAll(cfg.Dir, 0o700); err != nil {
		return recordFailure(trigger, createdBy, err), err
	}

	raw, err := os.CreateTemp(cfg.Dir, ".konak-*.dump")
	if err != nil {
		return recordFailure(trigger, createdBy, err), err
	}
	rawPath := raw.Name()
	_ = raw.Close()
	defer os.Remove(rawPath)

	cmd := exec.CommandContext(
		ctx,
		cfg.PgDumpPath,
		"--dbname="+cfg.DBURL,
		"--format=custom",
		"--compress=6",
		"--no-owner",
		"--no-acl",
		"--file="+rawPath,
	)
	if output, err := cmd.CombinedOutput(); err != nil {
		wrapped := fmt.Errorf("pg_dump: %w: %s", err, strings.TrimSpace(string(output)))
		return recordFailure(trigger, createdBy, wrapped), wrapped
	}

	filename := "konak-" + time.Now().UTC().Format("20060102-150405") + ".dump.enc"
	encryptedPath := filepath.Join(cfg.Dir, filename)
	if err := encryptFile(rawPath, encryptedPath, cfg.EncryptionKey); err != nil {
		_ = os.Remove(encryptedPath)
		return recordFailure(trigger, createdBy, err), err
	}
	stat, err := os.Stat(encryptedPath)
	if err != nil {
		return recordFailure(trigger, createdBy, err), err
	}
	checksum, err := fileChecksum(encryptedPath)
	if err != nil {
		return recordFailure(trigger, createdBy, err), err
	}
	meta := Metadata{
		Filename:  filename,
		SizeBytes: stat.Size(),
		Checksum:  checksum,
		Trigger:   trigger,
		Status:    "ready",
		CreatedAt: stat.ModTime().UTC().Format(time.RFC3339),
	}
	record(meta, createdBy)
	state.Lock()
	state.last = meta
	state.Unlock()
	prune(cfg.Dir, cfg.RetentionDays)
	log.Printf("BACKUP: yaratildi %s (%d bytes)", filename, stat.Size())
	return meta, nil
}

func recordFailure(trigger, createdBy string, err error) Metadata {
	meta := Metadata{
		Trigger:   trigger,
		Status:    "failed",
		Error:     err.Error(),
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}
	record(meta, createdBy)
	state.Lock()
	state.last = meta
	state.Unlock()
	return meta
}

func record(meta Metadata, createdBy string) {
	if db.Pool == nil {
		return
	}
	_, _ = db.Pool.Exec(context.Background(), `
		INSERT INTO backups
			(filename,size_bytes,checksum,trigger,status,error_message,created_by,created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
		meta.Filename, meta.SizeBytes, meta.Checksum, meta.Trigger, meta.Status,
		meta.Error, createdBy, meta.CreatedAt,
	)
}

func List() ([]Metadata, error) {
	cfg := CurrentConfig()
	entries, err := os.ReadDir(cfg.Dir)
	if errors.Is(err, os.ErrNotExist) {
		return []Metadata{}, nil
	}
	if err != nil {
		return nil, err
	}
	result := make([]Metadata, 0)
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".dump.enc") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		checksum, _ := fileChecksum(filepath.Join(cfg.Dir, entry.Name()))
		result = append(result, Metadata{
			Filename:  entry.Name(),
			SizeBytes: info.Size(),
			Checksum:  checksum,
			Status:    "ready",
			CreatedAt: info.ModTime().UTC().Format(time.RFC3339),
		})
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt > result[j].CreatedAt
	})
	return result, nil
}

func Status() map[string]interface{} {
	state.RLock()
	defer state.RUnlock()
	return map[string]interface{}{
		"enabled": state.cfg.Enabled,
		"running": state.running,
		"last":    state.last,
	}
}

func FilePath(filename string) (string, error) {
	cfg := CurrentConfig()
	if filepath.Base(filename) != filename || !strings.HasSuffix(filename, ".dump.enc") {
		return "", errors.New("backup fayl nomi noto'g'ri")
	}
	path := filepath.Join(cfg.Dir, filename)
	if _, err := os.Stat(path); err != nil {
		return "", err
	}
	return path, nil
}

func ScheduleRestore(filename string) error {
	cfg := CurrentConfig()
	if filepath.Base(filename) != filename || !strings.HasSuffix(filename, ".dump.enc") {
		return errors.New("backup fayl nomi noto'g'ri")
	}
	path := filepath.Join(cfg.Dir, filename)
	if _, err := os.Stat(path); err != nil {
		return err
	}
	if err := verifyEncryptedFile(path, cfg.EncryptionKey); err != nil {
		return fmt.Errorf("backup tekshiruvi: %w", err)
	}
	marker, _ := json.Marshal(map[string]string{
		"filename":     filename,
		"scheduled_at": time.Now().UTC().Format(time.RFC3339),
	})
	if err := os.MkdirAll(cfg.Dir, 0o700); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(cfg.Dir, restoreMarker), marker, 0o600)
}

// ApplyPendingRestore runs before the application opens its PostgreSQL pool.
// The marker is kept on failure, allowing the next restart to retry safely.
func ApplyPendingRestore(ctx context.Context) error {
	cfg := CurrentConfig()
	markerPath := filepath.Join(cfg.Dir, restoreMarker)
	data, err := os.ReadFile(markerPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var marker struct {
		Filename string `json:"filename"`
	}
	if err := json.Unmarshal(data, &marker); err != nil {
		return err
	}
	if filepath.Base(marker.Filename) != marker.Filename {
		return errors.New("restore marker fayl nomi noto'g'ri")
	}
	encryptedPath := filepath.Join(cfg.Dir, marker.Filename)
	raw, err := os.CreateTemp(cfg.Dir, ".restore-*.dump")
	if err != nil {
		return err
	}
	rawPath := raw.Name()
	_ = raw.Close()
	defer os.Remove(rawPath)

	if err := decryptFile(encryptedPath, rawPath, cfg.EncryptionKey); err != nil {
		return err
	}
	cmd := exec.CommandContext(
		ctx,
		cfg.PgRestorePath,
		"--clean",
		"--if-exists",
		"--no-owner",
		"--no-acl",
		"--dbname="+cfg.DBURL,
		rawPath,
	)
	// Marker HAR QANDAY holatda o'chiriladi — muvaffaqiyat ham, xato ham.
	//
	// Ilgari xato bo'lsa marker qolib ketardi va `main.go` uni `log.Fatal`
	// bilan kutib olardi: server har ishga tushganda o'sha tiklashni qaytadan
	// urinib, qaytadan yiqilardi. Restoran kassasi kimdir SSH bilan kirib
	// faylni qo'lda o'chirmaguncha butunlay ishlamay turardi. Endi xato
	// jurnalga yoziladi, server esa ko'tariladi — bu holatda ishlaydigan
	// kassa ishlamaydiganidan yaxshiroq.
	restoreErr := error(nil)
	if output, err := cmd.CombinedOutput(); err != nil {
		restoreErr = fmt.Errorf("pg_restore: %w: %s", err, strings.TrimSpace(string(output)))
	}
	if err := os.Remove(markerPath); err != nil {
		log.Printf("BACKUP: restore markerini o'chirib bo'lmadi: %v", err)
	}
	if restoreErr != nil {
		log.Printf("XATO: BACKUP TIKLASH MUVAFFAQIYATSIZ (%s): %v", marker.Filename, restoreErr)
		log.Printf("XATO: baza YARIM tiklangan bo'lishi mumkin — ma'lumotni tekshiring!")
		return nil
	}
	log.Printf("BACKUP: %s nusxasi muvaffaqiyatli tiklandi", marker.Filename)
	return nil
}

func encryptFile(sourcePath, destinationPath, password string) error {
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()
	destination, err := os.OpenFile(destinationPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	ok := false
	defer func() {
		_ = destination.Close()
		if !ok {
			_ = os.Remove(destinationPath)
		}
	}()

	salt := make([]byte, backupSaltSize)
	nonceBase := make([]byte, backupNonceBase)
	if _, err := rand.Read(salt); err != nil {
		return err
	}
	if _, err := rand.Read(nonceBase); err != nil {
		return err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, backupIterations, 32)
	if err != nil {
		return err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}
	if _, err := destination.Write([]byte(backupMagic)); err != nil {
		return err
	}
	if _, err := destination.Write(salt); err != nil {
		return err
	}
	if _, err := destination.Write(nonceBase); err != nil {
		return err
	}

	buffer := make([]byte, backupChunkSize)
	var counter uint32
	for {
		n, readErr := source.Read(buffer)
		if n > 0 {
			counter++
			nonce := chunkNonce(nonceBase, counter)
			sealed := gcm.Seal(nil, nonce, buffer[:n], []byte(backupMagic))
			if err := binary.Write(destination, binary.BigEndian, uint32(n)); err != nil {
				return err
			}
			if _, err := destination.Write(sealed); err != nil {
				return err
			}
		}
		if errors.Is(readErr, io.EOF) {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	if err := binary.Write(destination, binary.BigEndian, uint32(0)); err != nil {
		return err
	}
	if err := destination.Sync(); err != nil {
		return err
	}
	ok = true
	return nil
}

func decryptFile(sourcePath, destinationPath, password string) error {
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()
	destination, err := os.OpenFile(destinationPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	ok := false
	defer func() {
		_ = destination.Close()
		if !ok {
			_ = os.Remove(destinationPath)
		}
	}()
	if err := decryptToWriter(source, destination, password); err != nil {
		return err
	}
	if err := destination.Sync(); err != nil {
		return err
	}
	ok = true
	return nil
}

func verifyEncryptedFile(path, password string) error {
	source, err := os.Open(path)
	if err != nil {
		return err
	}
	defer source.Close()
	return decryptToWriter(source, io.Discard, password)
}

func decryptToWriter(source io.Reader, destination io.Writer, password string) error {
	magic := make([]byte, len(backupMagic))
	if _, err := io.ReadFull(source, magic); err != nil || string(magic) != backupMagic {
		return errors.New("backup formati noto'g'ri")
	}
	salt := make([]byte, backupSaltSize)
	nonceBase := make([]byte, backupNonceBase)
	if _, err := io.ReadFull(source, salt); err != nil {
		return err
	}
	if _, err := io.ReadFull(source, nonceBase); err != nil {
		return err
	}
	key, err := pbkdf2.Key(sha256.New, password, salt, backupIterations, 32)
	if err != nil {
		return err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}

	var counter uint32
	for {
		var plainLength uint32
		if err := binary.Read(source, binary.BigEndian, &plainLength); err != nil {
			return fmt.Errorf("backup to'liq emas: %w", err)
		}
		if plainLength == 0 {
			return nil
		}
		if plainLength > backupChunkSize {
			return errors.New("backup chunk hajmi noto'g'ri")
		}
		sealed := make([]byte, int(plainLength)+gcm.Overhead())
		if _, err := io.ReadFull(source, sealed); err != nil {
			return fmt.Errorf("backup to'liq emas: %w", err)
		}
		counter++
		plain, err := gcm.Open(nil, chunkNonce(nonceBase, counter), sealed, []byte(backupMagic))
		if err != nil {
			return errors.New("backup kaliti noto'g'ri yoki fayl buzilgan")
		}
		if _, err := destination.Write(plain); err != nil {
			return err
		}
	}
}

func chunkNonce(base []byte, counter uint32) []byte {
	nonce := make([]byte, 12)
	copy(nonce, base)
	binary.BigEndian.PutUint32(nonce[8:], counter)
	return nonce
}

func fileChecksum(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func latestFile(dir string) (Metadata, bool) {
	_ = dir
	items, err := List()
	if err != nil || len(items) == 0 {
		return Metadata{}, false
	}
	return items[0], true
}

func prune(dir string, retentionDays int) {
	cutoff := time.Now().AddDate(0, 0, -retentionDays)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".dump.enc") {
			continue
		}
		info, err := entry.Info()
		if err == nil && info.ModTime().Before(cutoff) {
			if err := os.Remove(filepath.Join(dir, entry.Name())); err != nil {
				log.Printf("BACKUP: eski faylni o'chirishda xato: %v", err)
			}
		}
	}
}

// pgVersionOf — yo'ldan PostgreSQL versiyasini sonli qiymatga aylantiradi
// ("C:/Program Files/PostgreSQL/9.6/bin/pg_dump.exe" → 906,
//
//	".../18/bin/pg_dump.exe" → 1800). Solishtirish matn emas, SON bo'ladi.
func pgVersionOf(path string) int {
	parts := strings.FieldsFunc(filepath.ToSlash(path), func(r rune) bool { return r == '/' })
	best := -1
	for _, part := range parts {
		major, minor := 0, 0
		if n, _ := fmt.Sscanf(part, "%d.%d", &major, &minor); n >= 1 && major > 0 && major < 100 {
			v := major*100 + minor
			if v > best {
				best = v
			}
		}
	}
	return best
}
