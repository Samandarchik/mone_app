// core2/ui/reports_ui.dart — mone_core hisobotlari (ReportsUi, perm
// report.view), 3 tab: Aylanma (/reports/turnover — ombor + davr, jadval:
// tovar, ochilish/kirim/chiqim/yopilish miqdor va qiymat), Qoldiq qiymati
// (/reports/stock-value — ombor bo'yicha pozitsiya, qiymat, jami), Defitsit
// (/reports/deficit — ombor×tovar jamlangan partiyasiz chiqimlar: miqdor,
// hujjatlar soni, davr; bosilsa tovar kartochkasi). Javoblar
// `{"items":[…]}`. Miqdorlar base'dan kg/l/dona ko'rinishda, pul butun so'm.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_report.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class ReportsUi extends StatefulWidget {
  const ReportsUi({super.key});

  @override
  State<ReportsUi> createState() => _ReportsUiState();
}

class _ReportsUiState extends State<ReportsUi> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Hisobotlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: kCoreAccent,
          labelColor: kCoreAccentDark,
          unselectedLabelColor: Colors.black54,
          tabs: const [
            Tab(text: 'Aylanma'),
            Tab(text: 'Qoldiq qiymati'),
            Tab(text: 'Defitsit'),
          ],
        ),
      ),
      body: CoreConnectGate(
        child: TabBarView(
          controller: _tab,
          children: const [_TurnoverTab(), _StockValueTab(), _DeficitTab()],
        ),
      ),
    );
  }
}

// ───────────────────────── Aylanma ─────────────────────────

class _TurnoverTab extends StatefulWidget {
  const _TurnoverTab();

  @override
  State<_TurnoverTab> createState() => _TurnoverTabState();
}

class _TurnoverTabState extends State<_TurnoverTab> with AutomaticKeepAliveClientMixin {
  final _service = CoreStockService();
  int? _sklad;
  String _from = isoOf(DateTime.now().subtract(const Duration(days: 30)));
  String _to = todayIso();
  List<CoreTurnoverRow>? _rows;
  String? _error;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.turnover(skladId: _sklad, dateFrom: _from, dateTo: _to);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _rows ?? const <CoreTurnoverRow>[];
    final dict = context.read<CoreDictProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            children: [
              CoreSkladDropdown(
                value: _sklad,
                label: 'Ombor',
                allowNull: true,
                onChanged: (v) => setState(() => _sklad = v),
              ),
              const SizedBox(height: 8),
              Row(
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
                        }
                      },
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('${coreDate(_from)} – ${coreDate(_to)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _load,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kCoreAccent, foregroundColor: Colors.white),
                    child: const Text('Ko\'rsatish'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? CoreErrorView(message: _error!, onRetry: _load)
              : _loading
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : _rows == null
                      ? const Center(child: Text('Davr tanlab «Ko\'rsatish» bosing'))
                      : rows.isEmpty
                          ? const Center(child: Text('Ma\'lumot yo\'q'))
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: DataTable(
                                  headingRowHeight: 36,
                                  dataRowMinHeight: 32,
                                  dataRowMaxHeight: 40,
                                  columnSpacing: 14,
                                  headingTextStyle: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                                  dataTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
                                  columns: const [
                                    DataColumn(label: Text('Tovar')),
                                    DataColumn(label: Text('Ochilish'), numeric: true),
                                    DataColumn(label: Text('Kirim'), numeric: true),
                                    DataColumn(label: Text('Chiqim'), numeric: true),
                                    DataColumn(label: Text('Yopilish'), numeric: true),
                                    DataColumn(label: Text('Yopilish, so\'m'), numeric: true),
                                  ],
                                  rows: [
                                    for (final r in rows)
                                      DataRow(cells: [
                                        DataCell(SizedBox(
                                          width: 160,
                                          child: Text(
                                              r.goodName.isNotEmpty ? r.goodName : dict.goodName(r.goodId),
                                              overflow: TextOverflow.ellipsis),
                                        )),
                                        DataCell(Text(coreFormatQtyUnit(r.openQty, _unit(r, dict)))),
                                        DataCell(Text('+${coreFormatQty(r.inQty, _unit(r, dict))}',
                                            style: TextStyle(color: Colors.green.shade700))),
                                        DataCell(Text('−${coreFormatQty(r.outQty, _unit(r, dict))}',
                                            style: TextStyle(color: Colors.red.shade700))),
                                        DataCell(Text(coreFormatQtyUnit(r.closeQty, _unit(r, dict)),
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: r.closeQty < 0 ? Colors.red : Colors.black87))),
                                        DataCell(Text(coreMoney(r.closeCost))),
                                      ]),
                                  ],
                                ),
                              ),
                            ),
        ),
      ],
    );
  }

  String _unit(CoreTurnoverRow r, CoreDictProvider dict) =>
      dict.goodById(r.goodId)?.baseUnit ?? r.baseUnit;
}

// ───────────────────────── Qoldiq qiymati ─────────────────────────

class _StockValueTab extends StatefulWidget {
  const _StockValueTab();

  @override
  State<_StockValueTab> createState() => _StockValueTabState();
}

class _StockValueTabState extends State<_StockValueTab> with AutomaticKeepAliveClientMixin {
  final _service = CoreStockService();
  String _date = todayIso();
  List<CoreStockSummary>? _rows;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      List<CoreStockSummary> r;
      try {
        r = await _service.stockValue(date: _date);
      } catch (_) {
        // /reports/stock-value hali bo'lmasa /stock/summary bilan bir xil shakl.
        r = await _service.summary(date: _date);
      }
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dict = context.read<CoreDictProvider>();
    final rows = _rows ?? const <CoreStockSummary>[];
    final total = rows.fold<int>(0, (s, r) => s + (r.cost ?? 0));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final d = await pickDate(context, _date);
                    if (d != null) {
                      setState(() => _date = d);
                      _load();
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Sana: ${coreDate(_date)}'),
                ),
              ),
              const SizedBox(width: 8),
              Text('Jami: ${coreMoney(total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? CoreErrorView(message: _error!, onRetry: _load)
              : _rows == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : rows.isEmpty
                      ? const Center(child: Text('Ma\'lumot yo\'q'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.warehouse_outlined, color: kCoreAccentDark),
                                title: Text(r.name.isNotEmpty ? r.name : dict.skladName(r.skladId),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${r.positions} pozitsiya'
                                  '${r.qtyNegative > 0 ? ' · manfiy: ${r.qtyNegative}' : ''}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: r.qtyNegative > 0 ? Colors.red.shade700 : Colors.grey.shade600),
                                ),
                                trailing: Text('${coreMoney(r.cost ?? 0)} so\'m',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ───────────────────────── Defitsit ─────────────────────────

class _DeficitTab extends StatefulWidget {
  const _DeficitTab();

  @override
  State<_DeficitTab> createState() => _DeficitTabState();
}

class _DeficitTabState extends State<_DeficitTab> with AutomaticKeepAliveClientMixin {
  final _service = CoreStockService();
  String _from = isoOf(DateTime.now().subtract(const Duration(days: 30)));
  String _to = todayIso();
  List<CoreDeficitRow>? _rows;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final r = await _service.deficit(dateFrom: _from, dateTo: _to);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dict = context.read<CoreDictProvider>();
    final rows = _rows ?? const <CoreDeficitRow>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: DateTime(now.year + 1),
                initialDateRange:
                    DateTimeRange(start: DateTime.parse(_from), end: DateTime.parse(_to)),
              );
              if (r != null) {
                setState(() {
                  _from = isoOf(r.start);
                  _to = isoOf(r.end);
                });
                _load();
              }
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text('${coreDate(_from)} – ${coreDate(_to)}'),
          ),
        ),
        Expanded(
          child: _error != null
              ? CoreErrorView(message: _error!, onRetry: _load)
              : _rows == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : rows.isEmpty
                      ? const Center(child: Text('Defitsit yo\'q'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final unit = r.baseUnit.isNotEmpty
                                ? r.baseUnit
                                : (dict.goodById(r.goodId)?.baseUnit ?? 'pcs');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: ListTile(
                                dense: true,
                                // Tovar kartochkasi — partiyasiz chiqimlar qaysi hujjatdan.
                                onTap: () => context.push(StockCardUi(
                                  skladId: r.skladId,
                                  goodId: r.goodId,
                                  goodName: r.goodName.isNotEmpty
                                      ? r.goodName
                                      : dict.goodName(r.goodId),
                                  baseUnit: unit,
                                )),
                                leading: Icon(Icons.remove_circle_outline,
                                    color: Colors.red.shade700),
                                title: Text(
                                    r.goodName.isNotEmpty ? r.goodName : dict.goodName(r.goodId),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${r.skladName.isNotEmpty ? r.skladName : dict.skladName(r.skladId)}'
                                  ' · ${r.docs} hujjat · ${coreDate(r.firstDate)} – ${coreDate(r.lastDate)}'
                                  '${r.cost != 0 ? ' · ${coreMoney(r.cost)} so\'m' : ''}',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: Text(
                                  coreFormatQtyUnit(r.qty, unit),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
