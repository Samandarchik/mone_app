package api

import "testing"

func TestCustomerURLForCode(t *testing.T) {
	orig := customerPublicURL
	defer func() { customerPublicURL = orig }()

	customerPublicURL = ""
	if got := customerURLForCode("abc-123"); got != "https://konak.uz/table/abc-123" {
		t.Errorf("default base: got %q", got)
	}

	customerPublicURL = "https://konak.uz/"
	if got := customerURLForCode("abc-123"); got != "https://konak.uz/table/abc-123" {
		t.Errorf("trailing slash: got %q", got)
	}

	customerPublicURL = "http://192.168.1.5:5174"
	if got := customerURLForCode("a b/c"); got != "http://192.168.1.5:5174/table/a%20b%2Fc" {
		t.Errorf("escape: got %q", got)
	}
}
