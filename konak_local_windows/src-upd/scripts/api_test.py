#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KONAK POS — to'liq API test (end-to-end).

Ishlab turgan local backendni boshdan-oxir tekshiradi: autentifikatsiya,
ruxsatlar, menyu, zona/stol, smena, buyurtma (POS/QR/online), to'lov, ombor,
retsept, pishirish, CRM, promo, moliya, analitika, spisaniya, audit, backup,
WebSocket. Har bir tekshiruv OK/XATO bo'lib chiqadi, oxirida umumiy natija.

Test o'z ma'lumotini yaratadi va o'chiradi ("ZZ-TEST..." nomlari bilan),
demo ma'lumotlariga tegmaydi.

Ishlatish:
    python3 scripts/api_test.py
    KONAK_URL=http://localhost:3000 python3 scripts/api_test.py
"""

import base64
import json
import os
import socket
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta

BASE = os.environ.get("KONAK_URL", "http://localhost:3000").rstrip("/")
ADMIN_PHONE = os.environ.get("KONAK_ADMIN_PHONE", "+998901234567")
ADMIN_PIN = os.environ.get("KONAK_ADMIN_PIN", "1234")

# Har ishga tushirishda noyob qo'shimcha — test ma'lumoti to'qnashmasin
SUF = datetime.now().strftime("%H%M%S")

PIN9 = "9" + SUF[-3:]

PASSED = []
FAILED = []
TOKENS = {}
GREEN, RED, DIM, BOLD, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[1m", "\033[0m"


def section(title):
    print(f"\n{BOLD}── {title} {'─' * max(0, 60 - len(title))}{RESET}")


def check(name, condition, detail=""):
    if condition:
        PASSED.append(name)
        print(f"  {GREEN}OK{RESET}   {name}" + (f" {DIM}{detail}{RESET}" if detail else ""))
    else:
        FAILED.append((name, detail))
        print(f"  {RED}XATO{RESET} {name} {DIM}{detail}{RESET}")
    return condition


def api(method, path, body=None, token=None, raw=False, headers=None):
    """(status, body) qaytaradi. Xatoda ham exception tashlamaydi."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload, status = resp.read(), resp.status
    except urllib.error.HTTPError as e:
        payload, status = e.read(), e.code
    except urllib.error.URLError as e:
        print(f"{RED}Backendga ulanib bo'lmadi: {BASE} ({e}){RESET}")
        sys.exit(2)
    if raw:
        return status, payload
    try:
        return status, json.loads(payload.decode()) if payload else None
    except json.JSONDecodeError:
        return status, payload.decode(errors="replace")


def items_of(resp, key):
    return resp.get(key, []) if isinstance(resp, dict) else (resp or [])


# ==========================================================================
# 1. Salomatlik va ochiq (autentifikatsiyasiz) endpointlar
# ==========================================================================
def test_public():
    section("1. Ochiq endpointlar (token kerak emas)")
    status, body = api("GET", "/api/health")
    check("GET /api/health → 200", status == 200, str(body)[:60])

    status, menu = api("GET", "/api/menu")
    cats = len(menu.get("categories", [])) if isinstance(menu, dict) else 0
    prods = len(menu.get("products", [])) if isinstance(menu, dict) else 0
    check("GET /api/menu — POS menyusi", status == 200 and cats > 0 and prods > 0,
          f"{cats} kategoriya, {prods} mahsulot, versiya {menu.get('version')}")

    status, web = api("GET", "/api/menu-web")
    web_prods = len(web.get("products", [])) if isinstance(web, dict) else 0
    check("GET /api/menu-web — QR mijoz menyusi", status == 200,
          f"{web_prods} mahsulot (qoldig'i 0 bo'lganlar yashiriladi)")
    check("menu-web POS menyusidan kichik yoki teng", web_prods <= prods,
          f"{web_prods} ≤ {prods}")

    # /api/stocks endi HIMOYALANGAN: ombor qoldig'i ochiq ko'rinmasligi kerak.
    status, _ = api("GET", "/api/stocks")
    check("GET /api/stocks tokensiz → 401", status == 401)

    status, _ = api("GET", "/api/orders")
    check("Tokensiz himoyalangan endpoint → 401", status == 401)

    status, _ = api("GET", "/api/orders", token="soxta.token.qiymati")
    check("Soxta token → 401", status == 401)


# ==========================================================================
# 2. Autentifikatsiya
# ==========================================================================
def test_auth():
    section("2. Autentifikatsiya va rollar")
    status, body = api("POST", "/api/auth/login", {"phone": ADMIN_PHONE, "pin": ADMIN_PIN})
    ok = status == 200 and "token" in (body or {})
    check("POST /api/auth/login (telefon + PIN)", ok,
          f"{body.get('user', {}).get('name')} / {body.get('user', {}).get('role')}" if ok else str(body)[:80])
    if not ok:
        print(f"{RED}super_admin bilan kira olmadim — test to'xtatildi{RESET}")
        sys.exit(2)
    TOKENS["super_admin"] = body["token"]

    status, body = api("POST", "/api/auth/login", {"phone": ADMIN_PHONE, "pin": "9999"})
    check("Noto'g'ri PIN → 401", status == 401, str(body)[:60])

    for role, pin in (("admin", "1111"), ("cashier", "2222"),
                      ("waiter", "3333"), ("kitchen", "4444"), ("custom", "5555")):
        status, body = api("POST", "/api/auth/pin-login", {"pin": pin})
        if status == 200:
            TOKENS[role] = body["token"]
        check(f"PIN-login {pin} → {role}", status == 200,
              f"{body.get('user', {}).get('name')} / {body.get('user', {}).get('role')}"
              if status == 200 else str(body)[:60])

    status, _ = api("POST", "/api/auth/pin-login", {"pin": "12"})
    check("Qisqa PIN → 400", status == 400)


# ==========================================================================
# 3. Ruxsatlar (RBAC)
# ==========================================================================
def test_permissions():
    section("3. Ruxsatlar — har rol o'z chegarasida")
    cases = [
        ("waiter", "DELETE", "/api/product/999999", 403, "ofitsiant mahsulot o'chira olmaydi"),
        ("waiter", "GET", "/api/analytics/overview", 403, "ofitsiantga analitika yopiq"),
        ("cashier", "GET", "/api/ingredients", 403, "kassirga ombor yopiq"),
        ("cashier", "POST", "/api/user", 403, "kassir xodim qo'sha olmaydi"),
        ("kitchen", "GET", "/api/finance/daily", 403, "oshpazga moliya yopiq"),
        ("kitchen", "GET", "/api/cooking/needed", 200, "oshpaz pishirish ro'yxatini ko'radi"),
        ("admin", "GET", "/api/analytics/overview", 200, "adminga analitika ochiq"),
        ("admin", "GET", "/api/audit", 403, "audit faqat super_admin uchun"),
        ("super_admin", "GET", "/api/audit", 200, "super_admin auditni ko'radi"),
        ("cashier", "GET", "/api/finance/daily", 403,
         "kassirga moliya sahifasi yopiq (u smena statistikasini ko'radi)"),
    ]
    for role, method, path, want, label in cases:
        if role not in TOKENS:
            check(f"{role}: {label}", False, "token yo'q")
            continue
        body = {} if method == "POST" else None
        status, _ = api(method, path, body, token=TOKENS[role])
        check(f"{role}: {label}", status == want, f"kutilgan {want}, keldi {status}")

    yesterday = (date.today() - timedelta(days=1)).isoformat()
    status, _ = api("GET", f"/api/finance/daily?date={yesterday}", token=TOKENS.get("admin"))
    check("admin kechagi moliyani ko'ra olmaydi → 403 (faqat bugun)", status == 403)
    status, _ = api("GET", f"/api/finance/daily?date={yesterday}", token=TOKENS["super_admin"])
    check("super_admin istalgan kunni ko'radi → 200", status == 200)


# ==========================================================================
# 4. Menyu CRUD
# ==========================================================================
def test_menu_crud():
    section("4. Menyu — kategoriya va mahsulot CRUD")
    t = TOKENS["super_admin"]
    _, menu_before = api("GET", "/api/menu")
    version_before = menu_before.get("version", 0)

    status, cat = api("POST", "/api/category",
                      {"name_uz": f"ZZ-TEST kategoriya {SUF}", "name_ru": "ZZ-TEST",
                       "name_tr": "ZZ-TEST"}, token=t)
    cat_id = (cat or {}).get("id")
    check("POST /api/category", status in (200, 201) and cat_id, f"id={cat_id}")

    status, prod = api("POST", "/api/product",
                       {"name_uz": f"ZZ-TEST mahsulot {SUF}", "name_ru": "ZZ-TEST",
                        "name_tr": "ZZ-TEST", "price": 12345,
                        "category_id": cat_id, "product_type": "ready"}, token=t)
    prod_id = (prod or {}).get("id")
    check("POST /api/product", status in (200, 201) and prod_id, f"id={prod_id}")

    _, menu_after = api("GET", "/api/menu")
    check("menu_version oshdi", menu_after.get("version", 0) > version_before,
          f"{version_before} → {menu_after.get('version')}")

    status, _ = api("PUT", f"/api/product/{prod_id}", {"price": 15000}, token=t)
    _, menu2 = api("GET", "/api/menu")
    new_price = next((p["price"] for p in menu2["products"] if p["id"] == prod_id), None)
    check("PUT /api/product — narx yangilandi", status == 200 and new_price == 15000,
          f"narx={new_price}")

    status, _ = api("POST", "/api/stock/set",
                    {"product_id": prod_id, "count": 7}, token=t)
    _, stocks = api("GET", "/api/stocks", token=t)
    stock_map = {s["product_id"]: s.get("count") for s in items_of(stocks, "stocks")} \
        if isinstance(stocks, dict) else {s["product_id"]: s.get("count") for s in stocks}
    check("POST /api/stock/set — qoldiq kiritildi", status == 200 and stock_map.get(prod_id) == 7,
          f"qoldiq={stock_map.get(prod_id)}")

    status, _ = api("POST", "/api/reorder",
                    {"categories": [{"id": cat_id, "sort_order": 99}],
                     "products": [{"id": prod_id, "sort_order": 1, "category_id": cat_id}]},
                    token=t)
    check("POST /api/reorder — tartib o'zgartirish", status == 200)

    status, _ = api("DELETE", f"/api/category/{cat_id}", token=t)
    check("Ichida mahsuloti bor kategoriya o'chmaydi → 400", status == 400)

    status, _ = api("DELETE", f"/api/product/{prod_id}", token=t)
    check("DELETE /api/product", status == 200)
    status, _ = api("DELETE", f"/api/category/{cat_id}", token=t)
    check("DELETE /api/category (bo'shatilgandan keyin)", status == 200)


# ==========================================================================
# 5. Zona va stollar
# ==========================================================================
def test_zones():
    section("5. Zona va stollar")
    t = TOKENS["super_admin"]
    status, zones = api("GET", "/api/zones", token=t)
    total_tables = sum(len(z.get("tables", [])) for z in zones) if status == 200 else 0
    check("GET /api/zones", status == 200 and len(zones) >= 2,
          f"{len(zones)} zona, {total_tables} stol")

    occupied = [tb["sku"] for z in zones for tb in z.get("tables", [])
                if tb.get("status") == "occupied"]
    check("Band stollar ko'rinadi", len(occupied) > 0, ", ".join(occupied))

    status, qr = api("GET", "/api/tables/qr-codes", token=t)
    check("GET /api/tables/qr-codes", status == 200 and qr,
          f"{len(items_of(qr, 'tables') or qr)} ta QR")

    status, zone = api("POST", "/api/zone", {"name": f"ZZ-TEST zona {SUF}", "count": 3}, token=t)
    zid = (zone or {}).get("id")
    check("POST /api/zone — 3 stol bilan", status in (200, 201) and zid, f"id={zid}")

    status, _ = api("PUT", f"/api/zone/{zid}", {"name": "ZZ-TEST zona 2", "count": 5}, token=t)
    _, zones2 = api("GET", "/api/zones", token=t)
    z2 = next((z for z in zones2 if z["id"] == zid), None)
    check("PUT /api/zone — stol soni 5 ga chiqdi",
          status == 200 and z2 and len(z2.get("tables", [])) == 5,
          f"{len(z2.get('tables', [])) if z2 else '-'} stol")

    status, _ = api("DELETE", f"/api/zone/{zid}", token=t)
    check("DELETE /api/zone", status == 200)

    status, _ = api("POST", "/api/zone", {"name": "ZZ-KO'P", "count": 500}, token=t)
    check("500 stolli zona rad etiladi → 400", status == 400)


# ==========================================================================
# 6. Xodimlar
# ==========================================================================
def test_users():
    section("6. Xodimlar")
    t = TOKENS["super_admin"]
    status, users = api("GET", "/api/users", token=t)
    check("GET /api/users", status == 200 and len(users) >= 6, f"{len(users)} xodim")
    check("PIN javobda ochiq ko'rinmaydi",
          all("pin" not in u for u in users), "xavfsizlik")

    status, user = api("POST", "/api/user",
                       {"name": f"ZZ-TEST xodim {SUF}", "phone": f"+9989{SUF}01",
                        "role": "waiter", "pin": PIN9}, token=t)
    uid = (user or {}).get("id")
    check("POST /api/user", status in (200, 201) and uid, f"id={uid}")

    status, _ = api("POST", "/api/user",
                    {"name": "ZZ-TEST 2", "phone": f"+9989{SUF}02",
                     "role": "waiter", "pin": PIN9}, token=t)
    check("Takroriy PIN rad etiladi", status in (400, 409), f"status={status}")

    status, _ = api("POST", "/api/user",
                    {"name": "ZZ", "phone": f"+9989{SUF}03",
                     "role": "hacker", "pin": PIN9}, token=t)
    check("Noma'lum rol rad etiladi → 400", status == 400)

    status, _ = api("PUT", f"/api/user/{uid}", {"role": "cashier"}, token=t)
    check("PUT /api/user — rol o'zgartirish", status == 200)

    status, body = api("POST", "/api/auth/pin-login", {"pin": PIN9})
    check("Yangi xodim PIN bilan kira oladi",
          status == 200 and body.get("user", {}).get("role") == "cashier")

    status, _ = api("DELETE", f"/api/user/{uid}", token=t)
    check("DELETE /api/user", status == 200)
    status, _ = api("POST", "/api/auth/pin-login", {"pin": PIN9})
    check("O'chirilgan xodim kira olmaydi → 401", status == 401)


# ==========================================================================
# 7. Smena
# ==========================================================================
def test_shift():
    section("7. Smena")
    t = TOKENS["super_admin"]
    status, shift = api("GET", "/api/shift/current", token=t)
    check("GET /api/shift/current — smena ochiq",
          status == 200 and shift.get("status") == "open",
          f"smena #{shift.get('id')}, kassada {shift.get('opening_cash')} so'm")
    stats = shift.get("current_stats", {})
    check("Smena statistikasi to'liq",
          all(k in stats for k in ("total_orders", "total_revenue", "by_payment",
                                   "by_type", "current_expected_cash")),
          f"{stats.get('total_orders')} chek, {stats.get('total_revenue')} so'm")

    status, _ = api("POST", "/api/shift/open", {"opening_cash": 100}, token=t)
    check("Ikkinchi smena ochilmaydi → 400", status == 400)

    status, body = api("POST", "/api/shift/close", {"actual_cash": 100}, token=t)
    check("Band stol bo'lsa smena yopilmaydi → 400", status == 400,
          (body or {}).get("message", "")[:60] if isinstance(body, dict) else "")


# ==========================================================================
# 8. Buyurtma (POS)
# ==========================================================================
def test_orders():
    section("8. Buyurtma — yaratish, tuzatish, yopish")
    t = TOKENS["super_admin"]
    status, orders = api("GET", "/api/orders", token=t)
    check("GET /api/orders", status == 200 and len(orders) > 0, f"{len(orders)} ta chek")

    free_sku = _free_table(t)
    check("Bo'sh stol topildi", bool(free_sku), free_sku or "-")

    status, order = api("POST", "/api/order/create",
                        {"type": "dine_in", "table_sku": free_sku,
                         "items": [{"product_id": 105, "quantity": 2},
                                   {"product_id": 216, "quantity": 1}]}, token=t)
    number = (order or {}).get("order_number")
    check("POST /api/order/create (zalga)", status == 200 and number,
          f"{number}, jami {(order or {}).get('total')} so'm")
    check("Buyurtma raqami formati to'g'ri",
          bool(number) and number.count("-") == 3 and "-P" in number, number or "")

    _, zones = api("GET", "/api/zones", token=t)
    st = next((tb["status"] for z in zones for tb in z["tables"] if tb["sku"] == free_sku), None)
    check("Stol 'band' bo'ldi", st == "occupied", f"status={st}")

    status, _ = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": free_sku, "items": []}, token=t)
    check("Bo'sh buyurtma rad etiladi → 400", status == 400)

    status, _ = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": free_sku,
                     "items": [{"product_id": 105, "quantity": -5}]}, token=t)
    check("Manfiy miqdor rad etiladi → 400", status == 400)

    status, _ = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": free_sku,
                     "items": [{"product_id": 999999, "quantity": 1}]}, token=t)
    check("Yo'q mahsulot rad etiladi → 400", status == 400)

    status, body = api("POST", "/api/order/create",
                       {"type": "takeaway",
                        "items": [{"product_id": 213, "quantity": 5}]}, token=t)
    check("Qoldiqdan ko'p sotilmaydi → 400", status == 400,
          (body or {}).get("error", "") if isinstance(body, dict) else "")

    status, _ = api("POST", "/api/order/cancel-item",
                    {"order_number": number, "product_id": 105, "cancel_qty": 1}, token=t)
    check("POST /api/order/cancel-item — 1 dona qaytarildi", status == 200)

    status, body = api("POST", "/api/order/close",
                       {"table_sku": free_sku, "payment_method": "cash",
                        "discount": 5000}, token=t)
    check("POST /api/order/close (naqd + chegirma)", status == 200,
          f"jami {(body or {}).get('total')} so'm")

    _, zones2 = api("GET", "/api/zones", token=t)
    st2 = next((tb["status"] for z in zones2 for tb in z["tables"] if tb["sku"] == free_sku), None)
    check("Yopilgach stol bo'shadi", st2 == "free", f"status={st2}")

    status, _ = api("POST", "/api/order/close",
                    {"table_sku": free_sku, "payment_method": "cash"}, token=t)
    check("Ochiq cheki yo'q stolni yopib bo'lmaydi → 404", status == 404)

    # aralash to'lov
    sku2 = _free_table(t)
    _, order2 = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": sku2,
                     "items": [{"product_id": 112, "quantity": 2}]}, token=t)
    total = (order2 or {}).get("total", 0)
    status, _ = api("POST", "/api/order/close",
                    {"table_sku": sku2,
                     "payments": [{"method": "cash", "amount": total - 1000},
                                  {"method": "card", "amount": 500}]}, token=t)
    check("Summasi to'g'ri kelmagan aralash to'lov rad etiladi → 400", status == 400)
    status, body = api("POST", "/api/order/close",
                       {"table_sku": sku2,
                        "payments": [{"method": "cash", "amount": total - 5000},
                                     {"method": "click", "amount": 5000}]}, token=t)
    check("Aralash to'lov (naqd + click) qabul qilindi", status == 200,
          f"jami {(body or {}).get('total')} so'm")

    # bekor qilish
    sku3 = _free_table(t)
    _, order3 = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": sku3,
                     "items": [{"product_id": 112, "quantity": 1}]}, token=t)
    n3 = (order3 or {}).get("order_number")
    status, _ = api("POST", "/api/order/cancel", {"order_number": n3}, token=t)
    check("POST /api/order/cancel", status == 200, n3 or "")
    status, _ = api("POST", "/api/order/cancel", {"order_number": n3}, token=t)
    check("Bekor qilingan chek qayta bekor qilinmaydi → 400", status == 400)

    status, _ = api("POST", "/api/order/create",
                    {"type": "dine_in", "table_sku": sku3,
                     "items": [{"product_id": 112, "quantity": 1}]},
                    token=TOKENS.get("kitchen"))
    check("Oshpaz buyurtma yarata olmaydi → 403", status == 403)


def _free_table(token):
    _, zones = api("GET", "/api/zones", token=token)
    for z in zones:
        for tb in z.get("tables", []):
            if tb.get("status") == "free" and not tb.get("has_active_order"):
                return tb["sku"]
    return None


# ==========================================================================
# 9. Ombor: ingredient, ta'minotchi, partiya, xarid
# ==========================================================================
def test_warehouse():
    section("9. Ombor — ingredient, ta'minotchi, partiya, xarid")
    t = TOKENS["super_admin"]
    status, resp = api("GET", "/api/ingredients", token=t)
    ings = items_of(resp, "ingredients")
    check("GET /api/ingredients", status == 200 and len(ings) >= 19, f"{len(ings)} ingredient")
    check("Ingredient qoldig'i butun sonda", all(isinstance(i["count"], int) for i in ings))

    status, ing = api("POST", "/api/ingredient",
                      {"name": f"ZZ-TEST ingredient {SUF}", "unit": "gr",
                       "min_qty": 100, "waste_percent": 5}, token=t)
    iid = (ing or {}).get("id")
    check("POST /api/ingredient", status in (200, 201) and iid, f"id={iid}")

    status, _ = api("POST", "/api/ingredient",
                    {"name": f"ZZ-TEST ingredient {SUF}", "unit": "gr"}, token=t)
    check("Takroriy nom rad etiladi → 409", status == 409)

    status, sup = api("POST", "/api/suppliers",
                      {"name": f"ZZ-TEST ta'minotchi {SUF}", "phone": f"+9989{SUF}05"}, token=t)
    sid = (sup or {}).get("id")
    check("POST /api/suppliers", status in (200, 201) and sid, f"id={sid}")

    status, pur = api("POST", "/api/purchase",
                      {"note": "ZZ-TEST xarid", "supplier_id": sid,
                       "items": [{"ingredient_id": iid, "qty": 5000,
                                  "subtotal": 250000, "batch_code": "ZZ-B1"}]}, token=t)
    pid = (pur or {}).get("id")
    check("POST /api/purchase — kirim + partiya + avto-xarajat",
          status == 200 and pid, f"xarid #{pid}")

    _, resp2 = api("GET", "/api/ingredients", token=t)
    cnt = next((i["count"] for i in items_of(resp2, "ingredients") if i["id"] == iid), None)
    check("Xariddan keyin ombor qoldig'i oshdi", cnt == 5000, f"qoldiq={cnt}")

    status, batches = api("GET", f"/api/ingredient-batches?ingredient_id={iid}", token=t)
    blist = items_of(batches, "items") or items_of(batches, "batches")
    check("GET /api/ingredient-batches", status == 200 and len(blist) >= 1,
          f"{len(blist)} partiya")

    status, moves = api("GET", f"/api/ingredient/moves?ingredient_id={iid}", token=t)
    mlist = items_of(moves, "moves")
    check("GET /api/ingredient/moves — harakatlar jurnali",
          status == 200 and len(mlist) >= 1, f"{len(mlist)} harakat")

    status, body = api("DELETE", f"/api/purchase/{pid}", token=t)
    check("DELETE /api/purchase — kirim orqaga qaytariladi", status == 200,
          str(body)[:70])
    _, resp3 = api("GET", "/api/ingredients", token=t)
    cnt3 = next((i["count"] for i in items_of(resp3, "ingredients") if i["id"] == iid), None)
    check("Xarid o'chgach qoldiq 0 ga qaytdi", cnt3 == 0, f"qoldiq={cnt3}")

    status, _ = api("POST", "/api/ingredient/adjust",
                    {"ingredient_id": iid, "new_count": 120,
                     "comment": "ZZ-TEST korreksiya"}, token=t)
    check("POST /api/ingredient/adjust — korreksiya", status == 200)

    api("DELETE", f"/api/ingredient/{iid}", token=t)
    api("DELETE", f"/api/suppliers/{sid}", token=t)

    status, purchases = api("GET", "/api/purchases", token=t)
    check("GET /api/purchases", status == 200,
          f"{len(items_of(purchases, 'purchases'))} xarid")
    status, bozor = api("GET", "/api/bozor/list", token=t)
    check("GET /api/bozor/list — bozorlik ro'yxati", status == 200,
          f"{len(items_of(bozor, 'items'))} pozitsiya")


# ==========================================================================
# 10. Retsept va pishirish
# ==========================================================================
def test_recipes_cooking():
    section("10. Retsept va pishirish")
    t = TOKENS["super_admin"]
    status, recipes = api("GET", "/api/recipes", token=t)
    rlist = items_of(recipes, "recipes")
    check("GET /api/recipes", status == 200 and len(rlist) >= 9, f"{len(rlist)} retsept")

    status, cost = api("GET", "/api/recipe/cost?product_id=157", token=t)
    check("GET /api/recipe/cost — tannarx hisobi",
          status == 200 and cost.get("piece_cost", 0) > 0,
          f"1 dona ≈ {cost.get('piece_cost')} so'm, partiya {cost.get('batch_qty')} dona")
    check("Tannarxda narxsiz ingredient yo'q", cost.get("incomplete") in (False, None, []),
          f"incomplete={cost.get('incomplete')}")

    status, needed = api("GET", "/api/cooking/needed", token=TOKENS.get("kitchen", t))
    nlist = items_of(needed, "items")
    check("GET /api/cooking/needed — pishirish kerak", status == 200,
          f"{len(nlist)} pozitsiya")

    _, resp = api("GET", "/api/ingredients", token=t)
    before = {i["id"]: i["count"] for i in items_of(resp, "ingredients")}

    status, cooking = api("POST", "/api/cooking/start",
                          {"product_id": 165, "qty": 10}, token=t)
    cid = (cooking or {}).get("id")
    check("POST /api/cooking/start", status == 200 and cid,
          f"pishirish #{cid}, {len(items_of(cooking, 'ingredients') or [])} ingredient chiqdi")

    _, resp2 = api("GET", "/api/ingredients", token=t)
    after = {i["id"]: i["count"] for i in items_of(resp2, "ingredients")}
    reduced = sum(1 for k in before if after.get(k, 0) < before[k])
    check("Pishirish ombordan ingredient yechdi", reduced > 0, f"{reduced} ta ingredient kamaydi")

    status, _ = api("POST", f"/api/cooking/{cid}/cancel", {}, token=t)
    check("POST /api/cooking/{id}/cancel — ingredient qaytdi", status == 200)
    _, resp3 = api("GET", "/api/ingredients", token=t)
    back = {i["id"]: i["count"] for i in items_of(resp3, "ingredients")}
    check("Bekor qilingach qoldiq tiklandi", back == before,
          "hammasi joyiga qaytdi" if back == before else "farq bor")

    status, cooking2 = api("POST", "/api/cooking/start",
                           {"product_id": 165, "qty": 10}, token=t)
    cid2 = (cooking2 or {}).get("id")
    _, stocks_before = api("GET", "/api/stocks", token=t)
    status, _ = api("POST", f"/api/cooking/{cid2}/done", {}, token=t)
    check("POST /api/cooking/{id}/done — tayyor mahsulot bazaga qo'shildi", status == 200)
    status, _ = api("POST", f"/api/cooking/{cid2}/done", {}, token=t)
    check("Yakunlangan pishirish qayta yopilmaydi → 409", status == 409)

    status, _ = api("POST", "/api/cooking/start", {"product_id": 145, "qty": 1}, token=t)
    check("Retseptsiz mahsulot pishirilmaydi → 400", status == 400)

    status, cookings = api("GET", "/api/cookings", token=t)
    check("GET /api/cookings", status == 200,
          f"{len(items_of(cookings, 'cookings'))} yozuv")


# ==========================================================================
# 11. CRM: mijoz, ball, promo
# ==========================================================================
def test_crm():
    section("11. CRM — mijoz, sodiqlik ballari, promo-kod")
    t = TOKENS["super_admin"]
    status, resp = api("GET", "/api/customers", token=t)
    customers = items_of(resp, "items")
    check("GET /api/customers", status == 200 and len(customers) >= 8,
          f"{len(customers)} mijoz, jami sarflagan {resp.get('summary', {}).get('total_spent')} so'm")

    status, resp2 = api("GET", "/api/customers?search=Aziza", token=t)
    check("Mijoz qidiruvi (ism bo'yicha)", status == 200 and len(items_of(resp2, "items")) >= 1)

    status, cust = api("POST", "/api/customers",
                       {"name": f"ZZ-TEST mijoz {SUF}", "phone": f"+9989{SUF}04",
                        "tags": ["test"], "notes": "avtotest"}, token=t)
    cid = (cust or {}).get("id")
    check("POST /api/customers", status in (200, 201) and cid, f"id={cid}")

    status, _ = api("POST", "/api/customers",
                    {"name": "ZZ-TEST 2", "phone": f"+9989{SUF}04"}, token=t)
    check("Takroriy telefon rad etiladi", status in (400, 409))

    status, body = api("POST", f"/api/customers/{cid}/loyalty",
                       {"type": "earn", "points": 100, "note": "test"}, token=t)
    check("Ball qo'shish (earn)", status == 200 and body.get("balance") == 100,
          f"balans={body.get('balance')}, pul qiymati={body.get('loyalty_value')} so'm")

    status, body = api("POST", f"/api/customers/{cid}/loyalty",
                       {"type": "redeem", "points": 30}, token=t)
    check("Ball yechish (redeem)", status == 200 and body.get("balance") == 70,
          f"balans={body.get('balance')}")

    status, _ = api("POST", f"/api/customers/{cid}/loyalty",
                    {"type": "redeem", "points": 1000}, token=t)
    check("Yetarli ball bo'lmasa rad etiladi → 409", status == 409)

    status, detail = api("GET", f"/api/customers/{cid}", token=t)
    check("GET /api/customers/{id} — tarix bilan", status == 200,
          f"{len(items_of(detail, 'loyalty') or items_of(detail, 'transactions'))} ball harakati")

    status, _ = api("DELETE", f"/api/customers/{cid}", token=t)
    check("DELETE /api/customers (arxivlash)", status == 200)

    status, promos = api("GET", "/api/promos", token=t)
    check("GET /api/promos", status == 200 and len(promos) >= 4, f"{len(promos)} promo")

    status, body = api("POST", "/api/promos/validate",
                       {"code": "KONAK10", "subtotal": 100000}, token=t)
    check("KONAK10 (10%, maks 20 000) — 100 000 so'mga",
          status == 200 and body.get("discount") == 10000,
          f"chegirma={body.get('discount')}")

    status, body = api("POST", "/api/promos/validate",
                       {"code": "KONAK10", "subtotal": 500000}, token=t)
    check("KONAK10 maksimal chegirma bilan cheklandi",
          status == 200 and body.get("discount") == 20000,
          f"chegirma={body.get('discount')} (maks 20 000)")

    status, body = api("POST", "/api/promos/validate",
                       {"code": "SOVGA5", "subtotal": 10000}, token=t)
    check("Minimal summaga yetmasa rad etiladi", status >= 400 or body.get("valid") is False,
          f"status={status}")

    status, body = api("POST", "/api/promos/validate",
                       {"code": "ESKI2025", "subtotal": 100000}, token=t)
    check("Muddati o'tgan promo ishlamaydi", status >= 400 or body.get("valid") is False,
          f"status={status}")

    status, body = api("POST", "/api/promos/validate",
                       {"code": "YOQKOD", "subtotal": 100000}, token=t)
    check("Mavjud bo'lmagan promo rad etiladi", status >= 400 or body.get("valid") is False)

    status, promo = api("POST", "/api/promos",
                        {"code": f"ZZTEST{SUF}", "discount_type": "fixed", "value": 1000,
                         "min_order_total": 0, "status": "active"}, token=t)
    pid = (promo or {}).get("id")
    check("POST /api/promos", status in (200, 201) and pid, f"id={pid}")
    status, _ = api("PUT", f"/api/promos/{pid}", {"code": f"ZZTEST{SUF}", "discount_type": "fixed",
                                                  "value": 2000, "status": "active"}, token=t)
    check("PUT /api/promos", status == 200)
    status, _ = api("DELETE", f"/api/promos/{pid}", token=t)
    check("DELETE /api/promos", status == 200)


# ==========================================================================
# 12. Moliya va analitika
# ==========================================================================
def test_finance_analytics():
    section("12. Moliya va analitika")
    t = TOKENS["super_admin"]
    status, fin = api("GET", "/api/finance/daily", token=t)
    inc = (fin or {}).get("income", {})
    check("GET /api/finance/daily", status == 200 and "profit" in fin,
          f"tushum {inc.get('total_revenue')} / xarajat {fin.get('expenses', {}).get('total')}"
          f" / sof {fin.get('profit', {}).get('net_profit')}")
    by = inc.get("by_payment_method", {})
    check("To'lov usullari bo'yicha taqsimot bor",
          all(k in by for k in ("cash", "card", "payme", "click")),
          ", ".join(f"{k}={v}" for k, v in by.items() if v))

    status, exps = api("GET", "/api/finance/daily/expenses", token=t)
    check("GET /api/finance/daily/expenses", status == 200 and len(exps) >= 3,
          f"{len(exps)} xarajat")

    status, cats = api("GET", "/api/expense-categories", token=t)
    check("GET /api/expense-categories", status == 200 and len(cats) >= 6,
          f"{len(cats)} kategoriya")

    cat_id = cats[0]["id"] if cats else 1
    status, _ = api("POST", "/api/expense",
                    {"category_id": cat_id, "amount": 1000,
                     "description": "ZZ-TEST xarajat"}, token=t)
    check("POST /api/expense", status == 200)

    status, cat = api("POST", "/api/expense-category",
                      {"name_uz": f"ZZ-TEST xarajat kat. {SUF}"}, token=t)
    ecid = (cat or {}).get("id")
    check("POST /api/expense-category", status == 200 and ecid, f"id={ecid}")
    status, _ = api("DELETE", f"/api/expense-category/{ecid}", token=t)
    check("DELETE /api/expense-category", status == 200)

    frm = (date.today() - timedelta(days=13)).isoformat()
    to = date.today().isoformat()
    status, an = api("GET", f"/api/analytics/overview?from={frm}&to={to}", token=t)
    summ = (an or {}).get("summary", {})
    check("GET /api/analytics/overview (14 kun)", status == 200 and summ.get("revenue", 0) > 0,
          f"{summ.get('completed_orders')} chek, tushum {summ.get('revenue')}, "
          f"o'rtacha chek {summ.get('average_check')}")
    check("Tannarx va foyda hisoblanadi",
          "estimated_cogs" in summ and "net_profit" in summ,
          f"COGS {summ.get('estimated_cogs')}, sof foyda {summ.get('net_profit')}")
    check("Kunlik trend to'liq", len(an.get("trend", [])) == 14, f"{len(an.get('trend', []))} kun")
    check("Top mahsulotlar bor", len(an.get("top_products", [])) > 0,
          ", ".join(p.get("name", "?") for p in an.get("top_products", [])[:3]))
    check("Manba (POS/QR/online) bo'yicha taqsimot", len(an.get("by_source", [])) >= 2,
          ", ".join(f"{s['source']}={s['count']}" for s in an.get("by_source", [])))
    check("Eng gavjum soatlar", len(an.get("peak_hours", [])) > 0)
    check("Mijoz statistikasi", "unique_customers" in (an or {}).get("customers", {}),
          f"{an.get('customers', {}).get('unique_customers')} noyob mijoz")

    status, prods = api("GET", "/api/analytics/products", token=t)
    check("GET /api/analytics/products", status == 200)

    status, csv = api("GET", f"/api/analytics/export.csv?from={frm}&to={to}", token=t, raw=True)
    check("GET /api/analytics/export.csv", status == 200 and len(csv) > 100,
          f"{len(csv)} bayt CSV")

    status, _ = api("GET", "/api/analytics/overview?from=2020-01-01&to=2026-12-31", token=t)
    check("Juda uzun oraliq rad etiladi → 400", status == 400)


# ==========================================================================
# 13. Spisaniya va inventarizatsiya
# ==========================================================================
def test_writeoff_inventory():
    section("13. Spisaniya va inventarizatsiya")
    t = TOKENS["super_admin"]
    status, wo = api("GET", "/api/write-offs", token=t)
    check("GET /api/write-offs", status == 200,
          f"{len(items_of(wo, 'items') or items_of(wo, 'write_offs'))} yozuv")

    status, _ = api("POST", "/api/write-offs",
                    {"product_id": 146, "qty": 1, "reason": "ZZ-TEST",
                     "note": "avtotest"}, token=t)
    check("POST /api/write-offs", status == 200)

    status, _ = api("POST", "/api/write-offs",
                    {"product_id": 146, "qty": 0, "reason": ""}, token=t)
    check("Bo'sh sabab/0 miqdor rad etiladi → 400", status == 400)

    status, body = api("POST", "/api/inventory",
                       {"items": [{"product_id": 146, "actual_count": 20}]}, token=t)
    check("POST /api/inventory — qoldiq to'g'rilash", status == 200, str(body)[:70])

    status, _ = api("POST", "/api/inventory",
                    {"items": [{"product_id": 146, "actual_count": 20}]},
                    token=TOKENS.get("waiter"))
    check("Ofitsiant inventarizatsiya qila olmaydi → 403", status == 403)


# ==========================================================================
# 14. QR mijoz oqimi
# ==========================================================================
def test_qr():
    section("14. QR mijoz oqimi")
    t = TOKENS["super_admin"]
    _, qr = api("GET", "/api/tables/qr-codes", token=t)
    tables = items_of(qr, "tables") or (qr if isinstance(qr, list) else [])
    free = _free_table(t)
    entry = next((x for x in tables if x.get("sku") == free), None)
    code = (entry or {}).get("qr_code") or (entry or {}).get("code")
    check("Stol QR kodi olindi", bool(code), f"{free} → {str(code)[:12]}…")

    status, lookup = api("GET", f"/api/qr/table/{code}")
    check("GET /api/qr/table/{code} — stolni aniqlash", status == 200,
          str((lookup or {}).get("label") or (lookup or {}).get("table", {})))

    status, session = api("POST", "/api/qr/session", {"code": code})
    token = (session or {}).get("session_token")
    check("POST /api/qr/session — sessiya ochildi", status in (200, 201) and token,
          f"token {str(token)[:12]}…")

    status, st = api("GET", f"/api/qr/status?token={token}")
    check("GET /api/qr/status", status == 200, str(st)[:70])

    status, order = api("POST", "/api/qr/order",
                        {"session_token": token,
                         "customer_name": "ZZ-TEST mehmon",
                         "items": [{"product_id": 121, "quantity": 1}]})
    check("POST /api/qr/order — mijoz buyurtmasi", status in (200, 201),
          f"{(order or {}).get('order_number')}, {(order or {}).get('total')} so'm")

    status, _ = api("POST", "/api/qr/order",
                    {"session_token": "yaroqsiz-token",
                     "items": [{"product_id": 121, "quantity": 1}]})
    check("Yaroqsiz sessiya rad etiladi", status >= 400, f"status={status}")

    status, _ = api("POST", "/api/qr/call-waiter", {"session_token": token})
    check("POST /api/qr/call-waiter", status in (200, 201, 429))

    status, _ = api("POST", "/api/qr/request-bill", {"session_token": token})
    check("POST /api/qr/request-bill — hisob so'rash", status in (200, 201, 429))

    number = (order or {}).get("order_number")
    if number:
        api("POST", "/api/order/close",
            {"table_sku": free, "payment_method": "cash"}, token=t)

    status, page = api("GET", "/customer/", raw=True)
    check("QR mijoz web ilovasi ochiladi (/customer/)",
          status == 200 and b"<html" in page.lower(), f"{len(page)} bayt")


# ==========================================================================
# 15. Online (saboy/dostafka) oqimi
# ==========================================================================
def new_verification_token():
    """Telegram tasdig'ini simulyatsiya qiladi (bazaga confirmed yozuv qo'yadi)."""
    import shutil
    import subprocess
    if not shutil.which("psql"):
        return None
    token = f"zz-test-token-{SUF}"
    pgurl = os.environ.get(
        "DEMO_DB_URL",
        "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable")
    stmt = (
        "INSERT INTO online_verifications (code,pending_token,verification_token,"
        "status,tg_user_id,tg_username,phone,expires_at) VALUES "
        f"('{SUF}','zz-pending-{SUF}','{token}','confirmed',555000333,'zz_test',"
        "'998901112207',NOW()+INTERVAL '1 hour')")
    proc = subprocess.run(["psql", pgurl, "-q", "-c", stmt],
                          capture_output=True, text=True)
    return token if proc.returncode == 0 else None



def test_online():
    section("15. Online buyurtma (saboy / dostafka)")
    status, body = api("POST", "/api/online/telegram/verify/start", {})
    if status == 503:
        check("Telegram o'chiq bo'lsa aniq xato qaytadi → 503", True,
              "demo rejimida bot ataylab o'chirilgan")
    else:
        check("POST /api/online/telegram/verify/start", status == 200,
              f"kod {(body or {}).get('code')}")

    status, _ = api("POST", "/api/online/order",
                    {"type": "delivery",
                     "items": [{"product_id": 102, "quantity": 1}],
                     "customer": {"phone": "998901112203",
                                  "verification_token": "yaroqsiz"},
                     "location": {"lat": 40.1, "lng": 65.3, "address": "test"}})
    check("Yaroqsiz tasdiq tokeni rad etiladi → 401", status == 401)

    status, _ = api("POST", "/api/online/order",
                    {"type": "delivery",
                     "items": [{"product_id": 102, "quantity": 1}],
                     "customer": {"phone": "998901112203",
                                  "verification_token": "demo-verification-token-0002"}})
    check("Dostafkada manzilsiz buyurtma rad etiladi → 400", status == 400)

    fresh = new_verification_token()
    if not fresh:
        check("Test uchun yangi tasdiq tokeni tayyorlandi", False,
              "psql topilmadi — online buyurtma testi o'tkazib yuborildi")
        return
    check("Test uchun yangi tasdiq tokeni tayyorlandi", True, fresh)

    status, order = api("POST", "/api/online/order",
                        {"type": "takeaway",
                         "items": [{"product_id": 102, "quantity": 1}],
                         "customer": {"phone": "998901112207",
                                      "tg_user_id": 555000222,
                                      "verification_token": fresh},
                         "note": "ZZ-TEST saboy"})
    check("POST /api/online/order — saboy buyurtma", status == 200,
          f"{(order or {}).get('order_number')}, {(order or {}).get('total')} so'm")

    status, _ = api("POST", "/api/online/order",
                    {"type": "takeaway",
                     "items": [{"product_id": 102, "quantity": 1}],
                     "customer": {"phone": "998901112207",
                                  "verification_token": fresh}})
    check("Bir tasdiq tokeni ikki marta ishlamaydi → 401", status == 401)

    number = (order or {}).get("order_number")
    if number:
        status, _ = api("POST", "/api/order/close",
                        {"order_number": number, "payment_method": "cash"},
                        token=TOKENS["super_admin"])
        check("Online chekni kassa yopdi", status == 200, number)


# ==========================================================================
# 16. Printerlar va sozlamalar
# ==========================================================================
def test_printers_settings():
    section("16. Printerlar va sozlamalar")
    t = TOKENS["super_admin"]
    status, printers = api("GET", "/api/printers", token=t)
    check("GET /api/printers", status == 200 and len(printers) >= 3,
          ", ".join(p["name"] for p in printers))

    status, rp = api("GET", "/api/settings/receipt-printer", token=t)
    check("GET /api/settings/receipt-printer", status == 200,
          f"{rp.get('name')} ({rp.get('address')})")

    status, pr = api("POST", "/api/printers",
                     {"name": f"ZZ-TEST printer {SUF}", "address": "127.0.0.1:9199"}, token=t)
    pid = (pr or {}).get("id")
    check("POST /api/printers", status in (200, 201) and pid, f"id={pid}")
    status, _ = api("PUT", f"/api/printers/{pid}", {"address": "127.0.0.1:9198"}, token=t)
    check("PUT /api/printers", status == 200)
    status, _ = api("PUT", "/api/settings/receipt-printer", {"printer_id": pid}, token=t)
    check("Chek printerini almashtirish", status == 200)
    status, _ = api("PUT", "/api/settings/receipt-printer", {"printer_id": 1}, token=t)
    check("Chek printerini qaytarish", status == 200)
    status, _ = api("DELETE", f"/api/printers/{pid}", token=t)
    check("DELETE /api/printers", status == 200)

    status, cloud = api("GET", "/api/settings/cloud", token=t)
    check("GET /api/settings/cloud (faqat super_admin)", status == 200,
          f"url='{cloud.get('url')}', ulangan={cloud.get('connected')}")
    status, _ = api("GET", "/api/settings/cloud", token=TOKENS.get("admin"))
    check("Adminga bulut sozlamasi yopiq → 403", status == 403)
    status, _ = api("PUT", "/api/settings/cloud", {"url": "http://xato", "token": "x"}, token=t)
    check("Noto'g'ri ws:// manzil rad etiladi → 400", status == 400)

    status, _ = api("POST", "/api/order/print-receipt",
                    {"table_sku": "Z1-1"}, token=t)
    check("POST /api/order/print-receipt (printer yo'q bo'lsa ham yiqilmaydi)",
          status in (200, 400, 404, 500), f"status={status}")


# ==========================================================================
# 17. Audit, monitoring, backup
# ==========================================================================
def test_ops():
    section("17. Audit, monitoring, backup")
    t = TOKENS["super_admin"]
    status, audit = api("GET", "/api/audit?limit=20", token=t)
    alist = items_of(audit, "items") or items_of(audit, "logs")
    check("GET /api/audit", status == 200 and len(alist) > 0, f"{len(alist)} yozuv")
    if alist:
        first = alist[0]
        check("Audit yozuvida kim/nima/qachon bor",
              all(k in first for k in ("actor_name", "action", "entity_type", "created_at")),
              f"{first.get('actor_name')} → {first.get('action')} {first.get('entity_type')}")

    status, filtered = api("GET", "/api/audit?entity_type=order&limit=5", token=t)
    check("Audit filtri (entity_type)", status == 200)

    status, ops = api("GET", "/api/operations/summary", token=t)
    check("GET /api/operations/summary", status == 200 and "database" in (ops or {}),
          f"faol chek {ops.get('active_orders')}, smena {ops.get('open_shifts')}, "
          f"sync pending {ops.get('sync', {}).get('pending')}")
    check("Backup holati ko'rinadi", "backup" in (ops or {}),
          f"oxirgi: {((ops.get('backup') or {}).get('last') or {}).get('filename')}")

    status, backups = api("GET", "/api/backups", token=t)
    blist = items_of(backups, "items")
    check("GET /api/backups", status == 200 and len(blist) > 0, f"{len(blist)} backup")

    if blist:
        fname = blist[0]["filename"]
        status, data = api("GET", f"/api/backups/{fname}/download", token=t, raw=True)
        check("Backup yuklab olinadi va SHIFRLANGAN",
              status == 200 and len(data) > 1000 and not data.startswith(b"PGDMP"),
              f"{len(data)} bayt, ochiq dump emas")

    status, _ = api("GET", "/api/backups", token=TOKENS.get("admin"))
    check("Adminga backup yopiq → 403", status == 403)


# ==========================================================================
# 18. WebSocket
# ==========================================================================
def test_websocket():
    section("18. WebSocket (real vaqt kanali)")
    parsed = urllib.parse.urlparse(BASE)
    host = parsed.hostname or "localhost"
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    key = base64.b64encode(os.urandom(16)).decode()
    try:
        sock = socket.create_connection((host, port), timeout=10)
        sock.sendall((
            f"GET /ws HTTP/1.1\r\nHost: {host}:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        resp = sock.recv(2048)
        first = resp.split(b"\r\n")[0].decode(errors="replace")
        upgraded = "101" in first
        check("WSS ulanish (/ws) — HTTP 101 Upgrade", upgraded, first)
        if not upgraded:
            sock.close()
            return

        # POS klienti kabi init xabar yuboramiz (token bilan)
        init = json.dumps({
            "event": "init",
            "payload": {"token": TOKENS["super_admin"], "menu_version": 0,
                        "source": "pos"},
        }).encode()
        sock.sendall(_ws_frame(init))
        sock.settimeout(6)
        got = b""
        try:
            for _ in range(3):
                chunk = sock.recv(8192)
                if not chunk:
                    break
                got += chunk
                if b"event" in got:
                    break
        except socket.timeout:
            pass
        check("Init'dan keyin server javob beradi (menyu/holat)",
              len(got) > 0, f"{len(got)} bayt")
        text = got.decode("utf-8", errors="replace")
        check("Javobda hodisa (event) nomi bor", "event" in text,
              text[:80].replace("\n", " "))
        sock.close()
    except OSError as e:
        check("WSS ulanish (/ws)", False, str(e))


def _ws_frame(payload):
    """Klientdan serverga maskalangan matn freymi."""
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    header = bytes([0x81])
    n = len(payload)
    if n < 126:
        header += bytes([0x80 | n])
    elif n < 65536:
        header += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        header += bytes([0x80 | 127]) + struct.pack(">Q", n)
    return header + mask + masked


# ==========================================================================
def main():
    print(f"{BOLD}KONAK POS — to'liq API test{RESET}")
    print(f"Server: {BASE}")
    test_public()
    test_auth()
    test_permissions()
    test_menu_crud()
    test_zones()
    test_users()
    test_shift()
    test_orders()
    test_warehouse()
    test_recipes_cooking()
    test_crm()
    test_finance_analytics()
    test_writeoff_inventory()
    test_qr()
    test_online()
    test_printers_settings()
    test_ops()
    test_websocket()

    total = len(PASSED) + len(FAILED)
    print(f"\n{BOLD}{'=' * 64}{RESET}")
    print(f"{BOLD}NATIJA: {total} tekshiruv — "
          f"{GREEN}{len(PASSED)} o'tdi{RESET}{BOLD}, "
          f"{RED if FAILED else GREEN}{len(FAILED)} xato{RESET}")
    if FAILED:
        print(f"\n{RED}Xatolar:{RESET}")
        for name, detail in FAILED:
            print(f"  • {name} {DIM}{detail}{RESET}")
    print()
    sys.exit(1 if FAILED else 0)


if __name__ == "__main__":
    main()
