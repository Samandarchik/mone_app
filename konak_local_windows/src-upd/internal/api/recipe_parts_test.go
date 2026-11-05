package api

import "testing"

// Bir masalliq bir necha qismda bo'lsa (tuxum — "Biskvit" va "Krem"),
// ombordan chiqim BITTA qator bo'lib, miqdorlar QO'SHILISHI kerak.
func TestMergeRecipeParts_SameIngredientInTwoParts(t *testing.T) {
	items := []RecipeItem{
		{IngredientID: 1, Name: "Un", Unit: "gr", Amount: 500, Part: "Biskvit"},
		{IngredientID: 2, Name: "Tuxum", Unit: "dona", Amount: 6, Part: "Biskvit"},
		{IngredientID: 3, Name: "Qaymoq", Unit: "gr", Amount: 400, Part: "Krem"},
		{IngredientID: 2, Name: "Tuxum", Unit: "dona", Amount: 4, Part: "Krem"},
	}
	got := mergeRecipeParts(items)

	if len(got) != 3 {
		t.Fatalf("3 ta masalliq kutilgandi, %d ta chiqdi: %+v", len(got), got)
	}
	// Tartib — birinchi uchrash tartibi
	if got[0].IngredientID != 1 || got[1].IngredientID != 2 || got[2].IngredientID != 3 {
		t.Fatalf("tartib buzilgan: %+v", got)
	}
	if got[1].Amount != 10 {
		t.Fatalf("tuxum 6+4=10 bo'lishi kerak, %d chiqdi", got[1].Amount)
	}
	if got[1].Name != "Tuxum" || got[1].Unit != "dona" {
		t.Fatalf("nom/birlik yo'qolgan: %+v", got[1])
	}
	if got[1].Part != "" {
		t.Fatalf("birlashtirilgan qatorda qism qolmasligi kerak: %q", got[1].Part)
	}
}

// Qismsiz eski retsept — hech narsa o'zgarmaydi.
func TestMergeRecipeParts_NoParts(t *testing.T) {
	items := []RecipeItem{
		{IngredientID: 1, Name: "Un", Unit: "gr", Amount: 500},
		{IngredientID: 2, Name: "Shakar", Unit: "gr", Amount: 200},
	}
	got := mergeRecipeParts(items)
	if len(got) != 2 || got[0].Amount != 500 || got[1].Amount != 200 {
		t.Fatalf("qismsiz retsept o'zgarmasligi kerak: %+v", got)
	}
}

// Yaxlitlash BIR MARTA: qismlar alohida hisoblanganda chetlanish to'planardi.
// 3 ta qismda 1 gr dan (jami 3 gr), 10 talik partiyadan 1 ta pishirilsa:
// birlashtirilgan hisob 0.3 → 0 (keyin handler 1 ga ko'taradi), alohida
// hisobda esa har qism 0.1 → 0 → 1 bo'lib, jami 3 gr yozilardi.
func TestMergeRecipeParts_RoundingOnce(t *testing.T) {
	items := []RecipeItem{
		{IngredientID: 7, Name: "Za'faron", Unit: "gr", Amount: 1, Part: "A"},
		{IngredientID: 7, Name: "Za'faron", Unit: "gr", Amount: 1, Part: "B"},
		{IngredientID: 7, Name: "Za'faron", Unit: "gr", Amount: 1, Part: "C"},
	}
	merged := mergeRecipeParts(items)
	if len(merged) != 1 || merged[0].Amount != 3 {
		t.Fatalf("3 gr kutilgandi: %+v", merged)
	}
	if got := grossAmountScaled(merged[0].Amount, 1, 10, 0); got != 0 {
		t.Fatalf("0 kutilgandi (handler keyin 1 ga ko'taradi), %d chiqdi", got)
	}
	// Alohida hisoblansa har biri 0 chiqib, handler uchalasini 1 ga
	// ko'targan bo'lardi — jami 3 gr, ya'ni 10 barobar ortiqcha.
	var separate int64
	for _, it := range items {
		g := grossAmountScaled(it.Amount, 1, 10, 0)
		if g <= 0 {
			g = 1
		}
		separate += g
	}
	if separate != 3 {
		t.Fatalf("test farazi buzildi: %d", separate)
	}
}

// Qism bo'yicha tannarx yig'indisi retseptdagi tartibda chiqadi.
func TestRecipePartTotals(t *testing.T) {
	items := []RecipeItem{
		{IngredientID: 1, Amount: 500, Part: "Biskvit"},
		{IngredientID: 2, Amount: 6, Part: "Biskvit"},
		{IngredientID: 3, Amount: 400, Part: "Krem"},
	}
	detail := []map[string]interface{}{
		{"cost": int64(3000)}, {"cost": int64(6000)}, {"cost": int64(8000)},
	}
	got := recipePartTotals(items, detail)
	if len(got) != 2 {
		t.Fatalf("2 qism kutilgandi: %+v", got)
	}
	if got[0]["part"] != "Biskvit" || got[0]["cost"].(int64) != 9000 || got[0]["items_count"].(int) != 2 {
		t.Fatalf("Biskvit noto'g'ri: %+v", got[0])
	}
	if got[1]["part"] != "Krem" || got[1]["cost"].(int64) != 8000 {
		t.Fatalf("Krem noto'g'ri: %+v", got[1])
	}
}

// Qismsiz retseptda ekran qism jadvalini ko'rsatmasligi kerak.
func TestRecipePartTotals_Empty(t *testing.T) {
	items := []RecipeItem{{IngredientID: 1, Amount: 500}}
	detail := []map[string]interface{}{{"cost": int64(3000)}}
	if got := recipePartTotals(items, detail); len(got) != 0 {
		t.Fatalf("bo'sh kutilgandi: %+v", got)
	}
}

func TestNormalizeRecipePart(t *testing.T) {
	if got := normalizeRecipePart("  Krem  "); got != "Krem" {
		t.Fatalf("trim ishlamadi: %q", got)
	}
	long := ""
	for i := 0; i < 60; i++ {
		long += "a"
	}
	if got := normalizeRecipePart(long); len([]rune(got)) != maxRecipePartLen {
		t.Fatalf("uzunlik chegaralanmadi: %d", len([]rune(got)))
	}
	// Ko'p baytli harflar bayt emas, HARF bo'yicha kesilishi kerak
	uz := ""
	for i := 0; i < 60; i++ {
		uz += "ў"
	}
	if got := normalizeRecipePart(uz); len([]rune(got)) != maxRecipePartLen {
		t.Fatalf("kirill harflari kesilishi buzilgan: %d", len([]rune(got)))
	}
}
