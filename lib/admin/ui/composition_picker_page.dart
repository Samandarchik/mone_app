// admin/ui/composition_picker_page.dart — ingredient (tarkib) tanlash sahifasi
// (CompositionPickerPage): home page kabi kategoriya ro'yxati, kategoriya ichida
// mahsulotlar; AppBar qidiruvi barcha mahsulotlar bo'yicha ishlaydi. Tanlangach
// miqdor+birlik dialogi (_AmountUnitDialog) orqali natijani TechItem qilib qaytaradi.
// шт mahsulot grammda kiritilsa «1 шт = X gr» so'raladi (piece_weight_g ga saqlanadi).
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/catalog/tech_card.dart';
import 'package:uz_ai_dev/admin/model/tech_card_cost.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';

// Ingredient (tarkib) tanlash sahifasi.
// Qidiruv bo'sh bo'lsa — home page'dagi kabi KATEGORIYA ro'yxati chiqadi;
// kategoriya bosilsa shu kategoriya mahsulotlari ochiladi. Qidiruv yozilsa —
// barcha mahsulotlar bo'yicha qidiradi. Mahsulot tanlanganda miqdor (butun son)
// + birlik so'raydigan dialog ochiladi va natija sifatida [TechItem] qaytaradi.
// Полуфабрикат ham SHU yerdan tanlanadi (ro'yxatda «ПФ» belgisi bilan) —
// alohida pf tanlagich yo'q; tex karta muharriri qatorni bazadagi
// is_semi_finished orqali avto пф deb ko'rsatadi.
class CompositionPickerPage extends StatefulWidget {
  // Ro'yxatdan chiqariladigan mahsulot (tahrirlanayotgan kartaning o'zi) —
  // mahsulot o'z tarkibiga o'zini qo'sha olmasin.
  final int? excludeProductId;

  const CompositionPickerPage({super.key, this.excludeProductId});

  @override
  State<CompositionPickerPage> createState() => _CompositionPickerPageState();
}

class _CompositionPickerPageState extends State<CompositionPickerPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  // Mahsulotlar YAGONA provider (ProductProviderAdmin) dan olinadi.
  // Ro'yxat allaqachon yuklangan bo'lsa (home page'da) qaytadan GET qilinmaydi —
  // faqat hech yuklanmagan bo'lsa bir marta yuklanadi. Kategoriyalar ham shunday.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final productProvider = context.read<ProductProviderAdmin>();
      final categoryProvider = context.read<CategoryProviderAdmin>();
      await Future.wait([
        if (productProvider.products.isEmpty)
          productProvider.initializeProducts(),
        if (categoryProvider.categories.isEmpty)
          categoryProvider.getCategories(),
      ]);
      if (!mounted) return;
      final products = productProvider.products
          .where((p) => p.id != widget.excludeProductId)
          .toList();
      setState(() {
        _allProducts = products;
        _filtered = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = _allProducts;
      } else {
        _filtered = _allProducts
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _onProductTap(Product product) async {
    final result = await showDialog<TechItem>(
      context: context,
      builder: (_) => _AmountUnitDialog(product: product),
    );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  // Kategoriya ichidagi mahsulotlar sahifasini ochadi; u yerda mahsulot
  // tanlansa TechItem qaytadi va bu sahifa ham shu natija bilan yopiladi.
  Future<void> _onCategoryTap(CategoryProductAdmin category) async {
    final result = await Navigator.of(context).push<TechItem>(
      MaterialPageRoute(
        builder: (_) => _CategoryProductsPage(
          categoryId: category.id,
          categoryName: category.name,
          excludeProductId: widget.excludeProductId,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Поиск продукта...',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => _searchController.clear(),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    // Qidiruv bo'sh — home page'dagi kabi kategoriya ro'yxati.
    if (_searchController.text.trim().isEmpty) {
      return _buildCategoryList();
    }

    // Qidiruv yozilgan — barcha mahsulotlar bo'yicha natijalar.
    if (_filtered.isEmpty) {
      return const Center(child: Text('Продукты не найдены'));
    }
    return ListView.separated(
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _ProductPickTile(product: _filtered[index], onTap: _onProductTap),
    );
  }

  Widget _buildCategoryList() {
    return Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
      builder: (context, categoryProvider, productProvider, _) {
        final categories = categoryProvider.categories;
        if (categories.isEmpty) {
          return const Center(child: Text('Kategoriyalar topilmadi'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final productCount =
                productProvider.getProductCountByCategory(category.id);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipOval(
                child: category.imageUrl != null
                    ? AppNetworkImage(
                        imageUrl: "${AppUrls.baseUrl}${category.imageUrl}",
                        width: 55,
                        height: 55,
                        fit: BoxFit.cover,
                        errorWidget: (context) =>
                            const Icon(Icons.image_not_supported),
                      )
                    : Container(
                        width: 55,
                        height: 55,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.image_not_supported),
                      ),
              ),
              title: Text(
                category.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                '$productCount продукт',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey,
              ),
              onTap: () => _onCategoryTap(category),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

// Bitta kategoriya mahsulotlari ro'yxati. Mahsulot tanlanganda miqdor+birlik
// dialogi ochiladi va sahifa [TechItem] natija bilan yopiladi.
class _CategoryProductsPage extends StatelessWidget {
  final int categoryId;
  final String categoryName;
  final int? excludeProductId;

  const _CategoryProductsPage({
    required this.categoryId,
    required this.categoryName,
    this.excludeProductId,
  });

  Future<void> _onProductTap(
      BuildContext context, Product product) async {
    final result = await showDialog<TechItem>(
      context: context,
      builder: (_) => _AmountUnitDialog(product: product),
    );
    if (result != null && context.mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = context
        .watch<ProductProviderAdmin>()
        .products
        .where((p) => p.categoryId == categoryId && p.id != excludeProductId)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: products.isEmpty
          ? const Center(child: Text('Продукты не найдены'))
          : ListView.separated(
              itemCount: products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _ProductPickTile(
                product: products[index],
                onTap: (p) => _onProductTap(context, p),
              ),
            ),
    );
  }
}

// Mahsulot qatori (rasm + nom + birlik + qo'shish belgisi) — qidiruv
// natijalarida ham, kategoriya ichida ham bir xil ishlatiladi.
class _ProductPickTile extends StatelessWidget {
  final Product product;
  final ValueChanged<Product> onTap;

  const _ProductPickTile({required this.product, required this.onTap});

  String _fullImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    return url.startsWith('http') ? url : '${AppUrls.baseUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _fullImageUrl(product.imageUrl);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: imageUrl.isEmpty
              ? Container(
                  color: Colors.grey[200],
                  child: Icon(Icons.image, color: Colors.grey[400]),
                )
              : AppNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_) => Container(color: Colors.grey[200]),
                  errorWidget: (_) => Container(
                    color: Colors.grey[200],
                    child: Icon(Icons.broken_image, color: Colors.grey[400]),
                  ),
                ),
        ),
      ),
      // Полуфабрикат — nom yonida «ПФ» belgisi (tex kartadagi chip uslubi):
      // tanlansa muharrir uni bazadan avto пф deb taniydi.
      title: product.isPf
          ? Row(
              children: [
                Flexible(child: Text(product.name)),
                Container(
                  margin: const EdgeInsets.only(left: 5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border.all(color: Colors.purple.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ПФ',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ),
              ],
            )
          : Text(product.name),
      subtitle: product.unit.isNotEmpty ? Text(product.unit) : null,
      trailing: const Icon(Icons.add_circle_outline),
      onTap: () => onTap(product),
    );
  }
}

// Miqdor (butun son amount) + birlik (g/ml/pcs/m) kiritish dialogi.
// шт-oiladagi mahsulot (tuxum, полуфабрикат) grammda ham kiritilishi mumkin:
// bunda «1 шт = X gr» so'raladi/ko'rsatiladi (pf uchun tex kartadan, xom
// mahsulot uchun admin kiritadi va mahsulotga saqlanadi — piece_weight_g).
class _AmountUnitDialog extends StatefulWidget {
  final Product product;

  const _AmountUnitDialog({required this.product});

  @override
  State<_AmountUnitDialog> createState() => _AmountUnitDialogState();
}

class _AmountUnitDialogState extends State<_AmountUnitDialog> {
  final TextEditingController _amountController = TextEditingController();
  // «1 шт = X gr» maydoni (faqat xom шт mahsulot + 'g' birlikda ko'rinadi).
  final TextEditingController _pieceWeightController = TextEditingController();
  // Default birlik — gramm (eng ko'p ishlatiladigan).
  String _unit = 'g';
  bool _saving = false;

  // Mahsulot шт-oilasidanmi (tuxum, pf...). Pf mahsulot type doim шт.
  bool get _isShtFamily => normalizeProductType(widget.product.unit) == 'шт';

  // Полуфабрикат birligi TANLANMAYDI — o'z tex kartasi belgilaydi: batch_unit
  // 'g' → гр, aks holda дона. Дона'dagi пф grammga o'tmaydi (birlik faqat пф
  // tex kartasida шт↔гр bilan o'zgartiriladi). null — oddiy (xom) mahsulot.
  String? get _pfFixedUnit => widget.product.isPf
      ? (widget.product.techCard?.batchUnit == 'g' ? 'g' : 'pcs')
      : null;

  @override
  void initState() {
    super.initState();
    // Mahsulot turidan birlikni topishga harakat qilamiz (пф — kartasidan).
    _unit = _pfFixedUnit ?? normalizeTechUnit(widget.product.unit);
    final saved = _effectiveW;
    if (saved > 0 && !widget.product.isPf) {
      _pieceWeightController.text = saved.toString();
    }
  }

  // Saqlangan effektiv «1 dona og'irligi» (tex kartadan yoki piece_weight_g).
  int get _effectiveW => techEffectivePieceWeightG(
        widget.product.id,
        techProductsById(context.read<ProductProviderAdmin>().products),
      );

  // Hisob-kitoblar uchun joriy W: pf — tex kartadan (read-only), xom —
  // maydonga yozilgan qiymat.
  int get _currentW => widget.product.isPf
      ? _effectiveW
      : (int.tryParse(_pieceWeightController.text.trim()) ?? 0);

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _onUnitChanged(String? value) {
    if (value == null) return;
    setState(() => _unit = value);
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _snack('Введите корректное количество');
      return;
    }
    // Gramm kiritilgan шт mahsulot: W (1 шт = X gr) majburiy — usiz backend
    // g -> dona konvertini qila olmaydi.
    if (_isShtFamily && _unit == 'g') {
      final w = _currentW;
      if (widget.product.isPf) {
        if (w <= 0) {
          _snack('Пф tex kartasida og\'irlik yo\'q — grammda kiritib '
              'bo\'lmaydi');
          return;
        }
      } else {
        if (w <= 0) {
          _snack('1 шт necha gramm ekanini kiriting');
          return;
        }
        // Yangi/o'zgargan W avval mahsulotga saqlanadi (piece_weight_g).
        if (w != widget.product.pieceWeightG) {
          setState(() => _saving = true);
          final provider = context.read<ProductProviderAdmin>();
          final ok = await provider
              .updateProduct(widget.product.copyWith(pieceWeightG: w));
          if (!mounted) return;
          setState(() => _saving = false);
          if (!ok) {
            _snack(provider.error ?? '«1 шт = $w gr» saqlanmadi');
            return;
          }
        }
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      TechItem(
        productId: widget.product.id,
        name: widget.product.name,
        amount: amount,
        unit: _unit,
      ),
    );
  }

  // «1 шт = X gr» bo'limi: pf — read-only matn, xom — tahrir maydoni.
  // Faqat шт-oilasida va 'g' birlik tanlanganda ko'rinadi.
  Widget _pieceWeightSection() {
    if (widget.product.isPf) {
      final w = _effectiveW;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            // Og'irlik yo'q — grammda kiritib bo'lmaydi (saqlash bloklanadi).
            w > 0
                ? '1 шт ≈ $w г (tex kartadan)'
                : 'Пф tex kartasida og\'irlik yo\'q — grammda kiritib '
                    'bo\'lmaydi',
            style: w > 0
                ? TextStyle(fontSize: 13, color: Colors.grey.shade700)
                : TextStyle(fontSize: 12.5, color: Colors.red[700]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: _pieceWeightController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '1 шт = __ гр',
          helperText: 'Bir dona og\'irligi — mahsulotga saqlanadi',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    // «1 шт = X gr» faqat XOM шт mahsulotda (tuxum) kerak — гр rejimidagi
    // пф o'zi grammda o'lchanadi (1 dona = 1 гр), eslatma ortiqcha.
    final showPieceWeight = _isShtFamily && _unit == 'g' && _pfFixedUnit != 'g';
    final w = _currentW;
    // Jonli «≈ N шт» hisobi (gramm kiritilayotganda).
    final pcsHint = (showPieceWeight && w > 0 && amount > 0)
        ? '≈ ${(amount / w).toStringAsFixed(1)} шт'
        : null;
    // 'pcs' birlikda og'irlik ma'lum bo'lsa kichik eslatma.
    final savedW = _isShtFamily ? _effectiveW : 0;
    final pcsUnitHint = (_isShtFamily && _unit == 'pcs' && savedW > 0)
        ? '1 шт ≈ $savedW г'
        : null;
    return AlertDialog(
      title: Text(widget.product.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Количество (целое)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (pcsHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pcsHint,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Пф birligi qat'iy (o'z tex kartasidan) — tanlash yo'q.
          if (_pfFixedUnit != null)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Ед. изм.',
                border: OutlineInputBorder(),
              ),
              child: Text(techUnitLabel(_unit)),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ед. изм.',
                border: OutlineInputBorder(),
              ),
              items: kTechUnits
                  .map((u) => DropdownMenuItem<String>(
                        value: u,
                        child: Text(techUnitLabel(u)),
                      ))
                  .toList(),
              onChanged: _onUnitChanged,
            ),
          if (pcsUnitHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pcsUnitHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ),
          if (showPieceWeight) _pieceWeightSection(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Добавить'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _pieceWeightController.dispose();
    super.dispose();
  }
}
