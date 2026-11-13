import 'package:flutter/material.dart';

import '../services/staff_call_service.dart';
import '../theme/app_theme.dart';

/// Mehmon chaqirganda butun ekranni egallaydigan katta ogohlantirish.
///
/// Ataylab shunday: zalda kassa ekraniga yugurib qaramaydi, shuning uchun
/// stol raqami ekranning yarmini egallaydi va o'zi yo'qolmaydi — faqat
/// "Yopish" bosilganda ketadi.
class StaffCallDialog extends StatefulWidget {
  const StaffCallDialog({super.key});

  @override
  State<StaffCallDialog> createState() => _StaffCallDialogState();
}

class _StaffCallDialogState extends State<StaffCallDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    StaffCallService().onDialogInit();
  }

  @override
  void dispose() {
    StaffCallService().onDialogDispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<StaffCall>>(
      valueListenable: StaffCallService().pending,
      builder: (context, calls, _) {
        if (calls.isEmpty) {
          // Hamma chaqiruv yopildi — dialogni o'zimiz olib tashlaymiz.
          // `isCurrent` tekshiruvi: ustimizga boshqa oyna ochilgan bo'lsa
          // uni tortib yubormaslik uchun.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context);
            if (route != null && route.isCurrent) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        return _body(context, calls);
      },
    );
  }

  Widget _body(BuildContext context, List<StaffCall> calls) {
    final call = calls.first;
    final rest = calls.skip(1).toList();
    final color = call.kind == StaffCallKind.waiter
        ? AppColors.danger
        : AppColors.warning;

    return PopScope(
      // "Orqaga" tugmasi ham yopmaydi — chaqiruv tasodifan o'tkazib
      // yuborilmasin.
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.all(context.gutter),
        backgroundColor: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context, call, color),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.s(20),
                    context.s(24),
                    context.s(20),
                    context.s(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'STOL',
                        style: TextStyle(
                          fontSize: context.s(15),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 3,
                          color: AppColors.textFaint,
                        ),
                      ),
                      SizedBox(height: context.s(6)),
                      _tableLabel(context, call, color),
                      SizedBox(height: context.s(10)),
                      Text(
                        _clock(call.at),
                        style: TextStyle(
                          fontSize: context.s(16),
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (rest.isNotEmpty) ...[
                        SizedBox(height: context.s(18)),
                        _queue(context, rest),
                      ],
                      SizedBox(height: context.s(24)),
                      _closeButton(context, call, color, rest.length),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, StaffCall call, Color color) {
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(
        horizontal: context.s(20),
        vertical: context.s(22),
      ),
      child: Column(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1.1).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              padding: EdgeInsets.all(context.s(14)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(
                call.icon,
                size: context.s(40),
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: context.s(14)),
          Text(
            call.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: context.s(20),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Stol nomi — ekrandagi eng katta narsa. Uzun nom (masalan
  /// "TASHQARI-12") ham sig'ishi uchun `FittedBox` bilan kichraytiriladi.
  Widget _tableLabel(BuildContext context, StaffCall call, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        call.label,
        maxLines: 1,
        style: TextStyle(
          fontSize: context.s(76),
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -1,
          color: color,
        ),
      ),
    );
  }

  /// Bir vaqtda bir nechta stol chaqirsa — qolganlari shu yerda ko'rinadi,
  /// joriysi yopilgach navbat bilan chiqadi.
  Widget _queue(BuildContext context, List<StaffCall> rest) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.s(12)),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Navbatda yana ${rest.length} ta chaqiruv',
            style: TextStyle(
              fontSize: context.s(13),
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(height: context.s(8)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in rest)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.s(12),
                    vertical: context.s(7),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.icon,
                        size: context.s(16),
                        color: c.kind == StaffCallKind.waiter
                            ? AppColors.danger
                            : AppColors.warning,
                      ),
                      SizedBox(width: context.s(6)),
                      Text(
                        c.label,
                        style: TextStyle(
                          fontSize: context.s(15),
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _closeButton(
    BuildContext context,
    StaffCall call,
    Color color,
    int restCount,
  ) {
    return SizedBox(
      width: double.infinity,
      height: context.s(64),
      child: FilledButton.icon(
        onPressed: () => StaffCallService().dismiss(call),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        icon: Icon(Icons.check_rounded, size: context.s(26)),
        label: Text(
          restCount > 0 ? 'Yopish va keyingisi' : 'Yopish',
          style: TextStyle(
            fontSize: context.s(20),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _clock(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return 'Chaqirilgan vaqt: $h:$m';
  }
}
