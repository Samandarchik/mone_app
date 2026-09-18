// shef/ui/biskvit_page.dart — shef bosh menyusidagi «Biskvit» bo'limi
// (BiskvitPage): tepada biskvit rasmi (assets/biskvit.png), ostida to'rt
// bo'lim — Biskvit / Nachinka / Krem / Bezaklar.
// Har bo'lim backend'dagi MAVJUD kategoriyaga (Тех картадаги Бисквит, Крем...)
// ID bo'yicha bog'lanadi. Bog'lanishni shef O'ZI tanlaydi (birinchi bosishda
// yoki kartani bosib turib — ro'yxatdan) va u qurilmada saqlanadi
// (BiskvitLinks, SharedPreferences). Nom bo'yicha taxmin ATAYLAB yo'q: o'xshash
// nomli boshqa kategoriya (masalan «Бисквиты» — pechenye) noto'g'ri
// mahsulotlarni ko'rsatib qo'yardi.
// Bo'lim bosilsa ShefTechCardProductsPage — «Тех карта»dagi o'sha kategoriya
// sahifasining O'ZI (hamma mahsulot va retseptlari bilan) + «Qo'shish».
// Bog'langan kategoriyalar «Тех карта» ro'yxatidan yashiriladi
// (BiskvitLinks.linkedIds → shef_tech_card_page.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

const String _biskvitImage = 'assets/biskvit.png';

// Bo'lim → kategoriya id bog'lanishi (qurilmada saqlanadi; logout
// o'chirmaydi — session.dart faqat o'z kalitlarini tozalaydi).
class BiskvitLinks {
  BiskvitLinks._();

  static const String _prefsKey = 'shef_biskvit_links';
  static Map<String, int> _ids = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _ids = {
          for (final e in map.entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
        };
      }
    } catch (_) {
      // Buzilgan qiymat — bog'lanishsiz boshlaymiz (qayta tanlanadi).
      _ids = {};
    }
    _loaded = true;
  }

  static int? idFor(String sectionKey) => _ids[sectionKey];

  static Set<int> get linkedIds => _ids.values.toSet();

  static Future<void> set(String sectionKey, int categoryId) async {
    _ids = {..._ids, sectionKey: categoryId};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_ids));
  }
}

// Biskvitning bitta bo'limi.
class _BiskvitSection {
  final String key;
  final String title;
  final IconData icon;

  const _BiskvitSection(this.key, this.title, this.icon);
}

const List<_BiskvitSection> _biskvitSections = [
  _BiskvitSection('biskvit', 'Biskvit', Icons.interests_outlined),
  _BiskvitSection('nachinka', 'Nachinka', Icons.layers_outlined),
  _BiskvitSection('krem', 'Krem', Icons.icecream_outlined),
  _BiskvitSection('bezak', 'Bezaklar', Icons.auto_awesome_outlined),
];

// «Biskvit» — to'rt bo'lim.
class BiskvitPage extends StatefulWidget {
  const BiskvitPage({super.key});

  @override
  State<BiskvitPage> createState() => _BiskvitPageState();
}

class _BiskvitPageState extends State<BiskvitPage> {
  bool _linksLoaded = false;

  @override
  void initState() {
    super.initState();
    BiskvitLinks.load().then((_) {
      if (mounted) setState(() => _linksLoaded = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Kartalardagi «N ta» soni uchun (allaqachon yuklangan bo'lsa — jim).
      context.read<ProductProviderAdmin>().initializeProducts();
    });
  }

  CategoryProductAdmin? _linkedCategory(_BiskvitSection s) {
    final id = BiskvitLinks.idFor(s.key);
    if (id == null) return null;
    for (final c in context.read<CategoryProviderAdmin>().categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  // Bitta bosish: bog'langan bo'lsa — kategoriya sahifasi, aks holda tanlash.
  Future<void> _openSection(_BiskvitSection s) async {
    final category = _linkedCategory(s);
    if (category == null) {
      final picked = await _pickCategory(s);
      if (picked == null || !mounted) return;
      return _openCategory(picked);
    }
    return _openCategory(category);
  }

  Future<void> _openCategory(CategoryProductAdmin category) {
    // Sarlavha — kategoriyaning o'z nomi, xuddi «Тех карта»dagidek.
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShefTechCardProductsPage(
          categoryId: category.id,
          categoryName: category.name,
          canAddProducts: true,
        ),
      ),
    );
  }

  // Kategoriya tanlash oynasi — «Тех карта»dagi (shefga belgilangan) hamma
  // kategoriya, mahsulot soni bilan. Tanlangani saqlanadi.
  Future<CategoryProductAdmin?> _pickCategory(_BiskvitSection s) async {
    final cats = context.read<CategoryProviderAdmin>();
    if (cats.categories.isEmpty) await cats.getCategories();
    if (!mounted) return null;
    final counts = <int, int>{};
    for (final p in context.read<ProductProviderAdmin>().products) {
      counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
    }
    final currentId = BiskvitLinks.idFor(s.key);
    // Boshqa bo'limlarga allaqachon bog'langanlar — belgi bilan ko'rsatiladi.
    final otherLinks = <int, String>{
      for (final o in _biskvitSections)
        if (o.key != s.key && BiskvitLinks.idFor(o.key) != null)
          BiskvitLinks.idFor(o.key)!: o.title,
    };

    final picked = await showModalBottomSheet<CategoryProductAdmin>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '«${s.title}» uchun kategoriya',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '«Тех карта»dagi kategoriyani tanlang — uning hamma '
                'mahsulotlari shu bo\'limda ko\'rinadi',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: cats.categories.isEmpty
                  ? const Center(
                      child: Text(
                        'Kategoriya yo\'q',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: cats.categories.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final c = cats.categories[i];
                        final selected = c.id == currentId;
                        final usedBy = otherLinks[c.id];
                        return ListTile(
                          onTap: () => Navigator.pop(ctx, c),
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected ? _accentColor : Colors.black38,
                          ),
                          title: Text(
                            c.name,
                            style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: usedBy == null
                              ? null
                              : Text('Hozir «$usedBy» bo\'limida',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800)),
                          trailing: Text(
                            '${counts[c.id] ?? 0} ta',
                            style: TextStyle(
                                fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return null;
    await BiskvitLinks.set(s.key, picked.id);
    if (!mounted) return null;
    setState(() {});
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Biskvit',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // Tepada guruh rasmi — qaysi bo'limda turganini ko'rsatib turadi.
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 150,
              color: Colors.white,
              alignment: Alignment.center,
              child: Image.asset(
                _biskvitImage,
                height: 130,
                cacheHeight: 390,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Sahifada atigi 4 karta — ikkala provider'ni kuzatish arzon.
          Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
            builder: (context, cats, products, _) {
              final byId = {for (final c in cats.categories) c.id: c};
              final counts = <int, int>{};
              for (final p in products.products) {
                counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
              }
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  for (final s in _biskvitSections)
                    Builder(builder: (context) {
                      final id = _linksLoaded ? BiskvitLinks.idFor(s.key) : null;
                      final category = id == null ? null : byId[id];
                      return _SectionCard(
                        section: s,
                        linkedName: category?.name,
                        count: category == null ? 0 : (counts[category.id] ?? 0),
                        onTap: () => _openSection(s),
                        onLongPress: () => _pickCategory(s),
                      );
                    }),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Kategoriyani almashtirish — kartani bosib turing',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// Biskvit bo'limi kartasi (shef bosh menyusidagi _MenuCard uslubida). Ostida
// bog'langan kategoriya nomi yoki «tanlanmagan».
class _SectionCard extends StatelessWidget {
  final _BiskvitSection section;
  final String? linkedName;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SectionCard({
    required this.section,
    required this.linkedName,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final linked = linkedName != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(section.icon, color: _accentColor, size: 26),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Text(
                      '$count ta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                linked ? linkedName! : 'Kategoriya tanlanmagan — bosing',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: linked ? Colors.grey.shade600 : Colors.orange.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
