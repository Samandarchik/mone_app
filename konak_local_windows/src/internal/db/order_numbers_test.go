package db

import "testing"

func TestOrderSourcePrefix(t *testing.T) {
	for source, want := range map[string]string{
		"pos": "P", "qr": "Q", "online": "O", "unknown": "P",
	} {
		if got := orderSourcePrefix(source); got != want {
			t.Fatalf("%s prefix: got %s want %s", source, got, want)
		}
	}
}
