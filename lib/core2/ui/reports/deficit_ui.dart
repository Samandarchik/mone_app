// core2/ui/reports/deficit_ui.dart — «Defitsit» (partiyasiz chiqim),
// `GET /reports/deficit`: ombor × tovar bo'yicha partiyasiz (qoldiqsiz)
// yechilgan miqdor, uning oxirgi narxdagi qiymati, hujjatlar soni va davri.
// Qator bosilsa tovar kartochkasi ochiladi. «Excel (CSV)» — `?format=csv`.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
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
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DeficitUi extends StatefulWidget {
  const DeficitUi({super.key});

  @override
  State<DeficitUi> createState() => _DeficitUiState();
}

class _DeficitUiState extends State<DeficitUi> {
  static const String _key = 'defitsit';

  final _service = CoreStockService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;

  List<CoreDeficitRow>? _rows;
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
      final r = await _service.deficit(
          dateFrom: _period.from, dateTo: _period.to, skladId: _sklad);
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
    final dict = context.read<CoreDictProvider>();
    final rows = _rows ?? const <CoreDeficitRow>[];
    final totalCost = rows.fold<int>(0, (s, r) => s + r.cost);
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Defitsit',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Partiyasiz chiqim'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.deficit,
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
            if (_rows != null)
              CoreSummaryHeader(tiles: [
                CoreSummaryTile('Pozitsiya', '${rows.length}'),
                if (showCost)
                  CoreSummaryTile('Jami', coreSumUz(totalCost),
                      color: coreShortageColor(context)),
              ]),
            if (_rows != null && !showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: _rows != null && rows.isEmpty,
                emptyText: 'Defitsit yo\'q',
                child: ListView.builder(
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
                        onTap: () => context.push(StockCardUi(
                          skladId: r.skladId,
                          goodId: r.goodId,
                          goodName: r.goodName.isNotEmpty
                              ? r.goodName
                              : dict.goodName(r.goodId),
                          baseUnit: unit,
                        )),
                        leading: Icon(Icons.remove_circle_outline,
                            color: coreShortageColor(context)),
                        title: Text(
                            r.goodName.isNotEmpty
                                ? r.goodName
                                : dict.goodName(r.goodId),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${r.skladName.isNotEmpty ? r.skladName : dict.skladName(r.skladId)}'
                          ' · ${r.docs} hujjat · ${coreDateUz(r.firstDate)} – ${coreDateUz(r.lastDate)}'
                          '${showCost && r.cost != 0 ? ' · ${coreSumUz(r.cost)}' : ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Text(
                          coreQtyUnitUz(r.qty, unit),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: coreShortageColor(context)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
