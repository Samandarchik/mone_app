// core2/ui/dict_corrs_ui.dart — mone_core kontragentlari (DictCorrsUi):
// ro'yxat (nom, tur: supplier/payment/debtor/writeoff/other, faol), tur
// bo'yicha filtr chip, FAB «+» / qatorga bosish → dialog (nom, tur, faol).
// Yozish — perm dict.edit.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DictCorrsUi extends StatefulWidget {
  const DictCorrsUi({super.key});

  @override
  State<DictCorrsUi> createState() => _DictCorrsUiState();
}

class _DictCorrsUiState extends State<DictCorrsUi> {
  String? _kind;

  static String kindTitle(String k) {
    switch (k) {
      case 'supplier':
        return 'Ta\'minotchi';
      case 'payment':
        return 'To\'lov turi';
      case 'debtor':
        return 'Qarzdor';
      case 'writeoff':
        return 'Spisaniya';
      default:
        return 'Boshqa';
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.select<CoreSession, bool>((s) => s.has(CorePerms.dictEdit));
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Kontragentlar',
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Hammasi', style: TextStyle(fontSize: 12)),
                    selected: _kind == null,
                    selectedColor: kCoreAccent.withValues(alpha: 0.25),
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  for (final k in CoreCorr.kinds) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text(kindTitle(k), style: const TextStyle(fontSize: 12)),
                      selected: _kind == k,
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Selector<CoreDictProvider, List<CoreCorr>>(
                selector: (_, d) => d.corrs,
                builder: (context, all, _) {
                  final list = _kind == null
                      ? all
                      : all.where((c) => c.kind == _kind).toList();
                  if (list.isEmpty) return const Center(child: Text('Kontragent yo\'q'));
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          dense: true,
                          onTap: canEdit ? () => _edit(context, c) : null,
                          leading: Icon(Icons.person_outline,
                              color: c.active ? kCoreAccentDark : Colors.grey),
                          title: Text(c.name,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: c.active ? Colors.black87 : Colors.grey)),
                          subtitle: Text(
                              '#${c.id} · ${kindTitle(c.kind)}${c.active ? '' : ' · nofaol'}',
                              style: const TextStyle(fontSize: 11.5)),
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

  Future<void> _edit(BuildContext context, CoreCorr? c) async {
    final result = await showDialog<CoreCorr>(
      context: context,
      builder: (_) => _CorrDialog(corr: c, initialKind: _kind),
    );
    if (result == null || !context.mounted) return;
    try {
      await context.read<CoreDictProvider>().saveCorr(result);
      if (context.mounted) showCoreInfo(context, 'Saqlandi: ${result.name}');
    } catch (e) {
      if (context.mounted) showCoreError(context, e);
    }
  }
}

class _CorrDialog extends StatefulWidget {
  final CoreCorr? corr;
  final String? initialKind;
  const _CorrDialog({this.corr, this.initialKind});

  @override
  State<_CorrDialog> createState() => _CorrDialogState();
}

class _CorrDialogState extends State<_CorrDialog> {
  late final _name = TextEditingController(text: widget.corr?.name ?? '');
  late String _kind = widget.corr?.kind ?? widget.initialKind ?? 'supplier';
  late bool _active = widget.corr?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.corr == null ? 'Yangi kontragent' : 'Tahrirlash'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, autofocus: true, decoration: coreInput('Nomi')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: CoreCorr.kinds.contains(_kind) ? _kind : 'other',
            decoration: coreInput('Turi'),
            items: [
              for (final k in CoreCorr.kinds)
                DropdownMenuItem(value: k, child: Text(_DictCorrsUiState.kindTitle(k))),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
        ElevatedButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              CoreCorr(id: widget.corr?.id ?? 0, name: name, kind: _kind, active: _active),
            );
          },
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}
