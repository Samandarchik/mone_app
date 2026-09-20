// core2/ui/reports/production_report_ui.dart — «Ishlab chiqarish»
// (Акт выпуска), `GET /reports/production`. Posted `act` + `production`
// mahsulot qatorlari: mahsulot × qabul qiluvchi ombor, miqdor, ingredient
// tannarxi va 1 birlik tannarxi. `qty_from_other` > 0 bo'lgan qatorlarda
// «boshqa ombor xomashyosi» belgisi (ЦЕХ → МАГАЗИН oqimi).
//
// Filtrlar: davr (eslab qolinadi), ombor (xomashyo YOKI mahsulot ombori),
// «Kassa sotuvi ham» (`include_sales=1`). «Excel (CSV)» AppBar'da.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/recipe_cost_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Jadvalda ko'rsatiladigan eng ko'p qator (qolgani Excel'da).
const int kProductionMaxRows = 300;

class ProductionReportUi extends StatefulWidget {
  const ProductionReportUi({super.key});

  @override
  State<ProductionReportUi> createState() => _ProductionReportUiState();
}

class _ProductionReportUiState extends State<ProductionReportUi> {
  static const String _key = 'ishlab-chiqarish';

  final _service = CoreReportsService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;
  bool _includeSales = false;

  CoreProductionReport? _data;
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
        if (_sklad != null) 'sklad_id': _sklad,
        if (_includeSales) 'include_sales': 1,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.production(
        dateFrom: _period.from,
        dateTo: _period.to,
        skladId: _sklad,
        includeSales: _includeSales,
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
            const Text('Ishlab chiqarish',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Акт выпуска · Переработка'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.production,
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
            CoreFilterBar(children: [
              CorePeriodBar(period: _period, onChanged: _setPeriod),
              SizedBox(
                width: 240,
                child: CoreSkladDropdown(
                  value: _sklad,
                  label: 'Ombor (xomashyo yoki mahsulot)',
                  allowNull: true,
                  onChanged: (v) {
                    setState(() => _sklad = v);
                    _load();
                  },
                ),
              ),
              FilterChip(
                label: const Text('Kassa sotuvi ham'),
                selected: _includeSales,
                selectedColor: kCoreAccent.withValues(alpha: 0.25),
                onSelected: (v) {
                  setState(() => _includeSales = v);
                  _load();
                },
              ),
            ]),
            if (d != null) _summary(context, d),
            if (d != null && !d.showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: d != null && d.items.isEmpty,
                emptyText: 'Bu davrda ishlab chiqarish yo\'q',
                child: d == null ? const SizedBox.shrink() : _body(context, d),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, CoreProductionReport d) {
    final other = d.items.where((r) => r.fromOtherSklad).length;
    return CoreSummaryHeader(tiles: [
      CoreSummaryTile('Pozitsiya', '${d.items.length}'),
      if (d.showCost)
        CoreSummaryTile('Ingredient tannarxi', coreSumUz(d.totalCost)),
      CoreSummaryTile('Boshqa ombor xomashyosi', '$other qator',
          color: other > 0 ? Colors.orange.shade800 : null),
    ]);
  }

  Widget _body(BuildContext context, CoreProductionReport d) {
    final items = [...d.items]
      ..sort((a, b) => d.showCost
          ? b.cost.compareTo(a.cost)
          : b.qty.compareTo(a.qty));
    final shown = items.take(kProductionMaxRows).toList();
    final cols = coreReportColumns(const [
      CoreReportColumn('Mahsulot'),
      CoreReportColumn('Mahsulot ombori'),
      CoreReportColumn('Hujjat', numeric: true),
      CoreReportColumn('Miqdor', numeric: true),
      CoreReportColumn('Ingredient tannarxi', money: true, numeric: true),
      CoreReportColumn('1 birlik tannarxi', money: true, numeric: true),
    ], d.showCost);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoreReportTable(
            minWidth: d.showCost ? 820 : 520,
            columns: [
              for (final c in cols)
                DataColumn(label: Text(c.title), numeric: c.numeric),
            ],
            rows: [
              for (final r in shown)
                DataRow(
                  // Reja tannarxi bilan solishtirish — kalkulyatsiya kartasi.
                  onSelectChanged: (_) => context.push(RecipeCostUi(
                    goodId: r.goodId,
                    goodName: r.goodName,
                  )),
                  cells: [
                    DataCell(SizedBox(
                      width: 210,
                      child: Row(children: [
                        if (r.fromOtherSklad)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: 'Xomashyo boshqa ombordan: '
                                  '${coreQtyUnitUz(r.qtyFromOther, r.baseUnit)}',
                              child: Icon(Icons.alt_route,
                                  size: 15, color: Colors.orange.shade800),
                            ),
                          ),
                        Expanded(
                          child: Text(
                              r.goodName.isEmpty
                                  ? 'Tovar #${r.goodId}'
                                  : r.goodName,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    )),
                    DataCell(SizedBox(
                        width: 150,
                        child: Text(r.toSkladName,
                            overflow: TextOverflow.ellipsis))),
                    DataCell(Text('${r.docs}')),
                    DataCell(Text(coreQtyUnitUz(r.qty, r.baseUnit))),
                    if (d.showCost) ...[
                      DataCell(Text(coreMoneyUz(r.cost))),
                      DataCell(Text(
                          '${coreMoneyUz(r.unitCost)} / ${coreUnitUz(r.priceUnit.isEmpty ? r.baseUnit : r.priceUnit)}')),
                    ],
                  ],
                ),
            ],
          ),
          if (items.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                '${shown.length} / ${items.length} qator ko\'rsatildi — to\'liq ro\'yxat «Excel (CSV)» da',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Text(
              '⤳ belgisi — xomashyosi boshqa ombordan yechilgan qator.'
              ' Qatorni bosing: reja tannarxi (kalkulyatsiya kartasi).',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          if (d.totals.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text('Omborlar bo\'yicha',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final t in d.totals)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListTile(
                  dense: true,
                  leading:
                      const Icon(Icons.warehouse_outlined, color: kCoreAccentDark),
                  title: Text(
                      t.toSkladName.isEmpty
                          ? 'Ombor #${t.toSklad}'
                          : t.toSkladName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${t.positions} pozitsiya',
                      style: const TextStyle(fontSize: 11.5)),
                  trailing: d.showCost
                      ? Text(coreSumUz(t.cost),
                          style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
                ),
              ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
