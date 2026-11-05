package audit

import "testing"

func TestSanitizeJSON(t *testing.T) {
	value := SanitizeJSON([]byte(`{
		"name":"Ali",
		"pin":"1234",
		"nested":{"cloud_token":"secret","amount":42}
	}`))
	root := value.(map[string]interface{})
	if root["pin"] != "[REDACTED]" {
		t.Fatal("PIN must be redacted")
	}
	nested := root["nested"].(map[string]interface{})
	if nested["cloud_token"] != "[REDACTED]" || nested["amount"].(float64) != 42 {
		t.Fatal("nested secrets must be redacted without removing safe fields")
	}
}
