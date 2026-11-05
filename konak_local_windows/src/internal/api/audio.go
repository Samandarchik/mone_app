package api

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
)

// ============================================================
// Stol chaqirish uchun audio o'ynatish (m4a)
//
// Audio fayllar joylashuvi: <project>/m4a/
//   - zone fayllari: zal.m4a, tashqari.m4a (lowercase)
//   - raqam fayllari: 1.m4a ... 16.m4a
//
// Label format DB da: "ZAL-3", "TASHQARI-5"
// Audio ketma-ketligi: <zone>.m4a → <num>.m4a
//
// Cross-platform:
//   darwin  — afplay (built-in)
//   windows — PowerShell + System.Windows.Media.MediaPlayer (WPF)
//             oyna ko'rsatmasdan, hech qanday player ochmasdan ishlaydi
//             (HideWindow + CREATE_NO_WINDOW bayroqlari, audio_windows.go)
//   linux   — ffplay (ffmpeg) yoki mpg123
// ============================================================

var (
	audioMu sync.Mutex // bir vaqtda faqat bitta chaqirish ovozi

	m4aDirOnce sync.Once
	m4aDir     string
)

// resolveM4ADir — m4a papkasini topadi.
// 1. M4A_DIR env (agar berilgan bo'lsa)
// 2. Joriy ish papkasidan boshlab 5 daraja yuqoriga qarab `m4a/` izlash
// 3. Fallback: <CWD>/m4a
func resolveM4ADir() string {
	m4aDirOnce.Do(func() {
		if env := os.Getenv("M4A_DIR"); env != "" {
			if abs, err := filepath.Abs(env); err == nil {
				m4aDir = abs
				return
			}
		}
		cwd, _ := os.Getwd()
		dir := cwd
		for i := 0; i < 5; i++ {
			candidate := filepath.Join(dir, "m4a")
			if st, err := os.Stat(candidate); err == nil && st.IsDir() {
				m4aDir = candidate
				return
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
		m4aDir = filepath.Join(cwd, "m4a")
	})
	return m4aDir
}

// playTableCall — stolni ovoz bilan chaqirish.
// label: "ZAL-3", "TASHQARI-5" ko'rinishida.
func playTableCall(label string) {
	parts := strings.SplitN(label, "-", 2)
	if len(parts) != 2 {
		log.Printf("AUDIO: noto'g'ri label format: %q", label)
		return
	}
	zone := strings.ToLower(strings.TrimSpace(parts[0]))
	num, err := strconv.Atoi(strings.TrimSpace(parts[1]))
	if err != nil {
		log.Printf("AUDIO: raqam parse xatosi: %q", label)
		return
	}

	dir := resolveM4ADir()
	zonePath := filepath.Join(dir, zone+".m4a")
	numPath := filepath.Join(dir, fmt.Sprintf("%d.m4a", num))

	files := []string{}
	if fileExists(zonePath) {
		files = append(files, zonePath)
	} else {
		log.Printf("AUDIO: zone fayli topilmadi: %s", zonePath)
	}
	if fileExists(numPath) {
		files = append(files, numPath)
	} else {
		log.Printf("AUDIO: raqam fayli topilmadi: %s", numPath)
	}

	if len(files) == 0 {
		return
	}

	go func() {
		audioMu.Lock()
		defer audioMu.Unlock()
		for _, f := range files {
			if err := playAudioFile(f); err != nil {
				log.Printf("AUDIO: %s o'ynatishda xato: %v", f, err)
			}
		}
	}()
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

// playAudioFile — bitta m4a faylni o'ynatadi va u tugaguncha kutadi.
func playAudioFile(path string) error {
	switch runtime.GOOS {
	case "darwin":
		cmd := exec.Command("afplay", path)
		hideCmdWindow(cmd)
		return cmd.Run()

	case "windows":
		return playAudioWindowsHidden(path)

	default:
		// Linux: ffplay yoki mpg123
		var cmd *exec.Cmd
		if _, err := exec.LookPath("ffplay"); err == nil {
			cmd = exec.Command("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path)
		} else if _, err := exec.LookPath("mpg123"); err == nil {
			cmd = exec.Command("mpg123", "-q", path)
		} else {
			return fmt.Errorf("audio player topilmadi (ffplay yoki mpg123 o'rnating)")
		}
		hideCmdWindow(cmd)
		return cmd.Run()
	}
}

// buildWindowsPlayScript — Windows uchun PowerShell skriptini yaratadi.
// System.Windows.Media.MediaPlayer (WPF) hech qanday UI ochmaydi —
// audio fonda ishlaydi.
func buildWindowsPlayScript(path string) string {
	uri := "file:///" + strings.ReplaceAll(path, "\\", "/")
	return fmt.Sprintf(`Add-Type -AssemblyName presentationCore
$mp = New-Object System.Windows.Media.MediaPlayer
$mp.Open([Uri]'%s')
$wait = 50
while (-not $mp.NaturalDuration.HasTimeSpan -and $wait -gt 0) {
  Start-Sleep -Milliseconds 100
  $wait--
}
$mp.Play()
if ($mp.NaturalDuration.HasTimeSpan) {
  $totalMs = [int]$mp.NaturalDuration.TimeSpan.TotalMilliseconds
  Start-Sleep -Milliseconds ($totalMs + 200)
} else {
  Start-Sleep -Milliseconds 3000
}
$mp.Stop()
$mp.Close()`, uri)
}
