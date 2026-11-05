package api

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"konak-local/internal/db"
)

const analyticsMaxDays = 366

type analyticsDateRange struct {
	From string
	To   string
	Days int
}

type analyticsDay struct {
	Date      string
	Revenue   int64
	Orders    int64
	Cancelled int64
	Discount  int64
	Expenses  int64
	Cost      int64
}

type analyticsProductCost struct {
	PieceCost  int64
	Incomplete bool
}

type analyticsProductSale struct {
	ProductID  int
	Category   int
	Name       string
	Quantity   int64
	Revenue    int64
	Cost       int64
	Incomplete bool
}

type analyticsCategorySale struct {
	CategoryID int
	Name       string
	Quantity   int64
	Revenue    int64
}

type analyticsOrderItem struct {
	ProductID int             `json:"product_id"`
	Snapshot  json.RawMessage `json:"snapshot"`
	Quantity  int64           `json:"quantity"`
	Price     int64           `json:"price"`
	Total     int64           `json:"total"`
}

type analyticsProductSnapshot struct {
	Name       map[string]string `json:"name"`
	CategoryID int               `json:"category_id"`
}

func parseAnalyticsRange(fromRaw, toRaw string, now time.Time) (analyticsDateRange, error) {
	today, _ := time.Parse("2006-01-02", now.Format("2006-01-02"))
	var fromDate, toDate time.Time
	var err error

	if strings.TrimSpace(toRaw) == "" {
		toDate = today
	} else {
		toDate, err = time.Parse("2006-01-02", strings.TrimSpace(toRaw))
		if err != nil {
			return analyticsDateRange{}, errors.New("to sanasi YYYY-MM-DD formatida bo'lishi kerak")
		}
	}
	if strings.TrimSpace(fromRaw) == "" {
		fromDate = toDate.AddDate(0, 0, -6)
	} else {
		fromDate, err = time.Parse("2006-01-02", strings.TrimSpace(fromRaw))
		if err != nil {
			return analyticsDateRange{}, errors.New("from sanasi YYYY-MM-DD formatida bo'lishi kerak")
		}
	}
	if fromDate.After(toDate) {
		return analyticsDateRange{}, errors.New("Boshlanish sanasi tugash sanasidan keyin bo'lmaydi")
	}
	days := int(toDate.Sub(fromDate).Hours()/24) + 1
	if days > analyticsMaxDays {
		return analyticsDateRange{}, fmt.Errorf("Hisobot oralig'i %d kundan oshmasligi kerak", analyticsMaxDays)
	}
	return analyticsDateRange{
		From: fromDate.Format("2006-01-02"),
		To:   toDate.Format("2006-01-02"),
		Days: days,
	}, nil
}

func analyticsRangeFromRequest(r *http.Request) (analyticsDateRange, error) {
	return parseAnalyticsRange(
		r.URL.Query().Get("from"),
		r.URL.Query().Get("to"),
		time.Now(),
	)
}

func handleAnalyticsOverview(w http.ResponseWriter, r *http.Request) {
	dateRange, err := analyticsRangeFromRequest(r)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}
	report, err := buildAnalyticsOverview(r.Context(), dateRange)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	jsonResponse(w, http.StatusOK, report)
}

func buildAnalyticsOverview(
	ctx context.Context,
	dateRange analyticsDateRange,
) (map[string]interface{}, error) {
	var completed, cancelled, revenue, discounts int64
	var identifiedOrders, uniqueCustomers int64
	err := db.Pool.QueryRow(ctx, `
		SELECT
		  COUNT(*) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),
		  COUNT(*) FILTER (WHERE status='cancelled'),
		  COALESCE(SUM(total) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),0),
		  COALESCE(SUM(discount) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),0),
		  COUNT(*) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		      AND COALESCE(customer_phone,'')<>''
		  ),
		  COUNT(DISTINCT customer_phone) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		      AND COALESCE(customer_phone,'')<>''
		  )
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'`,
		dateRange.From, dateRange.To,
	).Scan(
		&completed, &cancelled, &revenue, &discounts,
		&identifiedOrders, &uniqueCustomers,
	)
	if err != nil {
		return nil, err
	}

	var expenses int64
	if err := db.Pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount),0)
		FROM expenses
		WHERE date::date BETWEEN $1::date AND $2::date`,
		dateRange.From, dateRange.To,
	).Scan(&expenses); err != nil {
		return nil, err
	}

	days := make(map[string]*analyticsDay, dateRange.Days)
	fromDate, _ := time.Parse("2006-01-02", dateRange.From)
	for offset := 0; offset < dateRange.Days; offset++ {
		date := fromDate.AddDate(0, 0, offset).Format("2006-01-02")
		days[date] = &analyticsDay{Date: date}
	}
	if err := loadAnalyticsDailyOrders(ctx, dateRange, days); err != nil {
		return nil, err
	}
	if err := loadAnalyticsDailyExpenses(ctx, dateRange, days); err != nil {
		return nil, err
	}

	costs, err := loadAnalyticsProductCosts(ctx)
	if err != nil {
		return nil, err
	}
	productSales, totalCost, incompleteProducts, err := loadAnalyticsProductSales(
		ctx, dateRange, costs, days,
	)
	if err != nil {
		return nil, err
	}
	categoryNames, err := loadAnalyticsCategoryNames(ctx)
	if err != nil {
		return nil, err
	}

	trend := make([]map[string]interface{}, 0, len(days))
	for offset := 0; offset < dateRange.Days; offset++ {
		date := fromDate.AddDate(0, 0, offset).Format("2006-01-02")
		day := days[date]
		trend = append(trend, map[string]interface{}{
			"date": day.Date, "orders": day.Orders,
			"cancelled_orders": day.Cancelled,
			"revenue":          day.Revenue, "discount": day.Discount,
			"expenses": day.Expenses, "estimated_cogs": day.Cost,
			"net_profit": day.Revenue - day.Cost - day.Expenses,
		})
	}

	topProducts := analyticsTopProducts(productSales)
	topCategories := analyticsTopCategories(productSales, categoryNames)
	byType, err := loadAnalyticsOrderBreakdown(ctx, dateRange, "type")
	if err != nil {
		return nil, err
	}
	bySource, err := loadAnalyticsOrderBreakdown(ctx, dateRange, "source")
	if err != nil {
		return nil, err
	}
	byPayment, err := loadAnalyticsPayments(ctx, dateRange)
	if err != nil {
		return nil, err
	}
	peakHours, err := loadAnalyticsPeakHours(ctx, dateRange)
	if err != nil {
		return nil, err
	}

	var newCustomers, returningCustomers int64
	if err := db.Pool.QueryRow(ctx, `
		SELECT
		  COUNT(*) FILTER (
		    WHERE created_at::date BETWEEN $1::date AND $2::date
		  ),
		  COUNT(*) FILTER (
		    WHERE visit_count>1
		      AND last_visit_at::date BETWEEN $1::date AND $2::date
		  )
		FROM customers
		WHERE status='active'`,
		dateRange.From, dateRange.To,
	).Scan(&newCustomers, &returningCustomers); err != nil {
		return nil, err
	}

	averageCheck := int64(0)
	if completed > 0 {
		averageCheck = revenue / completed
	}
	grossProfit := revenue - totalCost
	netProfit := grossProfit - expenses
	return map[string]interface{}{
		"range": map[string]interface{}{
			"from": dateRange.From, "to": dateRange.To, "days": dateRange.Days,
		},
		"summary": map[string]interface{}{
			"completed_orders": completed, "cancelled_orders": cancelled,
			"revenue": revenue, "average_check": averageCheck,
			"discounts": discounts, "expenses": expenses,
			"estimated_cogs": totalCost, "gross_profit": grossProfit,
			"net_profit":               netProfit,
			"incomplete_cost_products": incompleteProducts,
		},
		"customers": map[string]interface{}{
			"identified_orders":   identifiedOrders,
			"unique_customers":    uniqueCustomers,
			"new_customers":       newCustomers,
			"returning_customers": returningCustomers,
		},
		"trend": trend, "by_type": byType, "by_source": bySource,
		"by_payment": byPayment, "peak_hours": peakHours,
		"top_products": topProducts, "top_categories": topCategories,
	}, nil
}

func loadAnalyticsDailyOrders(
	ctx context.Context,
	dateRange analyticsDateRange,
	days map[string]*analyticsDay,
) error {
	rows, err := db.Pool.Query(ctx, `
		SELECT created_at::date::text,
		  COUNT(*) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),
		  COUNT(*) FILTER (WHERE status='cancelled'),
		  COALESCE(SUM(total) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),0),
		  COALESCE(SUM(discount) FILTER (
		    WHERE status='completed' AND payment_status='paid'
		  ),0)
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'
		GROUP BY created_at::date
		ORDER BY created_at::date`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var date string
		var orders, cancelled, revenue, discount int64
		if err := rows.Scan(
			&date, &orders, &cancelled, &revenue, &discount,
		); err != nil {
			return err
		}
		if day := days[date]; day != nil {
			day.Orders = orders
			day.Cancelled = cancelled
			day.Revenue = revenue
			day.Discount = discount
		}
	}
	return rows.Err()
}

func loadAnalyticsDailyExpenses(
	ctx context.Context,
	dateRange analyticsDateRange,
	days map[string]*analyticsDay,
) error {
	rows, err := db.Pool.Query(ctx, `
		SELECT date::date::text,COALESCE(SUM(amount),0)
		FROM expenses
		WHERE date::date BETWEEN $1::date AND $2::date
		GROUP BY date::date`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var date string
		var amount int64
		if err := rows.Scan(&date, &amount); err != nil {
			return err
		}
		if day := days[date]; day != nil {
			day.Expenses = amount
		}
	}
	return rows.Err()
}

func loadAnalyticsProductCosts(
	ctx context.Context,
) (map[int]analyticsProductCost, error) {
	prices, err := loadIngPriceInfo(ctx)
	if err != nil {
		return nil, err
	}
	rows, err := db.Pool.Query(ctx, `
		SELECT product_id,batch_qty,items FROM recipes`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int]analyticsProductCost{}
	for rows.Next() {
		var productID, batchQty int
		var itemsJSON []byte
		if err := rows.Scan(&productID, &batchQty, &itemsJSON); err != nil {
			return nil, err
		}
		items := []RecipeItem{}
		if err := json.Unmarshal(itemsJSON, &items); err != nil {
			out[productID] = analyticsProductCost{Incomplete: true}
			continue
		}
		_, pieceCost, _, incomplete := recipeCost(batchQty, items, prices)
		out[productID] = analyticsProductCost{
			PieceCost: pieceCost, Incomplete: incomplete,
		}
	}
	return out, rows.Err()
}

func loadAnalyticsProductSales(
	ctx context.Context,
	dateRange analyticsDateRange,
	costs map[int]analyticsProductCost,
	days map[string]*analyticsDay,
) (map[int]*analyticsProductSale, int64, int, error) {
	rows, err := db.Pool.Query(ctx, `
		SELECT created_at::date::text,items
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'
		  AND status='completed' AND payment_status='paid'`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return nil, 0, 0, err
	}
	defer rows.Close()
	sales := map[int]*analyticsProductSale{}
	incomplete := map[int]bool{}
	var totalCost int64
	for rows.Next() {
		var date string
		var itemsJSON []byte
		if err := rows.Scan(&date, &itemsJSON); err != nil {
			return nil, 0, 0, err
		}
		items := []analyticsOrderItem{}
		if err := json.Unmarshal(itemsJSON, &items); err != nil {
			continue
		}
		for _, item := range items {
			if item.ProductID <= 0 || item.Quantity <= 0 {
				continue
			}
			var snapshot analyticsProductSnapshot
			_ = json.Unmarshal(item.Snapshot, &snapshot)
			name := strings.TrimSpace(snapshot.Name["uz"])
			if name == "" {
				name = fmt.Sprintf("Mahsulot #%d", item.ProductID)
			}
			lineRevenue := item.Total
			if lineRevenue == 0 && item.Price > 0 {
				lineRevenue = item.Price * item.Quantity
			}
			cost, hasCost := costs[item.ProductID]
			lineCost := cost.PieceCost * item.Quantity
			isIncomplete := !hasCost || cost.Incomplete
			sale := sales[item.ProductID]
			if sale == nil {
				sale = &analyticsProductSale{
					ProductID: item.ProductID,
					Category:  snapshot.CategoryID,
					Name:      name,
				}
				sales[item.ProductID] = sale
			}
			sale.Quantity += item.Quantity
			sale.Revenue += lineRevenue
			sale.Cost += lineCost
			sale.Incomplete = sale.Incomplete || isIncomplete
			totalCost += lineCost
			if day := days[date]; day != nil {
				day.Cost += lineCost
			}
			if isIncomplete {
				incomplete[item.ProductID] = true
			}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, 0, 0, err
	}
	return sales, totalCost, len(incomplete), nil
}

func loadAnalyticsCategoryNames(ctx context.Context) (map[int]string, error) {
	rows, err := db.Pool.Query(ctx, `SELECT id,name_uz FROM categories`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	names := map[int]string{}
	for rows.Next() {
		var id int
		var name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, err
		}
		names[id] = name
	}
	return names, rows.Err()
}

func analyticsTopProducts(
	sales map[int]*analyticsProductSale,
) []map[string]interface{} {
	items := make([]*analyticsProductSale, 0, len(sales))
	for _, sale := range sales {
		items = append(items, sale)
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].Revenue == items[j].Revenue {
			return items[i].Quantity > items[j].Quantity
		}
		return items[i].Revenue > items[j].Revenue
	})
	if len(items) > 20 {
		items = items[:20]
	}
	out := make([]map[string]interface{}, 0, len(items))
	for _, item := range items {
		profit := item.Revenue - item.Cost
		percent := int64(0)
		if item.Revenue > 0 {
			percent = profit * 100 / item.Revenue
		}
		out = append(out, map[string]interface{}{
			"product_id": item.ProductID, "name": item.Name,
			"quantity": item.Quantity, "revenue": item.Revenue,
			"estimated_cost": item.Cost, "profit": profit,
			"profit_percent": percent, "incomplete": item.Incomplete,
		})
	}
	return out
}

func analyticsTopCategories(
	sales map[int]*analyticsProductSale,
	names map[int]string,
) []map[string]interface{} {
	categories := map[int]*analyticsCategorySale{}
	for _, sale := range sales {
		category := categories[sale.Category]
		if category == nil {
			name := strings.TrimSpace(names[sale.Category])
			if name == "" {
				name = "Kategoriyasiz"
			}
			category = &analyticsCategorySale{
				CategoryID: sale.Category, Name: name,
			}
			categories[sale.Category] = category
		}
		category.Quantity += sale.Quantity
		category.Revenue += sale.Revenue
	}
	items := make([]*analyticsCategorySale, 0, len(categories))
	for _, category := range categories {
		items = append(items, category)
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].Revenue > items[j].Revenue
	})
	out := make([]map[string]interface{}, 0, len(items))
	for _, item := range items {
		out = append(out, map[string]interface{}{
			"category_id": item.CategoryID, "name": item.Name,
			"quantity": item.Quantity, "revenue": item.Revenue,
		})
	}
	return out
}

func loadAnalyticsOrderBreakdown(
	ctx context.Context,
	dateRange analyticsDateRange,
	column string,
) ([]map[string]interface{}, error) {
	if column != "type" && column != "source" {
		return nil, errors.New("analytics breakdown column is invalid")
	}
	query := fmt.Sprintf(`
		SELECT COALESCE(%s,'other'),COUNT(*),COALESCE(SUM(total),0)
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'
		  AND status='completed' AND payment_status='paid'
		GROUP BY %s
		ORDER BY SUM(total) DESC`, column, column)
	rows, err := db.Pool.Query(ctx, query, dateRange.From, dateRange.To)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]interface{}{}
	for rows.Next() {
		var key string
		var count, total int64
		if err := rows.Scan(&key, &count, &total); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{
			column: key, "count": count, "revenue": total,
		})
	}
	return out, rows.Err()
}

func loadAnalyticsPayments(
	ctx context.Context,
	dateRange analyticsDateRange,
) ([]map[string]interface{}, error) {
	rows, err := db.Pool.Query(ctx, `
		SELECT method,COALESCE(SUM(amount),0)
		FROM (
		  SELECT COALESCE(payment_method,'other') AS method,total::bigint AS amount
		  FROM orders
		  WHERE created_at >= $1::date
		    AND created_at < $2::date + INTERVAL '1 day'
		    AND status='completed' AND payment_status='paid'
		    AND payments IS NULL
		  UNION ALL
		  SELECT COALESCE(part->>'method','other'),
		         COALESCE((part->>'amount')::bigint,0)
		  FROM orders
		  CROSS JOIN LATERAL jsonb_array_elements(
		    CASE WHEN jsonb_typeof(payments)='array'
		      THEN payments ELSE '[]'::jsonb END
		  ) part
		  WHERE created_at >= $1::date
		    AND created_at < $2::date + INTERVAL '1 day'
		    AND status='completed' AND payment_status='paid'
		) payment_rows
		GROUP BY method
		ORDER BY SUM(amount) DESC`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]interface{}{}
	for rows.Next() {
		var method string
		var total int64
		if err := rows.Scan(&method, &total); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{
			"method": method, "total": total,
		})
	}
	return out, rows.Err()
}

func loadAnalyticsPeakHours(
	ctx context.Context,
	dateRange analyticsDateRange,
) ([]map[string]interface{}, error) {
	rows, err := db.Pool.Query(ctx, `
		SELECT EXTRACT(HOUR FROM created_at)::int,
		       COUNT(*),COALESCE(SUM(total),0)
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'
		  AND status='completed' AND payment_status='paid'
		GROUP BY EXTRACT(HOUR FROM created_at)
		ORDER BY COUNT(*) DESC,EXTRACT(HOUR FROM created_at)
		LIMIT 8`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]interface{}{}
	for rows.Next() {
		var hour int
		var count, revenue int64
		if err := rows.Scan(&hour, &count, &revenue); err != nil {
			return nil, err
		}
		out = append(out, map[string]interface{}{
			"hour": hour, "orders": count, "revenue": revenue,
		})
	}
	return out, rows.Err()
}

type analyticsLedgerRow struct {
	At          time.Time
	Kind        string
	Reference   string
	OrderType   string
	Source      string
	Payment     string
	Customer    string
	Description string
	Income      int64
	Expense     int64
	Note        string
}

func handleAnalyticsCSV(w http.ResponseWriter, r *http.Request) {
	dateRange, err := analyticsRangeFromRequest(r)
	if err != nil {
		jsonError(w, http.StatusBadRequest, "invalid_range", err.Error())
		return
	}
	data, err := buildAnalyticsCSV(r.Context(), dateRange)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "db_error", err.Error())
		return
	}
	filename := fmt.Sprintf(
		"konak-hisobot-%s_%s.csv", dateRange.From, dateRange.To,
	)
	w.Header().Set("Content-Type", "text/csv; charset=utf-8")
	w.Header().Set(
		"Content-Disposition",
		fmt.Sprintf(`attachment; filename="%s"`, filename),
	)
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(data)
}

func buildAnalyticsCSV(
	ctx context.Context,
	dateRange analyticsDateRange,
) ([]byte, error) {
	ledger := []analyticsLedgerRow{}
	orderRows, err := db.Pool.Query(ctx, `
		SELECT created_at,order_number,type,source,
		       COALESCE(payment_method,''),payments,
		       COALESCE(customer_name,''),COALESCE(customer_phone,''),
		       items,total,COALESCE(note,'')
		FROM orders
		WHERE created_at >= $1::date
		  AND created_at < $2::date + INTERVAL '1 day'
		  AND status='completed' AND payment_status='paid'`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return nil, err
	}
	for orderRows.Next() {
		var row analyticsLedgerRow
		var payments, items []byte
		var customerName, customerPhone string
		if err := orderRows.Scan(
			&row.At, &row.Reference, &row.OrderType, &row.Source,
			&row.Payment, &payments, &customerName, &customerPhone,
			&items, &row.Income, &row.Note,
		); err != nil {
			orderRows.Close()
			return nil, err
		}
		row.Kind = "Sotuv"
		row.Customer = strings.TrimSpace(
			strings.TrimSpace(customerName) + " " + strings.TrimSpace(customerPhone),
		)
		row.Payment = analyticsPaymentSummary(row.Payment, payments)
		row.Description = analyticsItemsSummary(items)
		ledger = append(ledger, row)
	}
	if err := orderRows.Err(); err != nil {
		orderRows.Close()
		return nil, err
	}
	orderRows.Close()

	expenseRows, err := db.Pool.Query(ctx, `
		SELECT e.created_at,e.id,ec.name_uz,e.amount,e.description
		FROM expenses e
		JOIN expense_categories ec ON ec.id=e.category_id
		WHERE e.date::date BETWEEN $1::date AND $2::date`,
		dateRange.From, dateRange.To,
	)
	if err != nil {
		return nil, err
	}
	for expenseRows.Next() {
		var row analyticsLedgerRow
		var id int64
		if err := expenseRows.Scan(
			&row.At, &id, &row.Description, &row.Expense, &row.Note,
		); err != nil {
			expenseRows.Close()
			return nil, err
		}
		row.Kind = "Xarajat"
		row.Reference = "X-" + strconv.FormatInt(id, 10)
		ledger = append(ledger, row)
	}
	if err := expenseRows.Err(); err != nil {
		expenseRows.Close()
		return nil, err
	}
	expenseRows.Close()

	sort.SliceStable(ledger, func(i, j int) bool {
		return ledger[i].At.Before(ledger[j].At)
	})
	var totalIncome, totalExpense int64
	var buffer bytes.Buffer
	buffer.Write([]byte{0xEF, 0xBB, 0xBF})
	writer := csv.NewWriter(&buffer)
	if err := writer.Write([]string{
		"Turi", "Sana", "Vaqt", "Raqam", "Buyurtma turi", "Manba",
		"To'lov", "Mijoz", "Tarkib / kategoriya", "Tushum",
		"Xarajat", "Izoh",
	}); err != nil {
		return nil, err
	}
	for _, row := range ledger {
		totalIncome += row.Income
		totalExpense += row.Expense
		if err := writer.Write([]string{
			row.Kind, row.At.Format("2006-01-02"), row.At.Format("15:04:05"),
			csvSafe(row.Reference), row.OrderType, row.Source, csvSafe(row.Payment),
			csvSafe(row.Customer), csvSafe(row.Description), strconv.FormatInt(row.Income, 10),
			strconv.FormatInt(row.Expense, 10), csvSafe(row.Note),
		}); err != nil {
			return nil, err
		}
	}
	if err := writer.Write([]string{
		"JAMI", dateRange.From + " — " + dateRange.To, "", "", "", "", "",
		"", "", strconv.FormatInt(totalIncome, 10),
		strconv.FormatInt(totalExpense, 10),
		"Sof pul oqimi: " + strconv.FormatInt(totalIncome-totalExpense, 10),
	}); err != nil {
		return nil, err
	}
	writer.Flush()
	if err := writer.Error(); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}

func analyticsItemsSummary(itemsJSON []byte) string {
	items := []analyticsOrderItem{}
	if err := json.Unmarshal(itemsJSON, &items); err != nil {
		return ""
	}
	parts := make([]string, 0, len(items))
	for _, item := range items {
		if item.Quantity <= 0 {
			continue
		}
		var snapshot analyticsProductSnapshot
		_ = json.Unmarshal(item.Snapshot, &snapshot)
		name := strings.TrimSpace(snapshot.Name["uz"])
		if name == "" {
			name = fmt.Sprintf("Mahsulot #%d", item.ProductID)
		}
		parts = append(parts, fmt.Sprintf("%s x%d", name, item.Quantity))
	}
	return strings.Join(parts, "; ")
}

func analyticsPaymentSummary(method string, paymentsJSON []byte) string {
	if len(paymentsJSON) == 0 || string(paymentsJSON) == "null" {
		return method
	}
	var payments []struct {
		Method string `json:"method"`
		Amount int64  `json:"amount"`
	}
	if err := json.Unmarshal(paymentsJSON, &payments); err != nil ||
		len(payments) == 0 {
		return method
	}
	parts := make([]string, 0, len(payments))
	for _, payment := range payments {
		parts = append(parts, fmt.Sprintf(
			"%s: %d", payment.Method, payment.Amount,
		))
	}
	return strings.Join(parts, "; ")
}

// csvSafe — Excel formula injection'dan himoya.
//
// MUAMMO: `=`, `+`, `-`, `@` bilan boshlangan katak Excel'da FORMULA sifatida
// bajariladi. Mijoz ismi va izoh esa OCHIQ `/api/qr/order` endpointidan
// keladi — ya'ni QR orqali buyurtma bergan har kim restoran egasining
// hisobot faylida bajariladigan formula qoldira olardi.
// Tab/CR bilan boshlanishi ham xavfli (Excel ularni tashlab yuboradi).
func csvSafe(v string) string {
	if v == "" {
		return v
	}
	switch v[0] {
	case '=', '+', '-', '@', 0x09, 0x0d:
		return "'" + v
	}
	return v
}
