import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/api_service.dart';
import '../../core/services/app_state.dart';
import '../../core/services/wss_service.dart';
import '../../core/theme/app_theme.dart';
import 'admin_nav.dart';
import 'widgets/admin_page.dart';

/// Yon panelning to'q rangi — navigatsiya kontentdan aniq ajralib turadi.
class _Nav {
  static const bg = Color(0xFF0F172A);
  static const bgSoft = Color(0xFF1E293B);
  static const line = Color(0xFF1E293B);
  static const text = Color(0xFFCBD5E1);
  static const textDim = Color(0xFF64748B);
}

const _kRailCollapsedKey = 'admin_rail_collapsed';

class AdminShell extends StatefulWidget {
  final VoidCallback onLogout;
  final Map<String, dynamic> permissions;
  final String role;
  const AdminShell({
    super.key,
    required this.onLogout,
    this.permissions = const {},
    this.role = '',
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late List<AdminDestination> _items;
  late String _currentId;

  /// Orqaga qaytish tarixi — telefonda tizim «orqaga» tugmasi ilovadan
  /// chiqarib yubormasdan, oldingi bo'limga qaytaradi.
  final List<String> _history = [];

  bool _railCollapsed = false;
  StreamSubscription? _wssSub;

  /// Texnik bo'limlar («Tizim nazorati», «Bulut») ochilganmi.
  /// Har safar ilova qayta ochilganda yana yashiriladi.
  bool _hiddenShown = false;

  @override
  void initState() {
    super.initState();
    _items = visibleDestinations(widget.permissions, widget.role);
    _currentId = _items.isEmpty ? '' : _items.first.id;
    _restoreRail();
    _wssSub = WssService().eventStream.listen((event) {
      final e = event['event'];
      if (e == 'menu:outdated') {
        ApiService().invalidateMenu();
      } else if (e == 'stock:updated') {
        ApiService().invalidateStocks();
      }
    });
  }

  Future<void> _restoreRail() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _railCollapsed = p.getBool(_kRailCollapsedKey) ?? false);
  }

  Future<void> _toggleRail() async {
    setState(() => _railCollapsed = !_railCollapsed);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRailCollapsedKey, _railCollapsed);
  }

  /// «Local server» belgisini 5 soniya bosib turish — texnik bo'limlarni
  /// ochadi/yopadi. Kassir tasodifan sync va server sozlamalariga
  /// kirmasligi uchun ular odatda ro'yxatda umuman ko'rinmaydi.
  void _toggleHidden() {
    final next = !_hiddenShown;
    final items = visibleDestinations(
      widget.permissions,
      widget.role,
      includeHidden: next,
    );
    setState(() {
      _hiddenShown = next;
      _items = items;
      _history.removeWhere((id) => !items.any((d) => d.id == id));
      if (!items.any((d) => d.id == _currentId)) {
        _currentId = items.isEmpty ? '' : items.first.id;
      }
    });
    HapticFeedback.mediumImpact();
    if (next) {
      // Ochilgan zahoti o'sha bo'limga o'tiladi — qidirib yurilmasin.
      _go('operations');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: next ? AppColors.success : _Nav.bgSoft,
          content: Text(
            next
                ? 'Texnik bo‘limlar ochildi'
                : 'Texnik bo‘limlar yana yashirildi',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  AdminDestination get _current =>
      _items.firstWhere((d) => d.id == _currentId, orElse: () => _items.first);

  void _go(String id) {
    if (id == _currentId) return;
    if (!_items.any((d) => d.id == id)) return;
    setState(() {
      _history.add(_currentId);
      if (_history.length > 12) _history.removeAt(0);
      _currentId = id;
    });
  }

  /// Tizim «orqaga» si: oldingi bo'lim → bosh bo'lim → ilovadan chiqish.
  bool _goBack() {
    if (_history.isNotEmpty) {
      setState(() => _currentId = _history.removeLast());
      return true;
    }
    if (_currentId != _items.first.id) {
      setState(() => _currentId = _items.first.id);
      return true;
    }
    return false;
  }

  Future<void> _openNav() async {
    final isPhone = context.isPhoneUi;
    final selected = isPhone
        ? await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _NavSheet(
              items: _items,
              currentId: _currentId,
              onLogout: widget.onLogout,
              hiddenShown: _hiddenShown,
              canUnlock: hasHiddenDestinations(widget.permissions, widget.role),
              onToggleHidden: _toggleHidden,
            ),
          )
        : await showDialog<String>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.45),
            builder: (_) =>
                _CommandPalette(items: _items, currentId: _currentId),
          );
    if (selected != null) _go(selected);
  }

  void _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tizimdan chiqasizmi?'),
        content: const Text('Qayta kirish uchun PIN kod kerak bo‘ladi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chiqish'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: AppColors.textFaint,
              ),
              const SizedBox(height: 14),
              const Text(
                'Sizda hech qanday bo‘limga ruxsat yo‘q',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Chiqish'),
              ),
            ],
          ),
        ),
      );
    }

    final dest = _current;
    final isPhone = context.isPhoneUi;

    final body = AdminScope(
      destination: dest,
      isPhone: isPhone,
      go: _go,
      openNav: _openNav,
      // Bo'lim almashganda ekran QAYTA yaratiladi — doim yangi ma'lumot
      // (tirik saqlansa admin eski summani ko'rib qolardi).
      child: KeyedSubtree(key: ValueKey(dest.id), child: dest.build()),
    );

    final scaffold = isPhone
        ? _buildPhone(dest, body)
        : _buildDesktop(dest, body);

    // Ctrl+K / ⌘K — istalgan joydan bo'lim qidirish.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openNav,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openNav,
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  // ===================== TELEFON =====================

  Widget _buildPhone(AdminDestination dest, Widget body) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_goBack()) Navigator.of(context).maybePop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: body,
        bottomNavigationBar: _BottomBar(
          items: _items,
          currentId: _currentId,
          onSelect: _go,
          onMore: _openNav,
        ),
      ),
    );
  }

  // ===================== PLANSHET / DESKTOP =====================

  Widget _buildDesktop(AdminDestination dest, Widget body) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          _Sidebar(
            items: _items,
            currentId: _currentId,
            collapsed: _railCollapsed,
            onSelect: _go,
            onToggle: _toggleRail,
            onSearch: _openNav,
            onLogout: _confirmLogout,
            userName: AppState().userName,
            role: widget.role,
            hiddenShown: _hiddenShown,
            canUnlock: hasHiddenDestinations(widget.permissions, widget.role),
            onToggleHidden: _toggleHidden,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ============================================================
// Yon panel (planshet / desktop)
// ============================================================

class _Sidebar extends StatelessWidget {
  final List<AdminDestination> items;
  final String currentId;
  final bool collapsed;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggle;
  final VoidCallback onSearch;
  final VoidCallback onLogout;
  final String? userName;
  final String role;

  /// Texnik bo'limlar hozir ochiqmi.
  final bool hiddenShown;

  /// Yashiradigan bo'lim umuman bormi (yo'q bo'lsa bosib turish ma'nosiz).
  final bool canUnlock;
  final VoidCallback onToggleHidden;

  const _Sidebar({
    required this.items,
    required this.currentId,
    required this.collapsed,
    required this.onSelect,
    required this.onToggle,
    required this.onSearch,
    required this.onLogout,
    required this.userName,
    required this.role,
    required this.hiddenShown,
    required this.canUnlock,
    required this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AdminDestination>>{};
    for (final d in items) {
      groups.putIfAbsent(d.group, () => []).add(d);
    }
    final ordered = [
      ...AdminGroups.order.where(groups.containsKey),
      ...groups.keys.where((g) => !AdminGroups.order.contains(g)),
    ];

    return AnimatedContainer(
      duration: AppDuration.normal,
      curve: Curves.easeOutCubic,
      width: collapsed ? 76 : 250,
      color: _Nav.bg,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            _brand(context),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 14 : 12),
              child: _searchButton(),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 14 : 12,
                  vertical: 6,
                ),
                children: [
                  for (final g in ordered) ...[
                    if (collapsed)
                      const Divider(color: _Nav.line, height: 18)
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
                        child: Text(
                          g.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: _Nav.textDim,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    for (final d in groups[g]!)
                      _NavItem(
                        dest: d,
                        active: d.id == currentId,
                        collapsed: collapsed,
                        onTap: () => onSelect(d.id),
                      ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const Divider(color: _Nav.line, height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                collapsed ? 14 : 12,
                10,
                collapsed ? 14 : 12,
                10,
              ),
              child: Column(
                children: [
                  _NavStatus(
                    unlocked: hiddenShown,
                    onHold: canUnlock ? onToggleHidden : null,
                  ),
                  const SizedBox(height: 10),
                  _userRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brand(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 14 : 16,
        14,
        collapsed ? 14 : 12,
        12,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Center(
              child: Text(
                'K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MONE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    'Boshqaruv paneli',
                    style: TextStyle(color: _Nav.textDim, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          if (!collapsed)
            _NavIconButton(
              icon: Icons.menu_open_rounded,
              tooltip: 'Panelni yig‘ish',
              onTap: onToggle,
            ),
        ],
      ),
    );
  }

  Widget _searchButton() {
    if (collapsed) {
      return Column(
        children: [
          _NavIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Bo‘lim qidirish (Ctrl+K)',
            onTap: onSearch,
            big: true,
          ),
          const SizedBox(height: 6),
          _NavIconButton(
            icon: Icons.menu_rounded,
            tooltip: 'Panelni ochish',
            onTap: onToggle,
            big: true,
          ),
        ],
      );
    }
    return Material(
      color: _Nav.bgSoft,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onSearch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 18, color: _Nav.textDim),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Bo‘lim qidirish',
                  style: TextStyle(color: _Nav.textDim, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: const Text(
                  'Ctrl K',
                  style: TextStyle(
                    color: _Nav.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userRow() {
    final name = (userName ?? '').trim();
    final roleLabel = role == 'super_admin' ? 'Super admin' : 'Administrator';
    // Ism kelmagan bo'lsa rol nomi sarlavha bo'ladi — pastda uni takrorlash
    // o'rniga tugmaning nima qilishi yoziladi.
    final label = name.isEmpty ? roleLabel : name;
    final sub = name.isEmpty ? 'Tizimdan chiqish' : roleLabel;
    if (collapsed) {
      return _NavIconButton(
        icon: Icons.logout_rounded,
        tooltip: '$label — chiqish',
        onTap: onLogout,
        big: true,
        color: AppColors.danger,
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onLogout,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primary.withValues(alpha: 0.22),
                child: Text(
                  label.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      sub,
                      style: const TextStyle(color: _Nav.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.logout_rounded,
                size: 17,
                color: AppColors.danger,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final AdminDestination dest;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavItem({
    required this.dest,
    required this.active,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      active ? dest.activeIcon : dest.icon,
      size: 20,
      color: active ? Colors.white : _Nav.text,
    );

    final content = collapsed
        ? Center(child: icon)
        : Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dest.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? Colors.white : _Nav.text,
                  ),
                ),
              ),
            ],
          );

    final tile = Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: active
            ? dest.accent.withValues(alpha: 0.24)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: active
              ? dest.accent.withValues(alpha: 0.55)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 11),
            child: content,
          ),
        ),
      ),
    );

    if (!collapsed) return tile;
    return Tooltip(message: dest.label, preferBelow: false, child: tile);
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool big;
  final Color? color;
  const _NavIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.big = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _Nav.bgSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: SizedBox(
            width: big ? 48 : 36,
            height: big ? 44 : 36,
            child: Icon(icon, size: 19, color: color ?? _Nav.text),
          ),
        ),
      ),
    );
  }
}

/// Yon panel pastidagi ulanish holati: qaysi serverga ulangan va jonlimi.
/// Server holati belgisi.
///
/// Yashirin funksiya: 5 soniya bosib turilsa texnik bo'limlar
/// («Tizim nazorati», «Bulut») ro'yxatga qo'shiladi. Bosib turilgani
/// bilinib turishi uchun belgi ichi asta to'ladi — tasodifan bosib
/// qolgan odam nima bo'layotganini ko'radi va qo'lini uzadi.
class _NavStatus extends StatefulWidget {
  final bool unlocked;

  /// `null` — bosib turish o'chirilgan (yashiradigan bo'lim yo'q).
  final VoidCallback? onHold;

  const _NavStatus({required this.unlocked, this.onHold});

  @override
  State<_NavStatus> createState() => _NavStatusState();
}

class _NavStatusState extends State<_NavStatus>
    with SingleTickerProviderStateMixin {
  static const _holdFor = Duration(seconds: 5);

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: _holdFor)
        ..addStatusListener((st) {
          if (st != AnimationStatus.completed) return;
          _hold.value = 0;
          widget.onHold?.call();
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.onHold == null) return;
    _hold.forward(from: 0);
  }

  void _up() {
    if (_hold.value == 0) return;
    // Qo'l uzilsa darrov bo'shaydi — 5 soniya orqaga qaytib o'tirmaydi.
    _hold.animateBack(0, duration: const Duration(milliseconds: 180));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: WssService().connectionStream,
      initialData: WssService().isConnected,
      builder: (context, live) {
        final online = live.data ?? false;
        return StreamBuilder<bool>(
          stream: ApiService().endpointStream,
          initialData: ApiService().isUsingCloud,
          builder: (context, ep) {
            final onCloud = ep.data ?? false;
            final c = !online
                ? AppColors.danger
                : (onCloud ? AppColors.warning : AppColors.success);
            final label = !online
                ? 'Aloqa yo‘q'
                : (onCloud ? 'Bulut serveri' : 'Local server');
            return Listener(
              onPointerDown: (_) => _down(),
              onPointerUp: (_) => _up(),
              onPointerCancel: (_) => _up(),
              child: AnimatedBuilder(
                animation: _hold,
                builder: (context, _) => Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: c.withValues(alpha: 0.3)),
                  ),
                  child: Stack(
                    children: [
                      if (_hold.value > 0)
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _hold.value,
                            child: ColoredBox(color: c.withValues(alpha: 0.3)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: c,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (widget.unlocked) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.lock_open_rounded, size: 13, color: c),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================
// Pastki panel (telefon)
// ============================================================

class _BottomBar extends StatelessWidget {
  final List<AdminDestination> items;
  final String currentId;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  const _BottomBar({
    required this.items,
    required this.currentId,
    required this.onSelect,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    // Pastki panelga eng ko'p ishlatiladigan 4 ta bo'lim chiqadi,
    // qolganlari «Yana» ichida (qidiruvi bilan).
    final primary = items.where((d) => d.primaryOrder != null).toList()
      ..sort((a, b) => a.primaryOrder!.compareTo(b.primaryOrder!));
    final slots = primary.take(4).toList();
    if (slots.isEmpty) slots.addAll(items.take(4));
    final inSlots = slots.any((d) => d.id == currentId);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final d in slots)
                Expanded(
                  child: _BottomItem(
                    icon: d.id == currentId ? d.activeIcon : d.icon,
                    label: d.label,
                    color: d.accent,
                    active: d.id == currentId,
                    onTap: () => onSelect(d.id),
                  ),
                ),
              Expanded(
                child: _BottomItem(
                  icon: Icons.apps_rounded,
                  label: 'Yana',
                  color: AppColors.primary,
                  active: !inSlots,
                  onTap: onMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  const _BottomItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? color : AppColors.textFaint,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? color : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// «Yana» — barcha bo'limlar (telefon)
// ============================================================

class _NavSheet extends StatefulWidget {
  final List<AdminDestination> items;
  final String currentId;
  final VoidCallback onLogout;
  final bool hiddenShown;
  final bool canUnlock;
  final VoidCallback onToggleHidden;

  const _NavSheet({
    required this.items,
    required this.currentId,
    required this.onLogout,
    required this.hiddenShown,
    required this.canUnlock,
    required this.onToggleHidden,
  });

  @override
  State<_NavSheet> createState() => _NavSheetState();
}

class _NavSheetState extends State<_NavSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final matched = widget.items
        .where((d) => d.matches(_query))
        .toList(growable: false);
    final groups = <String, List<AdminDestination>>{};
    for (final d in matched) {
      groups.putIfAbsent(d.group, () => []).add(d);
    }
    final ordered = [
      ...AdminGroups.order.where(groups.containsKey),
      ...groups.keys.where((g) => !AdminGroups.order.contains(g)),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bo‘limlar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceAlt,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AdminSearchField(
                hint: 'Bo‘lim nomi bo‘yicha qidirish…',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: matched.isEmpty
                  ? const Center(
                      child: Text(
                        'Bunday bo‘lim topilmadi',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      children: [
                        for (final g in ordered) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                            child: Text(
                              g.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textFaint,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ),
                          for (final d in groups[g]!)
                            _SheetTile(
                              dest: d,
                              active: d.id == widget.currentId,
                              onTap: () => Navigator.pop(context, d.id),
                            ),
                        ],
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Server holati — 5 soniya bosib turilsa texnik
                    // bo'limlar ochiladi (panel yopilib, ro'yxat yangilanadi).
                    _NavStatus(
                      unlocked: widget.hiddenShown,
                      onHold: widget.canUnlock
                          ? () {
                              Navigator.pop(context);
                              widget.onToggleHidden();
                            }
                          : null,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onLogout();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(
                            color: AppColors.danger.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 19),
                        label: const Text(
                          'Tizimdan chiqish',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final AdminDestination dest;
  final bool active;
  final VoidCallback onTap;
  const _SheetTile({
    required this.dest,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: active ? dest.accent : AppColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: dest.accent.withValues(alpha: active ? 1 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    active ? dest.activeIcon : dest.icon,
                    color: active ? Colors.white : dest.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dest.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dest.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active)
                  Icon(Icons.check_circle_rounded, size: 20, color: dest.accent)
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textGhost,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Ctrl+K — bo'lim qidirish (planshet / desktop)
// ============================================================

class _CommandPalette extends StatefulWidget {
  final List<AdminDestination> items;
  final String currentId;
  const _CommandPalette({required this.items, required this.currentId});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String _query = '';
  int _cursor = 0;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<AdminDestination> get _matched =>
      widget.items.where((d) => d.matches(_query)).toList(growable: false);

  void _submit() {
    final list = _matched;
    if (list.isEmpty) return;
    Navigator.pop(context, list[_cursor.clamp(0, list.length - 1)].id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final list = _matched;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _cursor = (_cursor + 1) % (list.isEmpty ? 1 : list.length),
      );
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _cursor =
            (_cursor - 1 + (list.isEmpty ? 1 : list.length)) %
            (list.isEmpty ? 1 : list.length),
      );
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final list = _matched;
    if (_cursor >= list.length) _cursor = 0;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 90, left: 24, right: 24),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Focus(
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: TextField(
                  autofocus: true,
                  focusNode: _focus,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _cursor = 0;
                  }),
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Bo‘lim nomi… (↑↓ tanlash, Enter — ochish)',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Bunday bo‘lim yo‘q',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final d = list[i];
                          final hovered = i == _cursor;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: hovered
                                  ? d.accent.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                onTap: () => Navigator.pop(context, d.id),
                                onHover: (v) {
                                  if (v) setState(() => _cursor = i);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: d.accent.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.sm,
                                          ),
                                        ),
                                        child: Icon(
                                          d.icon,
                                          size: 18,
                                          color: d.accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              d.label,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              d.hint,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (d.id == widget.currentId)
                                        const Text(
                                          'ochiq',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textFaint,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
