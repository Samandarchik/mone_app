// admin/ui/pos_mone_stations_ui.dart — POS Mone kassalari (faqat admin):
// PosMoneStationsUi — ro'yxat (aloqa holati, filial, sklad); PosMoneStationEditPage —
// kassani filial + asosiy skladga bog'lash va BO'LIM yo'naltirishi: kategoriya
// yoki mahsulot → sklad (fresh → bar ombori, salat → oshxona ombori).
// Smena yopilganda Mone tex karta bo'yicha shu skladlardan yechadi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/pos_mone_station_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/services/pos_mone_service.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';

class PosMoneStationsUi extends StatefulWidget {
  const PosMoneStationsUi({super.key});

  @override
  State<PosMoneStationsUi> createState() => _PosMoneStationsUiState();
}

class _PosMoneStationsUiState extends State<PosMoneStationsUi> {
  final PosMoneService _service = PosMoneService();
  List<PosMoneStation> _stations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fp = context.read<FilialProviderAdmin>();
      if (fp.filials.isEmpty) fp.getFilials();
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.fetchStations();
      if (!mounted) return;
      setState(() {
        _stations = list;
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

  Future<void> _open(PosMoneStation st) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosMoneStationEditPage(station: st)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRk7Bg,
      appBar: AppBar(
        backgroundColor: kRk7Bg,
        elevation: 0,
        title: const Text('POS kassalar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kRk7Accent,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _stations.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null && _stations.isEmpty) {
      return rk7ErrorState(_error!, onRetry: _load);
    }
    if (_stations.isEmpty) {
      return rk7EmptyState(Icons.point_of_sale,
          'Kassa yo\'q — filial kassa serveri birinchi ishga tushganda shu yerda paydo bo\'ladi');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _stations.length,
      itemBuilder: (context, i) => _card(_stations[i]),
    );
  }

  Widget _card(PosMoneStation st) {
    final bound = st.filialId > 0;
    final hasSklad = st.effectiveSkladId > 0 || st.routes.isNotEmpty;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color:
                bound && hasSklad ? Colors.grey.shade300 : Colors.red.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(st),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle,
                      size: 10,
                      color: st.online ? Colors.green : Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(st.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                bound ? 'Filial: ${st.filialName}' : 'Filialga bog\'lanmagan',
                style: TextStyle(
                    fontSize: 12.5,
                    color: bound ? Colors.black87 : Colors.red.shade700),
              ),
              Text(
                st.effectiveSkladId > 0
                    ? 'Asosiy sklad: ${SkladRegistry.nameOf(st.effectiveSkladId)}'
                    : 'Asosiy sklad tanlanmagan',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
              if (st.routes.isNotEmpty)
                Text('Bo\'lim yo\'naltirishlari: ${st.routes.length} ta',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(
                [
                  st.stationId,
                  if (st.appVersion.isNotEmpty) 'v${st.appVersion}',
                  if (st.lastSeenAt != null)
                    'oxirgi aloqa ${_fmt(st.lastSeenAt!)}',
                ].join(' · '),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

// ─────────────────────────── Tahrirlash ───────────────────────────

class PosMoneStationEditPage extends StatefulWidget {
  final PosMoneStation station;
  const PosMoneStationEditPage({super.key, required this.station});

  @override
  State<PosMoneStationEditPage> createState() => _PosMoneStationEditPageState();
}

class _PosMoneStationEditPageState extends State<PosMoneStationEditPage> {
  final PosMoneService _service = PosMoneService();
  late final TextEditingController _name;
  late int _filialId;
  late int _skladId;
  // kategoriya id → sklad id (0 = asosiy sklad).
  final Map<int, int> _catRoutes = {};
  // mahsulot id → sklad id.
  final Map<int, int> _prodRoutes = {};
  // «Tayyor holda yechilsin» belgilangan kategoriya/mahsulotlar.
  final Set<int> _catSelf = {};
  final Set<int> _prodSelf = {};

  List<PosMoneCatalogItem> _cats = const [];
  List<PosMoneCatalogItem> _prods = const [];
  bool _catalogLoading = false;
  String? _catalogError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final st = widget.station;
    _name = TextEditingController(text: st.name);
    _filialId = st.filialId;
    _skladId = st.skladId;
    for (final r in st.routes) {
      if (r.isProduct) {
        _prodRoutes[r.productId] = r.skladId;
        if (r.self) _prodSelf.add(r.productId);
      } else if (r.categoryId > 0) {
        _catRoutes[r.categoryId] = r.skladId;
        if (r.self) _catSelf.add(r.categoryId);
      }
    }
    if (_filialId > 0) _loadCatalog();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final (cats, prods) = await _service.fetchCatalog(_filialId);
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _prods = prods;
        _catalogLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = e.toString().replaceFirst('Exception: ', '');
        _catalogLoading = false;
      });
    }
  }

  String _prodName(int id) {
    for (final p in _prods) {
      if (p.id == id) return p.name;
    }
    return 'Mahsulot #$id';
  }

  Future<void> _save() async {
    if (_filialId <= 0) {
      rk7Snack(context, 'Filial tanlang', error: true);
      return;
    }
    final routes = <PosMoneSkladRoute>[
      for (final e in _catRoutes.entries)
        if (e.value > 0)
          PosMoneSkladRoute(
              categoryId: e.key,
              skladId: e.value,
              self: _catSelf.contains(e.key)),
      for (final e in _prodRoutes.entries)
        if (e.value > 0)
          PosMoneSkladRoute(
              productId: e.key,
              skladId: e.value,
              self: _prodSelf.contains(e.key)),
    ];
    if (_skladId <= 0 && routes.isEmpty) {
      rk7Snack(
          context, 'Asosiy sklad yoki kamida bitta bo\'lim skladini tanlang',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.saveStation(
        stationId: widget.station.stationId,
        name: _name.text.trim(),
        filialId: _filialId,
        skladId: _skladId,
        routes: routes,
      );
      if (!mounted) return;
      rk7Snack(context, 'Kassa saqlandi');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  Future<void> _addProductRoute() async {
    final picked = await showModalBottomSheet<PosMoneCatalogItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPicker(
        products: [
          for (final p in _prods)
            if (!_prodRoutes.containsKey(p.id)) p,
        ],
      ),
    );
    if (picked != null) {
      setState(() => _prodRoutes[picked.id] = _skladId > 0
          ? _skladId
          : (SkladRegistry.ids.isNotEmpty ? SkladRegistry.ids.first : 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filials = context.watch<FilialProviderAdmin>().filials;
    final filialIds = filials.map((f) => f.id).toSet();
    return Scaffold(
      backgroundColor: kRk7Bg,
      appBar: AppBar(
        backgroundColor: kRk7Bg,
        elevation: 0,
        title: Text(widget.station.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kRk7Accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Saqlash'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          TextField(
            controller: _name,
            decoration: _dec('Kassa nomi'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: filialIds.contains(_filialId) ? _filialId : null,
            isExpanded: true,
            decoration: _dec('Filial'),
            items: [
              for (final f in filials)
                DropdownMenuItem(value: f.id, child: Text(f.name)),
            ],
            onChanged: (v) {
              if (v == null || v == _filialId) return;
              setState(() {
                _filialId = v;
                _catRoutes.clear();
                _prodRoutes.clear();
              });
              _loadCatalog();
            },
          ),
          const SizedBox(height: 10),
          _skladDropdown(
            label: 'Asosiy sklad (yo\'naltirilmagan hamma narsa)',
            value: _skladId,
            allowNone: true,
            noneText: 'tanlanmagan — yechilmaydi',
            onChanged: (v) => setState(() => _skladId = v),
          ),
          const SizedBox(height: 18),
          const Text('Bo\'limlar: kategoriya → ombor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Masalan «Ichimliklar» → Bar ombori, «Salatlar» → Oshxona ombori. '
            'Sotilgan taomning tex karta masalliqlari shu ombordan yechiladi.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          if (_filialId <= 0)
            Text('Avval filial tanlang',
                style: TextStyle(color: Colors.grey.shade600))
          else if (_catalogLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          else if (_catalogError != null)
            rk7ErrorState(_catalogError!, onRetry: _loadCatalog)
          else if (_cats.isEmpty)
            Text('Bu filial POS katalogi bo\'sh',
                style: TextStyle(color: Colors.grey.shade600))
          else
            for (final c in _cats)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skladDropdown(
                      label: c.name,
                      value: _catRoutes[c.id] ?? 0,
                      allowNone: true,
                      noneText: 'asosiy sklad',
                      onChanged: (v) => setState(() {
                        if (v > 0) {
                          _catRoutes[c.id] = v;
                        } else {
                          _catRoutes.remove(c.id);
                          _catSelf.remove(c.id);
                        }
                      }),
                    ),
                    if ((_catRoutes[c.id] ?? 0) > 0)
                      _selfToggle(_catSelf, c.id),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('Alohida mahsulotlar',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: _prods.isEmpty ? null : _addProductRoute,
                icon: const Icon(Icons.add),
                label: const Text('Qo\'shish'),
              ),
            ],
          ),
          Text(
            'Kategoriyadan farqli omborga ketadigan mahsulot (masalan apelsin fresh → Bar).',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          for (final e in _prodRoutes.entries.toList())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(children: [
                Row(
                  children: [
                    Expanded(
                      child: _skladDropdown(
                        label: _prodName(e.key),
                        value: e.value,
                        allowNone: false,
                        onChanged: (v) =>
                            setState(() => _prodRoutes[e.key] = v),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _prodRoutes.remove(e.key);
                        _prodSelf.remove(e.key);
                      }),
                      icon: Icon(Icons.close, color: Colors.red.shade400),
                    ),
                  ],
                ),
                _selfToggle(_prodSelf, e.key),
              ]),
            ),
        ],
      ),
    );
  }

  // «Tayyor holda yechilsin» — mahsulotning o'zi skladdan (masalliqlari emas).
  Widget _selfToggle(Set<int> set, int id) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: set.contains(id),
        title: const Text('Tayyor holda yechilsin (masalliqlari emas)',
            style: TextStyle(fontSize: 12.5)),
        subtitle: const Text(
            'Nonvoyxona: tayyor tort skladda turadi. Restoran (fresh, salat) uchun belgilamang.',
            style: TextStyle(fontSize: 11)),
        onChanged: (v) =>
            setState(() => v == true ? set.add(id) : set.remove(id)),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _skladDropdown({
    required String label,
    required int value,
    required bool allowNone,
    String noneText = '',
    required ValueChanged<int> onChanged,
  }) {
    final ids = SkladRegistry.ids;
    final valid = value == 0
        ? (allowNone ? 0 : null)
        : (ids.contains(value) ? value : null);
    return DropdownButtonFormField<int>(
      initialValue: valid,
      isExpanded: true,
      decoration: _dec(label),
      items: [
        if (allowNone)
          DropdownMenuItem(
              value: 0,
              child: Text(noneText,
                  style: TextStyle(color: Colors.grey.shade600))),
        for (final id in ids)
          DropdownMenuItem(value: id, child: Text(SkladRegistry.nameOf(id))),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final List<PosMoneCatalogItem> products;
  const _ProductPicker({required this.products});

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [
      for (final p in widget.products)
        if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Mahsulot qidirish'),
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
          ],
        ),
      ),
    );
  }
}
