//go:build !windows

package api

import (
	"errors"
	"os/exec"
)

// hideCmdWindow — non-Windows platformlarda no-op.
// (Linux/macOS da konsol window flicker muammosi yo'q)
func hideCmdWindow(cmd *exec.Cmd) {
	// no-op
}

// playAudioWindowsHidden — non-Windows da chaqirilmaydi
// (runtime.GOOS switch tomonidan filterlangan), lekin
// kompilyatsiya uchun stub kerak.
func playAudioWindowsHidden(path string) error {
	return errors.New("playAudioWindowsHidden faqat Windows uchun")
}
