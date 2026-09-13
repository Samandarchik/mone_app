// shef/ui/widgets/category_group.dart — ro'yxatni KATEGORIYA bo'yicha
// guruhlashning yagona naqshi: buildCategoryEntries() yassi (flat) ro'yxat
// yasaydi, CategoryHeaderTile esa guruh sarlavhasini chizadi.
//
// Nega yassi ro'yxat: ListView.builder bitta indeks ustida ishlashi kerak
// (sarlavha + qatorlar bitta ro'yxatda). Butun ro'yxatni Column ga yig'ish
// lazy'likni yo'qotadi.
//
// Foydalanuvchilar: shef/ui/shef_create_order_ui.dart, shef/ui/pf_stock_page.dart.
import 'package:flutter/material.dart';

// Yassi ro'yxatdagi guruh sarlavhasi elementi (qolgan elementlar — T qatorlar).
class CategoryHeader {
  final String title;
  final int count; // FILTRdan keyingi (ko'rinadigan) qatorlar soni

  const CategoryHeader(this.title, this.count);
}

// Kategoriyasi bo'sh mahsulotlar guruhi sarlavhasi (doim oxirida).
const String kUncategorizedTitle = 'Kategoriyasiz';

// Elementlarni kategoriya bo'yicha guruhlab, YASSI ro'yxat qaytaradi:
// [CategoryHeader, T, T, CategoryHeader, T, ...].
//
// Qoidalar:
// - guruhlar nomi bo'yicha alifbo tartibida; category_name bo'shlari OXIRIDA
//   «Kategoriyasiz» sarlavhasi ostida;
// - guruh ichida elementlarning kelgan tartibi saqlanadi;
// - ro'yxatda FAQAT BITTA guruh bo'lsa sarlavha qo'shilmaydi (ortiqcha shovqin) —
//   natija oddiy qatorlar ro'yxati bo'ladi;
// - bo'sh guruh umuman chizilmaydi (filtrlangan ro'yxat kirsa, o'zi chiqib ketadi).
//
// MUHIM: bu funksiya sort qiladi — uni har build'da emas, faqat manba ro'yxat
// yoki qidiruv matni o'zgarganda chaqirib, natijasini keshlash kerak.
List<Object> buildCategoryEntries<T extends Object>(
  List<T> items, {
  required int Function(T item) categoryId,
  required String Function(T item) categoryName,
}) {
  if (items.isEmpty) return const [];

  // Kalit: nomi bo'sh bo'lsa hammasi bitta «Kategoriyasiz» guruhiga tushadi,
  // aks holda id + nom (bir xil nomli ikki kategoriya aralashib ketmasin).
  final groups = <String, List<T>>{};
  final titles = <String, String>{};

  for (final item in items) {
    final name = categoryName(item).trim();
    final key = name.isEmpty ? '' : '${categoryId(item)}|$name';
    (groups[key] ??= <T>[]).add(item);
    titles[key] = name.isEmpty ? kUncategorizedTitle : name;
  }

  // Bitta guruh — sarlavhasiz, hozirgi ko'rinish saqlanadi.
  if (groups.length == 1) return List<Object>.of(items);

  final keys = groups.keys.toList()
    ..sort((a, b) {
      // Kategoriyasiz («') doim oxirida.
      if (a.isEmpty) return b.isEmpty ? 0 : 1;
      if (b.isEmpty) return -1;
      final ta = titles[a]!.toLowerCase();
      final tb = titles[b]!.toLowerCase();
      final c = ta.compareTo(tb);
      return c != 0 ? c : a.compareTo(b);
    });

  final entries = <Object>[];
  for (final key in keys) {
    final rows = groups[key]!;
    if (rows.isEmpty) continue;
    entries.add(CategoryHeader(titles[key]!, rows.length));
    entries.addAll(rows);
  }
  return entries;
}

// Guruh sarlavhasi: kichik, qalin, accent chiziqli — shef ekranlari uslubida
// (fon 0xFFFAF6F1, accent 0xFFC5A97B).
class CategoryHeaderTile extends StatelessWidget {
  final CategoryHeader header;

  const CategoryHeaderTile({super.key, required this.header});

  static const Color _accentColor = Color(0xFFC5A97B);
  static const Color _headerBg = Color(0xFFF2EADE);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: const BoxDecoration(
          color: _headerBg,
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border(left: BorderSide(color: _accentColor, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                header.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${header.count})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.brown.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
