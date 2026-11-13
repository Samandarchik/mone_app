// admin/ui/kassa_staff_ui.dart — KASSA XODIMLARI (admin; o'zgartirish — super admin).
// KassaStaffUi — filial tanlanadi, xodimlar ro'yxati (rol, holat, HR holati);
// «Qo'shish» — HR ro'yxatidan qidirib tanlash → rol → PIN (bir marta ko'rsatiladi).
// Xodim kartasi: rol, filial, faol/o'chiq, PINni yangilash.
// HR'da ishdan ketgan xodim avtomatik bloklanadi (backend kassa_staff.go);
// kassa serveri ro'yxatni o'zi tortadi (pos_backend monesync/staff.go).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/services/kassa_staff_service.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

class KassaStaffUi extends StatefulWidget {
  const KassaStaffUi({super.key});

  @override
  State<KassaStaffUi> createState() => _KassaStaffUiState();
}

class _KassaStaffUiState extends State<KassaStaffUi> {
  final _service = KassaStaffService();
  int? _filialId;
  KassaStaffList _data = const KassaStaffList([], [], false);
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fp = context.read<FilialProviderAdmin>();
      if (fp.filials.isEmpty) await fp.getFilials();
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
      final d = await _service.fetch(fid);
      if (!mounted) return;
      setState(() {
        _data = d;
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

  String _roleName(String id) {
    for (final r in _data.roles) {
      if (r.$1 == id) return r.$2;
    }
    return id;
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _showPin(String name, String pin) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Kassa PIN kodi:'),
          const SizedBox(height: 8),
          SelectableText(pin,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 8)),
          const SizedBox(height: 8),
          Text('Yozib oling yoki xodimga ayting — qayta ko‘rsatilmaydi. '
              'Kassa serveri bir necha daqiqada yangilanadi.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: pin)),
            child: const Text('Nusxalash'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Yozib oldim')),
        ],
      ),
    );
  }

  Future<String?> _pickRole(String? current) => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Rol', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final r in _data.roles)
              ListTile(
                leading: Icon(r.$1 == current ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(r.$2),
                onTap: () => Navigator.pop(ctx, r.$1),
              ),
          ]),
        ),
      );

  Future<void> _add() async {
    final fid = _filialId;
    if (fid == null) return;
    final person = await Navigator.of(context)
        .push<HrPerson>(MaterialPageRoute(builder: (_) => _HrPickerPage(service: _service)));
    if (person == null || !mounted) return;
    final role = await _pickRole(null);
    if (role == null || !mounted) return;
    try {
      final (s, pin) = await _service.create(person.personId, role, fid);
      if (!mounted) return;
      await _showPin(s.name, pin);
      _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _edit(KassaStaffMember s) async {
    final filials = context.read<FilialProviderAdmin>().filials;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s.phone)),
          ListTile(leading: const Icon(Icons.badge_outlined), title: Text('Rol: ${_roleName(s.role)}'), onTap: () => Navigator.pop(ctx, 'role')),
          ListTile(leading: const Icon(Icons.store_mall_directory_outlined), title: Text('Filial: ${s.filialName}'), onTap: () => Navigator.pop(ctx, 'filial')),
          ListTile(leading: const Icon(Icons.pin_outlined), title: const Text('PINni yangilash'), onTap: () => Navigator.pop(ctx, 'pin')),
          ListTile(
            leading: Icon(s.active ? Icons.block : Icons.check_circle_outline, color: s.active ? Colors.red : Colors.green),
            title: Text(s.active ? 'Kassaga kirishni o‘chirish' : 'Qayta yoqish'),
            onTap: () => Navigator.pop(ctx, 'active'),
          ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      String pin = '';
      KassaStaffMember upd = s;
      switch (action) {
        case 'role':
          final r = await _pickRole(s.role);
          if (r == null || r == s.role) return;
          (upd, pin) = await _service.update(s.id, {'role': r});
        case 'filial':
          if (!mounted) return;
          final f = await showModalBottomSheet<int>(
            context: context,
            builder: (ctx) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
                for (final f in filials)
                  ListTile(
                    leading: Icon(f.id == s.filialId ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: Text(f.name),
                    onTap: () => Navigator.pop(ctx, f.id),
                  ),
              ]),
            ),
          );
          if (f == null || f == s.filialId) return;
          (upd, pin) = await _service.update(s.id, {'filial_id': f});
        case 'pin':
          (upd, pin) = await _service.resetPin(s.id);
        case 'active':
          (upd, pin) = await _service.update(s.id, {'active': !s.active});
      }
      if (!mounted) return;
      if (pin.isNotEmpty) await _showPin(upd.name, pin);
      _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kassa xodimlari', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (filialName.isNotEmpty)
            Text(filialName, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
        ]),
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
      floatingActionButton: _filialId == null || !_data.hrEnabled
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('HR dan qo‘shish'),
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
                      if (!_data.hrEnabled)
                        Card(
                          color: Colors.orange.shade50,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('HR ulanmagan: serverda HR_SYNC_KEY sozlanmagan. '
                                'Sozlangach HR xodimlari shu yerda ko‘rinadi.'),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Xodim HR ro‘yxatidan tanlanadi, rol va filial beriladi — PIN o‘sha filial kassasida '
                          'avtomatik ishlaydi. HR’da ishdan ketsa kassaga kira olmaydi.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                      if (_data.staff.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Bu filialda kassa xodimi yo‘q')),
                        ),
                      for (final s in _data.staff)
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundImage: s.photoUrl.isEmpty
                                  ? null
                                  : appNetworkImageProvider(context, s.photoUrl, displayWidth: 40),
                              child: s.photoUrl.isEmpty ? Text(s.name.isEmpty ? '?' : s.name[0]) : null,
                            ),
                            title: Text(s.name,
                                style: TextStyle(
                                    decoration: s.enabled ? null : TextDecoration.lineThrough,
                                    color: s.enabled ? null : Colors.grey)),
                            subtitle: Text([
                              _roleName(s.role),
                              s.phone,
                              if (s.blocked) 'HR: ${s.hrStatus.isEmpty ? 'ishlamaydi' : s.hrStatus}',
                              if (!s.active) 'o‘chirilgan',
                            ].where((x) => x.isNotEmpty).join(' · ')),
                            trailing: Icon(s.enabled ? Icons.check_circle : Icons.block,
                                color: s.enabled ? Colors.green : Colors.red),
                            onTap: () => _edit(s),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// HR ro'yxatidan xodim tanlash (qidiruv — ism yoki telefon).
class _HrPickerPage extends StatefulWidget {
  final KassaStaffService service;
  const _HrPickerPage({required this.service});

  @override
  State<_HrPickerPage> createState() => _HrPickerPageState();
}

class _HrPickerPageState extends State<_HrPickerPage> {
  List<HrPerson> _list = const [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final l = await widget.service.searchHr(q);
      if (!mounted) return;
      setState(() {
        _list = l;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ism yoki telefon', border: InputBorder.none),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _list.isEmpty
                  ? const Center(child: Text('Topilmadi'))
                  : ListView(children: [
                      for (final p in _list)
                        ListTile(
                          enabled: p.staffId == 0,
                          leading: CircleAvatar(
                            backgroundImage: p.photoUrl.isEmpty
                                ? null
                                : appNetworkImageProvider(context, p.photoUrl, displayWidth: 40),
                            child: p.photoUrl.isEmpty ? Text(p.fio.isEmpty ? '?' : p.fio[0]) : null,
                          ),
                          title: Text(p.fio),
                          subtitle: Text([p.lavozim, p.phone, if (p.staffId != 0) 'allaqachon kassada']
                              .where((x) => x.isNotEmpty)
                              .join(' · ')),
                          onTap: () => Navigator.pop(context, p),
                        ),
                    ]),
    );
  }
}
