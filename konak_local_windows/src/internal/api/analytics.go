package api

// Foyda analitikasi — 5-bosqich (S6 qarori):
//   GET /api/analytics/products — retseptli har mahsulot: tannarx (oxirgi bozor
//   narxlaridan), sotuv narxi, foyda va foyda %; eng yomoni tepada.

import (
	"encoding/json"
	"math"
	"net/http"
	"sort"

	"konak-local/internal/db"
)

func handleAnalyticsProducts(w http.ResponseWriter, r *http.Request) {
	if requireAdminRole(w, r) == nil {
		return
	}

	rows, err := db.Pool.Query(r.Context(), `
		SELECT rc.product_id, COALESCE(p.name_uz, ''), COALESCE(p.price, 0),
		       rc.batch_qty, rc.items
		FROM recipes rc
		JOIN products p ON p.id = rc.product_id AND p.status = 'active'
		ORDER BY p.name_uz`)
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}
	defer rows.Close()

	type rec struct {
		productID, price, batchQty int
		name                       string
		itemsJSON                  []byte
	}
	recs := []rec{}
	for rows.Next() {
		var rc rec
		if err := rows.Scan(&rc.productID, &rc.name, &rc.price, &rc.batchQty, &rc.itemsJSON); err != nil {
			jsonError(w, 500, "db_error", err.Error())
			return
		}
		recs = append(recs, rc)
	}
	rows.Close()

	prices, err := loadIngPriceInfo(r.Context())
	if err != nil {
		jsonError(w, 500, "db_error", err.Error())
		return
	}

	products := []map[string]interface{}{}
	for _, rc := range recs {
		items := []RecipeItem{}
		json.Unmarshal(rc.itemsJSON, &items)
		_, pieceCost, detail, incomplete := recipeCost(rc.batchQty, items, prices)

		// Narxsiz (xaridi kiritilmagan) ingredientlar — UI undov bosilganda ko'rsatadi
		missing := []string{}
		for _, d := range detail {
			if hp, ok := d["has_price"].(bool); ok && !hp {
				missing = append(missing, d["name"].(string))
			}
		}

		profit := int64(rc.price) - pieceCost
		percent := 0
		if rc.price > 0 {
			percent = int(math.Round(float64(profit) * 100 / float64(rc.price)))
		}
		products = append(products, map[string]interface{}{
			"product_id": rc.productID, "name": rc.name, "price": rc.price,
			"piece_cost": pieceCost, "profit": profit, "profit_percent": percent,
			"incomplete": incomplete, "missing_ingredients": missing,
		})
	}

	// Eng yomon foyda % tepada
	sort.Slice(products, func(i, j int) bool {
		return products[i]["profit_percent"].(int) < products[j]["profit_percent"].(int)
	})

	jsonResponse(w, 200, map[string]interface{}{"products": products})
}
