# POS Menu — Kategoriya va Mahsulotlar Logikasi

Bu hujjat `order/order_screen.dart` ichidagi menyu (chap panel) qanday qurilishini, kategoriyalar va mahsulotlar qanday tartibda ko'rsatilishini, almashtirish (switch) logikasini tushuntiradi.

Asosiy kod: `mobile/lib/features/pos/order/order_screen.dart`
Yordamchi kod: `mobile/lib/core/services/local_db.dart` (saqlash + tartiblash)

---

## 1. Ma'lumot manbasi (data source)

Menyu **LocalDB** dan o'qiladi (SQLite mobil, in-memory web). Agar local bo'sh bo'lsa, server `/api/menu` dan olinadi va localga yoziladi.

```dart
// _loadMenu()  — order_screen.dart:64
final cats  = await LocalDB().getCategories();
final prods = await LocalDB().getProducts();
if (cats.isEmpty) {
  final m = await ApiService().getMenu(force: true);
  await LocalDB().saveCategories(m['categories']);
  await LocalDB().saveProducts(m['products']);
}
```

State `_menu = {'categories': [...], 'products': [...]}` ko'rinishida saqlanadi.

---

## 2. Tartib (sort_order)

Kategoriya ham, mahsulot ham server tomonidan beriladigan **`sort_order`** maydoni bo'yicha tartiblanadi. Bu tartib LocalDB ga yozilganda ham, o'qilganda ham saqlanadi.

```dart
// local_db.dart:99
final rows = await _db!.query('categories', orderBy: 'sort_order');

// local_db.dart:129
final rows = await _db!.query('products',
    where: 'status = ?', whereArgs: ['active'],
    orderBy: 'sort_order');
```

Muhim:
- Faqat `status = 'active'` bo'lgan mahsulotlar olinadi.
- `sort_order` qiymati admin paneldagi **drag-drop** orqali o'zgartirilib, `POST /api/reorder` endpoint orqali serverga yuboriladi (qarang: CLAUDE.md "Mahsulotlar boshqarish").
- Demak: POSdagi tartib = adminda admin sudrab qo'ygan tartib.

---

## 3. Sahifalar tuzilishi (`_catPages`)

PageView uchun sahifalar massivi shu logika bilan quriladi:

```dart
// order_screen.dart:113
List<List<dynamic>> get _catPages {
  final all = _menu?['products'] as List<dynamic>? ?? [];
  final pages = <List<dynamic>>[all];        // index 0 = "Hammasi"
  for (final c in _categories) {
    pages.add(all.where((p) => p['category_id'] == c['id']).toList());
  }
  return pages;
}
```

Natija — sahifalar massivi:

| Index | Sahifa            | Mazmun                                  |
|-------|-------------------|------------------------------------------|
| 0     | **Hammasi**       | Barcha aktiv mahsulotlar (sort_order)   |
| 1     | Kategoriya[0]     | `category_id == categories[0].id`       |
| 2     | Kategoriya[1]     | `category_id == categories[1].id`       |
| ...   | ...               | ...                                      |
| N     | Kategoriya[N-1]   | oxirgi kategoriya mahsulotlari          |

Muhim nuqtalar:
- `_categories` ham `sort_order` bo'yicha kelgani uchun, sahifalarning chap-o'ngga tartibi = adminda kategoriyalarni qo'yilgan tartib.
- Har bir kategoriya sahifasidagi mahsulotlar tartibi = `products` ro'yxati ichidagi tartib (chunki `.where(...)` filtrlash original tartibni saqlaydi). Ya'ni mahsulot `sort_order` ham hurmat qilinadi.
- "Hammasi" sahifasi — **barcha** mahsulotlar (kategoriyaga qarab guruhlanmagan), ular `sort_order` bo'yicha global ketma-ketlikda.

---

## 4. UI komponenti — ekran kengligiga qarab ikki xil

`build()` da `MediaQuery` kengligi `AppBreakpoints.phone` (720) bilan solishtiriladi:

**Keng ekran (desktop/planshet, ≥720):** chapda buyurtma paneli, o'ngda menyu.

```
┌──────────────────┬──────────────────────────────────────┐
│ Buyurtma  3 chek │ [Hammasi] [Kompot] [Salat] [Plov]... │
├──────────────────┼──────────────────────────────────────┤
│ YANGI CHEK  2 ta │ ┌─┐┌─┐┌─┐┌─┐┌─┐                      │
│  Plov  x2        │ └─┘└─┘└─┘└─┘└─┘   ← kichik kartochka │
│ YUBORILGAN       │ ┌─┐┌─┐┌─┐┌─┐┌─┐     (max 150px)      │
│  #P7  ...        │ └─┘└─┘└─┘└─┘└─┘                      │
├──────────────────┤                                      │
│ Jami  88 000     │                                      │
│ [Chek] [To'lov]  │                                      │
└──────────────────┴──────────────────────────────────────┘
```

- Chap panel eni: 320 (ekran ≥1400 bo'lsa 380).
- Grid: `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisExtent: 168)` — ustun soni kenglikdan o'zi hisoblanadi.
- Pastki `_BottomBar` **ko'rsatilmaydi** (uning o'rnida chap panel tugmalari).

**Telefon (<720):** eski ko'rinish — faqat menyu, savat/cheklar pastki bar va bottom sheet orqali.

```
┌─────────────────────────────────────────────┐
│ [Hammasi] [Kompot] [Salat] [Plov] [Choy]... │  ← ChoiceChip lar (gorizontal scroll)
├─────────────────────────────────────────────┤
│  ┌─┐ ┌─┐ ┌─┐                                │
│  │ │ │ │ │ │                                │  ← GridView (3 ustun)
│  └─┘ └─┘ └─┘                                │
│  ...mahsulot kartochkalari...               │
├─────────────────────────────────────────────┤
│ [4 chek 88 000]                   [To'lov]  │  ← _BottomBar
└─────────────────────────────────────────────┘
```

### 4.0 Chap panel tarkibi (`_buildOrderPanel`)
- **YANGI CHEK** — hali yuborilmagan savat (`_cart`), har qatori `_CartTile`
  (bosilsa −1, uzoq bosilsa tez kamayadi, ✕ butunlay o'chiradi).
- **YUBORILGAN** — `_buildChecksDetail()` (bottom sheet bilan bir xil kod):
  chek raqami, vaqti, mahsulotlari, bekor qilish tugmalari.
- Pastda: savat jami + **Yuborish**, keyin Mahsulotlar / Jami +
  **Chek** va **To'lov** tugmalari. Bekor qilinayotgan mahsulotlar bo'lsa —
  `_buildCancelCart()` qizil bloki.

### 4.1 Yuqorida — kategoriya chip lar
- `SizedBox(height: 42)` ichida `ListView.builder` (gorizontal).
- `itemCount = _categories.length + 1` — birinchisi har doim **"Hammasi"**.
- `ChoiceChip(selected: _selectedCatIndex == i)` — aktiv chip belgilanadi.
- `onSelected` → `setState(_selectedCatIndex = i)` + `_catPageController.animateToPage(i)` (300ms).

### 4.2 O'rta — PageView (mahsulotlar)
- `PageView.builder(controller: _catPageController, itemCount: _catPages.length)`.
- `onPageChanged: (i) => _selectedCatIndex = i` — barmoq bilan chap-o'ng surganda chip sinxronlashadi.
- Har sahifa = `GridView.builder`; grid delegate ekran kengligiga qarab tanlanadi (4-bo'limga qarang).

### 4.3 Mahsulot kartochkasi
Ko'rsatadi:
- Rasm (yoki `Icons.fastfood` placeholder)
- Stock badge (yuqori-o'ng burchak, agar `stockCount != null`) — masalan `48`.
- Mahsulot nomi (`p['name']['uz']`) — 1 qator, ellipsis.
- Narx — yashil rang.
- **"Tugadi"** overlay (qizil) — agar `stockCount <= 0`.

Tap reaksiyasi:
- Tugagan bo'lsa (`soldOut`) → `onTap = null`, `Opacity(0.4)`.
- Aksincha → `_addToCart(product)`.

### 4.4 Stock tekshiruvi (`_addToCart`)
```dart
// order_screen.dart:122
final stockCount     = AppState().getStockCount(product['id']);
final currentInCart  = (savatdagi soni)
if (stockCount != null && (currentInCart + 1) > stockCount) {
  // SnackBar: "faqat N ta qolgan"
  return;
}
```
`AppState().stocks` — WSS orqali real-time yangilanadi (CLAUDE.md "Stock (Limit)").

---

## 5. Almashtirish (switch) ikki yo'nalishda

Chip ↔ PageView **ikkala yo'nalishda** sinxron:

```
ChoiceChip bosildi
  └─> setState(_selectedCatIndex = i)
  └─> _catPageController.animateToPage(i, 300ms)

PageView surildi
  └─> onPageChanged(i)
  └─> setState(_selectedCatIndex = i)   // chip aktivlik holatini yangilaydi
```

Ikkala yo'lda ham `_selectedCatIndex` — yagona haqiqat (single source of truth), shu sababli chip va sahifa hech qachon mos kelmasligi mumkin emas.

---

## 6. Real-time yangilanish

Menyu o'zgarishlarini WSS tinglaydi:

```dart
// order_screen.dart:58
if (e['event'] == 'order:items_added' || ... ) {
  _loadTable();  // o'ng panel (cheklar) yangilanadi
}

AppState().addListener(_onAppStateChanged);  // stock yangilansa setState
```

Ya'ni `stock:updated` WSS event keladi → `AppState().stocks` yangilanadi → `addListener` orqali `setState` chaqiriladi → mahsulot kartochkasidagi stock badge va "Tugadi" overlay darhol qayta chiziladi (rebuild).

Menyu tarkibi (kategoriyalar, mahsulotlar ro'yxati) o'zgarsa — bu `menu:outdated` WSS event orqali markaziy joyda LocalDB qayta yuklanadi va `_menu` keyingi `_loadMenu` chaqiruvida yangilanadi.

---

## 7. Qisqa xulosa

1. **Manba**: LocalDB (`getCategories`, `getProducts`), bo'sh bo'lsa server.
2. **Tartib**: `sort_order` ASC (admindan drag-drop bilan boshqariladi).
3. **Filter**: faqat `status = 'active'` mahsulotlar.
4. **Sahifalar**: `[Hammasi, Kat1, Kat2, ..., KatN]` — `_catPages`.
5. **Sahifa ichida**: mahsulotlar `category_id` bo'yicha filtrlanadi, lekin global `sort_order` saqlanadi.
6. **UI**: yuqorida `ChoiceChip` qatori, ostida `GridView` (desktopda kichik kartochkalar, telefonda 3 ustun), ChoiceChip ↔ PageView ikkala tomonga sinxron. Desktopda chapda buyurtma paneli turadi.
7. **Stock**: `AppState().getStockCount(id)` — WSS orqali real-time, savatga qo'shishda lokal validatsiya.
