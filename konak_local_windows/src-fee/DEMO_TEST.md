# KONAK POS — demo va test qo'llanmasi

Bu hujjat **local demo** uchun: backend noutbukda ishga tushadi, bazada
tizimning **hamma moduli** bo'yicha ko'rsatiladigan ma'lumot bor, va har bir
funksiyani qanday tekshirish kerakligi yozilgan.

> **Muhim:** demo rejimi **bulutga ham, Windows master'ga ham tegmaydi.**
> `SYNC_MODE=off` — demo buyurtmalari hech qayerga sinxronlanmaydi.
> Telegram bot ham o'chirilgan (bitta bot tokenini ikki server so'rasa,
> jonli bot ishlamay qoladi).

---

## 1. Tez ishga tushirish

```bash
cd ~/Desktop/konak_pos/pos_backend

./scripts/run_demo.sh          # backend :3000 da (build + ishga tushirish)
python3 scripts/demo_seed.py   # demo ma'lumotlarni to'ldirish
./scripts/demo_info.sh         # namoyish uchun ma'lumot varag'i
```

Tekshirish:

```bash
curl -s http://localhost:3000/api/health
```

| Manzil | Nima |
|---|---|
| `http://localhost:3000/api` | REST API (Flutter ilova shu manzilni so'raydi) |
| `ws://localhost:3000/ws` | WebSocket — real vaqt (stol, chek, qoldiq) |
| `http://localhost:3000/customer/?code=<QR>` | QR mijoz menyusi (web) |
| `./server_demo.log` | server logi (`tail -f server_demo.log`) |

**Flutter ilovada** birinchi ochilishda base URL so'raladi → `http://localhost:3000`
(`/api` **qo'shilmaydi**, ilova o'zi qo'shadi). Telefondan ulansangiz
`localhost` o'rniga noutbukning LAN IP'sini yozing (masalan `http://192.168.1.5:3000`).

---

## 2. Kirish ma'lumotlari

| Ism | Telefon | Rol | PIN | Nima ko'radi |
|---|---|---|---|---|
| Samandar | +998901234567 | `super_admin` | **1234** | hammasi: audit, backup, bulut sozlamasi, istalgan kun moliyasi |
| Dilshod Karimov | +998901112233 | `admin` | **1111** | menyu, ombor, analitika, **faqat bugungi** moliya |
| Nodira Yusupova | +998902223344 | `cashier` | **2222** | kassa, chek, smena, spisaniya, mijoz |
| Aziz Rahimov | +998903334455 | `waiter` | **3333** | zal, chek ochish/qo'shish (yopa olmaydi) |
| Sardor Qodirov | +998904445566 | `kitchen` | **4444** | faqat oshxona: pishirish |
| Malika Tosheva | +998905556677 | `waiter` + maxsus ruxsat | **5555** | ofitsiant, lekin **chek yopa oladi** (custom_permissions namunasi) |

Login ikki xil: telefon + PIN (`/api/auth/login`) yoki faqat PIN (`/api/auth/pin-login`).

---

## 3. Demo bazasida nima bor

| Modul | Ma'lumot |
|---|---|
| **Menyu** | **11 kategoriya, 132 mahsulot** — Windows master'dagi **joriy menyu**ning aynan nusxasi (ID'lar ham bir xil: kategoriya 10–20, mahsulot 94–225) |
| **Zona/stol** | ZAL — 12 stol (`Z1-1…Z1-12`), TASHQARI — 7 stol (`Z2-1…Z2-7`), har birida o'z QR kodi |
| **Xodimlar** | 6 ta — beshta rol + maxsus ruxsatli xodim |
| **Printer** | 3 stansiya: Kassa (chek), Oshxona, Bar. Kategoriyalar printerlarga biriktirilgan (ichimlik→Bar, taom/desert→Oshxona) |
| **Ombor** | 19 ingredient (gr/ml/dona), min qoldiq va chiqindi foizi bilan |
| **Ta'minotchi** | 4 ta; 5 ta bozor xaridi → **20 ta FIFO kirim partiyasi** (`UN-2608-A` eskiroq, `UN-2608-B` qimmatroq — FIFO namunasi) |
| **Retsept** | 9 ta pishiriladigan mahsulot (Наполеон, Brownie, Oreo chizkeyk, San Sebastyan, Vatrushka, Simit, Pogaça, Kartoshka, Pistachio Bloom) |
| **Pishirish** | 1 ta yakunlangan, 1 ta **hozir pishmoqda**, 1 ta bekor qilingan (ingredient qaytgan) |
| **Qoldiq** | Hamma mahsulotga qoldiq kiritilgan; 4 tasi ataylab **0** (tugagan), bir nechtasi limitdan past (**«pishirish kerak»** ro'yxatiga tushadi) |
| **CRM** | 8 mijoz (tug'ilgan kun, teg, izoh), sodiqlik ballari, ball tarixi |
| **Promo** | `KONAK10` (10%, min 50 000, maks 20 000), `SOVGA5` (5 000 so'm, min 30 000), `BIRMARTA` (20%, limit 1 marta), `ESKI2025` (**muddati o'tgan** — ishlamasligi kerak) |
| **Buyurtma** | **~186 chek**: oxirgi 14 kunlik tarix (analitika uchun) + bugungi jonli cheklar |
| **Bugun** | 4 ta yopilgan (naqd / karta+chegirma / click / **aralash to'lov**), 1 ta bekor qilingan, 6 ta **ochiq** chek: 3 stol + saboy + QR + dostafka |
| **Xarajat** | 14 kunlik kunlik xarajatlar + oylik ijara/oylik/kommunal + xaridlardan avtomatik «Bozor» xarajati |
| **Smena** | Bugun ochiq (kassada 500 000 so'm) |
| **Audit/backup** | Har bir o'zgarish audit jurnalida; shifrlangan backup mavjud |

Aniq raqamlar va QR havolalar: `./scripts/demo_info.sh`

**Namoyish uchun tayyor raqamlar (14 kun):** tushum ≈ **29 239 000 so'm**,
148 yopilgan chek, o'rtacha chek ≈ **197 560 so'm**, xarajat ≈ 24 037 733,
sof foyda ≈ **+4 453 403 so'm**. To'lov: naqd 10.2 mln, karta 8.5 mln,
click 6.2 mln, payme 4.3 mln.

---

## 4. Avtomatik test (bir buyruq bilan)

```bash
python3 scripts/api_test.py
```

**178 ta tekshiruv**, 18 bo'lim bo'yicha. Har biri `OK` yoki `XATO` bo'lib
chiqadi, oxirida umumiy natija. Hozirgi holat: **178/178 o'tadi**.

Nima tekshiriladi:

| # | Bo'lim | Misol tekshiruvlar |
|---|---|---|
| 1 | Ochiq endpointlar | `/api/health`, `/api/menu`, `/api/menu-web`, tokensiz kirish → 401 |
| 2 | Autentifikatsiya | telefon+PIN, PIN-login, noto'g'ri PIN → 401, qisqa PIN → 400 |
| 3 | Ruxsatlar (RBAC) | har rol o'z chegarasida: ofitsiant analitikani, kassir omborni, oshpaz moliyani ko'ra olmaydi |
| 4 | Menyu CRUD | kategoriya/mahsulot yaratish, narx o'zgartirish, `menu_version` oshishi, ichida mahsuloti bor kategoriya o'chmasligi |
| 5 | Zona/stol | zona yaratish (stollar avtomatik), stol sonini oshirish, QR kodlar, 500 stol → 400 |
| 6 | Xodimlar | yaratish, rol o'zgartirish, **takroriy PIN → 409**, o'chirilgan xodim kira olmasligi, PIN javobda ochiq ko'rinmasligi |
| 7 | Smena | joriy smena + statistika, ikkinchi smena ochilmasligi, band stol bilan yopilmasligi |
| 8 | Buyurtma | yaratish, stol band bo'lishi, bo'sh/manfiy/yo'q mahsulot → 400, **qoldiqdan ko'p sotilmasligi**, pozitsiya bekor qilish, yopish + chegirma, **aralash to'lov** (noto'g'ri summa → 400), bekor qilish |
| 9 | Ombor | ingredient CRUD, takroriy nom → 409, xarid → kirim + partiya + avto-xarajat, xaridni bekor qilish (kirim orqaga qaytadi), harakatlar jurnali |
| 10 | Retsept/pishirish | tannarx hisobi, «pishirish kerak» ro'yxati, pishirish → ombordan chiqim, **bekor qilinganda ingredient qaytishi**, yakunlanganini qayta yopib bo'lmasligi, retseptsiz mahsulot → 400 |
| 11 | CRM/promo | mijoz CRUD, ball qo'shish/yechish, yetarli ball yo'q → 409, promo hisobi (10% / maksimal cheklov / min summa / muddati o'tgan / yo'q kod) |
| 12 | Moliya/analitika | kunlik moliya, to'lov usullari, 14 kunlik hisobot (trend, top mahsulot, manba, gavjum soat, mijoz), **CSV eksport**, juda uzun oraliq → 400 |
| 13 | Spisaniya/inventarizatsiya | spisaniya yozuvi, bo'sh sabab → 400, inventarizatsiya, ofitsiantga yopiq → 403 |
| 14 | QR mijoz | stolni QR orqali aniqlash, sessiya, buyurtma, yaroqsiz sessiya → 401, ofitsiant chaqirish, hisob so'rash, web ilova ochilishi |
| 15 | Online | tasdiqsiz buyurtma → 401, dostafkada manzilsiz → 400, saboy buyurtma, **bir tasdiq tokeni ikki marta ishlamasligi** |
| 16 | Printer/sozlama | printer CRUD, chek printerini tanlash, bulut sozlamasi (faqat super_admin), noto'g'ri `ws://` → 400 |
| 17 | Audit/monitoring/backup | audit jurnali (kim/nima/qachon), filtr, tizim holati, backup ro'yxati, **backup shifrlanganligi**, adminga yopiqligi |
| 18 | WebSocket | `/ws` ulanish (HTTP 101), `init` xabaridan keyin server holatni yuborishi |

> Test o'z ma'lumotini yaratadi va o'chiradi (`ZZ-TEST…`), lekin bir nechta
> test cheki bazada qoladi. Namoyishdan oldin tozalash: `4-bo'lim` oxiridagi
> «Qayta tiklash» buyrug'i.

---

## 5. Qo'lda test ssenariylari

Har bir ssenariy: **nima qilinadi → nima ko'rinishi kerak.**

### 5.1. Login va rollar
1. Ilovaga `1234` bilan kiring → hamma bo'lim ochiq.
2. Chiqib, `3333` (ofitsiant) bilan kiring → **Analitika, Ombor, Xodimlar,
   Sozlama bo'limlari yo'q**; chek yopish tugmasi ishlamaydi.
3. `4444` (oshxona) bilan kiring → faqat pishirish ekrani.
4. `5555` (Malika) bilan kiring → ofitsiant, **lekin chek yopa oladi**
   (maxsus ruxsat namunasi).

### 5.2. Menyu
1. Menyu ekranini oching → **11 kategoriya, 132 mahsulot**, narxlar joyida.
2. Mahsulot narxini o'zgartiring → boshqa qurilmada menyu **darrov** yangilanadi
   (WSS `menu:outdated` + `menu_version` oshadi).
3. Kategoriyani boshqa printerga biriktiring → keyingi chek o'sha printerga ketadi.

### 5.3. Zal va stollar
1. Zal ekrani: ZAL 12 stol, TASHQARI 7 stol.
2. **Z1-1, Z1-7, Z2-4, Z1-10** — band (qizil), qolganlari bo'sh.
3. Stolga bosing → ochiq chek va uning pozitsiyalari ko'rinadi.

### 5.4. Buyurtma ochish
1. Bo'sh stolni tanlang, 2-3 mahsulot qo'shing, saqlang.
2. Stol **band** bo'ladi, boshqa qurilmada ham darrov qizaradi.
3. Chekda **10% xizmat haqi** qo'shilgan bo'ladi (faqat zal buyurtmasida).
4. Oshxona/bar printeriga chek ketadi (printer ulanmagan bo'lsa logda
   `PRINTER … connection failed` — bu **kutilgan**, dastur yiqilmaydi).

### 5.5. Qoldiq nazorati
1. Menyudan **Turk chay Samavar kichik (#96)** ni sotmoqchi bo'ling → qoldiq 0,
   **«faqat 0 ta qolgan»** xatosi.
2. `Ombor → qoldiq qo'shish` orqali 5 ta kiriting → mahsulot sotuvga chiqadi.
3. QR mijoz menyusida (`/customer/`) qoldig'i 0 mahsulotlar **ko'rinmaydi**
   (POS menyusida esa ko'rinadi — bu ataylab shunday).

### 5.6. Chekni yopish va to'lov
1. Ochiq chekli stolni yoping → naqd / karta / click / payme tanlang.
2. **Aralash to'lov**: bitta chekni ikki usulga bo'ling (masalan naqd 50 000 +
   karta qolgani). Summalar jamiga teng bo'lmasa — **xato beradi**.
3. Chegirma kiriting → jami kamayadi, smena statistikasi darrov yangilanadi.
4. Yopilgach stol **bo'shaydi**, QR sessiyasi yopiladi.

### 5.7. Chekni/pozitsiyani bekor qilish
1. Ochiq chekdan bitta pozitsiyani bekor qiling → qoldiq **qaytadi**.
2. Butun chekni bekor qiling → status `cancelled`, stol bo'shaydi, printerga
   «BEKOR QILINDI» cheki ketadi.
3. Bekor qilingan chekni qayta bekor qilib bo'lmaydi.

### 5.8. Smena
1. `Smena` ekrani: ochiq smena, kassadagi boshlang'ich pul **500 000**.
2. Statistika: chek soni, tushum, to'lov usullari, tur bo'yicha (zal/saboy/
   dostafka), xarajat, **kassada kutilayotgan pul**.
3. Smenani yopmoqchi bo'ling → **«4 ta band stol bor»** xatosi (avval stollarni
   yopish kerak). Bu — pulni yo'qotmaslik himoyasi.

### 5.9. Xarajatlar va moliya
1. `Xarajat` → kategoriya tanlab, summa kiriting.
2. `Moliya (bugun)`: tushum, xarajat, sof foyda, kategoriya kesimida xarajat.
3. `1111` (admin) bilan kiring → **kechagi kunni ko'ra olmaydi** (403),
   `1234` bilan esa istalgan kun ochiladi.

### 5.10. Ombor va bozor xaridi
1. `Ombor` → 19 ingredient, qoldiq va minimal chegara.
2. `Bozor xaridi` → ta'minotchi tanlang, ingredient + miqdor + summa +
   partiya kodi kiriting.
3. Saqlagach: ombor qoldig'i **oshadi**, yangi **partiya** paydo bo'ladi va
   «Bozor» kategoriyasida **avtomatik xarajat** yoziladi.
4. Xaridni o'chiring → kirim orqaga qaytadi (partiya ishlatilgan bo'lsa
   **o'chirishga ruxsat bermaydi** — hisob buzilmasligi uchun).

### 5.11. Retsept va tannarx
1. `Retsept` → Наполеон (#157): 8 dona/partiya, 6 ingredient.
2. `Tannarx` → 1 dona ≈ **19 200 so'm** (partiya narxi ÷ 8, chiqindi foizi bilan).
3. Ingredient narxi (yangi xarid) o'zgarsa — tannarx ham o'zgaradi.

### 5.12. Pishirish (oshxona)
1. `4444` bilan kiring → **«Pishirish kerak»** ro'yxati (limitdan past mahsulotlar).
2. Наполеон 8 dona `Boshlash` → ombordan ingredient **FIFO** bo'yicha yechiladi
   (eski partiyadan avval).
3. `Tayyor` → mahsulot qoldig'i +8, POS'da darrov sotuvga chiqadi.
4. Boshqa pishirishni `Bekor qilish` → **ingredient omborga to'liq qaytadi**.

### 5.13. Spisaniya va inventarizatsiya
1. `Spisaniya` → mahsulot, miqdor, sabab (muddati o'tgan / sifatsiz / to'kildi).
2. Qoldiq kamayadi, yozuv jurnalda qoladi (kim, qachon, nega).
3. `Inventarizatsiya` → haqiqiy sanoq kiriting → farq hisoblanadi va yoziladi.

### 5.14. CRM, ballar va promo
1. `Mijozlar` → 8 mijoz, tashrif soni, sarflagan puli, ballari.
2. Mijozga qo'lda ball qo'shing/yeching; ball yetmasa **xato beradi**.
3. Chek yopishda mijoz telefonini kiriting → **har 10 000 so'mga 1 ball**
   avtomatik yoziladi (1 ball = 100 so'm).
4. Promo tekshiruvi:
   - `KONAK10` + 100 000 so'm → chegirma **10 000**
   - `KONAK10` + 500 000 so'm → chegirma **20 000** (maksimal cheklov)
   - `SOVGA5` + 10 000 so'm → **rad etiladi** (minimal summa 30 000)
   - `ESKI2025` → **rad etiladi** (muddati o'tgan)
   - `BIRMARTA` → bir marta ishlaydi, ikkinchisida rad etiladi

### 5.15. QR mijoz (stoldan buyurtma)
1. `./scripts/demo_info.sh` dan stol QR havolasini oling va brauzerda oching
   (yoki telefonda QR'ni skanerlang).
2. Mijoz menyusi ochiladi → savatga qo'shing → buyurtma bering.
3. POS'da chek **darrov** paydo bo'ladi (manba: `qr`, raqam `…-Q000010`).
4. `Ofitsiantni chaqirish` va `Hisobni so'rash` → POS'da ovozli/vizual signal.
5. Mijoz menyusida **tannarx, qoldiq, ichki ma'lumot ko'rinmaydi** (ataylab yopiq).

### 5.16. Online buyurtma (saboy / dostafka)
Demo rejimida Telegram bot o'chirilgan, shuning uchun tasdiqlash
**tayyor token** bilan simulyatsiya qilinadi (`demo-verification-token-0002`):

```bash
curl -s -X POST http://localhost:3000/api/online/order \
  -H 'Content-Type: application/json' -d '{
    "type":"delivery",
    "items":[{"product_id":102,"quantity":2}],
    "customer":{"phone":"998901112207",
                "verification_token":"demo-verification-token-0002"},
    "location":{"lat":40.1041,"lng":65.3737,"address":"Navoiy sh., Islom Karimov 5"},
    "note":"2-qavat"}'
```

- POS'da **DOSTAFKA** cheki paydo bo'ladi (raqam `…-O000011`).
- Token **bir marta** ishlaydi — qayta yuborilsa `401`.
- Manzilsiz dostafka → `400`.
- Haqiqiy Telegram oqimini ko'rsatmoqchi bo'lsangiz:
  `DEMO_TELEGRAM=1 ./scripts/run_demo.sh` — lekin bu **jonli botni**
  vaqtincha buzadi (bitta tokenni ikki server so'raydi).

### 5.17. Analitika
1. `Analitika` → oraliqni 14 kun qilib tanlang.
2. Ko'rinadi: tushum, chek soni, o'rtacha chek, chegirmalar, taxminiy tannarx
   (COGS), yalpi/sof foyda, **kunlik trend**, top mahsulot, top kategoriya,
   tur (zal/saboy/dostafka), **manba** (POS/QR/online), to'lov usuli,
   eng gavjum soatlar, mijoz statistikasi.
3. `CSV eksport` → hisobot faylga tushadi.
4. Diqqat: `incomplete_cost_products` — retsepti yo'q mahsulotlar soni; ularning
   tannarxi hisobga kirmaydi (demoda 9 tasidan boshqasi retseptsiz).

### 5.18. Audit, monitoring, backup (faqat super_admin)
1. `Audit` → har bir o'zgarish: kim, nima qildi, qachon, qaysi IP.
2. `Tizim holati` → faol cheklar, ochiq smena, baza ulanishlari, sync navbati,
   oxirgi backup.
3. `Backup` → `Yaratish` bosing → yangi shifrlangan fayl paydo bo'ladi;
   yuklab olsangiz — ichi **shifrlangan** (oddiy dump emas).

### 5.19. Real vaqt (WebSocket) — ikki qurilmada
1. Ikkita ilovani (yoki ilova + brauzer) bir vaqtda oching.
2. Birinchisida stolga chek oching → ikkinchisida stol **darrov** qizaradi.
3. Mahsulot sotilsa — qoldiq ikkala ekranda ham bir vaqtda kamayadi.
4. Menyuni o'zgartirsangiz — ikkinchi qurilma menyuni qayta yuklaydi.

---

## 6. Foydali buyruqlar

```bash
# Token olish
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+998901234567","pin":"1234"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

# Joriy smena statistikasi
curl -s http://localhost:3000/api/shift/current -H "Authorization: Bearer $TOKEN"

# Bugungi moliya
curl -s http://localhost:3000/api/finance/daily -H "Authorization: Bearer $TOKEN"

# 14 kunlik analitika
curl -s "http://localhost:3000/api/analytics/overview?from=$(date -v-13d +%F)&to=$(date +%F)" \
  -H "Authorization: Bearer $TOKEN"

# CSV hisobot
curl -s "http://localhost:3000/api/analytics/export.csv?from=$(date -v-13d +%F)&to=$(date +%F)" \
  -H "Authorization: Bearer $TOKEN" -o hisobot.csv

# Stollarning QR kodlari
curl -s http://localhost:3000/api/tables/qr-codes -H "Authorization: Bearer $TOKEN"

# Bugungi cheklar (bazadan)
psql "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable" \
  -c "select order_number,type,table_sku,status,payment_method,total,source
      from orders where created_at::date=CURRENT_DATE order by id"
```

---

## 7. Cheklovlar (namoyishda aytib o'tish uchun)

| Narsa | Holat | Sabab |
|---|---|---|
| Bulut sync | **o'chiq** (`SYNC_MODE=off`) | demo ma'lumoti jonli bazaga ketmasin |
| Telegram bot | **o'chiq** | bitta bot tokenini ikki server so'rasa, jonli bot ishlamay qoladi |
| Chek printeri | fizik printer yo'q | manzillar `127.0.0.1:910x`; ulanish darrov rad etiladi, dastur **yiqilmaydi**, logda yozib qo'yiladi |
| Tannarx | faqat 9 mahsulotda | qolganlarida retsept yo'q — analitikada `incomplete_cost_products` bo'lib ko'rsatiladi |
| Katalog sync | hali yo'q | menyu/qoldiq/retsept node'lar orasida replikatsiya qilinmaydi (faqat buyurtma/smena/xarajat/zona/xodim) |

---

## 8. Tozalash va qayta tiklash

Namoyishdan keyin (yoki test cheklarini tozalash uchun) demo bazani boshidan
tiklash — **hammasi bir xil holatga qaytadi**:

```bash
psql "postgres://konak:konak@localhost:5432/konak_pos?sslmode=disable" \
     -f scripts/demo_reset.sql
python3 scripts/demo_seed.py
```

`demo_reset.sql` faqat **local demo bazasini** tozalaydi (`konak_pos`),
super_admin xodim va sozlamalar saqlanadi.

Backendni to'xtatish:

```bash
lsof -ti :3000 | xargs kill
```

---

## 9. Fayllar

| Fayl | Vazifasi |
|---|---|
| `scripts/run_demo.sh` | backendni demo rejimida build qilib ishga tushiradi |
| `scripts/demo_seed.py` | demo ma'lumotlarni to'ldiradi (API + SQL) |
| `scripts/demo_reset.sql` | demo bazani boshlang'ich holatga qaytaradi |
| `scripts/demo_info.sh` | namoyish uchun ma'lumot varag'i (loginlar, QR, ochiq cheklar) |
| `scripts/api_test.py` | to'liq avtomatik API test (178 tekshiruv) |
| `scripts/menu_snapshot.json` | Windows master'dan olingan joriy menyu nusxasi |
