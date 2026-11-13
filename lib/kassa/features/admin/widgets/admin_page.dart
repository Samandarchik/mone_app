import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tutorial_widgets.dart';
import '../admin_nav.dart';

/// Sahifaning asosiy amali — planshetda sarlavha yonidagi tugma,
/// telefonda pastdagi katta FAB bo'lib chiqadi.
class AdminAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  const AdminAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
  });
}

/// Sarlavha yonidagi ikkilamchi amal (yangilash, eksport, filtr...).
class AdminIconAction {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const AdminIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });
}

/// HAR BIR admin ekranining karkasi.
///
/// NEGA: ilgari har ekran o'zicha yasalardi — birida `Card`+`ListTile`,
/// boshqasida qo'lda yig'ilgan konteyner; sarlavha ba'zisida bor, ba'zisida
/// yo'q; yuklanish paytida butun ekran bo'shab, faqat aylanma chiqardi;
/// «qo'shish» tugmasi bir joyda FAB, boshqa joyda matn tugma edi. Endi
/// bularning hammasi shu yerda, bitta joyda hal qilinadi:
///
///  * sarlavha + izoh (nechta yozuv borligi ko'rinib turadi)
///  * qidiruv maydoni, filtr qatori, bo'limcha tugmalari (segment)
///  * asosiy amal — planshetda tugma, telefonda FAB
///  * yuklanish / xato / bo'sh holat — uchalasi bir xil ko'rinishda
///  * planshet-desktopda kontent o'qishga qulay kenglikda markazda turadi
class AdminPage extends StatelessWidget {
  /// Bo'sh qoldirilsa — ochiq bo'lim nomi olinadi.
  final String? title;
  final String? subtitle;

  /// Sarlavha oldidagi ikonka (bo'sh — bo'limniki).
  final IconData? icon;
  final Color? accent;

  /// Orqaga qaytish (ichki sahifa: masalan kategoriya ichi).
  final VoidCallback? onBack;

  final List<AdminIconAction> actions;
  final AdminAction? primaryAction;

  /// Qidiruv — `onSearchChanged` berilsa maydon ko'rinadi.
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final String searchHint;

  /// Sarlavha ostidagi qatorga qo'yiladigan ixtiyoriy widget (filtr chiplari,
  /// sana tanlagich, jami statistika...).
  final Widget? toolbar;

  /// Bo'limchalar (segment tugmalari).
  final List<String>? segments;
  final int segmentIndex;
  final ValueChanged<int>? onSegmentChanged;

  final Future<void> Function()? onRefresh;

  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  /// Kontent ekran chetiga tegib turmasin (standart: chetdan bo'shliq).
  final bool padded;

  /// Keng ekranda kontentni o'rtada, o'qishga qulay kenglikda ushlash.
  final bool constrained;

  /// Ekran pastida doim turadigan panel (masalan «hozir ijro etilmoqda»).
  final Widget? bottomBar;

  final Widget child;

  /// Video qo'llanma kaliti (sarlavha yonidagi «i»). Berilmasa — ochiq
  /// bo'lim id'si (admin panelida). POS'da ishlatilganda aniq beriladi.
  final String? helpKey;

  const AdminPage({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.onBack,
    this.actions = const [],
    this.primaryAction,
    this.onSearchChanged,
    this.searchController,
    this.searchHint = 'Qidirish…',
    this.toolbar,
    this.segments,
    this.segmentIndex = 0,
    this.onSegmentChanged,
    this.onRefresh,
    this.loading = false,
    this.error,
    this.onRetry,
    this.padded = true,
    this.constrained = true,
    this.bottomBar,
    this.helpKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scope = AdminScope.maybeOf(context);
    final dest = scope?.destination;
    final isPhone = context.isPhoneUi;
    // Klaviatura ochilganda FAB yozilayotgan maydonni to‘sib qo‘yadi
    // (bozorlikda «Miqdor»/«Narx» ustiga tushardi) — shu sababli
    // klaviatura chiqishi bilan tugma ham yashirinadi.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final color = accent ?? dest?.accent ?? AppColors.primary;
    final pageTitle = title ?? dest?.label ?? '';
    final pageIcon = icon ?? dest?.activeIcon ?? Icons.circle;

    Widget body;
    if (error != null) {
      body = AdminErrorView(message: error!, onRetry: onRetry);
    } else if (loading) {
      body = const AdminLoadingView();
    } else {
      body = child;
    }

    if (padded || constrained) {
      body = _ContentFrame(
        padded: padded,
        constrained: constrained,
        child: body,
      );
    }

    if (onRefresh != null && error == null && !loading) {
      body = RefreshIndicator(
        onRefresh: onRefresh!,
        color: color,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _AdminHeader(
            title: pageTitle,
            helpKey: helpKey ?? dest?.id,
            subtitle: subtitle,
            icon: pageIcon,
            color: color,
            onBack: onBack,
            actions: actions,
            primaryAction: primaryAction,
            onSearchChanged: onSearchChanged,
            searchController: searchController,
            searchHint: searchHint,
            toolbar: toolbar,
            segments: segments,
            segmentIndex: segmentIndex,
            onSegmentChanged: onSegmentChanged,
            isPhone: isPhone,
          ),
          Expanded(child: body),
          ?bottomBar,
        ],
      ),
      floatingActionButton: (isPhone && primaryAction != null && !keyboardOpen)
          ? FloatingActionButton.extended(
              heroTag: 'admin-fab-${dest?.id ?? pageTitle}',
              backgroundColor: primaryAction!.color ?? color,
              foregroundColor: Colors.white,
              onPressed: primaryAction!.onPressed,
              icon: Icon(primaryAction!.icon),
              label: Text(
                primaryAction!.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }
}

class _ContentFrame extends StatelessWidget {
  final bool padded;
  final bool constrained;
  final Widget child;
  const _ContentFrame({
    required this.padded,
    required this.constrained,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget c = child;
    if (padded) {
      c = Padding(
        padding: EdgeInsets.fromLTRB(context.gutter, 0, context.gutter, 0),
        child: c,
      );
    }
    if (constrained) {
      c = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.readableWidth),
          child: c,
        ),
      );
    }
    return c;
  }
}

// ============================================================
// Sarlavha bloki
// ============================================================

class _AdminHeader extends StatelessWidget {
  final String title;
  final String? helpKey;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onBack;
  final List<AdminIconAction> actions;
  final AdminAction? primaryAction;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final String searchHint;
  final Widget? toolbar;
  final List<String>? segments;
  final int segmentIndex;
  final ValueChanged<int>? onSegmentChanged;
  final bool isPhone;

  const _AdminHeader({
    required this.title,
    required this.helpKey,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onBack,
    required this.actions,
    required this.primaryAction,
    required this.onSearchChanged,
    required this.searchController,
    required this.searchHint,
    required this.toolbar,
    required this.segments,
    required this.segmentIndex,
    required this.onSegmentChanged,
    required this.isPhone,
  });

  @override
  Widget build(BuildContext context) {
    final gutter = context.gutter;
    final hasSearch = onSearchChanged != null;
    final showInlineSearch = hasSearch && !isPhone;

    final titleBlock = Row(
      children: [
        if (onBack != null) ...[
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Orqaga',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
        ] else ...[
          Container(
            width: isPhone ? 36 : 42,
            height: isPhone ? 36 : 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, color: color, size: isPhone ? 20 : 23),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isPhone ? 19 : 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (helpKey != null) ...[
                    const SizedBox(width: 8),
                    TutorialHelpButton(helpKey!, size: isPhone ? 24 : 28),
                  ],
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final actionButtons = <Widget>[
      // Telefonda yon panel yo'q — ulanish holati shu yerda ko'rinadi.
      if (isPhone) ...[
        const AdminStatusDot(),
        const SizedBox(width: 8),
      ],
      for (final a in actions) ...[
        _RoundIconButton(
          icon: a.icon,
          tooltip: a.tooltip,
          onPressed: a.onPressed,
          color: a.color,
        ),
        const SizedBox(width: 8),
      ],
      if (primaryAction != null && !isPhone)
        FilledButton.icon(
          onPressed: primaryAction!.onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: primaryAction!.color ?? color,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          icon: Icon(primaryAction!.icon, size: 19),
          label: Text(primaryAction!.label),
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, isPhone ? 10 : 14, gutter, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: titleBlock),
                  if (showInlineSearch) ...[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 260,
                      child: AdminSearchField(
                        controller: searchController,
                        hint: searchHint,
                        onChanged: onSearchChanged!,
                      ),
                    ),
                  ],
                  if (actionButtons.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Row(mainAxisSize: MainAxisSize.min, children: actionButtons),
                  ],
                ],
              ),
              if (hasSearch && isPhone) ...[
                const SizedBox(height: 10),
                AdminSearchField(
                  controller: searchController,
                  hint: searchHint,
                  onChanged: onSearchChanged!,
                ),
              ],
              if (segments != null && segments!.isNotEmpty) ...[
                const SizedBox(height: 12),
                AdminSegments(
                  items: segments!,
                  index: segmentIndex,
                  onChanged: onSegmentChanged ?? (_) {},
                  color: color,
                ),
              ],
              if (toolbar != null) ...[
                const SizedBox(height: 12),
                toolbar!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: onPressed == null ? AppColors.textGhost : c),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Qidiruv maydoni
// ============================================================

class AdminSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const AdminSearchField({
    super.key,
    this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  late TextEditingController _c;
  bool _own = false;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ?? TextEditingController();
    _own = widget.controller == null;
  }

  @override
  void dispose() {
    if (_own) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: widget.hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textFaint),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textMuted,
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

// ============================================================
// Segment (bo'limcha) tugmalari — eski ko'k `TabBar` o'rniga
// ============================================================

class AdminSegments extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  final Color color;

  const AdminSegments({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++)
              GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppDuration.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: i == index ? AppShadows.xs : null,
                  ),
                  child: Text(
                    items[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                      color: i == index ? color : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Holatlar: yuklanmoqda / xato / bo'sh
// ============================================================

class AdminLoadingView extends StatelessWidget {
  const AdminLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [for (var i = 0; i < 6; i++) const _SkeletonRow()],
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow();
  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.9).animate(_c),
      child: Container(
        height: 68,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(height: 11, width: 160, color: AppColors.surfaceAlt),
                  const SizedBox(height: 8),
                  Container(height: 9, width: 90, color: AppColors.surfaceAlt),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const AdminErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 34, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ma’lumot olinmadi',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Qayta urinish'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ============================================================
// Ulanish holati (telefon sarlavhasida)
// ============================================================

/// Kichik nuqta: yashil — local server bilan jonli aloqa, sariq — bulut
/// orqali ishlayapti (oshxona printeri yetib bormasligi mumkin), qizil —
/// aloqa yo'q. Bosilganda izohi chiqadi.
class AdminStatusDot extends StatelessWidget {
  const AdminStatusDot({super.key});

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
            final color = !online
                ? AppColors.danger
                : (onCloud ? AppColors.warning : AppColors.success);
            final text = !online
                ? 'Aloqa yo‘q'
                : (onCloud ? 'Bulut serveri' : 'Local server');
            return Tooltip(
              message: text,
              child: GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(text),
                    backgroundColor: color,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
