#!/bin/bash
# KONAK LOCAL SERVER — API Test Script
# Run: ./test_api.sh

BASE="http://localhost:3000"

echo "========================================="
echo "  KONAK LOCAL SERVER — API TEST"
echo "========================================="
echo ""

echo "1. GET /api/health"
curl -s $BASE/api/health
echo -e "\n"

echo "2. GET /api/menu"
curl -s $BASE/api/menu | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'  version: {d[\"version\"]}')
print(f'  categories: {len(d[\"categories\"])} ta')
for c in d['categories']:
    print(f'    - {c[\"name\"][\"uz\"]}')
print(f'  products: {len(d[\"products\"])} ta')
for p in d['products']:
    print(f'    - {p[\"name\"][\"uz\"]} — {p[\"price\"]} so\"m')
"
echo ""

echo "3. GET /api/stocks"
curl -s $BASE/api/stocks | python3 -c "
import sys,json
for s in json.load(sys.stdin):
    print(f'  product #{s[\"product_id\"]}: {s[\"count\"]} ta')
"
echo ""

echo "4. GET /api/table/1-2"
curl -s $BASE/api/table/1-2 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'  {d[\"label\"]} [{d[\"status\"]}] seats:{d[\"seats\"]}')
print(f'  locked_by: {d[\"locked_by\"]}')
print(f'  active_order: {d[\"active_order\"]}')
"
echo ""

echo "5. POST /api/auth/login (Aziz, cashier)"
TOKEN=$(curl -s -X POST $BASE/api/auth/login -H "Content-Type: application/json" -d '{"phone":"+998909876543","pin":"5678"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['token']);print(f'  id:{d[\"user\"][\"id\"]} name:{d[\"user\"][\"name\"]} role:{d[\"user\"][\"role\"]}',file=sys.stderr)" 2>&1)
echo "  token: ${TOKEN:0:40}..."
echo ""

echo "6. GET /api/zones (with token)"
curl -s $BASE/api/zones -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys,json
for z in json.load(sys.stdin):
    name = z.get('name',{}).get('uz','?')
    tables = z.get('tables',[])
    free = sum(1 for t in tables if t['status']=='free')
    print(f'  {name}: {len(tables)} stol ({free} bosh)')
"
echo ""

echo "7. GET /api/shift/current"
curl -s $BASE/api/shift/current -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'  status: {d[\"status\"]}')"
echo ""

echo "8. POST /api/shift/open (500000 som)"
curl -s -X POST $BASE/api/shift/open -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"opening_cash":500000}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'  shift_id:{d.get(\"shift_id\")} status:{d.get(\"status\")} cash:{d.get(\"opening_cash\")}')"
echo ""

echo "9. GET /api/orders (active)"
curl -s "$BASE/api/orders?status=active" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'  {len(d)} ta aktiv buyurtma')"
echo ""

echo "10. POST /api/expense"
curl -s -X POST $BASE/api/expense -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"category_id":2,"amount":350000,"description":"Gusht 5kg"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'  id:{d.get(\"id\")} amount:{d.get(\"amount\")} desc:{d.get(\"description\")}')"
echo ""

echo "========================================="
echo "  ALL TESTS COMPLETE"
echo "========================================="
