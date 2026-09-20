// core2/ui/reports/issues_report_ui.dart — «Hisobdan chiqarish sabablar
// bo'yicha» (Списание), `GET /reports/issues`. Posted `issue` hujjatlari
// (kassa sotuvi kirmaydi); kontragent = «sabab» (Списание Бухг., Хоз
// расход…). Guruhlash: sabab → ombor → tovarlar, har darajada summa.
//
// Filtrlar: davr (eslab qolinadi), ombor, sabab (kontragent; «Kontragentsiz»
// = `corr_id=0`). Pul ustunlari `show_cost` bo'yicha; «Excel (CSV)».
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_export.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

// ───────────────────── Guruhlash (sof mantiq — test bor) ─────────────────

/// Sabab ichidagi bitta ombor: tovarlar va ularning tannarx yig'indisi.
class IssueSkladGroup {
  final int skladId;
  final String skladName;
  final int cost;
  final List<CoreIssueRow> rows;
  const IssueSkladGroup({
    required this.skladId,
    required this.skladName,
    required this.cost,
    required this.rows,
  });
}

/// Sabab (kontragent) guruhi: omborlar va umumiy summa.
class IssueCorrGroup {
  final int corrId;
  final String corrName;
  final int cost;
  final List<IssueSkladGroup> sklads;
  const IssueCorrGroup({
    required this.corrId,
    required this.corrName,
    required this.cost,
    required this.sklads,
  });

  int get positions =>
      sklads.fold(0, (s, g) => s + g.rows.length);
}

/// `items` ni sabab → ombor → tovar ko'rinishida guruhlaydi; har daraja
/// summasi bo'yicha kamayish tartibida.
List<IssueCorrGroup> groupIssueRows(List<CoreIssueRow> items) {
  final byCorr = <int, List<CoreIssueRow>>{};
  final corrNames = <int, String>{};
  for (final r in items) {
    byCorr.putIfAbsent(r.corrId, () => []).add(r);
    corrNames[r.corrId] =
        r.corrName.isNotEmpty ? r.corrName : 'Kontragentsiz';
  }
  final out = <IssueCorrGroup>[];
  for (final e in byCorr.entries) {
    final bySklad = <int, List<CoreIssueRow>>{};
    final skladNames = <int, String>{};
    for (final r in e.value) {
      bySklad.putIfAbsent(r.skladId, () => []).add(r);
      skladNames[r.skladId] =
          r.skladName.isNotEmpty ? r.skladName : 'Ombor #${r.skladId}';
    }
    final groups = <IssueSkladGroup>[];
    for (final s in bySklad.entries) {
      final rows = [...s.value]..sort((a, b) => b.cost.compareTo(a.cost));
      groups.add(IssueSkladGroup(
        skladId: s.key,
        skladName: skladNames[s.key] ?? '',
        cost: rows.fold(0, (x, r) => x + r.cost),
        rows: rows,
      ));
    }
    groups.sort((a, b) => b.cost.compareTo(a.cost));
    out.add(IssueCorrGroup(
      corrId: e.key,
      corrName: corrNames[e.key] ?? '',
      cost: groups.fold(0, (x, g) => x + g.cost),
      sklads: groups,
    ));
  }
  out.sort((a, b) => b.cost.compareTo(a.cost));
  return out;
}

// ───────────────────────────── Ekran ─────────────────────────────

class IssuesReportUi extends StatefulWidget {
  const IssuesReportUi({super.key});

  @override
  State<IssuesReportUi> createState() => _IssuesReportUiState();
}

class _IssuesReportUiState extends State<IssuesReportUi> {
  static const String _key = 'spisaniye';

  final _service = CoreReportsService();
  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;
  int? _corr;

  CoreIssuesReport? _data;
  List<IssueCorrGroup> _groups = const [];
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
        if (_corr != null) 'corr_id': _corr,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.issues(
        dateFrom: _period.from,
        dateTo: _period.to,
        skladId: _sklad,
        corrId: _corr,
      );
      if (mounted) {
        setState(() {
          _data = r;
          // Guruhlash og'ir emas, lekin har build'da emas — yuklashda bir marta.
          _groups = groupIssueRows(r.items);
        });
      }
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
            const Text('Hisobdan chiqarish',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Списание — sabablar bo\'yicha'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.issues,
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
                empty: d != null && _groups.isEmpty,
                emptyText: 'Bu davrda hisobdan chiqarish yo\'q',
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) =>
                      _corrCard(context, _groups[i], d?.showCost ?? true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final corrs = context.select<CoreDictProvider, List<CoreCorr>>(
        (d) => d.corrs.where((c) => c.active).toList());
    final sorted = [...corrs]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return CoreFilterBar(children: [
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
      SizedBox(
        width: 240,
        child: DropdownButtonFormField<int?>(
          key: ValueKey('issue-corr-$_corr'),
          initialValue: _corr,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Sabab (kontragent)',
              border: OutlineInputBorder(),
              isDense: true),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Hammasi')),
            const DropdownMenuItem<int?>(value: 0, child: Text('Kontragentsiz')),
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
    ]);
  }

  Widget _summary(BuildContext context, CoreIssuesReport d) {
    final positions = _groups.fold(0, (s, g) => s + g.positions);
    return CoreSummaryHeader(tiles: [
      CoreSummaryTile('Sabablar', '${_groups.length}'),
      CoreSummaryTile('Pozitsiya', '$positions'),
      if (d.showCost)
        CoreSummaryTile('Jami tannarx', coreSumUz(d.totalCost),
            color: coreShortageColor(context)),
    ]);
  }

  Widget _corrCard(BuildContext context, IssueCorrGroup g, bool showCost) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          g.corrId == 0 ? Icons.help_outline : Icons.label_outline,
          color: g.corrId == 0 ? Colors.orange.shade700 : kCoreAccentDark,
        ),
        title: Text(g.corrName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text('${g.sklads.length} ombor · ${g.positions} pozitsiya',
            style: const TextStyle(fontSize: 11.5)),
        trailing: showCost
            ? Text(coreSumUz(g.cost),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13))
            : null,
        children: [
          for (final s in g.sklads)
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.only(left: 28, right: 16),
              title: Text(s.skladName, style: const TextStyle(fontSize: 13)),
              subtitle: Text('${s.rows.length} tovar',
                  style: const TextStyle(fontSize: 11)),
              trailing: showCost
                  ? Text(coreMoneyUz(s.cost),
                      style: const TextStyle(fontSize: 12.5))
                  : null,
              children: [
                for (final r in s.rows)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(44, 2, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  r.goodName.isEmpty
                                      ? 'Tovar #${r.goodId}'
                                      : r.goodName,
                                  style: const TextStyle(fontSize: 12.5)),
                              Text('${r.docs} hujjat',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(coreQtyUnitUz(r.qty, r.baseUnit),
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            if (showCost)
                              Text(coreSumUz(r.cost),
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade700)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
