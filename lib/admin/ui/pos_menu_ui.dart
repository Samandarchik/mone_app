// admin/ui/pos_menu_ui.dart — Konak POS menyu editori ekrani (faqat admin):
// PosMenuUi (StatefulWidget) — PosMenuService bilan katalogni tartiblash,
// qo'shish/chiqarish; har o'zgarishda avto-saqlash (PUT /api/pos-menu).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/model/pos_menu_model.dart';
import 'package:uz_ai_dev/admin/services/pos_menu_service.dart';
import 'package:uz_ai_dev/admin/ui/widgets/sale_price_dialog.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/production/ui/widgets/cost_sheet.dart'
    show fmtCostMoney;

// POS menyu EDITORI — Konak POS ko'radigan katalog kuratsiyasi:
// - tartibni sudrab o'zgartirish (ReorderableListView, faqat "Hammasi"da),
// - qatordagi qizil ikonka bilan menyudan chiqarish (bazaga tegmaydi),
// - "+" bilan available_products dan menyu oxiriga qo'shish.
// Har o'zgarishda AVTO-SAQLASH: PUT /api/pos-menu to'liq TARTIBLI id
// ro'yxati bilan; holat javobdagi data bilan yangilanadi, xatoda oldingi
// (server) holatga qaytariladi. Kategoriya chiplari — client-side FILTR.
// configured=false — server to'liq bazani qaytaradi; birinchi o'zgarish
// config yaratadi (maxsus UI shart emas).
//
// MUHIM (int kontrakt): sale_price — butun so'm (0 = narx qo'yilmagan),
// limit_qty — saqlanadigan birlikda BUTUN (кг/л -> gr/ml) —
// formatQtyUnit kg/l ga qaytaradi.

const Color _kBgColor = Color(0xFFFAF6F1);
const Color _kAccent = Color(0xFFC5A97B);
const Color _kAccentDark = Color(0xFF8A6F45);

class PosMenuUi extends StatefulWidget {
  const PosMenuUi({super.key, this.kassa = false});

  // kassa=true — Mone kassasi menyusi: filial tanlanadi, faqat Taom va Tovar.
  final bool kassa;

  @override
  State<PosMenuUi> createState() => _PosMenuUiState();
}

class _PosMenuUiState extends State<PosMenuUi> {
  late final PosMenuService _service = PosMenuService(kassa: widget.kassa);
  // Kassa rejimida tanlangan filial (null — server birinchisini oladi / kassa
  // rejimida filial tanlanmaguncha yuklanmaydi).
  int? _filialId;

  PosMenuResult? _result;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Tanlangan kategoriya id'si (null = "Hammasi").
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    if (widget.kassa) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final fp = context.read<FilialProviderAdmin>();
        if (fp.filials.isEmpty) await fp.getFilials();
        if (!mounted) return;
        if (fp.filials.isNotEmpty) {
          _filialId = fp.filials.first.id;
          _load();
        } else {
          setState(() {
            _loading = false;
            _error = 'Filiallar topilmadi';
          });
        }
      });
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchPosMenu(filialId: _filialId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _resetFilterIfGone(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // Kategoriya o'chib ketgan bo'lsa filtrni "Hammasi"ga qaytarish.
  void _resetFilterIfGone(PosMenuResult result) {
    if (_selectedCategoryId != null &&
        !result.categories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = null;
    }
  }

  // ─────────────────────── Kuratsiya (avto-saqlash) ───────────────────────

  // Optimistik yangilash + PUT. Xatoda oldingi (oxirgi server) holatga
  // qaytariladi va snackbar ko'rsatiladi.
  Future<void> _persist(
    List<PosMenuProduct> products,
    List<PosMenuProduct> available,
  ) async {
    final previous = _result;
    if (previous == null) return;
    setState(() {
      _saving = true;
      _result = PosMenuResult(
        filialId: previous.filialId,
        filialName: previous.filialName,
        configured: previous.configured,
        categories: previous.categories,
        products: products,
        availableProducts: available,
      );
    });
    try {
      final updated = await _service.savePosMenu(
        previous.filialId > 0 ? previous.filialId : null,
        products.map((p) => p.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _result = updated;
        _saving = false;
        _resetFilterIfGone(updated);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = previous; // server holatiga qaytarish
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saqlanmadi: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // Drag drop — faqat "Hammasi" ko'rinishida (indexlar to'liq ro'yxatga mos).
  // onReorderItem newIndex'ni allaqachon to'g'rilab beradi.
  void _onReorder(int oldIndex, int newIndex) {
    final result = _result;
    if (result == null || _saving) return;
    if (oldIndex == newIndex) return;
    final products = List<PosMenuProduct>.of(result.products);
    final moved = products.removeAt(oldIndex);
    products.insert(newIndex, moved);
    _persist(products, result.availableProducts);
  }

  // Menyudan chiqarish — bazaga tegmaydi, available'ga tushadi.
  void _removeProduct(PosMenuProduct product) {
    final result = _result;
    if (result == null || _saving) return;
    _persist(
      result.products.where((p) => p.id != product.id).toList(),
      [...result.availableProducts, product],
    );
  }

  // Available'dan menyu OXIRIGA qo'shish.
  void _addProduct(PosMenuProduct product) {
    final result = _result;
    if (result == null || _saving) return;
    _persist(
      [...result.products, product],
      result.availableProducts.where((p) => p.id != product.id).toList(),
    );
  }

  // ─────────────────────────────── Build ───────────────────────────────

  // Kassa rejimi: filial tanlash (menyu har filialda alohida, narx umumiy).
  Widget _filialPicker() {
    final filials = context.watch<FilialProviderAdmin>().filials;
    return PopupMenuButton<int>(
      tooltip: 'Filial',
      icon: const Icon(Icons.store_mall_directory_outlined),
      onSelected: (id) {
        if (id == _filialId) return;
        _filialId = id;
        _selectedCategoryId = null;
        _load();
      },
      itemBuilder: (_) => [
        for (final f in filials)
          CheckedPopupMenuItem<int>(
            value: f.id,
            checked: f.id == _filialId,
            child: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filialName = _result?.filialName ?? '';
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.kassa ? 'Kassa menyusi' : 'POS menyu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (filialName.isNotEmpty)
              Text(
                filialName,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          if (widget.kassa) _filialPicker(),
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kAccentDark,
                  ),
                ),
              ),
            )
          else if (_result != null)
            IconButton(
              icon: const Icon(Icons.add, color: _kAccentDark),
              tooltip: 'Qo\'shish',
              onPressed: _openAddSheet,
            ),
        ],
        bottom: _result == null ? null : _categoryChips(_result!),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _kAccent,
        child: _body(),
      ),
    );
  }

  // AppBar ostidagi gorizontal skrollanadigan kategoriya chiplari:
  // "Hammasi" + har kategoriya uchun bittadan. Filtr client-side.
  PreferredSizeWidget _categoryChips(PosMenuResult result) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            _chip(label: 'Hammasi', categoryId: null),
            for (final category in result.categories)
              _chip(label: category.name, categoryId: category.id),
          ],
        ),
      ),
    );
  }

  Widget _chip({required String label, required int? categoryId}) {
    final selected = _selectedCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedCategoryId = categoryId),
        selectedColor: _kAccent.withValues(alpha: 0.25),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? _kAccentDark : Colors.black87,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? _kAccent : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (_error != null && _result == null) {
      return _scrollableCenter(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      );
    }

    final all = _result?.products ?? const <PosMenuProduct>[];
    final filtered = _selectedCategoryId == null
        ? all
        : all.where((p) => p.categoryId == _selectedCategoryId).toList();

    return Column(
      children: [
        _hintBanner(),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState()
              : _selectedCategoryId == null
                  // "Hammasi" — drag bilan tartiblanadigan to'liq ro'yxat.
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: all.length,
                      onReorderItem: _onReorder,
                      itemBuilder: (context, index) =>
                          _productCard(all[index], reorderIndex: index),
                    )
                  // Kategoriya filtri faol — drag O'CHIRILGAN (handle'siz).
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _productCard(filtered[index]),
                    ),
        ),
      ],
    );
  }

  // Kichik hint banner — bu ekran POS menyusining editori ekanini eslatadi.
  Widget _hintBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: _kAccentDark),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bu ro\'yxat POS\'da ko\'rinadigan menyu — tartibini sudrab '
              'o\'zgartiring, keraksizini o\'chiring',
              style: TextStyle(fontSize: 11.5, color: _kAccentDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return _scrollableCenter(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _selectedCategoryId == null
                ? 'Menyuda mahsulot yo\'q — "+" bilan qo\'shing'
                : 'Bu kategoriyada mahsulot yo\'q',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // Pull-to-refresh xato/bo'sh holatda ham ishlashi uchun skrollanadigan markaz.
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

  // Bitta mahsulot kartasi: rasm + nom + kategoriya, o'ngda narx, limit
  // badge, o'chirish ikonkasi va (faqat "Hammasi"da) drag handle.
  Widget _productCard(PosMenuProduct product, {int? reorderIndex}) {
    return Card(
      key: ValueKey(product.id),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _thumbnail(product.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.categoryName,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (product.limitQty > 0) ...[
                    const SizedBox(height: 4),
                    _limitBadge(product),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _priceText(product, editable: true),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: Colors.red, size: 22),
              tooltip: 'Menyudan chiqarish',
              visualDensity: VisualDensity.compact,
              onPressed: _saving ? null : () => _removeProduct(product),
            ),
            if (reorderIndex != null)
              ReorderableDragStartListener(
                index: reorderIndex,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.drag_handle,
                      color: Colors.grey.shade500, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // editable=true (asosiy menyu ro'yxati) — narx BOSILADI, sotish narxini
  // shu yerdan qo'lda qo'yish mumkin (POS shu narxni ko'radi); saqlangach
  // menyu qayta yuklanadi. «Qo'shish» oynasida esa qator butunligicha
  // mahsulotni menyuga qo'shadi — u yerda narx faqat ko'rsatiladi.
  Widget _priceText(PosMenuProduct product, {bool editable = false}) {
    final hasPrice = product.salePrice > 0;
    final label = hasPrice
        ? Text(
            '${fmtCostMoney(product.salePrice)} so\'m',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: _kAccentDark,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          )
        : Text(
            'Narx yo\'q',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade500,
            ),
          );
    if (!editable) return label;
    return InkWell(
      onTap: _saving ? null : () => _editPrice(product),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            const SizedBox(width: 3),
            Icon(
              Icons.edit,
              size: 12,
              color: hasPrice ? Colors.grey.shade400 : Colors.blue.shade400,
            ),
          ],
        ),
      ),
    );
  }

  // Sotish narxini qo'lda kiritish (yagona manba: sale_price_dialog.dart).
  // Narx tex kartada saqlanadi — POS menyu esa o'z servisidan o'qiydi,
  // shuning uchun saqlangach ro'yxatni qayta yuklaymiz.
  Future<void> _editPrice(PosMenuProduct product) async {
    final saved = await editProductSalePrice(
      context,
      productId: product.id,
      productName: product.name,
    );
    if (saved != null && mounted) await _load();
  }

  // 48x48 dumaloq burchakli rasm; URL bo'sh/xato bo'lsa ikonka.
  Widget _thumbnail(String imageUrl) {
    final placeholder = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.bakery_dining, color: _kAccentDark, size: 24),
    );
    if (imageUrl.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        imageUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }

  // Avto-buyurtma limiti badge'i (limit_qty saqlanadigan birlikda butun).
  Widget _limitBadge(PosMenuProduct product) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Limit: ${formatQtyUnit(product.limitQty, product.unit)}',
        style: const TextStyle(
          fontSize: 11,
          color: _kAccentDark,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  // ────────────────────── "+ Qo'shish" bottom sheet ──────────────────────

  // available_products ro'yxati qidiruv bilan; tap → menyu oxiriga qo'shiladi.
  void _openAddSheet() {
    final result = _result;
    if (result == null || _saving) return;
    if (result.availableProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Qo\'shiladigan mahsulot yo\'q — hammasi menyuda'),
        ),
      );
      return;
    }
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final available =
                _result?.availableProducts ?? const <PosMenuProduct>[];
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? available
                : available
                    .where((p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.categoryName.toLowerCase().contains(q))
                    .toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Menyuga qo\'shish',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: false,
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: InputDecoration(
                          hintText: 'Qidirish...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: _kAccent),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'Hech narsa topilmadi',
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final product = filtered[index];
                                return Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: Colors.grey.shade300),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _addProduct(product);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          _thumbnail(product.imageUrl),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  product.name,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  product.categoryName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _priceText(product),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.add_circle_outline,
                                            color: _kAccentDark,
                                            size: 22,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
