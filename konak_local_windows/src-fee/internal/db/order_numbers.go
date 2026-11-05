package db

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type RowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

// nodeTag — ko'p-node sync'da buyurtma raqami to'qnashuvining oldini oladi.
// "local" node raqamlari o'zgarmaydi (26-08-07-P000001); boshqa node'lar
// (masalan cloud) raqam boshiga o'z belgisini oladi: C26-08-07-P000001.
// Belgi bo'lmasa ikkala node ham bir xil raqam yaratib, sync'da bittasi
// jimgina yo'qolardi (ON CONFLICT DO NOTHING).
var nodeTag = ""

// SetNodeTag — main.go da NODE_ID asosida chaqiriladi ("local" → bo'sh).
func SetNodeTag(nodeID string) {
	if nodeID == "" || nodeID == "local" {
		nodeTag = ""
		return
	}
	nodeTag = strings.ToUpper(nodeID[:1])
}

// NextOrderNumber allocates one global, concurrency-safe daily sequence.
// Source is kept in the readable number while uniqueness comes from one counter.
func NextOrderNumber(ctx context.Context, query RowQuerier, source string) (string, error) {
	var day time.Time
	var value int64
	err := query.QueryRow(ctx, `
		INSERT INTO order_daily_counters (business_date,last_value)
		VALUES (CURRENT_DATE,1)
		ON CONFLICT (business_date)
		DO UPDATE SET last_value=order_daily_counters.last_value+1
		RETURNING business_date,last_value`,
	).Scan(&day, &value)
	if err != nil {
		return "", err
	}
	prefix := orderSourcePrefix(source)
	return fmt.Sprintf("%s%s-%s%06d", nodeTag, day.Format("06-01-02"), prefix, value), nil
}

func orderSourcePrefix(source string) string {
	switch strings.ToLower(source) {
	case "qr":
		return "Q"
	case "online":
		return "O"
	default:
		return "P"
	}
}
