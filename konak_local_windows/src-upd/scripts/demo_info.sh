#!/usr/bin/env bash
# KONAK POS — demo uchun ma'lumot varag'i: loginlar, QR havolalar, ochiq
# cheklar, promo-kodlar, joriy holat. Namoyish paytida qo'l ostida tursin.
#
#   ./scripts/demo_info.sh

set -uo pipefail
PGURL="${DEMO_DB_URL:-postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable}"
URL="${KONAK_URL:-http://localhost:3000}"
Q() { psql "$PGURL" -tAq -c "$1"; }

echo "══════════════════════════════════════════════════════════════"
echo " KONAK POS — DEMO MA'LUMOT VARAG'I"
echo "══════════════════════════════════════════════════════════════"
printf " Backend : %s\n" "$URL"
printf " Holat   : %s\n" "$(curl -fsS "$URL/api/health" >/dev/null 2>&1 && echo 'ishlayapti ✓' || echo 'ISHLAMAYAPTI ✗')"
printf " Baza    : %s\n" "$PGURL"

echo
echo "── KIRISH (ilovada) ──────────────────────────────────────────"
psql "$PGURL" -c "SELECT name AS \"Ism\", phone AS \"Telefon\", role AS \"Rol\",
       CASE role WHEN 'super_admin' THEN '1234' WHEN 'admin' THEN '1111'
                 WHEN 'cashier' THEN '2222' WHEN 'kitchen' THEN '4444'
                 ELSE CASE WHEN name LIKE 'Malika%' THEN '5555' ELSE '3333' END
       END AS \"PIN\"
  FROM users WHERE status='active' ORDER BY id"

echo "── ZONA VA STOLLAR ───────────────────────────────────────────"
psql "$PGURL" -c "SELECT z.name AS \"Zona\", z.id AS \"№\", COUNT(t.id) AS \"Stol\",
       COUNT(*) FILTER (WHERE t.status='occupied') AS \"Band\",
       'Z'||z.id||'-1 … Z'||z.id||'-'||MAX(t.number) AS \"SKU oralig'i\"
  FROM zones z JOIN tables t ON t.zone_id=z.id
 WHERE z.status='active' GROUP BY z.name, z.id ORDER BY z.id"

echo "── QR HAVOLALAR (mijoz menyusi) ──────────────────────────────"
Q "SELECT '  '||sku||' → $URL/customer/?code='||qr_code FROM tables ORDER BY zone_id, number LIMIT 5"
echo "  (qolganlari: GET $URL/api/tables/qr-codes)"

echo
echo "── BUGUNGI OCHIQ CHEKLAR ─────────────────────────────────────"
psql "$PGURL" -c "SELECT order_number AS \"Raqam\", type AS \"Turi\",
       COALESCE(table_sku,'—') AS \"Stol\", source AS \"Manba\", total AS \"Jami\"
  FROM orders WHERE status NOT IN ('completed','cancelled') ORDER BY id"

echo "── PROMO-KODLAR ──────────────────────────────────────────────"
psql "$PGURL" -c "SELECT code AS \"Kod\", discount_type AS \"Turi\", value AS \"Qiymat\",
       min_order_total AS \"Min summa\", COALESCE(max_discount,0) AS \"Maks chegirma\",
       COALESCE(usage_limit,0) AS \"Limit\", used_count AS \"Ishlatilgan\",
       CASE WHEN ends_at IS NOT NULL AND ends_at < NOW() THEN 'MUDDATI O''TGAN' ELSE status END AS \"Holat\"
  FROM promo_codes ORDER BY id"

echo "── ONLINE (saboy/dostafka) TEST TOKENLARI ────────────────────"
psql "$PGURL" -c "SELECT verification_token AS \"Token\", status AS \"Holat\",
       phone AS \"Telefon\", expires_at::timestamp(0) AS \"Muddati\"
  FROM online_verifications ORDER BY id"

echo "── JORIY HOLAT ───────────────────────────────────────────────"
printf "  Menyu           : %s kategoriya, %s mahsulot (versiya %s)\n" \
  "$(Q "SELECT COUNT(*) FROM categories WHERE status='active'")" \
  "$(Q "SELECT COUNT(*) FROM products WHERE status='active'")" \
  "$(Q "SELECT version FROM menu_version WHERE id=1")"
printf "  Buyurtma        : jami %s, bugun %s, ochiq %s\n" \
  "$(Q "SELECT COUNT(*) FROM orders")" \
  "$(Q "SELECT COUNT(*) FROM orders WHERE created_at::date=CURRENT_DATE")" \
  "$(Q "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed','cancelled')")"
printf "  Smena           : %s\n" \
  "$(Q "SELECT COALESCE((SELECT 'ochiq (#'||id||'), kassada '||opening_cash||' so''m' FROM shifts WHERE status='open'),'yopiq')")"
printf "  Ombor           : %s ingredient, %s faol partiya\n" \
  "$(Q "SELECT COUNT(*) FROM ingredients WHERE status='active'")" \
  "$(Q "SELECT COUNT(*) FROM ingredient_batches WHERE status='active' AND remaining_qty>0")"
printf "  Pishirish       : %s ta jarayonda\n" \
  "$(Q "SELECT COUNT(*) FROM cookings WHERE status='cooking'")"
printf "  CRM             : %s mijoz, %s ball muomalada\n" \
  "$(Q "SELECT COUNT(*) FROM customers WHERE status='active'")" \
  "$(Q "SELECT COALESCE(SUM(loyalty_points),0) FROM customers")"
printf "  Audit / backup  : %s yozuv, %s backup\n" \
  "$(Q "SELECT COUNT(*) FROM audit_logs")" \
  "$(Q "SELECT COUNT(*) FROM backups")"
echo "══════════════════════════════════════════════════════════════"
