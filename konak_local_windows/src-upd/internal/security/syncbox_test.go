package security

import (
	"encoding/base64"
	"strings"
	"testing"
)

func TestSealOpenRoundTrip(t *testing.T) {
	ConfigureSyncSecret("test-sync-token-0123456789")
	sealed, err := SealForSync("2502")
	if err != nil {
		t.Fatalf("SealForSync: %v", err)
	}
	if strings.Contains(sealed, "2502") {
		t.Fatal("shifrlangan matn ichida ochiq PIN ko'rinmasligi kerak")
	}
	got, err := OpenFromSync(sealed)
	if err != nil {
		t.Fatalf("OpenFromSync: %v", err)
	}
	if got != "2502" {
		t.Fatalf("kutilgan 2502, olindi %q", got)
	}
}

func TestSealIsRandomized(t *testing.T) {
	ConfigureSyncSecret("test-sync-token-0123456789")
	a, _ := SealForSync("1234")
	b, _ := SealForSync("1234")
	if a == b {
		t.Fatal("bir xil matn har safar bir xil shifrlanmasligi kerak (nonce)")
	}
}

func TestOpenWithWrongSecretFails(t *testing.T) {
	ConfigureSyncSecret("test-sync-token-0123456789")
	sealed, _ := SealForSync("2502")

	ConfigureSyncSecret("boshqa-sync-token-98765432")
	if _, err := OpenFromSync(sealed); err == nil {
		t.Fatal("boshqa kalit bilan ochilmasligi kerak")
	}
}

func TestOpenRejectsTamperedPayload(t *testing.T) {
	ConfigureSyncSecret("test-sync-token-0123456789")
	sealed, _ := SealForSync("2502")

	raw, _ := base64.StdEncoding.DecodeString(sealed)
	raw[len(raw)-1] ^= 0xFF
	if _, err := OpenFromSync(base64.StdEncoding.EncodeToString(raw)); err == nil {
		t.Fatal("buzilgan payload qabul qilinmasligi kerak")
	}
}

func TestShortSecretRejected(t *testing.T) {
	ConfigureSyncSecret("qisqa")
	if SyncSecretReady() {
		t.Fatal("qisqa kalit tayyor deb hisoblanmasligi kerak")
	}
	if _, err := SealForSync("1234"); err == nil {
		t.Fatal("qisqa kalit bilan shifrlash xato qaytarishi kerak")
	}
}
