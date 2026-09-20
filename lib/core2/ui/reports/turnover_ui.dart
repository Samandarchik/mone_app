// core2/ui/reports/turnover_ui.dart — «Aylanma» (Оборотная ведомость),
// `GET /reports/turnover`: tovar bo'yicha ochilish qoldig'i + kirim − chiqim
// = yopilish (miqdor va qiymat). Avval `reports_ui.dart` dagi tab edi —
// endi o'z ekrani, davr eslab qolinadi va «Excel (CSV)» bor.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_report.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Jadvalda ko'rsatiladigan eng ko'p qator (qolgani Excel'da).
const int kTurnoverMaxRows = 300;

class TurnoverUi extends StatefulWidget {
  const TurnoverUi({super.key});

  @override
  State<TurnoverUi> createState() => _TurnoverUiState();
}

class _TurnoverUiState extends State<TurnoverUi> {
  static const String _key = 'aylanma';

  final _service = CoreStockService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;

  List<CoreTurnoverRow>? _rows;
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
      final r = await _service.turnover(
          skladId: _sklad, dateFrom: _period.from, dateTo: _period.to);
      if (mounted) setState(() => _rows = r);
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
    final showCost =
        context.select<CoreSession, bool>((s) => s.has(CorePerms.stockCostView));
    final rows = _rows ?? const <CoreTurnoverRow>[];
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aylanma',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Оборотная ведомость'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.turnover,
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
            if (_rows != null && !showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: _rows != null && rows.isEmpty,
                child: _table(context, rows, showCost),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(
      BuildContext context, List<CoreTurnoverRow> rows, bool showCost) {
    final dict = context.read<CoreDictProvider>();
    final shown = rows.take(kTurnoverMaxRows).toList();
    final cols = coreReportColumns(const [
      CoreReportColumn('Tovar'),
      CoreReportColumn('Ochilish', numeric: true),
      CoreReportColumn('Kirim', numeric: true),
      CoreReportColumn('Chiqim', numeric: true),
      CoreReportColumn('Yopilish', numeric: true),
      CoreReportColumn('Yopilish, so\'m', money: true, numeric: true),
    ], showCost);
    return SingleChildScrollView(
      child: Column(
        children: [
          CoreReportTable(
            minWidth: showCost ? 760 : 620,
            columns: [
              for (final c in cols)
                DataColumn(label: Text(c.title), numeric: c.numeric),
            ],
            rows: [
              for (final r in shown)
                () {
                  final unit = dict.goodById(r.goodId)?.baseUnit ?? r.baseUnit;
                  return DataRow(cells: [
                    DataCell(SizedBox(
                      width: 200,
                      child: Text(
                          r.goodName.isNotEmpty
                              ? r.goodName
                              : dict.goodName(r.goodId),
                          overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(coreQtyUnitUz(r.openQty, unit))),
                    DataCell(Text('+${coreQtyUz(r.inQty, unit)}',
                        style: TextStyle(color: coreSurplusColor(context)))),
                    DataCell(Text('−${coreQtyUz(r.outQty, unit)}',
                        style: TextStyle(color: coreShortageColor(context)))),
                    DataCell(Text(coreQtyUnitUz(r.closeQty, unit),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: r.closeQty < 0
                                ? coreShortageColor(context)
                                : Colors.black87))),
                    if (showCost) DataCell(Text(coreMoneyUz(r.closeCost))),
                  ]);
                }(),
            ],
          ),
          if (rows.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Text(
                '${shown.length} / ${rows.length} qator ko\'rsatildi — to\'liq ro\'yxat «Excel (CSV)» da',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}
