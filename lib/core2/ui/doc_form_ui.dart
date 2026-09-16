// core2/ui/doc_form_ui.dart — universal hujjat formasi (DocFormUi): bitta
// ekran, tur bo'yicha maydonlar — receipt (corr supplier, qaysi omborga,
// narx), issue (dan, corr payment/writeoff/debtor, sotuv summasi), transfer/
// reserve (dan/ga), production (dan/ga, ikki jadval: sarf flag=1 va mahsulot
// flag=0), act (ga, taomlar), inventory (ombor, sana, tovar ro'yxati: joriy
// qoldiq + fakt; «faqat farqlilar»; bo'sh qoldirilganlar yuborilmaydi).
// Miqdor: tanlangan birlikda kiritiladi (kg/l/dona), serverga BUTUN base
// (`coreQtyFromUi`); narx — 1 birlik, butun so'm; summa avtomatik; sotuv
// summasi (issue/reserve/act) — QATOR darajasida `sale_amount` (ledger.Line).
// Inventory qatori `flag`: 1 — tayyor mahsulot (is_complect, retsept bilan
// yoyiladi), 0 — xom. Tovar qidiruvi server tomonda (good_picker).
// Hujjat endpointlari ledger ulanmaguncha 501 — showCoreError «hali
// yoqilmagan» deb ko'rsatadi.
// Tugmalar perms bo'yicha: Saqlash (draft) — doc.<type>.create, Tasdiqlash —
// doc.<type>.post (warnings → dialog), O'chirish (draft). Orqa sana —
// doc.backdate. Bozorchi: DocFormUi.marketReceipt() — supplier «РЫНОК»
// oldindan, «Saqlash va tasdiqlash» (POST /docs/quick).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_picker.dart';

class DocFormUi extends StatelessWidget {
  final String type;
  // Mavjud draft'ni tahrirlash (null — yangi).
  final CoreDoc? existing;
  // Bozorchi tez oqimi: supplier=РЫНОК, «Saqlash va tasdiqlash».
  final bool market;

  const DocFormUi({super.key, required this.type, this.existing})
      : market = false;

  const DocFormUi.marketReceipt({super.key})
      : type = CoreDocType.receipt,
        existing = null,
        market = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Text(
          market
              ? 'Bozor приход'
              : existing == null
                  ? 'Yangi: ${CoreDocType.title(type)}'
                  : '${CoreDocType.title(type)} ${existing!.number}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: CoreConnectGate(
        child: type == CoreDocType.inventory
            ? _InventoryForm(existing: existing)
            : _DocForm(type: type, existing: existing, market: market),
      ),
    );
  }
}

// ───────────────────────── Oddiy hujjat formasi ─────────────────────────

/// Bitta tahrirlanayotgan qator: tovar, birlik, UI miqdor/narx matni.
class _LineEdit {
  final CoreGood good;
  CoreGoodUnit unit;
  final TextEditingController qty;
  final TextEditingController price;
  // issue/reserve/act: qator sotuv summasi (ixtiyoriy, butun so'm).
  final TextEditingController sale;
  final int flag;

  _LineEdit({
    required this.good,
    required this.unit,
    String qtyText = '',
    String priceText = '',
    String saleText = '',
    this.flag = 0,
  })  : qty = TextEditingController(text: qtyText),
        price = TextEditingController(text: priceText),
        sale = TextEditingController(text: saleText);

  int get baseQty => coreQtyFromUi(parseUiQty(qty.text) ?? 0, unit);
  int get priceInt => parseMoney(price.text);
  int get amount => coreLineAmount(baseQty, priceInt, unit);
  int get saleInt => parseMoney(sale.text);

  void dispose() {
    qty.dispose();
    price.dispose();
    sale.dispose();
  }

  CoreDocLine toLine() => CoreDocLine(
        goodId: good.id,
        goodName: good.name,
        unit: unit.unit,
        qty: baseQty,
        price: priceInt,
        amount: amount,
        saleAmount: sale.text.trim().isEmpty ? null : saleInt,
        flag: flag,
      );
}

class _DocForm extends StatefulWidget {
  final String type;
  final CoreDoc? existing;
  final bool market;
  const _DocForm({required this.type, this.existing, required this.market});

  @override
  State<_DocForm> createState() => _DocFormState();
}

class _DocFormState extends State<_DocForm> {
  late String _date;
  int? _from;
  int? _to;
  int? _corr;
  final _comment = TextEditingController();
  final List<_LineEdit> _lines = [];
  bool _busy = false;
  bool _initDone = false;

  String get type => widget.type;
  bool get hasFrom => CoreDocType.hasFrom(type);
  bool get hasTo => CoreDocType.hasTo(type);
  bool get hasCorr => CoreDocType.hasCorr(type);
  bool get hasPrice => CoreDocType.hasPrice(type);
  bool get hasSale => CoreDocType.hasSaleAmount(type);
  bool get isProduction => type == CoreDocType.production;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _date = ex?.docDate ?? todayIso();
    _from = ex?.fromSklad;
    _to = ex?.toSklad;
    _corr = ex?.corrId;
    _comment.text = ex?.comment ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    final dict = context.read<CoreDictProvider>();
    final ex = widget.existing;
    if (ex != null) {
      // Tovarlar to'liq keshlanmaydi (12 000+): keshda bo'lmasa qator
      // ma'lumotidan (nom + `unit` → base) quramiz; fonda keshga olib kelamiz.
      dict.ensureGoods(ex.lines.map((l) => l.goodId));
      for (final l in ex.lines) {
        final good = dict.goodById(l.goodId) ??
            CoreGood(
                id: l.goodId,
                name: l.goodName,
                baseUnit: coreBaseUnitOf(l.unit),
                partial: true);
        final unit = good.selectableUnits.firstWhere(
          (u) => u.unit == l.unit,
          orElse: () => good.preferredUnit,
        );
        _lines.add(_LineEdit(
          good: good,
          unit: unit,
          qtyText: coreFormatInUnit(l.qty, unit),
          priceText: l.price > 0 ? formatMoneyInput(l.price) : '',
          saleText: (l.saleAmount ?? 0) > 0 ? formatMoneyInput(l.saleAmount!) : '',
          flag: l.flag,
        ));
      }
    }
    if (widget.market && _corr == null) {
      _corr = dict.findCorrByName('рынок')?.id ??
          dict.findCorrByName('bozor')?.id;
    }
    // Foydalanuvchi bitta omborga biriktirilgan bo'lsa — default.
    final user = context.read<CoreSession>().user;
    if (user != null && user.sklads.length == 1) {
      _to ??= hasTo ? user.sklads.first : null;
      _from ??= hasFrom ? user.sklads.first : null;
    }
    if (dict.activeSklads.length == 1) {
      final only = dict.activeSklads.first.id;
      if (hasTo) _to ??= only;
      if (hasFrom) _from ??= only;
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _total => _lines.fold(0, (s, l) => s + l.amount);
  int get _totalSale => _lines.fold(0, (s, l) => s + l.saleInt);

  /// Qator qaysi ombor qoldig'ini ko'rsatadi: production'da sarf (flag=1)
  /// «dan» omboridan yechiladi, mahsulot (flag=0) «ga» omboriga kiradi;
  /// qolgan turlarda chiqim bo'lsa «dan», aks holda «ga».
  int? _skladForFlag(int flag) {
    if (isProduction) return flag == 1 ? _from : _to;
    return hasFrom ? _from : _to;
  }

  Future<void> _addLine({int flag = 0}) async {
    final sklad = _skladForFlag(flag);
    final good = await pickCoreGood(context, skladId: sklad);
    if (good == null || !mounted) return;
    setState(() {
      _lines.add(_LineEdit(good: good, unit: good.preferredUnit, flag: flag));
    });
  }

  CoreDoc _build() => CoreDoc(
        id: widget.existing?.id ?? 0,
        type: type,
        docDate: _date,
        fromSklad: hasFrom ? _from : null,
        toSklad: hasTo ? _to : null,
        corrId: hasCorr ? _corr : null,
        comment: _comment.text.trim(),
        lines: _lines.map((l) => l.toLine()).toList(),
      );

  String? _validate() {
    if (hasFrom && _from == null) return 'Qaysi ombordan — tanlang';
    if (hasTo && _to == null) return 'Qaysi omborga — tanlang';
    if (hasCorr && _corr == null) return 'Kontragentni tanlang';
    // Faqat ko'chirish/rezervda omborlar farq qilishi shart; ishlab
    // chiqarishda from = to bo'lishi mumkin (server ham ruxsat beradi).
    if ((type == CoreDocType.transfer || type == CoreDocType.reserve) &&
        _from == _to) {
      return 'Ombor «dan» va «ga» bir xil';
    }
    if (_lines.isEmpty) return 'Kamida bitta qator qo\'shing';
    for (final l in _lines) {
      if (l.baseQty <= 0) return '«${l.good.name}» miqdori 0';
      if (hasPrice && l.priceInt <= 0) return '«${l.good.name}» narxi 0';
    }
    if (isProduction) {
      if (!_lines.any((l) => l.flag == 1)) return 'Sarf qatorlari yo\'q';
      if (!_lines.any((l) => l.flag == 0)) return 'Mahsulot qatorlari yo\'q';
    }
    return null;
  }

  Future<void> _save({required bool post, bool quick = false}) async {
    final err = _validate();
    if (err != null) {
      showCoreInfo(context, err);
      return;
    }
    final docs = context.read<CoreDocsProvider>();
    final stock = context.read<CoreStockProvider>();
    setState(() => _busy = true);
    try {
      final draft = _build();
      CoreDoc saved;
      List<CoreDocWarning> warnings = const [];
      if (quick) {
        final res = await docs.quick(draft);
        saved = res.doc;
        warnings = res.warnings;
      } else {
        saved = draft.id > 0
            ? await docs.update(draft.id, draft)
            : await docs.create(draft);
        if (post) {
          final res = await docs.post(saved.id);
          saved = res.doc;
          warnings = res.warnings;
        }
      }
      if (!mounted) return;
      if (warnings.isNotEmpty) await showWarningsDialog(context, warnings);
      if (!mounted) return;
      stock.refreshSklads([saved.fromSklad, saved.toSklad]);
      showCoreInfo(
          context,
          post || quick
              ? 'Hujjat o\'tkazildi: ${saved.number}'
              : 'Saqlandi (qoralama): ${saved.number}');
      if (widget.market) {
        // Bozorchi keyingi kirimni darhol kiritadi — forma tozalanadi.
        setState(() {
          for (final l in _lines) {
            l.dispose();
          }
          _lines.clear();
          _comment.clear();
          _date = todayIso();
        });
      } else {
        context.pushReplacement(DocDetailUi(docId: saved.id, initial: saved));
      }
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ex = widget.existing;
    if (ex == null) return;
    final ok = await confirmDialog(
        context, 'O\'chirish', 'Qoralama ${ex.number} o\'chirilsinmi?',
        okText: 'O\'chirish', danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<CoreDocsProvider>().delete(ex.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    final canCreate = session.canCreate(type);
    final canPost = session.canPost(type);
    final editable = widget.existing == null || widget.existing!.isDraft;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              _header(session, editable),
              const SizedBox(height: 10),
              if (isProduction) ...[
                _linesSection('Sarf (xomashyo)', flag: 1, editable: editable),
                const SizedBox(height: 10),
                _linesSection('Mahsulot (chiqish)', flag: 0, editable: editable),
              ] else
                _linesSection(
                    type == CoreDocType.act ? 'Taomlar' : 'Qatorlar',
                    flag: 0,
                    editable: editable),
              const SizedBox(height: 10),
              _totalCard(),
            ],
          ),
        ),
        if (editable)
          _actions(canCreate: canCreate, canPost: canPost),
      ],
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: child,
      );

  Widget _header(CoreSession session, bool editable) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: !editable
                    ? null
                    : () async {
                        final d = await pickDate(context, _date,
                            allowPast: session.canBackdate);
                        if (d != null) setState(() => _date = d);
                      },
                child: InputDecorator(
                  decoration: coreInput('Sana',
                      suffix: const Icon(Icons.calendar_today, size: 18)),
                  child: Text(coreDate(_date)),
                ),
              ),
            ),
            if (!session.canBackdate)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Orqa sana ruxsati yo\'q (doc.backdate)',
                  child: Icon(Icons.lock_clock, size: 18, color: Colors.grey.shade500),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (hasFrom)
          CoreSkladDropdown(
            value: _from,
            label: 'Qaysi ombordan',
            enabled: editable,
            onChanged: (v) => setState(() => _from = v),
          ),
        if (hasFrom && hasTo) const SizedBox(height: 10),
        if (hasTo)
          CoreSkladDropdown(
            value: _to,
            label: 'Qaysi omborga',
            enabled: editable,
            onChanged: (v) => setState(() => _to = v),
          ),
        if (hasCorr) ...[
          const SizedBox(height: 10),
          CoreCorrDropdown(
            value: _corr,
            label: type == CoreDocType.receipt ? 'Kimdan (ta\'minotchi)' : 'Kontragent',
            kinds: type == CoreDocType.receipt
                ? const ['supplier', 'other']
                : const ['payment', 'writeoff', 'debtor', 'other'],
            enabled: editable && !widget.market,
            onChanged: (v) => setState(() => _corr = v),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _comment,
          enabled: editable,
          decoration: coreInput('Izoh'),
        ),
      ],
    ));
  }

  Widget _linesSection(String title, {required int flag, required bool editable}) {
    final lines = _lines.where((l) => l.flag == flag).toList();
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            if (editable)
              TextButton.icon(
                onPressed: () => _addLine(flag: flag),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tovar'),
              ),
          ],
        ),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Qator yo\'q — «+ Tovar» bilan qo\'shing',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
          ),
        for (final l in lines) _lineRow(l, editable),
      ],
    ));
  }

  Widget _lineRow(_LineEdit l, bool editable) {
    final sklad = _skladForFlag(l.flag);
    final stockRow = sklad == null
        ? null
        : context.select<CoreStockProvider, CoreStockRow?>(
            (s) => s.rowFor(sklad, l.good.id));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kCoreBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.good.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (stockRow != null)
                Text(
                  'qoldiq: ${coreFormatQtyUnit(stockRow.qty, stockRow.baseUnit)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: stockRow.qty < 0 ? Colors.red : Colors.grey.shade600),
                ),
              if (editable)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _lines.remove(l);
                    l.dispose();
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: l.qty,
                  enabled: editable,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: coreInput('Miqdor'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('u-${l.good.id}-${l.unit.unit}'),
                  initialValue: l.unit.unit,
                  isExpanded: true,
                  decoration: coreInput('Birlik'),
                  items: [
                    for (final u in l.good.selectableUnits)
                      DropdownMenuItem(value: u.unit, child: Text(u.unit)),
                  ],
                  onChanged: !editable
                      ? null
                      : (v) {
                          final u = l.good.selectableUnits
                              .firstWhere((e) => e.unit == v, orElse: () => l.unit);
                          setState(() => l.unit = u);
                        },
                ),
              ),
              if (hasPrice) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: l.price,
                    enabled: editable,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: coreInput('Narx / ${l.unit.unit}'),
                  ),
                ),
              ],
            ],
          ),
          if (hasPrice)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('= ${coreMoney(l.amount)} so\'m',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          if (hasSale)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: l.sale,
                enabled: editable,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: coreInput('Sotuv summasi (ixtiyoriy, so\'m)'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalCard() {
    if (!hasPrice && !hasSale) return const SizedBox.shrink();
    return _card(Column(
      children: [
        if (hasPrice)
          Row(
            children: [
              const Expanded(
                  child: Text('Jami', style: TextStyle(fontWeight: FontWeight.bold))),
              Text('${coreMoney(_total)} so\'m',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        if (hasSale)
          Row(
            children: [
              const Expanded(
                  child: Text('Sotuv summasi',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              Text('${coreMoney(_totalSale)} so\'m',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
      ],
    ));
  }

  Widget _actions({required bool canCreate, required bool canPost}) {
    final isNew = widget.existing == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: _busy
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Row(
                children: [
                  if (!isNew)
                    IconButton(
                      tooltip: 'O\'chirish',
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                    ),
                  if (widget.market)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: canPost ? () => _save(post: true, quick: true) : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kCoreAccent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46)),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Saqlash va tasdiqlash'),
                      ),
                    )
                  else ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canCreate ? () => _save(post: false) : null,
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46)),
                        child: const Text('Saqlash'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canPost && (canCreate || !isNew)
                            ? () => _save(post: true)
                            : null,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kCoreAccent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46)),
                        child: const Text('Tasdiqlash'),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ───────────────────────── Inventarizatsiya formasi ─────────────────────────

class _InventoryForm extends StatefulWidget {
  final CoreDoc? existing;
  const _InventoryForm({this.existing});

  @override
  State<_InventoryForm> createState() => _InventoryFormState();
}

class _InventoryFormState extends State<_InventoryForm> {
  late String _date;
  int? _sklad;
  final _comment = TextEditingController();
  final _search = TextEditingController();
  String _q = '';
  bool _onlyDiff = false;
  bool _busy = false;
  // good_id → fakt matni (UI birlikda). Bo'sh — yuborilmaydi.
  final Map<int, TextEditingController> _fact = {};
  // Qoldiqda yo'q, qo'lda qo'shilgan tovarlar.
  final List<CoreGood> _extra = [];
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.docDate ?? todayIso();
    _sklad = widget.existing?.toSklad;
    _comment.text = widget.existing?.comment ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    final dict = context.read<CoreDictProvider>();
    final user = context.read<CoreSession>().user;
    if (_sklad == null && user != null && user.sklads.length == 1) {
      _sklad = user.sklads.first;
    }
    if (_sklad == null && dict.activeSklads.length == 1) {
      _sklad = dict.activeSklads.first.id;
    }
    final ex = widget.existing;
    if (ex != null) {
      for (final l in ex.lines) {
        final good = dict.goodById(l.goodId) ??
            CoreGood(
                id: l.goodId,
                name: l.goodName,
                baseUnit: coreBaseUnitOf(l.unit),
                partial: true);
        _extra.add(good);
        _ctrl(good.id).text = coreFormatQty(l.qty, good.baseUnit);
      }
      dict.ensureGoods(ex.lines.map((l) => l.goodId));
    }
    if (_sklad != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadStock(_sklad!);
      });
    }
  }

  // Qoldiqni yuklash; qatorlardagi tovar nomi/base birligi dict keshiga.
  // Orqa sana bo'lsa hisob qoldig'i O'SHA kun oxiriga olinadi (`?date=`) —
  // aks holda inventar farqi bugungi qoldiqqa nisbatan chiqib ketardi.
  void _loadStock(int skladId) {
    final stock = context.read<CoreStockProvider>();
    final dict = context.read<CoreDictProvider>();
    stock.onRows = (rows) => dict.cacheGoods(rows.map((r) => r.toGood()));
    final today = todayIso();
    stock.load(skladId, date: _date == today ? null : _date, nonzero: true);
  }

  // Ekrandagi qatorlar tovarlari (qoldiqdan yoki qo'lda) — `_build` uchun.
  final Map<int, CoreGood> _goodsById = {};

  TextEditingController _ctrl(int goodId) =>
      _fact.putIfAbsent(goodId, () => TextEditingController());

  @override
  void dispose() {
    _comment.dispose();
    _search.dispose();
    for (final c in _fact.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Qatorlar: qoldiqdagi tovarlar + qo'lda qo'shilganlar (takrorsiz).
  List<_InvRow> _rows(CoreDictProvider dict, List<CoreStockRow> stock) {
    final rows = <_InvRow>[];
    final seen = <int>{};
    for (final r in stock) {
      final good = dict.goodById(r.goodId) ?? r.toGood();
      seen.add(r.goodId);
      _goodsById[good.id] = good;
      rows.add(_InvRow(good: good, current: r.qty));
    }
    for (final g in _extra) {
      _goodsById.putIfAbsent(g.id, () => g);
      if (seen.add(g.id)) {
        // Qo'lda qo'shilgan tovarning joriy qoldig'i (keshda bo'lsa).
        final cur = context.read<CoreStockProvider>().qtyFor(_sklad ?? 0, g.id);
        rows.add(_InvRow(good: g, current: cur));
      }
    }
    final q = _q.toLowerCase();
    return rows.where((r) {
      if (q.isNotEmpty && !r.good.name.toLowerCase().contains(q)) return false;
      if (_onlyDiff) {
        final fact = parseUiQty(_fact[r.good.id]?.text);
        if (fact == null) return false;
        final factBase = coreQtyFromUi(fact, r.good.preferredUnit);
        return factBase != r.current;
      }
      return true;
    }).toList();
  }

  CoreDoc _build(CoreDictProvider dict) {
    final lines = <CoreDocLine>[];
    _fact.forEach((goodId, c) {
      final v = parseUiQty(c.text);
      if (v == null) return; // bo'sh — yuborilmaydi
      // Keshdagi to'liq karta ustun (is_complect ma'lum), bo'lmasa ekrandagi.
      final good = dict.goodById(goodId) ?? _goodsById[goodId];
      if (good == null) return;
      final unit = good.preferredUnit;
      lines.add(CoreDocLine(
        goodId: goodId,
        goodName: good.name,
        unit: unit.unit,
        qty: coreQtyFromUi(v, unit),
        // Ledger: inventory qatorida flag 1 = tayyor mahsulot (taom) fakti —
        // retsept bo'yicha ingredientlarga yoyiladi; 0 = xom ashyo.
        flag: good.isComplect ? 1 : 0,
      ));
    });
    return CoreDoc(
      id: widget.existing?.id ?? 0,
      type: CoreDocType.inventory,
      docDate: _date,
      toSklad: _sklad,
      comment: _comment.text.trim(),
      lines: lines,
    );
  }

  Future<void> _save({required bool post}) async {
    if (_sklad == null) {
      showCoreInfo(context, 'Omborni tanlang');
      return;
    }
    final dict = context.read<CoreDictProvider>();
    final docs = context.read<CoreDocsProvider>();
    final stock = context.read<CoreStockProvider>();
    setState(() => _busy = true);
    try {
      // Fakt kiritilgan tovarlarning to'liq kartasi (is_complect → flag).
      await dict.ensureGoods(_fact.entries
          .where((e) => parseUiQty(e.value.text) != null)
          .map((e) => e.key));
      if (!mounted) return;
      final doc = _build(dict);
      if (doc.lines.isEmpty) {
        showCoreInfo(context, 'Hech bir tovarga fakt kiritilmadi');
        return;
      }
      CoreDoc saved = doc.id > 0
          ? await docs.update(doc.id, doc)
          : await docs.create(doc);
      List<CoreDocWarning> warnings = const [];
      if (post) {
        final res = await docs.post(saved.id);
        saved = res.doc;
        warnings = res.warnings;
      }
      if (!mounted) return;
      if (warnings.isNotEmpty) await showWarningsDialog(context, warnings);
      if (!mounted) return;
      stock.refreshSklads([saved.toSklad]);
      context.pushReplacement(DocDetailUi(docId: saved.id, initial: saved));
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    final dict = context.watch<CoreDictProvider>();
    final stockP = context.watch<CoreStockProvider>();
    final stock = _sklad == null ? const <CoreStockRow>[] : (stockP.rowsFor(_sklad!) ?? const []);
    final loading = _sklad != null && stockP.isLoading(_sklad!);
    final rows = _rows(dict, stock);
    final editable = widget.existing == null || widget.existing!.isDraft;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: CoreSkladDropdown(
                      value: _sklad,
                      label: 'Ombor',
                      enabled: editable,
                      onChanged: (v) {
                        setState(() => _sklad = v);
                        if (v != null) _loadStock(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: !editable
                        ? null
                        : () async {
                            final d = await pickDate(context, _date,
                                allowPast: session.canBackdate);
                            if (d == null || d == _date) return;
                            setState(() => _date = d);
                            // Hisob qoldig'i sana bo'yicha qayta olinadi.
                            if (_sklad != null) _loadStock(_sklad!);
                          },
                    child: InputDecorator(
                      decoration: coreInput('Sana'),
                      child: Text(coreDate(_date)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _q = v),
                      decoration: coreInput('Qidirish',
                          suffix: const Icon(Icons.search, size: 18)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Faqat farqlilar', style: TextStyle(fontSize: 12)),
                    selected: _onlyDiff,
                    selectedColor: kCoreAccent.withValues(alpha: 0.25),
                    onSelected: (v) => setState(() => _onlyDiff = v),
                  ),
                  if (editable)
                    IconButton(
                      tooltip: 'Tovar qo\'shish',
                      onPressed: () async {
                        final g = await pickCoreGood(context, skladId: _sklad);
                        if (g != null && mounted) setState(() => _extra.add(g));
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _sklad == null
              ? const Center(child: Text('Omborni tanlang'))
              : loading && stock.isEmpty
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _invRow(rows[i], editable),
                    ),
        ),
        if (editable)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: _busy
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: session.canCreate(CoreDocType.inventory)
                                ? () => _save(post: false)
                                : null,
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46)),
                            child: const Text('Saqlash'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: session.canPost(CoreDocType.inventory)
                                ? () => _save(post: true)
                                : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: kCoreAccent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46)),
                            child: const Text('Tasdiqlash'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  Widget _invRow(_InvRow r, bool editable) {
    final unit = r.good.preferredUnit;
    final ctrl = _ctrl(r.good.id);
    final fact = parseUiQty(ctrl.text);
    final factBase = fact == null ? null : coreQtyFromUi(fact, unit);
    final delta = factBase == null ? null : factBase - r.current;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: delta != null && delta != 0
                ? (delta < 0 ? Colors.red.shade300 : Colors.green.shade300)
                : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.good.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  'hisob: ${coreFormatQtyUnit(r.current, r.good.baseUnit)}'
                  '${delta == null ? '' : '  ·  farq: ${delta > 0 ? '+' : ''}${coreFormatQty(delta, r.good.baseUnit)}'}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: delta != null && delta != 0
                          ? (delta < 0 ? Colors.red.shade700 : Colors.green.shade700)
                          : Colors.grey.shade600),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: ctrl,
              enabled: editable,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => setState(() {}),
              decoration: coreInput('Fakt, ${unit.unit}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvRow {
  final CoreGood good;
  final int current;
  const _InvRow({required this.good, required this.current});
}
