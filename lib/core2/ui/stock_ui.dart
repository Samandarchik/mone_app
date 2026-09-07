// core2/ui/stock_ui.dart — mone_core qoldiq (StockUi): ombor tanlash,
// qidiruv, qatorda tovar, qty (kg/l ko'rinishda), cost/last_price faqat
// `stock.cost.view` bo'lsa; manfiy qoldiq qizil; qator bosilsa
// StockCardUi — 2 tab: kartochka (/stock/card ledger yozuvlari balans bilan,
// sana oralig'i) va partiyalar (/batches: kirgan/qolgan, narx, sana).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

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
    if (_sklad != null) {
      context.read<CoreStockProvider>().load(_sklad!, nonzero: _nonzero);
    }
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
    final rows = _sklad == null ? const <CoreStockRow>[] : (stockP.rowsFor(_sklad!) ?? const []);
    final loading = _sklad != null && stockP.isLoading(_sklad!);
    final error = _sklad != null ? stockP.errorFor(_sklad!) : null;
    final q = _q.toLowerCase();
    final filtered = q.isEmpty
        ? rows
        : rows.where((r) => r.goodName.toLowerCase().contains(q)).toList();
    final totalCost = showCost ? filtered.fold<int>(0, (s, r) => s + (r.cost ?? 0)) : 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            children: [
              CoreSkladDropdown(
                value: _sklad,
                label: 'Ombor',
                onChanged: (v) {
                  setState(() => _sklad = v);
                  _load();
                },
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
                    label: const Text('≠0', style: TextStyle(fontSize: 12)),
                    selected: _nonzero,
                    selectedColor: kCoreAccent.withValues(alpha: 0.25),
                    onSelected: (v) {
                      setState(() => _nonzero = v);
                      _load();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showCost && filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text('${filtered.length} pozitsiya',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const Spacer(),
                Text('Qiymat: ${coreMoney(totalCost)} so\'m',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
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
                                    Center(child: Text('Qoldiq yo\'q')),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
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
}

class _StockTile extends StatelessWidget {
  final CoreStockRow row;
  final bool showCost;
  final VoidCallback onTap;
  const _StockTile({required this.row, required this.showCost, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final neg = row.negative;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: neg ? Colors.red.shade300 : Colors.grey.shade300),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(row.goodName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: showCost
            ? Text(
                'qiymat: ${coreMoney(row.cost ?? 0)}'
                '${row.lastPrice != null ? ' · oxirgi narx: ${coreMoney(row.lastPrice!)}/${row.baseUnit}' : ''}'
                '${row.low ? ' · KAM' : ''}',
                style: TextStyle(
                    fontSize: 11.5,
                    color: row.low ? Colors.orange.shade800 : Colors.grey.shade600),
              )
            : (row.low
                ? Text('kam qoldi', style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800))
                : null),
        trailing: Text(
          coreFormatQtyUnit(row.qty, row.baseUnit),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: neg ? Colors.red.shade700 : Colors.black87,
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
  List<CoreCardEntry>? _card;
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
          skladId: widget.skladId, goodId: widget.goodId, dateFrom: _from, dateTo: _to);
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
      final b = await _service.batches(skladId: widget.skladId, goodId: widget.goodId);
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
          tabs: const [Tab(text: 'Kartochka'), Tab(text: 'Partiyalar')],
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
                  label: Text('${coreDate(_from)} – ${coreDate(_to)}'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cardErr != null
              ? CoreErrorView(message: _cardErr!, onRetry: _loadCard)
              : _card == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _card!.isEmpty
                      ? const Center(child: Text('Harakat yo\'q'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: _card!.length,
                          itemBuilder: (_, i) {
                            final e = _card![i];
                            final plus = e.qtyDelta >= 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                dense: true,
                                onTap: e.docId > 0
                                    ? () => context.push(DocDetailUi(docId: e.docId))
                                    : null,
                                leading: Icon(docTypeIcon(e.docType), color: kCoreAccentDark),
                                title: Text(
                                    '${CoreDocType.title(e.docType)} · ${coreDate(e.docDate)}',
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: showCost
                                    ? Text(
                                        'qiymat: ${plus ? '+' : ''}${coreMoney(e.costDelta)}',
                                        style: TextStyle(
                                            fontSize: 11.5, color: Colors.grey.shade600))
                                    : null,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${plus ? '+' : ''}${coreFormatQty(e.qtyDelta, widget.baseUnit)}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: plus ? Colors.green.shade700 : Colors.red.shade700),
                                    ),
                                    Text(
                                      '= ${coreFormatQtyUnit(e.balance, widget.baseUnit)}',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: e.balance < 0 ? Colors.red : Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _batchesTab(bool showCost) {
    if (_batchErr != null) return CoreErrorView(message: _batchErr!, onRetry: _loadBatches);
    if (_batches == null) return const Center(child: CircularProgressIndicator.adaptive());
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
            onTap: b.docId > 0 ? () => context.push(DocDetailUi(docId: b.docId)) : null,
            title: Text('Partiya #${b.id} · ${coreDate(b.receivedAt, withTime: true)}',
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              'kirdi: ${coreFormatQtyUnit(b.qtyIn, widget.baseUnit)}'
              '${showCost ? ' · narx: ${coreMoney(b.unitCost)}/${widget.baseUnit}' : ''}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            trailing: Text(
              'qoldi: ${coreFormatQty(b.qtyLeft, widget.baseUnit)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}
