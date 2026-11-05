-- KONAK POS — demo bazasini boshlang'ich holatga qaytarish.
--
-- HAMMA ma'lumotni o'chiradi (faqat super_admin xodim va sozlamalar qoladi)
-- va ID ketma-ketliklarini 1 dan boshlaydi — shunda demo har safar bir xil
-- chiqadi (zona Z1/Z2, printer #1..#3, mijoz #1..#8 va h.k.).
--
-- FAQAT LOCAL DEMO BAZASIDA ishlating:
--   psql "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable" \
--        -f scripts/demo_reset.sql
-- Keyin: python3 scripts/demo_seed.py

BEGIN;

DELETE FROM ing_batch_moves;
DELETE FROM ingredient_batches;
DELETE FROM purchase_items;
DELETE FROM purchases;
DELETE FROM ing_moves;
DELETE FROM cookings;
DELETE FROM recipes;
DELETE FROM write_offs;
DELETE FROM inventory_corrections;
DELETE FROM shift_stock_snapshots;
DELETE FROM loyalty_transactions;
DELETE FROM orders;
DELETE FROM customers;
DELETE FROM promo_codes;
DELETE FROM expenses;
DELETE FROM expense_categories;
DELETE FROM qr_sessions;
DELETE FROM online_verifications;
DELETE FROM table_locks;
DELETE FROM tables;
DELETE FROM zones;
DELETE FROM stocks;
DELETE FROM products;
DELETE FROM categories;
DELETE FROM shifts;
DELETE FROM order_daily_counters;
DELETE FROM audit_logs;
DELETE FROM backups;
DELETE FROM sync_queue;
DELETE FROM sync_applied;
DELETE FROM printer_stations;
DELETE FROM ingredients;
DELETE FROM suppliers;
DELETE FROM users WHERE id <> 1;

-- ID ketma-ketliklari 1 dan boshlansin
SELECT setval(pg_get_serial_sequence(t, 'id'), 1, false)
FROM unnest(ARRAY[
  'categories','products','zones','tables','orders','shifts',
  'expense_categories','expenses','qr_sessions','printer_stations',
  'ingredients','ing_moves','purchases','purchase_items','cookings',
  'write_offs','inventory_corrections','customers','loyalty_transactions',
  'promo_codes','suppliers','ingredient_batches','ing_batch_moves',
  'audit_logs','backups','online_verifications'
]) AS t;
SELECT setval(pg_get_serial_sequence('users', 'id'), 1, true);

UPDATE menu_version SET version = 1, updated_at = NOW() WHERE id = 1;

COMMIT;
