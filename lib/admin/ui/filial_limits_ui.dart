// admin/ui/filial_limits_ui.dart — filial mahsulot limitlari ekrani (FilialLimitsUi):
// FilialProviderAdmin + ProductProviderAdmin, limitlar FilialLimitService orqali;
// limit_qty gram kontraktda BUTUN (кг/л→gr/ml). Tashqi POS avto-buyurtma uchun.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/filial_limit_model.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/services/filial_limit_service.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';

// Filial limitlari — admin har bir filial uchun mahsulot bo'yicha maqsadli
// qoldiq belgilaydi («Napoleon torti — bu filialda 4 dona turishi kerak»).
// Tashqi POS har kuni kechqurun kamomadni avtomatik buyurtma qiladi.
//
// MUHIM (gram kontrakt): limit_qty API'da saqlanadigan birlikdagi BUTUN son —
// кг/л mahsulotlarda gr/ml (admin 1.5 kiritadi -> 1500 yuboriladi), шт va
// boshqalarda oddiy dona. Float YUBORILMAYDI (qtyFromUi butunlaydi).
class FilialLimitsUi extends StatefulWidget {
  const FilialLimitsUi({super.key});

  @override
  State<FilialLimitsUi> createState() => _FilialLimitsUiState();
}

class _FilialLimitsUiState extends State<FilialLimitsUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accent = Color(0xFFC5A97B);

  final FilialLimitService _service = FilialLimitService();
  final TextEditingController _searchController = TextEditingController();

  int? _selectedFilialId;
  // product_id -> limit (faqat limiti bor mahsulotlar).
  Map<int, FilialLimit> _limits = {};
  bool _limitsLoading = false;
  String? _limitsError;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filiallar (mavjud global provider) va mahsulotlar (ProductProviderAdmin —
  // kesh bo'lsa qayta so'ramaydi) parallel yuklanadi, so'ng birinchi filial
  // avtomatik tanlanadi.
  Future<void> _init() async {
    final filialProvider = context.read<FilialProviderAdmin>();
    final productProvider = context.read<ProductProviderAdmin>();
    await Future.wait([
      if (filialProvider.filials.isEmpty) filialProvider.getFilials(),
      productProvider.initializeProducts(),
    ]);
    if (!mounted) return;
    if (_selectedFilialId == null && filialProvider.filials.isNotEmpty) {
      _selectFilial(filialProvider.filials.first.id);
    }
  }

  void _selectFilial(int filialId) {
    if (_selectedFilialId == filialId) return;
    setState(() {
      _selectedFilialId = filialId;
      _limits = {};
    });
    _loadLimits(filialId);
  }

  Future<void> _loadLimits(int filialId) async {
    setState(() {
      _limitsLoading = true;
      _limitsError = null;
    });
    try {
      final list = await _service.fetchLimits(filialId);
      // Kutish paytida admin boshqa filialga o'tgan bo'lsa — eski javob
      // yangi tanlovni bosib qo'ymasin.
      if (!mounted || _selectedFilialId != filialId) return;
      setState(() {
        _limits = {for (final l in list) l.productId: l};
        _limitsLoading = false;
      });
    } catch (e) {
      if (!mounted || _selectedFilialId != filialId) return;
      setState(() {
        _limitsError = e.toString().replaceFirst('Exception: ', '');
        _limitsLoading = false;
      });
    }
  }

  // Pull-to-refresh: limitlar + mahsulotlar qayta yuklanadi.
  Future<void> _refresh() async {
    final productProvider = context.read<ProductProviderAdmin>();
    final filialId = _selectedFilialId;
    await Future.wait([
      productProvider.initializeProducts(forceRefresh: true),
      if (filialId != null) _loadLimits(filialId),
    ]);
  }

  // Tanlangan filialga biriktirilgan mahsulotlar (+ nom bo'yicha qidiruv).
  List<Product> _filialProducts(ProductProviderAdmin provider) {
    final filialId = _selectedFilialId;
    if (filialId == null) return const [];
    final q = _search.trim().toLowerCase();
    return provider.products
        .where((p) =>
            p.filials.contains(filialId) &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
        .toList();
  }

  // ─────────────────────── Limit tahrirlash dialogi ───────────────────────

  Future<void> _editLimit(Product product) async {
    final filialId = _selectedFilialId;
    if (filialId == null) return;

    final existing = _limits[product.id];
    // кг/л — admin kg/l da kasr kiritadi (API'ga gr/ml butun ketadi);
    // шт va boshqalar — faqat butun son.
    final allowDecimal = qtyUnitFactor(product.unit) != 1;
    final controller = TextEditingController(
      text: existing == null ? '' : formatQty(existing.limitQty, product.unit),
    );

    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          product.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: allowDecimal),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  allowDecimal ? RegExp(r'[\d.,]') : RegExp(r'\d'),
                ),
              ],
              decoration: InputDecoration(
                labelText: 'Limit (${product.unit})',
                hintText: allowDecimal ? 'Masalan: 1.5' : 'Masalan: 4',
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: _accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '0 yoki bo\'sh — limit o\'chiriladi',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (existing?.updated != null) ...[
              const SizedBox(height: 4),
              Text(
                'Yangilangan: ${DateFormat('dd.MM.yyyy HH:mm').format(existing!.updated!.toLocal())}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );

    if (text == null) return; // Bekor qilindi

    // Bo'sh — 0 (o'chirish). Vergul ham qabul qilinadi (1,5 -> 1.5).
    final trimmed = text.trim().replaceAll(',', '.');
    final double? uiValue = trimmed.isEmpty ? 0 : double.tryParse(trimmed);
    if (uiValue == null || uiValue < 0) {
      _showSnack('Noto\'g\'ri qiymat', error: true);
      return;
    }

    // Gram kontrakt: кг/л -> ×1000 butun; шт -> butun dona. Har doim int.
    final int apiQty = qtyFromUi(uiValue, product.unit).round();

    // O'zgarish yo'q — server bezovta qilinmaydi.
    final int currentQty = existing?.limitQty ?? 0;
    if (apiQty == currentQty) return;

    try {
      final saved = await _service.saveLimit(
        filialId: filialId,
        productId: product.id,
        limitQty: apiQty,
      );
      if (!mounted || _selectedFilialId != filialId) return;
      setState(() {
        if (apiQty == 0) {
          _limits.remove(product.id);
        } else {
          // Backend qatorni qaytarmasa ham qator joyida yangilanadi
          // (to'liq qayta so'rov YO'Q).
          _limits[product.id] = saved ??
              FilialLimit(
                id: existing?.id ?? 0,
                filialId: filialId,
                productId: product.id,
                productName: product.name,
                unit: product.unit,
                limitQty: apiQty,
                updated: DateTime.now(),
              );
        }
      });
      _showSnack(apiQty == 0 ? 'Limit o\'chirildi' : 'Limit saqlandi');
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  // ─────────────────────────────── Build ───────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Filial limitlari',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer2<FilialProviderAdmin, ProductProviderAdmin>(
        builder: (context, filialProvider, productProvider, _) {
          // Filiallar hali yuklanmoqda
          if (filialProvider.isLoading && filialProvider.filials.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          // Filiallarni olishda xato
          if (filialProvider.error != null && filialProvider.filials.isEmpty) {
            return _errorState(
              filialProvider.error!.replaceFirst('Exception: ', ''),
              onRetry: _init,
            );
          }

          if (filialProvider.filials.isEmpty) {
            return const Center(child: Text('Filiallar topilmadi'));
          }

          return Column(
            children: [
              _filialChips(filialProvider),
              _summaryLine(),
              _searchField(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: _accent,
                  child: _limitsBody(productProvider),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Filial tanlash chiplari (production stats dagi naqsh, gorizontal skroll).
  Widget _filialChips(FilialProviderAdmin filialProvider) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final filial in filialProvider.filials)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filial.name),
                selected: _selectedFilialId == filial.id,
                onSelected: (_) => _selectFilial(filial.id),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _selectedFilialId == filial.id
                      ? Colors.white
                      : Colors.black54,
                ),
                selectedColor: _accent,
                backgroundColor: Colors.white,
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: _selectedFilialId == filial.id
                      ? _accent
                      : Colors.grey.shade300,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryLine() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Limit o\'rnatilgan: ${_limits.length} ta mahsulot',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _search = value),
        decoration: InputDecoration(
          hintText: 'Mahsulot qidirish...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _accent, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _limitsBody(ProductProviderAdmin productProvider) {
    // Limitlar yoki mahsulotlar yuklanmoqda
    if (_limitsLoading ||
        (productProvider.isLoading && !productProvider.isInitialized)) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_limitsError != null) {
      return _errorState(
        _limitsError!,
        onRetry: () {
          final filialId = _selectedFilialId;
          if (filialId != null) _loadLimits(filialId);
        },
      );
    }

    final products = _filialProducts(productProvider);
    if (products.isEmpty) {
      return _scrollableCenter(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _search.trim().isEmpty
                  ? 'Bu filialga biriktirilgan mahsulot yo\'q'
                  : 'Hech narsa topilmadi',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: products.length,
      itemBuilder: (context, index) => _productRow(products[index]),
    );
  }

  // Bitta mahsulot qatori: nom + birlik, o'ngda joriy limit yoki «—».
  Widget _productRow(Product product) {
    final limit = _limits[product.id];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: () => _editLimit(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.unit,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Gram kontrakt: limitQty API birlikda (gr/ml) — ko'rsatishda
              // formatQtyUnit kg/l ga qaytaradi («1.5 кг», «4 шт»).
              Text(
                limit == null
                    ? '—'
                    : formatQtyUnit(limit.limitQty, product.unit),
                style: limit == null
                    ? TextStyle(fontSize: 14, color: Colors.grey.shade400)
                    : const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _accent,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorState(String message, {required VoidCallback onRetry}) {
    return _scrollableCenter(
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
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Qayta urinish'),
          ),
        ],
      ),
    );
  }

  // Pull-to-refresh xato/bo'sh holatda ham ishlashi uchun skrollanadigan
  // markaz (inventory_history_page dagi naqsh).
  Widget _scrollableCenter({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
