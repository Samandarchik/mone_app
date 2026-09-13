// shef/ui/shef_tech_card_page.dart — shef uchun тех карта ekranlari:
// ShefTechCardCategoriesPage (unga belgilangan kategoriyalar — backend
// GET /api/categories ni shefning category_list bo'yicha O'ZI filtrlaydi)
// va ShefTechCardProductsPage (kategoriya mahsulotlari + qidiruv). Mahsulot
// bosilsa TechCardEditorPage faqat-o'qish narx rejimida ochiladi
// (canEditPrices: false): shef retseptni tahrirlaydi, masalliq narxi /
// «Сумма» / tannarx / sotuv narxini KO'RADI, lekin narx/foyda/nakladnoyni
// o'zgartira olmaydi.
// Mahsulot qo'shish/o'chirish/tartiblash/PDF bu yerda YO'Q.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

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

          return RefreshIndicator(
            onRefresh: _refresh,
            child: provider.categories.isEmpty
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
                    itemCount: provider.categories.length,
                    itemBuilder: (context, index) {
                      final category = provider.categories[index];
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

  const ShefTechCardProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<ShefTechCardProductsPage> createState() =>
      _ShefTechCardProductsPageState();
}

class _ShefTechCardProductsPageState extends State<ShefTechCardProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) => _ProductTile(
                            product: rows[index],
                            onTap: () => _openTechCard(rows[index]),
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

// Mahsulot qatori: rasm + nom (+ ПФ belgisi) + тех карта bor/yo'q belgisi.
class _ProductTile extends StatelessWidget {
  final ProductModelAdmin product;
  final VoidCallback onTap;

  const _ProductTile({required this.product, required this.onTap});

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
      subtitle: Text(
        hasCard ? 'Тех карта bor' : 'Тех карта to\'ldirilmagan',
        style: TextStyle(
          fontSize: 12,
          color: hasCard ? Colors.green.shade700 : Colors.grey.shade600,
        ),
      ),
      // «i» — tarkibi bor mahsulotda (admin ro'yxatidagi naqsh).
      trailing: hasCard
          ? const Icon(Icons.info_outline, color: _accentColor)
          : const Icon(Icons.chevron_right, color: Colors.black38),
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
