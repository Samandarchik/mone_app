// shef/ui/biskvit_page.dart — shef bosh menyusidagi «Biskvit» bo'limi
// (BiskvitPage): tepada biskvit rasmi (assets/biskvit.png), ostida shef
// QO'SHGAN kategoriyalar kartalari — har birida kategoriyaning o'z rasmi,
// nomi va mahsulot soni (masalan Бисквит, Начинка, Крем, Украшения).
// AppBar'dagi «+» — «Тех карта»dagi kategoriyalardan birini tanlab qo'shish;
// kartani bosib turish — bo'limdan olib tashlash (kategoriya o'chmaydi,
// «Тех карта»ga qaytadi). Ro'yxat ID bo'yicha, qurilmada saqlanadi
// (BiskvitLinks, SharedPreferences). Nom bo'yicha taxmin ATAYLAB yo'q:
// o'xshash nomli boshqa kategoriya begona mahsulotlarni ko'rsatib qo'yardi.
// Karta bosilsa ShefTechCardProductsPage — «Тех карта»dagi o'sha kategoriya
// sahifasining O'ZI (hamma mahsulot va retseptlari bilan) + «Qo'shish».
// Qo'shilgan kategoriyalar «Тех карта» ro'yxatidan yashiriladi
// (BiskvitLinks.linkedIds → shef_tech_card_page.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

const String _biskvitImage = 'assets/biskvit.png';

// Biskvit bo'limidagi kategoriyalar (id'lar, qo'shilgan tartibida).
// Qurilmada saqlanadi; logout o'chirmaydi (session.dart faqat o'z
// kalitlarini tozalaydi).
class BiskvitLinks {
  BiskvitLinks._();

  static const String _prefsKey = 'shef_biskvit_categories';
  // Avvalgi versiya: 4 ta qat'iy bo'lim → id xaritasi. Bir marta ko'chiriladi.
  static const String _legacyKey = 'shef_biskvit_links';
  static const List<String> _legacyOrder = [
    'biskvit',
    'nachinka',
    'krem',
    'bezak',
  ];

  static List<int> _ids = [];
  static bool _loaded = false;

  static List<int> get ids => List.unmodifiable(_ids);
  static Set<int> get linkedIds => _ids.toSet();

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _ids = [
          for (final v in jsonDecode(raw) as List)
            if (v is num) v.toInt(),
        ];
      } else {
        final legacy = prefs.getString(_legacyKey);
        if (legacy != null && legacy.isNotEmpty) {
          final map = jsonDecode(legacy) as Map<String, dynamic>;
          for (final k in _legacyOrder) {
            final v = map[k];
            if (v is num && !_ids.contains(v.toInt())) _ids.add(v.toInt());
          }
          await _save(prefs);
          await prefs.remove(_legacyKey);
        }
      }
    } catch (_) {
      // Buzilgan qiymat — bo'sh ro'yxatdan boshlaymiz (qayta qo'shiladi).
      _ids = [];
    }
    _loaded = true;
  }

  static Future<void> add(int categoryId) async {
    if (_ids.contains(categoryId)) return;
    _ids = [..._ids, categoryId];
    await _save(await SharedPreferences.getInstance());
  }

  static Future<void> remove(int categoryId) async {
    _ids = _ids.where((id) => id != categoryId).toList();
    await _save(await SharedPreferences.getInstance());
  }

  static Future<void> _save(SharedPreferences prefs) =>
      prefs.setString(_prefsKey, jsonEncode(_ids));
}

// Shef bosh menyusiga «+» bilan qo'shilgan kategoriyalar (id'lar, qo'shilgan
// tartibida) — BiskvitLinks bilan bir xil, faqat bo'lim bosh ekranning o'zi
// (shef_home_ui.dart). Bular ham «Тех карта» ro'yxatidan yashiriladi.
class ShefHomeLinks {
  ShefHomeLinks._();

  static const String _prefsKey = 'shef_home_categories';

  static List<int> _ids = [];
  static bool _loaded = false;

  static List<int> get ids => List.unmodifiable(_ids);
  static Set<int> get linkedIds => _ids.toSet();

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _ids = [
          for (final v in jsonDecode(raw) as List)
            if (v is num) v.toInt(),
        ];
      }
    } catch (_) {
      _ids = [];
    }
    _loaded = true;
  }

  static Future<void> add(int categoryId) async {
    if (_ids.contains(categoryId)) return;
    _ids = [..._ids, categoryId];
    await _save(await SharedPreferences.getInstance());
  }

  static Future<void> remove(int categoryId) async {
    _ids = _ids.where((id) => id != categoryId).toList();
    await _save(await SharedPreferences.getInstance());
  }

  static Future<void> _save(SharedPreferences prefs) =>
      prefs.setString(_prefsKey, jsonEncode(_ids));
}

// «+» oynasi: «Тех карта»dagi kategoriyalardan birini tanlash (rasm, nom va
// mahsulot soni bilan). [exclude] — allaqachon biror bo'limga qo'shilganlar.
// Biskvit bo'limi va shef bosh ekrani shu oynani ishlatadi.
Future<CategoryProductAdmin?> pickTechCardCategory(
  BuildContext context, {
  required Set<int> exclude,
  required String hint,
}) async {
  final cats = context.read<CategoryProviderAdmin>();
  if (cats.categories.isEmpty) await cats.getCategories();
  if (!context.mounted) return null;
  final counts = <int, int>{};
  for (final p in context.read<ProductProviderAdmin>().products) {
    counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
  }
  final options =
      cats.categories.where((c) => !exclude.contains(c.id)).toList();

  return showModalBottomSheet<CategoryProductAdmin>(
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
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Kategoriya qo\'shish',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: options.isEmpty
                ? const Center(
                    child: Text(
                      'Qo\'shiladigan kategoriya qolmadi',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView.separated(
                    controller: scroll,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final c = options[i];
                      return ListTile(
                        onTap: () => Navigator.pop(ctx, c),
                        leading: CategoryThumb(category: c, size: 44),
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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
}

// Kategoriya rasmi to'liq manzili (backend nisbiy yo'l qaytaradi).
String _imageUrlOf(CategoryProductAdmin c) {
  final url = c.imageUrl ?? '';
  if (url.isEmpty) return '';
  return url.startsWith('http') ? url : '${AppUrls.baseUrl}$url';
}

// «Biskvit» — qo'shilgan kategoriyalar.
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

  void _openCategory(CategoryProductAdmin category) {
    // Sarlavha — kategoriyaning o'z nomi, xuddi «Тех карта»dagidek.
    Navigator.push(
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

  // «+» — hali qo'shilmagan kategoriyalardan birini tanlash. Tanlangani
  // darhol karta bo'lib chiqadi. Bosh ekranga qo'shilganlar ham chiqmaydi.
  Future<void> _addCategory() async {
    await Future.wait([BiskvitLinks.load(), ShefHomeLinks.load()]);
    if (!mounted) return;
    final picked = await pickTechCardCategory(
      context,
      exclude: {...BiskvitLinks.linkedIds, ...ShefHomeLinks.linkedIds},
      hint: '«Тех карта»dagi kategoriya hamma mahsulotlari bilan '
          'Biskvit bo\'limiga o\'tadi',
    );
    if (picked == null || !mounted) return;
    await BiskvitLinks.add(picked.id);
    if (!mounted) return;
    setState(() {});
  }

  // Kartani bosib turish — bo'limdan olib tashlash (tasdiq bilan).
  Future<void> _removeCategory(CategoryProductAdmin category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biskvit bo\'limidan olib tashlash'),
        content: Text(
          '«${category.name}» Biskvit bo\'limidan olinib, yana «Тех карта»da '
          'ko\'rinadi. Kategoriya va mahsulotlar o\'chmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Olib tashlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await BiskvitLinks.remove(category.id);
    if (!mounted) return;
    setState(() {});
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
        actions: [
          IconButton(
            onPressed: _addCategory,
            tooltip: 'Kategoriya qo\'shish',
            icon: const Icon(Icons.add_circle_outline),
            color: Colors.brown.shade700,
            iconSize: 28,
          ),
          const SizedBox(width: 4),
        ],
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
          // Kartalar soni kichik — ikkala provider'ni kuzatish arzon.
          Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
            builder: (context, cats, products, _) {
              if (!_linksLoaded) return const SizedBox.shrink();
              final byId = {for (final c in cats.categories) c.id: c};
              final counts = <int, int>{};
              for (final p in products.products) {
                counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
              }
              // Backend'da o'chirilgan (ro'yxatda yo'q) id'lar ko'rsatilmaydi.
              final linked = [
                for (final id in BiskvitLinks.ids)
                  if (byId[id] != null) byId[id]!,
              ];
              if (linked.isEmpty) {
                return _EmptyHint(onAdd: _addCategory);
              }
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
                children: [
                  for (final c in linked)
                    _CategoryTile(
                      category: c,
                      count: counts[c.id] ?? 0,
                      onTap: () => _openCategory(c),
                      onLongPress: () => _removeCategory(c),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Hali kategoriya qo'shilmagan — «+» ga yo'naltiruvchi ko'rinish.
class _EmptyHint extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Text(
            'Hozircha kategoriya yo\'q.\n«+» bilan «Тех карта»dagi '
            'kategoriyani qo\'shing',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Kategoriya qo\'shish'),
          ),
        ],
      ),
    );
  }
}

// Kategoriya rasmi (bo'lmasa ikonka) — kvadrat, yumaloq burchak.
class CategoryThumb extends StatelessWidget {
  final CategoryProductAdmin category;
  final double size;
  // null — kvadrat (size × size).
  final double? width;

  const CategoryThumb({
    super.key,
    required this.category,
    required this.size,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final url = _imageUrlOf(category);
    final w = width ?? size;
    final placeholder = Container(
      width: w,
      height: size,
      color: _accentColor.withValues(alpha: 0.15),
      child:
          Icon(Icons.category_outlined, color: _accentColor, size: size * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url.isEmpty
          ? placeholder
          : AppNetworkImage(
              imageUrl: url,
              width: w,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_) => placeholder,
              errorWidget: (_) => placeholder,
            ),
    );
  }
}

// Bo'limdagi bitta kategoriya kartasi: tepada rasmi, ostida nomi va soni.
class _CategoryTile extends StatelessWidget {
  final CategoryProductAdmin category;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => CategoryThumb(
                    category: category,
                    size: box.maxHeight,
                    width: box.maxWidth,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count ta mahsulot',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
