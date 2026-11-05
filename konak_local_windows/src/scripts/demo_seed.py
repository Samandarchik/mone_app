#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
KONAK POS — demo/test bazasini to'ldirish.

Nima qiladi: ishlab turgan local backendga (default http://localhost:3000)
API orqali murojaat qilib, tizimning HAMMA moduli uchun ko'rsatiladigan
ma'lumot yaratadi — menyu (Windows master'dagi joriy menyu), zona/stol,
xodimlar, ombor (ingredient/ta'minotchi/partiya/retsept), pishirish, CRM,
promo, xarajat, smena va 2 haftalik buyurtma tarixi (analitika uchun).

Ishlatish:
    python3 scripts/demo_seed.py
    KONAK_URL=http://localhost:3000 python3 scripts/demo_seed.py

Eslatma: tarixiy buyurtmalar API orqali yaratib bo'lmaydi (API doim NOW()
ishlatadi), shuning uchun ular to'g'ridan-to'g'ri SQL bilan yoziladi.
"""

import json
import os
import random
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta

BASE = os.environ.get("KONAK_URL", "http://localhost:3000").rstrip("/")
PGURL = os.environ.get(
    "DEMO_DB_URL", "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable"
)
ADMIN_PHONE = os.environ.get("KONAK_ADMIN_PHONE", "+998901234567")
ADMIN_PIN = os.environ.get("KONAK_ADMIN_PIN", "1234")
HERE = os.path.dirname(os.path.abspath(__file__))
SNAPSHOT = os.path.join(HERE, "menu_snapshot.json")

random.seed(20260816)  # takrorlanadigan demo

TOKEN = None
STEP = 0


# --------------------------------------------------------------------------
# yordamchilar
# --------------------------------------------------------------------------
def step(title):
    global STEP
    STEP += 1
    print(f"\n=== {STEP:02d}. {title} " + "=" * max(0, 56 - len(title)))


def ok(msg):
    print(f"   ✓ {msg}")


def warn(msg):
    print(f"   ! {msg}")


def api(method, path, body=None, token="auto", expect=(200, 201)):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    tok = TOKEN if token == "auto" else token
    if tok:
        req.add_header("Authorization", "Bearer " + tok)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            status = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        status = e.code
    except urllib.error.URLError as e:
        print(f"\nXATO: {BASE} ga ulanib bo'lmadi ({e}). Backend ishga tushganmi?")
        sys.exit(1)
    try:
        parsed = json.loads(raw) if raw else None
    except json.JSONDecodeError:
        parsed = raw
    if expect and status not in expect:
        raise RuntimeError(f"{method} {path} → {status}: {raw[:300]}")
    return parsed


def sql(statement):
    """Bitta SQL buyrug'ini psql orqali bajaradi."""
    proc = subprocess.run(
        ["psql", PGURL, "-v", "ON_ERROR_STOP=1", "-q", "-c", statement],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"SQL xato: {proc.stderr.strip()[:400]}")
    return proc.stdout


def sql_file(text):
    """Katta SQL blokini vaqtinchalik fayl orqali bajaradi."""
    path = os.path.join("/tmp", "konak_demo_seed.sql")
    with open(path, "w") as fh:
        fh.write(text)
    proc = subprocess.run(
        ["psql", PGURL, "-v", "ON_ERROR_STOP=1", "-q", "-f", path],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"SQL xato: {proc.stderr.strip()[:600]}")
    return proc.stdout


def scalar(query):
    proc = subprocess.run(
        ["psql", PGURL, "-tAq", "-c", query], capture_output=True, text=True
    )
    return proc.stdout.strip()


def money(value):
    """1234567 → "1 234 567"."""
    return f"{int(value):,}".replace(",", " ")


def q(value):
    """SQL uchun matnni qochirish."""
    return "'" + str(value).replace("'", "''") + "'"


def items_of(resp, key):
    """API ba'zan ro'yxatni {"key": [...]} ichida qaytaradi."""
    if isinstance(resp, dict):
        return resp.get(key, [])
    return resp or []


# --------------------------------------------------------------------------
# 01. Login
# --------------------------------------------------------------------------
def login():
    global TOKEN
    step("super_admin bilan kirish")
    resp = api(
        "POST", "/api/auth/login", {"phone": ADMIN_PHONE, "pin": ADMIN_PIN}, token=None
    )
    TOKEN = resp["token"]
    ok(f"{resp['user']['name']} ({resp['user']['role']}) — token olindi")


# --------------------------------------------------------------------------
# 02. Eski sinov ma'lumotlarini yopish
# --------------------------------------------------------------------------
def cleanup():
    step("Eski sinov ma'lumotlarini tozalash")
    shift = api("GET", "/api/shift/current")
    if isinstance(shift, dict) and shift.get("status") == "open":
        api("POST", "/api/shift/close", {"actual_cash": 0}, expect=(200, 400))
        ok("ochiq qolgan eski smena yopildi")
    for pid in json.loads(scalar(
        "SELECT COALESCE(json_agg(id)::text,'[]') FROM products "
        "WHERE status<>'deleted' AND id < 90"
    )):
        api("DELETE", f"/api/product/{pid}", expect=(200,))
        ok(f"sinov mahsuloti #{pid} arxivlandi")
    for cid in json.loads(scalar(
        "SELECT COALESCE(json_agg(id)::text,'[]') FROM categories "
        "WHERE status<>'deleted' AND id < 10"
    )):
        api("DELETE", f"/api/category/{cid}", expect=(200, 400))
        ok(f"sinov kategoriyasi #{cid} arxivlandi")


# --------------------------------------------------------------------------
# 03. Printerlar
# --------------------------------------------------------------------------
PRINTERS = [
    ("Kassa printeri", "127.0.0.1:9100"),
    ("Oshxona printeri", "127.0.0.1:9101"),
    ("Bar printeri", "127.0.0.1:9102"),
]


def seed_printers():
    step("Printer stansiyalari")
    existing = {p["name"]: p["id"] for p in api("GET", "/api/printers")}
    ids = {}
    for name, addr in PRINTERS:
        if name in existing:
            ids[name] = existing[name]
            ok(f"{name} — mavjud (#{existing[name]})")
            continue
        resp = api("POST", "/api/printers", {"name": name, "address": addr})
        ids[name] = resp["id"]
        ok(f"{name} → {addr} (#{resp['id']})")
    api("PUT", "/api/settings/receipt-printer", {"printer_id": ids["Kassa printeri"]})
    ok("chek printeri = Kassa printeri")
    return ids


# --------------------------------------------------------------------------
# 04. Menyu (Windows master'dagi joriy menyu, ID'lar bir xil)
# --------------------------------------------------------------------------
BAR_CATEGORIES = {10, 11, 12, 13, 14, 15}  # ichimliklar → Bar
KITCHEN_CATEGORIES = {16, 17, 18, 19, 20}  # taom/desert → Oshxona


def seed_menu(printer_ids):
    step("Menyu importi (joriy menyu — Windows master nusxasi)")
    if scalar("SELECT COUNT(*) FROM products WHERE id BETWEEN 94 AND 225") != "0":
        ok("menyu allaqachon import qilingan — o'tkazib yuborildi")
        return
    with open(SNAPSHOT) as fh:
        menu = json.load(fh)

    bar = printer_ids["Bar printeri"]
    kitchen = printer_ids["Oshxona printeri"]
    lines = ["BEGIN;"]
    for c in menu["categories"]:
        station = bar if c["id"] in BAR_CATEGORIES else kitchen
        lines.append(
            "INSERT INTO categories (id,name_uz,name_ru,name_tr,icon,sort_order,"
            "status,printer_station_id) VALUES "
            f"({c['id']},{q(c['name']['uz'])},{q(c['name']['ru'])},"
            f"{q(c['name']['tr'])},{q(c.get('icon') or '')},{c['sort_order']},"
            f"'active',{station}) ON CONFLICT (id) DO NOTHING;"
        )
    for p in menu["products"]:
        lines.append(
            "INSERT INTO products (id,name_uz,name_ru,name_tr,description_uz,"
            "description_ru,description_tr,category_id,price,media,status,"
            "is_recommended,sort_order,product_type) VALUES "
            f"({p['id']},{q(p['name']['uz'])},{q(p['name']['ru'])},"
            f"{q(p['name']['tr'])},'','','',{p['category_id']},{p['price']},"
            f"'[]'::jsonb,'active',false,{p['sort_order']},'ready') "
            "ON CONFLICT (id) DO NOTHING;"
        )
    lines += [
        "SELECT setval('categories_id_seq',(SELECT MAX(id) FROM categories));",
        "SELECT setval('products_id_seq',(SELECT MAX(id) FROM products));",
        "INSERT INTO stocks (product_id,count) SELECT id,0 FROM products "
        "WHERE id NOT IN (SELECT product_id FROM stocks);",
        "UPDATE menu_version SET version=version+1,updated_at=NOW() WHERE id=1;",
        "COMMIT;",
    ]
    sql_file("\n".join(lines))
    ok(f"{len(menu['categories'])} kategoriya, {len(menu['products'])} mahsulot "
       f"(ID 10–20 / 94–225 — Windows bilan bir xil)")


# --------------------------------------------------------------------------
# 05. Zona va stollar
# --------------------------------------------------------------------------
def seed_zones():
    step("Zona va stollar")
    zones = api("GET", "/api/zones")
    have = {z["name"]["uz"] if isinstance(z["name"], dict) else z["name"] for z in zones}
    for name, count in (("ZAL", 12), ("TASHQARI", 7)):
        if name in have:
            ok(f"{name} — mavjud")
            continue
        resp = api("POST", "/api/zone", {"name": name, "count": count})
        ok(f"{name} — {count} ta stol (zona #{resp['id']}, SKU Z{resp['id']}-1..{count})")


# --------------------------------------------------------------------------
# 06. Xodimlar
# --------------------------------------------------------------------------
STAFF = [
    ("Dilshod Karimov", "+998901112233", "admin", "1111", None),
    ("Nodira Yusupova", "+998902223344", "cashier", "2222", None),
    ("Aziz Rahimov", "+998903334455", "waiter", "3333", None),
    ("Sardor Qodirov", "+998904445566", "kitchen", "4444", None),
    (
        "Malika Tosheva",
        "+998905556677",
        "waiter",
        "5555",
        # ofitsiant, lekin qo'shimcha ruxsat: chek yopa oladi
        {"orders": ["create", "read", "add_items", "close"], "payments": ["create", "read"]},
    ),
]


def seed_users():
    step("Xodimlar (har rol uchun bittadan)")
    have = {u["phone"] for u in api("GET", "/api/users")}
    for name, phone, role, pin, perms in STAFF:
        if phone in have:
            ok(f"{name} — mavjud")
            continue
        body = {"name": name, "phone": phone, "role": role, "pin": pin}
        if perms:
            body["custom_permissions"] = perms
        resp = api("POST", "/api/user", body)
        extra = " (+ maxsus ruxsat)" if perms else ""
        ok(f"{name} — {role}, PIN {pin}{extra} (#{resp.get('id')})")


# --------------------------------------------------------------------------
# 07. Xarajat kategoriyalari va xarajatlar
# --------------------------------------------------------------------------
EXPENSE_CATEGORIES = [
    ("Ijara", "Аренда", "Kira"),
    ("Kommunal", "Коммунальные", "Faturalar"),
    ("Oylik", "Зарплата", "Maaş"),
    ("Bozor", "Базар", "Pazar"),
    ("Marketing", "Маркетинг", "Pazarlama"),
    ("Boshqa", "Прочее", "Diğer"),
]


def seed_expense_categories():
    step("Xarajat kategoriyalari")
    have = {c["name_uz"]: c["id"] for c in api("GET", "/api/expense-categories")}
    ids = {}
    for uz, ru, tr in EXPENSE_CATEGORIES:
        if uz in have:
            ids[uz] = have[uz]
            ok(f"{uz} — mavjud")
            continue
        resp = api(
            "POST", "/api/expense-category", {"name_uz": uz, "name_ru": ru, "name_tr": tr}
        )
        ids[uz] = resp["id"]
        ok(f"{uz} (#{resp['id']})")
    return ids


def seed_expenses(cat_ids):
    step("Bugungi xarajatlar")
    if int(scalar(
        "SELECT COUNT(*) FROM expenses WHERE date = CURRENT_DATE::text "
        "AND description = 'Instagram reklama'"
    )) > 0:
        ok("bugungi xarajatlar allaqachon kiritilgan — o'tkazib yuborildi")
        return
    # Bugungilar — kichik, kunlik xarajatlar (oylik ijara/oylik tarixda turadi),
    # shunda smena ekranidagi "kassada kutilayotgan pul" real chiqadi.
    rows = [
        ("Bozor", 250_000, "Ertalabki non va ko'kat"),
        ("Marketing", 300_000, "Instagram reklama"),
        ("Boshqa", 120_000, "Salfetka, bir martalik idish"),
    ]
    for cat, amount, desc in rows:
        api(
            "POST",
            "/api/expense",
            {"category_id": cat_ids[cat], "amount": amount, "description": desc},
        )
        ok(f"{cat}: {money(amount)} so'm — {desc}")


# --------------------------------------------------------------------------
# 08. Ombor: ingredientlar
# --------------------------------------------------------------------------
INGREDIENTS = [
    # (nom, birlik, min_qty, waste %)
    ("Un", "gr", 5_000, 2),
    ("Shakar", "gr", 3_000, 1),
    ("Sut", "ml", 5_000, 2),
    ("Tuxum", "dona", 30, 3),
    ("Sariyog'", "gr", 2_000, 2),
    ("Qaymoq 33%", "ml", 2_000, 2),
    ("Krem-pishloq", "gr", 2_000, 2),
    ("Oq shokolad", "gr", 1_000, 1),
    ("Qora shokolad", "gr", 1_000, 1),
    ("Kakao", "gr", 500, 1),
    ("Kofe doni", "gr", 2_000, 3),
    ("Qora choy", "gr", 1_000, 2),
    ("Matcha kukuni", "gr", 300, 2),
    ("Limon", "dona", 10, 5),
    ("Pista", "gr", 500, 2),
    ("Oreo pechenye", "gr", 500, 2),
    ("Labne (tvorog)", "gr", 1_000, 2),
    ("Kunjut", "gr", 300, 1),
    ("Vanilin", "gr", 100, 0),
]


def seed_ingredients():
    step("Ombor — ingredientlar")
    have = {i["name"]: i["id"] for i in items_of(api("GET", "/api/ingredients"), "ingredients")}
    ids = {}
    for name, unit, min_qty, waste in INGREDIENTS:
        if name in have:
            ids[name] = have[name]
            ok(f"{name} — mavjud")
            continue
        resp = api(
            "POST",
            "/api/ingredient",
            {"name": name, "unit": unit, "min_qty": min_qty, "waste_percent": waste},
        )
        ids[name] = resp["id"]
        ok(f"{name} ({unit}, min {min_qty}, chiqindi {waste}%) — #{resp['id']}")
    return ids


# --------------------------------------------------------------------------
# 09. Ta'minotchilar
# --------------------------------------------------------------------------
SUPPLIERS = [
    ("Navoiy Oziq-Ovqat", "+998661234567", "Navoiy sh., Bozor ko'chasi 12", "Un, shakar, yog'"),
    ("Baraka Sut", "+998662345678", "Karmana tumani", "Sut, qaymoq, tvorog — har kuni ertalab"),
    ("Kofe Import MChJ", "+998712345678", "Toshkent sh., Chilonzor", "Kofe doni, matcha"),
    ("Dehqon bozori", "+998663456789", "Navoiy markaziy bozori", "Limon, meva"),
]


def seed_suppliers():
    step("Ta'minotchilar")
    have = {s["name"]: s["id"] for s in api("GET", "/api/suppliers")}
    ids = {}
    for name, phone, address, notes in SUPPLIERS:
        if name in have:
            ids[name] = have[name]
            ok(f"{name} — mavjud")
            continue
        resp = api(
            "POST",
            "/api/suppliers",
            {"name": name, "phone": phone, "address": address, "notes": notes},
        )
        ids[name] = resp["id"]
        ok(f"{name} — #{resp['id']}")
    return ids


# --------------------------------------------------------------------------
# 10. Bozor xaridi → FIFO partiyalar + avto-xarajat
# --------------------------------------------------------------------------
def seed_purchases(ing, sup):
    step("Bozor xaridi (partiya + avtomatik xarajat)")
    if scalar("SELECT COUNT(*) FROM purchases") != "0":
        ok("xaridlar allaqachon kiritilgan — o'tkazib yuborildi")
        return
    purchases = [
        (
            "Navoiy Oziq-Ovqat",
            "Haftalik un-shakar xaridi",
            [
                ("Un", 50_000, 750_000, "UN-2608-A"),
                ("Shakar", 30_000, 480_000, "SH-2608-A"),
                ("Sariyog'", 10_000, 1_100_000, "SY-2608-A"),
                ("Vanilin", 500, 90_000, "VN-2608"),
            ],
        ),
        (
            "Baraka Sut",
            "Ertalabki sut mahsulotlari",
            [
                ("Sut", 40_000, 560_000, "ST-2608-A"),
                ("Qaymoq 33%", 12_000, 720_000, "QM-2608-A"),
                ("Krem-pishloq", 15_000, 1_350_000, "KP-2608-A"),
                ("Labne (tvorog)", 8_000, 400_000, "LB-2608"),
                ("Tuxum", 300, 450_000, "TX-2608"),
            ],
        ),
        (
            "Kofe Import MChJ",
            "Kofe va matcha zaxirasi",
            [
                ("Kofe doni", 12_000, 1_680_000, "KF-2608-A"),
                ("Matcha kukuni", 2_000, 900_000, "MT-2608"),
                ("Qora choy", 5_000, 350_000, "CH-2608"),
                ("Qora shokolad", 6_000, 780_000, "SHK-2608"),
                ("Oq shokolad", 4_000, 560_000, "OSH-2608"),
                ("Kakao", 3_000, 330_000, "KK-2608"),
                ("Oreo pechenye", 4_000, 480_000, "OR-2608"),
                ("Pista", 3_000, 1_050_000, "PS-2608"),
                ("Kunjut", 2_000, 160_000, "KN-2608"),
            ],
        ),
        (
            "Dehqon bozori",
            "Limon va yangi mahsulot",
            [("Limon", 120, 240_000, "LM-2608")],
        ),
        (
            "Navoiy Oziq-Ovqat",
            "Ikkinchi un partiyasi (narx oshgan — FIFO namunasi)",
            [("Un", 25_000, 450_000, "UN-2608-B")],
        ),
    ]
    for supplier, note, items in purchases:
        body = {
            "note": note,
            "supplier_id": sup[supplier],
            "items": [
                {
                    "ingredient_id": ing[name],
                    "qty": qty,
                    "subtotal": subtotal,
                    "batch_code": code,
                }
                for name, qty, subtotal, code in items
            ],
        }
        resp = api("POST", "/api/purchase", body)
        total = sum(i[2] for i in items)
        ok(f"{supplier}: {len(items)} ta pozitsiya, {money(total)} so'm "
           f"(xarid #{resp.get('id', '?')})")

    # Xaridlar API orqali doim "hozir" yoziladi. Demo real ko'rinishi uchun
    # ularni oxirgi 5 kunga taqsimlaymiz (xarajat sanasi va partiya kirimi ham).
    sql_file("""
BEGIN;
UPDATE purchases SET created_at = created_at - ((6 - id) || ' days')::interval
 WHERE id BETWEEN 1 AND 5;
UPDATE expenses e SET date = (p.created_at::date)::text, created_at = p.created_at
  FROM purchases p WHERE p.expense_id = e.id;
UPDATE ingredient_batches b SET received_at = p.created_at, created_at = p.created_at
  FROM purchase_items pi JOIN purchases p ON p.id = pi.purchase_id
 WHERE b.purchase_item_id = pi.id;
COMMIT;
""")
    ok("xaridlar va kirim partiyalari oxirgi 5 kunga taqsimlandi (FIFO tartibi saqlandi)")


# --------------------------------------------------------------------------
# 11. Retseptlar (mahsulot turi → "cooked")
# --------------------------------------------------------------------------
RECIPES = [
    # product_id, nom, batch_qty, [(ingredient, butun partiya uchun miqdor)]
    (157, "Наполеон", 8, [("Un", 1200), ("Shakar", 600), ("Sut", 1500),
                          ("Tuxum", 6), ("Sariyog'", 800), ("Vanilin", 10)]),
    (165, "Brownıe", 10, [("Un", 500), ("Shakar", 700), ("Tuxum", 5),
                          ("Sariyog'", 400), ("Qora shokolad", 600), ("Kakao", 100)]),
    (169, "Oreo Chizkeyk", 12, [("Krem-pishloq", 1800), ("Shakar", 500),
                                ("Tuxum", 4), ("Qaymoq 33%", 600),
                                ("Oreo pechenye", 700), ("Sariyog'", 200)]),
    (186, "Сан Себастян", 10, [("Krem-pishloq", 2000), ("Shakar", 500),
                               ("Tuxum", 6), ("Qaymoq 33%", 700), ("Un", 100)]),
    (205, "Vatrushkı", 20, [("Un", 1500), ("Shakar", 300), ("Sut", 500),
                            ("Tuxum", 3), ("Labne (tvorog)", 1200), ("Sariyog'", 250)]),
    (201, "Sımıt", 30, [("Un", 2500), ("Shakar", 150), ("Sut", 400),
                        ("Kunjut", 400), ("Sariyog'", 150)]),
    (199, "Labnelı pogaca", 24, [("Un", 2000), ("Sut", 600), ("Tuxum", 2),
                                 ("Sariyog'", 300), ("Labne (tvorog)", 900)]),
    (206, "Kartoshka", 20, [("Un", 800), ("Kakao", 150), ("Sut", 400),
                            ("Sariyog'", 500), ("Shakar", 400)]),
    (195, "Pistachio Bloom", 10, [("Krem-pishloq", 1500), ("Pista", 800),
                                  ("Shakar", 400), ("Qaymoq 33%", 500), ("Tuxum", 4)]),
]


def seed_recipes(ing):
    step("Retseptlar (pishiriladigan mahsulotlar)")
    for pid, name, batch, items in RECIPES:
        api("PUT", f"/api/product/{pid}", {"product_type": "cooked"})
        api(
            "PUT",
            "/api/recipe",
            {
                "product_id": pid,
                "batch_qty": batch,
                "items": [
                    {"ingredient_id": ing[n], "amount": amount} for n, amount in items
                ],
            },
        )
        cost = api("GET", f"/api/recipe/cost?product_id={pid}")
        unit_cost = cost.get("piece_cost", 0)
        ok(f"#{pid} {name}: {batch} dona/partiya, {len(items)} ingredient, "
           f"tannarx ≈ {money(unit_cost)} so'm/dona")


# --------------------------------------------------------------------------
# 12. Qoldiqlar va pishirish limitlari
# --------------------------------------------------------------------------
ZERO_STOCK = [96, 208, 212, 213]          # ataylab 0 — "tugagan" holat namunasi
LOW_STOCK = {155: 2, 157: 1, 207: 3}      # limitdan past — "pishirish kerak"
COOK_LIMITS = {157: 6, 165: 8, 169: 8, 186: 6, 205: 15, 201: 20, 199: 15,
               206: 12, 195: 6}


def seed_stocks():
    step("Mahsulot qoldiqlari va pishirish limitlari")
    menu = json.load(open(SNAPSHOT))
    ready = 0
    for p in menu["products"]:
        pid = p["id"]
        if pid in ZERO_STOCK:
            count = 0
        elif pid in LOW_STOCK:
            count = LOW_STOCK[pid]
        elif pid in COOK_LIMITS:
            count = random.randint(8, 20)
        elif p["category_id"] in (16,):          # desertlar
            count = random.randint(4, 14)
        elif p["category_id"] in (18, 19):       # issiq taom, tost
            count = random.randint(10, 25)
        else:                                    # ichimlik va boshqa
            count = random.randint(25, 80)
        api("POST", "/api/stock/set", {"product_id": pid, "count": count})
        ready += 1
    ok(f"{ready} ta mahsulotga qoldiq kiritildi "
       f"({len(ZERO_STOCK)} tasi ataylab 0 — 'tugagan' holati)")
    for pid, limit in COOK_LIMITS.items():
        api("POST", "/api/stock/limit", {"product_id": pid, "limit_qty": limit})
    ok(f"{len(COOK_LIMITS)} ta mahsulotga pishirish limiti qo'yildi")


# --------------------------------------------------------------------------
# 13. Pishirish
# --------------------------------------------------------------------------
def seed_cooking():
    step("Pishirish (ombordan ingredient FIFO chiqimi)")
    if scalar("SELECT COUNT(*) FROM cookings") != "0":
        ok("pishirishlar allaqachon bor — o'tkazib yuborildi")
        return
    done = api("POST", "/api/cooking/start", {"product_id": 157, "qty": 8})
    api("POST", f"/api/cooking/{done['id']}/done", {})
    ok(f"#157 Наполеон — 8 dona pishirildi va bazaga qo'shildi (pishirish #{done['id']})")

    done2 = api("POST", "/api/cooking/start", {"product_id": 205, "qty": 20})
    api("POST", f"/api/cooking/{done2['id']}/done", {})
    ok(f"#205 Vatrushkı — 20 dona tayyor (pishirish #{done2['id']})")

    active = api("POST", "/api/cooking/start", {"product_id": 165, "qty": 10})
    ok(f"#165 Brownıe — 10 dona HOZIR pishmoqda (pishirish #{active['id']}, status=cooking)")

    cancelled = api("POST", "/api/cooking/start", {"product_id": 201, "qty": 30})
    api("POST", f"/api/cooking/{cancelled['id']}/cancel", {})
    ok(f"#201 Sımıt — bekor qilindi, ingredient omborga QAYTARILDI "
       f"(pishirish #{cancelled['id']})")


# --------------------------------------------------------------------------
# 14. CRM: mijozlar, ballar, promo-kodlar
# --------------------------------------------------------------------------
CUSTOMERS = [
    ("Aziza Karimova", "+998901112200", "1995-04-12", "female", ["doimiy"], "Har shanba keladi"),
    ("Bekzod Tursunov", "+998901112201", "1988-11-03", "male", [], ""),
    ("Gulnora Saidova", "+998901112202", "1990-08-20", "female", ["doimiy", "desert"], "Chizkeyk yoqtiradi"),
    ("Jasur Ergashev", "+998901112203", "", "male", ["dostafka"], "Dostafka mijozi"),
    ("Kamola Nazarova", "+998901112204", "1997-02-14", "female", ["VIP"], "Tug'ilgan kunda chegirma"),
    ("Otabek Rahmonov", "+998901112205", "", "male", [], ""),
    ("Sevara Yo'ldosheva", "+998901112206", "1993-06-30", "female", ["doimiy"], ""),
    ("Umid Xolmatov", "+998901112207", "", "male", ["saboy"], "Doim saboy oladi"),
]

PROMOS = [
    {"code": "KONAK10", "discount_type": "percent", "value": 10,
     "min_order_total": 50_000, "max_discount": 20_000, "status": "active"},
    {"code": "SOVGA5", "discount_type": "fixed", "value": 5_000,
     "min_order_total": 30_000, "status": "active"},
    {"code": "BIRMARTA", "discount_type": "percent", "value": 20,
     "min_order_total": 0, "max_discount": 30_000, "usage_limit": 1, "status": "active"},
    {"code": "ESKI2025", "discount_type": "percent", "value": 15,
     "min_order_total": 0, "status": "active",
     "starts_at": "2025-01-01T00:00:00Z", "ends_at": "2025-12-31T23:59:59Z"},
]


def seed_crm():
    step("CRM — mijozlar, sodiqlik ballari, promo-kodlar")
    have = {c["phone"]: c["id"] for c in items_of(api("GET", "/api/customers?limit=200"), "items")}
    ids = {}
    for name, phone, bday, gender, tags, notes in CUSTOMERS:
        key = phone.lstrip("+")
        if key in have:
            ids[phone] = have[key]
            ok(f"{name} — mavjud")
            continue
        body = {"name": name, "phone": phone, "gender": gender, "tags": tags,
                "notes": notes}
        if bday:
            body["birthday"] = bday
        resp = api("POST", "/api/customers", body)
        ids[phone] = resp["id"]
        ok(f"{name} — {phone} (#{resp['id']})")

    # qo'lda berilgan bonus ballar
    for phone, points, note in (
        ("+998901112204", 150, "VIP mijozga sovg'a ball"),
        ("+998901112200", 40, "Tug'ilgan kun bonusi"),
    ):
        api("POST", f"/api/customers/{ids[phone]}/loyalty",
            {"type": "earn", "points": points, "note": note})
        ok(f"{phone} → +{points} ball ({note})")
    api("POST", f"/api/customers/{ids['+998901112204']}/loyalty",
        {"type": "redeem", "points": 50, "note": "Chek uchun ishlatildi"})
    ok("+998901112204 → -50 ball (yechib olindi)")

    have_promo = {p["code"] for p in api("GET", "/api/promos")}
    for promo in PROMOS:
        if promo["code"] in have_promo:
            ok(f"{promo['code']} — mavjud")
            continue
        api("POST", "/api/promos", promo)
        kind = "%" if promo["discount_type"] == "percent" else "so'm"
        ok(f"{promo['code']} — {promo['value']}{kind} chegirma")
    return ids


# --------------------------------------------------------------------------
# 15. Tarixiy buyurtmalar (analitika uchun) — SQL
# --------------------------------------------------------------------------
HIST_DAYS = 14


def seed_history():
    step(f"Buyurtma tarixi — oxirgi {HIST_DAYS} kun (analitika uchun)")
    if int(scalar("SELECT COUNT(*) FROM orders WHERE created_at < CURRENT_DATE")) > 5:
        ok("tarix allaqachon yozilgan — o'tkazib yuborildi")
        return
    menu = json.load(open(SNAPSHOT))
    products = {p["id"]: p for p in menu["products"]}
    sellable = [p for p in menu["products"] if p["price"] <= 100_000]
    phones = [c[1].lstrip("+") for c in CUSTOMERS]
    users = json.loads(scalar(
        "SELECT COALESCE(json_agg(json_build_object('id',id,'name',name))::text,'[]') "
        "FROM users WHERE role IN ('cashier','waiter','admin','super_admin')"
    ))

    lines = ["BEGIN;"]
    total_orders = 0
    for day_offset in range(HIST_DAYS, 0, -1):
        day = date.today() - timedelta(days=day_offset)
        weekend = day.weekday() >= 5
        count = random.randint(12, 20) if weekend else random.randint(7, 14)
        for seq in range(1, count + 1):
            hour = random.choices(
                [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
                weights=[3, 4, 5, 8, 10, 8, 6, 6, 7, 9, 10, 8, 4],
            )[0]
            created = datetime(day.year, day.month, day.day, hour,
                               random.randint(0, 59), random.randint(0, 59))
            otype = random.choices(
                ["dine_in", "takeaway", "delivery"], weights=[62, 24, 14]
            )[0]
            source = "online" if (otype != "dine_in" and random.random() < 0.35) else "pos"
            if otype == "dine_in" and random.random() < 0.12:
                source = "qr"
            prefix = {"online": "O", "qr": "Q"}.get(source, "P")
            number = f"{day.strftime('%y-%m-%d')}-{prefix}{seq:06d}"

            items, subtotal = [], 0
            for idx in range(random.randint(1, 4)):
                p = random.choice(sellable)
                qty = random.randint(1, 3)
                line = p["price"] * qty
                subtotal += line
                snapshot = {
                    "name": p["name"],
                    "price": p["price"],
                    "category_id": p["category_id"],
                    "media": [],
                }
                user = random.choice(users) if users else {"id": 1, "name": "Samandar"}
                items.append({
                    "id": idx + 1,
                    "product_id": p["id"],
                    "snapshot": snapshot,
                    "quantity": qty,
                    "price": p["price"],
                    "total": line,
                    "note": None,
                    "added_by": {"type": source, "name": user["name"],
                                 "user_id": user["id"]},
                    "added_at": created.isoformat() + "Z",
                })
            service_fee = subtotal * 10 // 100 if otype == "dine_in" else 0
            delivery_fee = 0
            discount = 0
            promo = "NULL"
            if random.random() < 0.12:
                discount = min(20_000, subtotal * 10 // 100)
                promo = q("KONAK10")
            total = subtotal + service_fee + delivery_fee - discount

            cancelled = random.random() < 0.06
            if cancelled:
                status, pay_status, method, payments = "cancelled", "unpaid", "NULL", "NULL"
                total = 0
            else:
                status, pay_status = "completed", "paid"
                pick = random.choices(
                    ["cash", "card", "click", "payme", "split"],
                    weights=[42, 24, 16, 12, 6],
                )[0]
                if pick == "split":
                    half = total // 2
                    method = q("split")
                    payments = q(json.dumps(
                        [{"method": "cash", "amount": half},
                         {"method": "click", "amount": total - half}]
                    )) + "::jsonb"
                else:
                    method, payments = q(pick), "NULL"

            phone = "NULL"
            cname = "NULL"
            if random.random() < 0.38:
                idx = random.randrange(len(phones))
                phone = q(phones[idx])
                cname = q(CUSTOMERS[idx][0])

            table_sku, table_id, zone_id = "NULL", "NULL", "NULL"
            if otype == "dine_in":
                zone, num = (1, random.randint(1, 12)) if random.random() < 0.7 else (2, random.randint(1, 7))
                table_sku = q(f"Z{zone}-{num}")
                zone_id = str(zone)
            creator = random.choice(users) if users else {"id": 1}
            lines.append(
                "INSERT INTO orders (order_number,type,table_sku,table_id,zone_id,"
                "items,subtotal,service_fee,delivery_fee,discount,total,"
                "payment_method,payments,payment_status,status,source,created_by,"
                "customer_name,customer_phone,promo_code,created_at,updated_at) VALUES ("
                f"{q(number)},{q(otype)},{table_sku},{table_id},{zone_id},"
                f"{q(json.dumps(items, ensure_ascii=False))}::jsonb,{subtotal},"
                f"{service_fee},{delivery_fee},{discount},{total},{method},{payments},"
                f"{q(pay_status)},{q(status)},{q(source)},{creator['id']},{cname},{phone},"
                f"{promo},{q(created.isoformat())},{q(created.isoformat())}"
                ") ON CONFLICT (order_number) DO NOTHING;"
            )
            total_orders += 1
        lines.append(
            "INSERT INTO order_daily_counters (business_date,last_value) VALUES "
            f"({q(day.isoformat())},{count}) ON CONFLICT (business_date) DO NOTHING;"
        )

    # tarixiy xarajatlar
    for day_offset in range(HIST_DAYS, 0, -1):
        day = date.today() - timedelta(days=day_offset)
        for cat_name, amount, desc in (
            ("Bozor", random.randint(150_000, 350_000), "Kunlik bozorlik"),
            ("Kommunal", random.randint(40_000, 90_000), "Elektr"),
        ):
            lines.append(
                "INSERT INTO expenses (category_id,amount,description,date,created_by) "
                f"SELECT id,{amount},{q(desc)},{q(day.isoformat())},"
                "'{\"user_id\":1,\"name\":\"Samandar\",\"role\":\"super_admin\"}'::jsonb "
                f"FROM expense_categories WHERE name_uz={q(cat_name)} LIMIT 1;"
            )

    # oylik yirik xarajatlar (ijara, oylik) — 12 kun oldin to'langan
    big_day = (date.today() - timedelta(days=12)).isoformat()
    for cat_name, amount, desc in (
        ("Ijara", 3_000_000, "Avgust oyi ijara to'lovi"),
        ("Oylik", 2_400_000, "Xodimlar oyligi"),
        ("Kommunal", 850_000, "Elektr + suv (oylik)"),
    ):
        lines.append(
            "INSERT INTO expenses (category_id,amount,description,date,created_by) "
            f"SELECT id,{amount},{q(desc)},{q(big_day)},"
            "'{\"user_id\":1,\"name\":\"Samandar\",\"role\":\"super_admin\"}'::jsonb "
            f"FROM expense_categories WHERE name_uz={q(cat_name)} LIMIT 1;"
        )

    # mijoz statistikasi tarixdan hisoblansin
    lines += [
        "UPDATE orders o SET customer_id=c.id FROM customers c "
        "WHERE o.customer_phone=c.phone AND o.customer_id IS NULL;",
        """UPDATE customers c SET
             total_spent=s.spent, visit_count=s.visits, last_visit_at=s.last_visit,
             loyalty_points=c.loyalty_points+s.spent/10000, updated_at=NOW()
           FROM (SELECT customer_id, SUM(total) spent, COUNT(*) visits,
                        MAX(created_at) last_visit
                 FROM orders WHERE customer_id IS NOT NULL AND status='completed'
                 GROUP BY customer_id) s
           WHERE c.id=s.customer_id;""",
        """INSERT INTO loyalty_transactions
             (customer_id,order_number,type,points,balance_after,note,created_by)
           SELECT customer_id,order_number,'earn',total/10000,total/10000,
                  'Avtomatik cashback','system'
           FROM orders WHERE customer_id IS NOT NULL AND status='completed'
             AND total>=10000
           ON CONFLICT DO NOTHING;""",
        "UPDATE orders SET loyalty_points_earned=total/10000 "
        "WHERE customer_id IS NOT NULL AND status='completed';",
        "COMMIT;",
    ]
    sql_file("\n".join(lines))
    ok(f"{total_orders} ta tarixiy buyurtma + {HIST_DAYS*2} ta xarajat yozildi")
    ok("mijoz tashrif/ball statistikasi tarixdan qayta hisoblandi")


# --------------------------------------------------------------------------
# 16. Bugungi smena va jonli buyurtmalar
# --------------------------------------------------------------------------
def seed_today():
    step("Bugungi smena va jonli buyurtmalar")
    shift = api("GET", "/api/shift/current")
    if not (isinstance(shift, dict) and shift.get("status") == "open"):
        api("POST", "/api/shift/open", {"opening_cash": 500_000})
        ok("smena ochildi (kassada 500 000 so'm)")
    else:
        ok("smena allaqachon ochiq")

    if int(scalar(
        "SELECT COUNT(*) FROM orders WHERE created_at::date=CURRENT_DATE"
    )) >= 8:
        ok("bugungi buyurtmalar allaqachon yaratilgan — o'tkazib yuborildi")
        return

    # yopilgan cheklar
    closed = [
        ("Z1-3", [(102, 2), (169, 1)], "cash", 0),
        ("Z1-5", [(109, 1), (155, 1), (216, 2)], "card", 5_000),
        ("Z2-2", [(120, 2), (165, 2)], "click", 0),
    ]
    for sku, items, method, discount in closed:
        api("POST", "/api/order/create", {
            "type": "dine_in", "table_sku": sku,
            "items": [{"product_id": p, "quantity": qty} for p, qty in items],
        })
        api("POST", "/api/order/close", {
            "table_sku": sku, "payment_method": method, "discount": discount,
        })
        ok(f"{sku} — {len(items)} pozitsiya, {method} bilan yopildi"
           + (f", chegirma {money(discount)}" if discount else ""))

    # aralash to'lov (split)
    api("POST", "/api/order/create", {
        "type": "dine_in", "table_sku": "Z1-8",
        "items": [{"product_id": 207, "quantity": 1}, {"product_id": 105, "quantity": 2}],
    })
    total = int(scalar(
        "SELECT total FROM orders WHERE table_sku='Z1-8' "
        "AND status NOT IN ('completed','cancelled') LIMIT 1"
    ))
    half = total // 2
    api("POST", "/api/order/close", {
        "table_sku": "Z1-8", "payments": [
            {"method": "cash", "amount": half},
            {"method": "card", "amount": total - half},
        ],
    })
    ok(f"Z1-8 — ARALASH to'lov: naqd {money(half)} + karta {money(total - half)}")

    # ochiq (band) stollar — demo paytida ko'rsatish uchun
    for sku, items, note in (
        ("Z1-1", [(102, 2), (205, 3)], "Deraza yonidagi stol"),
        ("Z1-7", [(215, 1), (145, 2), (224, 1)], None),
        ("Z2-4", [(114, 2), (196, 1)], "Mehmonlar kutmoqda"),
    ):
        body = {"type": "dine_in", "table_sku": sku,
                "items": [{"product_id": p, "quantity": q_} for p, q_ in items]}
        if note:
            body["note"] = note
        resp = api("POST", "/api/order/create", body)
        ok(f"{sku} — OCHIQ chek {resp['order_number']}, {money(resp['total'])} so'm")

    # saboy va dostafka
    resp = api("POST", "/api/order/create", {
        "type": "takeaway",
        "items": [{"product_id": 104, "quantity": 2}, {"product_id": 201, "quantity": 4}],
        "note": "Saboy — 15 daqiqada olib ketiladi",
    })
    ok(f"SABOY chek {resp['order_number']} — {money(resp['total'])} so'm")

    # bekor qilingan chek
    resp = api("POST", "/api/order/create", {
        "type": "takeaway",
        "items": [{"product_id": 112, "quantity": 1}],
    })
    api("POST", "/api/order/cancel", {"order_number": resp["order_number"]})
    ok(f"{resp['order_number']} — BEKOR qilindi (namuna)")


# --------------------------------------------------------------------------
# 17. Spisaniya, inventarizatsiya, ombor korreksiyasi
# --------------------------------------------------------------------------
def seed_writeoffs():
    step("Spisaniya, inventarizatsiya va ombor korreksiyasi")
    if scalar("SELECT COUNT(*) FROM write_offs") == "0":
        for pid, qty, reason, note in (
            (155, 1, "Muddati o'tgan", "Kechagi desert qolib ketdi"),
            (216, 3, "Sifatsiz", "Non quruq bo'lib qolgan"),
            (145, 2, "Sindi/to'kildi", "Shisha tushib ketdi"),
        ):
            api("POST", "/api/write-offs", {"product_id": pid, "qty": qty,
                                            "reason": reason, "note": note})
            ok(f"#{pid} — {qty} dona spisaniya ({reason})")

    if scalar("SELECT COUNT(*) FROM inventory_corrections") == "0":
        api("POST", "/api/inventory", {"items": [
            {"product_id": 146, "actual_count": 18},
            {"product_id": 149, "actual_count": 22},
            {"product_id": 217, "actual_count": 5},
        ]})
        ok("3 ta mahsulot bo'yicha inventarizatsiya kiritildi")

    ing = {i["name"]: i["id"] for i in items_of(api("GET", "/api/ingredients"), "ingredients")}
    api("POST", "/api/ingredient/adjust", {
        "ingredient_id": ing["Limon"], "new_count": 95,
        "comment": "Inventarizatsiya: bir qismi buzilgan",
    })
    ok("Limon qoldig'i 95 donaga korreksiya qilindi")


# --------------------------------------------------------------------------
# 18. QR mijoz sessiyasi + QR buyurtma
# --------------------------------------------------------------------------
def seed_qr():
    step("QR mijoz — sessiya va buyurtma")
    code = scalar("SELECT qr_code FROM tables WHERE sku='Z1-10'")
    if not code:
        warn("Z1-10 stoli topilmadi")
        return None
    if int(scalar(
        "SELECT COUNT(*) FROM orders WHERE source='qr' "
        "AND created_at::date=CURRENT_DATE"
    )) > 0:
        ok(f"QR buyurtma allaqachon bor. Z1-10 QR kodi: {code}")
        return code
    session = api("POST", "/api/qr/session", {"code": code}, token=None)
    token = session.get("session_token") or session.get("token")
    resp = api("POST", "/api/qr/order", {
        "session_token": token,
        "customer_name": "QR mehmon",
        "customer_phone": "+998901112206",
        "items": [{"product_id": 121, "quantity": 2}, {"product_id": 205, "quantity": 2}],
        "note": "QR orqali buyurtma — demo",
    }, token=None, expect=(200, 201))
    ok(f"Z1-10 QR kodi: {code}")
    ok(f"QR buyurtma yaratildi: {resp.get('order_number')}")
    api("POST", "/api/qr/call-waiter", {"session_token": token}, token=None,
        expect=(200, 201, 400, 429))
    ok("«Ofitsiantni chaqirish» signali yuborildi")
    return code


# --------------------------------------------------------------------------
# 19. Online (saboy/dostafka) buyurtma — Telegram tasdig'i simulyatsiyasi
# --------------------------------------------------------------------------
def seed_online():
    step("Online buyurtma (Telegram tasdig'i simulyatsiya qilinadi)")
    token = "demo-verification-token-0001"
    sql(
        "INSERT INTO online_verifications (code,pending_token,verification_token,"
        "status,tg_user_id,tg_username,phone,location_lat,location_lng,expires_at) "
        f"VALUES ('123456','demo-pending-0001',{q(token)},'confirmed',555000111,"
        "'demo_user','998901112203',40.104100,65.373700,NOW()+INTERVAL '30 days') "
        "ON CONFLICT (pending_token) DO NOTHING"
    )
    used = scalar(f"SELECT status FROM online_verifications WHERE verification_token={q(token)}")
    if used != "confirmed":
        ok(f"tasdiq tokeni allaqachon ishlatilgan (status={used})")
        return token
    resp = api("POST", "/api/online/order", {
        "type": "delivery",
        "items": [{"product_id": 157, "quantity": 1}, {"product_id": 102, "quantity": 2}],
        "customer": {"phone": "998901112203", "tg_user_id": 555000111,
                     "tg_username": "demo_user", "verification_token": token},
        "location": {"lat": 40.1041, "lng": 65.3737, "address": "Navoiy sh., Islom Karimov 5"},
        "note": "Dostafka — 2-qavat",
    }, token=None)
    ok(f"DOSTAFKA buyurtma: {resp['order_number']} — {money(resp['total'])} so'm")
    # test uchun yana bitta tayyor token qoldiramiz
    sql(
        "INSERT INTO online_verifications (code,pending_token,verification_token,"
        "status,tg_user_id,tg_username,phone,expires_at) VALUES "
        "('654321','demo-pending-0002','demo-verification-token-0002','confirmed',"
        "555000222,'demo_user2','998901112207',NOW()+INTERVAL '30 days') "
        "ON CONFLICT (pending_token) DO NOTHING"
    )
    ok("test uchun ikkinchi tasdiq tokeni tayyor: demo-verification-token-0002")
    return token


# --------------------------------------------------------------------------
# 20. Backup
# --------------------------------------------------------------------------
def seed_backup():
    step("Shifrlangan backup")
    resp = api("POST", "/api/backups", {}, expect=(200, 201, 500))
    if isinstance(resp, dict) and resp.get("filename"):
        ok(f"backup yaratildi: {resp['filename']}")
    else:
        backups = api("GET", "/api/backups")
        items = items_of(backups, "items")
        if items:
            ok(f"mavjud backuplar: {len(items)} ta")
        else:
            warn(f"backup javobi: {str(resp)[:120]}")


# --------------------------------------------------------------------------
# Xulosa
# --------------------------------------------------------------------------
def summary(qr_code):
    step("XULOSA")
    rows = [
        ("Kategoriya", "SELECT COUNT(*) FROM categories WHERE status='active'"),
        ("Mahsulot", "SELECT COUNT(*) FROM products WHERE status='active'"),
        ("Zona", "SELECT COUNT(*) FROM zones WHERE status='active'"),
        ("Stol", "SELECT COUNT(*) FROM tables"),
        ("Band stol", "SELECT COUNT(*) FROM tables WHERE status='occupied'"),
        ("Xodim", "SELECT COUNT(*) FROM users WHERE status='active'"),
        ("Ingredient", "SELECT COUNT(*) FROM ingredients WHERE status='active'"),
        ("Ta'minotchi", "SELECT COUNT(*) FROM suppliers WHERE status='active'"),
        ("Kirim partiyasi", "SELECT COUNT(*) FROM ingredient_batches"),
        ("Retsept", "SELECT COUNT(*) FROM recipes"),
        ("Pishirish", "SELECT COUNT(*) FROM cookings"),
        ("Mijoz", "SELECT COUNT(*) FROM customers WHERE status='active'"),
        ("Promo-kod", "SELECT COUNT(*) FROM promo_codes WHERE status='active'"),
        ("Buyurtma (jami)", "SELECT COUNT(*) FROM orders"),
        ("Buyurtma (bugun)", "SELECT COUNT(*) FROM orders WHERE created_at::date=CURRENT_DATE"),
        ("Ochiq chek", "SELECT COUNT(*) FROM orders WHERE status NOT IN ('completed','cancelled')"),
        ("Xarajat", "SELECT COUNT(*) FROM expenses"),
        ("Spisaniya", "SELECT COUNT(*) FROM write_offs"),
        ("Audit yozuvi", "SELECT COUNT(*) FROM audit_logs"),
    ]
    for label, query in rows:
        print(f"   {label:<20} {scalar(query):>6}")
    if qr_code:
        print(f"\n   QR demo havolasi: {BASE}/customer/?code={qr_code}")
    print(f"\n   Backend:  {BASE}")
    print(f"   Baza:     {PGURL}")


def main():
    print("KONAK POS — demo ma'lumotlarni to'ldirish")
    print(f"Backend: {BASE}")
    login()
    cleanup()
    printers = seed_printers()
    seed_menu(printers)
    seed_zones()
    seed_users()
    cats = seed_expense_categories()
    ing = seed_ingredients()
    sup = seed_suppliers()
    seed_purchases(ing, sup)
    seed_recipes(ing)
    seed_stocks()
    seed_cooking()
    seed_crm()
    seed_history()
    seed_today()
    seed_expenses(cats)
    seed_writeoffs()
    qr_code = seed_qr()
    seed_online()
    seed_backup()
    summary(qr_code)
    print("\nTayyor. Endi ilovadan yoki scripts/api_test.py orqali tekshirish mumkin.\n")


if __name__ == "__main__":
    main()
