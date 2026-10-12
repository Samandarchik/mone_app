// production/ui/widgets/stock_widgets.dart — sklad qoldig'i (stock) uchun umumiy
// vidjetlar: StockSkladView (qidiruv+qoldiq+korreksiya), showStockMovesSheet
// (harakatlar tarixi), showStockAdjustDialog; StockProvider ustida.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';
import 'package:uz_ai_dev/production/provider/stock_provider.dart';

// Sklad qoldig'i uchun UMUMIY vidjetlar: bitta sklad ko'rinishi (qidiruv +
// qoldiqlar ro'yxati + korreksiya), harakatlar tarixi bottom sheet'i va
// korreksiya dialogi. Ombor va admin sahifalari shularni qayta ishlatadi.

const Color _accent = Color(0xFFC5A97B);

// Bitta skladning qoldiqlari ko'rinishi. Scaffold'siz — sahifa (yoki tab)
// ichiga joylanadi. canAdjust=true bo'lsa «Korreksiya» tugmasi chiqadi.
class StockSkladView extends StatefulWidget {
  final int skladId;
  final bool canAdjust;

  const StockSkladView({
    super.key,
    required this.skladId,
    this.canAdjust = false,
  });

  @override
  State<StockSkladView> createState() => _StockSkladViewState();
}

class _StockSkladViewState extends State<StockSkladView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _onlyLow = false; // faqat kam qolganlar filtri

  // Tab almashganda qayta yuklanmasin (admin sklad tablari).
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<StockProvider>();
      // Faqat hali yuklanmagan bo'lsa yuklaymiz (kesh bor bo'lsa ko'rsatiladi).
      if (provider.stockFor(widget.skladId) == null &&
          !provider.isLoading(widget.skladId)) {
        provider.fetchStock(widget.skladId);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAdjustDialog() async {
    final provider = context.read<StockProvider>();
    final result = await showStockAdjustDialog(
      context,
      skladId: widget.skladId,
    );
    if (result == null || !mounted) return;
    final err = result.isWriteOff
        ? await provider.writeOff(
            skladId: widget.skladId,
            productId: result.productId,
            qty: result.qty,
            reason: result.comment,
          )
        : await provider.adjust(
            skladId: widget.skladId,
            productId: result.productId,
            qty: result.qty,
            comment: result.comment,
          );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ??
            (result.isWriteOff ? 'Spisaniya qayd etildi' : 'Korreksiya saqlandi')),
        backgroundColor: err == null ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<StockProvider>(
      builder: (context, provider, child) {
        final rows = provider.stockFor(widget.skladId);
        final loading = provider.isLoading(widget.skladId);
        final error = provider.errorFor(widget.skladId);

        if (loading && rows == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        if (error != null && rows == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.fetchStock(widget.skladId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            ),
          );
        }

        final all = rows ?? const <StockRow>[];
        final lowCount = all.where((r) => r.low).length;
        final q = _query.toLowerCase().trim();
        var filtered = q.isEmpty
            ? all
            : all.where((r) => r.name.toLowerCase().contains(q)).toList();
        if (_onlyLow) {
          filtered = filtered.where((r) => r.low).toList();
        }

        return Column(
          children: [
            // Qidiruv + korreksiya qatori.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Mahsulot qidirish...',
                        prefixIcon:
                            const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear,
                                    color: Colors.grey),
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
                  if (widget.canAdjust) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          provider.isSubmitting ? null : _openAdjustDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Korreksiya'),
                    ),
                  ],
                ],
              ),
            ),
            // «Kam qolganlar» filtri (min chegaradan tushganlar soni bilan).
            if (lowCount > 0 || _onlyLow)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: FilterChip(
                    selected: _onlyLow,
                    onSelected: (v) => setState(() => _onlyLow = v),
                    avatar: Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: _onlyLow ? Colors.white : Colors.orange.shade800,
                    ),
                    label: Text('Kam qolganlar ($lowCount)'),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _onlyLow ? Colors.white : Colors.orange.shade800,
                    ),
                    selectedColor: Colors.orange.shade700,
                    checkmarkColor: Colors.white,
                    backgroundColor: Colors.orange.shade50,
                    side: BorderSide(color: Colors.orange.shade300),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: _accent,
                onRefresh: () => provider.fetchStock(widget.skladId),
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              _onlyLow
                                  ? 'Kam qolgan mahsulotlar yo\'q'
                                  : q.isEmpty
                                      ? 'Qoldiq yozuvlari yo\'q.\nKirim yoki '
                                          'korreksiya kiritilganda paydo '
                                          'bo\'ladi.'
                                      : 'Hech narsa topilmadi',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _StockRowTile(
                          row: filtered[index],
                          canSetMin: widget.canAdjust,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Bitta qoldiq qatori: nomi | qty + birlik (manfiy — QIZIL, kam qolgan —
// to'q sariq fon + ogohlantirish belgisi). Bosilganda harakatlar tarixi,
// long-press'da «Min chegara» menyusi ochiladi.
class _StockRowTile extends StatelessWidget {
  final StockRow row;
  final bool canSetMin;

  const _StockRowTile({required this.row, this.canSetMin = false});

  // Long-press menyusi: min chegara tahriri (+ tarix ham qulaylik uchun).
  Future<void> _showRowMenu(BuildContext context) async {
    final title = row.name.isEmpty ? 'Mahsulot #${row.productId}' : row.name;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                // qty API birlikda (кг/л -> gramm) — UI'da kg/l ko'rinadi.
                'Qoldiq: ${formatQty(row.qty, row.type)} ${row.type}'
                '${row.minQty > 0 ? ' • Min: ${formatQty(row.minQty, row.type)}' : ''}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            const Divider(height: 1),
            if (canSetMin)
              ListTile(
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('Min chegara'),
                subtitle: Text(
                  row.minQty > 0
                      ? 'Hozir: ${formatQty(row.minQty, row.type)} ${row.type}'
                      : 'O\'rnatilmagan',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMin(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Harakatlar tarixi'),
              onTap: () {
                Navigator.pop(ctx);
                showStockMovesSheet(
                  context,
                  skladId: row.skladId,
                  productId: row.productId,
                  title: row.name,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Min chegara son kiritish dialogi -> POST /api/stock/min -> refresh.
  Future<void> _editMin(BuildContext context) async {
    final provider = context.read<StockProvider>();
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _MinQtyDialog(row: row),
    );
    if (value == null || !context.mounted) return;
    final err = await provider.setMin(
      skladId: row.skladId,
      productId: row.productId,
      minQty: value,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Min chegara saqlandi'),
        backgroundColor: err == null ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final negative = row.qty < 0;
    final low = row.low;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: low ? Colors.orange.shade50 : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: negative
              ? Colors.red.shade300
              : low
                  ? Colors.orange.shade300
                  : Colors.grey.shade300,
        ),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          row.name.isEmpty ? 'Mahsulot #${row.productId}' : row.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: row.minQty > 0
            ? Text(
                'Min: ${formatQty(row.minQty, row.type)} ${row.type}'.trim(),
                style: TextStyle(
                  fontSize: 11.5,
                  color: low ? Colors.orange.shade800 : Colors.grey.shade600,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (low) ...[
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 6),
            ],
            Text(
              '${formatQty(row.qty, row.type)} ${row.type}'.trim(),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: negative
                    ? Colors.red
                    : low
                        ? Colors.orange.shade900
                        : Colors.black87,
              ),
            ),
          ],
        ),
        onTap: () => showStockMovesSheet(
          context,
          skladId: row.skladId,
          productId: row.productId,
          title: row.name,
        ),
        onLongPress: () => _showRowMenu(context),
      ),
    );
  }
}

// Min chegara kiritish dialogi. null — bekor; qiymat 0 bo'lishi mumkin
// (chegara olib tashlanadi).
class _MinQtyDialog extends StatefulWidget {
  final StockRow row;

  const _MinQtyDialog({required this.row});

  @override
  State<_MinQtyDialog> createState() => _MinQtyDialogState();
}

class _MinQtyDialogState extends State<_MinQtyDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      // minQty API birlikda — maydonga UI (kg/l) qiymati yoziladi.
      text: widget.row.minQty > 0
          ? formatQty(widget.row.minQty, widget.row.type)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctrl.text.trim().replaceAll(',', '.');
    // Bo'sh — chegarani olib tashlash (0).
    final value = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (value == null || value < 0) {
      setState(() => _error = 'Miqdorni to\'g\'ri kiriting');
      return;
    }
    // UI (kg/l) -> API (butun gramm/ml).
    Navigator.pop(context, qtyFromUi(value, widget.row.type).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return AlertDialog(
      title: Text(
        'Min chegara — ${row.name.isEmpty ? '#${row.productId}' : row.name}',
        style: const TextStyle(fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Qoldiq shu chegaraga tushganda qator «kam qolgan» deb '
            'belgilanadi. Bo\'sh qoldirilsa chegara olib tashlanadi.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText:
                  'Min miqdor${row.type.isNotEmpty ? ' (${row.type})' : ''}',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
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
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

// Harakatlar tarixi bottom sheet'i: sana | sabab | +/- qty (rangli) | izoh.
// productId berilsa faqat shu mahsulot tarixi.
void showStockMovesSheet(
  BuildContext context, {
  required int skladId,
  int? productId,
  String title = '',
}) {
  final provider = context.read<StockProvider>();
  // Harakat qatorlarida birlik (type) katalogdan ham topilishi uchun.
  provider.ensureCatalog();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? 'Harakatlar tarixi' : title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<StockMove>>(
                  future: provider.fetchMoves(skladId, productId: productId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator.adaptive());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            snapshot.error
                                .toString()
                                .replaceFirst('Exception: ', ''),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }
                    final moves = snapshot.data ?? const <StockMove>[];
                    if (moves.isEmpty) {
                      return const Center(
                        child: Text(
                          'Harakatlar yo\'q',
                          style: TextStyle(color: Colors.black54),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: moves.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _MoveRow(
                        move: moves[index],
                        showName: title.isEmpty,
                        // qty API birlikda — mahsulot birligi qoldiq/katalog
                        // ro'yxatidan aniqlanadi (topilmasa faktor 1).
                        type: provider.typeFor(
                            skladId, moves[index].productId),
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
}

class _MoveRow extends StatelessWidget {
  final StockMove move;
  // Umumiy tarixda (mahsulot filtri yo'q) mahsulot nomi ham ko'rsatiladi.
  final bool showName;
  // Mahsulot birligi (кг/л bo'lsa qty gramm/ml'da keladi — /1000 ko'rsatiladi).
  final String? type;

  const _MoveRow({required this.move, this.showName = false, this.type});

  String _date(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final positive = move.qty >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showName && move.name.isNotEmpty)
                  Text(
                    move.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  '${_date(move.created)} • ${stockReasonLabel(move.reason)}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (move.comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      move.comment,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.black87,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${positive ? '+' : ''}${formatQty(move.qty, type)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: positive ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Korreksiya dialogi ───────────────────────

// Dialog natijasi: tanlangan mahsulot, ishorali miqdor va izoh.
// isWriteOff=true — SPISANIYA (brak): /api/stock/write-off ga ketadi
// (qty musbat, comment = sabab, majburiy).
class StockAdjustResult {
  final int productId;
  final double qty; // + kirim, − chiqim (spisaniyada musbat)
  final String comment;
  final bool isWriteOff;

  const StockAdjustResult({
    required this.productId,
    required this.qty,
    required this.comment,
    this.isWriteOff = false,
  });
}

// Korreksiya dialogini ochish. Mahsulot qoldiq qatorlaridan yoki katalogdan
// (qidiruv bilan) tanlanadi. null — bekor qilindi.
Future<StockAdjustResult?> showStockAdjustDialog(
  BuildContext context, {
  required int skladId,
}) {
  // Katalogni oldindan yuklab qo'yamiz (bir marta; xatoda jim).
  context.read<StockProvider>().ensureCatalog();
  return showDialog<StockAdjustResult>(
    context: context,
    builder: (_) => _StockAdjustDialog(skladId: skladId),
  );
}

class _StockAdjustDialog extends StatefulWidget {
  final int skladId;

  const _StockAdjustDialog({required this.skladId});

  @override
  State<_StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<_StockAdjustDialog> {
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  Product? _selected;
  // 0: + kirim, 1: − chiqim, 2: spisaniya (brak)
  int _mode = 0;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // Mahsulot tanlash: qoldiq qatorlari + katalog birlashtirilib, qidiruv
  // bilan bottom sheet'da ko'rsatiladi.
  Future<void> _pickProduct() async {
    final provider = context.read<StockProvider>();
    final merged = <int, Product>{};
    for (final r in provider.stockFor(widget.skladId) ?? const <StockRow>[]) {
      merged[r.productId] =
          Product(id: r.productId, name: r.name, unit: r.type);
    }
    for (final c in provider.catalog) {
      merged.putIfAbsent(c.id, () => c);
    }
    final items = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ProductPickerSheet(items: items),
    );
    if (picked != null && mounted) {
      setState(() {
        _selected = picked;
        _error = null;
      });
    }
  }

  void _submit() {
    if (_selected == null) {
      setState(() => _error = 'Mahsulot tanlang');
      return;
    }
    final raw = _qtyController.text.trim().replaceAll(',', '.');
    final qty = double.tryParse(raw);
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Miqdorni to\'g\'ri kiriting (0 dan katta)');
      return;
    }
    if (_mode == 2 && _commentController.text.trim().isEmpty) {
      setState(() => _error = 'Spisaniya uchun sababi majburiy');
      return;
    }
    // UI (kg/l) -> API (butun gramm/ml); boshqa birliklar o'zgarishsiz.
    final apiQty = qtyFromUi(qty, _selected!.unit).toDouble();
    Navigator.pop(
      context,
      StockAdjustResult(
        productId: _selected!.id,
        qty: _mode == 1 ? -apiQty : apiQty,
        comment: _commentController.text.trim(),
        isWriteOff: _mode == 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Korreksiya', style: TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mahsulot tanlash maydoni.
            InkWell(
              onTap: _pickProduct,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Mahsulot',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selected == null
                            ? 'Tanlash...'
                            : '${_selected!.name}'
                                '${_selected!.unit.isNotEmpty ? ' (${_selected!.unit})' : ''}',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selected == null
                              ? Colors.grey
                              : Colors.black87,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Rejim: + kirim / − chiqim / spisaniya (brak).
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Kirim (+)')),
                    selected: _mode == 0,
                    selectedColor: Colors.green.shade100,
                    onSelected: (_) => setState(() => _mode = 0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Chiqim (−)')),
                    selected: _mode == 1,
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) => setState(() => _mode = 1),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Brak 🗑')),
                    selected: _mode == 2,
                    selectedColor: Colors.orange.shade100,
                    onSelected: (_) => setState(() => _mode = 2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              autofocus: false,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText:
                    'Miqdor${_selected != null && _selected!.unit.isNotEmpty ? ' (${_selected!.unit})' : ''}',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _mode == 2 ? 'Sababi (majburiy)' : 'Izoh (ixtiyoriy)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

// Mahsulot tanlash bottom sheet'i (qidiruv bilan).
class _ProductPickerSheet extends StatefulWidget {
  final List<Product> items;

  const _ProductPickerSheet({required this.items});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
            .where((p) => p.name.toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: Padding(
        // Klaviatura ochilganda ro'yxat ko'rinib turishi uchun.
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Mahsulot qidirish...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFFF5F1EA),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Hech narsa topilmadi',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              p.name,
                              style: const TextStyle(fontSize: 14),
                            ),
                            trailing: p.unit.isEmpty
                                ? null
                                : Text(
                                    p.unit,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
