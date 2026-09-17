// admin/ui/user_management_screen.dart — foydalanuvchilarni boshqarish ekrani
// (UserManagementScreen): UserManagementService orqali ro'yxat/o'chirish, qator
// bosilsa UserEditDialog, login+parolni Telegram orqali yuborish.
// Foydalanuvchilar ro'yxati: oq karta ichida qatorlar, har qatorda avatar
// (bosh harflar), telefon, ochiq parol, Telegram holati, rol pill'i va dostup.
// Qator bosilsa — tahrirlash dialogi, uzoq bosilsa — o'chirish tasdig'i.
// Yuborish tugmalari login+parolni Telegram orqali jo'natadi.
// Har qatorda berilgan dostup (filial/sklad/kategoriya/Ostatka/manba) nomlari
// bilan ko'rinadi (_accessBlock) — dialogni ochmasdan; ✏️ tahrirlash dialogini
// ochadi. Kategoriya nomlari ProductProvider'dan, Ostatka omborlari
// Sh5Service.fetchSklads'dan bir marta yuklanadi (yuklanmaguncha — soni).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/user_model.dart';
import 'package:uz_ai_dev/admin/services/sh5_service.dart';
import 'package:uz_ai_dev/admin/services/user_management_service.dart';
import 'package:uz_ai_dev/admin/ui/user_edit_dialog.dart';
import 'package:uz_ai_dev/core/constants/roles.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';

// Bitta dostup guruhi (masalan «Kategoriya: Tortlar, Pirojniy +3»).
class _AccessGroup {
  final IconData icon;
  final String title;
  final List<String> items;
  // items bo'sh bo'lganda ko'rsatiladigan matn.
  final String emptyText;
  const _AccessGroup(this.icon, this.title, this.items, this.emptyText);
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final UserManagementService _userService = UserManagementService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<User> _users = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String _query = '';

  // Dostup nomlari uchun: id → nom.
  Map<int, String> _categoryNames = {};
  Map<int, String> _sh5Names = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
    // Provider darhol notify qiladi — build fazasidan keyinga.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAccessNames();
    });
  }

  // Kategoriya va Ostatka ombor nomlari. Xato bo'lsa jim — qatorda soni chiqadi.
  Future<void> _loadAccessNames() async {
    final products = context.read<ProductProvider>();
    try {
      if (products.categories.isEmpty) await products.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categoryNames = {for (final c in products.categories) c.id: c.name};
      });
    } catch (_) {}
    try {
      final sklads = await Sh5Service().fetchSklads();
      if (!mounted) return;
      setState(() {
        _sh5Names = {for (final s in sklads) s.id: s.name};
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Qidiruv: ism, telefon, rol va filial nomi bo'yicha (katta-kichik harf farqsiz).
  List<User> get _filteredUsers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _users;
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    return _users.where((u) {
      if (_displayName(u).toLowerCase().contains(q)) return true;
      if (qDigits.isNotEmpty &&
          u.phone.replaceAll(RegExp(r'\D'), '').contains(qDigits)) {
        return true;
      }
      if (_roleLabel(u.role).toLowerCase().contains(q)) return true;
      final filial = u.filial?.name.toLowerCase() ?? '';
      return filial.contains(q);
    }).toList();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final users = await _userService.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _errText(e);
        _isLoading = false;
      });
    }
  }

  String _errText(Object e) => e.toString().replaceFirst('Exception: ', '');

  String _displayName(User u) => u.name.isNotEmpty ? u.name : u.phone;

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ==================== Amallar ====================

  Future<void> _openEditDialog(User? user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => UserEditDialog(user: user),
    );
    if (result == true && mounted) {
      _showSnack(
        user != null
            ? 'Foydalanuvchi yangilandi'
            : 'Yangi foydalanuvchi yaratildi',
        Colors.green.shade600,
      );
      _loadUsers();
    }
  }

  Future<void> _confirmDelete(User user) async {
    final name = _displayName(user);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('O\'chirish'),
        content: Text('$name o\'chirilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _userService.deleteUser(user.id);
      if (!mounted) return;
      _showSnack('Foydalanuvchi o\'chirildi', Colors.green.shade600);
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      _showSnack(_errText(e), Colors.red.shade600);
    }
  }

  /// Bitta foydalanuvchiga login+parolni Telegram orqali yuborish.
  Future<void> _sendCredentials(User user) async {
    final name = _displayName(user);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Telegram orqali yuborish'),
        content:
            Text('$name — login va parol Telegram orqali yuborilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(const SnackBar(content: Text('Yuborilmoqda...')));
    try {
      await _userService.sendCredentials(user.id);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('Telegram orqali yuborildi'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // Backend xabari (masalan "Bu foydalanuvchining Telegrami bog'lanmagan").
      messenger.showSnackBar(SnackBar(
        content: Text(_errText(e)),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// Barcha foydalanuvchilarga login+parolni Telegram orqali yuborish.
  Future<void> _sendAllCredentials() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hammaga yuborish'),
        content: const Text(
            'Barcha foydalanuvchilarga login va parol Telegram orqali yuborilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(const SnackBar(content: Text('Yuborilmoqda...')));
    try {
      final res = await _userService.sendAllCredentials();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      final parts = <String>['${res.sent} ta yuborildi'];
      if (res.skipped.isNotEmpty) {
        parts.add('${res.skipped.length} ta Telegramsiz');
      }
      if (res.failed.isNotEmpty) parts.add('${res.failed.length} ta xato');
      messenger.showSnackBar(SnackBar(
        content: Text(parts.join(' · ')),
        backgroundColor: res.failed.isNotEmpty ? Colors.orange : Colors.green,
        duration: const Duration(seconds: 6),
        action: res.skipped.isNotEmpty
            ? SnackBarAction(
                label: 'Batafsil',
                textColor: Colors.white,
                onPressed: () => _showSkippedDialog(res.skipped),
              )
            : null,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(_errText(e)),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// Telegrami bog'lanmagani uchun o'tkazib yuborilganlar ro'yxati +
  /// botga ulanish yo'riqnomasi.
  Future<void> _showSkippedDialog(List<String> skipped) async {
    final botUsername = await _userService.getTelegramBotUsername();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Telegram ulanmaganlar'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final name in skipped)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    'Ular @$botUsername botiga kirib, telefon raqamini '
                    'yuborishi kerak',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1E40AF)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  // ==================== UI bo'laklari ====================

  String _roleLabel(String role) {
    switch (role) {
      case AppRoles.seller:
        return 'Sotuvchi';
      case AppRoles.ombor:
        return 'Ombor';
      case AppRoles.yukKeltiruvchi:
        return 'Yuk keltiruvchi';
      case AppRoles.bugalter:
        return 'Bugalter';
      case AppRoles.shef:
        return 'Shef';
      case AppRoles.admin:
      case AppRoles.superAdmin:
        return 'Admin';
      default:
        return role;
    }
  }

  bool _isAdminUser(User u) =>
      u.isAdmin || u.role == AppRoles.admin || u.role == AppRoles.superAdmin;

  String _initials(User u) {
    final name = _displayName(u).trim();
    if (name.isEmpty) return '?';
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _avatar(User u, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE0E7FF),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(u),
        style: TextStyle(
          fontSize: size >= 72 ? 24 : 18,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF3730A3),
        ),
      ),
    );
  }

  Widget _rolePill(User u) {
    final isAdmin = _isAdminUser(u);
    final bg = isAdmin ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF);
    final border = isAdmin ? const Color(0xFFFDE68A) : const Color(0xFFC7D2FE);
    final dot = isAdmin ? const Color(0xFFD97706) : const Color(0xFF4F46E5);
    final textColor =
        isAdmin ? const Color(0xFF92400E) : const Color(0xFF3730A3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              isAdmin ? 'Admin' : _roleLabel(u.role),
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneLine(User u, {double fontSize = 13}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF2563EB)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            u.phone,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2563EB),
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFF2563EB),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _passwordLine(User u) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.key_rounded, size: 14, color: Color(0xFF9CA3AF)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            u.passwordPlain,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Telegram bog'langan/bog'lanmagan holat chip'i.
  Widget _telegramStatus(User u) {
    final linked = u.telegramChatId != 0;
    final color =
        linked ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.send_rounded, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          linked ? 'Ulangan' : 'Ulanmagan',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _sendButton(User u) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Telegram orqali yuborish',
      icon: const Icon(Icons.send_rounded, size: 20, color: Color(0xFF2563EB)),
      onPressed: () => _sendCredentials(u),
    );
  }

  static const Map<String, String> _sourceLabels = {
    'samarqand': 'Samarqand',
    'toshkent': 'Toshkent',
    'zagranitsa': 'Zagranitsa',
  };

  List<String> _categoryList(User u) => [
        for (final id in u.categoryIds ?? const <int>[])
          _categoryNames[id] ?? '#$id',
      ];

  List<String> _skladList(User u) =>
      [for (final id in u.sklads) SkladRegistry.nameOf(id)];

  // Rolga qarab qaysi dostup maydonlari ma'noli — user_edit_dialog.dart
  // dagi rol → maydon qoidalari bilan bir xil.
  List<_AccessGroup> _accessGroups(User u) {
    if (_isAdminUser(u)) {
      return const [
        _AccessGroup(Icons.verified_user_outlined, 'To\'liq dostup', [], ''),
      ];
    }
    switch (u.role) {
      case AppRoles.seller:
        return [
          _AccessGroup(Icons.store_outlined, 'Filial',
              [if (u.filial != null) u.filial!.name], 'tanlanmagan'),
          _AccessGroup(Icons.category_outlined, 'Kategoriya',
              _categoryList(u), 'yo\'q'),
          _AccessGroup(Icons.inventory_2_outlined, 'Ostatka', [
            for (final id in u.sh5Sklads) _sh5Names[id] ?? '#$id',
          ], 'yo\'q'),
        ];
      case AppRoles.ombor:
        return [
          _AccessGroup(
              Icons.warehouse_outlined, 'Sklad', _skladList(u), 'tanlanmagan'),
          _AccessGroup(Icons.category_outlined, 'Kategoriya',
              _categoryList(u), 'yo\'q'),
        ];
      case AppRoles.shef:
        return [
          _AccessGroup(
              Icons.warehouse_outlined, 'Sklad', _skladList(u), 'tanlanmagan'),
          _AccessGroup(Icons.menu_book_outlined, 'Тех карта',
              _categoryList(u), 'yo\'q'),
        ];
      case AppRoles.yukKeltiruvchi:
        return [
          _AccessGroup(
              Icons.warehouse_outlined, 'Sklad', _skladList(u), 'tanlanmagan'),
          _AccessGroup(Icons.local_shipping_outlined, 'Manba', [
            for (final s in u.sources) _sourceLabels[s] ?? s,
          ], 'hammasi'),
        ];
      case AppRoles.bugalter:
        return const [
          _AccessGroup(Icons.lock_open_outlined, 'Cheklovsiz', [], ''),
        ];
      default:
        return const [];
    }
  }

  // «Kategoriya: A, B, C +4» — to'liq ro'yxat tooltip'da.
  Widget _accessChip(_AccessGroup g) {
    const maxShown = 3;
    final bool noValue = g.items.isEmpty && g.emptyText.isNotEmpty;
    final String value;
    if (g.items.isEmpty) {
      value = g.emptyText;
    } else if (g.items.length <= maxShown) {
      value = g.items.join(', ');
    } else {
      value = '${g.items.take(maxShown).join(', ')} '
          '+${g.items.length - maxShown}';
    }
    final fg = noValue ? const Color(0xFF9CA3AF) : const Color(0xFF374151);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: noValue ? const Color(0xFFF9FAFB) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(g.icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: value.isEmpty ? g.title : '${g.title}: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (value.isNotEmpty) TextSpan(text: value),
              ]),
              style: TextStyle(fontSize: 12, color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (g.items.length <= maxShown) return chip;
    return Tooltip(message: g.items.join('\n'), child: chip);
  }

  // Dostup chiplari + ✏️ (tahrirlash dialogi).
  Widget _accessBlock(User u) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final g in _accessGroups(u)) _accessChip(g)],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Dostupni o\'zgartirish',
          icon: const Icon(Icons.edit_outlined,
              size: 18, color: Color(0xFF4F46E5)),
          onPressed: () => _openEditDialog(u),
        ),
      ],
    );
  }

  // Tor (telefon) ekran qatori: tepada avatar + ism/telefon/parol/Telegram,
  // o'ngda yuborish tugmasi; pastda rol pill + filial.
  Widget _rowNarrow(User u, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditDialog(u),
      onLongPress: () => _confirmDelete(u),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                const SizedBox(width: 8),
                _avatar(u, 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _displayName(u),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF111827),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _phoneLine(u),
                      if (u.passwordPlain.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _passwordLine(u),
                      ],
                      const SizedBox(height: 4),
                      _telegramStatus(u),
                    ],
                  ),
                ),
                _sendButton(u),
              ],
            ),
            const SizedBox(height: 10),
            // Rol — pastda alohida qatorda, uning ostida dostup.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: _rolePill(u),
            ),
            const SizedBox(height: 8),
            _accessBlock(u),
          ],
        ),
      ),
    );
  }

  // Keng ekran qatori: hamma element bitta gorizontal qatorda.
  Widget _rowWide(User u, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openEditDialog(u),
      onLongPress: () => _confirmDelete(u),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ),
            SizedBox(width: 88, child: _avatar(u, 72)),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayName(u),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF111827),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  _phoneLine(u, fontSize: 14),
                  if (u.passwordPlain.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _passwordLine(u),
                  ],
                  const SizedBox(height: 4),
                  _telegramStatus(u),
                ],
              ),
            ),
            SizedBox(
              width: 180,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _rolePill(u),
              ),
            ),
            Expanded(flex: 3, child: _accessBlock(u)),
            _sendButton(u),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isNarrow) {
    return Padding(
      padding: EdgeInsets.all(isNarrow ? 12 : 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Text(
            _query.trim().isEmpty
                ? '${_users.length} ta foydalanuvchi'
                : '${_filteredUsers.length} / ${_users.length} ta foydalanuvchi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _openEditDialog(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Yangi foydalanuvchi'),
              ),
              IconButton(
                icon: const Icon(Icons.send_rounded),
                tooltip: 'Hammaga Telegram orqali yuborish',
                onPressed: _sendAllCredentials,
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadUsers,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Qidiruv maydoni — header bilan ro'yxat orasida.
  Widget _searchField(bool isNarrow) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          isNarrow ? 12 : 20, 0, isNarrow ? 12 : 20, isNarrow ? 12 : 16),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: 'Qidirish: ism, telefon, rol, filial...',
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey[500]),
          prefixIcon:
              Icon(Icons.search_rounded, size: 20, color: Colors.grey[500]),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey[500]),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF4F46E5)),
          ),
        ),
      ),
    );
  }

  Widget _content(bool isNarrow) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.red.shade600),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'Foydalanuvchilar yo\'q',
          style: TextStyle(fontSize: 15, color: Colors.grey[600]),
        ),
      );
    }
    final users = _filteredUsers;
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'Hech narsa topilmadi',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) =>
          isNarrow ? _rowNarrow(users[i], i) : _rowWide(users[i], i),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Foydalanuvchilar'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          return Padding(
            padding: isNarrow
                ? const EdgeInsets.all(8)
                : const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _header(isNarrow),
                  _searchField(isNarrow),
                  const Divider(height: 1),
                  Expanded(child: _content(isNarrow)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
