import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/business_day.dart';

/// Admin ro'yxatlaridagi BITTA qator.
///
/// Ilgari har ekran `Card` + `ListTile` ni o'zicha sozlardi: birida
/// `CircleAvatar`, boshqasida ikonka; balandligi turlicha; bosilganda
/// javob bermaydigan joylari bor edi. Bu qator hamma joyda bir xil:
/// chapda rangli belgi, o'rtada nom + izoh, o'ngda qiymat/holat va
/// «uch nuqta» menyusi. Butun qator bosiladi (48pt dan baland).
class AdminTile extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Chapdagi belgi — ikonka yoki bosh harf.
  final IconData? icon;
  final String? initials;
  final Color color;

  /// O'ngdagi asosiy qiymat (summa, soni…) va uning ostidagi izoh.
  final String? value;
  final String? valueHint;
  final Color? valueColor;

  /// O'ngdagi holat belgisi (masalan «Faol»/«Nofaol»).
  final Widget? badge;

  /// O'ngdagi ixtiyoriy widget (switch, tugma…). `value` bilan birga
  /// ishlatilmaydi.
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// «⋮» menyusi: {kalit: (nom, ikonka)} + tanlanganda chaqiriladi.
  final List<AdminMenuItem>? menu;
  final ValueChanged<String>? onMenuSelected;

  /// Qatorni ajratib ko'rsatish (masalan zaxira tugagan ingredient).
  final Color? highlight;

  const AdminTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.initials,
    this.color = AppColors.primary,
    this.value,
    this.valueHint,
    this.valueColor,
    this.badge,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.menu,
    this.onMenuSelected,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          _leading(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.25,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // O'ng tomondagi blok (holat belgisi + summa) qolgan joyni TO'LIQ
          // egallaydi va ichidagi qiymat o'ngga tiraladi — shunda «⋮» tugmasi
          // hamma qatorda bir xil joyda, kartaning o'ng chetida turadi
          // (ilgari qiymat uzunligiga qarab sakrardi). Tor telefonda belgi
          // qisqaradi, summa esa kichrayib sig'adi — qator yorilmaydi.
          if (badge != null || value != null)
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Flexible(child: badge!),
                  ],
                  if (value != null) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              value!,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: valueColor ?? AppColors.text,
                              ),
                            ),
                          ),
                          if (valueHint != null)
                            Text(
                              valueHint!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textFaint,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (menu != null && menu!.isNotEmpty) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  size: 20, color: AppColors.textFaint),
              tooltip: 'Amallar',
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              onSelected: (v) => onMenuSelected?.call(v),
              itemBuilder: (_) => [
                for (final m in menu!)
                  PopupMenuItem<String>(
                    value: m.value,
                    height: 44,
                    child: Row(
                      children: [
                        Icon(m.icon,
                            size: 18, color: m.color ?? AppColors.textMuted),
                        const SizedBox(width: 10),
                        Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: m.color ?? AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ] else if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textGhost),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: highlight ?? AppColors.border,
          width: highlight != null ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: content,
        ),
      ),
    );
  }

  Widget _leading() {
    if (initials != null) {
      return Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          initials!,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon ?? Icons.circle, color: color, size: 21),
    );
  }
}

class AdminMenuItem {
  final String value;
  final String label;
  final IconData icon;
  final Color? color;
  const AdminMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });
}

/// Sozlama ekranlaridagi oq blok: sarlavha + ichida qatorlar.
class AdminSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const AdminSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.trailing,
    this.padding,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 11),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, size: 17, color: c),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sarlavha ostidagi kichik statistika kartalari qatori.
///
/// Telefonda gorizontal aylantiriladi, planshetda bir qatorga teng
/// bo'linadi — ikkalasida ham raqamlar mayda bo'lib qolmaydi.
class AdminStatsRow extends StatelessWidget {
  final List<AdminStatData> items;
  const AdminStatsRow({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (context.isTabletUi || items.length <= 2) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _AdminStatCard(data: items[i])),
          ],
        ],
      );
    }
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => SizedBox(
          width: 150,
          child: _AdminStatCard(data: items[i]),
        ),
      ),
    );
  }
}

class AdminStatData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const AdminStatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _AdminStatCard extends StatelessWidget {
  final AdminStatData data;
  const _AdminStatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(data.icon, size: 18, color: data.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textFaint,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ro'yxat bo'sh bo'lganda — nima qilish kerakligini AYTADIGAN ekran.
class AdminEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;

  const AdminEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: c),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: c),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ro'yxat uchun tayyor `ListView` — bir xil bo'shliq va pastda FAB uchun joy.
class AdminList extends StatelessWidget {
  final List<Widget> children;
  final ScrollController? controller;
  final Widget? header;
  const AdminList({
    super.key,
    required this.children,
    this.controller,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.only(top: 14, bottom: 96),
      children: [
        ?header,
        ...children,
      ],
    );
  }
}

/// Bo'lim ichidagi kichik sarlavha (ro'yxat guruhlari uchun).
class AdminGroupLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AdminGroupLabel({super.key, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textFaint,
                letterSpacing: 0.9,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Sana tanlash qatori: «‹ 22-avgust, juma ›» + «Bugun».
///
/// Kunlik hisobotli ekranlarda (buyurtmalar, xarajatlar, moliya) bir xil
/// ishlaydi — oldin har biri o'zicha yasagan edi va ba'zisida ertangi
/// kunga o'tib ketish mumkin edi.
class AdminDateBar extends StatelessWidget {
  /// Tanlangan kun. [withTime] yoqilgan bo'lsa bu — kun BOSHLANISH VAQTI
  /// (defolt 02:00), aks holda oddiy sana (00:00).
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  /// Kelajakka o'tishga ruxsat (odatda yo'q).
  final bool allowFuture;

  /// Kun boshlanish SOATINI ham tanlash mumkinmi.
  ///
  /// Ish kuni doim 02:00 dan boshlanadi (`kBusinessDayStartHour`). Tarixda
  /// buni o'zgartirish kerak bo'ladi: masalan 10:00 tanlansa ro'yxat
  /// «10:00 → ertasi 10:00» oynasini ko'rsatadi. Defolt — 02:00, ya'ni
  /// avvalgi xatti-harakat.
  final bool withTime;

  const AdminDateBar({
    super.key,
    required this.date,
    required this.onChanged,
    this.allowFuture = false,
    this.withTime = false,
  });

  static const _months = [
    'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
    'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr',
  ];
  static const _weekdays = [
    'dushanba', 'seshanba', 'chorshanba', 'payshanba',
    'juma', 'shanba', 'yakshanba',
  ];

  static String label(DateTime d) {
    // "Bugun" — ish kuni (02:00 chegarasi). Kechasi 00:30 da ochilgan
    // ro'yxat KECHAGI sanani ko'rsatadi va u "Bugun" deb yoziladi:
    // kassir uchun bu hali o'sha kecha.
    final today = businessToday();
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Bugun, ${d.day}-${_months[d.month - 1]}';
    if (diff == 1) return 'Kecha, ${d.day}-${_months[d.month - 1]}';
    return '${d.day}-${_months[d.month - 1]}, ${_weekdays[d.weekday - 1]}';
  }

  /// Qatordagi kun — oyna BOSHLANGAN sana. Oyna 24 soat davom etadi, ya'ni
  /// «22-avgust 10:00» → 23-avgust 10:00 gacha, lekin nomi 22-avgust.
  DateTime get _day => DateTime(date.year, date.month, date.day);

  bool get _isToday => isBusinessToday(_day);

  /// Kun boshlanishi defoltdan (02:00) farq qilsa — qatorda ko'rinadi:
  /// «Bugun, 22-avgust · 10:00 dan».
  String get _text {
    final base = label(_day);
    if (!withTime) return base;
    if (date.hour == kBusinessDayStartHour && date.minute == 0) return base;
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$base · $hh:$mm dan';
  }

  @override
  Widget build(BuildContext context) {
    final canForward = allowFuture || !_isToday;
    return Row(
      children: [
        _arrow(
          icon: Icons.chevron_left_rounded,
          onTap: () => onChanged(date.subtract(const Duration(days: 1))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () async {
                final picked = await pickDateCupertino(
                  context,
                  initial: date,
                  withTime: withTime,
                  // Chegara — ish kunining oxiri: shu kunni tanlash mumkin,
                  // ertangisi yo'q.
                  maximum: allowFuture
                      ? null
                      : businessToday().add(const Duration(hours: 23, minutes: 59)),
                );
                if (picked != null) onChanged(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        _text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _arrow(
          icon: Icons.chevron_right_rounded,
          onTap: canForward
              ? () => onChanged(date.add(const Duration(days: 1)))
              : null,
        ),
        if (!_isToday) ...[
          const SizedBox(width: 8),
          Material(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onChanged(
                  withTime ? businessTodayStart() : businessToday()),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Text(
                  'Bugun',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _arrow({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? AppColors.textGhost : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
