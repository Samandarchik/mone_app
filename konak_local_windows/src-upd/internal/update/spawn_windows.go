//go:build windows

package update

import (
	"os/exec"
	"syscall"
)

// spawnDetached — bat'ni serverdan butunlay ajratilgan holda ishga tushiradi:
// server os.Exit qilganda bat o'lib qolmasligi kerak (u aynan server
// o'chishini kutib turadi).
func spawnDetached(path string) error {
	cmd := exec.Command("cmd.exe", "/C", path)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow: true,
		// DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
		CreationFlags: 0x00000008 | 0x00000200,
	}
	return cmd.Start()
}
