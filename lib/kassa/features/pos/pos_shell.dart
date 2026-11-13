import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/wss_service.dart';
import '../../core/services/api_service.dart';
import '../../core/widgets/connection_indicator.dart';
import '../../core/widgets/card_size_sheet.dart';
import '../../core/widgets/tutorial_widgets.dart';
import 'tables/tables_screen.dart';
import 'order/orders_panel.dart';
import 'shift/shift_screen.dart';
import 'expenses/pos_expenses_screen.dart';
import 'cooking/cooking_screen.dart';
import '../admin/menu_management/products_screen.dart';
import '../admin/music/music_screen.dart';
import '../login/base_url_setup_screen.dart';

class PosShell extends StatefulWidget {
  final VoidCallback onLogout;
  final Map<String, dynamic> permissions;
  const PosShell(
      {super.key, required this.onLogout, this.permissions = const {}});

  @override
  State<PosShell> createState() => _PosShellState();
}

class _PosShellState extends State<PosShell> {
  int _index = 0;

  /// Ruxsat AMAL darajasida tekshiriladi.
  ///
  /// Ilgari faqat resurs kaliti borligi tekshirilardi. Ruxsatlar esa
  /// `{resurs: [amallar]}` ko'rinishida keladi — ya'ni faqat `read` bor
  /// xodimga ham to'liq yozuv oynasi ochilardi va u serverda 403 olardi.
  /// Masalan `{"orders":["read","create"]}` bo'lgan ofitsiantga "To'lov"
  /// tugmasi ko'rinar, bosgandan keyingina rad etilardi.
  bool _can(String resource, String action) {
    final actions = widget.permissions[resource];
    if (actions is List) return actions.contains(action);
    return false;
  }

  bool _has(String resource) {
    final actions = widget.permissions[resource];
    return actions is List && actions.isNotEmpty;
  }

  List<_TabItem> get _tabs {
    final tabs = <_TabItem>[];

    if (_can('orders', 'create') || _can('zones', 'read')) {
      tabs.add(_TabItem(
        Icons.table_restaurant_rounded,
        Icons.table_restaurant_outlined,
        'Stollar',
        const TablesScreen(),
      ));
    }
    if (_can('orders', 'read')) {
      tabs.add(_TabItem(
        Icons.receipt_long_rounded,
        Icons.receipt_long_outlined,
        'Buyurtma',
        const OrdersPanel(),
      ));
    }
    if (_can('shifts', 'read')) {
      tabs.add(_TabItem(
        Icons.access_time_filled_rounded,
        Icons.schedule_rounded,
        'Smena',
        const ShiftScreen(),
      ));
    }
    if (_has('products') || _has('categories')) {
      tabs.add(_TabItem(
        Icons.restaurant_menu_rounded,
        Icons.restaurant_menu_outlined,
        'Menyu',
        const ProductsScreen(),
      ));
    }
    if (_can('cooking', 'read')) {
      tabs.add(_TabItem(
        Icons.bakery_dining_rounded,
        Icons.bakery_dining_outlined,
        'Pishirish',
        const CookingScreen(),
      ));
    }
    if (_can('expenses', 'create') || _can('expenses', 'read')) {
      tabs.add(_TabItem(
        Icons.payments_rounded,
        Icons.payments_outlined,
        'Xarajat',
        const PosExpensesScreen(),
      ));
    }
    if (_can('music', 'update')) {
      tabs.add(_TabItem(
        Icons.music_note_rounded,
        Icons.music_note_outlined,
        'Musiqa',
        const MusicScreen(),
      ));
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.isEmpty) {
      return _buildNoAccess();
    }
    if (_index >= tabs.length) _index = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return AppBreakpoints.isPhone(constraints.maxWidth)
            ? _buildPhoneLayout(tabs)
            : _buildTabletLayout(tabs);
      },
    );
  }

  // ===== TELEFON: pastki navigatsiya, yon panel yo'q =====
  Widget _buildPhoneLayout(List<_TabItem> tabs) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _OfflineBanner(),
            Expanded(
              // Tab almashganda ekran qayta yaratiladi — doim yangi ma'lumot
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: tabs[_index].screen,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        tabs: tabs,
        selected: _index,
        onSelect: (i) => setState(() => _index = i),
        onLogout: widget.onLogout,
      ),
    );
  }

  // ===== PLANSHET / DESKTOP: yon panel =====
  Widget _buildTabletLayout(List<_TabItem> tabs) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const _OfflineBanner(),
            Expanded(
              child: Row(
                children: [
                  _SideRail(
                    tabs: tabs,
                    selected: _index,
                    onSelect: (i) => setState(() => _index = i),
                    onLogout: widget.onLogout,
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.xl),
                        bottomLeft: Radius.circular(AppRadius.xl),
                      ),
                      child: Container(
                        color: AppColors.bg,
                        // Tab almashganda ekran qayta yaratiladi — doim yangi ma'lumot
                        child: KeyedSubtree(
                          key: ValueKey(_index),
                          child: tabs[_index].screen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccess() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_person_rounded,
                    size: 44, color: AppColors.danger),
              ),
              const SizedBox(height: 20),
              const Text('Ruxsat yo\'q',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text)),
              const SizedBox(height: 8),
              const Text('Sizga hech qanday modul biriktirilmagan',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Chiqish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Offline banner (telefon) — faqat aloqa uzilganda ko'rinadi
// ============================================================

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ApiService().endpointStream,
      initialData: ApiService().isUsingCloud,
      builder: (context, endpointSnap) {
        final onCloud = endpointSnap.data ?? false;
        return StreamBuilder<bool>(
          stream: WssService().connectionStream,
          initialData: WssService().isConnected,
          builder: (context, snapshot) {
            final connected = snapshot.data ?? false;
            // Cloudda ishlayotganda kassir buni bilishi shart: bu yerdan
            // yuborilgan buyurtmaning oshxona cheki local server ko'tarilgach
            // chop etiladi — cloud restoran ichidagi printerga yeta olmaydi.
            if (connected && onCloud) {
              return _bar(
                bg: AppColors.warningSoft,
                fg: AppColors.warning,
                icon: Icons.cloud_done_rounded,
                text: 'ONLINE server — oshxona cheki local ulangach chiqadi',
              );
            }
            if (connected) return const SizedBox.shrink();
            return _bar(
              bg: AppColors.dangerSoft,
              fg: AppColors.danger,
              icon: Icons.cloud_off_rounded,
              text: 'Server bilan aloqa yo\'q — qayta ulanmoqda',
            );
          },
        );
      },
    );
  }

  Widget _bar({
    required Color bg,
    required Color fg,
    required IconData icon,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: bg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Bottom bar (telefon) — 4 ta tab + «Yana»
// ============================================================

class _BottomBar extends StatelessWidget {
  final List<_TabItem> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _BottomBar({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onLogout,
  });

  /// Panelda ko'rinadigan tab soni — qolgani «Yana» ichida
  static const _maxVisible = 4;

  @override
  Widget build(BuildContext context) {
    final visible = tabs.length <= _maxVisible ? tabs.length : _maxVisible;
    final overflowSelected = selected >= visible;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (int i = 0; i < visible; i++)
                Expanded(
                  child: _BottomBarItem(
                    icon: i == selected ? tabs[i].iconFilled : tabs[i].iconOutline,
                    label: tabs[i].label,
                    active: i == selected,
                    onTap: () => onSelect(i),
                  ),
                ),
              Expanded(
                child: _BottomBarItem(
                  // Yashirin tab tanlangan bo'lsa — «Yana» o'sha tabni ko'rsatadi
                  icon: overflowSelected
                      ? tabs[selected].iconFilled
                      : Icons.more_horiz_rounded,
                  label: overflowSelected ? tabs[selected].label : 'Yana',
                  active: overflowSelected,
                  onTap: () => _openMoreSheet(context, visible),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMoreSheet(BuildContext context, int visible) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: 8),
              for (int i = visible; i < tabs.length; i++)
                _SheetTile(
                  icon: i == selected ? tabs[i].iconFilled : tabs[i].iconOutline,
                  label: tabs[i].label,
                  active: i == selected,
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelect(i);
                  },
                ),
              if (tabs.length > visible)
                const Divider(height: 12, color: AppColors.borderSoft),
              const _SheetConnectionRow(),
              _SheetTile(
                icon: Icons.play_circle_outline_rounded,
                label: 'Video qo‘llanma',
                active: false,
                onTap: () {
                  Navigator.pop(ctx);
                  openTutorialsScreen(context);
                },
              ),
              _SheetTile(
                icon: Icons.aspect_ratio_rounded,
                label: 'Karta o\'lchamlari',
                active: false,
                onTap: () {
                  Navigator.pop(ctx);
                  showCardSizeSheet(context);
                },
              ),
              _SheetTile(
                icon: Icons.dns_rounded,
                label: 'Server manzili',
                active: false,
                onTap: () async {
                  Navigator.pop(ctx);
                  final changed = await showServerUrlSheet(context);
                  if (changed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Server manzili yangilandi'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
              ),
              _SheetTile(
                icon: Icons.logout_rounded,
                label: 'Chiqish',
                active: false,
                danger: true,
                onTap: () {
                  Navigator.pop(ctx);
                  onLogout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomBarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: AppDuration.normal,
            width: 46,
            height: 28,
            decoration: BoxDecoration(
              color: active ? AppColors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (active ? AppColors.primary : AppColors.text);
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SheetConnectionRow extends StatelessWidget {
  const _SheetConnectionRow();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: WssService().connectionStream,
      initialData: WssService().isConnected,
      builder: (context, snapshot) {
        final ok = snapshot.data ?? false;
        final c = ok ? AppColors.success : AppColors.danger;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                ok ? 'Serverga ulangan' : 'Server bilan aloqa yo\'q',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c,
                ),
              ),
              const SizedBox(width: 8),
              const EndpointBadge(),
              const Spacer(),
              Text(
                ApiService()
                    .baseUrl
                    .replaceAll('http://', '')
                    .replaceAll('https://', ''),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// Side rail (72px) — brand at top, tabs middle, hidden ⋯ menu at bottom
// ============================================================

class _SideRail extends StatelessWidget {
  final List<_TabItem> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _SideRail({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    // Planshetda panel kengroq: 72pt da 10px yozuv va 22px ikonka
    // 13 dyuymli ekranda mayda ko'rinardi — barmoq bilan urish ham
    // noqulay edi.
    final wide = context.isTabletUi;
    final railW = wide ? 92.0 : 72.0;
    final brand = wide ? 52.0 : 44.0;

    return Container(
      width: railW,
      decoration: const BoxDecoration(color: AppColors.surface),
      child: Column(
        children: [
          SizedBox(height: wide ? 18 : 14),
          // Brand badge
          Container(
            width: brand,
            height: brand,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.coloredGlow(AppColors.primary,
                  opacity: 0.32),
            ),
            child: Center(
              child: Text(
                'K',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: brand * 0.45,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SizedBox(height: wide ? 12 : 10),
          const _ConnectionDot(),
          SizedBox(height: wide ? 20 : 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: tabs.length,
              itemBuilder: (_, i) {
                final t = tabs[i];
                final active = i == selected;
                return Padding(
                  padding: EdgeInsets.only(bottom: wide ? 8 : 6),
                  child: _RailItem(
                    icon: active ? t.iconFilled : t.iconOutline,
                    label: t.label,
                    active: active,
                    wide: wide,
                    onTap: () => onSelect(i),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          // Hidden menu button — opens popup with logout / info
          _MoreMenuButton(onLogout: onLogout),
          SizedBox(height: wide ? 14 : 10),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool wide;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.wide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppDuration.normal,
          padding: EdgeInsets.symmetric(vertical: wide ? 11 : 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: wide ? 26 : 22),
              SizedBox(height: wide ? 5 : 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: wide ? 11.5 : 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenuButton extends StatelessWidget {
  final VoidCallback onLogout;
  const _MoreMenuButton({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      offset: const Offset(60, -10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      elevation: 8,
      padding: EdgeInsets.zero,
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _MenuHeader(),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'tutorials',
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.play_circle_outline_rounded,
                  size: 18, color: AppColors.textMuted),
              SizedBox(width: 10),
              Text(
                'Video qo‘llanma',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'sizes',
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.aspect_ratio_rounded,
                  size: 18, color: AppColors.textMuted),
              SizedBox(width: 10),
              Text(
                'Karta o\'lchamlari',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'server',
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.dns_rounded,
                  size: 18, color: AppColors.textMuted),
              SizedBox(width: 10),
              Text(
                'Server manzili',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'logout',
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.logout_rounded,
                  size: 18, color: AppColors.danger),
              SizedBox(width: 10),
              Text(
                'Chiqish',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (v) async {
        if (v == 'logout') {
          onLogout();
        } else if (v == 'tutorials') {
          openTutorialsScreen(context);
        } else if (v == 'sizes') {
          showCardSizeSheet(context);
        } else if (v == 'server') {
          final changed = await showServerUrlSheet(context);
          if (changed && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Server manzili yangilandi'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        }
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.more_horiz_rounded,
            size: 20, color: AppColors.textMuted),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = ApiService().baseUrl;
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Center(
                  child: Text(
                    'K',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'MONE KASSA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            base.replaceAll('http://', '').replaceAll('https://', ''),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          StreamBuilder<bool>(
            stream: WssService().connectionStream,
            initialData: WssService().isConnected,
            builder: (context, snapshot) {
              final ok = snapshot.data ?? false;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: ok ? AppColors.success : AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    ok ? 'Ulangan' : 'Uzilgan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: WssService().connectionStream,
      initialData: WssService().isConnected,
      builder: (context, snapshot) {
        final ok = snapshot.data ?? false;
        final c = ok ? AppColors.success : AppColors.danger;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            boxShadow: ok
                ? [
                    BoxShadow(
                      color: c.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _TabItem {
  final IconData iconFilled;
  final IconData iconOutline;
  final String label;
  final Widget screen;
  const _TabItem(this.iconFilled, this.iconOutline, this.label, this.screen);
}
