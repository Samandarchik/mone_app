#!/usr/bin/env python3
"""
Yo'qolgan retseptlarni AUDIT JURNALIDAN tiklaydi.

NEGA ISHLAYDI: retsept saqlash `PUT /api/recipe` orqali ketadi va serverdagi
audit qatlami har bir bunday so'rovning TO'LIQ tanasini
(`product_id`, `batch_qty`, `items`) `audit_logs` jadvaliga yozib qo'yadi.
Ya'ni retsept bazadan yo'qolgan bo'lsa ham, uning asl mazmuni jurnalda turadi.

FAQAT MAVJUD (allaqachon deploy qilingan) endpointlardan foydalanadi:
    POST /api/auth/login
    GET  /api/audit?entity_type=recipe
    GET  /api/recipe?product_id=
    PUT  /api/recipe
Shuning uchun serverni yangilamasdan ham ishlatish mumkin.

ISHLATISH
    # 1) Avval FAQAT hisobot — hech narsa yozilmaydi
    ./recover_recipes.py --url https://konak.uzaidev.uz --phone +998901234567 --pin 1234

    # 2) Tiklash (faqat YO'Q retseptlar; mavjudlari tegilmaydi)
    ./recover_recipes.py --url https://konak.uzaidev.uz --phone +998901234567 --pin 1234 --apply

    # Farq qilayotganlarini ham jurnaldagi oxirgi holatga qaytarish
    ./recover_recipes.py ... --apply --overwrite

    # Token bilan (parol kiritmasdan)
    ./recover_recipes.py --url ... --token eyJhbGciOi...

IKKALA SERVERDA HAM ishlating (local va online) — jurnal har bir serverda
o'zinikini saqlaydi, retsept esa qaysi biriga tushgani noma'lum.
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

GREEN, RED, YELLOW, DIM, RESET = (
    "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m"
)


def api(base, method, path, token=None, body=None, query=None):
    url = base.rstrip("/") + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = resp.read()
            return resp.status, json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        payload = e.read()
        try:
            return e.code, json.loads(payload)
        except json.JSONDecodeError:
            return e.code, {"message": payload.decode(errors="replace")[:200]}
    except urllib.error.URLError as e:
        print(f"{RED}Serverga ulanib bo'lmadi: {url} ({e}){RESET}")
        sys.exit(2)


def login(base, phone, pin):
    status, body = api(base, "POST", "/api/auth/login",
                       body={"phone": phone, "pin": pin})
    if status != 200 or not body or "token" not in body:
        msg = (body or {}).get("message", "noma'lum xato")
        print(f"{RED}Kirish muvaffaqiyatsiz: {msg}{RESET}")
        sys.exit(1)
    user = body.get("user", {})
    print(f"{DIM}Kirildi: {user.get('name')} ({user.get('role')}){RESET}")
    return body["token"]


def collect_from_audit(base, token):
    """Audit jurnalidan HAR MAHSULOT uchun ENG OXIRGI retseptni yig'adi."""
    latest = {}
    seen_ids = set()
    # `/api/audit` bir so'rovda 500 tadan ko'p qaytarmaydi; `to` bilan
    # orqaga qarab sahifalab boramiz.
    cursor = None
    while True:
        query = {"entity_type": "recipe", "limit": 500}
        if cursor:
            query["to"] = cursor
        status, body = api(base, "GET", "/api/audit", token=token, query=query)
        if status == 403:
            print(f"{RED}Audit jurnalini o'qishga ruxsat yo'q "
                  f"(super_admin bilan kiring){RESET}")
            sys.exit(1)
        if status != 200 or not isinstance(body, dict):
            print(f"{RED}Audit jurnalini o'qib bo'lmadi (HTTP {status}){RESET}")
            sys.exit(1)
        items = body.get("items") or []
        fresh = [it for it in items if it.get("id") not in seen_ids]
        if not fresh:
            break
        for it in fresh:
            seen_ids.add(it.get("id"))
            if it.get("action") != "put":
                continue
            req = it.get("request_data") or {}
            if not isinstance(req, dict):
                continue
            pid = req.get("product_id")
            rec_items = req.get("items")
            if not isinstance(pid, int) or pid <= 0:
                continue
            if not isinstance(rec_items, list) or not rec_items:
                continue
            created = it.get("created_at", "")
            # Ro'yxat id bo'yicha kamayib keladi — birinchi uchragani eng yangisi.
            if pid not in latest:
                latest[pid] = {
                    "batch_qty": req.get("batch_qty") or 0,
                    "items": rec_items,
                    "at": created,
                    "by": it.get("actor_name", ""),
                }
        if len(items) < 500:
            break
        cursor = items[-1].get("created_at")
        if not cursor:
            break
    return latest


def same_recipe(current, logged):
    """Bazadagi va jurnaldagi retsept aynan bir xilmi."""
    if not current.get("exists"):
        return False
    if current.get("batch_qty") != logged["batch_qty"]:
        return False
    cur = {i.get("ingredient_id"): i.get("amount")
           for i in current.get("items") or []}
    log = {i.get("ingredient_id"): i.get("amount") for i in logged["items"]}
    return cur == log


def main():
    ap = argparse.ArgumentParser(
        description="Retseptlarni audit jurnalidan tiklash")
    ap.add_argument("--url", required=True, help="Server manzili")
    ap.add_argument("--token", help="Tayyor token (phone/pin o'rniga)")
    ap.add_argument("--phone", help="Super admin telefoni, masalan +998901234567")
    ap.add_argument("--pin", help="4 xonali PIN")
    ap.add_argument("--apply", action="store_true",
                    help="Haqiqatan yozish (busiz faqat hisobot)")
    ap.add_argument("--overwrite", action="store_true",
                    help="Farq qilayotganlarini ham jurnaldagi holatga qaytarish")
    args = ap.parse_args()

    token = args.token
    if not token:
        if not (args.phone and args.pin):
            ap.error("--token yoki --phone bilan --pin kerak")
        token = login(args.url, args.phone, args.pin)

    print(f"{DIM}Audit jurnali o'qilmoqda…{RESET}")
    latest = collect_from_audit(args.url, token)
    if not latest:
        print(f"{YELLOW}Jurnalda birorta retsept yozuvi topilmadi.{RESET}")
        print(f"{DIM}Ehtimol retseptlar BOSHQA serverga saqlangan — "
              f"ikkinchi manzil bilan ham urinib ko'ring.{RESET}")
        return

    print(f"Jurnalda {len(latest)} ta mahsulot uchun retsept topildi.\n")

    missing, different, ok = [], [], []
    for pid in sorted(latest):
        logged = latest[pid]
        status, current = api(args.url, "GET", "/api/recipe",
                              token=token, query={"product_id": pid})
        if status != 200 or not isinstance(current, dict):
            different.append((pid, logged, "o'qib bo'lmadi"))
            continue
        if same_recipe(current, logged):
            ok.append(pid)
        elif current.get("exists"):
            different.append((pid, logged, "farq qilyapti"))
        else:
            missing.append((pid, logged))

    print(f"{GREEN}Joyida:      {len(ok)} ta{RESET}")
    print(f"{RED}Bazada YO'Q: {len(missing)} ta{RESET}")
    print(f"{YELLOW}Farq qilyapti: {len(different)} ta{RESET}\n")

    for pid, logged in missing:
        print(f"  {RED}YO'Q{RESET}  mahsulot #{pid}  "
              f"partiya={logged['batch_qty']}  "
              f"masalliq={len(logged['items'])}  "
              f"{DIM}{logged['at'][:19]} · {logged['by']}{RESET}")
    for pid, logged, why in different:
        print(f"  {YELLOW}FARQ{RESET}  mahsulot #{pid}  ({why})  "
              f"{DIM}{logged['at'][:19]}{RESET}")

    targets = list(missing)
    if args.overwrite:
        targets += [(pid, logged) for pid, logged, _ in different]

    if not args.apply:
        if targets:
            print(f"\n{DIM}Bu FAQAT hisobot — hech narsa yozilmadi.{RESET}")
            print(f"Tiklash uchun: {' '.join(sys.argv)} --apply")
        return
    if not targets:
        print(f"\n{GREEN}Tiklash kerak emas.{RESET}")
        return

    print(f"\n{DIM}{len(targets)} ta retsept tiklanmoqda…{RESET}")
    restored, failed = 0, 0
    for pid, logged in targets:
        payload = {
            "product_id": pid,
            "batch_qty": logged["batch_qty"],
            "items": [
                {"ingredient_id": i.get("ingredient_id"), "amount": i.get("amount")}
                for i in logged["items"]
            ],
        }
        status, body = api(args.url, "PUT", "/api/recipe",
                           token=token, body=payload)
        if status == 200:
            print(f"  {GREEN}tiklandi{RESET}  #{pid}")
            restored += 1
        else:
            msg = (body or {}).get("message", f"HTTP {status}")
            print(f"  {RED}xato{RESET}      #{pid} — {msg}")
            failed += 1

    print(f"\n{GREEN}Tiklandi: {restored}{RESET}"
          + (f"  {RED}Xato: {failed}{RESET}" if failed else ""))


if __name__ == "__main__":
    main()
