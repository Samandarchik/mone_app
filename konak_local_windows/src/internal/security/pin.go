package security

import (
	"crypto/hmac"
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"sync"
)

const (
	pinIterations = 210_000
	pinSaltSize   = 16
	pinKeySize    = 32
)

var (
	pinPepper []byte
	pepperMu  sync.RWMutex
)

// ConfigurePINPepper configures the server-side secret used both for the
// deterministic lookup fingerprint and as an extra secret input to PBKDF2.
// A database dump alone is therefore not enough to brute-force four-digit PINs.
func ConfigurePINPepper(pepper string) {
	pepperMu.Lock()
	pinPepper = []byte(pepper)
	pepperMu.Unlock()
}

func currentPepper() ([]byte, error) {
	pepperMu.RLock()
	defer pepperMu.RUnlock()
	if len(pinPepper) < 16 {
		return nil, errors.New("PIN_PEPPER kamida 16 belgidan iborat bo'lishi kerak")
	}
	out := make([]byte, len(pinPepper))
	copy(out, pinPepper)
	return out, nil
}

func ValidatePIN(pin string) bool {
	if len(pin) != 4 {
		return false
	}
	for _, r := range pin {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// PINFingerprint is deterministic and lets PIN-only login find the matching
// row without storing the original PIN. It must never be returned by the API.
func PINFingerprint(pin string) (string, error) {
	if !ValidatePIN(pin) {
		return "", errors.New("PIN 4 xonali raqam bo'lishi kerak")
	}
	pepper, err := currentPepper()
	if err != nil {
		return "", err
	}
	mac := hmac.New(sha256.New, pepper)
	_, _ = mac.Write([]byte("konak-pos-pin-lookup:" + pin))
	return "fp$" + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), nil
}

func HashPIN(pin string) (string, error) {
	if !ValidatePIN(pin) {
		return "", errors.New("PIN 4 xonali raqam bo'lishi kerak")
	}
	pepper, err := currentPepper()
	if err != nil {
		return "", err
	}
	salt := make([]byte, pinSaltSize)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := pbkdf2.Key(sha256.New, pin+string(pepper), salt, pinIterations, pinKeySize)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf(
		"pbkdf2_sha256$%d$%s$%s",
		pinIterations,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

func VerifyPIN(pin, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 4 || parts[0] != "pbkdf2_sha256" || !ValidatePIN(pin) {
		return false
	}
	iterations, err := strconv.Atoi(parts[1])
	if err != nil || iterations < 100_000 || iterations > 2_000_000 {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[2])
	if err != nil || len(salt) < 8 {
		return false
	}
	expected, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil || len(expected) != pinKeySize {
		return false
	}
	pepper, err := currentPepper()
	if err != nil {
		return false
	}
	actual, err := pbkdf2.Key(sha256.New, pin+string(pepper), salt, iterations, len(expected))
	if err != nil {
		return false
	}
	return subtle.ConstantTimeCompare(actual, expected) == 1
}
