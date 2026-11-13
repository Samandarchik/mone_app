import '../../../core/services/mone_mode.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/local_db.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/search_fold.dart';
import '../widgets/admin_page.dart';
import '../../../core/widgets/media_image.dart';
import 'product_edit_screen.dart';
import 'recipe_edit_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Map<String, dynamic>? _menu;
  bool _loading = true;
  int? _selectedCategory;
  List<Map<String, dynamic>> _grouped = [];
  bool _editMode = false;
  StreamSubscription? _wssSub;
  // Menyu qidiruvi
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
    AppState().addListener(_onStateChanged);
    // Real time: menyu o'zgarsa (boshqa qurilmadan ham) qayta yuklanadi
    _wssSub = WssService().eventStream.listen((e) {
      if (e['event'] == 'menu:outdated') _load();
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    _searchCtrl.dispose();
    AppState().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() { if (mounted) setState(() {}); }

  /// Admin menyusi HAR DOIM serverdan yuklanadi.
  ///
  /// NEGA: ilgari kesh bo'sh bo'lmasa lokal bazadan o'qilardi, lokal kesh esa
  /// POS bilan bitta — POS menyuni `status='active'` bilan yangilab, nofaol
  /// mahsulotlarni kesh jadvalidan o'chirib yuborardi. Natijada admin menyuda
  /// nofaol mahsulot bazada bor bo'lsa ham ko'rinmasdi va uni qayta yoqib
  /// bo'lmasdi. Endi ro'yxat serverdan `include_inactive=1` bilan olinadi,
  /// kesh esa faqat internet bo'lmaganda zaxira sifatida ishlatiladi.
  Future<void> _load() async {
    final wasMone = MoneMode.enabled.value;
    MoneMode.refresh().then((v) {
      if (mounted && v != wasMone) setState(() {});
    });
    try {
      final menu = await ApiService().getMenu(force: true, includeInactive: true);
      await LocalDB().saveCategories(menu['categories'] as List<dynamic>? ?? []);
      await LocalDB().saveProducts(menu['products'] as List<dynamic>? ?? []);
      if (mounted) setState(() { _menu = menu; _buildGrouped(); _loading = false; });
    } catch (_) {
      // Oflayn zaxira — nofaol mahsulotlar bilan birga
      try {
        final cats = await LocalDB().getCategories(includeInactive: true);
        final prods = await LocalDB().getProducts(includeInactive: true);
        if (mounted) setState(() { _menu = {'categories': cats, 'products': prods}; _buildGrouped(); _loading = false; });
      } catch (_) { if (mounted) setState(() => _loading = false); }
    }
  }

  Future<void> _saveOrder() async {
    // grouped dan categories va products sort_order ni chiqarish
    final catOrders = <Map<String, dynamic>>[];
    final prodOrders = <Map<String, dynamic>>[];
    int catSort = 1;
    int prodSort = 1;
    int currentCatId = 0;

    for (final item in _grouped) {
      if (item['_type'] == 'category') {
        final c = item['data'] as Map<String, dynamic>;
        currentCatId = c['id'] as int;
        catOrders.add({'id': currentCatId, 'sort_order': catSort++});
        prodSort = 1;
      } else {
        final p = item['data'] as Map<String, dynamic>;
        prodOrders.add({'id': p['id'], 'sort_order': prodSort++, 'category_id': currentCatId});
      }
    }

    try {
      await ApiService().reorder(catOrders, prodOrders);
    } catch (e) {
      if (kDebugMode) debugPrint('Reorder error: $e');
    }
  }

  void _buildGrouped() {
    _grouped = [];
    for (final c in _categories) {
      _grouped.add({'_type': 'category', 'data': c});
      final prods = (_menu?['products'] as List<dynamic>? ?? [])
          .where((p) => p['category_id'] == c['id'])
          .toList()
        ..sort((a, b) => ((a['sort_order'] ?? 0) as int).compareTo((b['sort_order'] ?? 0) as int));
      for (final p in prods) {
        _grouped.add({'_type': 'product', 'data': p});
      }
    }
  }

  List<dynamic> get _categories => _menu?['categories'] as List<dynamic>? ?? [];
  List<dynamic> get _products {
    final all = _menu?['products'] as List<dynamic>? ?? [];
    final filtered = _selectedCategory == null ? all : all.where((p) => p['category_id'] == _selectedCategory).toList();
    filtered.sort((a, b) => ((a['sort_order'] ?? 0) as int).compareTo((b['sort_order'] ?? 0) as int));
    return filtered;
  }

  int? _getStock(int productId) => AppState().getStockCount(productId);

  Future<void> _addCategory() async {
    final result = await _showCategorySheet(title: 'Yangi kategoriya');
    if (result == null || result['action'] != 'save') return;
    final name = (result['name_uz'] as String).trim();
    if (name.isEmpty) return;
    try {
      final res = await ApiService().createCategory({
        'name_uz': name,
        'name_ru': (result['name_ru'] as String).trim(),
        'name_tr': (result['name_tr'] as String).trim(),
        'status': 'active',
      });
      final img = result['image'] as String?;
      if (img != null) {
        await ApiService().uploadCategoryImage(res['id'] as int, img);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _editCategory(Map<String, dynamic> cat) async {
    final result = await _showCategorySheet(
      title: 'Kategoriyani tahrirlash',
      initial: cat,
      allowDelete: true,
    );
    if (result == null) return;
    if (result['action'] == 'save') {
      try {
        await ApiService().updateCategory(cat['id'], {
          'name_uz': (result['name_uz'] as String).trim(),
          'name_ru': (result['name_ru'] as String).trim(),
          'name_tr': (result['name_tr'] as String).trim(),
        });
        final img = result['image'] as String?;
        if (img != null) {
          await ApiService().uploadCategoryImage(cat['id'], img);
        }
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Xato: $e'),
                backgroundColor: AppColors.danger),
          );
        }
      }
    } else if (result['action'] == 'delete') {
      // `result` await'dan keyin keladi — shu orada ekran yopilgan bo'lsa
      // eski `context` bilan dialog ochish xatoga olib keladi.
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("O'chirish"),
          content: Text(
              "${cat['name']?['uz'] ?? ''} kategoriyasini o'chirishni xohlaysizmi?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Yo'q")),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger),
              child: const Text("O'chirish"),
            ),
          ],
        ),
      );
      if (confirm == true) {
        try {
          await ApiService().deleteCategory(cat['id']);
          await _load();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Xato: $e'),
                  backgroundColor: AppColors.danger),
            );
          }
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _showCategorySheet({
    required String title,
    Map<String, dynamic>? initial,
    bool allowDelete = false,
  }) {
    final nameUz = TextEditingController(
        text: initial?['name']?['uz'] ?? initial?['name_uz'] ?? '');
    final nameRu = TextEditingController(
        text: initial?['name']?['ru'] ?? initial?['name_ru'] ?? '');
    final nameTr = TextEditingController(
        text: initial?['name']?['tr'] ?? initial?['name_tr'] ?? '');
    String? pickedImage;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.text),
                              ),
                            ),
                            Material(
                              color: AppColors.surfaceAlt,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                onTap: () => Navigator.pop(ctx),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.close_rounded,
                                      size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 4, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final path = await pickImagePath();
                                  if (path != null) {
                                    setS(() => pickedImage = path);
                                  }
                                },
                                child: Container(
                                  height: 120,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.md),
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: pickedImage != null
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: const [
                                            Icon(
                                                Icons
                                                    .check_circle_rounded,
                                                color: AppColors.success),
                                            SizedBox(width: 8),
                                            Text('Rasm tanlandi',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ],
                                        )
                                      : Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: const [
                                            Icon(
                                                Icons
                                                    .add_photo_alternate_rounded,
                                                size: 32,
                                                color:
                                                    AppColors.primary),
                                            SizedBox(height: 6),
                                            Text(
                                              'Rasm tanlash',
                                              style: TextStyle(
                                                  color:
                                                      AppColors.primary,
                                                  fontWeight:
                                                      FontWeight.w700),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: nameUz,
                                decoration: const InputDecoration(
                                  labelText: '🇺🇿  O\'zbekcha (asosiy)',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: nameRu,
                                decoration: const InputDecoration(
                                  labelText: '🇷🇺  Ruscha',
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: nameTr,
                                decoration: const InputDecoration(
                                  labelText: '🇹🇷  Turkcha',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  if (allowDelete)
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.pop(
                                            ctx,
                                            {'action': 'delete'}),
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: AppColors.danger),
                                        label: const Text(
                                          "O'chirish",
                                          style: TextStyle(
                                              color: AppColors.danger),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 14),
                                          side: const BorderSide(
                                              color: AppColors.danger),
                                        ),
                                      ),
                                    ),
                                  if (allowDelete)
                                    const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: FilledButton.icon(
                                      onPressed: () =>
                                          Navigator.pop(ctx, {
                                        'action': 'save',
                                        'name_uz': nameUz.text,
                                        'name_ru': nameRu.text,
                                        'name_tr': nameTr.text,
                                        'image': pickedImage,
                                      }),
                                      icon: const Icon(
                                          Icons.check_rounded,
                                          size: 18),
                                      label: Text(allowDelete
                                          ? 'Saqlash'
                                          : 'Yaratish'),
                                      style: FilledButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 14),
                                        backgroundColor:
                                            AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addProduct() {
    final catId = _selectedCategory ?? (_categories.isNotEmpty ? _categories.first['id'] as int : 0);
    final newProduct = <String, dynamic>{
      'id': 0,
      'name_uz': '', 'name_ru': '', 'name_tr': '',
      'description': {'uz': '', 'ru': '', 'tr': ''},
      'category_id': catId,
      'price': 0, 'old_price': null,
      'media': [], 'status': 'active',
      'is_recommended': false,
      'sort_order': _products.length + 1,
    };
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProductEditScreen(
        product: newProduct,
        categories: _categories,
        yandex: _menu?['yandex'] as Map<String, dynamic>?,
      ),
    )).then((_) => _load());
  }

  String _money(dynamic v) {
    if (v == null || v == 0) return '0';
    final n = v is int ? v : (v as num).toInt();
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}${buf.toString()}';
  }

  String _catName(int catId) {
    for (final c in _categories) { if (c['id'] == catId) return c['name']?['uz'] ?? ''; }
    return '';
  }

  String _getImg(Map<String, dynamic> p) {
    final media = p['media'];
    if (media is List && media.isNotEmpty) return media[0]['url'] ?? '';
    return '';
  }

  void _openRecipe(Map<String, dynamic> p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEditScreen(
          productId: p['id'] as int,
          productName: p['name']?['uz'] ?? '',
        ),
      ),
    );
  }

  void _openEdit(Map<String, dynamic> p) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductEditScreen(
      product: p,
      categories: _categories,
      stock: _getStock(p['id']),
      yandex: _menu?['yandex'] as Map<String, dynamic>?,
    )));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final inCategory = _selectedCategory != null;
    final allProducts = _menu?['products'] as List<dynamic>? ?? [];

    // Sistem «orqaga» si (Android tugmasi, iOS chetdan surish) ISHLASIN:
    // avval qidiruvni, keyin kategoriyani yopadi va faqat shundan keyin
    // ilovadan chiqaradi.
    return PopScope(
      canPop: !inCategory && _search.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_search.isNotEmpty) {
          setState(_clearSearch);
        } else if (inCategory) {
          _exitCategory();
        }
      },
      child: AdminPage(
        helpKey: 'products',
        title: inCategory ? _catName(_selectedCategory!) : 'Menyu',
        subtitle: inCategory
            ? '${_products.length} ta mahsulot'
            : '${_categories.length} kategoriya · ${allProducts.length} mahsulot',
        onBack: inCategory ? _exitCategory : null,
        loading: _loading,
        onRefresh: _load,
        // Tartiblash rejimida qidiruv ishlamaydi — filtrlangan ro'yxatni
        // surish tartibni buzadi.
        searchController: _searchCtrl,
        onSearchChanged: _editMode
            ? null
            : (v) => setState(() => _search = v.trim().toLowerCase()),
        searchHint: inCategory
            ? 'Shu kategoriyadan qidirish…'
            : 'Mahsulot yoki kategoriya…',
        actions: [
          AdminIconAction(
            icon: _editMode ? Icons.check_rounded : Icons.swap_vert_rounded,
            tooltip: _editMode ? 'Tartiblashni tugatish' : 'Tartibni o‘zgartirish',
            color: _editMode ? AppColors.success : null,
            onPressed: () => setState(() {
              _editMode = !_editMode;
              if (_editMode) _clearSearch();
            }),
          ),
        ],
        // Mone rejimida katalog Mone'dan keladi — kassada yaratilmaydi.
        primaryAction: MoneMode.enabled.value
            ? null
            : AdminAction(
                label: inCategory ? 'Mahsulot' : 'Kategoriya',
                icon: Icons.add_rounded,
                onPressed: inCategory ? _addProduct : _addCategory,
                color: AppColors.warning,
              ),
        child: _search.isNotEmpty
            ? _buildSearchResults()
            : inCategory
                // O'ngga surish — kategoriyadan chiqish. Telefonda tepa-chap
                // burchakka tegmasdan qaytish yo'li.
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) > 250) _exitCategory();
                    },
                    child: _buildProductsList(),
                  )
                : _buildCategoriesList(),
      ),
    );
  }

  /// Kategoriyadan chiqish — ro'yxatga qaytish.
  void _exitCategory() {
    if (_selectedCategory == null) return;
    setState(() {
      _selectedCategory = null;
      _editMode = false;
    });
  }

  // ============================================================
  // Qidiruv
  // ============================================================

  void _clearSearch() {
    _searchCtrl.clear();
    _search = '';
  }

  bool _nameMatches(dynamic item) {
    final names = item['name'] as Map<String, dynamic>? ?? {};
    // Alifbodan qat'i nazar qidirish: «choy» ↔ «чой» (searchFold).
    final q = searchFold(_search);
    if (q.isNotEmpty &&
        names.values
            .any((n) => n is String && searchFold(n).contains(q))) {
      return true;
    }
    // Raqamli qidiruv — narx bo'yicha ham ("80" → 80 000, probel bilan ham)
    final digits = _search.replaceAll(' ', '');
    if (digits.isEmpty || int.tryParse(digits) == null) return false;
    final price = item['price'];
    return price is num && price.toInt().toString().startsWith(digits);
  }

  /// Kategoriya ichida bo'lsak — faqat shu kategoriyadan; aks holda
  /// butun menyu bo'yicha (mos kategoriyalar ham ko'rsatiladi)
  Widget _buildSearchResults() {
    final inCategory = _selectedCategory != null;
    final allProducts = _menu?['products'] as List<dynamic>? ?? [];
    final products = (inCategory ? _products : allProducts)
        .where(_nameMatches)
        .toList();
    final cats = inCategory
        ? const <dynamic>[]
        : _categories.where(_nameMatches).toList();

    if (products.isEmpty && cats.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Topilmadi',
        subtitle: 'Boshqa so\'z bilan urinib ko\'ring',
      );
    }

    return KMaxWidth(
      child: ListView(
        padding: _listPadding,
        children: [
          if (cats.isNotEmpty) ...[
            _searchSectionLabel('Kategoriyalar', cats.length),
            ...cats.map((c) {
              final prodCount = allProducts
                  .where((p) => p['category_id'] == c['id'])
                  .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: KCard(
                  onTap: () => setState(() {
                    _selectedCategory = c['id'];
                    _clearSearch();
                  }),
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  radius: AppRadius.md,
                  child: Row(
                    children: [
                      IconAvatar(
                        icon: Icons.folder_rounded,
                        color: AppColors.primary,
                        size: context.s(34.0),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c['name']?['uz'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: context.s(15.0),
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                            Text(
                              '$prodCount ta mahsulot',
                              style: TextStyle(
                                  color: AppColors.textFaint,
                                  fontSize: context.s(11.5)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textGhost),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (products.isNotEmpty) ...[
            _searchSectionLabel('Mahsulotlar', products.length),
            ...products.map((p) => _buildProductTile(
                  p,
                  0,
                  // Butun menyu bo'yicha qidirganda qaysi kategoriyada
                  // ekani ko'rinib tursin
                  categoryLabel: inCategory
                      ? null
                      : _catName(p['category_id'] as int? ?? 0),
                )),
          ],
        ],
      ),
    );
  }

  Widget _searchSectionLabel(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        child: Row(
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count ta',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textFaint),
            ),
          ],
        ),
      );

  /// Ro'yxatlar uchun umumiy bo'shliq: pastda FAB tugmasi turadi, oxirgi
  /// element uning ostida qolib ketmasin. Yon tomondagi bo'shliqni
  /// [AdminPage] o'zi beradi.
  EdgeInsets get _listPadding => const EdgeInsets.fromLTRB(0, 14, 0, 96);

  Widget _buildCategoriesList() {
    final cats = List<Map<String, dynamic>>.from(_categories);
    if (cats.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Kategoriya yo\'q',
        subtitle: 'Pastdagi tugma orqali birinchi kategoriyani qo\'shing',
      );
    }
    if (!_editMode) {
      return KMaxWidth(
        child: ListView.builder(
          padding: _listPadding,
          itemCount: cats.length,
          itemBuilder: (ctx, i) => _categoryTile(cats[i], i),
        ),
      );
    }
    return KMaxWidth(
      child: ReorderableListView.builder(
        padding: _listPadding,
        itemCount: cats.length,
        onReorder: (old, newIdx) {
          setState(() {
            if (newIdx > old) newIdx--;
            final item = cats.removeAt(old);
            cats.insert(newIdx, item);
            _menu!['categories'] = cats;
            _buildGrouped();
          });
          _saveOrder();
        },
        itemBuilder: (ctx, i) => _categoryTile(cats[i], i),
      ),
    );
  }

  /// Kategoriya qatori — ixcham (ilgari `ListTile` 72pt egallardi).
  Widget _categoryTile(Map<String, dynamic> c, int i) {
    final prodCount = (_menu?['products'] as List<dynamic>? ?? [])
        .where((p) => p['category_id'] == c['id'])
        .length;
    return Padding(
      key: ValueKey('cat-${c['id']}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: KCard(
        onTap: () => setState(() => _selectedCategory = c['id']),
        padding: EdgeInsets.fromLTRB(_editMode ? 4 : 10, 9, 6, 9),
        radius: AppRadius.md,
        child: Row(
          children: [
            if (_editMode)
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 20, color: AppColors.textFaint),
                ),
              ),
            IconAvatar(
              icon: Icons.folder_rounded,
              color: AppColors.primary,
              size: context.s(34.0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c['name']?['uz'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.s(15.0),
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    '$prodCount ta mahsulot',
                    style: TextStyle(
                        color: AppColors.textFaint, fontSize: context.s(11.5)),
                  ),
                ],
              ),
            ),
            if (!_editMode)
              IconButton(
                icon: const Icon(Icons.edit_rounded,
                    size: 17, color: AppColors.textFaint),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: () => _editCategory(c),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textGhost),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    if (_products.isEmpty) {
      return const EmptyState(
        icon: Icons.fastfood_rounded,
        title: 'Mahsulot yo\'q',
        subtitle: 'Bu kategoriyaga hali mahsulot qo\'shilmagan',
      );
    }
    if (!_editMode) {
      return KMaxWidth(
        child: ListView.builder(
          padding: _listPadding,
          itemCount: _products.length,
          itemBuilder: (ctx, i) => _buildProductTile(_products[i], i),
        ),
      );
    }
    return KMaxWidth(
      child: ReorderableListView.builder(
        padding: _listPadding,
        itemCount: _products.length,
        onReorder: (old, newIdx) {
          setState(() {
            if (newIdx > old) newIdx--;
            final prods = List<dynamic>.from(_products);
            final item = prods.removeAt(old);
            prods.insert(newIdx, item);
            final allProds = _menu!['products'] as List<dynamic>;
            for (int i = 0; i < prods.length; i++) {
              final idx = allProds.indexWhere((p) => p['id'] == prods[i]['id']);
              if (idx >= 0) allProds[idx]['sort_order'] = i + 1;
            }
            _buildGrouped();
          });
          _saveOrder();
        },
        itemBuilder: (ctx, i) => _buildProductTile(_products[i], i),
      ),
    );
  }

  /// Mahsulot qatori — IXCHAM.
  ///
  /// Ilgari bu `Card` + `ListTile` edi: `ListTile` o'zining 16pt yon
  /// bo'shlig'i, 16pt sarlavha oralig'i va 72pt minimal balandligini
  /// qo'shar, ustiga qo'lda 18+4pt bo'sh joy solingan edi — rasm bilan
  /// nom orasida deyarli 40pt bo'shliq hosil bo'lar, bitta qator ~90pt
  /// joy egallardi. Telefon ekraniga atigi 7-8 ta mahsulot sig'ardi.
  /// Endi qator qo'lda yig'ilgan: bo'shliqlar aniq, balandlik ~62pt.
  Widget _buildProductTile(dynamic p, int index, {String? categoryLabel}) {
    final stock = _getStock(p['id']);
    final inactive = p['status'] == 'inactive';
    final img = _getImg(p);
    final thumb = context.s(42.0);
    final type = p['product_type'] ?? 'cooked';
    final showRecipe = !_editMode && (type == 'cooked' || type == 'made');

    return Opacity(
      key: ValueKey('prod-${p['id']}'),
      opacity: inactive ? 0.45 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: KCard(
          onTap: () => _openEdit(p),
          padding: EdgeInsets.fromLTRB(_editMode ? 4 : 8, 8, 8, 8),
          radius: AppRadius.md,
          child: Row(
            children: [
              if (_editMode)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 20, color: AppColors.textFaint),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: thumb,
                  height: thumb,
                  color: AppColors.surfaceAlt,
                  child: img.isNotEmpty
                      ? MediaImage(
                          path: img,
                          width: thumb,
                          height: thumb,
                          placeholder: Icon(Icons.fastfood_rounded,
                              color: AppColors.textGhost, size: thumb * 0.45))
                      : Icon(Icons.fastfood_rounded,
                          color: AppColors.textGhost, size: thumb * 0.45),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p['name']?['uz'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: context.s(14.0),
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (p['is_recommended'] == true) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.accent),
                        ],
                        if (inactive) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                              label: 'Nofaol',
                              color: AppColors.danger,
                              fontSize: 9),
                        ],
                        // Yandex Eda menyusiga chiqarilgan mahsulot —
                        // ro'yxatdan ko'rinib tursin (kartochkani ochmasdan).
                        if (p['yandex_enabled'] == true) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                              label: 'Yandex',
                              color: kYandexColor,
                              fontSize: 9),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      categoryLabel != null && categoryLabel.isNotEmpty
                          ? categoryLabel
                          : (p['description']?['uz'] ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.s(11.0),
                        color: categoryLabel != null && categoryLabel.isNotEmpty
                            ? AppColors.primary
                            : AppColors.textFaint,
                        fontWeight: categoryLabel != null &&
                                categoryLabel.isNotEmpty
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Qoldiq — chapga tekislangan ustunda narx bilan birga
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _money(p['price']),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: context.s(13.0),
                      color: AppColors.text,
                    ),
                  ),
                  // Yandexda AYNAN turadigan narx (server hisoblab beradi:
                  // POS narxi + ustama, yaxlitlangan).
                  if (p['yandex_enabled'] == true &&
                      (p['yandex_final_price'] ?? 0) > 0) ...[
                    const SizedBox(height: 1),
                    Text(
                      'Y: ${_money(p['yandex_final_price'])}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: context.s(10.0),
                        color: kYandexColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  _stockChip(stock),
                ],
              ),
              if (showRecipe)
                IconButton(
                  tooltip: 'Retsept',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: const Icon(Icons.menu_book_rounded,
                      size: 18, color: AppColors.textFaint),
                  onPressed: () => _openRecipe(p),
                ),
              if (_editMode)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textGhost),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockChip(int? stock) {
    if (stock == null) {
      return const Text('∞',
          style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w700,
              color: AppColors.textGhost));
    }
    final c = stock == 0
        ? AppColors.danger
        : stock < 10
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$stock',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}
