// admin/ui/departments_ui.dart — FILIAL BO'LIMLARI (faqat admin).
// DepartmentsUi — filial tanlanadi, bo'limlar kartalari (ombor, kategoriyalar soni,
// asosiy belgisi); DepartmentEditPage — nom, ombor (mavjud yoki yangi), asosiy
// bo'lim, kategoriyalar (chip) va alohida mahsulotlar.
// Kassada sotilgan mahsulot qaysi bo'limda bo'lsa — o'sha bo'lim omboridan
// yechiladi va o'sha bo'lim printeriga chiqadi (backend departments.go).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/services/department_service.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';

class DepartmentsUi extends StatefulWidget {
  const DepartmentsUi({super.key});

  @override
  State<DepartmentsUi> createState() => _DepartmentsUiState();
}

class _DepartmentsUiState extends State<DepartmentsUi> {
  final _service = DepartmentService();
  int? _filialId;
  List<Department> _list = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fp = context.read<FilialProviderAdmin>();
      if (fp.filials.isEmpty) await fp.getFilials();
      await SkladRegistry.load();
      if (!mounted) return;
      if (fp.filials.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Filiallar topilmadi';
        });
        return;
      }
      _filialId = fp.filials.first.id;
      _load();
    });
  }

  Future<void> _load() async {
    final fid = _filialId;
    if (fid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetch(fid);
      if (!mounted) return;
      setState(() {
        _list = list;
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

  Future<void> _open(Department? d) async {
    final fid = _filialId;
    if (fid == null) return;
    final updated = await Navigator.of(context).push<List<Department>>(
      MaterialPageRoute(
          builder: (_) => DepartmentEditPage(filialId: fid, department: d, all: _list)),
    );
    if (updated != null && mounted) setState(() => _list = updated);
  }

  @override
  Widget build(BuildContext context) {
    final filials = context.watch<FilialProviderAdmin>().filials;
    String filialName = '';
    for (final f in filials) {
      if (f.id == _filialId) filialName = f.name;
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bo‘limlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (filialName.isNotEmpty)
              Text(filialName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Filial',
            icon: const Icon(Icons.store_mall_directory_outlined),
            onSelected: (id) {
              if (id == _filialId) return;
              _filialId = id;
              _load();
            },
            itemBuilder: (_) => [
              for (final f in filials)
                CheckedPopupMenuItem<int>(value: f.id, checked: f.id == _filialId, child: Text(f.name)),
            ],
          ),
        ],
      ),
      floatingActionButton: _filialId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(null),
              icon: const Icon(Icons.add),
              label: const Text('Bo‘lim'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Qayta urinish')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Kassada sotilgan mahsulot qaysi bo‘limda bo‘lsa — o‘sha bo‘lim omboridan yechiladi va '
                          'o‘sha bo‘lim printeriga chiqadi. Bo‘limga biriktirilmaganlar «asosiy» bo‘limdan.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                      if (_list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Bo‘lim yo‘q. Masalan: Bar, Oshxona, Vitrina')),
                        ),
                      for (final d in _list)
                        Card(
                          child: ListTile(
                            leading: Icon(d.isDefault ? Icons.star : Icons.kitchen_outlined,
                                color: d.isDefault ? Colors.amber.shade700 : null),
                            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([
                              d.skladId > 0 ? 'Ombor: ${SkladRegistry.display(d.skladId, d.skladName)}' : 'Ombor tanlanmagan (kassa ombori)',
                              '${d.categoryIds.length} kategoriya, ${d.productIds.length} alohida mahsulot',
                              if (d.isDefault) 'Asosiy bo‘lim',
                            ].join('\n')),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(d),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class DepartmentEditPage extends StatefulWidget {
  final int filialId;
  final Department? department;
  final List<Department> all;
  const DepartmentEditPage({super.key, required this.filialId, this.department, this.all = const []});

  @override
  State<DepartmentEditPage> createState() => _DepartmentEditPageState();
}

class _DepartmentEditPageState extends State<DepartmentEditPage> {
  final _service = DepartmentService();
  late final TextEditingController _name = TextEditingController(text: widget.department?.name ?? '');
  late int _skladId = widget.department?.skladId ?? 0;
  bool _newSklad = false;
  late bool _isDefault = widget.department?.isDefault ?? widget.all.isEmpty;
  late final Set<int> _cats = {...?widget.department?.categoryIds};
  late final List<int> _prods = [...?widget.department?.productIds];
  List<DeptPickItem> _allCats = const [];
  List<DeptPickItem> _allProds = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Boshqa bo'limlardagi kategoriya/mahsulot → bo'lim nomi (tanlab bo'lmaydi).
  late final Map<int, String> _catOwner = {
    for (final d in widget.all)
      if (d.id != widget.department?.id)
        for (final c in d.categoryIds) c: d.name,
  };
  late final Map<int, String> _prodOwner = {
    for (final d in widget.all)
      if (d.id != widget.department?.id)
        for (final p in d.productIds) p: d.name,
  };

  @override
  void initState() {
    super.initState();
    _loadSellables();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadSellables() async {
    try {
      final (cats, prods) = await _service.fetchSellables(widget.filialId);
      if (!mounted) return;
      setState(() {
        _allCats = cats;
        _allProds = prods;
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

  String _prodName(int id) {
    for (final p in _allProds) {
      if (p.id == id) return p.name;
    }
    return 'Mahsulot #$id';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bo‘lim nomini kiriting');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      if (_newSklad) 'new_sklad': true else 'sklad_id': _skladId,
      'is_default': _isDefault,
      'category_ids': _cats.toList(),
      'product_ids': _prods,
    };
    try {
      final list = widget.department == null
          ? await _service.create(widget.filialId, body)
          : await _service.update(widget.department!.id, body);
      if (_newSklad) await SkladRegistry.load();
      if (!mounted) return;
      Navigator.of(context).pop(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _delete() async {
    final d = widget.department;
    if (d == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('«${d.name}» o‘chirilsinmi?'),
        content: const Text('Ombor va undagi qoldiq o‘chirilmaydi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Yo‘q')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('O‘chirish')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final list = await _service.delete(d.id);
      if (!mounted) return;
      Navigator.of(context).pop(list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _addProduct() async {
    final choices = [
      for (final p in _allProds)
        if (!_prods.contains(p.id) && !_prodOwner.containsKey(p.id)) p,
    ];
    final picked = await showModalBottomSheet<DeptPickItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PickSheet(items: choices),
    );
    if (picked != null) setState(() => _prods.add(picked.id));
  }

  @override
  Widget build(BuildContext context) {
    final skladIds = SkladRegistry.ids;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.department == null ? 'Yangi bo‘lim' : widget.department!.name),
        actions: [
          if (widget.department != null)
            IconButton(onPressed: _saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saqlanmoqda…' : 'Saqlash'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
                  ),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Bo‘lim nomi', hintText: 'Bar, Oshxona, Vitrina…', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Ombor', style: TextStyle(fontWeight: FontWeight.w600)),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bu bo‘lim uchun yangi ombor ochilsin'),
                  value: _newSklad,
                  onChanged: (v) => setState(() => _newSklad = v),
                ),
                if (!_newSklad)
                  DropdownButtonFormField<int>(
                    initialValue: skladIds.contains(_skladId) ? _skladId : 0,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Kassa ombori (tanlanmagan)')),
                      for (final id in skladIds)
                        DropdownMenuItem(value: id, child: Text(SkladRegistry.nameOf(id))),
                    ],
                    onChanged: (v) => setState(() => _skladId = v ?? 0),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Asosiy bo‘lim'),
                  subtitle: const Text('Hech qaysi bo‘limga biriktirilmagan mahsulotlar shu yerdan yechiladi'),
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                ),
                const Divider(height: 32),
                const Text('Kategoriyalar', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Kategoriyadagi hamma mahsulot shu bo‘limga tegishli bo‘ladi.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                if (_allCats.isEmpty)
                  const Text('Kassa menyusida mahsulot yo‘q — avval «Kassa menyusi»ni to‘ldiring'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _allCats)
                      FilterChip(
                        label: Text(_catOwner.containsKey(c.id) ? '${c.name} · ${_catOwner[c.id]}' : c.name),
                        selected: _cats.contains(c.id),
                        onSelected: _catOwner.containsKey(c.id)
                            ? null
                            : (v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Row(children: [
                  const Expanded(
                      child: Text('Alohida mahsulotlar', style: TextStyle(fontWeight: FontWeight.w600))),
                  TextButton.icon(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Qo‘shish')),
                ]),
                Text('Kategoriyasi boshqa bo‘limda bo‘lsa ham shu bo‘limga o‘tadi (masalan: apelsinli fresh → Bar).',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                for (final id in _prods)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_prodName(id)),
                    trailing: IconButton(
                        icon: const Icon(Icons.close), onPressed: () => setState(() => _prods.remove(id))),
                  ),
              ],
            ),
    );
  }
}

class _PickSheet extends StatefulWidget {
  final List<DeptPickItem> items;
  const _PickSheet({required this.items});

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [
      for (final p in widget.items)
        if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Mahsulot qidirish'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(list[i].name),
                onTap: () => Navigator.of(context).pop(list[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
