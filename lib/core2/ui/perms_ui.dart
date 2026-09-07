// core2/ui/perms_ui.dart — mone_core ruxsatlar va foydalanuvchilar (admin,
// perm users.manage). PermsUi — rollar × perms switch jadvali: rol tanlanadi
// (chip, ro'yxat GET /roles, superadmin tahrirlanmaydi), katalog (/perms)
// guruh bo'yicha, har switch → PUT /roles/{role}/perms (butun map).
// CoreUsersUi — foydalanuvchilar ro'yxati (`{items,total}`; rol, omborlar,
// faol) + tahrir dialogi (nom, telefon, login_code, rol, omborlar chip,
// faol, parol ixtiyoriy, shaxsiy perm override).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_admin_service.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

// Fallback (GET /roles ishlamasa); superadmin faqat foydalanuvchi dialogida.
const List<String> kCoreRoles = [
  'admin',
  'bugalter',
  'ombor',
  'bozorchi',
  'shef',
  'seller',
];

class PermsUi extends StatefulWidget {
  const PermsUi({super.key});

  @override
  State<PermsUi> createState() => _PermsUiState();
}

class _PermsUiState extends State<PermsUi> {
  final _service = CoreAdminService();
  List<CorePermDef>? _catalog;
  // /roles dan (superadmin tahrirlanmaydi — ro'yxatdan chiqariladi).
  List<String> _roles = kCoreRoles;
  String _role = kCoreRoles.first;
  Map<String, bool>? _perms;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _perms = null;
    });
    try {
      _catalog ??= await _service.perms();
      if (_roles == kCoreRoles) {
        final rs = await _service.roles().catchError((_) => <String>[]);
        final editable = rs.where((r) => r != 'superadmin').toList();
        if (editable.isNotEmpty) {
          _roles = editable;
          if (!_roles.contains(_role)) _role = _roles.first;
        }
      }
      final p = await _service.rolePerms(_role);
      if (mounted) setState(() => _perms = p);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _toggle(String perm, bool v) async {
    final prev = Map<String, bool>.from(_perms ?? {});
    setState(() {
      _perms = {...prev, perm: v};
      _saving = true;
    });
    try {
      await _service.saveRolePerms(_role, _perms!);
    } catch (e) {
      if (mounted) {
        setState(() => _perms = prev);
        showCoreError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CorePermDef>>{};
    for (final p in _catalog ?? const <CorePermDef>[]) {
      groups.putIfAbsent(p.grp, () => []).add(p);
    }
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Ruxsatlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        needDicts: false,
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (final r in _roles) ...[
                    ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: _role == r,
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (_) {
                        setState(() => _role = r);
                        _load();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? CoreErrorView(message: _error!, onRetry: _load)
                  : _perms == null || _catalog == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          children: [
                            for (final g in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                                child: Text(_groupTitle(g.key),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, color: kCoreAccentDark)),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Column(
                                  children: [
                                    for (final p in g.value)
                                      SwitchListTile(
                                        dense: true,
                                        title: Text(p.title, style: const TextStyle(fontSize: 13.5)),
                                        subtitle: Text(p.perm,
                                            style: TextStyle(
                                                fontSize: 11, color: Colors.grey.shade600)),
                                        value: _perms![p.perm] ?? false,
                                        activeThumbColor: kCoreAccent,
                                        onChanged: (v) => _toggle(p.perm, v),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _groupTitle(String g) {
    switch (g) {
      case 'docs':
        return 'Hujjatlar';
      case 'dict':
        return 'Lug\'atlar / retsept';
      case 'view':
        return 'Ko\'rish';
      case 'admin':
        return 'Boshqaruv';
      default:
        return g;
    }
  }
}

// ───────────────────────── Foydalanuvchilar ─────────────────────────

class CoreUsersUi extends StatefulWidget {
  const CoreUsersUi({super.key});

  @override
  State<CoreUsersUi> createState() => _CoreUsersUiState();
}

class _CoreUsersUiState extends State<CoreUsersUi> {
  final _service = CoreAdminService();
  List<CoreUser>? _users;
  List<CorePermDef>? _catalog;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final u = await _service.users();
      _catalog ??= await _service.perms().catchError((_) => <CorePermDef>[]);
      if (mounted) setState(() => _users = u);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _edit(CoreUser? u) async {
    final result = await showDialog<_UserResult>(
      context: context,
      builder: (_) => _UserDialog(user: u, catalog: _catalog ?? const []),
    );
    if (result == null || !mounted) return;
    try {
      await _service.saveUser(result.user, password: result.password);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dict = context.read<CoreDictProvider>();
    final q = _q.toLowerCase();
    final list = (_users ?? const <CoreUser>[])
        .where((u) => q.isEmpty || u.name.toLowerCase().contains(q) || u.phone.contains(q))
        .toList();
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Foydalanuvchilar (v2)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: coreInput('Qidirish', suffix: const Icon(Icons.search, size: 18)),
              ),
            ),
            Expanded(
              child: _error != null
                  ? CoreErrorView(message: _error!, onRetry: _load)
                  : _users == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final u = list[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: ListTile(
                                dense: true,
                                onTap: () => _edit(u),
                                leading: CircleAvatar(
                                  backgroundColor: kCoreAccent.withValues(alpha: 0.2),
                                  child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: kCoreAccentDark)),
                                ),
                                title: Text(u.name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: u.active ? Colors.black87 : Colors.grey)),
                                subtitle: Text(
                                  [
                                    u.role,
                                    if (u.phone.isNotEmpty) u.phone,
                                    if (u.loginCode.isNotEmpty) 'kod: ${u.loginCode}',
                                    u.sklads.isEmpty
                                        ? 'hamma ombor'
                                        : u.sklads.map(dict.skladName).join(', '),
                                    if (!u.active) 'nofaol',
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            );
                          },
                        ),
            ),
          ],
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

class _UserResult {
  final CoreUser user;
  final String? password;
  const _UserResult(this.user, this.password);
}

class _UserDialog extends StatefulWidget {
  final CoreUser? user;
  final List<CorePermDef> catalog;
  const _UserDialog({this.user, required this.catalog});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final _name = TextEditingController(text: widget.user?.name ?? '');
  late final _phone = TextEditingController(text: widget.user?.phone ?? '');
  late final _code = TextEditingController(text: widget.user?.loginCode ?? '');
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'ombor';
  late Set<int> _sklads = {...?widget.user?.sklads};
  late bool _active = widget.user?.active ?? true;
  late Map<String, bool> _override = {...?widget.user?.permsOverride};
  bool _showPerms = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sklads = context.read<CoreDictProvider>().sklads;
    final roles = {...kCoreRoles, _role}.toList();
    return AlertDialog(
      title: Text(widget.user == null ? 'Yangi foydalanuvchi' : 'Tahrirlash'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, decoration: coreInput('Ism')),
              const SizedBox(height: 10),
              TextField(controller: _phone, decoration: coreInput('Telefon')),
              const SizedBox(height: 10),
              TextField(controller: _code, decoration: coreInput('Kirish kodi (login_code)')),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: coreInput('Parol (ixtiyoriy, o\'zgartirish uchun)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: coreInput('Rol'),
                items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 10),
              const Text('Omborlar (bo\'sh — hammasi)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in sklads)
                    FilterChip(
                      label: Text(s.name, style: const TextStyle(fontSize: 12)),
                      selected: _sklads.contains(s.id),
                      selectedColor: kCoreAccent.withValues(alpha: 0.25),
                      onSelected: (v) => setState(() {
                        _sklads = {..._sklads};
                        v ? _sklads.add(s.id) : _sklads.remove(s.id);
                      }),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Faol'),
                value: _active,
                activeThumbColor: kCoreAccent,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (widget.catalog.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _showPerms = !_showPerms),
                  icon: Icon(_showPerms ? Icons.expand_less : Icons.expand_more),
                  label: Text('Shaxsiy ruxsatlar (${_override.length})'),
                ),
              if (_showPerms)
                for (final p in widget.catalog)
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.title, style: const TextStyle(fontSize: 12.5)),
                      ),
                      // 3 holat: rol bo'yicha (—), ruxsat (✓), taqiq (✗)
                      SegmentedButton<int>(
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: 0, label: Text('—')),
                          ButtonSegment(value: 1, label: Text('✓')),
                          ButtonSegment(value: 2, label: Text('✗')),
                        ],
                        selected: {
                          !_override.containsKey(p.perm) ? 0 : (_override[p.perm]! ? 1 : 2)
                        },
                        onSelectionChanged: (s) => setState(() {
                          _override = {..._override};
                          switch (s.first) {
                            case 1:
                              _override[p.perm] = true;
                              break;
                            case 2:
                              _override[p.perm] = false;
                              break;
                            default:
                              _override.remove(p.perm);
                          }
                        }),
                      ),
                    ],
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
              _UserResult(
                CoreUser(
                  id: widget.user?.id ?? 0,
                  name: name,
                  phone: _phone.text.trim(),
                  loginCode: _code.text.trim(),
                  role: _role,
                  permsOverride: _override,
                  sklads: _sklads.toList()..sort(),
                  active: _active,
                ),
                _password.text.isEmpty ? null : _password.text,
              ),
            );
          },
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}
