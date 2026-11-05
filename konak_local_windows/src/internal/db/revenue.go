package db

import (
	"context"
	"log"
)

// paymentTotals — usul bo'yicha tushum (so'm, int). Aralash (split) to'lovlar ham
// to'g'ri bucketlarga qo'shiladi:
//   - payments IS NULL bo'lgan (oddiy) orderlar payment_method bo'yicha SUM(total),
//   - split orderlarning payments JSONB elementlari method bo'yicha SUM(amount).
//
// window — faqat shu paketdagi konstantalar ("created_at >= $1" / kun oynasi).
//
// XATO YUTILMAYDI. Ilgari har qanday xatoda BO'SH map qaytarilardi va bu
// jimgina eng og'ir oqibatga olib kelardi: smena yopilganda
// `CalculateShiftSummarySince` shu bucketlardan tushumni hisoblab,
// `shifts.summary` ga NOL yozardi. Kassir 4,5 mln so'm topshirib, hisobotda
// "kamomad 4,5 mln" bo'lib qolardi va buni hech kim sabab bilan bog'lay
// olmasdi. Endi chaqiruvchi xatoni ko'radi va hisobot umuman yozilmaydi.
func paymentTotals(ctx context.Context, window string, arg interface{}) (map[string]int, error) {
	q := `SELECT m, COALESCE(SUM(a), 0) FROM (
		SELECT payment_method AS m, total AS a FROM orders
		 WHERE ` + window + ` AND status = 'completed' AND payment_status = 'paid'
		   AND payments IS NULL AND payment_method IS NOT NULL
		UNION ALL
		SELECT p->>'method', (p->>'amount')::int FROM orders
		 CROSS JOIN LATERAL jsonb_array_elements(
		   CASE WHEN jsonb_typeof(payments)='array'
		     THEN payments ELSE '[]'::jsonb END
		 ) p
		 WHERE ` + window + ` AND status = 'completed' AND payment_status = 'paid'
	) t GROUP BY m`

	totals := map[string]int{}
	rows, err := Pool.Query(ctx, q, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var m string
		var a int
		if err := rows.Scan(&m, &a); err != nil {
			return nil, err
		}
		totals[m] = a
	}
	// `rows.Err()` — SHART: oqim o'rtasida uzilgan so'rov shusiz "hammasi
	// o'qildi" bo'lib ko'rinardi va tushumning bir qismi jimgina yo'qolardi.
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return totals, nil
}

// PaymentTotalsSince — smena oynasi: created_at >= since (RFC3339 string yoki time).
func PaymentTotalsSince(ctx context.Context, since interface{}) (map[string]int, error) {
	return paymentTotals(ctx, "created_at >= $1", since)
}

// PaymentTotalsByDate — kunlik oyna ("2006-01-02").
//
// `created_at::date = $1` EMAS, oraliq sharti ishlatiladi: cast qilingan
// ustun indeksga tushmaydi va har bir moliya ekrani butun `orders` jadvalini
// to'liq skanerlardi.
func PaymentTotalsByDate(ctx context.Context, date string) (map[string]int, error) {
	return paymentTotals(ctx,
		"created_at >= $1::date AND created_at < ($1::date + INTERVAL '1 day')", date)
}

// PaymentTotalsOrZero — xatoni jurnal qilib, bo'sh natija qaytaradi.
// FAQAT ko'rsatuvchi (read-only) joylarda ishlatiladi; pul yozadigan yo'lda
// (smena yopish) HECH QACHON ishlatilmaydi.
func PaymentTotalsOrZero(ctx context.Context, totals map[string]int, err error, where string) map[string]int {
	if err != nil {
		log.Printf("REVENUE: %s — to'lov summalari o'qilmadi: %v", where, err)
		return map[string]int{}
	}
	return totals
}
