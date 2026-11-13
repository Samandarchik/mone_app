// admin/ui/filial_supply_ui.dart — MARKAZ → FILIAL ta'minoti (faqat admin):
// FilialSupplyUi — 3 yorliq: «Manba ombor» (kategoriya filialga qaysi ombordan
// jo'natiladi, PUT /api/categories/{id}/supply-sklad), «Qabullar» (filial
// buyurtmalari kassada qabul qilinganmi, GET /api/filial-incoming), «Smena
// qoldig'i» (kamomad tarixi, GET /api/pos-mone/stock-counts[/{id}]).
// Backend: filial_supply.go. Miqdorlar milli butun son.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

int _int(dynamic v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

String _milli(int m) {
  final v = m / 1000;
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String _money(int v) {
  final s = v.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return '${v < 0 ? '-' : ''}$s so‘m';
}

String _when(dynamic iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  String p(int x) => x.toString().padLeft(2, '0');
  return '${p(t.day)}.${p(t.month)} ${p(t.hour)}:${p(t.minute)}';
}

Future<dynamic> _call(Future<Response> Function() f) async {
  try {
    final r = await f();
    return r.data is Map ? r.data['data'] : null;
  } on DioException catch (e) {
    if (e.response != null) throw Exception(parseDioError(e));
    throw Exception('Tarmoq xatosi: ${e.message}');
  }
}

class FilialSupplyUi extends StatelessWidget {
  const FilialSupplyUi({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Filial ta‘minoti', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Manba ombor'),
            Tab(text: 'Qabullar'),
            Tab(text: 'Smena qoldig‘i'),
            Tab(text: 'Kategoriya daraxti'),
          ]),
        ),
        body: const TabBarView(children: [_SupplySkladTab(), _ReceiptsTab(), _CountsTab(), _CategoryTreeTab()]),
      ),
    );
  }
}

Widget _errorView(String msg, VoidCallback retry) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Qayta urinish')),
        ]),
      ),
    );

// ======================= MANBA OMBOR =======================

class _SupplySkladTab extends StatefulWidget {
  const _SupplySkladTab();

  @override
  State<_SupplySkladTab> createState() => _SupplySkladTabState();
}

class _SupplySkladTabState extends State<_SupplySkladTab> {
  final Dio _dio = sl<Dio>();
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;
  String? _error;
  final Set<int> _saving = {};

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
      await SkladRegistry.load();
      final data = await _call(() => _dio.get(AppUrls.category));
      final list = data is List ? data : const [];
      if (!mounted) return;
      setState(() {
        _cats = [for (final c in list) if (c is Map) Map<String, dynamic>.from(c)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _set(Map<String, dynamic> c, int skladId) async {
    final id = _int(c['id']);
    setState(() => _saving.add(id));
    try {
      await _call(() => _dio.put(AppUrls.categorySupplySklad(id), data: {'supply_sklad_id': skladId}));
      if (!mounted) return;
      setState(() => c['supply_sklad_id'] = skladId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorView(_error!, _load);
    final ids = SkladRegistry.ids;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Filial buyurtma bergan mahsulot qaysi ombordan jo‘natiladi. Kassir «qabul qildim» deganda '
              'shu ombordan chiqim, filial bo‘limiga kirim bo‘ladi.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          for (final c in _cats)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text('${c['name'] ?? ''}'),
                subtitle: (c['printer_agent'] ?? '').toString().isEmpty ? null : Text('Printer: ${c['printer_agent']}'),
                trailing: _saving.contains(_int(c['id']))
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : DropdownButton<int>(
                        value: ids.contains(_int(c['supply_sklad_id'])) ? _int(c['supply_sklad_id']) : 0,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(value: 0, child: Text('— belgilanmagan')),
                          for (final id in ids) DropdownMenuItem(value: id, child: Text(SkladRegistry.nameOf(id))),
                        ],
                        onChanged: (v) {
                          if (v != null && v != _int(c['supply_sklad_id'])) _set(c, v);
                        },
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ======================= KATEGORIYA DARAXTI =======================
// Ota kategoriya (БАР → КОФЕ). Kassa yon panelida ildiz nomi guruh sarlavhasi
// bo'ladi. Server sikl va yo'q otani rad etadi (400).

class _CategoryTreeTab extends StatefulWidget {
  const _CategoryTreeTab();

  @override
  State<_CategoryTreeTab> createState() => _CategoryTreeTabState();
}

class _CategoryTreeTabState extends State<_CategoryTreeTab> {
  final Dio _dio = sl<Dio>();
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;
  String? _error;
  final Set<int> _saving = {};

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
      final data = await _call(() => _dio.get(AppUrls.category));
      final list = data is List ? data : const [];
      if (!mounted) return;
      setState(() {
        _cats = [for (final c in list) if (c is Map) Map<String, dynamic>.from(c)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Daraxt tartibi: ildizlar server tartibida, har birining ostida bolalari.
  List<(Map<String, dynamic>, int)> _tree() {
    final ids = {for (final c in _cats) _int(c['id'])};
    final kids = <int, List<Map<String, dynamic>>>{};
    for (final c in _cats) {
      final p = _int(c['parent_id']);
      kids.putIfAbsent(ids.contains(p) ? p : 0, () => []).add(c);
    }
    final out = <(Map<String, dynamic>, int)>[];
    final seen = <int>{};
    void walk(int parent, int depth) {
      for (final c in kids[parent] ?? const <Map<String, dynamic>>[]) {
        final id = _int(c['id']);
        if (!seen.add(id)) continue;
        out.add((c, depth));
        walk(id, depth + 1);
      }
    }

    walk(0, 0);
    for (final c in _cats) {
      if (!seen.contains(_int(c['id']))) out.add((c, 0)); // sikl himoyasi
    }
    return out;
  }

  Set<int> _descendants(int id) {
    final out = <int>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in _cats) {
        if (out.contains(_int(c['parent_id'])) && out.add(_int(c['id']))) grew = true;
      }
    }
    return out;
  }

  Future<void> _pickParent(Map<String, dynamic> c) async {
    final id = _int(c['id']);
    final banned = _descendants(id);
    final options = [for (final x in _cats) if (!banned.contains(_int(x['id']))) x];
    var q = '';
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final shown = q.isEmpty
              ? options
              : options.where((x) => '${x['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
          return AlertDialog(
            title: Text('«${c['name']}» — ota kategoriya'),
            content: SizedBox(
              width: 420,
              height: 460,
              child: Column(children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Qidirish'),
                  onChanged: (v) => setD(() => q = v.trim()),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.vertical_align_top),
                  title: const Text('— Ildiz (otasiz)'),
                  onTap: () => Navigator.pop(ctx, 0),
                ),
                Expanded(
                  child: ListView(children: [
                    for (final x in shown)
                      ListTile(
                        dense: true,
                        title: Text('${x['name']}'),
                        selected: _int(x['id']) == _int(c['parent_id']),
                        onTap: () => Navigator.pop(ctx, _int(x['id'])),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor'))],
          );
        },
      ),
    );
    if (picked == null || picked == _int(c['parent_id'])) return;
    setState(() => _saving.add(id));
    try {
      await _call(() => _dio.put('${AppUrls.category}/$id', data: {'parent_id': picked}));
      if (!mounted) return;
      setState(() => c['parent_id'] = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorView(_error!, _load);
    final rows = _tree();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Kategoriyani bosib ota kategoriyasini tanlang. Kassada eng yuqori ota (БАР, КУХНЯ, МАГАЗИН…) '
              'yon panelda guruh sarlavhasi bo‘ladi.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
          for (final (c, depth) in rows)
            Card(
              margin: EdgeInsets.only(bottom: 4, left: depth * 20.0),
              child: ListTile(
                dense: true,
                leading: Icon(depth == 0 ? Icons.folder : Icons.subdirectory_arrow_right, size: 20),
                title: Text('${c['name'] ?? ''}',
                    style: TextStyle(fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w500)),
                trailing: _saving.contains(_int(c['id']))
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _pickParent(c),
              ),
            ),
        ],
      ),
    );
  }
}

// ======================= FILIAL TANLASH (umumiy) =======================

mixin _FilialFilter<T extends StatefulWidget> on State<T> {
  int _filialId = 0; // 0 = hammasi

  Future<void> reload();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fp = context.read<FilialProviderAdmin>();
      if (fp.filials.isEmpty) await fp.getFilials();
      if (mounted) setState(() {});
      reload();
    });
  }

  Widget filialChips() {
    final filials = context.watch<FilialProviderAdmin>().filials;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: const Text('Hammasi'),
            selected: _filialId == 0,
            onSelected: (_) {
              setState(() => _filialId = 0);
              reload();
            },
          ),
        ),
        for (final f in filials)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text((f.location ?? '').isNotEmpty ? f.location! : f.name, overflow: TextOverflow.ellipsis),
              selected: _filialId == f.id,
              onSelected: (_) {
                setState(() => _filialId = f.id);
                reload();
              },
            ),
          ),
      ]),
    );
  }
}

// ======================= QABULLAR =======================

class _ReceiptsTab extends StatefulWidget {
  const _ReceiptsTab();

  @override
  State<_ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends State<_ReceiptsTab> with _FilialFilter<_ReceiptsTab> {
  final Dio _dio = sl<Dio>();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _call(() => _dio.get(AppUrls.filialIncoming,
          queryParameters: {'days': 7, if (_filialId != 0) 'filial_id': _filialId}));
      if (!mounted) return;
      setState(() {
        _rows = [for (final r in (data is List ? data : const [])) if (r is Map) Map<String, dynamic>.from(r)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _rows.where((r) => r['received_at'] == null).length;
    return Column(children: [
      filialChips(),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView(_error!, reload)
                : RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(padding: const EdgeInsets.all(12), children: [
                      Text('Oxirgi 7 kun: ${_rows.length} ta buyurtma, qabul kutilmoqda: $pending',
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      for (final r in _rows)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: Icon(
                              r['received_at'] == null
                                  ? Icons.local_shipping_outlined
                                  : _int(r['short_count']) > 0
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle,
                              color: r['received_at'] == null
                                  ? Colors.orange
                                  : _int(r['short_count']) > 0
                                      ? Colors.red
                                      : Colors.green,
                            ),
                            title: Text('${r['order_id']} · ${r['filial_name'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(r['received_at'] == null
                                ? '${_when(r['created'])} · ${_int(r['items_count'])} ta · qabul qilinmagan'
                                : 'Qabul: ${_when(r['received_at'])} · ${r['received_by'] ?? ''}'
                                    '${_int(r['short_count']) > 0 ? ' · kam: ${_int(r['short_count'])} ta' : ''}'),
                          ),
                        ),
                    ]),
                  ),
      ),
    ]);
  }
}

// ======================= SMENA QOLDIG'I =======================

class _CountsTab extends StatefulWidget {
  const _CountsTab();

  @override
  State<_CountsTab> createState() => _CountsTabState();
}

class _CountsTabState extends State<_CountsTab> with _FilialFilter<_CountsTab> {
  final Dio _dio = sl<Dio>();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _call(() => _dio.get(AppUrls.stockCounts,
          queryParameters: {'days': 60, if (_filialId != 0) 'filial_id': _filialId}));
      if (!mounted) return;
      setState(() {
        _rows = [for (final r in (data is List ? data : const [])) if (r is Map) Map<String, dynamic>.from(r)];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _open(int id) async {
    try {
      final data = await _call(() => _dio.get(AppUrls.stockCount(id)));
      if (!mounted || data is! Map) return;
      final c = Map<String, dynamic>.from(data);
      final items = [
        for (final it in (c['items'] as List? ?? const []))
          if (it is Map && _int(it['diff_milli']) != 0) Map<String, dynamic>.from(it)
      ];
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
            child: ListView(padding: const EdgeInsets.all(16), shrinkWrap: true, children: [
              Text('${c['sklad_name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${_when(c['counted_at'])} · sanadi: ${c['staff_name']}'),
              Text('Kamomad egasi: ${(c['prev_staff'] ?? '').toString().isEmpty ? 'noma‘lum' : c['prev_staff']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Kamomad: ${_int(c['shortage_count'])} ta · sotuv narxida ${_money(_int(c['shortage_sale_sum']))}'
                  ' · tannarx ${_money(_int(c['shortage_sum']))}'),
              const Divider(),
              if (items.isEmpty) const Text('Farq yo‘q — hamma qoldiq tizimdagidek'),
              for (final it in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${it['name']}'),
                  subtitle: Text('Tizim ${_milli(_int(it['system_milli']))} → sanaldi ${_milli(_int(it['counted_milli']))} ${it['unit']}'),
                  trailing: Text(
                    '${_int(it['diff_milli']) > 0 ? '+' : ''}${_milli(_int(it['diff_milli']))}\n${_money(_int(it['sale_sum']))}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: _int(it['diff_milli']) < 0 ? Colors.red : Colors.green),
                  ),
                ),
            ]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      filialChips(),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView(_error!, reload)
                : _rows.isEmpty
                    ? const Center(child: Text('Hali sanash bo‘lmagan'))
                    : RefreshIndicator(
                        onRefresh: reload,
                        child: ListView(padding: const EdgeInsets.all(12), children: [
                          for (final r in _rows)
                            Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                onTap: () => _open(_int(r['id'])),
                                leading: Icon(
                                  _int(r['shortage_count']) > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
                                  color: _int(r['shortage_count']) > 0 ? Colors.red : Colors.green,
                                ),
                                title: Text('${r['sklad_name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${_when(r['counted_at'])} · ${r['staff_name']}'
                                    '${_int(r['shortage_count']) > 0 ? '\nKamomad ${_int(r['shortage_count'])} ta (${_money(_int(r['shortage_sale_sum']))}) → ${r['prev_staff']}' : ''}'),
                                isThreeLine: _int(r['shortage_count']) > 0,
                              ),
                            ),
                        ]),
                      ),
      ),
    ]);
  }
}
