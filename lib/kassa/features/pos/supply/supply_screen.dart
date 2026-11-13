// supply_screen.dart — kassa «Yuk»: markazdan kelgan yukni qabul qilish va
// smena boshida qoldiqni sanash (Mone filial_supply.go ↔ pos_backend
// /api/mone/incoming, /api/mone/stock-count). SupplyScreen, _IncomingTab, _CountTab.
//
// Miqdorlar serverda MILLI butun son (кг/л → гр/мл, шт → dona×1000);
// ekranda birlikda (1.5 кг, 3 шт) ko'rsatiladi va kiritiladi.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';

String _errMsg(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['message'] != null) return d['message'].toString();
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Kassa serveri bilan aloqa yo‘q';
    }
  }
  return e.toString();
}

int _asInt(dynamic v) => v is num ? v.round() : int.tryParse('$v') ?? 0;

/// milli → «1.5» (birliksiz, ortiqcha nolsiz).
String _fmtMilli(int m) {
  final v = m / 1000;
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// Kiritilgan «1,5» → milli (1500). Bo'sh/xato → null.
int? _parseMilli(String s) {
  final t = s.trim().replaceAll(',', '.').replaceAll(' ', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 1000).round();
}

final _qtyFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,3}'));

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.danger : AppColors.success,
  ));
}

class SupplyScreen extends StatelessWidget {
  const SupplyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          title: const Text('Yuk va qoldiq'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Kelgan yuk'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Qoldiq sanash'),
          ]),
        ),
        body: const TabBarView(children: [_IncomingTab(), _CountTab()]),
      ),
    );
  }
}

// ============================ KELGAN YUK ============================

class _IncomingTab extends StatefulWidget {
  const _IncomingTab();

  @override
  State<_IncomingTab> createState() => _IncomingTabState();
}

class _IncomingTabState extends State<_IncomingTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

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
      final list = await ApiService().getMoneIncoming();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errMsg(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AcceptSheet(order: order),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Yuklab bo‘lmadi',
        subtitle: _error,
        color: AppColors.danger,
        action: FilledButton(onPressed: _load, child: const Text('Qayta urinish')),
      );
    }
    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Kelgan yuk yo‘q',
            subtitle: 'Markazga berilgan buyurtma kelganda shu yerda chiqadi',
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final o = _orders[i];
          final items = (o['items'] as List? ?? const []);
          final created = DateTime.tryParse('${o['created']}')?.toLocal();
          final when = created == null
              ? ''
              : '${created.day.toString().padLeft(2, '0')}.${created.month.toString().padLeft(2, '0')} '
                  '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
          final preview = items.take(3).map((e) => '${(e as Map)['name']}'.trim()).join(', ');
          return KCard(
            onTap: () => _open(o),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const IconAvatar(icon: Icons.local_shipping_rounded, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Buyurtma ${o['order_id']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('$when · ${items.length} ta mahsulot',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(preview + (items.length > 3 ? '…' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
            ]),
          );
        },
      ),
    );
  }
}

class _AcceptSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  const _AcceptSheet({required this.order});

  @override
  State<_AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<_AcceptSheet> {
  late final List<Map<String, dynamic>> _items =
      [for (final e in (widget.order['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
  late final List<TextEditingController> _ctrls = [
    for (final it in _items) TextEditingController(text: _fmtMilli(_asInt(it['count_milli'])))
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  int _received(int i) => _parseMilli(_ctrls[i].text) ?? 0;

  Future<void> _submit() async {
    final short = <String>[];
    for (var i = 0; i < _items.length; i++) {
      final cnt = _asInt(_items[i]['count_milli']);
      final r = _received(i);
      if (r < cnt) {
        short.add('${_items[i]['name']}: ${_fmtMilli(cnt)} → ${_fmtMilli(r)} ${_items[i]['unit']}');
      }
    }
    if (short.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kam kelgan'),
          content: Text('${short.join('\n')}\n\nAdminga xabar boradi. Tasdiqlaysizmi?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Orqaga')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tasdiqlash')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() => _saving = true);
    try {
      await ApiService().acceptMoneIncoming(_asInt(widget.order['id']), [
        for (var i = 0; i < _items.length; i++)
          {'product_id': _asInt(_items[i]['product_id']), 'received_milli': _received(i)}
      ]);
      if (!mounted) return;
      _snack(context, 'Qabul qilindi — omborga kirim qilindi');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, _errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(children: [
                Expanded(
                  child: Text('Buyurtma ${widget.order['order_id']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Kelgan sonni tekshiring. Kam kelgan bo‘lsa sonni tuzating.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = _items[i];
                  final cnt = _asInt(it['count_milli']);
                  final less = _received(i) < cnt;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${it['name']}'.trim(),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Buyurtma: ${_fmtMilli(cnt)} ${it['unit']} · ${it['supply_sklad_name'] ?? ''}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ]),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _ctrls[i],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_qtyFormatter],
                          textAlign: TextAlign.center,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: '${it['unit']}',
                            filled: less,
                            fillColor: AppColors.dangerTint,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Qabul qildim', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================ QOLDIQ SANASH ============================

class _CountTab extends StatefulWidget {
  const _CountTab();

  @override
  State<_CountTab> createState() => _CountTabState();
}

class _CountTabState extends State<_CountTab> {
  Map<String, dynamic>? _draft;
  int? _depId;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';
  // product_id → kiritilgan matn (bo'sh = tizimdagidek)
  final Map<int, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({int? depId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService().getMoneStockCountDraft(departmentId: depId ?? _depId);
      if (!mounted) return;
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      setState(() {
        _draft = d;
        _depId = _asInt(d['department_id']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errMsg(e);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _items =>
      [for (final e in (_draft?['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];

  TextEditingController _ctrl(int pid) => _ctrls.putIfAbsent(pid, () => TextEditingController());

  /// Kiritilgan qatorlar: product_id → (tizim, sanalgan).
  Map<int, (int, int)> get _entered {
    final out = <int, (int, int)>{};
    for (final it in _items) {
      final pid = _asInt(it['product_id']);
      final c = _ctrls[pid];
      final v = c == null ? null : _parseMilli(c.text);
      if (v != null) out[pid] = (_asInt(it['system_milli']), v);
    }
    return out;
  }

  Future<void> _save() async {
    final entered = _entered;
    final byId = {for (final it in _items) _asInt(it['product_id']): it};
    final diffs = <String>[];
    entered.forEach((pid, v) {
      if (v.$1 != v.$2) {
        final it = byId[pid]!;
        diffs.add('${'${it['name']}'.trim()}: ${_fmtMilli(v.$1)} → ${_fmtMilli(v.$2)} ${it['unit']}');
      }
    });
    final prev = (_draft?['prev'] as Map?)?['staff']?.toString() ?? '';
    final opening = _draft?['opening'] == true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(diffs.isEmpty ? 'Farq yo‘q' : 'Farq: ${diffs.length} ta'),
        content: SingleChildScrollView(
          child: Text(diffs.isEmpty
              ? 'Hamma qoldiq tizimdagidek. Saqlaysizmi?'
              : opening
                  ? '${diffs.join('\n')}\n\nBirinchi sanash: bu sonlar boshlang‘ich qoldiq bo‘ladi, hech kimga kamomad yozilmaydi.'
                  : '${diffs.join('\n')}\n\nKamomad ${prev.isEmpty ? 'oldingi smena' : '«$prev»'} hisobiga yoziladi.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Orqaga')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Saqlash')),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _saving = true);
    try {
      final res = await ApiService().saveMoneStockCount(_depId, [
        for (final e in entered.entries) {'product_id': e.key, 'counted_milli': e.value.$2}
      ]);
      if (!mounted) return;
      final short = _asInt(res['shortage_count']);
      _snack(context, short > 0 ? 'Saqlandi — kamomad $short ta, adminga xabar ketdi' : 'Saqlandi');
      setState(() => _saving = false);
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(context, _errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Yuklab bo‘lmadi',
        subtitle: _error,
        color: AppColors.danger,
        action: FilledButton(onPressed: () => _load(), child: const Text('Qayta urinish')),
      );
    }
    final deps = (_draft?['departments'] as List? ?? const []);
    final prev = (_draft?['prev'] as Map?) ?? const {};
    final warn = _draft?['sync_warning']?.toString();
    final q = _query.toLowerCase();
    final items = _items.where((it) => q.isEmpty || '${it['name']}'.toLowerCase().contains(q)).toList();
    final entered = _entered;
    final diffN = entered.values.where((v) => v.$1 != v.$2).length;

    return Column(children: [
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (deps.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final d in deps)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${(d as Map)['name']}'),
                      selected: _asInt(d['id']) == _depId,
                      onSelected: (_) => _load(depId: _asInt(d['id'])),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          if (_draft?['opening'] == true)
            const Text(
              'Birinchi sanash — hamma mahsulotni sanab kiriting: bu boshlang‘ich qoldiq bo‘ladi, kamomad yozilmaydi.',
              style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
            )
          else
            Text(
              prev['staff'] == null || '${prev['staff']}'.isEmpty
                  ? 'Oldingi smena topilmadi — kamomad egasi noma‘lum'
                  : 'Oldingi smena: ${prev['staff']} — kamomad shu kassirga yoziladi',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          if (warn != null && warn.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⚠️ $warn', style: const TextStyle(color: AppColors.warning, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Mahsulot qidirish',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 4),
          const Text('Faqat farq qilganini yozing — bo‘sh qator tizimdagidek qoladi.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'Bu bo‘limda mahsulot yo‘q')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = items[i];
                  final pid = _asInt(it['product_id']);
                  final sys = _asInt(it['system_milli']);
                  final v = entered[pid];
                  final diff = v == null ? 0 : v.$2 - v.$1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${it['name']}'.trim(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Tizimda: ${_fmtMilli(sys)} ${it['unit']}'
                              '${diff == 0 ? '' : '  ·  farq ${diff > 0 ? '+' : ''}${_fmtMilli(diff)}'}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: diff < 0
                                      ? AppColors.danger
                                      : diff > 0
                                          ? AppColors.success
                                          : AppColors.textMuted)),
                        ]),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _ctrl(pid),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [_qtyFormatter],
                          textAlign: TextAlign.center,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: _fmtMilli(sys),
                            suffixText: '${it['unit']}',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ]),
                  );
                },
              ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(diffN == 0 ? 'Qoldiqni tasdiqlash' : 'Saqlash · farq $diffN ta',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    ]);
  }
}
