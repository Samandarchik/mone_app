package crm

import "testing"

func TestNormalizePhone(t *testing.T) {
	tests := map[string]string{
		"+998 90 123-45-67": "998901234567",
		"90 123 45 67":      "998901234567",
		"123":               "",
	}
	for input, want := range tests {
		if got := NormalizePhone(input); got != want {
			t.Fatalf("NormalizePhone(%q)=%q, want %q", input, got, want)
		}
	}
}

func TestCalculatePromoDiscount(t *testing.T) {
	max := 12_000
	if got := CalculatePromoDiscount("percent", 20, 100_000, &max); got != max {
		t.Fatalf("capped percent discount=%d, want %d", got, max)
	}
	if got := CalculatePromoDiscount("fixed", 30_000, 20_000, nil); got != 20_000 {
		t.Fatalf("fixed discount=%d, want subtotal", got)
	}
}

func TestValidPromoCode(t *testing.T) {
	if !ValidPromoCode(" yoz-2026 ") {
		t.Fatal("expected normalized code to be valid")
	}
	if ValidPromoCode("a b") {
		t.Fatal("spaces must be rejected")
	}
}
