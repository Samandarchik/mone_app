package api

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestParseAnalyticsRangeDefaultsToSevenDays(t *testing.T) {
	now := time.Date(2026, 7, 25, 18, 0, 0, 0, time.Local)
	got, err := parseAnalyticsRange("", "", now)
	if err != nil {
		t.Fatal(err)
	}
	if got.From != "2026-07-19" || got.To != "2026-07-25" || got.Days != 7 {
		t.Fatalf("unexpected range: %+v", got)
	}
}

func TestParseAnalyticsRangeRejectsInvalidRange(t *testing.T) {
	now := time.Date(2026, 7, 25, 18, 0, 0, 0, time.Local)
	if _, err := parseAnalyticsRange("2026-07-26", "2026-07-25", now); err == nil {
		t.Fatal("expected reversed range to fail")
	}
	if _, err := parseAnalyticsRange("2025-01-01", "2026-07-25", now); err == nil {
		t.Fatal("expected oversized range to fail")
	}
}

func TestAnalyticsItemsSummaryUsesSnapshotAndQuantity(t *testing.T) {
	items, err := json.Marshal([]map[string]interface{}{
		{
			"product_id": 7,
			"quantity":   2,
			"snapshot": map[string]interface{}{
				"name": map[string]string{"uz": "Lag'mon"},
			},
		},
		{"product_id": 9, "quantity": 0},
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := analyticsItemsSummary(items); got != "Lag'mon x2" {
		t.Fatalf("unexpected summary: %q", got)
	}
}

func TestAnalyticsPaymentSummaryFormatsSplitPayment(t *testing.T) {
	got := analyticsPaymentSummary(
		"split",
		[]byte(`[{"method":"cash","amount":12000},{"method":"card","amount":8000}]`),
	)
	if !strings.Contains(got, "cash: 12000") ||
		!strings.Contains(got, "card: 8000") {
		t.Fatalf("unexpected payment summary: %q", got)
	}
}
