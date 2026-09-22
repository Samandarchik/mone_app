// shef/ui/shef_cakes_page.dart — «Торты» bo'limi (ShefCakesPage): Biskvit
// bo'limi yoki shef bosh ekranidagi nomi «Торт» bo'lgan kategoriya
// (isTortCategory) ochilganda. Tayyor tortlar 2 ustunli GRIDda: tepada
// tortning fotosi (bo'lmasa — tex kartadagi o'lchamda qoplangan tort chizmasi,
// rangi nom/tarkibdan), ostida nomi, o'lchami/og'irligi va tex karta holati.
// Karta bir marta bosilsa — KONSTRUKTOR shu tort bilan
// (ShefConstructorPage(cake: ...): biskvit/nachinka/qoplama tortning tex
// kartasidan oldindan tanlanadi); ikki marta — tortning tex kartasi (narxsiz
// rejim, bo'limlardagi naqsh). Pastda «Qo'shish» — shu kategoriyaga yangi
// tort. Ro'yxat ProductProviderAdmin (YAGONA manba) dan, lokal qidiruv.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/admin_add_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/shef_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

class ShefCakesPage extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  // true — pastda «Qo'shish» (Biskvit bo'limi / bosh ekrandan ochilganda).
  final bool canAddProducts;

  const ShefCakesPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.canAddProducts = false,
  });

  @override
  State<ShefCakesPage> createState() => _ShefCakesPageState();
}

class _ShefCakesPageState extends State<ShefCakesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
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

  // Bir marta bosish — konstruktor shu tort bilan.
  void _openConstructor(ProductModelAdmin cake) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ShefConstructorPage(cake: cake)),
    );
  }

  // Ikki marta bosish — tortning tex kartasi (narxsiz rejim).
  void _openTechCard(ProductModelAdmin cake) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(product: cake, canEditPrices: false),
      ),
    );
  }

  Future<void> _addProduct() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddProductPage(initialCategoryId: widget.categoryId),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      floatingActionButton: widget.canAddProducts
          ? FloatingActionButton.extended(
              onPressed: _addProduct,
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Qo\'shish'),
            )
          : null,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        titleSpacing: _searchOpen ? 0 : null,
        title: _searchOpen
            ? _compactSearch()
            : Text(
                widget.categoryName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
      body: Consumer<ProductProviderAdmin>(
        builder: (context, provider, _) {
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

          return RefreshIndicator(
            onRefresh: _refresh,
            child: rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 140),
                      Center(
                        child: Text(
                          all.isEmpty
                              ? 'Bu kategoriyada tort yo\'q'
                              : 'Topilmadi',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    // Pastki joy — FAB oxirgi qatorni yopmasin.
                    padding: EdgeInsets.fromLTRB(
                        12, 8, 12, widget.canAddProducts ? 88 : 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 246,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final p = rows[index];
                      return _CakeCard(
                        cake: p,
                        onTap: () => _openConstructor(p),
                        onDoubleTap: () => _openTechCard(p),
                      );
                    },
                  ),
          );
        },
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
          hintText: 'Tort qidirish...',
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
}

// Tortda tex karta tarkibi bormi (shef_tech_card_page.dart dagi naqsh).
bool _hasTechCard(ProductModelAdmin p) {
  final tc = p.techCard;
  if (tc == null) return false;
  return tc.bases.any((b) => b.ingredients.isNotEmpty) ||
      tc.consumables.isNotEmpty;
}

// Tortning o'lchami va og'irligi — «Ø 18 sm · 6 sm · 1.2 kg» (bo'lgan
// qismlari); hech biri yo'q bo'lsa ''.
String _sizeLine(TechCard? c) {
  if (c == null) return '';
  final parts = <String>[];
  final d = c.diameterCm ?? 0;
  final w = c.widthCm ?? 0;
  final l = c.lengthCm ?? 0;
  final h = c.heightCm ?? 0;
  if (d > 0) {
    parts.add('Ø $d sm');
  } else if (w > 0 && l > 0) {
    parts.add('$w×$l sm');
  }
  if (h > 0) parts.add('$h sm');
  final g = c.pieceWeightG > 0 ? c.pieceWeightG : c.batchWeightG;
  if (g > 0) parts.add('${formatQty(g, 'кг')} kg');
  return parts.join(' · ');
}

// Bitta tort kartasi: tepada foto (bo'lmasa — tex kartadagi o'lchamda
// qoplangan tort chizmasi), ostida nom, o'lcham/og'irlik va tex karta
// holati. Bir marta — konstruktor, ikki marta — tex karta.
class _CakeCard extends StatelessWidget {
  final ProductModelAdmin cake;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  const _CakeCard({
    required this.cake,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final image = cake.imageUrl ?? '';
    final url = image.isEmpty ? null : '${AppUrls.baseUrl}$image';
    final hasCard = _hasTechCard(cake);
    final size = _sizeLine(cake.techCard);
    // Foto yo'q — qoplangan butun tort, o'lchami tex kartadan, rangi
    // nom/tarkibdan (FillingLook.coatOf: «Покрытие» palitrasi → tavsif).
    final Widget drawn = FillingThumb(
      look: FillingLook.neutral,
      coat: FillingLook.coatOf(cake.name, cake.techCard),
      dims: BiscuitDims.fromTechCard(cake.techCard),
      whole: true,
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
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, box) => url != null
                        ? AppNetworkImage(
                            imageUrl: url,
                            width: box.maxWidth,
                            height: box.maxHeight,
                            fit: BoxFit.cover,
                            placeholder: (_) => drawn,
                            errorWidget: (_) => drawn,
                          )
                        : SizedBox.expand(child: drawn),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cake.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              if (size.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  size,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.brown.shade700),
                ),
              ],
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    hasCard ? Icons.menu_book : Icons.menu_book_outlined,
                    size: 14,
                    color: hasCard ? Colors.green.shade700 : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      hasCard ? 'Тех карта bor' : 'Тех карта to\'ldirilmagan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasCard
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
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
