package security

import "testing"

func TestPINHashAndFingerprint(t *testing.T) {
	ConfigurePINPepper("test-pepper-that-is-long-enough")

	hash, err := HashPIN("1234")
	if err != nil {
		t.Fatalf("HashPIN: %v", err)
	}
	if !VerifyPIN("1234", hash) {
		t.Fatal("correct PIN must verify")
	}
	if VerifyPIN("4321", hash) {
		t.Fatal("wrong PIN must not verify")
	}

	fp1, err := PINFingerprint("1234")
	if err != nil {
		t.Fatalf("PINFingerprint: %v", err)
	}
	fp2, _ := PINFingerprint("1234")
	fp3, _ := PINFingerprint("4321")
	if fp1 != fp2 || fp1 == fp3 {
		t.Fatal("fingerprint must be deterministic and PIN-specific")
	}
}

func TestValidatePIN(t *testing.T) {
	for _, pin := range []string{"", "123", "12345", "12a4", "１２３４"} {
		if ValidatePIN(pin) {
			t.Fatalf("%q must be invalid", pin)
		}
	}
	if !ValidatePIN("0000") {
		t.Fatal("four ASCII digits must be valid")
	}
}
