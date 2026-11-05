package crm

import (
	"context"
	"errors"
	"strings"
	"unicode"

	"github.com/jackc/pgx/v5"

	"konak-local/internal/db"
)

const loyaltyEarnStep = 10_000

// NormalizePhone stores one searchable phone representation. Local
// Uzbekistan numbers are expanded to the 998 country code.
func NormalizePhone(raw string) string {
	var digits strings.Builder
	for _, r := range raw {
		if unicode.IsDigit(r) {
			digits.WriteRune(r)
		}
	}
	phone := digits.String()
	if len(phone) == 9 {
		phone = "998" + phone
	}
	if len(phone) < 9 || len(phone) > 15 {
		return ""
	}
	return phone
}

// CompleteOrder links a paid order to a customer and applies the automatic
// 1-point-per-10,000-som reward exactly once.
func CompleteOrder(ctx context.Context, orderNumber string) error {
	tx, err := db.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var phone, name, status string
	var total int64
	err = tx.QueryRow(ctx, `
		SELECT COALESCE(customer_phone,''),COALESCE(customer_name,''),status,total
		FROM orders WHERE order_number=$1 FOR UPDATE`,
		orderNumber,
	).Scan(&phone, &name, &status, &total)
	if err != nil {
		return err
	}
	phone = NormalizePhone(phone)
	if status != "completed" || phone == "" {
		return tx.Commit(ctx)
	}

	var customerID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO customers (phone,name)
		VALUES ($1,$2)
		ON CONFLICT (phone) DO UPDATE SET
			name=CASE WHEN EXCLUDED.name<>'' THEN EXCLUDED.name ELSE customers.name END,
			status='active',updated_at=NOW()
		RETURNING id`,
		phone, strings.TrimSpace(name),
	).Scan(&customerID)
	if err != nil {
		return err
	}

	var currentBalance int64
	if err := tx.QueryRow(ctx,
		"SELECT loyalty_points FROM customers WHERE id=$1 FOR UPDATE",
		customerID,
	).Scan(&currentBalance); err != nil {
		return err
	}
	earned := total / loyaltyEarnStep
	balanceAfter := currentBalance + earned

	var transactionID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO loyalty_transactions
			(customer_id,order_number,type,points,balance_after,note,created_by)
		VALUES ($1,$2,'earn',$3,$4,'Avtomatik cashback','system')
		ON CONFLICT DO NOTHING
		RETURNING id`,
		customerID, orderNumber, earned, balanceAfter,
	).Scan(&transactionID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if err == nil {
		if _, err := tx.Exec(ctx, `
			UPDATE customers SET
				loyalty_points=$1,total_spent=total_spent+$2,
				visit_count=visit_count+1,last_visit_at=NOW(),updated_at=NOW()
			WHERE id=$3`,
			balanceAfter, total, customerID,
		); err != nil {
			return err
		}
	}

	if _, err := tx.Exec(ctx, `
		UPDATE orders SET customer_id=$1,loyalty_points_earned=$2
		WHERE order_number=$3`,
		customerID, earned, orderNumber,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
