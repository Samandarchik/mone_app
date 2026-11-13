import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

const _roleLabels = {
  'super_admin': 'Super admin',
  'admin': 'Admin',
  'cashier': 'Kassir',
  'waiter': 'Ofitsiant',
  'kitchen': 'Oshpaz',
};

const _roleColors = {
  'super_admin': Color(0xFF7C3AED),
  'admin': AppColors.primary,
  'cashier': AppColors.success,
  'waiter': AppColors.warning,
  'kitchen': AppColors.danger,
};

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _roleFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await ApiService().getUsers(force: true);
      if (!mounted) return;
      setState(() {
        _users = u;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  /// Xodim maydonlarini tekshiradi va SABABINI qaytaradi (null = joyida).
  ///
  /// Server ham tekshiradi, lekin uning xatosi ilgari yutilardi. Telefon
  /// esa `+998` prefiksiga qo'shib yuborilardi: to'liq raqam kiritilsa
  /// "+998+998901234567" ketardi.
  String? _validate(String name, String phone, String pin,
      {required bool requirePin}) {
    if (name.trim().isEmpty) return 'Ism kiritilishi kerak';
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 9) {
      return 'Telefon 9 raqamdan iborat bo‘lishi kerak (+998 dan keyin)';
    }
    if (requirePin || pin.isNotEmpty) {
      if (pin.length != 4 || !RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
        return 'PIN aynan 4 ta raqamdan iborat bo‘lishi kerak';
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _users
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((u) {
          if (_roleFilter.isNotEmpty && u['role'] != _roleFilter) return false;
          if (q.isEmpty) return true;
          final name = (u['name'] ?? '').toString().toLowerCase();
          final phone = (u['phone'] ?? '').toString().toLowerCase();
          final role = (_roleLabels[u['role']] ?? '').toLowerCase();
          return name.contains(q) || phone.contains(q) || role.contains(q);
        })
        .toList();
  }

  Future<void> _openForm({Map<String, dynamic>? user}) async {
    final editing = user != null;
    final nameC = TextEditingController(text: user?['name']?.toString() ?? '');
    final phoneC = TextEditingController(
      text: (user?['phone'] ?? '').toString().replaceFirst('+998', ''),
    );
    final pinC = TextEditingController();
    var role = (user?['role'] ?? 'waiter').toString();

    final saved = await showAdminForm(
      context: context,
      title: editing ? (user['name']?.toString() ?? 'Xodim') : 'Yangi xodim',
      subtitle: editing ? 'Ma’lumotlarni tahrirlash' : 'PIN kod bilan kiradi',
      icon: editing ? Icons.badge_rounded : Icons.person_add_alt_1_rounded,
      color: const Color(0xFF8B5CF6),
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Ism familiya',
          controller: nameC,
          hint: 'Masalan: Aziz Karimov',
          icon: Icons.person_outline_rounded,
          autofocus: !editing,
        ),
        AdminField(
          label: 'Telefon raqami',
          controller: phoneC,
          hint: '901234567',
          prefixText: '+998 ',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          maxLength: 9,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        AdminField(
          label: editing ? 'Yangi PIN kod' : 'PIN kod',
          controller: pinC,
          hint: '4 ta raqam',
          helper: editing
              ? 'Bo‘sh qoldirilsa — eski PIN o‘zgarmaydi'
              : 'Xodim shu PIN bilan tizimga kiradi',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscure: true,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        AdminChoice<String>(
          label: 'Lavozimi',
          value: role,
          items: _roleLabels,
          colors: _roleColors,
          onChanged: (v) => refresh(() => role = v),
        ),
      ],
      submitLabel: editing ? 'Saqlash' : 'Qo‘shish',
      onSubmit: () async {
        final problem = _validate(
          nameC.text,
          phoneC.text,
          pinC.text,
          requirePin: !editing,
        );
        if (problem != null) {
          showErr(context, problem);
          return false;
        }
        final data = <String, dynamic>{
          'name': nameC.text.trim(),
          'phone': '+998${phoneC.text.replaceAll(RegExp(r'[^0-9]'), '')}',
          'role': role,
        };
        if (pinC.text.isNotEmpty) data['pin'] = pinC.text;
        try {
          if (editing) {
            await ApiService().updateUser(user['id'] as int, data);
          } else {
            await ApiService().createUser(data);
          }
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
      onDelete: editing
          ? () async {
              try {
                await ApiService().deleteUser(user['id'] as int);
                return true;
              } catch (e) {
                if (mounted) showErr(context, apiErrorText(e));
                return false;
              }
            }
          : null,
      deleteLabel: 'Xodimni o‘chirish',
    );

    if (saved == true) {
      if (mounted) showOk(context, editing ? 'Saqlandi' : 'Xodim qo‘shildi');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final counts = <String, int>{};
    for (final u in _users.whereType<Map>()) {
      final r = (u['role'] ?? '').toString();
      counts[r] = (counts[r] ?? 0) + 1;
    }

    return AdminPage(
      subtitle: '${_users.length} ta xodim',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: _load,
      onSearchChanged: (v) => setState(() => _query = v),
      searchHint: 'Ism yoki telefon bo‘yicha…',
      primaryAction: AdminAction(
        label: 'Yangi xodim',
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => _openForm(),
      ),
      toolbar: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            KChip(
              label: 'Hammasi',
              selected: _roleFilter.isEmpty,
              badge: _users.length,
              onTap: () => setState(() => _roleFilter = ''),
            ),
            for (final e in _roleLabels.entries)
              if ((counts[e.key] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: KChip(
                    label: e.value,
                    selected: _roleFilter == e.key,
                    accent: _roleColors[e.key] ?? AppColors.primary,
                    badge: counts[e.key],
                    onTap: () => setState(() => _roleFilter = e.key),
                  ),
                ),
          ],
        ),
      ),
      child: list.isEmpty
          ? AdminEmpty(
              icon: Icons.badge_outlined,
              title: _users.isEmpty ? 'Hali xodim yo‘q' : 'Topilmadi',
              message: _users.isEmpty
                  ? 'Kassir, ofitsiant va oshpazlarni shu yerdan qo‘shasiz. Har biri o‘z PIN kodi bilan kiradi.'
                  : 'Qidiruv yoki filtrni o‘zgartirib ko‘ring.',
              actionLabel: _users.isEmpty ? 'Xodim qo‘shish' : null,
              onAction: _users.isEmpty ? () => _openForm() : null,
              color: const Color(0xFF8B5CF6),
            )
          : AdminList(
              children: [
                for (final u in list)
                  AdminTile(
                    title: u['name']?.toString() ?? '—',
                    subtitle: _prettyPhone(u['phone']?.toString() ?? ''),
                    initials: _initials(u['name']?.toString() ?? '?'),
                    color: _roleColors[u['role']] ?? AppColors.textMuted,
                    badge: StatusBadge(
                      label: _roleLabels[u['role']] ?? '${u['role'] ?? ''}',
                      color: _roleColors[u['role']] ?? AppColors.textMuted,
                    ),
                    onTap: () => _openForm(user: u),
                    menu: const [
                      AdminMenuItem(
                        value: 'edit',
                        label: 'Tahrirlash',
                        icon: Icons.edit_outlined,
                      ),
                      AdminMenuItem(
                        value: 'delete',
                        label: 'O‘chirish',
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                    ],
                    onMenuSelected: (v) async {
                      if (v == 'edit') {
                        _openForm(user: u);
                      } else if (v == 'delete') {
                        final ok = await confirmAction(
                          context: context,
                          title: 'Xodimni o‘chirish',
                          message:
                              '${u['name']} tizimdan butunlay o‘chiriladi.',
                          confirmLabel: 'O‘chirish',
                          danger: true,
                        );
                        if (ok != true) return;
                        try {
                          await ApiService().deleteUser(u['id'] as int);
                          if (!context.mounted) return;
                          showOk(context, 'O‘chirildi');
                        } catch (e) {
                          if (!context.mounted) return;
                          showErr(context, apiErrorText(e));
                        }
                        _load();
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.elementAt(1).characters.first)
      .toUpperCase();
}

/// +998901234567 → +998 90 123 45 67
String _prettyPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length != 12) return raw;
  return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} '
      '${d.substring(8, 10)} ${d.substring(10)}';
}
