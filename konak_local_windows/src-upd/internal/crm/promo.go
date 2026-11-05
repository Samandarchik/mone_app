package crm

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrPromoInvalid  = errors.New("promo kod yaroqsiz")
	ErrPromoInactive = errors.New("promo kod faol emas")
	ErrPromoMinimum  = errors.New("minimal buyurtma summasi yetarli emas")
	ErrPromoLimit    = errors.New("promo kod limiti tugagan")
)

var promoCodePattern = regexp.MustCompile(`^[A-Z0-9_-]{3,32}$`)

type PromoResult struct {
	Code     string `json:"code"`
	Discount int    `json:"discount"`
}

type promoQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

func NormalizePromoCode(raw string) string {
	return strings.ToUpper(strings.TrimSpace(raw))
}

func ValidPromoCode(raw string) bool {
	return promoCodePattern.MatchString(NormalizePromoCode(raw))
}

func CalculatePromoDiscount(
	discountType string,
	value, subtotal int,
	maxDiscount *int,
) int {
	if subtotal <= 0 || value <= 0 {
		return 0
	}
	discount := value
	if discountType == "percent" {
		discount = subtotal * value / 100
	}
	if maxDiscount != nil && *maxDiscount >= 0 && discount > *maxDiscount {
		discount = *maxDiscount
	}
	if discount > subtotal {
		return subtotal
	}
	return discount
}

// ApplyPromo validates a code using a row lock and optionally consumes one use.
// The caller should pass its order transaction when consume is true.
func ApplyPromo(
	ctx context.Context,
	query promoQuerier,
	rawCode string,
	subtotal int,
	consume bool,
) (PromoResult, error) {
	code := NormalizePromoCode(rawCode)
	if !ValidPromoCode(code) {
		return PromoResult{}, ErrPromoInvalid
	}
	lockClause := ""
	if consume {
		lockClause = " FOR UPDATE"
	}
	var discountType, status string
	var value, minTotal, usedCount int
	var maxDiscount, usageLimit *int
	var startsAt, endsAt *time.Time
	err := query.QueryRow(ctx, `
		SELECT discount_type,value,min_order_total,max_discount,starts_at,ends_at,
		       usage_limit,used_count,status
		FROM promo_codes WHERE code=$1`+lockClause,
		code,
	).Scan(
		&discountType, &value, &minTotal, &maxDiscount, &startsAt, &endsAt,
		&usageLimit, &usedCount, &status,
	)
	if err != nil {
		return PromoResult{}, ErrPromoInvalid
	}
	now := time.Now()
	if status != "active" ||
		(startsAt != nil && now.Before(*startsAt)) ||
		(endsAt != nil && !now.Before(*endsAt)) {
		return PromoResult{}, ErrPromoInactive
	}
	if usageLimit != nil && usedCount >= *usageLimit {
		return PromoResult{}, ErrPromoLimit
	}
	if subtotal < minTotal {
		return PromoResult{}, ErrPromoMinimum
	}
	discount := CalculatePromoDiscount(
		discountType,
		value,
		subtotal,
		maxDiscount,
	)
	if consume {
		if _, err := query.Exec(ctx, `
			UPDATE promo_codes
			SET used_count=used_count+1,updated_at=NOW()
			WHERE code=$1`,
			code,
		); err != nil {
			return PromoResult{}, err
		}
	}
	return PromoResult{Code: code, Discount: discount}, nil
}
