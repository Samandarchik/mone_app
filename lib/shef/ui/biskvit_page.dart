// shef/ui/biskvit_page.dart — shef bosh menyusidagi «Торты» bo'limi
// (BiskvitPage — sinf/fayl nomi eski, KO'RINADIGAN nom «Торты»):
// tepada HAMMA tortlar gridi (rasm YO'Q — biskvit.png faqat
// bosh menyu kartasida), ostida shef QO'SHGAN kategoriyalar kartalari — har
// birida kategoriyaning o'z rasmi, nomi va mahsulot soni (masalan Бисквит,
// Начинка, Крем, Украшения). Tort kartasi BIR marta bosilsa — TORTNING O'Z
// TO'LIQ konstruktori (ShefCakeConstructorPage: biskvit, kesim va tayyor
// tort — shu tortning tex kartasi va undagi пф'larning tex kartalari
// bo'yicha, 3-qadamda fotosidan 3D model); IKKI marta — tortning tex
// kartasi. Umumiy konstruktor (kategoriyalardan tanlash,
// ShefConstructorPage) bu bo'limda YO'Q — u faqat «Готовый» ekranida.
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
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/admin_add_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_cake_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_cakes_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

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

// Shef ko'radigan hamma kategoriyalar (id → kategoriya): «Тех карта»
// ro'yxati + полуфабрикат qoldig'ida uchraydigan, lekin u ro'yxatda YO'Q
// kategoriyalar (shefga belgilanmagan пф kategoriyalari). Ikkinchilarining
// rasmi yo'q — kartada ikonka chiqadi.
Map<int, CategoryProductAdmin> shefCategoriesById(
  List<CategoryProductAdmin> categories,
  List<PfStockRow> pf,
) {
  final byId = {for (final c in categories) c.id: c};
  for (final r in pf) {
    final name = r.categoryName.trim();
    if (r.categoryId <= 0 || name.isEmpty || byId.containsKey(r.categoryId)) {
      continue;
    }
    byId[r.categoryId] = CategoryProductAdmin(
      id: r.categoryId,
      name: name,
      imageUrl: null,
      printerId: 1,
    );
  }
  return byId;
}

// «+» oynasi: kategoriyalardan birini tanlash (rasm, nom va mahsulot soni
// bilan). Ikki bo'lim: «Полуфабрикат» (ichida пф bor kategoriyalar) va
// «Тех карта» (qolganlari). [exclude] — allaqachon biror bo'limga
// qo'shilganlar. Biskvit bo'limi va shef bosh ekrani shu oynani ishlatadi.
Future<CategoryProductAdmin?> pickTechCardCategory(
  BuildContext context, {
  required Set<int> exclude,
  required String hint,
  // true — «Торт» kategoriyalari ro'yxatda chiqmaydi («Торты» bo'limi:
  // hamma tortlar allaqachon tepadagi gridda, karta takror bo'lardi).
  bool hideTort = false,
}) async {
  final cats = context.read<CategoryProviderAdmin>();
  final shef = context.read<ShefProvider>();
  await Future.wait([
    if (cats.categories.isEmpty) cats.getCategories(),
    if (shef.pfStock.isEmpty) shef.fetchPfStock(),
  ]);
  if (!context.mounted) return null;
  final counts = <int, int>{};
  for (final p in context.read<ProductProviderAdmin>().products) {
    counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
  }
  // Har kategoriyadagi пф soni — bo'limga ajratish va «N ta пф» uchun.
  final pfCounts = <int, int>{};
  for (final r in shef.pfStock) {
    if (r.categoryId > 0) {
      pfCounts[r.categoryId] = (pfCounts[r.categoryId] ?? 0) + 1;
    }
  }
  final all = shefCategoriesById(cats.categories, shef.pfStock)
      .values
      .where((c) => !exclude.contains(c.id))
      .where((c) => !hideTort || !isTortCategory(c.name));
  final pfOptions = all.where((c) => pfCounts.containsKey(c.id)).toList();
  final otherOptions = all.where((c) => !pfCounts.containsKey(c.id)).toList();
  final empty = pfOptions.isEmpty && otherOptions.isEmpty;

  Widget sectionHeader(String title) => Container(
        width: double.infinity,
        color: _bgColor,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade700,
          ),
        ),
      );

  Widget optionTile(BuildContext ctx, CategoryProductAdmin c, String count) =>
      ListTile(
        onTap: () => Navigator.pop(ctx, c),
        leading: CategoryThumb(category: c, size: 44),
        title: Text(
          c.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Text(
          count,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
      );

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
            child: empty
                ? const Center(
                    child: Text(
                      'Qo\'shiladigan kategoriya qolmadi',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ListView(
                    controller: scroll,
                    children: [
                      if (pfOptions.isNotEmpty) ...[
                        sectionHeader('Полуфабрикат'),
                        for (final c in pfOptions) ...[
                          optionTile(ctx, c, '${pfCounts[c.id]} ta пф'),
                          const Divider(height: 1),
                        ],
                      ],
                      if (otherOptions.isNotEmpty) ...[
                        sectionHeader('Тех карта'),
                        for (final c in otherOptions) ...[
                          optionTile(ctx, c, '${counts[c.id] ?? 0} ta'),
                          const Divider(height: 1),
                        ],
                      ],
                    ],
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
      // Qo'shilgan пф kategoriyalari nomi shu ro'yxatdan topiladi.
      final shef = context.read<ShefProvider>();
      if (shef.pfStock.isEmpty) shef.fetchPfStock();
    });
  }

  void _openCategory(CategoryProductAdmin category) {
    // «Торты» — tortlar gridi, tort bosilsa konstruktor (shef_cakes_page).
    if (isTortCategory(category.name)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShefCakesPage(
            categoryId: category.id,
            categoryName: category.name,
            canAddProducts: true,
          ),
        ),
      );
      return;
    }
    // Sarlavha — kategoriyaning o'z nomi, xuddi «Тех карта»dagidek.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShefTechCardProductsPage(
          categoryId: category.id,
          categoryName: category.name,
          canAddProducts: true,
          // Pishirish vaqti/harorati — faqat «Бисквит» kategoriyasida.
          showBaking: isBiskvitCategory(category.name),
          // «Начинка» — kesilgan tort, kesimda nachinka (тех картадан).
          showFillingCake: isNachinkaCategory(category.name),
        ),
      ),
    );
  }

  // Tort bosilsa — tortning o'z to'liq konstruktori (tex kartasidan).
  void _openCakeConstructor(ProductModelAdmin cake) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShefCakeConstructorPage(cake: cake)),
    );
  }

  // «Qo'shish» — yangi tort «Торт» kategoriyasiga (shef_cakes_page.dart
  // dagi bilan bir xil oqim); qaytgach ro'yxat yangilanadi.
  Future<void> _addCake(int categoryId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(initialCategoryId: categoryId),
      ),
    );
    if (!mounted) return;
    await context
        .read<ProductProviderAdmin>()
        .initializeProducts(forceRefresh: true);
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
          '«Торты» bo\'limiga o\'tadi',
      hideTort: true,
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
        title: const Text('«Торты» bo\'limidan olib tashlash'),
        content: Text(
          '«${category.name}» «Торты» bo\'limidan olinib, yana «Тех карта»da '
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
        // Bosh menyudagi karta bilan bir xil nom.
        title: const Text(
          'Торты',
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
          // Kartalar soni kichik — ikkala provider'ni kuzatish arzon.
          Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
            builder: (context, cats, products, _) {
              if (!_linksLoaded) return const SizedBox.shrink();
              // Пф kategoriyalari «Тех карта» ro'yxatida bo'lmasligi mumkin.
              final pf = context.select<ShefProvider, List<PfStockRow>>(
                (p) => p.pfStock,
              );
              final byId = shefCategoriesById(cats.categories, pf);
              final counts = <int, int>{};
              // HAMMA tortlar (nomi «Торт» bo'lgan kategoriyalar mahsulotlari)
              // — bo'limga kirilishi bilan tepada, kategoriyalardan oldin.
              final cakes = <ProductModelAdmin>[];
              for (final p in products.products) {
                counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
                if (isTortCategory(byId[p.categoryId]?.name ?? '')) {
                  cakes.add(p);
                }
              }
              // Backend'da o'chirilgan (ro'yxatda yo'q) id'lar ko'rsatilmaydi.
              // «Торт» kategoriyalari ham chiqmaydi — ularning tortlari
              // allaqachon tepadagi gridda (karta takror bo'lardi).
              final linked = [
                for (final id in BiskvitLinks.ids)
                  if (byId[id] != null && !isTortCategory(byId[id]!.name))
                    byId[id]!,
              ];
              // Yangi tort qo'shish uchun — birinchi «Торт» kategoriyasi.
              CategoryProductAdmin? tortCategory;
              for (final c in byId.values) {
                if (isTortCategory(c.name)) {
                  tortCategory = c;
                  break;
                }
              }
              if (linked.isEmpty && cakes.isEmpty && tortCategory == null) {
                return _EmptyHint(onAdd: _addCategory);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cakes.isNotEmpty || tortCategory != null) ...[
                    // Sarlavha + «Qo'shish» (yangi tort «Торт»
                    // kategoriyasiga; kategoriya kartasi bu bo'limda yo'q).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Tortlar',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (tortCategory != null)
                            TextButton.icon(
                              onPressed: () => _addCake(tortCategory!.id),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.brown.shade700,
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Qo\'shish'),
                            ),
                        ],
                      ),
                    ),
                    if (cakes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                        child: Text(
                          'Hozircha tort yo\'q — «Qo\'shish» bilan qo\'shing',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: kCakeGridDelegate,
                      itemCount: cakes.length,
                      // Bir marta bosish — tortning o'z to'liq konstruktori;
                      // IKKI marta — tortning tex kartasi.
                      itemBuilder: (context, i) => CakeCard(
                        cake: cakes[i],
                        onTap: () => _openCakeConstructor(cakes[i]),
                        onDoubleTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TechCardEditorPage(
                              product: cakes[i],
                              canEditPrices: false,
                              showFillingColor: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (linked.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 2, 4, 8),
                      child: Text(
                        'Kategoriyalar',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    _categoryGrid(linked, counts),
                  ] else
                    _EmptyHint(onAdd: _addCategory),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Kategoriya kartalari: ustun soni ekran kengligidan (karta ≤ 220 px),
  // balandligi QAT'IY — tor ekranda kartalar kichrayib yopishib ketmaydi.
  Widget _categoryGrid(
      List<CategoryProductAdmin> linked, Map<int, int> counts) {
    return GridView(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 200,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final c in linked) ...[
                    _CategoryTile(
                      category: c,
                      count: counts[c.id] ?? 0,
                      onTap: () => _openCategory(c),
                      onLongPress: () => _removeCategory(c),
                    ),
                    // «Покрытие» — «Начинка»ning O'SHA mahsulotlari, tortni
                    // tashqaridan qoplagan krem sifatida (shef_home_ui.dart
                    // dagi karta bilan bir xil).
                    if (isNachinkaCategory(c.name))
                      _CategoryTile(
                        category: c,
                        count: counts[c.id] ?? 0,
                        title: 'Покрытие',
                        thumb: const CoatingSectionThumb(),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShefTechCardProductsPage(
                              categoryId: c.id,
                              categoryName: 'Покрытие',
                              showCoating: true,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
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
  final VoidCallback? onLongPress;
  // Berilsa kategoriya nomi/rasmi o'rniga shular («Покрытие» kartasi).
  final String? title;
  final Widget? thumb;

  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
    this.onLongPress,
    this.title,
    this.thumb,
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
                child: thumb != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox.expand(child: thumb),
                      )
                    : LayoutBuilder(
                        builder: (context, box) => CategoryThumb(
                          category: category,
                          size: box.maxHeight,
                          width: box.maxWidth,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                title ?? category.name,
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
