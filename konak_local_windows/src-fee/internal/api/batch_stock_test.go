package api

import "testing"

func TestAllocateBatchStockUsesFIFOOrder(t *testing.T) {
	batches := []batchStock{
		{id: 1, remaining: 3},
		{id: 2, remaining: 8},
		{id: 3, remaining: 10},
	}
	got := allocateBatchStock(batches, 9)
	want := []int64{3, 6, 0}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("allocation[%d]=%d, want %d", index, got[index], want[index])
		}
	}
}

func TestValidateBatchInputRejectsMissingQuantity(t *testing.T) {
	input := ingredientBatchInput{
		IngredientID: 1,
	}
	if message := validateBatchInput(&input, true); message == "" {
		t.Fatal("expected missing quantity to be rejected")
	}
}
