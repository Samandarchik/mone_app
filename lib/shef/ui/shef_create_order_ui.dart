// shef/ui/shef_create_order_ui.dart — yangi ishlab chiqarish buyurtmasi yaratish
// ekrani: ShefCreateOrderUi — tex kartali mahsulotlar savati «Полуфабрикат» va
// «Готовый» bo'limlariga ajratilgan, har bo'lim ichida ro'yxat KATEGORIYA
// bo'yicha guruhlangan (category_group.dart), partiya yaxlitlashi jonli;
// ShefProvider ustida.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/services/shef_service.dart';
import 'package:uz_ai_dev/shef/ui/widgets/category_group.dart';

// Yangi ishlab chiqarish buyurtmasi yaratish sahifasi.
// Tex kartali mahsulotlar ro'yxati (rasm bilan), qidiruv, har mahsulotga son
// kiritish (dialog). Partiya yaxlitlashi jonli ko'rinadi:
// «130 dona → 7 partiya (140 talik masalliq)».
// Ro'yxat ikki bo'limga ajratilgan: «Полуфабрикат» (is_semi_finished) va
// «Готовый». Qidiruv ikkalasida ham ishlaydi, savat esa UMUMIY — ikki
// bo'limdan tanlanganlar bitta buyurtmaga ketadi.
// Har bo'lim ichida qatorlar kategoriya sarlavhalari ostida guruhlanadi
// (bitta kategoriya bo'lsa sarlavha chiqmaydi). Guruhlash HAR BUILD'da emas —
// faqat mahsulotlar ro'yxati yoki qidiruv o'zgarganda hisoblanib keshlanadi
// (`_rebuildGroups`), ListView esa yassi (flat) indeks ustida chizadi.
class ShefCreateOrderUi extends StatefulWidget {
  const ShefCreateOrderUi({super.key});

  @override
  State<ShefCreateOrderUi> createState() => _ShefCreateOrderUiState();
}

class _ShefCreateOrderUiState extends State<ShefCreateOrderUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Tanlangan bo'lim: 0 — Полуфабрикат, 1 — Готовый.
  int _tab = 0;

  // Savat: productId -> son.
  final Map<int, int> _cart = {};

  // ── Guruhlash keshi ──────────────────────────────────────────────────────
  // Manba ro'yxat (identity) va qidiruv matni o'zgarmaguncha qayta hisoblamaymiz.
  List<ProductionProduct>? _groupsSource;
  String _groupsQuery = '';
  // Yassi (flat) ro'yxatlar: CategoryHeader | ProductionProduct elementlari.
  List<Object> _pfEntries = const [];
  List<Object> _readyEntries = const [];
  // Tab yorlig'idagi son — filtrdan keyingi mahsulotlar soni.
  int _pfCount = 0;
  int _readyCount = 0;

  // Faqat manba/qidiruv o'zgarganda ishlaydi (build ichidan chaqiriladi, lekin
  // setState qilmaydi — bu shunchaki kesh).
  void _rebuildGroups(List<ProductionProduct> source, String query) {
    if (identical(_groupsSource, source) && _groupsQuery == query) return;
    _groupsSource = source;
    _groupsQuery = query;

    final matched = query.isEmpty
        ? source
        : source.where((p) => p.name.toLowerCase().contains(query)).toList();
    final pfList = matched.where((p) => p.isSemiFinished).toList();
    final readyList = matched.where((p) => !p.isSemiFinished).toList();
    _pfCount = pfList.length;
    _readyCount = readyList.length;
    _pfEntries = buildCategoryEntries<ProductionProduct>(
      pfList,
      categoryId: (p) => p.categoryId,
      categoryName: (p) => p.categoryName,
    );
    _readyEntries = buildCategoryEntries<ProductionProduct>(
      readyList,
      categoryId: (p) => p.categoryId,
      categoryName: (p) => p.categoryName,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShefProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _fullImageUrl(String url) {
    if (url.isEmpty) return '';
    return url.startsWith('http') ? url : '${AppUrls.baseUrl}$url';
  }

  // Mahsulot bosilganda son kiritish dialogi (jonli partiya hisobi bilan).
  Future<void> _editQty(ProductionProduct product) async {
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => _QtyDialog(
        product: product,
        initialQty: _cart[product.id] ?? 0,
      ),
    );
    if (qty == null || !mounted) return;
    setState(() {
      if (qty <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = qty;
      }
    });
  }

  Future<void> _submit() async {
    final provider = context.read<ShefProvider>();
    final ok = await provider.createOrder(Map.of(_cart));
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buyurtma yuborildi')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Buyurtma yuborilmadi'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  int get _totalQty => _cart.values.fold(0, (s, v) => s + v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Yangi buyurtma',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<ShefProvider>(
        builder: (context, provider, child) {
          if (provider.isLoadingProducts) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.productsError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      provider.productsError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.fetchProducts(),
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

          // Bo'limlar (полуфабрикат / tayyor) + kategoriya guruhlari keshdan.
          final query = _searchQuery.toLowerCase();
          _rebuildGroups(provider.products, query);
          // Tanlangan bo'lim bo'sh, ikkinchisida natija bor bo'lsa —
          // ko'rsatishda ikkinchisiga o'tamiz (masalan katalogda пф yo'q).
          var tab = _tab;
          if (tab == 0 && _pfCount == 0 && _readyCount > 0) tab = 1;
          if (tab == 1 && _readyCount == 0 && _pfCount > 0) tab = 0;
          final entries = tab == 0 ? _pfEntries : _readyEntries;

          return Column(
            children: [
              Padding(
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
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _sectionTabs(tab, _pfCount, _readyCount),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Mahsulot topilmadi'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          // Yassi ro'yxat: sarlavha yoki mahsulot qatori.
                          if (entry is CategoryHeader) {
                            return CategoryHeaderTile(header: entry);
                          }
                          return _productTile(entry as ProductionProduct);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _cart.isEmpty ? null : _cartBar(),
    );
  }

  // «Полуфабрикат» / «Готовый» bo'lim tanlagichi (qavsda topilgan soni).
  Widget _sectionTabs(int tab, int pfCount, int readyCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(child: _tabButton(tab, 0, 'Полуфабрикат', pfCount)),
          const SizedBox(width: 8),
          Expanded(child: _tabButton(tab, 1, 'Готовый', readyCount)),
        ],
      ),
    );
  }

  Widget _tabButton(int tab, int index, String label, int count) {
    final selected = tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accentColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accentColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _productTile(ProductionProduct product) {
    final qty = _cart[product.id] ?? 0;
    final imageUrl = _fullImageUrl(product.imageUrl);
    final batches = product.batchesFor(qty);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: qty > 0 ? _accentColor : Colors.grey.shade300,
          width: qty > 0 ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: () => _editQty(product),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 52,
            height: 52,
            child: imageUrl.isEmpty
                ? Container(
                    color: Colors.grey.shade200,
                    child: Icon(Icons.cake_outlined,
                        color: Colors.grey.shade400),
                  )
                : AppNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_) => Container(color: Colors.grey.shade200),
                    errorWidget: (_) => Container(
                      color: Colors.grey.shade200,
                      child: Icon(Icons.broken_image,
                          color: Colors.grey.shade400),
                    ),
                  ),
          ),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: qty > 0
            ? Text(
                // Partiya yaxlitlashi jonli: 130 dona → 7 partiya (140 talik).
                '$qty dona → $batches partiya '
                '(${batches * product.totalPieces} talik masalliq)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.brown.shade700,
                  fontWeight: FontWeight.w500,
                ),
              )
            : Text(
                'Partiya: ${product.totalPieces} dona',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
        trailing: qty > 0
            ? Text(
                '$qty',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _accentColor,
                ),
              )
            : Icon(Icons.add_circle_outline, color: Colors.grey.shade500),
      ),
    );
  }

  // Pastki savat paneli: tanlanganlar soni + yuborish tugmasi.
  Widget _cartBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_cart.length} mahsulot • $_totalQty dona',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Consumer<ShefProvider>(
              builder: (context, provider, _) => ElevatedButton.icon(
                onPressed: provider.isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: provider.isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Yuborish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Son kiritish dialogi — partiya hisobi jonli ko'rinadi.
// Mahsulot tanlanishi bilan полуфабрикат qoldig'i (pf-availability)
// so'raladi va son maydoni max_qty bilan QATTIQ cheklanadi (server ham
// oshib ketsa 400 qaytaradi).
class _QtyDialog extends StatefulWidget {
  final ProductionProduct product;
  final int initialQty;

  const _QtyDialog({required this.product, required this.initialQty});

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final TextEditingController _ctrl;
  final ShefService _service = ShefService();
  int _qty = 0;

  // Полуфабрикат qoldig'i (null — hali kelmagan yoki xato).
  PfAvailability? _avail;
  bool _availLoading = false;
  // Foydalanuvchi chegaraga urilganda ko'rsatiladigan xabar.
  String? _capMessage;
  // Klaviatura bosishlarida ortiqcha so'rov ketmasligi uchun.
  Timer? _debounce;

  int? get _maxQty => _avail?.maxQty;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty;
    _ctrl = TextEditingController(
      text: widget.initialQty > 0 ? widget.initialQty.toString() : '',
    );
    // Mahsulot tanlandi — qoldiqni darhol so'raymiz.
    _fetchAvailability(_qty > 0 ? _qty : 1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailability(int qty) async {
    setState(() => _availLoading = true);
    try {
      final avail =
          await _service.fetchPfAvailability(widget.product.id, qty);
      if (!mounted) return;
      setState(() {
        _avail = avail;
        _availLoading = false;
      });
      _applyCap();
    } catch (_) {
      // Jim — cheklovni server baribir tekshiradi (400 + tayyor xabar).
      if (!mounted) return;
      setState(() => _availLoading = false);
    }
  }

  // Joriy son max_qty dan oshsa — qattiq kesamiz va xabar ko'rsatamiz.
  void _applyCap() {
    final max = _maxQty;
    if (max == null || _qty <= max) return;
    setState(() {
      _qty = max;
      // Programmatik .text o'zgarishi onChanged'ni chaqirmaydi.
      _ctrl.text = max.toString();
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      _capMessage = max > 0
          ? 'Полуфабрикат yetarli emas — ko\'pi bilan $max dona '
              'buyurtma berish mumkin'
          : 'Полуфабрикат qoldig\'i yo\'q — buyurtma berib bo\'lmaydi';
    });
  }

  void _onQtyChanged(String v) {
    final parsed = int.tryParse(v.trim()) ?? 0;
    final max = _maxQty;
    if (max != null && parsed > max) {
      _qty = parsed;
      _applyCap();
    } else {
      setState(() {
        _qty = parsed;
        _capMessage = null;
      });
    }
    // Miqdor o'zgardi — kerak (need) hisobini kichik debounce bilan yangilaymiz.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _fetchAvailability(_qty > 0 ? _qty : 1);
    });
  }

  int get _cappedQty {
    final max = _maxQty;
    if (max != null && _qty > max) return max;
    return _qty;
  }

  // Dona sonini chiroyli ko'rsatish (butun bo'lsa kasrsiz).
  static String _fmtNum(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  // Полуфабрикат qoldig'i bloki.
  Widget _pfInfo() {
    final avail = _avail;
    if (_availLoading && avail == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Полуфабрикат qoldig\'i tekshirilmoqda...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (avail == null || avail.limits.isEmpty) {
      return const SizedBox.shrink();
    }
    final max = avail.maxQty;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Полуфабрикат:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          for (final l in avail.limits)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${l.name}: kerak ${l.need} dona — '
                'qoldiq ${_fmtNum(l.stock)} dona, '
                'band ${_fmtNum(l.reserved)}, '
                'mumkin ${_fmtNum(l.available)}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: _qty > 0 && l.need > l.available
                      ? Colors.red.shade700
                      : Colors.grey.shade800,
                ),
              ),
            ),
          if (max != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ko\'pi bilan $max dona buyurtma berish mumkin',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color:
                      max > 0 ? Colors.brown.shade700 : Colors.red.shade700,
                ),
              ),
            ),
          if (_capMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _capMessage!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batches = widget.product.batchesFor(_cappedQty);
    return AlertDialog(
      title: Text(widget.product.name, style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Necha dona',
              border: OutlineInputBorder(),
            ),
            onChanged: _onQtyChanged,
            onSubmitted: (_) => Navigator.pop(context, _cappedQty),
          ),
          const SizedBox(height: 10),
          Text(
            _cappedQty > 0
                ? '$_cappedQty dona → $batches partiya '
                    '(${batches * widget.product.totalPieces} talik masalliq)'
                : 'Partiya: ${widget.product.totalPieces} dona',
            style: TextStyle(
              fontSize: 13,
              color: _cappedQty > 0
                  ? Colors.brown.shade700
                  : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          _pfInfo(),
        ],
      ),
      actions: [
        if (widget.initialQty > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text(
              'O\'chirish',
              style: TextStyle(color: Colors.red),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _cappedQty),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
