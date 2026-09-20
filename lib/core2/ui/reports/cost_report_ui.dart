// core2/ui/reports/cost_report_ui.dart — «Tannarx va food cost»
// (Себестоимость), `GET /reports/cost`: posted `act` flag=0 (taom)
// qatorlari — miqdor, ingredient tannarxi, 1 birlik tannarxi, sotuv summasi
// (`sale_amount`), foyda va food cost % (tannarx / sotuv).
//
// Eslatma (SH5_BIZNES_MANTIQ §8): bu hisobotga ilovadan `production` bilan
// kiritilgan sex mahsuloti KIRMAYDI — u «Ishlab chiqarish» hisobotida.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/recipe_cost_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Jadvalda ko'rsatiladigan eng ko'p qator (qolgani Excel'da).
const int kCostMaxRows = 300;

class CostReportUi extends StatefulWidget {
  const CostReportUi({super.key});

  @override
  State<CostReportUi> createState() => _CostReportUiState();
}

class _CostReportUiState extends State<CostReportUi> {
  static const String _key = 'tannarx';

  final _service = CoreReportsService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;

  CoreCostReport? _data;
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
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.cost(
          dateFrom: _period.from, dateTo: _period.to, skladId: _sklad);
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
    final canCost =
        context.select<CoreSession, bool>((s) => s.has(CorePerms.stockCostView));
    final d = _data;
    final showCost = (d?.showCost ?? true) && canCost;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tannarx va food cost',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Себестоимость'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.cost,
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
                width: 220,
                child: CoreSkladDropdown(
                  value: _sklad,
                  label: 'Ombor',
                  allowNull: true,
                  onChanged: (v) {
                    setState(() => _sklad = v);
                    _load();
                  },
                ),
              ),
            ]),
            if (d != null)
              CoreSummaryHeader(tiles: [
                CoreSummaryTile('Taom', '${d.items.length}'),
                if (showCost) ...[
                  CoreSummaryTile('Tannarx', coreSumUz(d.totalCost)),
                  CoreSummaryTile('Sotuv', coreSumUz(d.totalSale)),
                  CoreSummaryTile('Foyda', coreSumUz(d.totalProfit),
                      color: coreSignColor(context, d.totalProfit)),
                ],
              ]),
            if (d != null && !showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: d != null && d.items.isEmpty,
                emptyText: 'Bu davrda akt qatorlari yo\'q',
                child:
                    d == null ? const SizedBox.shrink() : _table(context, d, showCost),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context, CoreCostReport d, bool showCost) {
    final items = [...d.items]..sort((a, b) => b.cost.compareTo(a.cost));
    final shown = items.take(kCostMaxRows).toList();
    final cols = coreReportColumns(const [
      CoreReportColumn('Taom'),
      CoreReportColumn('Miqdor (akt)', numeric: true),
      CoreReportColumn('Tannarx', money: true, numeric: true),
      CoreReportColumn('1 birlik', money: true, numeric: true),
      CoreReportColumn('Sotuv', money: true, numeric: true),
      CoreReportColumn('Foyda', money: true, numeric: true),
      CoreReportColumn('Food cost', money: true, numeric: true),
    ], showCost);
    return SingleChildScrollView(
      child: Column(
        children: [
          CoreReportTable(
            minWidth: showCost ? 860 : 380,
            columns: [
              for (final c in cols)
                DataColumn(label: Text(c.title), numeric: c.numeric),
            ],
            rows: [
              for (final r in shown)
                DataRow(
                  onSelectChanged: (_) => context.push(
                      RecipeCostUi(goodId: r.goodId, goodName: r.goodName)),
                  cells: [
                    DataCell(SizedBox(
                        width: 210,
                        child: Text(
                            r.goodName.isEmpty ? 'Tovar #${r.goodId}' : r.goodName,
                            overflow: TextOverflow.ellipsis))),
                    DataCell(Text(coreQtyUnitUz(r.qty, r.baseUnit))),
                    if (showCost) ...[
                      DataCell(Text(coreMoneyUz(r.cost))),
                      DataCell(Text(coreMoneyUz(r.unitCost))),
                      DataCell(Text(coreMoneyUz(r.sale))),
                      DataCell(Text(coreMoneyUz(r.profit),
                          style: TextStyle(
                              color: coreSignColor(context, r.profit)))),
                      DataCell(Text(r.foodCostPct == null
                          ? '—'
                          : '${coreNumUz(r.foodCostPct!, maxFrac: 1)} %')),
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Text(
              'Faqat `act` (taom) qatorlari. Qatorni bosing — kalkulyatsiya kartasi (reja tannarxi).',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
