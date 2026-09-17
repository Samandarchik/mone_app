// core2/ui/inventory_count_ui.dart — «SANASH» (inventarizatsiya) oson rejimi.
//
// Oqim: ombor + sana → shu ombordagi qoldiqli tovarlar guruh bo'yicha
// bo'limlarga yig'iladi → har qatorga FAKT kiritiladi (telefonda
// `CountKeypad` pastki varaqda, kompyuterda jadval katagiga to'g'ridan-to'g'ri
// yoziladi, Enter/Tab keyingi katakka) → «Yakunlash» xulosasi (kamomad /
// ortiqcha, so'm faqat `stock.cost.view` bo'lsa) → «Tasdiqlash» (post).
//
// Muhim qoidalar (mavjud `doc_form_ui.dart` dagi `_InventoryForm` mantig'i,
// 68443b2 da tuzatilgan — shu yerda qayta ishlatilgan):
//  • hisob qoldig'i SANA bo'yicha olinadi (`GET /stock?date=` — orqa sana
//    bo'lsa o'sha kun oxiriga), aks holda farq bugungi qoldiqqa chiqib ketardi;
//  • qator `flag` = tovar `is_complect` bo'lsa 1 (tayyor fakt, yoyilmaydi),
//    aks holda 0 — shuning uchun saqlashdan oldin `ensureGoods` bilan TO'LIQ
//    tovar kartasi olinadi (`partial` kartada `is_complect` ishonchsiz);
//  • fakt kiritilmagan qator hujjatga YUBORILMAYDI (hisob o'zgarmaydi);
//  • miqdor serverga butun BASE birlikda (g/ml/mpcs/mm) ketadi.
//
// Avto-saqlash: har o'zgarishdan 2 s keyin qoralama saqlanadi (birinchi marta
// `POST /docs`, keyin `PUT /docs/{id}`); tarmoq xatosida qayta urinadi va
// tepada «saqlanmadi» belgisi ko'rinadi. `docId` berilsa (yoki shu ombor+sana
// uchun qoralama topilsa) sanash davom ettiriladi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/count_keypad.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_picker.dart';

/// Kompyuter ko'rinishi (jadval) shu kenglikdan boshlanadi.
const double _kWideBreakpoint = 900;

class InventoryCountUi extends StatefulWidget {
  const InventoryCountUi({super.key, this.skladId, this.docId});

  /// Boshlang'ich ombor («Bugun» sahifasidagi ombor tanlagichdan).
  final int? skladId;

  /// Davom ettiriladigan qoralama hujjat.
  final int? docId;

  @override
  State<InventoryCountUi> createState() => _InventoryCountUiState();
}

/// Saqlash holati — tepadagi belgi.
enum _SaveState { idle, dirty, saving, saved, failed }

class _InventoryCountUiState extends State<InventoryCountUi> {
  // ── Lug'at/kesh providerlari (timer ichida `context` ishlatmaslik uchun) ──
  late CoreDictProvider _dict;
  late CoreDocsProvider _docs;
  late CoreStockProvider _stockP;

  /// Qoralama qidirish uchun (umumiy ro'yxat filtrlarini buzmaslik kerak).
  final CoreDocService _docService = CoreDocService();

  int? _sklad;
  String _date = todayIso();
  String _comment = '';

  /// good_id → fakt matni (tovarning ko'rsatish birligida: kg / l / dona).
  /// Bo'sh matn — «sanalmagan» (hujjatga yuborilmaydi).
  final Map<int, TextEditingController> _fact = {};
  final Map<int, FocusNode> _focus = {};

  /// Qoldiqda yo'q, qo'lda qo'shilgan tovarlar.
  final List<CoreGood> _extra = [];

  /// Ekranda ko'rinadigan tovarlar (qoldiq + qo'lda qo'shilganlar).
  final Map<int, CoreGood> _goodsById = {};

  /// Yopilgan guruh bo'limlari.
  final Set<String> _closed = {};

  final _search = TextEditingController();
  String _q = '';
  int _tab = 0; // 0 — hammasi, 1 — sanalmagan, 2 — farqli

  // ── Avto-saqlash ──
  int? _docId;
  Timer? _saveTimer;
  Timer? _retryTimer;
  _SaveState _saveState = _SaveState.idle;
  String? _saveError;
  bool _posting = false;

  bool _initDone = false;
  bool _loadingDoc = false;

  @override
  void initState() {
    super.initState();
    _sklad = widget.skladId;
    _docId = widget.docId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    _dict = context.read<CoreDictProvider>();
    _docs = context.read<CoreDocsProvider>();
    _stockP = context.read<CoreStockProvider>();
    final user = context.read<CoreSession>().user;
    if (_sklad == null && user != null && user.sklads.isNotEmpty) {
      _sklad = user.sklads.first;
    }
    if (_sklad == null && _dict.activeSklads.isNotEmpty) {
      _sklad = _dict.activeSklads.first.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_docId != null) {
        // Qoralamani davom ettirish: ombor/sana hujjatdan olinadi.
        await _openDraft(_docId!);
        return;
      }
      if (_sklad != null) _loadStock();
      await _offerExistingDraft();
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _search.dispose();
    for (final c in _fact.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  // ───────────────────────────── Yuklash ─────────────────────────────

  TextEditingController _ctrl(int goodId) =>
      _fact.putIfAbsent(goodId, () => TextEditingController());

  FocusNode _node(int goodId) => _focus.putIfAbsent(goodId, () => FocusNode());

  /// Hisob qoldig'i: orqa sana bo'lsa O'SHA kun oxiriga (`?date=`).
  void _loadStock() {
    final sklad = _sklad;
    if (sklad == null) return;
    _stockP.onRows = (rows) {
      _dict.cacheGoods(rows.map((r) => r.toGood()));
      // Guruh nomi va `is_complect` uchun to'liq kartalar (fonda).
      _dict.ensureGoods(rows.map((r) => r.goodId));
    };
    _stockP.load(sklad, date: _date == todayIso() ? null : _date, nonzero: true);
  }

  /// Qoralamani ochish (davom ettirish).
  Future<void> _openDraft(int id) async {
    setState(() => _loadingDoc = true);
    try {
      final doc = await _docs.fetch(id);
      if (!mounted) return;
      _applyDraft(doc);
      // Hisob qoldig'i hujjat sanasi/ombori bo'yicha qayta olinadi.
      _loadStock();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  void _applyDraft(CoreDoc doc) {
    _docId = doc.id;
    _date = doc.docDate;
    _sklad = doc.toSklad ?? _sklad;
    _comment = doc.comment;
    for (final l in doc.lines) {
      final good = _dict.goodById(l.goodId) ??
          CoreGood(
            id: l.goodId,
            name: l.goodName,
            baseUnit: coreBaseUnitOf(l.unit),
            partial: true,
          );
      _goodsById.putIfAbsent(good.id, () => good);
      if (!_extra.any((g) => g.id == good.id)) _extra.add(good);
      _ctrl(good.id).text = coreQtyUz(l.qty, good.baseUnit);
    }
    _dict.ensureGoods(doc.lines.map((l) => l.goodId));
    _saveState = _SaveState.saved;
    setState(() {});
  }

  /// Shu ombor + sana uchun tugallanmagan qoralama bo'lsa — davom ettirishni
  /// taklif qiladi.
  Future<void> _offerExistingDraft() async {
    final sklad = _sklad;
    if (sklad == null) return;
    try {
      final page = await _docService.list(
        type: CoreDocType.inventory,
        status: CoreDocStatus.draft,
        sklad: sklad,
        dateFrom: _date,
        dateTo: _date,
        limit: 5,
      );
      if (!mounted || page.items.isEmpty) return;
      final found = page.items.first;
      final ok = await confirmDialog(
        context,
        'Tugallanmagan sanash bor',
        '${coreDateUz(found.docDate)} · ${_dict.skladName(found.toSklad)}\n'
            'Oldin boshlangan sanashni davom ettirasizmi?',
        okText: 'Davom ettirish',
      );
      if (!mounted) return;
      if (ok) await _openDraft(found.id);
    } catch (e) {
      // Ro'yxat olinmasa yangi sanash boshlanadi — bu xato emas.
      debugPrint('inventory_count_ui[draft qidiruvi]: $e');
    }
  }

  // ───────────────────────── Qatorlar / filtr ─────────────────────────

  List<_InvRow> _allRows(List<CoreStockRow> stock) {
    final rows = <_InvRow>[];
    final seen = <int>{};
    for (final r in stock) {
      final good = _dict.goodById(r.goodId) ?? r.toGood();
      _goodsById[good.id] = good;
      seen.add(r.goodId);
      rows.add(_InvRow(
        good: good,
        current: r.qty,
        lastPrice: r.lastPrice,
        low: r.low,
        negative: r.negative || r.hasDeficit,
      ));
    }
    for (final g in _extra) {
      _goodsById.putIfAbsent(g.id, () => g);
      if (!seen.add(g.id)) continue;
      final row = _sklad == null ? null : _stockP.rowFor(_sklad!, g.id);
      final good = _dict.goodById(g.id) ?? g;
      rows.add(_InvRow(
        good: good,
        current: row?.qty ?? 0,
        lastPrice: row?.lastPrice,
        low: row?.low ?? false,
        negative: row?.negative ?? false,
      ));
    }
    rows.sort((a, b) =>
        a.good.name.toLowerCase().compareTo(b.good.name.toLowerCase()));
    return rows;
  }

  int? _factBase(_InvRow r) {
    final v = parseUiQty(_fact[r.good.id]?.text);
    if (v == null) return null;
    return coreQtyFromUi(v, r.good.preferredUnit);
  }

  bool _matches(_InvRow r) {
    if (_q.isNotEmpty && !r.good.name.toLowerCase().contains(_q)) return false;
    final fact = _factBase(r);
    switch (_tab) {
      case 1:
        return fact == null;
      case 2:
        return fact != null && fact != r.current;
      default:
        return true;
    }
  }

  String _groupOf(CoreGood g) {
    final name = _dict.groupById(g.groupId)?.name.trim() ?? '';
    return name.isEmpty ? 'Boshqa' : name;
  }

  /// Bo'limlar (guruh nomi bo'yicha), har birida saralangan qatorlar.
  List<_Section> _sections(List<_InvRow> rows) {
    final map = <String, List<_InvRow>>{};
    for (final r in rows) {
      map.putIfAbsent(_groupOf(r.good), () => []).add(r);
    }
    final names = map.keys.toList()
      ..sort((a, b) {
        if (a == 'Boshqa') return 1;
        if (b == 'Boshqa') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [
      for (final n in names)
        _Section(
          name: n,
          rows: map[n]!,
          counted: map[n]!.where((r) => _factBase(r) != null).length,
        ),
    ];
  }

  // ───────────────────────── Avto-saqlash ─────────────────────────

  void _touch() {
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    setState(() => _saveState = _SaveState.dirty);
    _saveTimer = Timer(const Duration(seconds: 2), _autoSave);
  }

  /// Fakt kiritilgan qatorlardan hujjat. [extra] — «sanalmaganlar hisobdagidek»
  /// tanlansa qo'shiladigan qatorlar.
  CoreDoc _buildDoc({List<_InvRow> fillUncounted = const []}) {
    final lines = <CoreDocLine>[];
    void add(int goodId, int qty) {
      final good = _dict.goodById(goodId) ?? _goodsById[goodId];
      if (good == null) return;
      final unit = good.preferredUnit;
      lines.add(CoreDocLine(
        goodId: goodId,
        goodName: good.name,
        unit: unit.unit,
        qty: qty,
        // Ledger: inventar qatorida flag 1 = tayyor mahsulot (taom) fakti —
        // retsept bo'yicha yoyilmaydi; 0 = xom qator.
        flag: good.isComplect ? 1 : 0,
      ));
    }

    final done = <int>{};
    _fact.forEach((goodId, c) {
      final v = parseUiQty(c.text);
      if (v == null) return;
      final good = _dict.goodById(goodId) ?? _goodsById[goodId];
      if (good == null) return;
      done.add(goodId);
      add(goodId, coreQtyFromUi(v, good.preferredUnit));
    });
    for (final r in fillUncounted) {
      if (done.contains(r.good.id)) continue;
      add(r.good.id, r.current);
    }
    return CoreDoc(
      id: _docId ?? 0,
      type: CoreDocType.inventory,
      docDate: _date,
      toSklad: _sklad,
      comment: _comment,
      lines: lines,
    );
  }

  Future<void> _autoSave() async {
    if (!mounted || _posting || _sklad == null) return;
    final doc = _buildDoc();
    // Bo'sh hujjat saqlanmaydi (server `lines` bo'sh bo'lsa 422 beradi).
    if (doc.lines.isEmpty) {
      setState(() => _saveState = _SaveState.idle);
      return;
    }
    setState(() => _saveState = _SaveState.saving);
    try {
      final saved = _docId == null
          ? await _docs.create(doc)
          : await _docs.update(_docId!, doc);
      if (!mounted) return;
      setState(() {
        _docId = saved.id > 0 ? saved.id : _docId;
        _saveState = _SaveState.saved;
        _saveError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final err = CoreClient.wrap(e);
      setState(() {
        _saveState = _SaveState.failed;
        _saveError = err.display;
      });
      // Tarmoq/serverga ulanish xatosi — o'zi qayta urinadi.
      if (err.network) {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 10), _autoSave);
      }
    }
  }

  // ───────────────────────── Yakunlash / post ─────────────────────────

  Future<void> _finish(List<_InvRow> rows, bool showCost) async {
    final session = context.read<CoreSession>();
    if (!session.canPost(CoreDocType.inventory)) {
      showCoreInfo(context, 'Sizda sanashni tasdiqlash ruxsati yo\'q');
      return;
    }
    final counted = <_CountLine>[];
    final uncounted = <_InvRow>[];
    for (final r in rows) {
      final fact = _factBase(r);
      if (fact == null) {
        uncounted.add(r);
      } else {
        counted.add(_CountLine(row: r, fact: fact));
      }
    }
    if (counted.isEmpty) {
      showCoreInfo(context, 'Hech bir tovarga fakt kiritilmadi');
      return;
    }
    final res = await showModalBottomSheet<_FinishChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _SummarySheet(
        counted: counted,
        uncounted: uncounted,
        showCost: showCost,
        skladName: _dict.skladName(_sklad),
        date: _date,
      ),
    );
    if (res == null || !mounted) return;
    await _post(res.fillUncounted ? uncounted : const []);
  }

  Future<void> _post(List<_InvRow> fill) async {
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    setState(() => _posting = true);
    try {
      // `is_complect` (flag) uchun TO'LIQ tovar kartalari.
      final ids = <int>{
        for (final e in _fact.entries)
          if (parseUiQty(e.value.text) != null) e.key,
        for (final r in fill) r.good.id,
      };
      await _dict.ensureGoods(ids);
      if (!mounted) return;
      final doc = _buildDoc(fillUncounted: fill);
      final saved = _docId == null
          ? await _docs.create(doc)
          : await _docs.update(_docId!, doc);
      _docId = saved.id;
      final res = await _docs.post(saved.id);
      if (!mounted) return;
      setState(() => _saveState = _SaveState.saved);
      await _stockP.refreshSklads([res.doc.toSklad]);
      if (!mounted) return;
      await _showResult(res);
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _showResult(CoreDocPostResult res) async {
    final open = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Sanash tasdiqlandi')),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hujjat: ${res.doc.number}  ·  ${coreDateUz(res.doc.docDate)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${res.doc.lines.length} ta qator · ${_dict.skladName(res.doc.toSklad)}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              if (res.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Diqqat qiling:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in res.warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: Colors.orange.shade800),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_warningUz(w),
                                      style: const TextStyle(fontSize: 12.5)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Yopish')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kCoreAccent, foregroundColor: Colors.white),
            child: const Text('Hujjatni ko\'rish'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (open == true) {
      context.pushReplacement(DocDetailUi(docId: res.doc.id, initial: res.doc));
    } else {
      Navigator.pop(context);
    }
  }

  /// Ogohlantirishlar oddiy tilda.
  String _warningUz(CoreDocWarning w) {
    final good = _dict.goodById(w.goodId);
    final name = w.goodName.isNotEmpty
        ? w.goodName
        : (good?.name ?? 'Tovar #${w.goodId ?? 0}');
    final qty = good == null ? '${w.qty}' : coreQtyUnitUz(w.qty, good.baseUnit);
    switch (w.code) {
      case 'negative_stock':
        return '$name — qoldiq manfiy bo\'ldi ($qty). '
            'Kirim hujjati kiritilmagan bo\'lishi mumkin.';
      case 'no_batch':
        return '$name — partiya topilmadi, narx oxirgi kirimdan olindi.';
      case 'no_recipe':
        return '$name — retsept yo\'q, taom ingredientlarga yoyilmadi.';
      case 'rounding':
        return '$name — yaxlitlash farqi ($qty).';
      default:
        return w.msg.isNotEmpty ? '$name — ${w.msg}' : name;
    }
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Sanash',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          _saveBadge(),
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _loadStock,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CoreConnectGate(child: _body()),
    );
  }

  Widget _saveBadge() {
    late final IconData icon;
    late final Color color;
    late final String text;
    switch (_saveState) {
      case _SaveState.saving:
        icon = Icons.cloud_sync_outlined;
        color = Colors.grey.shade700;
        text = 'Saqlanmoqda';
        break;
      case _SaveState.saved:
        icon = Icons.cloud_done_outlined;
        color = Colors.green.shade700;
        text = 'Saqlandi';
        break;
      case _SaveState.failed:
        icon = Icons.cloud_off;
        color = Colors.red.shade700;
        text = 'Saqlanmadi';
        break;
      case _SaveState.dirty:
        icon = Icons.edit_outlined;
        color = Colors.orange.shade800;
        text = 'O\'zgardi';
        break;
      case _SaveState.idle:
        return const SizedBox.shrink();
    }
    return InkWell(
      onTap: _saveState == _SaveState.failed
          ? () {
              if (_saveError != null) showCoreInfo(context, _saveError!);
              _autoSave();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, color: color)),
        ]),
      ),
    );
  }

  Widget _body() {
    final session = context.watch<CoreSession>();
    context.watch<CoreDictProvider>(); // guruh nomlari yuklanganda yangilanadi
    final stockP = context.watch<CoreStockProvider>();
    final showCost = session.has(CorePerms.stockCostView);
    final stock =
        _sklad == null ? const <CoreStockRow>[] : (stockP.rowsFor(_sklad!) ?? const []);
    final loading = _sklad != null && stockP.isLoading(_sklad!);
    final error = _sklad != null ? stockP.errorFor(_sklad!) : null;

    final all = _allRows(stock);
    final visible = all.where(_matches).toList();
    final counted = all.where((r) => _factBase(r) != null).length;

    if (_loadingDoc) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= _kWideBreakpoint;
      return Column(
        children: [
          _header(session, all.length, counted),
          Expanded(
            child: _sklad == null
                ? const Center(child: Text('Omborni tanlang'))
                : (loading && stock.isEmpty)
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : (error != null && stock.isEmpty)
                        ? CoreErrorView(message: error, onRetry: _loadStock)
                        : visible.isEmpty
                            ? Center(
                                child: Text(
                                  _tab == 1
                                      ? 'Hammasi sanaldi'
                                      : (_tab == 2
                                          ? 'Farqli tovar yo\'q'
                                          : 'Tovar topilmadi'),
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : _list(visible, wide, showCost),
          ),
          _bottomBar(session, all, showCost, counted),
        ],
      );
    });
  }

  Widget _header(CoreSession session, int total, int counted) {
    final ratio = total == 0 ? 0.0 : counted / total;
    return Container(
      color: kCoreBg,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        children: [
          // Qidiruv BIRINCHI — eng ko'p ishlatiladigan amal.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Tovar qidirish…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() => _q = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Ro\'yxatda yo\'q tovarni qo\'shish',
                onPressed: _posting ? null : _addGood,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Ombor + sana.
          Row(
            children: [
              Expanded(
                child: CoreSkladDropdown(
                  value: _sklad,
                  label: 'Ombor',
                  enabled: !_posting,
                  onChanged: (v) {
                    if (v == null || v == _sklad) return;
                    setState(() {
                      _sklad = v;
                      _resetCount();
                    });
                    _loadStock();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: InkWell(
                  onTap: _posting
                      ? null
                      : () async {
                          final d = await pickDate(context, _date,
                              allowPast: session.canBackdate);
                          if (d == null || d == _date || !mounted) return;
                          setState(() {
                            _date = d;
                            _resetCount();
                          });
                          // Hisob qoldig'i o'sha kun oxiriga qayta olinadi.
                          _loadStock();
                        },
                  child: InputDecorator(
                    decoration: coreInput('Sana'),
                    child: Text(coreDayUz(_date),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Taraqqiyot.
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(kCoreAccentDark),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$counted/$total sanaldi',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
          const SizedBox(height: 6),
          // Tablar.
          Row(
            children: [
              for (final t in const [
                [0, 'Hammasi'],
                [1, 'Sanalmagan'],
                [2, 'Farqli'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t[1] as String,
                        style: const TextStyle(fontSize: 12.5)),
                    selected: _tab == t[0],
                    selectedColor: kCoreAccent.withValues(alpha: 0.3),
                    onSelected: (_) => setState(() => _tab = t[0] as int),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Ombor/sana almashsa kiritilgan faktlar boshqa qoldiqqa tegishli bo'lardi.
  /// Eski controller/focus'lar DARHOL o'chirilmaydi — hali ekrandagi
  /// TextField'lar ularga ulangan; kadr tugagach o'chiriladi.
  void _resetCount() {
    final oldCtrls = _fact.values.toList();
    final oldNodes = _focus.values.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in oldCtrls) {
        c.dispose();
      }
      for (final f in oldNodes) {
        f.dispose();
      }
    });
    _fact.clear();
    _focus.clear();
    _extra.clear();
    _docId = null;
    _saveTimer?.cancel();
    _retryTimer?.cancel();
    _saveState = _SaveState.idle;
    _saveError = null;
  }

  Future<void> _addGood() async {
    final g = await pickCoreGood(context, skladId: _sklad);
    if (g == null || !mounted) return;
    setState(() {
      if (!_extra.any((e) => e.id == g.id)) _extra.add(g);
      _goodsById[g.id] = g;
      _tab = 0;
      _q = '';
      _search.clear();
    });
    // Yangi qator darhol kiritishga tayyor bo'lsin.
    final row = _InvRow(
      good: g,
      current: _sklad == null ? 0 : _stockP.qtyFor(_sklad!, g.id),
      lastPrice: null,
      low: false,
      negative: false,
    );
    await _editRow(row);
  }

  Widget _list(List<_InvRow> rows, bool wide, bool showCost) {
    final sections = _sections(rows);
    final items = <_ListItem>[];
    for (final s in sections) {
      items.add(_ListItem.header(s));
      if (_closed.contains(s.name)) continue;
      for (final r in s.rows) {
        items.add(_ListItem.row(r));
      }
    }
    // Enter/Tab bilan yurish uchun ko'rinadigan tartib.
    final order = [
      for (final i in items)
        if (i.row != null) i.row!.good.id
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.section != null) return _sectionHeader(item.section!);
        final r = item.row!;
        return wide
            ? _wideRow(r, order, showCost)
            : _phoneRow(r, showCost);
      },
    );
  }

  Widget _sectionHeader(_Section s) {
    final closed = _closed.contains(s.name);
    return InkWell(
      onTap: () => setState(() {
        if (closed) {
          _closed.remove(s.name);
        } else {
          _closed.add(s.name);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Row(
          children: [
            Icon(closed ? Icons.chevron_right : Icons.expand_more,
                size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 2),
            Expanded(
              child: Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ),
            Text('${s.counted}/${s.rows.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // ── Telefon qatori: bosilsa klaviatura ──
  Widget _phoneRow(_InvRow r, bool showCost) {
    final fact = _factBase(r);
    final delta = fact == null ? null : fact - r.current;
    final border = delta == null
        ? (r.negative
            ? Colors.red.shade200
            : (r.low ? Colors.orange.shade200 : Colors.grey.shade300))
        : (delta == 0
            ? Colors.green.shade200
            : (delta < 0 ? Colors.red.shade300 : Colors.green.shade400));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _posting ? null : () => _editRow(r),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.good.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(r, fact, showCost),
                      style: TextStyle(
                        fontSize: 12,
                        color: delta == null || delta == 0
                            ? Colors.grey.shade600
                            : (delta < 0
                                ? Colors.red.shade700
                                : Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fact == null
                        ? '—'
                        : coreQtyUnitUz(fact, r.good.baseUnit),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: fact == null ? Colors.grey.shade400 : Colors.black87,
                    ),
                  ),
                  Text(fact == null ? 'sanalmagan' : 'fakt',
                      style:
                          TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(_InvRow r, int? fact, bool showCost) {
    final parts = <String>['hisobda: ${coreQtyUnitUz(r.current, r.good.baseUnit)}'];
    if (fact != null) {
      final d = fact - r.current;
      if (d == 0) {
        parts.add('farq yo\'q');
      } else {
        final money =
            showCost && r.lastPrice != null ? ' (${coreSumUz(d.abs() * r.lastPrice!)})' : '';
        parts.add(d < 0
            ? 'kamomad ${coreQtyUnitUz(-d, r.good.baseUnit)}$money'
            : 'ortiqcha ${coreQtyUnitUz(d, r.good.baseUnit)}$money');
      }
    } else if (r.negative) {
      parts.add('qoldiq manfiy');
    } else if (r.low) {
      parts.add('kam qoldi');
    }
    return parts.join('  ·  ');
  }

  Future<void> _editRow(_InvRow r) async {
    final res = await showCountKeypad(
      context,
      goodName: r.good.name,
      baseUnit: r.good.baseUnit,
      currentBase: r.current,
      initialBase: _factBase(r),
      hint: _groupOf(r.good),
    );
    if (res == null || !mounted) return;
    setState(() {
      _ctrl(r.good.id).text =
          res.cleared ? '' : coreQtyUz(res.base, r.good.baseUnit);
    });
    _touch();
  }

  // ── Kompyuter jadvali: katakka to'g'ridan-to'g'ri yoziladi ──
  Widget _wideRow(_InvRow r, List<int> order, bool showCost) {
    final fact = _factBase(r);
    final delta = fact == null ? null : fact - r.current;
    final unit = r.good.preferredUnit;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: delta == null
              ? (r.negative ? Colors.red.shade200 : Colors.grey.shade300)
              : (delta == 0
                  ? Colors.green.shade200
                  : (delta < 0 ? Colors.red.shade300 : Colors.green.shade400)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(r.good.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 140,
            child: Text(
              coreQtyUnitUz(r.current, r.good.baseUnit),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13,
                  color: r.negative ? Colors.red.shade700 : Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _ctrl(r.good.id),
              focusNode: _node(r.good.id),
              enabled: !_posting,
              textAlign: TextAlign.right,
              textInputAction: TextInputAction.next,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'fakt',
                suffixText: coreUnitUz(unit.unit),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (_) {
                setState(() {});
                _touch();
              },
              onSubmitted: (_) => _focusNext(r.good.id, order),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Hisobdagidek',
            visualDensity: VisualDensity.compact,
            onPressed: _posting
                ? null
                : () {
                    _ctrl(r.good.id).text =
                        coreQtyUz(r.current, r.good.baseUnit);
                    setState(() {});
                    _touch();
                  },
            icon: const Icon(Icons.done_all, size: 18),
          ),
          SizedBox(
            width: 170,
            child: Text(
              delta == null
                  ? ''
                  : (delta == 0
                      ? 'farq yo\'q'
                      : '${delta > 0 ? '+' : '−'}${coreQtyUnitUz(delta.abs(), r.good.baseUnit)}'
                          '${showCost && r.lastPrice != null ? ' · ${coreSumUz(delta.abs() * r.lastPrice!)}' : ''}'),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: delta == null || delta == 0
                    ? Colors.grey.shade600
                    : (delta < 0 ? Colors.red.shade700 : Colors.green.shade700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _focusNext(int goodId, List<int> order) {
    final i = order.indexOf(goodId);
    if (i < 0 || i + 1 >= order.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _node(order[i + 1]).requestFocus();
  }

  Widget _bottomBar(
      CoreSession session, List<_InvRow> all, bool showCost, int counted) {
    final canPost = session.canPost(CoreDocType.inventory);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: _posting
            ? const SizedBox(
                height: 46,
                child: Center(child: CircularProgressIndicator.adaptive()))
            : ElevatedButton.icon(
                onPressed: counted == 0 || !canPost
                    ? null
                    : () => _finish(all, showCost),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(canPost
                    ? 'Yakunlash ($counted ta sanaldi)'
                    : 'Tasdiqlash ruxsati yo\'q'),
              ),
      ),
    );
  }
}

// ───────────────────────────── Modellar ─────────────────────────────

class _InvRow {
  final CoreGood good;
  final int current; // hisob qoldig'i (base birlik)
  final int? lastPrice; // 1 base birlik narxi (stock.cost.view bo'lsa)
  final bool low;
  final bool negative;
  const _InvRow({
    required this.good,
    required this.current,
    required this.lastPrice,
    required this.low,
    required this.negative,
  });
}

class _Section {
  final String name;
  final List<_InvRow> rows;
  final int counted;
  const _Section({required this.name, required this.rows, required this.counted});
}

class _ListItem {
  final _Section? section;
  final _InvRow? row;
  const _ListItem.header(this.section) : row = null;
  const _ListItem.row(this.row) : section = null;
}

class _CountLine {
  final _InvRow row;
  final int fact;
  const _CountLine({required this.row, required this.fact});

  int get delta => fact - row.current;
  int get money => (row.lastPrice ?? 0) * delta;
}

class _FinishChoice {
  final bool fillUncounted;
  const _FinishChoice(this.fillUncounted);
}

// ───────────────────────── Yakunlash xulosasi ─────────────────────────

class _SummarySheet extends StatefulWidget {
  final List<_CountLine> counted;
  final List<_InvRow> uncounted;
  final bool showCost;
  final String skladName;
  final String date;

  const _SummarySheet({
    required this.counted,
    required this.uncounted,
    required this.showCost,
    required this.skladName,
    required this.date,
  });

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _fillUncounted = false;

  @override
  Widget build(BuildContext context) {
    final minus = widget.counted.where((c) => c.delta < 0).toList()
      ..sort((a, b) => a.money.compareTo(b.money));
    final plus = widget.counted.where((c) => c.delta > 0).toList()
      ..sort((a, b) => b.money.compareTo(a.money));
    final same = widget.counted.length - minus.length - plus.length;
    final minusSum = minus.fold<int>(0, (s, c) => s + c.money);
    final plusSum = plus.fold<int>(0, (s, c) => s + c.money);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sanash xulosasi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${widget.skladName} · ${coreDateUz(widget.date)}',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    _stat('Sanaldi', '${widget.counted.length}', Colors.black87),
                    _stat('Farqsiz', '$same', Colors.grey.shade700),
                    _stat('Kamomad', '${minus.length}', Colors.red.shade700),
                    _stat('Ortiqcha', '${plus.length}', Colors.green.shade700),
                  ],
                ),
                if (widget.showCost && (minusSum != 0 || plusSum != 0)) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kCoreBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Kamomad: ${coreSumUz(-minusSum)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade700)),
                        ),
                        Expanded(
                          child: Text('Ortiqcha: ${coreSumUz(plusSum)}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.uncounted.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.warning_amber,
                              size: 18, color: Colors.orange.shade800),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${widget.uncounted.length} ta tovar sanalmadi',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        _choice(
                          selected: !_fillUncounted,
                          text: 'Sanalmaganlar o\'zgarmasin (tavsiya etiladi)',
                          onTap: () => setState(() => _fillUncounted = false),
                        ),
                        _choice(
                          selected: _fillUncounted,
                          text: 'Sanalmaganlar hisobdagidek yozilsin',
                          onTap: () => setState(() => _fillUncounted = true),
                        ),
                      ],
                    ),
                  ),
                ],
                if (minus.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _title('Kamomad (hisobdan kam chiqdi)', Colors.red.shade700),
                  for (final c in minus) _line(c),
                ],
                if (plus.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _title('Ortiqcha (hisobdan ko\'p chiqdi)', Colors.green.shade700),
                  for (final c in plus) _line(c),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46)),
                      child: const Text('Orqaga'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, _FinishChoice(_fillUncounted)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('Tasdiqlash'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ikki variantli tanlov (radio o'rniga — katta, barmoq bilan bosiladigan).
  Widget _choice({
    required bool selected,
    required String text,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? kCoreAccentDark : Colors.grey.shade500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),
            ],
          ),
        ),
      );

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _title(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _line(_CountLine c) {
    final neg = c.delta < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(c.row.good.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Text(
            '${coreQtyUnitUz(c.row.current, c.row.good.baseUnit)} → '
            '${coreQtyUnitUz(c.fact, c.row.good.baseUnit)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: widget.showCost ? 150 : 90,
            child: Text(
              '${neg ? '−' : '+'}${coreQtyUnitUz(c.delta.abs(), c.row.good.baseUnit)}'
              '${widget.showCost && c.row.lastPrice != null ? '  ${coreSumUz(c.money.abs())}' : ''}',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: neg ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
