// core2/ui/reports/recipe_cost_ui.dart — «Kalkulyatsiya kartasi»
// (Калькуляционная карта), `GET /reports/recipe-cost?good_id&date&qty`.
// Taom / yarim tayyor mahsulot tanlanadi (qidiruv) + sana; retsept
// `expand_sub` qoidasi bilan yoyiladi va har ingredient o'sha kungacha
// bo'lgan OXIRGI partiya narxida hisoblanadi: miqdor, oxirgi narx, narx
// sanasi, qator summasi, ulush %, pastda 1 birlik tannarxi.
//
// Narx topilmagan ingredient sariq belgi bilan (`no_price`), sikl tufayli
// yoyilmagan p/f lar alohida eslatmada (`cut`). «Excel (CSV)» AppBar'da.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_picker.dart';

class RecipeCostUi extends StatefulWidget {
  final int? goodId;
  final String? goodName;
  const RecipeCostUi({super.key, this.goodId, this.goodName});

  @override
  State<RecipeCostUi> createState() => _RecipeCostUiState();
}

class _RecipeCostUiState extends State<RecipeCostUi> {
  final _service = CoreReportsService();

  int? _goodId;
  String _goodName = '';
  String _date = CorePeriod.of(CorePeriodPreset.today).to;
  final int _qty = 1000; // base birlik: 1000 = 1 dona / kg / l

  CoreRecipeCost? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _goodId = widget.goodId;
    _goodName = widget.goodName ?? '';
    if (_goodId != null) _load();
  }

  Map<String, dynamic> get _query => {
        'good_id': _goodId,
        'date': _date,
        'qty': _qty,
      };

  Future<void> _load() async {
    final id = _goodId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.recipeCost(goodId: id, date: _date, qty: _qty);
      if (mounted) {
        setState(() {
          _data = r;
          if (_goodName.isEmpty) _goodName = r.goodName;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// «retsept yo'q» (422) — oddiy tilda.
  String _errorText(Object e) {
    final err = CoreClient.wrap(e);
    if (err.status == 422 && err.message.toLowerCase().contains('retsept')) {
      return 'Bu mahsulotga retsept kiritilmagan';
    }
    return coreReportErrorText(err);
  }

  Future<void> _pick() async {
    final g = await pickCoreGood(context);
    if (g == null) return;
    setState(() {
      _goodId = g.id;
      _goodName = g.name;
      _data = null;
    });
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
            const Text('Kalkulyatsiya kartasi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Калькуляционная карта'),
          ],
        ),
        actions: [
          if (_goodId != null)
            CoreExcelAction(
              onPressed: () => coreExportCsv(
                context,
                path: CoreReportPaths.recipeCost,
                query: _query,
                fileKey: 'kalkulyatsiya',
                from: _date,
                suffix: _goodName,
              ),
            ),
          if (_goodId != null)
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            CoreFilterBar(children: [
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.search, size: 18),
                label: Text(
                    _goodName.isEmpty ? 'Taom / p-f tanlash' : _goodName,
                    overflow: TextOverflow.ellipsis),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final v = await pickDate(context, _date);
                  if (v == null) return;
                  setState(() => _date = v);
                  _load();
                },
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Sana: ${coreDateUz(_date)}'),
              ),
              if (d != null)
                Chip(
                  label: Text(
                      'Hisob: ${coreQtyUnitUz(_qty, d.baseUnit)}',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.white,
                ),
            ]),
            if (d != null) _summary(context, d),
            if (d != null && !d.showCost) const CoreNoCostNote(),
            Expanded(
              child: _goodId == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Taom yoki yarim tayyor mahsulotni tanlang —\n'
                          'retsept bo\'yicha tannarx hisoblanadi',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : CoreReportBody(
                      loading: _loading,
                      error: _error,
                      onRetry: _load,
                      empty: d != null && d.lines.isEmpty,
                      emptyText: 'Retsept qatorlari yo\'q',
                      child: d == null
                          ? const SizedBox.shrink()
                          : _lines(context, d),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, CoreRecipeCost d) {
    final unit = coreUnitUz(d.priceUnit.isEmpty ? d.baseUnit : d.priceUnit);
    return CoreSummaryHeader(tiles: [
      CoreSummaryTile('Ingredient', '${d.lines.length}'),
      if (d.showCost) ...[
        CoreSummaryTile('Jami tannarx', coreSumUz(d.totalCost)),
        CoreSummaryTile('1 $unit tannarxi', coreSumUz(d.unitCost),
            color: kCoreAccentDark),
      ],
      CoreSummaryTile('Narx sanasi', coreDateUz(d.date)),
    ]);
  }

  Widget _lines(BuildContext context, CoreRecipeCost d) {
    final cols = coreReportColumns(const [
      CoreReportColumn('Ingredient'),
      CoreReportColumn('Miqdor', numeric: true),
      CoreReportColumn('Oxirgi narx', money: true, numeric: true),
      CoreReportColumn('Narx sanasi'),
      CoreReportColumn('Summa', money: true, numeric: true),
      CoreReportColumn('Ulush %', money: true, numeric: true),
    ], d.showCost);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoreReportTable(
            minWidth: d.showCost ? 760 : 380,
            columns: [
              for (final c in cols)
                DataColumn(label: Text(c.title), numeric: c.numeric),
            ],
            rows: [
              for (final l in d.lines)
                DataRow(cells: [
                  DataCell(SizedBox(
                    width: 220,
                    child: Row(children: [
                      if (l.noPrice)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.warning_amber,
                              size: 15, color: Colors.orange.shade800),
                        ),
                      Expanded(
                        child: Text(
                            l.goodName.isEmpty
                                ? 'Tovar #${l.goodId}'
                                : l.goodName,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  )),
                  DataCell(Text(coreQtyUnitUz(l.qty, l.baseUnit))),
                  if (d.showCost) ...[
                    DataCell(Text(
                        '${coreMoneyUz(l.lastPrice)} / ${coreUnitUz(l.priceUnit.isEmpty ? l.baseUnit : l.priceUnit)}')),
                    DataCell(Text(
                        l.priceDate.isEmpty ? '—' : coreDateUz(l.priceDate))),
                    DataCell(Text(coreMoneyUz(l.cost))),
                    DataCell(Text('${coreNumUz(l.sharePct, maxFrac: 1)} %')),
                  ],
                ]),
            ],
          ),
          if (d.noPrice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                '${d.noPrice.length} ta ingredientda narx topilmadi — tannarx to\'liq emas',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          if (d.cut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                '${d.cut.length} ta yarim tayyor mahsulot ichkariga yoyilmadi (retsept sikli)',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
            child: Text(
              'Yoyish qoidasi: ${d.rule.isEmpty ? 'expand_sub' : d.rule}.'
              ' Narx — ${coreDateUz(d.date)} kunigacha oxirgi partiya narxi'
              ' (hamma ombor), 1 ${coreUnitUz(d.priceUnit.isEmpty ? d.baseUnit : d.priceUnit)} uchun.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
