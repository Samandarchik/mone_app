// core2/ui/reports/inventory_diff_ui.dart — «Kamomad va ortiqcha»
// (Сличительная ведомость), `GET /reports/inventory-diff`. Sanoq
// (inventory) hujjatlarining ledger deltalari: kamomad qizil, ortiqcha
// yashil, `net = ortiqcha − kamomad`.
//
// Filtrlar: davr (eslab qolinadi), ombor, tovar guruhi. Tablar:
// «Omborlar bo'yicha» (bosilsa o'sha ombor tovarlariga kiriladi),
// «Tovarlar bo'yicha» (kamomad summasi / farq / nom bo'yicha saralanadi),
// «Oylar bo'yicha» (oy → ombor). Pul ustunlari `show_cost` bo'yicha.
// AppBar: «Excel (CSV)» — joriy filtrlar bilan `?format=csv`.
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

/// Tovarlar tabining saralash tartibi.
enum InvDiffSort { shortage, net, name }

class InventoryDiffUi extends StatefulWidget {
  const InventoryDiffUi({super.key});

  @override
  State<InventoryDiffUi> createState() => _InventoryDiffUiState();
}

class _InventoryDiffUiState extends State<InventoryDiffUi>
    with SingleTickerProviderStateMixin {
  static const String _key = 'kamomad';

  final _service = CoreReportsService();
  late final TabController _tab = TabController(length: 3, vsync: this);

  CorePeriod _period = CorePeriod.of(CorePeriodPreset.thisMonth);
  int? _sklad;
  int? _group;
  InvDiffSort _sort = InvDiffSort.shortage;

  CoreInvDiffReport? _data;
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

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _query => {
        'date_from': _period.from,
        'date_to': _period.to,
        if (_sklad != null) 'sklad_id': _sklad,
        if (_group != null) 'group_id': _group,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.inventoryDiff(
        dateFrom: _period.from,
        dateTo: _period.to,
        skladId: _sklad,
        groupId: _group,
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
    final showCost = d?.showCost ?? true;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kamomad va ortiqcha',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            coreSh5Subtitle('Сличительная ведомость'),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.inventoryDiff,
              query: _query,
              fileKey: _key,
              from: _period.from,
              to: _period.to,
            ),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: kCoreAccent,
          labelColor: kCoreAccentDark,
          unselectedLabelColor: Colors.black54,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Omborlar bo\'yicha'),
            Tab(text: 'Tovarlar bo\'yicha'),
            Tab(text: 'Oylar bo\'yicha'),
          ],
        ),
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            _filters(context),
            if (d != null) _summary(context, d),
            if (d != null && !showCost) const CoreNoCostNote(),
            Expanded(
              child: CoreReportBody(
                loading: _loading,
                error: _error,
                onRetry: _load,
                empty: d != null && d.items.isEmpty && d.bySklad.isEmpty,
                emptyText: 'Bu davrda farqli sanoq yo\'q',
                child: d == null
                    ? const SizedBox.shrink()
                    : TabBarView(
                        controller: _tab,
                        children: [
                          _bySkladTab(context, d),
                          _byItemsTab(context, d),
                          _byMonthTab(context, d),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final groups = context.select<CoreDictProvider, List<CoreGoodGroup>>(
        (d) => d.groups);
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
        width: 220,
        child: DropdownButtonFormField<int?>(
          key: ValueKey('group-$_group'),
          initialValue: _group,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Guruh', border: OutlineInputBorder(), isDense: true),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Hammasi')),
            for (final g in groups)
              DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
          ],
          onChanged: (v) {
            setState(() => _group = v);
            _load();
          },
        ),
      ),
    ]);
  }

  Widget _summary(BuildContext context, CoreInvDiffReport d) {
    final t = d.total;
    return CoreSummaryHeader(tiles: [
      CoreSummaryTile('Farqli sanoq', '${t.docs} hujjat'),
      if (d.showCost) ...[
        CoreSummaryTile('Kamomad', coreSumUz(t.shortageSum),
            color: coreShortageColor(context)),
        CoreSummaryTile('Ortiqcha', coreSumUz(t.surplusSum),
            color: coreSurplusColor(context)),
        CoreSummaryTile('Sof farq', coreSumUz(t.netSum),
            color: coreSignColor(context, t.netSum)),
      ] else
        CoreSummaryTile('Pozitsiya', '${d.items.length}'),
    ]);
  }

  // ── Tab 1: omborlar ──
  Widget _bySkladTab(BuildContext context, CoreInvDiffReport d) {
    if (d.bySklad.isEmpty) {
      return const Center(child: Text('Ombor kesimi yo\'q'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: d.bySklad.length,
      itemBuilder: (_, i) => _skladCard(context, d, d.bySklad[i]),
    );
  }

  Widget _skladCard(
      BuildContext context, CoreInvDiffReport d, CoreInvDiffGroup g) {
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
        title: Text(g.skladName.isEmpty ? 'Ombor #${g.skladId}' : g.skladName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          d.showCost
              ? '${g.docs} sanoq · kamomad ${coreMoneyUz(g.shortageSum)} · ortiqcha ${coreMoneyUz(g.surplusSum)}'
              : '${g.docs} sanoq',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: d.showCost
            ? Text(coreSumUz(g.netSum),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: coreSignColor(context, g.netSum)))
            : const Icon(Icons.chevron_right),
        onTap: () => context.push(InventoryDiffSkladUi(
          skladId: g.skladId,
          skladName: g.skladName,
          period: _period,
          groupId: _group,
        )),
      ),
    );
  }

  // ── Tab 2: tovarlar ──
  Widget _byItemsTab(BuildContext context, CoreInvDiffReport d) {
    final rows = sortInvDiffItems(d.items, _sort);
    if (rows.isEmpty) return const Center(child: Text('Tovar kesimi yo\'q'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Text('Saralash:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final s in InvDiffSort.values) ...[
                    ChoiceChip(
                      label: Text(_sortLabel(s),
                          style: const TextStyle(fontSize: 12)),
                      selected: _sort == s,
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _sort = s),
                    ),
                    const SizedBox(width: 6),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: rows.length,
            itemBuilder: (_, i) => _itemRow(context, d, rows[i]),
          ),
        ),
      ],
    );
  }

  String _sortLabel(InvDiffSort s) => switch (s) {
        InvDiffSort.shortage => 'Kamomad summasi',
        InvDiffSort.net => 'Sof farq',
        InvDiffSort.name => 'Nomi',
      };

  Widget _itemRow(
      BuildContext context, CoreInvDiffReport d, CoreInvDiffRow r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.goodName.isEmpty ? 'Tovar #${r.goodId}' : r.goodName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${r.skladName} · ${r.docs} sanoq',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                coreQtyUnitUz(r.netQty, r.baseUnit),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: coreSignColor(context, r.netQty)),
              ),
              if (d.showCost)
                Text(coreSumUz(r.netSum),
                    style: TextStyle(
                        fontSize: 12, color: coreSignColor(context, r.netSum))),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab 3: oylar ──
  Widget _byMonthTab(BuildContext context, CoreInvDiffReport d) {
    if (d.byMonth.isEmpty) return const Center(child: Text('Oy kesimi yo\'q'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: d.byMonth.length,
      itemBuilder: (_, i) {
        final m = d.byMonth[i];
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
            title: Text(coreMonthUz(m.month),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text('${m.docs} farqli sanoq',
                style: const TextStyle(fontSize: 11.5)),
            trailing: d.showCost
                ? Text(coreSumUz(m.netSum),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: coreSignColor(context, m.netSum)))
                : null,
            children: [
              for (final s in m.sklads)
                ListTile(
                  dense: true,
                  title: Text(
                      s.skladName.isEmpty ? 'Ombor #${s.skladId}' : s.skladName,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${s.docs} sanoq',
                      style: const TextStyle(fontSize: 11)),
                  trailing: d.showCost
                      ? Text(coreSumUz(s.netSum),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: coreSignColor(context, s.netSum)))
                      : null,
                  onTap: () => context.push(InventoryDiffSkladUi(
                    skladId: s.skladId,
                    skladName: s.skladName,
                    period: _period,
                    groupId: _group,
                  )),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// «2026-08» → «Avgust 2026» (topilmasa o'zi).
String coreMonthUz(String month) {
  const names = [
    'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
    'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr', //
  ];
  final parts = month.split('-');
  if (parts.length < 2) return month.isEmpty ? '—' : month;
  final m = int.tryParse(parts[1]) ?? 0;
  if (m < 1 || m > 12) return month;
  return '${names[m - 1]} ${parts[0]}';
}

/// Tovar qatorlarini tanlangan tartibda saralash (sof mantiq — test bor).
List<CoreInvDiffRow> sortInvDiffItems(List<CoreInvDiffRow> src, InvDiffSort s) {
  final list = [...src];
  switch (s) {
    case InvDiffSort.shortage:
      list.sort((a, b) => b.shortageSum.compareTo(a.shortageSum));
    case InvDiffSort.net:
      list.sort((a, b) => a.netSum.compareTo(b.netSum));
    case InvDiffSort.name:
      list.sort((a, b) => a.goodName.toLowerCase().compareTo(b.goodName.toLowerCase()));
  }
  return list;
}

// ───────────────────── Ombor ichiga kirish (drill) ─────────────────────

/// Bitta ombor bo'yicha kamomad/ortiqcha tovarlari (eng katta kamomaddan).
class InventoryDiffSkladUi extends StatefulWidget {
  final int skladId;
  final String skladName;
  final CorePeriod period;
  final int? groupId;

  const InventoryDiffSkladUi({
    super.key,
    required this.skladId,
    required this.skladName,
    required this.period,
    this.groupId,
  });

  @override
  State<InventoryDiffSkladUi> createState() => _InventoryDiffSkladUiState();
}

class _InventoryDiffSkladUiState extends State<InventoryDiffSkladUi> {
  final _service = CoreReportsService();
  CoreInvDiffReport? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> get _query => {
        'date_from': widget.period.from,
        'date_to': widget.period.to,
        'sklad_id': widget.skladId,
        if (widget.groupId != null) 'group_id': widget.groupId,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _service.inventoryDiff(
        dateFrom: widget.period.from,
        dateTo: widget.period.to,
        skladId: widget.skladId,
        groupId: widget.groupId,
      );
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
    final rows = d == null
        ? const <CoreInvDiffRow>[]
        : sortInvDiffItems(d.items, InvDiffSort.net);
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.skladName.isEmpty
                    ? 'Ombor #${widget.skladId}'
                    : widget.skladName,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            coreSh5Subtitle(widget.period.fullLabel),
          ],
        ),
        actions: [
          CoreExcelAction(
            onPressed: () => coreExportCsv(
              context,
              path: CoreReportPaths.inventoryDiff,
              query: _query,
              fileKey: 'kamomad',
              from: widget.period.from,
              to: widget.period.to,
              suffix: widget.skladName,
            ),
          ),
        ],
      ),
      body: CoreConnectGate(
        child: CoreReportBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          empty: d != null && rows.isEmpty,
          emptyText: 'Bu omborda farq topilmadi',
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
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
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            'Kamomad ${coreQtyUnitUz(r.shortageQty, r.baseUnit)}'
                            ' · Ortiqcha ${coreQtyUnitUz(r.surplusQty, r.baseUnit)}',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(coreQtyUnitUz(r.netQty, r.baseUnit),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: coreSignColor(context, r.netQty))),
                        if (d?.showCost ?? true)
                          Text(coreSumUz(r.netSum),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: coreSignColor(context, r.netSum))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
