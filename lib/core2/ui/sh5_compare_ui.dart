// core2/ui/sh5_compare_ui.dart — «SH5 solishtiruv» (Sh5CompareUi): parallel
// davrda har kuni ertalab hisoblanadigan SH5 ↔ yadro solishtiruvi
// (`GET /reports/sh5-compare?date=`; mone_core `cmd/sh5compare` yozadi).
// Sana tanlanadi (default — KECHA, chunki hisob ertalab o'tgan kun uchun
// yopiladi), xulosa (qatorlar, farqli, %), «Eng katta farqlar» jadvali
// (ombor, tovar, SH5, yadro, farq, so'm) va «Hujjatlar» jadvali (tur, SH5,
// yadro). Miqdorlar javobda BUTUN base birlikda (g/ml/mpcs) keladi —
// ko'rsatishda kg/l/dona (`coreFormatQty`, ÷1000, 3 kasrgacha).
// Endpoint hali yo'q/kun hisoblanmagan bo'lsa (404) «hali hisoblanmagan»
// ko'rsatiladi — xato emas.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_report.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class Sh5CompareUi extends StatefulWidget {
  const Sh5CompareUi({super.key});

  @override
  State<Sh5CompareUi> createState() => _Sh5CompareUiState();
}

class _Sh5CompareUiState extends State<Sh5CompareUi> {
  final _service = CoreStockService();
  // Default — kecha: solishtiruv ertalab (06:00) o'tgan kun uchun yopiladi.
  String _date = isoOf(DateTime.now().subtract(const Duration(days: 1)));
  CoreSh5Compare? _data;
  String? _error;
  // 404 — kun hali hisoblanmagan (yoki endpoint hali qo'shilmagan).
  bool _notReady = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notReady = false;
    });
    try {
      final d = await _service.sh5Compare(date: _date);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      final err = CoreClient.wrap(e);
      if (!mounted) return;
      setState(() {
        _data = null;
        if (err.status == 404 || err.code == 'not_found') {
          _notReady = true;
        } else {
          _error = err.display;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await pickDate(context, _date);
    if (d == null || d == _date) return;
    setState(() => _date = d);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('SH5 solishtiruv',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(child: _body()),
    );
  }

  Widget _body() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Kun: ${coreDate(_date)}'),
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
        ),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_notReady) {
      return CoreErrorView(
        message: '${coreDate(_date)} uchun solishtiruv hali hisoblanmagan.\n'
            'Hisob har kuni ertalab (06:00) o\'tgan kun uchun yopiladi.',
        onRetry: _load,
      );
    }
    if (_error != null) return CoreErrorView(message: _error!, onRetry: _load);
    final d = _data;
    if (d == null) return const Center(child: Text('Ma\'lumot yo\'q'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: [
          _summary(d),
          const SizedBox(height: 10),
          _topTable(d),
          const SizedBox(height: 10),
          _docsTable(d),
        ],
      ),
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

  // Farq ulushi 0,5 % dan oshsa qizil (qabul mezoni — PLAN_PARALLEL §3).
  Color _pctColor(double pct) =>
      pct > 0.5 ? Colors.red.shade700 : Colors.green.shade700;

  Widget _summary(CoreSh5Compare d) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.compare_arrows, color: kCoreAccentDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(coreDate(d.date.isEmpty ? _date : d.date),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _pctColor(d.diffPct).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${d.diffPct.toStringAsFixed(2)} %',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: _pctColor(d.diffPct))),
            ),
          ],
        ),
        const Divider(),
        kv('Qatorlar', '${d.rows}'),
        kv('Farqli qatorlar', '${d.diffRows}',
            bold: d.diffRows > 0),
        if (d.topSum > 0)
          kv('Eng katta farqlar summasi', '${coreMoney(d.topSum)} so\'m'),
        if (d.computedAt.isNotEmpty)
          kv('Hisoblangan', coreDate(d.computedAt, withTime: true)),
      ],
    ));
  }

  // Miqdor: javobda butun base birlik (g/ml/mpcs) — kg/l/dona ko'rinishida.
  String _qty(int base, String unit) =>
      coreFormatQty(base, unit.isEmpty ? 'g' : unit);

  String _skladName(CoreSh5DiffRow r, CoreDictProvider dict) {
    if (r.skladName.isNotEmpty) return r.skladName;
    return r.skladId > 0 ? dict.skladName(r.skladId) : '—';
  }

  String _goodName(CoreSh5DiffRow r, CoreDictProvider dict) {
    if (r.goodName.isNotEmpty) return r.goodName;
    return r.goodId > 0 ? dict.goodName(r.goodId) : '—';
  }

  Widget _topTable(CoreSh5Compare d) {
    final dict = context.read<CoreDictProvider>();
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Eng katta farqlar (${d.top.length})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (d.top.isEmpty)
          Text('Farq yo\'q', style: TextStyle(color: Colors.grey.shade600))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 40,
              columnSpacing: 14,
              headingTextStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              dataTextStyle: const TextStyle(fontSize: 12, color: Colors.black87),
              columns: const [
                DataColumn(label: Text('Ombor')),
                DataColumn(label: Text('Tovar')),
                DataColumn(label: Text('SH5'), numeric: true),
                DataColumn(label: Text('Yadro'), numeric: true),
                DataColumn(label: Text('Farq'), numeric: true),
                DataColumn(label: Text('So\'m'), numeric: true),
              ],
              rows: [
                for (final r in d.top)
                  DataRow(cells: [
                    DataCell(SizedBox(
                      width: 120,
                      child: Text(_skladName(r, dict),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(SizedBox(
                      width: 150,
                      child: Text(_goodName(r, dict),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(_qty(r.sh5, r.baseUnit))),
                    DataCell(Text(_qty(r.core, r.baseUnit))),
                    DataCell(Text(
                      '${r.diff > 0 ? '+' : ''}${_qty(r.diff, r.baseUnit)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: r.diff < 0
                              ? Colors.red.shade700
                              : Colors.green.shade700),
                    )),
                    DataCell(Text(coreMoney(r.sum))),
                  ]),
              ],
            ),
          ),
      ],
    ));
  }

  Widget _docsTable(CoreSh5Compare d) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Hujjatlar (tur bo\'yicha)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (d.docs.isEmpty)
          Text('Ma\'lumot yo\'q', style: TextStyle(color: Colors.grey.shade600))
        else
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade100),
                children: const [
                  _Cell('Tur', head: true),
                  _Cell('SH5', head: true, right: true),
                  _Cell('Yadro', head: true, right: true),
                  _Cell('Farq', head: true, right: true),
                ],
              ),
              for (final r in d.docs)
                TableRow(children: [
                  _Cell(CoreDocType.title(r.type)),
                  _Cell('${r.sh5}', right: true),
                  _Cell('${r.core}', right: true),
                  _Cell('${r.diff > 0 ? '+' : ''}${r.diff}',
                      right: true,
                      color: r.diff == 0
                          ? Colors.grey.shade600
                          : (r.diff < 0 ? Colors.red.shade700 : Colors.green.shade700)),
                ]),
            ],
          ),
      ],
    ));
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool head;
  final bool right;
  final Color? color;
  const _Cell(this.text, {this.head = false, this.right = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Text(
          text,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: head ? FontWeight.bold : FontWeight.normal,
            color: color ?? Colors.black87,
          ),
        ),
      );
}
