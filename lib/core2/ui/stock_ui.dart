// core2/ui/stock_ui.dart — «QOLDIQ» (oson rejim).
//
// Ro'yxat: qidiruv BIRINCHI (eng ko'p ishlatiladigan amal), ostida ombor
// tanlagich va guruh chiplari; har qatorda tovar nomi va KATTA miqdor +
// birlik. Ranglar: QIZIL faqat manfiy qoldiqda; partiyasiz (defitsit) yoki
// `min_qty` dan past — sariq. Har bir rangli qatorda SABAB kichik yorliqda
// («manfiy», «partiyasiz», «kam qoldi»). Tovar bosilsa kartochka: ODDIY TILDA
// («17.09 · Kirim +5 kg · РЫНОК», «17.09 · Ko'chirish −2 kg → ГЕЛИОН БАР»)
// va partiyalar (FIFO) tabi.
//
// Ma'lumot: `GET /stock` (qty haqiqiy balans, `deficit` — partiyasiz
// yechilgan, `cost`/`last_price` faqat `stock.cost.view`), `GET /stock/card`
// ({open_qty, close_qty, rows[] — `kind`: in/out/deficit/repay}),
// `GET /batches`. Guruh chiplari uchun tovar kartalari fonda yuklanadi
// (`CoreDictProvider.ensureGoods` — qoldiq javobida `group_id` yo'q).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Hujjat turining o'zbekcha nomi (SH5 atamasi qavs ichida — Xilola tanisin).
String coreDocTypeUz(String type) {
  switch (type) {
    case CoreDocType.receipt:
      return 'Kirim';
    case CoreDocType.issue:
      return 'Hisobdan chiqarish';
    case CoreDocType.transfer:
      return 'Ko\'chirish';
    case CoreDocType.inventory:
      return 'Sanash';
    case CoreDocType.production:
      return 'Qayta ishlash';
    case CoreDocType.act:
      return 'Sotuv (taom)';
    case CoreDocType.reserve:
      return 'Rezerv';
    default:
      return type;
  }
}

class StockUi extends StatefulWidget {
  final int? initialSklad;
  const StockUi({super.key, this.initialSklad});

  @override
  State<StockUi> createState() => _StockUiState();
}

class _StockUiState extends State<StockUi> {
  int? _sklad;
  String _q = '';
  bool _nonzero = true;
  int? _group; // null — hamma guruh
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sklad = widget.initialSklad;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    if (_sklad == null) return;
    final stock = context.read<CoreStockProvider>();
    final dict = context.read<CoreDictProvider>();
    // Qoldiq qatorlaridagi tovar nomi/base birligi keshga (tovarlar to'liq
    // yuklanmaydi — 12 000+); guruh chiplari uchun to'liq kartalar fonda.
    stock.onRows = (rows) {
      dict.cacheGoods(rows.map((r) => r.toGood()));
      dict.ensureGoods(rows.map((r) => r.goodId));
    };
    stock.load(_sklad!, nonzero: _nonzero);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Qoldiq',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(child: _body()),
    );
  }

  Widget _body() {
    final dict = context.watch<CoreDictProvider>();
    final session = context.read<CoreSession>();
    // Birinchi ochilishda default ombor.
    if (_sklad == null && dict.activeSklads.isNotEmpty) {
      final user = session.user;
      _sklad = (user != null && user.sklads.isNotEmpty)
          ? user.sklads.first
          : dict.activeSklads.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final showCost = session.has(CorePerms.stockCostView);
    final stockP = context.watch<CoreStockProvider>();
    final rows =
        _sklad == null ? const <CoreStockRow>[] : (stockP.rowsFor(_sklad!) ?? const []);
    final loading = _sklad != null && stockP.isLoading(_sklad!);
    final error = _sklad != null ? stockP.errorFor(_sklad!) : null;

    final filtered = rows.where((r) {
      if (_q.isNotEmpty && !r.goodName.toLowerCase().contains(_q)) return false;
      if (_group != null && dict.goodById(r.goodId)?.groupId != _group) {
        return false;
      }
      return true;
    }).toList();
    final totalCost =
        showCost ? filtered.fold<int>(0, (s, r) => s + (r.cost ?? 0)) : 0;

    return Column(
      children: [
        _header(dict, rows),
        if (filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text('${filtered.length} ta tovar',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const Spacer(),
                if (showCost)
                  Text('Qiymat: ${coreSumUz(totalCost)}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        Expanded(
          child: _sklad == null
              ? const Center(child: Text('Ombor yo\'q'))
              : loading && rows.isEmpty
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : error != null && rows.isEmpty
                      ? CoreErrorView(message: error, onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: () async => _load(),
                          child: filtered.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(child: Text('Tovar topilmadi')),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 4, 12, 16),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _StockTile(
                                    row: filtered[i],
                                    showCost: showCost,
                                    onTap: () => context.push(StockCardUi(
                                      skladId: _sklad!,
                                      goodId: filtered[i].goodId,
                                      goodName: filtered[i].goodName,
                                      baseUnit: filtered[i].baseUnit,
                                    )),
                                  ),
                                ),
                        ),
        ),
      ],
    );
  }

  Widget _header(CoreDictProvider dict, List<CoreStockRow> rows) {
    // Guruh chiplari — faqat qoldiqda uchraydigan guruhlar (tovar kartasi
    // yuklangan bo'lsa). Kartalar fonda kelgani sari chiplar to'ldiriladi.
    final counts = <int, int>{};
    for (final r in rows) {
      final gid = dict.goodById(r.goodId)?.groupId;
      if (gid != null) counts[gid] = (counts[gid] ?? 0) + 1;
    }
    final groups = counts.keys.toList()
      ..sort((a, b) => (dict.groupById(a)?.name ?? '')
          .toLowerCase()
          .compareTo((dict.groupById(b)?.name ?? '').toLowerCase()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          // 1) Qidiruv birinchi.
          TextField(
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
          const SizedBox(height: 8),
          // 2) Ombor + «faqat qoldiqlilar».
          Row(
            children: [
              Expanded(
                child: CoreSkladDropdown(
                  value: _sklad,
                  label: 'Ombor',
                  onChanged: (v) {
                    setState(() {
                      _sklad = v;
                      _group = null;
                    });
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Faqat qoldiqlilar',
                    style: TextStyle(fontSize: 12)),
                selected: _nonzero,
                selectedColor: kCoreAccent.withValues(alpha: 0.25),
                onSelected: (v) {
                  setState(() => _nonzero = v);
                  _load();
                },
              ),
            ],
          ),
          // 3) Guruh chiplari.
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('Hammasi (${rows.length})',
                          style: const TextStyle(fontSize: 12)),
                      selected: _group == null,
                      selectedColor: kCoreAccent.withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _group = null),
                    ),
                  ),
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                            '${dict.groupById(g)?.name ?? 'Guruh #$g'} (${counts[g]})',
                            style: const TextStyle(fontSize: 12)),
                        selected: _group == g,
                        selectedColor: kCoreAccent.withValues(alpha: 0.3),
                        onSelected: (_) => setState(() => _group = g),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  final CoreStockRow row;
  final bool showCost;
  final VoidCallback onTap;
  const _StockTile(
      {required this.row, required this.showCost, required this.onTap});

  /// Qator rangining SABABI — kichik yorliq (foydalanuvchi qizil/sariqning
  /// nimadan ekanini darhol ko'rsin).
  String? get _reason {
    if (row.negative) return 'manfiy';
    if (row.hasDeficit) return 'partiyasiz';
    if (row.low) return 'kam qoldi';
    return null;
  }

  /// Ikkinchi qator — oddiy tilda: partiyasiz yechim, kam qolgani, qiymat.
  String _subtitle() {
    final parts = <String>[];
    if (row.negative) {
      parts.add('qoldiq manfiy — kirim kiritilmagan bo\'lishi mumkin');
    }
    if (row.hasDeficit) {
      parts.add(
          'partiyasiz yechilgan: ${coreQtyUnitUz(row.deficit, row.baseUnit)}');
    }
    if (row.low) {
      parts.add('kam qoldi (eng kami ${coreQtyUnitUz(row.minQty, row.baseUnit)})');
    }
    if (showCost) {
      parts.add('qiymat: ${coreSumUz(row.cost ?? 0)}');
      if (row.lastPrice != null) {
        parts.add(
            'oxirgi narx: ${coreSumUz(row.lastPrice! * _unitFactor(row.baseUnit))}'
            '/${coreUnitUz(row.baseUnit)}');
      }
    }
    return parts.join('  ·  ');
  }

  /// `last_price` 1 BASE birlik narxi — odamga ko'rsatishda 1 kg / 1 dona
  /// narxiga o'giriladi.
  int _unitFactor(String baseUnit) =>
      const {'g': 1000, 'ml': 1000, 'mpcs': 1000, 'mm': 1000}[baseUnit] ?? 1;

  @override
  Widget build(BuildContext context) {
    // QIZIL faqat manfiy qoldiqda. Partiyasiz (defitsit) yoki eng kam
    // miqdordan past — sariq; sababi yorliqda yozilgan.
    final bad = row.negative;
    final warn = !bad && (row.hasDeficit || row.low);
    final qtyColor = bad
        ? Colors.red.shade700
        : (warn ? Colors.orange.shade800 : Colors.black87);
    final sub = _subtitle();
    final reason = _reason;
    final reasonColor = bad ? Colors.red.shade700 : Colors.orange.shade800;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bad
              ? Colors.red.shade300
              : (warn ? Colors.orange.shade300 : Colors.grey.shade300),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(row.goodName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        if (reason != null)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: reasonColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: reasonColor.withValues(alpha: 0.45)),
                            ),
                            child: Text(reason,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: reasonColor)),
                          ),
                      ],
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: bad
                                ? Colors.red.shade700
                                : (warn
                                    ? Colors.orange.shade800
                                    : Colors.grey.shade600),
                          )),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                coreQtyUnitUz(row.qty, row.baseUnit),
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18, color: qtyColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Tovar kartochkasi ─────────────────────────

class StockCardUi extends StatefulWidget {
  final int skladId;
  final int goodId;
  final String goodName;
  final String baseUnit;
  const StockCardUi({
    super.key,
    required this.skladId,
    required this.goodId,
    required this.goodName,
    required this.baseUnit,
  });

  @override
  State<StockCardUi> createState() => _StockCardUiState();
}

class _StockCardUiState extends State<StockCardUi>
    with SingleTickerProviderStateMixin {
  final _service = CoreStockService();
  late final TabController _tab = TabController(length: 2, vsync: this);
  CoreStockCard? _card;
  List<CoreBatch>? _batches;
  String? _cardErr;
  String? _batchErr;
  String _from = isoOf(DateTime.now().subtract(const Duration(days: 30)));
  String _to = todayIso();

  @override
  void initState() {
    super.initState();
    _loadCard();
    _loadBatches();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadCard() async {
    setState(() {
      _card = null;
      _cardErr = null;
    });
    try {
      final c = await _service.card(
          skladId: widget.skladId,
          goodId: widget.goodId,
          dateFrom: _from,
          dateTo: _to);
      if (mounted) setState(() => _card = c);
    } catch (e) {
      if (mounted) setState(() => _cardErr = e.toString());
    }
  }

  Future<void> _loadBatches() async {
    setState(() {
      _batches = null;
      _batchErr = null;
    });
    try {
      final b =
          await _service.batches(skladId: widget.skladId, goodId: widget.goodId);
      if (mounted) setState(() => _batches = b);
    } catch (e) {
      if (mounted) setState(() => _batchErr = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCost = context.read<CoreSession>().has(CorePerms.stockCostView);
    final dict = context.read<CoreDictProvider>();
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          children: [
            Text(widget.goodName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            Text(dict.skladName(widget.skladId),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ],
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: kCoreAccent,
          labelColor: kCoreAccentDark,
          unselectedLabelColor: Colors.black54,
          tabs: const [Tab(text: 'Harakatlar'), Tab(text: 'Partiyalar')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_cardTab(showCost), _batchesTab(showCost)],
      ),
    );
  }

  Widget _cardTab(bool showCost) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 3),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: DateTimeRange(
                          start: DateTime.parse(_from), end: DateTime.parse(_to)),
                    );
                    if (r != null) {
                      setState(() {
                        _from = isoOf(r.start);
                        _to = isoOf(r.end);
                      });
                      _loadCard();
                    }
                  },
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('${coreDateUz(_from)} – ${coreDateUz(_to)}'),
                ),
              ),
            ],
          ),
        ),
        if (_card != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                    'Boshida: ${coreQtyUnitUz(_card!.openQty, widget.baseUnit)}',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                const Spacer(),
                Text('Hozir: ${coreQtyUnitUz(_card!.closeQty, widget.baseUnit)}',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color:
                            _card!.closeQty < 0 ? Colors.red : Colors.black87)),
              ],
            ),
          ),
        Expanded(
          child: _cardErr != null
              ? CoreErrorView(message: _cardErr!, onRetry: _loadCard)
              : _card == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _card!.rows.isEmpty
                      ? const Center(child: Text('Bu kunlarda harakat bo\'lmagan'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: _card!.rows.length,
                          itemBuilder: (_, i) => _MoveTile(
                            entry: _card!.rows[i],
                            baseUnit: widget.baseUnit,
                            showCost: showCost,
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _batchesTab(bool showCost) {
    if (_batchErr != null) {
      return CoreErrorView(message: _batchErr!, onRetry: _loadBatches);
    }
    if (_batches == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_batches!.isEmpty) return const Center(child: Text('Partiya yo\'q'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _batches!.length,
      itemBuilder: (_, i) {
        final b = _batches![i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ListTile(
            dense: true,
            onTap:
                b.docId > 0 ? () => context.push(DocDetailUi(docId: b.docId)) : null,
            title: Text('${coreDateUz(b.receivedAt)} kirgan partiya',
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              'kirgan: ${coreQtyUnitUz(b.qtyIn, widget.baseUnit)}'
              '${showCost ? ' · narx: ${coreSumUz(b.unitCost * _factor())}/${coreUnitUz(widget.baseUnit)}' : ''}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            trailing: Text(
              'qolgan: ${coreQtyUnitUz(b.qtyLeft, widget.baseUnit)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }

  int _factor() =>
      const {'g': 1000, 'ml': 1000, 'mpcs': 1000, 'mm': 1000}[widget.baseUnit] ??
      1;
}

/// Kartochkadagi bitta harakat — oddiy tilda.
class _MoveTile extends StatelessWidget {
  final CoreCardEntry entry;
  final String baseUnit;
  final bool showCost;
  const _MoveTile(
      {required this.entry, required this.baseUnit, required this.showCost});

  /// «17.09 · Ko'chirish −2 kg» ning ikkinchi qismi: qayerdan/qayerga yoki
  /// kontragent.
  String _who() {
    final plus = entry.qtyDelta >= 0;
    if (entry.corr.isNotEmpty) return entry.corr;
    if (entry.docType == CoreDocType.transfer ||
        entry.docType == CoreDocType.production ||
        entry.docType == CoreDocType.reserve) {
      if (plus) {
        return entry.fromSklad.isEmpty ? '' : '${entry.fromSklad} dan';
      }
      return entry.toSklad.isEmpty ? '' : '${entry.toSklad} ga';
    }
    return [entry.fromSklad, entry.toSklad]
        .where((s) => s.isNotEmpty)
        .join(' → ');
  }

  /// Partiya holati haqida oddiy izoh.
  String? _note() {
    switch (entry.kind) {
      case 'deficit':
        return 'partiya yo\'q edi (qarzga yechildi)';
      case 'repay':
      case 'repay_adj':
        return 'oldingi qarz qoplandi';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plus = entry.qtyDelta >= 0;
    final who = _who();
    final note = _note();
    final sub = [
      if (who.isNotEmpty) who,
      if (note != null) note,
      if (showCost && entry.costDelta != null)
        'qiymat: ${plus ? '+' : '−'}${coreSumUz(entry.costDelta!.abs())}',
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.kind == 'deficit'
              ? Colors.red.shade200
              : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: entry.docId > 0
            ? () => context.push(DocDetailUi(docId: entry.docId))
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(docTypeIcon(entry.docType), size: 20, color: kCoreAccentDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${coreDateUz(entry.docDate)} · ${coreDocTypeUz(entry.docType)}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: entry.kind == 'deficit'
                                  ? Colors.red.shade700
                                  : Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${plus ? '+' : '−'}${coreQtyUnitUz(entry.qtyDelta.abs(), baseUnit)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color:
                          plus ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                  Text(
                    'qoldi ${coreQtyUnitUz(entry.balance, baseUnit)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: entry.balance < 0
                            ? Colors.red
                            : Colors.grey.shade600),
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
