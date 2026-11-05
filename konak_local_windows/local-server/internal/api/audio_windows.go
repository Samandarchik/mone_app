//go:build windows

package api

import (
	"os/exec"
	"syscall"
)

// CREATE_NO_WINDOW = 0x08000000 — Windows API, jarayon hech qanday
// console window yaratmaydi. HideWindow + CREATE_NO_WINDOW birgalikda
// to'liq ko'rinmas (silent) ishni ta'minlaydi.
const createNoWindow = 0x08000000

// hideCmdWindow — Windows da exec.Cmd ni butunlay ko'rinmas qiladi.
// PowerShell oynasi flicker (yaltiroq) qilmaydi.
func hideCmdWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: createNoWindow,
	}
}

// playAudioWindowsHidden — Windows da m4a faylni butunlay fonda
// o'ynatadi: PowerShell oynasi ham, Windows Media Player ham,
// hech qanday UI ko'rinmaydi. WPF MediaPlayer ichki audio session
// orqali Windows audio service'ga yuboradi.
func playAudioWindowsHidden(path string) error {
	script := buildWindowsPlayScript(path)
	cmd := exec.Command(
		"powershell",
		"-NoProfile",
		"-NonInteractive",
		"-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass",
		"-Command", script,
	)
	hideCmdWindow(cmd)
	return cmd.Run()
}
