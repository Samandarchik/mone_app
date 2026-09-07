// core2/ui/dict_sklads_ui.dart — mone_core omborlari (DictSkladsUi):
// ro'yxat (nom, tur, allow_negative, faol) + «ombor qo'shish 1 forma»
// (FAB → dialog: nom, tur, manfiy qoldiq rejimi, faol). Qatorga bosilsa
// tahrir. Yozish — perm dict.edit (tugmalar shunga qarab).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DictSkladsUi extends StatelessWidget {
  const DictSkladsUi({super.key});

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<CoreSession, bool>((s) => s.has(CorePerms.dictEdit));
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Omborlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () => context.read<CoreDictProvider>().ensureLoaded(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: CoreConnectGate(
        child: Selector<CoreDictProvider, List<CoreSklad>>(
          selector: (_, d) => d.sklads,
          builder: (context, sklads, _) => sklads.isEmpty
              ? const Center(child: Text('Ombor yo\'q — «+» bilan qo\'shing'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: sklads.length,
                  itemBuilder: (_, i) {
                    final s = sklads[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        dense: true,
                        onTap: canEdit ? () => _edit(context, s) : null,
                        leading: Icon(Icons.warehouse_outlined,
                            color: s.active ? kCoreAccentDark : Colors.grey),
                        title: Text(s.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: s.active ? Colors.black87 : Colors.grey)),
                        subtitle: Text(
                          '#${s.id} · ${s.kind.isEmpty ? '—' : s.kind} · manfiy: ${s.allowNegative}'
                          '${s.active ? '' : ' · nofaol'}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: canEdit ? const Icon(Icons.chevron_right) : null,
                      ),
                    );
                  },
                ),
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

  Future<void> _edit(BuildContext context, CoreSklad? s) async {
    final result = await showDialog<CoreSklad>(
      context: context,
      builder: (_) => _SkladDialog(sklad: s),
    );
    if (result == null || !context.mounted) return;
    try {
      await context.read<CoreDictProvider>().saveSklad(result);
      if (context.mounted) showCoreInfo(context, 'Saqlandi: ${result.name}');
    } catch (e) {
      if (context.mounted) showCoreError(context, e);
    }
  }
}

class _SkladDialog extends StatefulWidget {
  final CoreSklad? sklad;
  const _SkladDialog({this.sklad});

  @override
  State<_SkladDialog> createState() => _SkladDialogState();
}

class _SkladDialogState extends State<_SkladDialog> {
  late final _name = TextEditingController(text: widget.sklad?.name ?? '');
  late String _kind = widget.sklad?.kind.isNotEmpty == true ? widget.sklad!.kind : 'central';
  late String _neg = widget.sklad?.allowNegative ?? 'warn';
  late bool _active = widget.sklad?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kinds = {...CoreSklad.kinds, _kind}.toList();
    return AlertDialog(
      title: Text(widget.sklad == null ? 'Yangi ombor' : 'Omborni tahrirlash'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: coreInput('Nomi'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: coreInput('Turi'),
              items: [for (final k in kinds) DropdownMenuItem(value: k, child: Text(k))],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _neg,
              decoration: coreInput('Manfiy qoldiq'),
              items: const [
                DropdownMenuItem(value: 'strict', child: Text('strict — rad etish')),
                DropdownMenuItem(value: 'warn', child: Text('warn — ogohlantirish')),
                DropdownMenuItem(value: 'soft', child: Text('soft — jim')),
              ],
              onChanged: (v) => setState(() => _neg = v ?? _neg),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              CoreSklad(
                id: widget.sklad?.id ?? 0,
                name: name,
                kind: _kind,
                filialId: widget.sklad?.filialId,
                active: _active,
                allowNegative: _neg,
              ),
            );
          },
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}
