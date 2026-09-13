// production/ui/widgets/price_history_sheet.dart — masalliq XARID narxi
// bottom sheet'i: showPriceHistorySheet/_PriceHistorySheet — tepada QO'LDA
// narx kiritish bloki (PUT /api/products/{id}/manual-price,
// ProductProviderAdmin orqali), ostida xaridlar tarixi (GET
// /api/prices/history). Tex karta muharriridagi «Цена» katagidan ochiladi.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart'
    show normalizeProductType;
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/production/models/price_history_model.dart';
import 'package:uz_ai_dev/production/services/production_service.dart';
import 'package:uz_ai_dev/production/ui/widgets/cost_sheet.dart';

// Bitta masalliqning xarid narxi sheet'i. Ikki qismdan iborat:
//   1) «Qo'lda narx» — hech qachon sotib olinmagan masalliq uchun admin
//      narxni SHU YERDA kiritadi (BUTUN so'm, mahsulotning TO'LIQ birligi
//      uchun: кг → 1 kg narxi, шт → 1 dona narxi). Bo'sh/0 — o'chirish.
//      XARID narxi doim USTUN — qo'lda narx faqat bo'shliqni to'ldiradi.
//   2) Xaridlar tarixi — GET /api/prices/history. Qator:
//      «dd.MM.yyyy • sklad • pricer — qty birlik × 1kg narxi = summa».
// Sheet `true` qaytarsa — qo'lda narx o'zgargan, chaqiruvchi narxlarni
// qayta yuklashi kerak.
// `allowManualEdit: false` — 1-qism (qo'lda narx bloki) UMUMAN chizilmaydi:
// faqat xarid tarixi ko'rinadi (shef rejimi, manual-price PUT yo'q).

const Color _accent = Color(0xFFC5A97B);

// Qo'lda narx maydonining yorlig'i: mahsulot birligiga qarab
// «1 кг narxi» / «1 литр narxi» / «1 дона narxi» / «1 метр narxi».
String manualPriceLabel(String productType) {
  switch (normalizeProductType(productType)) {
    case 'кг':
      return '1 кг narxi';
    case 'л':
      return '1 литр narxi';
    case 'шт':
      return '1 дона narxi';
    case 'м':
      return '1 метр narxi';
    default:
      final t = productType.trim();
      return t.isEmpty ? '1 birlik narxi' : '1 $t narxi';
  }
}

// Narx sheet'ini ochadi. Qo'lda narx saqlangan/o'chirilgan bo'lsa `true`
// qaytaradi (chaqiruvchi /api/prices/latest ni qayta yuklaydi).
Future<bool?> showPriceHistorySheet(
  BuildContext context, {
  required int productId,
  String productName = '',
  bool allowManualEdit = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _PriceHistorySheet(
      productId: productId,
      productName: productName,
      allowManualEdit: allowManualEdit,
    ),
  );
}

class _PriceHistorySheet extends StatefulWidget {
  final int productId;
  final String productName;
  // false — qo'lda narx bloki ko'rsatilmaydi (faqat tarix o'qiladi).
  final bool allowManualEdit;

  const _PriceHistorySheet({
    required this.productId,
    this.productName = '',
    this.allowManualEdit = true,
  });

  @override
  State<_PriceHistorySheet> createState() => _PriceHistorySheetState();
}

class _PriceHistorySheetState extends State<_PriceHistorySheet> {
  late Future<List<PriceHistoryEntry>> _future;
  final TextEditingController _manualCtrl = TextEditingController();

  // Mahsulotda XARID tarixi bormi — bo'lsa qo'lda narx ishlatilmaydi
  // (kulrang izoh chiqadi).
  bool _hasPurchases = false;
  bool _saving = false;

  // Mahsulot ProductProviderAdmin (yagona manba) dan bir marta olinadi:
  // birlik yorlig'i va joriy qo'lda narx uchun. null — ro'yxatda yo'q
  // (masalan mahsulotlar hali yuklanmagan) → tahrir bloki ko'rsatilmaydi.
  ProductModelAdmin? _product;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_product != null) return;
    final p = context.read<ProductProviderAdmin>().productById(widget.productId);
    if (p == null) return;
    _product = p;
    _manualCtrl.text =
        p.manualPrice > 0 ? formatMoneyInput(p.manualPrice) : '';
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    _future = ProductionService().fetchPriceHistory(widget.productId);
    // Xarid tarixi bor-yo'qligini alohida kuzatamiz (tahrir blokidagi izoh
    // FutureBuilder'dan tepada turadi). Xato — jim, izoh chiqmaydi.
    _future.then<void>(
      (list) {
        if (mounted) setState(() => _hasPurchases = list.isNotEmpty);
      },
      onError: (_) {},
    );
  }

  // «Saqlash»: bo'sh/0 — qo'lda narxni O'CHIRISH. Muvaffaqiyatda sheet
  // `true` qaytarib yopiladi — chaqiruvchi narxlarni qayta yuklaydi.
  Future<void> _saveManualPrice() async {
    if (_saving) return;
    final price = parseMoney(_manualCtrl.text);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ProductProviderAdmin>();

    setState(() => _saving = true);
    final ok = await provider.setManualPrice(widget.productId, price);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Narx saqlanmadi'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          price > 0
              ? 'Qo\'lda narx saqlandi: ${fmtCostMoney(price)} сум'
              : 'Qo\'lda narx o\'chirildi',
        ),
      ),
    );
  }

  // Klaviatura ochilganda sheet balandligi qisqarsin (overflow bo'lmasin).
  double _sheetHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final wanted = media.size.height * 0.6;
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top - 24;
    if (available <= 0) return wanted;
    if (wanted <= available) return wanted;
    return available < 220 ? 220 : available;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: _sheetHeight(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 20, color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.productName.isEmpty
                            ? 'Narx tarixi'
                            : 'Narx tarixi — ${widget.productName}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (widget.allowManualEdit && _product != null)
                _manualPriceBlock(_product!),
              Expanded(
                child: FutureBuilder<List<PriceHistoryEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator.adaptive());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                snapshot.error
                                    .toString()
                                    .replaceFirst('Exception: ', ''),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black54),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => setState(_reload),
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
                    final entries = snapshot.data ?? [];
                    if (entries.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Xarid tarixi yo\'q',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _HistoryRow(entry: entries[index]),
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

  // «Qo'lda narx» tahrir bloki — sheet'ning eng tepasida.
  Widget _manualPriceBlock(ProductModelAdmin product) {
    final saved = product.manualPrice;
    final at = product.manualPriceAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FD),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text(
                'Qo\'lda narx',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
              if (saved > 0 && at != null) ...[
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd.MM.yyyy').format(at.toLocal()),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _manualCtrl,
                  keyboardType: TextInputType.number,
                  // Pul — BUTUN so'm (tiyin yo'q); yozayotganda har 3
                  // xonadan probel: 200 000.
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    labelText: manualPriceLabel(product.type),
                    labelStyle: const TextStyle(fontSize: 13),
                    suffixText: ' сум',
                    hintText: '—',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _saveManualPrice(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveManualPrice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Saqlash'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Xarid narxi bo'lsa qo'lda narx ISHLATILMAYDI — buni aytib
          // qo'yamiz, aks holda admin «nega o'zgarmadi?» deb o'ylaydi.
          if (_hasPurchases)
            Text(
              'Xarid narxi ustun — qo\'lda narx faqat xarid bo\'lmaganda '
              'ishlatiladi.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            'Bo\'sh qoldirilsa (yoki 0) qo\'lda narx o\'chiriladi.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PriceHistoryEntry entry;

  const _HistoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final date = entry.date == null
        ? '—'
        : DateFormat('dd.MM.yyyy').format(entry.date!.toLocal());
    final head = [
      date,
      if (entry.skladName.isNotEmpty) entry.skladName,
      if (entry.pricer.isNotEmpty) entry.pricer,
    ].join(' • ');
    // qty eng kichik birlikda -> UI'da kg/l; narx eng kichik birlik uchun ->
    // UI'da 1 kg/l narxi (x qtyUnitFactor).
    final detail = '${formatQty(entry.qty, entry.unit)} ${entry.unit} × '
        '${fmtCostMoney(entry.price * qtyUnitFactor(entry.unit))} = '
        '${fmtCostMoney(entry.sum)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            head,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
