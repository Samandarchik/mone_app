// shef/ui/shef_tech_card_page.dart — shef uchun тех карта ekranlari:
// ShefTechCardCategoriesPage (unga belgilangan kategoriyalar — backend
// GET /api/categories ni shefning category_list bo'yicha O'ZI filtrlaydi)
// va ShefTechCardProductsPage (kategoriya mahsulotlari + qidiruv). Mahsulot
// bosilsa TechCardEditorPage faqat-o'qish narx rejimida ochiladi
// (canEditPrices: false): shef retseptni tahrirlaydi, masalliq narxi /
// «Сумма» / tannarx / sotuv narxini KO'RADI, lekin narx/foyda/nakladnoyni
// o'zgartira olmaydi.
// Mahsulot o'chirish/tartiblash/PDF bu yerda YO'Q; qo'shish — faqat Biskvit
// bo'limidan ochilganda (canAddProducts). Biskvit bo'limidagi «Бисквит»
// kategoriyasida (showBaking) har retsept ostida pishirish vaqti/harorati
// chipi — bosilsa tahrirlanadi (tech_card.bake_time_min / bake_temp_c).
// «Biskvit» bo'limiga bog'langan kategoriyalar (BiskvitLinks) bu ro'yxatda
// ko'rinmaydi — ular bosh menyudagi «Biskvit» bo'limida (biskvit_page.dart).
// Shef bosh ekraniga «+» bilan qo'shilganlar (ShefHomeLinks) ham shunday.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/admin_add_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/biskvit_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';

// Shef ekranlarining umumiy ranglari (shef_home_ui / pf_stock_page bilan bir xil).
const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

// Mahsulotda тех карта tarkibi bormi — «i» belgisini shartli ko'rsatish uchun
// (admin ro'yxatidagi naqsh: admin_product_ui.dart → _hasTechCard).
bool _hasTechCard(ProductModelAdmin product) {
  final tc = product.techCard;
  if (tc == null) return false;
  return tc.bases.any((b) => b.ingredients.isNotEmpty) ||
      tc.consumables.isNotEmpty;
}

// ---------------------------------------------------------------------------
// 1-ekran: kategoriyalar
// ---------------------------------------------------------------------------

// Shefga belgilangan kategoriyalar ro'yxati. Backend GET /api/categories ni
// shefning category_list bo'yicha filtrlab qaytaradi — bu yerda qo'shimcha
// filtr YO'Q (bo'sh ro'yxat = shefga kategoriya belgilanmagan).
class ShefTechCardCategoriesPage extends StatefulWidget {
  const ShefTechCardCategoriesPage({super.key});

  @override
  State<ShefTechCardCategoriesPage> createState() =>
      _ShefTechCardCategoriesPageState();
}

class _ShefTechCardCategoriesPageState
    extends State<ShefTechCardCategoriesPage> {
  @override
  void initState() {
    super.initState();
    // Biskvit bo'limi bog'lanishlari — yashiriladigan kategoriyalar uchun.
    Future.wait([BiskvitLinks.load(), ShefHomeLinks.load()]).then((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Mahsulotlar YAGONA manbadan bir marta yuklanadi (admin naqshi):
      // keyin xotirada qoladi, tex karta saqlanganda ham qayta GET yo'q.
      context.read<ProductProviderAdmin>().initializeProducts();
    });
  }

  Future<void> _refresh() async {
    final categories = context.read<CategoryProviderAdmin>();
    final products = context.read<ProductProviderAdmin>();
    await Future.wait([
      categories.getCategories(),
      products.initializeProducts(forceRefresh: true),
    ]);
  }

  void _openCategory(CategoryProductAdmin category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShefTechCardProductsPage(
          categoryId: category.id,
          categoryName: category.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Тех карта',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<CategoryProviderAdmin>(
        builder: (context, provider, child) {
          // Har kategoriyadagi mahsulot soni — mahsulotlar ro'yxati bo'ylab
          // BITTA o'tishda hisoblanadi (tile ichida qidirish O(N×M) bo'lardi).
          final counts = <int, int>{};
          for (final p in context.watch<ProductProviderAdmin>().products) {
            counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
          }

          if (provider.isLoading && provider.categories.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.error != null && provider.categories.isEmpty) {
            return _ErrorView(
              message: provider.error!.replaceFirst('Exception: ', ''),
              onRetry: () => provider.getCategories(),
            );
          }

          // «Biskvit» bo'limiga bog'langan kategoriyalar (biskvit_page.dart)
          // va shef bosh ekraniga qo'shilganlar (ShefHomeLinks) endi o'sha
          // yerda — bu ro'yxatda ko'rinmaydi.
          final hidden = {
            ...BiskvitLinks.linkedIds,
            ...ShefHomeLinks.linkedIds,
          };
          final categories =
              provider.categories.where((c) => !hidden.contains(c.id)).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: categories.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 140),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            Icon(Icons.menu_book_outlined,
                                size: 48, color: Colors.black26),
                            SizedBox(height: 12),
                            Text(
                              'Sizga kategoriya belgilanmagan — '
                              'administratorga murojaat qiling',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _CategoryCard(
                        category: category,
                        productCount: counts[category.id] ?? 0,
                        onTap: () => _openCategory(category),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

// Kategoriya kartasi: rasm + nom + mahsulot soni.
class _CategoryCard extends StatelessWidget {
  final CategoryProductAdmin category;
  final int productCount;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.productCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final url = category.imageUrl;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (url != null && url.isNotEmpty)
                    ? AppNetworkImage(
                        imageUrl: '${AppUrls.baseUrl}$url',
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorWidget: (context) =>
                            const Icon(Icons.image_not_supported),
                      )
                    : Container(
                        width: 52,
                        height: 52,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.category_outlined,
                            color: Colors.black38),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$productCount ta mahsulot',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2-ekran: kategoriyadagi mahsulotlar
// ---------------------------------------------------------------------------

// Bitta kategoriyaning mahsulotlari + nom bo'yicha qidiruv. Mahsulot bosilsa
// тех карта muharriri narxsiz rejimda ochiladi. Ro'yxat ProductProviderAdmin
// (YAGONA manba) dan olinadi va lokal filtrlanadi — provider'ning umumiy
// filteredProducts holatiga tegilmaydi.
class ShefTechCardProductsPage extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  // true — pastda «Qo'shish» (kategoriya tanlangan, «пф» yoqilgan forma).
  // Faqat Biskvit bo'limidan ochilganda (biskvit_page.dart).
  final bool canAddProducts;
  // true — har retsept yonida pishirish vaqti/harorati (bosilsa tahrir).
  // Faqat Biskvit bo'limidagi «Бисквит» kategoriyasi (isBiskvitCategory).
  final bool showBaking;
  // true — ro'yxat tepasida 3D tort va «Tort konstruktori» tugmasi.
  // Faqat shef bosh ekranidagi «П/Ф Бисквит» kartasidan (shef_home_ui.dart).
  final bool showCakeConstructor;

  const ShefTechCardProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.canAddProducts = false,
    this.showBaking = false,
    this.showCakeConstructor = false,
  });

  @override
  State<ShefTechCardProductsPage> createState() =>
      _ShefTechCardProductsPageState();
}

class _ShefTechCardProductsPageState extends State<ShefTechCardProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // «П/Ф Бисквит»: 3D'da ko'rsatilayotgan biskvit (null — birinchisi).
  int? _selectedId;
  // «П/Ф Бисквит»: qidiruv qatori faqat lupa bosilganda (AppBar'da) chiqadi.
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Bo'sh bo'lsa bir marta yuklaymiz (allaqachon yuklangan bo'lsa — jim).
      context.read<ProductProviderAdmin>().initializeProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      context.read<ProductProviderAdmin>().initializeProducts(
            forceRefresh: true,
          );

  // Тех карта muharriri — NARXSIZ rejim: shef retseptni tahrirlaydi, narx
  // maydonlari faqat o'qiladi (backend ham shef so'rovidan faqat tech_card ni
  // oladi). Saqlangach provider o'zini xotirada yangilaydi — qayta GET yo'q.
  void _openTechCard(ProductModelAdmin product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(
          product: product,
          canEditPrices: false,
          // «П/Ф Бисквит»: tex kartada «Biskvit fotosi» bo'limi.
          showBiscuitPhoto: widget.showCakeConstructor,
        ),
      ),
    );
  }

  // Pishirish vaqti/haroratini tahrirlash → tex kartada saqlash (shef
  // so'rovidan backend faqat tech_card ni oladi — boshqa maydon tegilmaydi).
  Future<void> _editBaking(ProductModelAdmin product) async {
    final card = product.techCard ?? const TechCard();
    final res = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _BakingDialog(
        title: product.name,
        timeMin: card.bakeTimeMin,
        tempC: card.bakeTempC,
      ),
    );
    if (res == null || !mounted) return;
    final (time, temp) = res;
    if (time == card.bakeTimeMin && temp == card.bakeTempC) return;

    final provider = context.read<ProductProviderAdmin>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.updateProduct(
      product.copyWith(
        techCard: card.copyWith(bakeTimeMin: time, bakeTempC: temp),
      ),
    );
    final raw = provider.error ?? '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${product.name}: pishirish rejimi saqlandi'
              : (raw.isEmpty ? 'Saqlashda xatolik' : raw)
                  .replaceFirst('Exception: ', ''),
        ),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
  }

  Future<void> _addProduct() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(
          initialCategoryId: widget.categoryId,
          initialSemiFinished: true,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final fab = widget.canAddProducts
        ? FloatingActionButton.extended(
            onPressed: _addProduct,
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Qo\'shish'),
          )
        : null;
    if (widget.showCakeConstructor) {
      return Scaffold(
        backgroundColor: _bgColor,
        floatingActionButton: fab,
        body: SafeArea(
          bottom: false,
          child: Consumer<ProductProviderAdmin>(
            builder: (context, provider, _) => _biscuitPage(provider),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _bgColor,
      floatingActionButton: fab,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: Text(
          widget.categoryName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<ProductProviderAdmin>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.products.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.error != null && provider.products.isEmpty) {
            return _ErrorView(
              message: provider.error!.replaceFirst('Exception: ', ''),
              onRetry: () => provider.initializeProducts(forceRefresh: true),
            );
          }

          final all = provider.products
              .where((p) => p.categoryId == widget.categoryId)
              .toList();
          final query = _searchQuery.trim().toLowerCase();
          final rows = query.isEmpty
              ? all
              : all.where((p) => p.name.toLowerCase().contains(query)).toList();

          return Column(
            children: [
              if (all.isNotEmpty) _searchField(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 140),
                            Center(
                              child: Text(
                                all.isEmpty
                                    ? 'Bu kategoriyada mahsulot yo\'q'
                                    : 'Topilmadi',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          // Pastki joy — FAB oxirgi qatorni yopmasin.
                          padding: EdgeInsets.fromLTRB(
                              8, 4, 8, widget.canAddProducts ? 88 : 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) => _ProductTile(
                            product: rows[index],
                            onTap: () => _openTechCard(rows[index]),
                            onEditBaking: widget.showBaking
                                ? () => _editBaking(rows[index])
                                : null,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Tanlangan biskvit (qidiruvdan qat'i nazar; yo'q bo'lsa — birinchisi).
  // Har build'da provider'dagi YANGI mahsulotdan olinadi — тех картага
  // balandlik/o'lcham qo'shilsa 3D darhol o'zgaradi.
  ProductModelAdmin? _selectedOf(List<ProductModelAdmin> all) {
    if (all.isEmpty) return null;
    for (final p in all) {
      if (p.id == _selectedId) return p;
    }
    return all.first;
  }

  // «П/Ф Бисквит» sahifasi (sarlavhasiz): bitta CustomScrollView —
  //  1) yuqori panel (orqaga + lupa) — sahifa bilan birga surilib ketadi;
  //  2) 3D biskvit — PINNED: grid pastga surilganda ekranning eng tepasiga
  //     chiqib qotadi, yana boshiga qaytilganda o'z joyiga tushadi;
  //  3) biskvitlar 2 ustunli grid.
  // Karta: bir marta bosish — 3D'da ko'rsatish, ikki marta — тех карта.
  Widget _biscuitPage(ProductProviderAdmin provider) {
    final loading = provider.isLoading && provider.products.isEmpty;
    final error = (provider.error != null && provider.products.isEmpty)
        ? provider.error!.replaceFirst('Exception: ', '')
        : null;
    final all = provider.products
        .where((p) => p.categoryId == widget.categoryId)
        .toList();
    final query = _searchQuery.trim().toLowerCase();
    final rows = query.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(query)).toList();
    final selected = _selectedOf(all);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            primary: false,
            backgroundColor: _bgColor,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            title: _searchOpen ? _compactSearch() : null,
            actions: [
              IconButton(
                tooltip: _searchOpen ? 'Yopish' : 'Qidirish',
                icon: Icon(_searchOpen ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                }),
              ),
            ],
          ),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorView(
                message: error,
                onRetry: () => provider.initializeProducts(forceRefresh: true),
              ),
            )
          else ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedBoxDelegate(
                extent: _biscuitViewH + 12,
                child: Container(
                  color: _bgColor,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Biscuit3DView(
                    height: _biscuitViewH,
                    dims: BiscuitDims.fromTechCard(selected?.techCard),
                    palette: selected == null
                        ? BiscuitPalette.classic
                        : BiscuitPalette.detect(
                            selected.name, selected.techCard),
                    // Tex kartaga biskvit fotosi qo'shilgan bo'lsa — yon
                    // tomoni shu fotodan (ichidagi rezavor/mevalar bilan).
                    photo: BiscuitPhoto.fromTechCard(selected?.techCard),
                  ),
                ),
              ),
            ),
            if (rows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(
                    all.isEmpty ? 'Bu kategoriyada mahsulot yo\'q' : 'Topilmadi',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              )
            else
              SliverPadding(
                // Pastki joy — FAB oxirgi qatorni yopmasin.
                padding: EdgeInsets.fromLTRB(
                    12, 4, 12, widget.canAddProducts ? 88 : 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: widget.showBaking ? 262 : 228,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: rows.length,
                    (context, index) {
                      final p = rows[index];
                      return _ProductGridCard(
                        product: p,
                        selected: p.id == selected?.id,
                        onTap: () => setState(() => _selectedId = p.id),
                        onDoubleTap: () => _openTechCard(p),
                        onEditBaking:
                            widget.showBaking ? () => _editBaking(p) : null,
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // AppBar'dagi ixcham qidiruv qatori (lupa bosilganda).
  Widget _compactSearch() {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Qidirish...',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Mahsulot qidirish...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, color: Colors.grey),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// «Бисквит» kategoriyasimi (nomi bo'yicha, katta-kichik harf farqsiz) —
// pishirish vaqti/harorati faqat shu kategoriya retseptlarida chiqadi
// (Начинка, Крем, Украшения kabi boshqa kategoriyalarda kerak emas).
bool isBiskvitCategory(String name) {
  final n = name.toLowerCase();
  return n.contains('бисквит') || n.contains('biskvit');
}

// Mahsulot qatori: rasm + nom (+ ПФ belgisi) + тех карта bor/yo'q belgisi.
// [onEditBaking] berilsa (faqat «Бисквит») ostida pishirish rejimi chipi.
class _ProductTile extends StatelessWidget {
  final ProductModelAdmin product;
  final VoidCallback onTap;
  final VoidCallback? onEditBaking;

  const _ProductTile({
    required this.product,
    required this.onTap,
    this.onEditBaking,
  });

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    final hasCard = _hasTechCard(product);
    return ListTile(
      onTap: onTap,
      leading: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? AppNetworkImage(
                imageUrl: '${AppUrls.baseUrl}$url',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorWidget: (context) => const Icon(Icons.image_not_supported),
              )
            : Container(
                width: 50,
                height: 50,
                color: Colors.grey.shade300,
                child: const Icon(Icons.image_not_supported),
              ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              '${product.name} (${product.type})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          // Полуфабрикат belgisi (admin ro'yxatidagi kabi).
          if (product.isSemiFinished)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                border: Border.all(color: Colors.purple.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'ПФ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasCard ? 'Тех карта bor' : 'Тех карта to\'ldirilmagan',
            style: TextStyle(
              fontSize: 12,
              color: hasCard ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
          if (onEditBaking != null) ...[
            const SizedBox(height: 6),
            _BakingChip(card: product.techCard, onTap: onEditBaking!),
          ],
        ],
      ),
      // «i» — tarkibi bor mahsulotda (admin ro'yxatidagi naqsh).
      trailing: hasCard
          ? const Icon(Icons.info_outline, color: _accentColor)
          : const Icon(Icons.chevron_right, color: Colors.black38),
    );
  }
}

// «П/Ф Бисквит»dagi 3D biskvit balandligi.
const double _biscuitViewH = 210;

// Qat'iy balandlikdagi pinned sarlavha (SliverPersistentHeader uchun).
class _PinnedBoxDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;

  _PinnedBoxDelegate({required this.extent, required this.child});

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      child;

  // Tanlangan biskvit / тех карта o'zgarsa qayta chizilsin.
  @override
  bool shouldRebuild(_PinnedBoxDelegate old) => true;
}

// Grid kartasi («П/Ф Бисквит»): tepada rasm, ostida nom (+ ПФ belgisi),
// тех карта holati va (berilsa) pishirish rejimi chipi. [selected] — hozir
// 3D'da ko'rsatilayotgani (ramka ajralib turadi).
class _ProductGridCard extends StatelessWidget {
  final ProductModelAdmin product;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback? onEditBaking;

  const _ProductGridCard({
    required this.product,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.onEditBaking,
  });

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    final hasCard = _hasTechCard(product);
    // Rasm yuklanmagan (yoki yuklanmay qolgan) biskvit — kulrang o'rniga
    // uning O'Z rasmi: o'lchami va turi (shokoladli, qizil baxmal, ...)
    // тех картадан chiziladi.
    final placeholder = BiscuitThumb(
      dims: BiscuitDims.fromTechCard(product.techCard),
      palette: BiscuitPalette.detect(product.name, product.techCard),
      photo: BiscuitPhoto.fromTechCard(product.techCard),
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: selected
                ? Border.all(color: _accentColor, width: 2)
                : Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, box) => (url != null && url.isNotEmpty)
                        ? AppNetworkImage(
                            imageUrl: '${AppUrls.baseUrl}$url',
                            width: box.maxWidth,
                            height: box.maxHeight,
                            fit: BoxFit.cover,
                            placeholder: (_) => placeholder,
                            errorWidget: (_) => placeholder,
                          )
                        : SizedBox.expand(child: placeholder),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (product.isSemiFinished)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        border: Border.all(color: Colors.purple.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ПФ',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hasCard ? 'Тех карта bor' : 'Тех карта to\'ldirilmagan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: hasCard ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
              if (onEditBaking != null) ...[
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _BakingChip(card: product.techCard, onTap: onEditBaking!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Pishirish rejimi chipi: «⏱ 25 daq · 🌡 180 °C». Kiritilmagan bo'lsa —
// «Pishirish rejimini kiriting». Bosilsa tahrir dialogi.
class _BakingChip extends StatelessWidget {
  final TechCard? card;
  final VoidCallback onTap;

  const _BakingChip({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final time = card?.bakeTimeMin ?? 0;
    final temp = card?.bakeTempC ?? 0;
    final empty = time <= 0 && temp <= 0;
    final color = Colors.deepOrange.shade700;
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: empty ? Colors.grey.shade600 : color,
    );
    return Material(
      color: empty ? Colors.grey.shade100 : Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: empty ? Colors.grey.shade300 : Colors.orange.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: empty
                ? [
                    Icon(Icons.local_fire_department_outlined,
                        size: 15, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('Pishirish rejimini kiriting', style: style),
                  ]
                : [
                    Icon(Icons.timer_outlined, size: 15, color: color),
                    const SizedBox(width: 3),
                    Text(time > 0 ? '$time daq' : '—', style: style),
                    const SizedBox(width: 10),
                    Icon(Icons.thermostat, size: 15, color: color),
                    const SizedBox(width: 2),
                    Text(temp > 0 ? '$temp °C' : '—', style: style),
                    const SizedBox(width: 6),
                    Icon(Icons.edit, size: 13, color: color),
                  ],
          ),
        ),
      ),
    );
  }
}

// Pishirish vaqti (daqiqa) va harorati (°C) — BUTUN son. Natija:
// (vaqt, harorat) yoki null (bekor). Bo'sh maydon = 0 (kiritilmagan).
class _BakingDialog extends StatefulWidget {
  final String title;
  final int timeMin;
  final int tempC;

  const _BakingDialog({
    required this.title,
    required this.timeMin,
    required this.tempC,
  });

  @override
  State<_BakingDialog> createState() => _BakingDialogState();
}

class _BakingDialogState extends State<_BakingDialog> {
  late final TextEditingController _timeCtrl = TextEditingController(
    text: widget.timeMin > 0 ? '${widget.timeMin}' : '',
  );
  late final TextEditingController _tempCtrl = TextEditingController(
    text: widget.tempC > 0 ? '${widget.tempC}' : '',
  );

  @override
  void dispose() {
    _timeCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
        context,
        (
          int.tryParse(_timeCtrl.text.trim()) ?? 0,
          int.tryParse(_tempCtrl.text.trim()) ?? 0,
        ),
      );

  InputDecoration _decoration(String label, String suffix, IconData icon) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _timeCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textInputAction: TextInputAction.next,
            decoration: _decoration(
                'Pishirish vaqti', 'daq', Icons.timer_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tempCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: _decoration('Harorat', '°C', Icons.thermostat),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

// Ikkala ekran uchun umumiy xato ko'rinishi.
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }
}
