// core2/ui/distribute_ui.dart — «Tarqatish» (Перемещение × bir nechta ombor).
//
// Nega kerak (SH5_BIZNES_MANTIQ P14, P11): «Оператор Цех» bir xil tovarlarni
// «Резка и Украшение» dan 4 do'konga kuniga ~24 marta ketma-ket ko'chiradi —
// SH5 da bu 4 ta alohida hujjat, aslida esa BITTA tarqatish vedomosti.
// Shu ekranda tovar BIR MARTA qo'shiladi, miqdorlar matritsada (qatorlar =
// tovarlar, ustunlar = do'konlar) kiritiladi va BITTA so'rov yuboriladi:
// `POST /docs/quick-batch` (CORE_DEBT_KONTRAKT §3) — nechta ustunda miqdor
// bo'lsa shuncha ko'chirish hujjati, hammasi bitta tranzaksiyada.
//
// Tartib: telefon — kataklar bosilsa miqdor klaviaturasi (qty_keypad);
// kompyuter (≥900 px) — kataklar tahrirlanadi (Tab — keyingi katak,
// Enter — shu ustunda pastki katak).
//
// Umumiy qismlar `widgets/good_search.dart` dan (qidiruv + «Tez-tez»
// chiplari), sof mantiq — `distribute_logic.dart` (matritsa → so'rov tanasi,
// jamlar, qoldiqdan oshib ketish, tekshiruv).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';
import 'package:uz_ai_dev/core2/ui/distribute_logic.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_search.dart';
import 'package:uz_ai_dev/core2/ui/widgets/qty_keypad.dart';

/// Ikki panel / tahrirlanadigan kataklar chegarasi (quick_doc_ui bilan bir xil).
const double kDistWideBreakpoint = 900;

class DistributeUi extends StatefulWidget {
  /// Manba ombor («Bugun» dagi ombor) — standart «qayerdan».
  final int? skladId;

  const DistributeUi({super.key, this.skladId});

  @override
  State<DistributeUi> createState() => _DistributeUiState();
}

/// Matritsa qatori: tovar + tanlangan kiritish birligi.
class _DRow {
  final CoreGood good;
  CoreGoodUnit unit;
  _DRow({required this.good, required this.unit});
}

class _DistributeUiState extends State<DistributeUi> {
  final CoreDocService _docService = CoreDocService();

  int? _from;
  List<int> _dests = [];
  final List<_DRow> _rows = [];

  /// good_id → (sklad_id → BUTUN base miqdor).
  final Map<int, Map<int, int>> _qty = {};

  late String _date;
  final _comment = TextEditingController();
  bool _showComment = false;

  List<CoreFreqGood> _freq = const [];
  bool _busy = false;
  bool _initDone = false;

  /// Xato bergan ustun (`details.index` → ombor) va matni — grid saqlanadi.
  int? _errDest;
  String? _errText;

  // Kompyuter tartibidagi tahrirlanadigan kataklar.
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _nodes = {};

  @override
  void initState() {
    super.initState();
    _date = coreToday();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    final dict = context.read<CoreDictProvider>();
    final session = context.read<CoreSession>();
    _from = widget.skladId ??
        (session.user?.sklads.isNotEmpty == true
            ? session.user!.sklads.first
            : (dict.activeSklads.length == 1 ? dict.activeSklads.first.id : null));
    _restoreDests();
    _afterFromChanged();
  }

  @override
  void dispose() {
    _comment.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  // ───────────────────────── Eslab qolish ─────────────────────────

  /// Oxirgi tanlangan omborlar — foydalanuvchi + MANBA ombor bo'yicha
  /// (bir qurilmada bir necha xodim, har sexda boshqa yo'nalish).
  String get _prefKey {
    final uid = context.read<CoreSession>().user?.id ?? 0;
    return 'core_dist_dests_u${uid}_s${_from ?? 0}';
  }

  Future<void> _restoreDests() async {
    if (_from == null) return;
    final key = _prefKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty || !mounted) return;
      final ids = (jsonDecode(raw) as List)
          .whereType<num>()
          .map((e) => e.toInt())
          .toList();
      final active = context.read<CoreDictProvider>().activeSklads
          .map((s) => s.id)
          .toSet();
      final keep = [
        for (final id in ids)
          if (id != _from && (active.isEmpty || active.contains(id))) id,
      ];
      if (keep.isEmpty) return;
      setState(() => _dests = keep.take(kDistMaxDests).toList());
    } catch (_) {
      // Kesh buzilgan / SharedPreferences yo'q — tanlov bo'sh qoladi.
    }
  }

  Future<void> _saveDests() async {
    if (_from == null || _dests.isEmpty) return;
    final key = _prefKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(_dests));
    } catch (_) {
      // Saqlanmasa ham ekran ishlaydi.
    }
  }

  // ───────────────────────── Yuklashlar ─────────────────────────

  void _afterFromChanged() {
    final from = _from;
    if (from == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoreStockProvider>().ensure(from);
    });
    _loadFreq(from);
  }

  Future<void> _loadFreq(int sklad) async {
    final list = await CoreFreqGood.load(
      service: _docService,
      skladId: sklad,
      type: CoreDocType.transfer,
    );
    if (!mounted) return;
    setState(() => _freq = list);
  }

  // ───────────────────────── Matritsa holati ─────────────────────────

  String _key(int goodId, int skladId) => '$goodId:$skladId';

  int _qtyOf(int goodId, int skladId) => _qty[goodId]?[skladId] ?? 0;

  void _setQty(int goodId, int skladId, int baseQty) {
    final row = _qty.putIfAbsent(goodId, () => {});
    if (baseQty <= 0) {
      row.remove(skladId);
    } else {
      row[skladId] = baseQty;
    }
  }

  /// Manba ombordagi qoldiq (base) — qator jamini solishtirish uchun.
  int _stockOf(int goodId) {
    final from = _from;
    if (from == null) return 0;
    return context.read<CoreStockProvider>().qtyFor(from, goodId);
  }

  List<DistGoodRow> _logicRows() => [
        for (final r in _rows)
          DistGoodRow(
            goodId: r.good.id,
            name: r.good.name,
            unit: r.unit.unit,
            stock: _stockOf(r.good.id),
          ),
      ];

  void _addGood(CoreGood good) {
    if (_rows.any((r) => r.good.id == good.id)) {
      showInfoUz(context, '«${good.name}» ro\'yxatda bor');
      return;
    }
    setState(() => _rows.add(_DRow(good: good, unit: good.preferredUnit)));
  }

  void _removeRow(int index) {
    final row = _rows[index];
    for (final d in _dests) {
      final k = _key(row.good.id, d);
      _ctrls.remove(k)?.dispose();
      _nodes.remove(k)?.dispose();
    }
    setState(() {
      _qty.remove(row.good.id);
      _rows.removeAt(index);
    });
  }

  Future<void> _openFreq(CoreFreqGood f) async {
    final good =
        await CoreFreqGood.resolve(context.read<CoreDictProvider>(), f);
    if (!mounted) return;
    _addGood(good);
  }

  // ───────────────────────── Omborlar ─────────────────────────

  Future<void> _pickFrom() async {
    final list = context.read<CoreDictProvider>().activeSklads;
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SkladPickSheet(
          title: 'Qaysi ombordan', items: list, current: {if (_from != null) _from!}),
    );
    if (id == null || !mounted) return;
    setState(() {
      _from = id;
      _dests = _dests.where((d) => d != id).toList();
      _errDest = null;
      _errText = null;
    });
    _restoreDests();
    _afterFromChanged();
  }

  Future<void> _pickDests() async {
    final list = context
        .read<CoreDictProvider>()
        .activeSklads
        .where((s) => s.id != _from)
        .toList();
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SkladPickSheet(
        title: 'Qaysi omborlarga',
        items: list,
        current: _dests.toSet(),
        multi: true,
        maxCount: kDistMaxDests,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Tartib: avvalgi tanlov tartibi saqlanadi, yangilari oxiriga.
      final keep = [
        for (final d in _dests)
          if (picked.contains(d)) d,
      ];
      for (final d in picked) {
        if (!keep.contains(d)) keep.add(d);
      }
      _dests = keep.take(kDistMaxDests).toList();
      _errDest = null;
      _errText = null;
    });
    _saveDests();
  }

  // ───────────────────────── Katak tahriri ─────────────────────────

  Future<void> _openCell(int rowIndex, int destIndex) async {
    final row = _rows[rowIndex];
    final dest = _dests[destIndex];
    final cur = _qtyOf(row.good.id, dest);
    final res = await showQtyKeypad(
      context,
      good: row.good,
      skladId: _from,
      initial: QtyKeypadResult(baseQty: cur, unit: row.unit),
      okText: 'Saqlash',
    );
    if (res == null || !mounted) return;
    setState(() {
      row.unit = res.unit;
      _setQty(row.good.id, dest, res.baseQty);
      _ctrls[_key(row.good.id, dest)]?.text =
          res.baseQty <= 0 ? '' : coreQtyInUnitUz(res.baseQty, res.unit);
    });
  }

  TextEditingController _ctrlFor(_DRow row, int dest) {
    final k = _key(row.good.id, dest);
    return _ctrls.putIfAbsent(k, () {
      final q = _qtyOf(row.good.id, dest);
      return TextEditingController(
          text: q <= 0 ? '' : coreQtyInUnitUz(q, row.unit));
    });
  }

  FocusNode _nodeFor(int goodId, int dest) =>
      _nodes.putIfAbsent(_key(goodId, dest), () => FocusNode());

  /// Enter: shu USTUNDA pastki katak (tarqatishda bir do'kon ustunini
  /// to'ldirib chiqish tabiiy).
  void _focusDown(int rowIndex, int destIndex) {
    final next = rowIndex + 1;
    if (next >= _rows.length) return;
    _nodeFor(_rows[next].good.id, _dests[destIndex]).requestFocus();
  }

  void _onCellText(_DRow row, int dest, String text) {
    final ui = parseUiQty(text) ?? 0;
    setState(() => _setQty(row.good.id, dest, coreQtyFromUi(ui, row.unit)));
  }

  // ───────────────────────── Yuborish ─────────────────────────

  Future<void> _submit() async {
    final rows = _logicRows();
    final err = distValidate(
      fromSklad: _from,
      dests: _dests,
      rows: rows,
      qtyOf: _qtyOf,
    );
    if (err != null) {
      showInfoUz(context, err);
      return;
    }
    final batch = distBuildBatch(
      fromSklad: _from!,
      dests: _dests,
      rows: rows,
      qtyOf: _qtyOf,
      docDate: _date,
      comment: _comment.text,
    );
    final docs = context.read<CoreDocsProvider>();
    final stock = context.read<CoreStockProvider>();
    setState(() {
      _busy = true;
      _errDest = null;
      _errText = null;
    });
    try {
      final res = await docs.quickBatch(batch.docs);
      if (!mounted) return;
      await _saveDests();
      stock.refreshSklads([_from, ...batch.dests]);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DistributeResultUi(result: res, skladId: _from),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // `details.index` — nechanchi hujjat xato berdi → o'sha ustun qizil.
      final err = _errorDest(e, batch);
      setState(() {
        _errDest = err;
        _errText = coreIsMissingEndpoint(e)
            ? kCoreOldServerMsg
            : coreErrorUz(e,
                    skladName: context.read<CoreDictProvider>().skladName)
                .text;
      });
      showNewApiErrorUz(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _errorDest(Object e, DistBatch batch) {
    try {
      final err = e is CoreApiException ? e : null;
      if (err == null) return null;
      return batch.destOfIndex(err.details['index']);
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── Ko'rinish ─────────────────────────

  @override
  Widget build(BuildContext context) {
    // Qoldiq fonda yuklanadi — kelganda qatorlardagi «qoldiq: …» yangilansin.
    context.watch<CoreStockProvider>();
    final wide = MediaQuery.of(context).size.width >= kDistWideBreakpoint;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tarqatish',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('Перемещение × bir nechta ombor',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                children: [
                  _headerCard(),
                  const SizedBox(height: 8),
                  CoreGoodSearchPanel(
                    skladId: _from,
                    onPicked: _addGood,
                    hint: 'Tovar qidirish (bir marta qo\'shiladi)…',
                    maxHeight: wide ? 360 : 280,
                  ),
                  if (_freq.isNotEmpty)
                    CoreFreqChips(items: _freq, onPick: _openFreq),
                  const SizedBox(height: 10),
                  if (_errText != null) ...[
                    _errorCard(),
                    const SizedBox(height: 8),
                  ],
                  _matrix(wide),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final dict = context.watch<CoreDictProvider>();
    final session = context.watch<CoreSession>();
    final backdated = _date != coreToday();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(
                icon: Icons.warehouse_outlined,
                label: _from == null ? 'Qaysi ombordan?' : dict.skladName(_from),
                warn: _from == null,
                onTap: _pickFrom,
              ),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _chip(
                icon: Icons.storefront_outlined,
                label: _dests.isEmpty
                    ? 'Qaysi omborlarga?'
                    : '${_dests.length} ta ombor',
                sub: _dests.isEmpty
                    ? null
                    : _dests.map(dict.skladName).join(', '),
                warn: _dests.length < kDistMinDests,
                onTap: _pickDests,
              ),
              _chip(
                icon: Icons.event,
                label: coreDayUz(_date),
                warn: backdated,
                onTap: () async {
                  final d = await pickDate(context, _date,
                      allowPast: session.canBackdate);
                  if (d != null && mounted) setState(() => _date = d);
                },
              ),
              _chip(
                icon: Icons.chat_bubble_outline,
                label: _showComment ? 'Izoh' : 'Izoh qo\'shish',
                onTap: () => setState(() => _showComment = !_showComment),
              ),
            ],
          ),
          if (backdated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Orqa sana: hujjatlar ${coreDateUz(_date)} kuniga yoziladi',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
              ),
            ),
          if (_showComment)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _comment,
                decoration: coreInput('Izoh (hamma hujjatga)',
                    hint: 'masalan: tarqatish 04:00'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    String? sub,
    VoidCallback? onTap,
    bool warn = false,
  }) {
    final color = warn ? Colors.orange.shade800 : kCoreAccentDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  if (sub != null)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.expand_more, size: 15, color: color),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_errText!, style: const TextStyle(fontSize: 12.5)),
                  if (_errDest != null)
                    Text(
                      'Xato ustun: ${context.read<CoreDictProvider>().skladName(_errDest)}. '
                      'Hech qanday hujjat yaratilmadi — tuzatib, qayta yuboring.',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.red.shade900),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Matritsa ──

  Widget _matrix(bool wide) {
    if (_dests.length < kDistMinDests) {
      return _hint('Avval $kDistMinDests ta yoki undan ko\'p qabul qiluvchi '
          'omborni tanlang (eng ko\'pi $kDistMaxDests ta)');
    }
    if (_rows.isEmpty) {
      return _hint('Tovar qidiring yoki «Tez-tez» dan tanlang — '
          'har bir tovar BIR MARTA qo\'shiladi');
    }
    const nameW = 180.0;
    const cellW = 104.0;
    final dict = context.watch<CoreDictProvider>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sarlavha: ombor nomlari.
            Row(
              children: [
                const SizedBox(width: nameW, child: _HeadCell('Tovar')),
                for (final d in _dests)
                  SizedBox(
                    width: cellW,
                    child: _HeadCell(
                      dict.skladName(d),
                      error: d == _errDest,
                    ),
                  ),
                const SizedBox(width: cellW, child: _HeadCell('Jami')),
              ],
            ),
            const Divider(height: 1),
            for (var i = 0; i < _rows.length; i++) ...[
              _matrixRow(i, wide, nameW, cellW),
              const Divider(height: 1),
            ],
            // Ustun jamlari.
            Row(
              children: [
                const SizedBox(
                  width: nameW,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Text('Ustun jami',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ),
                for (final d in _dests)
                  SizedBox(
                    width: cellW,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 10),
                      child: Text(
                        _colLabel(d),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                SizedBox(
                  width: cellW,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Text(
                      '${distFilledCells(_logicRows(), _dests, _qtyOf)} katak',
                      textAlign: TextAlign.end,
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Ustun jami: birliklar bir xil bo'lsa miqdor, aralash bo'lsa «N ta tovar»
  /// (kg va donani qo'shib bo'lmaydi).
  String _colLabel(int dest) {
    final s = distColumnSummary(dest, _logicRows(), _qtyOf);
    if (s.isEmpty) return '—';
    if (s.qty == null) return '${s.goods} ta tovar';
    return coreQtyUnitInUz(
        s.qty!, CoreGoodUnit(unit: s.unit, toBase: coreUnitFactor(s.unit)));
  }

  Widget _matrixRow(int i, bool wide, double nameW, double cellW) {
    final row = _rows[i];
    final stock = _stockOf(row.good.id);
    final total = distRowTotal(row.good.id, _dests, _qtyOf);
    final over = distRowOverStock(total, stock);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: nameW,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.good.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      Text(
                        'qoldiq: ${coreQtyUnitUz(stock, row.good.baseUnit)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: stock <= 0
                                ? Colors.red.shade700
                                : Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'O\'chirish',
                  onPressed: () => _removeRow(i),
                  icon: Icon(Icons.close, size: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        for (var j = 0; j < _dests.length; j++)
          SizedBox(
            width: cellW,
            child: _cell(i, j, wide),
          ),
        SizedBox(
          width: cellW,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total <= 0 ? '—' : coreQtyUnitInUz(total, row.unit),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: over ? Colors.red.shade700 : Colors.black87,
                  ),
                ),
                if (over)
                  Text('qoldiqdan ko\'p',
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.red.shade700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(int rowIndex, int destIndex, bool wide) {
    final row = _rows[rowIndex];
    final dest = _dests[destIndex];
    final q = _qtyOf(row.good.id, dest);
    final bad = dest == _errDest;
    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: TextField(
          controller: _ctrlFor(row, dest),
          focusNode: _nodeFor(row.good.id, dest),
          textAlign: TextAlign.end,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          textInputAction: TextInputAction.next,
          onChanged: (v) => _onCellText(row, dest, v),
          onSubmitted: (_) => _focusDown(rowIndex, destIndex),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: '0',
            suffixText: coreUnitUz(row.unit.unit),
            suffixStyle: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            filled: bad,
            fillColor: bad ? Colors.red.shade50 : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: bad ? Colors.red.shade300 : Colors.grey.shade300),
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _openCell(rowIndex, destIndex),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: bad
              ? Colors.red.shade50
              : (q > 0 ? kCoreAccent.withValues(alpha: 0.12) : kCoreBg),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: bad
                  ? Colors.red.shade300
                  : (q > 0 ? kCoreAccentDark : Colors.grey.shade300)),
        ),
        child: Text(
          q <= 0 ? '—' : coreQtyInUnitUz(q, row.unit),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: q > 0 ? Colors.black87 : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      );

  Widget _bottomBar() {
    final session = context.watch<CoreSession>();
    final can = session.canCreate(CoreDocType.transfer) &&
        session.canPost(CoreDocType.transfer);
    final rows = _logicRows();
    final docs = _dests
        .where((d) => distColumnTotal(d, rows, _qtyOf) > 0)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('${_rows.length} tovar · ${_dests.length} ombor',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                      const Spacer(),
                      Text('$docs ta hujjat',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: (can && docs > 0) ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('Saqlash va o\'tkazish ($docs ta hujjat)',
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.bold)),
                  ),
                  if (!can)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Ko\'chirishni o\'tkazish ruxsati yo\'q — '
                        'rahbaringizdan so\'rang',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.orange.shade900),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Matritsa sarlavha katagi (ombor nomi; xato bergan ustun qizil).
class _HeadCell extends StatelessWidget {
  final String text;
  final bool error;
  const _HeadCell(this.text, {this.error = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: error ? Colors.red.shade700 : Colors.black87,
        ),
      ),
    );
  }
}

// ───────────────────────── Ombor tanlash varag'i ─────────────────────────

/// Bitta yoki bir nechta ombor tanlash (multi — «Tanlash» tugmasi bilan).
class _SkladPickSheet extends StatefulWidget {
  final String title;
  final List<CoreSklad> items;
  final Set<int> current;
  final bool multi;
  final int maxCount;

  const _SkladPickSheet({
    required this.title,
    required this.items,
    required this.current,
    this.multi = false,
    this.maxCount = kDistMaxDests,
  });

  @override
  State<_SkladPickSheet> createState() => _SkladPickSheetState();
}

class _SkladPickSheetState extends State<_SkladPickSheet> {
  late final Set<int> _sel = {...widget.current};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = widget.items
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      if (widget.multi)
                        Text(
                          '${_sel.length} ta tanlandi · '
                          '$kDistMinDests–${widget.maxCount} ta',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (widget.items.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: coreInput('Qidirish',
                    suffix: const Icon(Icons.search, size: 18)),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = items[i];
                final on = _sel.contains(s.id);
                return ListTile(
                  dense: true,
                  title: Text(s.name),
                  trailing: widget.multi
                      ? Checkbox(
                          value: on,
                          onChanged: (_) => _toggle(s.id),
                        )
                      : (on
                          ? Icon(Icons.check, color: Colors.green.shade700)
                          : null),
                  onTap: () {
                    if (widget.multi) {
                      _toggle(s.id);
                    } else {
                      Navigator.pop(context, s.id);
                    }
                  },
                );
              },
            ),
          ),
          if (widget.multi)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SafeArea(
                top: false,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _sel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCoreAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text('Tanlash (${_sel.length})'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggle(int id) {
    setState(() {
      if (_sel.contains(id)) {
        _sel.remove(id);
      } else if (_sel.length < widget.maxCount) {
        _sel.add(id);
      } else {
        showInfoUz(context,
            'Eng ko\'pi bilan ${widget.maxCount} ta ombor tanlanadi');
      }
    });
  }
}

// ───────────────────────────── Natija ekrani ─────────────────────────────

/// Tarqatish natijasi: yaratilgan hujjatlar ro'yxati (raqam + ombor) va
/// birlashtirilgan ogohlantirishlar (kod bo'yicha guruhlangan —
/// quick_doc_result_ui.dart dagidek, har qatorda qaysi ombor ekani bilan).
class DistributeResultUi extends StatefulWidget {
  final CoreDocBatchResult result;
  final int? skladId;

  const DistributeResultUi({super.key, required this.result, this.skladId});

  @override
  State<DistributeResultUi> createState() => _DistributeResultUiState();
}

class _DistributeResultUiState extends State<DistributeResultUi> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ids =
          widget.result.warnings.map((w) => w.goodId ?? 0).where((id) => id > 0);
      if (ids.isNotEmpty) context.read<CoreDictProvider>().ensureGoods(ids);
    });
  }

  CoreDocBatchResult get res => widget.result;

  /// Ogohlantirish qaysi omborga tegishli («M1: …» o'rniga ombor nomi).
  String _destOf(CoreDocWarning w) {
    if (w.docIndex < 0 || w.docIndex >= res.docs.length) return '';
    return context.read<CoreDictProvider>().skladName(res.docs[w.docIndex].toSklad);
  }

  @override
  Widget build(BuildContext context) {
    final dict = context.watch<CoreDictProvider>();
    final groups = coreGroupWarnings(res.warnings);
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Bajarildi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _successCard(dict),
          const SizedBox(height: 12),
          for (var i = 0; i < res.docs.length; i++) _docTile(res.docs[i], i, dict),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in groups.entries) _warnCard(e.key, e.value, dict),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DistributeUi(skladId: widget.skladId),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Yana',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Bosh sahifa'),
          ),
        ],
      ),
    );
  }

  Widget _successCard(CoreDictProvider dict) {
    final from = res.docs.isEmpty ? null : res.docs.first.fromSklad;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, size: 60, color: Colors.green.shade600),
          const SizedBox(height: 10),
          Text('${res.docs.length} ta ko\'chirish o\'tkazildi',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${from == null ? '' : '${dict.skladName(from)} → '}'
            '${res.docs.map((d) => dict.skladName(d.toSklad)).join(', ')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (res.existing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${res.existing.length} tasi avvaldan mavjud edi — qayta '
                'yaratilmadi',
                style:
                    TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
              ),
            ),
        ],
      ),
    );
  }

  Widget _docTile(CoreDoc d, int index, CoreDictProvider dict) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: kCoreAccent.withValues(alpha: 0.2),
          child: Text('${index + 1}',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold)),
        ),
        title: Text(dict.skladName(d.toSklad),
            style:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '№ ${d.number.isEmpty ? d.id : d.number} · ${d.lines.length} qator'
          '${d.total > 0 ? ' · ${coreSumUz(d.total)}' : ''}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DocDetailUi(docId: d.id, initial: d),
          ),
        ),
      ),
    );
  }

  Widget _warnCard(
      String code, List<CoreDocWarning> list, CoreDictProvider dict) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(coreWarnIconUz(code), color: Colors.orange.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${coreWarnTitleUz(code)} · ${list.length} ta',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(coreWarnHintUz(code),
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          const SizedBox(height: 6),
          for (final w in list.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${_name(w, dict)} — ${_qty(w, dict)}'
                '${_destOf(w).isEmpty ? '' : ' · ${_destOf(w)}'}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          if (list.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('… va yana ${list.length - 8} ta',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }

  String _name(CoreDocWarning w, CoreDictProvider dict) {
    if (w.goodName.isNotEmpty) return w.goodName;
    return dict.goodById(w.goodId)?.name ?? 'Tovar #${w.goodId ?? 0}';
  }

  String _qty(CoreDocWarning w, CoreDictProvider dict) {
    final g = dict.goodById(w.goodId);
    return g == null ? '${w.qty}' : coreQtyUnitUz(w.qty, g.baseUnit);
  }
}
