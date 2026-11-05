// Package update — local (Windows) serverning o'zini o'zi yangilashi.
//
// Flutter ilova GitHub Releases'dan qanday yangilansa, backend ham bulutdan
// xuddi shunday yangilanadi: bulut har deploy'da Windows binarini artefakt
// sifatida saqlaydi (scripts/deploy-cloud.sh), local node esa har 30 daqiqada
// `/api/update/windows` ni so'rab turadi. Yangi build topilsa:
//
//  1. WSS orqali e'lon qilinadi ("server:update_available") va log yoziladi;
//  2. binar `server.update.exe` nomi bilan yuklab olinadi (sha256 tekshiriladi);
//  3. `apply_update.bat` yozilib detached ishga tushiriladi va server chiqadi;
//  4. bat eski jarayon o'chishini kutadi, eski exe'ni `.bak` qilib, yangisini
//     joyiga qo'yadi va serverni scheduled task orqali qayta ishga tushiradi.
//
// Ishlab turgan exe'ni Windows o'chirishga bermaydi, lekin RENAME qilishga
// ruxsat beradi — Flutter'dagi bilan bir xil hiyla. `.bak` oldingi versiya
// sifatida qoladi (qo'lda rollback uchun).
package update

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"konak-local/internal/db"
	"konak-local/internal/version"
	"konak-local/internal/wss"
)

const (
	checkInterval = 30 * time.Minute
	initialDelay  = time.Minute
)

type artifactInfo struct {
	Version   string `json:"version"`
	BuildUnix int64  `json:"build_unix"`
	SHA256    string `json:"sha256"`
	Size      int64  `json:"size"`
}

// Start — avto-yangilanish siklini ishga tushiradi.
//
// Faqat Windows'dagi dialer (local) node'da yuradi: bulut o'zini systemd +
// deploy skript bilan yangilaydi, Mac'dagi dev-run esa o'zini almashtirib
// yubormasligi kerak. AUTO_UPDATE=false bilan butunlay o'chiriladi.
func Start(syncMode string) {
	if runtime.GOOS != "windows" || syncMode != "dialer" {
		return
	}
	if os.Getenv("AUTO_UPDATE") == "false" {
		log.Println("UPDATE: avto-yangilanish o'chirilgan (AUTO_UPDATE=false)")
		return
	}
	log.Printf("UPDATE: avto-yangilanish yoqilgan (hozirgi versiya: %s)", version.Version)
	go func() {
		time.Sleep(initialDelay)
		for {
			if err := checkOnce(); err != nil {
				log.Printf("UPDATE: %v", err)
			}
			time.Sleep(checkInterval)
		}
	}()
}

func checkOnce() error {
	base, token := cloudHTTPBase()
	if base == "" {
		return nil // offline rejim — cloud URL kiritilmagan
	}

	info, err := fetchInfo(base, token)
	if err != nil {
		return err
	}
	// build_unix qat'iy katta bo'lsagina yangilanamiz: teng/eski artefaktga
	// qaytish (downgrade) va cheksiz yangilanish sikli shu bilan yopiladi.
	if info.BuildUnix == 0 || info.BuildUnix <= version.BuildUnix() {
		return nil
	}

	log.Printf("UPDATE: yangi versiya topildi: %s -> %s, yuklab olinmoqda...",
		version.Version, info.Version)
	if wss.H != nil {
		wss.H.BroadcastEvent("server:update_available", map[string]interface{}{
			"current": version.Version,
			"next":    info.Version,
		})
	}

	newExe, err := download(base, token, info)
	if err != nil {
		return fmt.Errorf("yuklab olishda xato: %w", err)
	}

	if err := applyAndRestart(newExe, info.Version); err != nil {
		return fmt.Errorf("yangilanishni qo'llashda xato: %w", err)
	}
	return nil // bu yerga yetib kelmaydi — applyAndRestart jarayonni yopadi
}

// cloudHTTPBase — sync sozlamasidagi WS manzildan HTTP bazani chiqaradi:
// "wss://konak.uzaidev.uz/sync" -> "https://konak.uzaidev.uz",
// "ws://100.74.167.39:3100/sync" -> "http://100.74.167.39:3100".
// Sozlama super_admin UI orqali o'zgartirilsa keyingi tekshiruvdayoq
// yangi manzil ishlatiladi.
func cloudHTTPBase() (string, string) {
	raw := db.GetSetting("cloud_ws_url")
	if raw == "" {
		return "", ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "", ""
	}
	scheme := "https"
	switch u.Scheme {
	case "ws", "http":
		scheme = "http"
	}
	return scheme + "://" + u.Host, db.GetSetting("cloud_token")
}

func fetchInfo(base, token string) (*artifactInfo, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(base + "/api/update/windows?token=" + url.QueryEscape(token))
	if err != nil {
		return nil, fmt.Errorf("cloud'dan versiya so'rashda xato: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == 404 {
		return &artifactInfo{}, nil // artefakt hali build qilinmagan — jim
	}
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("cloud versiya javobi: HTTP %d", resp.StatusCode)
	}
	var info artifactInfo
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&info); err != nil {
		return nil, fmt.Errorf("windows.json o'qishda xato: %w", err)
	}
	return &info, nil
}

// download — yangi binarni ishlab turgan exe yoniga `server.update.exe`
// nomi bilan tushiradi. Avval `.partial`ga oqim bilan yozilib sha256
// tekshiriladi — chala/buzuq fayl hech qachon almashtirishga bormaydi.
func download(base, token string, info *artifactInfo) (string, error) {
	self, err := os.Executable()
	if err != nil {
		return "", err
	}
	dir := filepath.Dir(self)
	final := filepath.Join(dir, "server.update.exe")
	partial := final + ".partial"

	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Get(base + "/api/update/windows/download?token=" + url.QueryEscape(token))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(partial)
	if err != nil {
		return "", err
	}
	hasher := sha256.New()
	_, err = io.Copy(io.MultiWriter(f, hasher), resp.Body)
	closeErr := f.Close()
	if err != nil {
		os.Remove(partial)
		return "", err
	}
	if closeErr != nil {
		os.Remove(partial)
		return "", closeErr
	}

	sum := hex.EncodeToString(hasher.Sum(nil))
	if !strings.EqualFold(sum, info.SHA256) {
		os.Remove(partial)
		return "", fmt.Errorf("sha256 mos emas: kutilgan %s, kelgan %s", info.SHA256, sum)
	}

	os.Remove(final)
	if err := os.Rename(partial, final); err != nil {
		return "", err
	}
	return final, nil
}

// applyAndRestart — apply_update.bat yozadi, detached ishga tushiradi va
// jarayonni yopadi. Qolganini bat qiladi (pastdagi shablonga qarang).
func applyAndRestart(newExe, newVersion string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	dir := filepath.Dir(self)
	exeName := filepath.Base(self)

	restart := os.Getenv("UPDATE_RESTART_CMD")
	if restart == "" {
		// Windows master'da backend scheduled task orqali yuradi.
		restart = "schtasks /Run /TN KonakBackend"
	}

	// MUHIM: cmd uchun CRLF; pauza `ping` bilan — `timeout /t` konsolsiz
	// (detached) sessiyada qotib qoladi (start-local.bat'dagi ma'lum tuzoq).
	lines := []string{
		"@echo off",
		fmt.Sprintf(`cd /d "%s"`, dir),
		fmt.Sprintf("echo [%%date%% %%time%%] yangilanish %s boshlandi >> update.log", newVersion),
		":wait",
		fmt.Sprintf(`tasklist /FI "PID eq %d" 2>nul | find "%d" >nul`, os.Getpid(), os.Getpid()),
		"if not errorlevel 1 (",
		"  ping -n 2 127.0.0.1 >nul",
		"  goto wait",
		")",
		fmt.Sprintf(`if exist "%s.bak" del /f /q "%s.bak" >> update.log 2>&1`, exeName, exeName),
		fmt.Sprintf(`if exist "%s" ren "%s" "%s.bak" >> update.log 2>&1`, exeName, exeName, exeName),
		fmt.Sprintf(`ren "%s" "%s" >> update.log 2>&1`, filepath.Base(newExe), exeName),
		"echo [%date% %time%] fayl almashtirildi, server qayta ishga tushirilmoqda >> update.log",
		restart + " >> update.log 2>&1",
		"echo [%date% %time%] tayyor >> update.log",
	}
	bat := filepath.Join(dir, "apply_update.bat")
	if err := os.WriteFile(bat, []byte(strings.Join(lines, "\r\n")+"\r\n"), 0755); err != nil {
		return err
	}

	if wss.H != nil {
		wss.H.BroadcastEvent("server:updating", map[string]interface{}{
			"version": newVersion,
		})
	}
	log.Printf("UPDATE: %s o'rnatilmoqda — server qayta ishga tushadi", newVersion)

	if err := spawnDetached(bat); err != nil {
		return err
	}
	// WSS xabari va log yozilib ulgurishi uchun qisqa pauza.
	time.Sleep(500 * time.Millisecond)
	os.Exit(0)
	return nil
}
