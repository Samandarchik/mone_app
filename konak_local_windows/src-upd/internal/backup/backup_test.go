package backup

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestEncryptedBackupRoundTrip(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.dump")
	encrypted := filepath.Join(dir, "backup.dump.enc")
	decrypted := filepath.Join(dir, "restored.dump")
	payload := bytes.Repeat([]byte("konak-pos-backup-data"), 100_000)
	if err := os.WriteFile(source, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := encryptFile(source, encrypted, "a-secure-test-backup-key"); err != nil {
		t.Fatal(err)
	}
	if err := decryptFile(encrypted, decrypted, "a-secure-test-backup-key"); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(decrypted)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("decrypted backup differs from source")
	}
}

func TestEncryptedBackupRejectsWrongKeyAndTampering(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.dump")
	encrypted := filepath.Join(dir, "backup.dump.enc")
	if err := os.WriteFile(source, []byte("important"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := encryptFile(source, encrypted, "correct-test-backup-key"); err != nil {
		t.Fatal(err)
	}
	if err := verifyEncryptedFile(encrypted, "wrong-test-backup-key"); err == nil {
		t.Fatal("wrong key must fail")
	}
	data, err := os.ReadFile(encrypted)
	if err != nil {
		t.Fatal(err)
	}
	data[len(data)-2] ^= 0xff
	if err := os.WriteFile(encrypted, data, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := verifyEncryptedFile(encrypted, "correct-test-backup-key"); err == nil {
		t.Fatal("tampered backup must fail")
	}
}
