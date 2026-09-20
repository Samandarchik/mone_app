// core2/ui/reports/stock_value_ui.dart — «Qoldiq qiymati» (Ведомость
// остатков), `GET /reports/stock-value?date=`: ombor bo'yicha pozitsiyalar
// soni, manfiy qoldiqlar va qiymat. Server bu hisobotni bermasa
// `/stock/summary` (bir xil shakl) bilan ishlaydi — eski xatti-harakat
// saqlangan. «Excel (CSV)» — `?format=csv`.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class StockValueUi extends StatefulWidget {
  const StockValueUi({super.key});

  @override
  State<StockValueUi> createState() => _StockValueUiState();
}

class _StockValueUiState extends State<StockValueUi> {
  final _service = CoreStockService();
  String _date = CorePeriod.of(CorePeriodPreset.today).to;

  List<CoreStockSummary>? _rows;
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
      List<CoreStockSummary> r;
      try {
        r = await _service.stockValue(date: _date);
      } catch (_) {
        // Eski server: `/reports/stock-value` yo'q — `/stock/summary` shakli bir xil.
        r = await _service.summary(date: _date);
      }
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = coreReportErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showCost =
        context.select<CoreSession, bool>((s) => s.has(CorePerms.stockCostView));
    final dict = context.read<CoreDictProvider>();
    final rows = _rows ?? const <CoreStockSummary>[];
    final total = rows.fold<int>(0, (s, r) => s + (r.cost ?? 0));
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Qoldiq qiymati',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Ведомость остатков'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.stockValue,
              query: {'date': _date},
              fileKey: 'qoldiq-qiymati',
              from: _date,
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            CoreFilterBar(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDate(context, _date);
                  if (d == null) return;
                  setState(() => _date = d);
                  _load();
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Sana: ${coreDateUz(_date)}'),
              ),
            ]),
            if (_rows != null)
              CoreSummaryHeader(tiles: [
                CoreSummaryTile('Ombor', '${rows.length}'),
                if (showCost) CoreSummaryTile('Jami qiymat', coreSumUz(total)),
              ]),
            if (_rows != null && !showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: _rows != null && rows.isEmpty,
                child: ListView.builder(
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
                        leading: const Icon(Icons.warehouse_outlined,
                            color: kCoreAccentDark),
                        title: Text(
                            r.name.isNotEmpty ? r.name : dict.skladName(r.skladId),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${r.positions} pozitsiya'
                          '${r.qtyNegative > 0 ? ' · manfiy: ${r.qtyNegative}' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: r.qtyNegative > 0
                                ? coreShortageColor(context)
                                : Colors.grey.shade600,
                          ),
                        ),
                        trailing: showCost
                            ? Text(coreSumUz(r.cost ?? 0),
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold))
                            : null,
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
