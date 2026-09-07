// core2/ui/integration_ui.dart — mone_core integratsiya (admin, perm
// integration.manage). SalePointsUi — sotuv nuqtalari ro'yxati + tahrir
// (nom, source konak/rk7, external_id, default ombor, qoidalar match/value/
// sklad, faol). ApiKeysUi — kalitlar ro'yxati, yaratish (nom + scopes) →
// kalit BIR MARTA dialogda, nusxalash; o'chirish. WebhooksUi — ro'yxat,
// qo'shish/tahrir (url, events, faol), o'chirish.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_integration.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_integration_service.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

// ───────────────────────── Sotuv nuqtalari ─────────────────────────

class SalePointsUi extends StatefulWidget {
  const SalePointsUi({super.key});

  @override
  State<SalePointsUi> createState() => _SalePointsUiState();
}

class _SalePointsUiState extends State<SalePointsUi> {
  final _service = CoreIntegrationService();
  List<CoreSalePoint>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _service.salePoints();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit(CoreSalePoint? p) async {
    final r = await showDialog<CoreSalePoint>(
      context: context,
      builder: (_) => _SalePointDialog(point: p),
    );
    if (r == null || !mounted) return;
    try {
      await _service.saveSalePoint(r);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dict = context.read<CoreDictProvider>();
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Sotuv nuqtalari',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        child: _error != null
            ? CoreErrorView(message: _error!, onRetry: _load)
            : _list == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _list!.isEmpty
                    ? const Center(child: Text('Sotuv nuqtasi yo\'q'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: _list!.length,
                        itemBuilder: (_, i) {
                          final p = _list![i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ListTile(
                              dense: true,
                              onTap: () => _edit(p),
                              leading: Icon(Icons.point_of_sale,
                                  color: p.active ? kCoreAccentDark : Colors.grey),
                              title: Text(p.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${p.source}:${p.externalId} · ombor: ${dict.skladName(p.skladId)}'
                                ' · ${p.rules.length} qoida${p.active ? '' : ' · nofaol'}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kCoreAccent,
        foregroundColor: Colors.white,
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _RuleEdit {
  String match;
  final TextEditingController value;
  int? skladId;
  _RuleEdit({this.match = 'category', String v = '', this.skladId})
      : value = TextEditingController(text: v);
  void dispose() => value.dispose();
}

class _SalePointDialog extends StatefulWidget {
  final CoreSalePoint? point;
  const _SalePointDialog({this.point});

  @override
  State<_SalePointDialog> createState() => _SalePointDialogState();
}

class _SalePointDialogState extends State<_SalePointDialog> {
  late final _name = TextEditingController(text: widget.point?.name ?? '');
  late final _ext = TextEditingController(text: widget.point?.externalId ?? '');
  late String _source = widget.point?.source ?? 'konak';
  late int? _sklad = widget.point?.skladId;
  late bool _active = widget.point?.active ?? true;
  late final List<_RuleEdit> _rules = [
    for (final r in widget.point?.rules ?? const <CoreSalePointRule>[])
      _RuleEdit(match: r.match, v: r.value, skladId: r.skladId),
  ];

  @override
  void dispose() {
    _name.dispose();
    _ext.dispose();
    for (final r in _rules) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sklads = context.read<CoreDictProvider>().sklads;
    return AlertDialog(
      title: Text(widget.point == null ? 'Yangi sotuv nuqtasi' : 'Tahrirlash'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, decoration: coreInput('Nomi')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _source,
                      decoration: coreInput('Manba'),
                      items: const [
                        DropdownMenuItem(value: 'konak', child: Text('konak')),
                        DropdownMenuItem(value: 'rk7', child: Text('rk7')),
                      ],
                      onChanged: (v) => setState(() => _source = v ?? _source),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(controller: _ext, decoration: coreInput('POS kodi (external_id)')),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CoreSkladDropdown(
                value: _sklad,
                label: 'Default ombor (yechish)',
                onChanged: (v) => setState(() => _sklad = v),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                      child: Text('Qoidalar (kategoriya/guruh/taom → ombor)',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                  TextButton.icon(
                    onPressed: () => setState(() => _rules.add(_RuleEdit())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Qoida'),
                  ),
                ],
              ),
              for (final r in _rules)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kCoreBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: DropdownButtonFormField<String>(
                              initialValue: r.match,
                              decoration: coreInput('match'),
                              items: const [
                                DropdownMenuItem(value: 'category', child: Text('category')),
                                DropdownMenuItem(value: 'group', child: Text('group')),
                                DropdownMenuItem(value: 'good', child: Text('good')),
                              ],
                              onChanged: (v) => setState(() => r.match = v ?? r.match),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(controller: r.value, decoration: coreInput('qiymat')),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _rules.remove(r);
                              r.dispose();
                            }),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int?>(
                        initialValue: sklads.any((s) => s.id == r.skladId) ? r.skladId : null,
                        isExpanded: true,
                        decoration: coreInput('→ ombor'),
                        items: [
                          for (final s in sklads)
                            DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
                        ],
                        onChanged: (v) => setState(() => r.skladId = v),
                      ),
                    ],
                  ),
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
            Navigator.pop(
              context,
              CoreSalePoint(
                id: widget.point?.id ?? 0,
                name: name,
                source: _source,
                externalId: _ext.text.trim(),
                skladId: _sklad,
                active: _active,
                rules: [
                  for (final r in _rules)
                    if (r.value.text.trim().isNotEmpty && r.skladId != null)
                      CoreSalePointRule(
                          match: r.match, value: r.value.text.trim(), skladId: r.skladId!),
                ],
              ),
            );
          },
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

// ───────────────────────── API kalitlar ─────────────────────────

class ApiKeysUi extends StatefulWidget {
  const ApiKeysUi({super.key});

  @override
  State<ApiKeysUi> createState() => _ApiKeysUiState();
}

class _ApiKeysUiState extends State<ApiKeysUi> {
  final _service = CoreIntegrationService();
  List<CoreApiKey>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _service.apiKeys();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final scopes = <String>{'read'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Yangi API kalit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameCtrl, autofocus: true, decoration: coreInput('Nomi')),
              const SizedBox(height: 10),
              const Text('Scopes', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in CoreApiKey.allScopes)
                    FilterChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      selected: scopes.contains(s),
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (v) => setS(() => v ? scopes.add(s) : scopes.remove(s)),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yaratish')),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || name.isEmpty || !mounted) return;
    try {
      final k = await _service.createApiKey(name, scopes.toList());
      if (!mounted) return;
      await _showKeyOnce(k);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  Future<void> _showKeyOnce(CoreApiKey k) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Kalit (faqat bir marta ko\'rsatiladi)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText(k.key,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 8),
            Text('Nusxalab xavfsiz joyga saqlang — bazada faqat hash qoladi.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: k.key));
              if (ctx.mounted) showCoreInfo(ctx, 'Nusxalandi');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Nusxalash'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Yopish')),
        ],
      ),
    );
  }

  Future<void> _delete(CoreApiKey k) async {
    final ok = await confirmDialog(context, 'O\'chirish', 'Kalit «${k.name}» o\'chirilsinmi?',
        okText: 'O\'chirish', danger: true);
    if (!ok || !mounted) return;
    try {
      await _service.deleteApiKey(k.id);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('API kalitlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        needDicts: false,
        child: _error != null
            ? CoreErrorView(message: _error!, onRetry: _load)
            : _list == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _list!.isEmpty
                    ? const Center(child: Text('Kalit yo\'q'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: _list!.length,
                        itemBuilder: (_, i) {
                          final k = _list![i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.vpn_key_outlined, color: kCoreAccentDark),
                              title: Text(k.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${k.scopes.join(', ')}${k.createdAt.isNotEmpty ? ' · ${coreDate(k.createdAt, withTime: true)}' : ''}',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              trailing: IconButton(
                                onPressed: () => _delete(k),
                                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                              ),
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kCoreAccent,
        foregroundColor: Colors.white,
        onPressed: _create,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ───────────────────────── Webhooklar ─────────────────────────

class WebhooksUi extends StatefulWidget {
  const WebhooksUi({super.key});

  @override
  State<WebhooksUi> createState() => _WebhooksUiState();
}

class _WebhooksUiState extends State<WebhooksUi> {
  final _service = CoreIntegrationService();
  List<CoreWebhook>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await _service.webhooks();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit(CoreWebhook? w) async {
    final urlCtrl = TextEditingController(text: w?.url ?? '');
    final events = <String>{...?w?.events};
    var active = w?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(w == null ? 'Yangi webhook' : 'Tahrirlash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: coreInput('URL', hint: 'https://…')),
              const SizedBox(height: 10),
              const Text('Hodisalar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final e in CoreWebhook.allEvents)
                    FilterChip(
                      label: Text(e, style: const TextStyle(fontSize: 12)),
                      selected: events.contains(e),
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (v) => setS(() => v ? events.add(e) : events.remove(e)),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Faol'),
                value: active,
                activeThumbColor: kCoreAccent,
                onChanged: (v) => setS(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Saqlash')),
          ],
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    urlCtrl.dispose();
    if (ok != true || url.isEmpty || !mounted) return;
    try {
      await _service.saveWebhook(
          CoreWebhook(id: w?.id ?? 0, url: url, events: events.toList(), active: active));
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  Future<void> _delete(CoreWebhook w) async {
    final ok = await confirmDialog(context, 'O\'chirish', '${w.url} o\'chirilsinmi?',
        okText: 'O\'chirish', danger: true);
    if (!ok || !mounted) return;
    try {
      await _service.deleteWebhook(w.id);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Webhooklar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        needDicts: false,
        child: _error != null
            ? CoreErrorView(message: _error!, onRetry: _load)
            : _list == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _list!.isEmpty
                    ? const Center(child: Text('Webhook yo\'q'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        itemCount: _list!.length,
                        itemBuilder: (_, i) {
                          final w = _list![i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ListTile(
                              dense: true,
                              onTap: () => _edit(w),
                              leading: Icon(Icons.webhook,
                                  color: w.active ? kCoreAccentDark : Colors.grey),
                              title: Text(w.url,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${w.events.join(', ')}${w.active ? '' : ' · nofaol'}',
                                  style: const TextStyle(fontSize: 11.5)),
                              trailing: IconButton(
                                onPressed: () => _delete(w),
                                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                              ),
                            ),
                          );
                        },
                      ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kCoreAccent,
        foregroundColor: Colors.white,
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
