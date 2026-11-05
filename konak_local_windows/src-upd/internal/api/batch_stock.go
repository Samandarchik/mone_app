package api

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

var errInsufficientIngredientStock = errors.New(
	"ingredient qoldig'i yetarli emas",
)

type batchStock struct {
	id        int64
	remaining int64
}

func consumeIngredientBatchesTx(
	ctx context.Context,
	tx pgx.Tx,
	ingredientID int,
	needed, current int64,
	reason, ref string,
) error {
	var allBatchQty int64
	if err := tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(remaining_qty),0)
		FROM ingredient_batches
		WHERE ingredient_id=$1 AND status='active' AND remaining_qty>0`,
		ingredientID,
	).Scan(&allBatchQty); err != nil {
		return err
	}
	legacyQty := current - allBatchQty
	if legacyQty < 0 {
		legacyQty = 0
	}

	rows, err := tx.Query(ctx, `
		SELECT id,remaining_qty
		FROM ingredient_batches
		WHERE ingredient_id=$1 AND status='active' AND remaining_qty>0
		ORDER BY received_at,id
		FOR UPDATE`,
		ingredientID,
	)
	if err != nil {
		return err
	}
	batches := []batchStock{}
	var eligibleBatchQty int64
	for rows.Next() {
		var batch batchStock
		if err := rows.Scan(&batch.id, &batch.remaining); err != nil {
			rows.Close()
			return err
		}
		eligibleBatchQty += batch.remaining
		batches = append(batches, batch)
	}
	rows.Close()
	if needed > eligibleBatchQty+legacyQty {
		return errInsufficientIngredientStock
	}

	// Kuzatuv yoqilishidan oldingi qoldiq eng eski hisoblanadi, shuning uchun
	// avval o'sha qism sarflanadi, qolgan miqdor FIFO partiyalardan olinadi.
	batchNeed := needed
	if legacyQty >= batchNeed {
		batchNeed = 0
	} else {
		batchNeed -= legacyQty
	}
	for index, take := range allocateBatchStock(batches, batchNeed) {
		if take == 0 {
			continue
		}
		batch := batches[index]
		if _, err := tx.Exec(ctx, `
			UPDATE ingredient_batches SET
				remaining_qty=remaining_qty-$1,
				status=CASE WHEN remaining_qty-$1=0 THEN 'depleted' ELSE status END,
				updated_at=NOW()
			WHERE id=$2`,
			take, batch.id,
		); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO ing_batch_moves
				(batch_id,ingredient_id,qty,reason,ref)
			VALUES ($1,$2,$3,$4,$5)`,
			batch.id, ingredientID, -take, reason, ref,
		); err != nil {
			return err
		}
	}
	return nil
}

func allocateBatchStock(batches []batchStock, needed int64) []int64 {
	takes := make([]int64, len(batches))
	remaining := needed
	for index, batch := range batches {
		if remaining <= 0 {
			break
		}
		take := batch.remaining
		if take > remaining {
			take = remaining
		}
		takes[index] = take
		remaining -= take
	}
	return takes
}

func restoreIngredientBatchesTx(
	ctx context.Context,
	tx pgx.Tx,
	ingredientID int,
	qty int64,
	reason, ref string,
) error {
	rows, err := tx.Query(ctx, `
		SELECT batch_id,-SUM(qty) AS net_consumed
		FROM ing_batch_moves
		WHERE ingredient_id=$1 AND ref=$2
		GROUP BY batch_id
		HAVING SUM(qty)<0
		ORDER BY batch_id`,
		ingredientID, ref,
	)
	if err != nil {
		return err
	}
	type restoreTarget struct {
		id  int64
		qty int64
	}
	targets := []restoreTarget{}
	for rows.Next() {
		var target restoreTarget
		if err := rows.Scan(&target.id, &target.qty); err != nil {
			rows.Close()
			return err
		}
		targets = append(targets, target)
	}
	rows.Close()

	remaining := qty
	for _, target := range targets {
		if remaining == 0 {
			break
		}
		restore := target.qty
		if restore > remaining {
			restore = remaining
		}
		if _, err := tx.Exec(ctx, `
			UPDATE ingredient_batches SET
				remaining_qty=remaining_qty+$1,status='active',updated_at=NOW()
			WHERE id=$2`,
			restore, target.id,
		); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO ing_batch_moves
				(batch_id,ingredient_id,qty,reason,ref)
			VALUES ($1,$2,$3,$4,$5)`,
			target.id, ingredientID, restore, reason, ref,
		); err != nil {
			return err
		}
		remaining -= restore
	}
	return nil
}

func automaticBatchCode(reason string) string {
	return fmt.Sprintf("AUTO-%s-%d", reason, time.Now().UnixNano())
}
