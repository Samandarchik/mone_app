// core2/ui/reports/purchases_report_ui.dart — «Xaridlar va narx tarixi»
// (Приход / цены), `GET /reports/purchases`. Yetkazuvchi × tovar: hujjatlar
// soni, miqdor, summa, o'rtacha / eng past / eng yuqori / oxirgi narx va
// oldingi davrga nisbatan o'zgarish % (|Δ| ≥ 5 % — ▲ qizil / ▼ yashil).
//
// Filtrlar: davr (eslab qolinadi), yetkazuvchi, tovar. Tovar bosilsa —
// o'sha tovarning oxirgi 12 oylik xaridi (server ALOHIDA narx tarixi
// endpointini bermaydi — davr yig'masi ko'rsatiladi va shu aytiladi).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_picker.dart';

/// Jadvalda ko'rsatiladigan eng ko'p qator (qolgani Excel'da).
const int kPurchaseMaxRows = 300;

class PurchasesReportUi extends StatefulWidget {
  const PurchasesReportUi({super.key});

  @override
  State<PurchasesReportUi> createState() => _PurchasesReportUiState();
}

class _PurchasesReportUiState extends State<PurchasesReportUi> {
  static const String _key = 'xaridlar';

  final _service = CoreReportsService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _corr;
  CoreGood? _good;

  CorePurchasesReport? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await coreLoadPeriod(_key);
    if (!mounted) return;
    setState(() => _period = p);
    _load();
  }

  Map<String, dynamic> get _query => {
        'date_from': _period.from,
        'date_to': _period.to,
        if (_corr != null) 'corr_id': _corr,
        if (_good != null) 'good_id': _good!.id,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.purchases(
        dateFrom: _period.from,
        dateTo: _period.to,
        corrId: _corr,
        goodId: _good?.id,
      );
      if (mounted) setState(() => _data = r);
    } catch (e) {
      if (mounted) setState(() => _error = coreReportErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(CorePeriod p) {
    setState(() => _period = p);
    coreSavePeriod(_key, p);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Xaridlar va narx tarixi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Приход · narxlar'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.purchases,
              query: _query,
              fileKey: _key,
              from: _period.from,
              to: _period.to,
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            _filters(context),
            if (d != null) _summary(context, d),
            if (d != null && !d.showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: d != null && d.items.isEmpty,
                emptyText: 'Bu davrda xarid yo\'q',
                child: d == null
                    ? const SizedBox.shrink()
                    : _table(context, d),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final suppliers = context.select<CoreDictProvider, List<CoreCorr>>(
        (d) => d.corrsOfKind(const ['supplier', 'other']));
    final sorted = [...suppliers]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return CoreFilterBar(children: [
      CorePeriodBar(period: _period, onChanged: _setPeriod),
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<int?>(
          key: ValueKey('purch-corr-$_corr'),
          initialValue: sorted.any((c) => c.id == _corr) ? _corr : null,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Yetkazuvchi',
              border: OutlineInputBorder(),
              isDense: true),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Hammasi')),
            for (final c in sorted)
              DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            setState(() => _corr = v);
            _load();
          },
        ),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final g = await pickCoreGood(context);
          if (g == null) return;
          setState(() => _good = g);
          _load();
        },
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: Text(_good?.name ?? 'Tovar: hammasi',
            overflow: TextOverflow.ellipsis),
      ),
      if (_good != null)
        TextButton.icon(
          onPressed: () {
            setState(() => _good = null);
            _load();
          },
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Tovar filtrini olib tashlash'),
        ),
    ]);
  }

  Widget _summary(BuildContext context, CorePurchasesReport d) =>
      CoreSummaryHeader(tiles: [
        CoreSummaryTile('Pozitsiya', '${d.items.length}'),
        if (d.showCost)
          CoreSummaryTile('Jami xarid', coreSumUz(d.totalSum)),
        CoreSummaryTile('Oldingi davr',
            '${coreDateUz(d.prevFrom)} – ${coreDateUz(d.prevTo)}'),
      ]);

  Widget _table(BuildContext context, CorePurchasesReport d) {
    final items = [...d.items]..sort((a, b) => b.sum.compareTo(a.sum));
    final shown = items.take(kPurchaseMaxRows).toList();
    final cols = coreReportColumns(const [
      CoreReportColumn('Yetkazuvchi'),
      CoreReportColumn('Tovar'),
      CoreReportColumn('Miqdor', numeric: true),
      CoreReportColumn('Summa', money: true, numeric: true),
      CoreReportColumn('O\'rtacha narx', money: true, numeric: true),
      CoreReportColumn('Eng past', money: true, numeric: true),
      CoreReportColumn('Eng yuqori', money: true, numeric: true),
      CoreReportColumn('Oxirgi narx', money: true, numeric: true),
      CoreReportColumn('O\'zgarish', money: true, numeric: true),
    ], d.showCost);
    return SingleChildScrollView(
      child: Column(
        children: [
          CoreReportTable(
            minWidth: d.showCost ? 900 : 380,
            columns: [
              for (final c in cols)
                DataColumn(label: Text(c.title), numeric: c.numeric),
            ],
            rows: [
              for (final r in shown)
                DataRow(
                  onSelectChanged: (_) => context.push(PurchaseGoodHistoryUi(
                    goodId: r.goodId,
                    goodName: r.goodName,
                  )),
                  cells: [
                    DataCell(SizedBox(
                        width: 130,
                        child: Text(r.corrName, overflow: TextOverflow.ellipsis))),
                    DataCell(SizedBox(
                        width: 190,
                        child: Text(
                            r.goodName.isEmpty ? 'Tovar #${r.goodId}' : r.goodName,
                            overflow: TextOverflow.ellipsis))),
                    DataCell(Text(coreQtyUnitUz(r.qty, r.baseUnit))),
                    if (d.showCost) ...[
                      DataCell(Text(coreMoneyUz(r.sum))),
                      DataCell(Text(coreMoneyUz(r.avgPrice))),
                      DataCell(Text(coreMoneyUz(r.minPrice))),
                      DataCell(Text(coreMoneyUz(r.maxPrice))),
                      DataCell(Text(coreMoneyUz(r.lastPrice))),
                      DataCell(corePriceChangeText(context, r.priceChangePct)),
                    ],
                  ],
                ),
            ],
          ),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                '${shown.length} / ${items.length} qator ko\'rsatildi — to\'liq ro\'yxat «Excel (CSV)» da',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
          if (d.showCost)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Text(
                'Narxlar 1 ko\'rsatish birligi uchun (kg / l / dona / m).'
                ' O\'zgarish oldingi davr (${coreDateUz(d.prevFrom)} – ${coreDateUz(d.prevTo)}) o\'rtacha narxiga nisbatan.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────── Tovar narxi: oxirgi 12 oy (yig'ma) ───────────────────

/// Bitta tovarning xarid tarixi — server faqat DAVR YIG'MASINI beradi
/// (alohida narx tarixi endpointi yo'q), shuning uchun oxirgi 12 oy
/// yetkazuvchilar kesimida ko'rsatiladi va buning cheklovi aytiladi.
class PurchaseGoodHistoryUi extends StatefulWidget {
  final int goodId;
  final String goodName;
  const PurchaseGoodHistoryUi(
      {super.key, required this.goodId, required this.goodName});

  @override
  State<PurchaseGoodHistoryUi> createState() => _PurchaseGoodHistoryUiState();
}

class _PurchaseGoodHistoryUiState extends State<PurchaseGoodHistoryUi> {
  final _service = CoreReportsService();
  late final String _to = CorePeriod.of(CorePeriodPreset.today).to;
  late final String _from = CorePeriod.range(
    DateTime.now().subtract(const Duration(days: 365)),
    DateTime.now(),
  ).from;

  CorePurchasesReport? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.purchases(
          dateFrom: _from, dateTo: _to, goodId: widget.goodId);
      if (mounted) setState(() => _data = r);
    } catch (e) {
      if (mounted) setState(() => _error = coreReportErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final items = [...?d?.items]..sort((a, b) => b.lastDate.compareTo(a.lastDate));
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.goodName.isEmpty
                    ? 'Tovar #${widget.goodId}'
                    : widget.goodName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            coreSh5Subtitle('Xarid narxi · oxirgi 12 oy'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.purchases,
              query: {
                'date_from': _from,
                'date_to': _to,
                'good_id': widget.goodId,
              },
              fileKey: 'xarid-narxi',
              from: _from,
              to: _to,
              suffix: widget.goodName,
            ),
          ),
        ],
      ),
      body: CoreConnectGate(
        child: CoreReportBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          empty: d != null && items.isEmpty,
          emptyText: 'Oxirgi 12 oyda bu tovar xarid qilinmagan',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Server har bir hujjatdagi narxni alohida bermaydi — quyida'
                  ' ${coreDateUz(_from)} – ${coreDateUz(_to)} davrining'
                  ' yetkazuvchilar kesimidagi yig\'masi.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ),
              for (final r in items) _supplierCard(context, r, d?.showCost ?? true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supplierCard(BuildContext context, CorePurchaseRow r, bool showCost) {
    final unit = coreUnitUz(r.priceUnit.isEmpty ? r.baseUnit : r.priceUnit);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.corrName.isEmpty ? 'Yetkazuvchisiz' : r.corrName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (showCost) corePriceChangeText(context, r.priceChangePct),
            ],
          ),
          const SizedBox(height: 6),
          kv('Miqdor', '${coreQtyUnitUz(r.qty, r.baseUnit)} · ${r.docs} hujjat'),
          if (showCost) ...[
            kv('Summa', coreSumUz(r.sum)),
            kv('O\'rtacha narx', '${coreSumUz(r.avgPrice)} / $unit'),
            kv('Eng past – eng yuqori',
                '${coreMoneyUz(r.minPrice)} – ${coreMoneyUz(r.maxPrice)}'),
            kv('Oxirgi narx',
                '${coreSumUz(r.lastPrice)} / $unit · ${coreDateUz(r.lastDate)}',
                bold: true),
            if (r.prevAvgPrice > 0)
              kv('Oldingi davr o\'rtachasi', coreSumUz(r.prevAvgPrice)),
          ],
        ],
      ),
    );
  }
}
