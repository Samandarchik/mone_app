// core2/ui/dict_goods_ui.dart — mone_core tovarlari (DictGoodsUi): qidiruv
// (lokal kesh), ro'yxat (nom, guruh, base birlik, п/ф/taom belgisi), FAB
// «+» / qatorga bosish → forma: nom, guruh, base birlik (g/ml/mpcs/mm —
// server faqat 1/1000 base kodlarini oladi), qo'shimcha birliklar (unit +
// to_base butun), rk_code, faol. PUT qisman (units berilsa to'liq almashadi).
// Yozish — perm dict.edit.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DictGoodsUi extends StatefulWidget {
  const DictGoodsUi({super.key});

  @override
  State<DictGoodsUi> createState() => _DictGoodsUiState();
}

class _DictGoodsUiState extends State<DictGoodsUi> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<CoreSession, bool>((s) => s.has(CorePerms.dictEdit));
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Tovarlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () => context.read<CoreDictProvider>().ensureLoaded(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Tovar qidirish...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Consumer<CoreDictProvider>(
                builder: (context, dict, _) {
                  final list = dict.searchGoods(_q, limit: 300, onlyActive: false);
                  if (list.isEmpty) return const Center(child: Text('Topilmadi'));
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final g = list[i];
                      final group = dict.groupById(g.groupId)?.name;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          dense: true,
                          onTap: canEdit ? () => _edit(context, g) : null,
                          title: Text(g.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: g.active ? Colors.black87 : Colors.grey)),
                          subtitle: Text(
                            [
                              '#${g.id}',
                              coreDisplayUnit(g.baseUnit),
                              if (group != null && group.isNotEmpty) group,
                              if (g.units.isNotEmpty)
                                g.units.map((u) => '${u.unit}=${u.toBase}').join(', '),
                              if (g.isSemi) 'п/ф',
                              if (g.isComplect) 'taom',
                              if (g.rkCode.isNotEmpty) 'rk:${g.rkCode}',
                              if (!g.active) 'nofaol',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          trailing: canEdit ? const Icon(Icons.chevron_right) : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              backgroundColor: kCoreAccent,
              foregroundColor: Colors.white,
              onPressed: () => _edit(context, null),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _edit(BuildContext context, CoreGood? g) async {
    final result = await showDialog<CoreGood>(
      context: context,
      builder: (_) => _GoodDialog(good: g),
    );
    if (result == null || !context.mounted) return;
    try {
      await context.read<CoreDictProvider>().saveGood(result);
      if (context.mounted) showCoreInfo(context, 'Saqlandi: ${result.name}');
    } catch (e) {
      if (context.mounted) showCoreError(context, e);
    }
  }
}

class _UnitEdit {
  final TextEditingController unit;
  final TextEditingController toBase;
  _UnitEdit(String u, int b)
      : unit = TextEditingController(text: u),
        toBase = TextEditingController(text: b > 0 ? '$b' : '');
  void dispose() {
    unit.dispose();
    toBase.dispose();
  }
}

class _GoodDialog extends StatefulWidget {
  final CoreGood? good;
  const _GoodDialog({this.good});

  @override
  State<_GoodDialog> createState() => _GoodDialogState();
}

class _GoodDialogState extends State<_GoodDialog> {
  late final _name = TextEditingController(text: widget.good?.name ?? '');
  late final _rk = TextEditingController(text: widget.good?.rkCode ?? '');
  late int? _group = widget.good?.groupId;
  late String _base = widget.good?.baseUnit ?? 'mpcs';
  late bool _semi = widget.good?.isSemi ?? false;
  late bool _complect = widget.good?.isComplect ?? false;
  late bool _active = widget.good?.active ?? true;
  late final List<_UnitEdit> _units = [
    for (final u in widget.good?.units ?? const <CoreGoodUnit>[])
      _UnitEdit(u.unit, u.toBase),
  ];

  @override
  void dispose() {
    _name.dispose();
    _rk.dispose();
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.read<CoreDictProvider>().groups;
    return AlertDialog(
      title: Text(widget.good == null ? 'Yangi tovar' : 'Tovarni tahrirlash'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: coreInput('Nomi'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: groups.any((g) => g.id == _group) ? _group : null,
                isExpanded: true,
                decoration: coreInput('Guruh'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  for (final g in groups)
                    DropdownMenuItem<int?>(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _group = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: CoreGood.baseUnits.contains(_base) ? _base : 'mpcs',
                decoration: coreInput('Base birlik (saqlash, 1/1000)'),
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('g — gramm (UI: kg)')),
                  DropdownMenuItem(value: 'ml', child: Text('ml — millilitr (UI: l)')),
                  DropdownMenuItem(value: 'mpcs', child: Text('mpcs — 0.001 dona (UI: dona)')),
                  DropdownMenuItem(value: 'mm', child: Text('mm — millimetr (UI: m)')),
                ],
                onChanged: widget.good == null
                    ? (v) => setState(() => _base = v ?? _base)
                    : null, // mavjud tovarning base birligi o'zgarmaydi
              ),
              const SizedBox(height: 10),
              TextField(controller: _rk, decoration: coreInput('RK/POS kodi (ixtiyoriy)')),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text('Qo\'shimcha birliklar',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _units.add(_UnitEdit('', 0))),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Birlik'),
                  ),
                ],
              ),
              for (final u in _units)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: u.unit,
                          decoration: coreInput('Birlik', hint: 'pack'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: u.toBase,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: coreInput('= base', hint: '1000'),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _units.remove(u);
                          u.dispose();
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Полуфабрикат'),
                value: _semi,
                activeThumbColor: kCoreAccent,
                onChanged: (v) => setState(() => _semi = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Taom (komplekt)'),
                value: _complect,
                activeThumbColor: kCoreAccent,
                onChanged: (v) => setState(() => _complect = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Faol'),
                value: _active,
                activeThumbColor: kCoreAccent,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final units = <CoreGoodUnit>[];
            for (final u in _units) {
              final code = u.unit.text.trim();
              final tb = int.tryParse(u.toBase.text.trim()) ?? 0;
              if (code.isNotEmpty && tb > 0) {
                units.add(CoreGoodUnit(unit: code, toBase: tb));
              }
            }
            Navigator.pop(
              context,
              CoreGood(
                id: widget.good?.id ?? 0,
                name: name,
                groupId: _group,
                baseUnit: _base,
                isComplect: _complect,
                isSemi: _semi,
                rkCode: _rk.text.trim(),
                active: _active,
                units: units,
              ),
            );
          },
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}
