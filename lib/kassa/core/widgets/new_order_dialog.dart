import 'package:flutter/material.dart';

import '../services/new_order_alert_service.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// Serverdan yangi buyurtma kelganda butun ekranni egallaydigan
/// ogohlantirish — mehmon chaqirig'i (StaffCallDialog) bilan bir uslubda,
/// lekin buyurtma TARKIBI bilan: kassir chekni ochmasdan nima kelganini
/// ko'radi. O'zi yo'qolmaydi — faqat «Ko'rdim» bosilganda ketadi.
class NewOrderDialog extends StatefulWidget {
  const NewOrderDialog({super.key});

  @override
  State<NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<NewOrderDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    NewOrderAlertService().onDialogInit();
  }

  @override
  void dispose() {
    NewOrderAlertService().onDialogDispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<IncomingOrder>>(
      valueListenable: NewOrderAlertService().pending,
      builder: (context, orders, _) {
        if (orders.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context);
            if (route != null && route.isCurrent) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }
        return _body(context, orders);
      },
    );
  }

  Widget _body(BuildContext context, List<IncomingOrder> orders) {
    final order = orders.first;
    final rest = orders.skip(1).toList();
    final color = order.color;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.all(context.gutter),
        backgroundColor: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context, order, color),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.s(20),
                    context.s(18),
                    context.s(20),
                    context.s(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _bigLabel(context, order, color),
                      SizedBox(height: context.s(6)),
                      Text(
                        '№ ${order.number}  ·  ${_clock(order.at)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: context.s(15),
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (order.customerName.isNotEmpty ||
                          order.phone.isNotEmpty) ...[
                        SizedBox(height: context.s(10)),
                        _customer(context, order),
                      ],
                      SizedBox(height: context.s(16)),
                      _items(context, order),
                      if (order.note.isNotEmpty) ...[
                        SizedBox(height: context.s(12)),
                        _note(context, order),
                      ],
                      if (rest.isNotEmpty) ...[
                        SizedBox(height: context.s(14)),
                        _queue(context, rest),
                      ],
                      SizedBox(height: context.s(20)),
                      _closeButton(context, order, color, rest.length),
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

  Widget _header(BuildContext context, IncomingOrder order, Color color) {
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(
        horizontal: context.s(20),
        vertical: context.s(18),
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.08).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              padding: EdgeInsets.all(context.s(12)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(order.icon, size: context.s(32), color: Colors.white),
            ),
          ),
          SizedBox(width: context.s(14)),
          Expanded(
            child: Text(
              order.title,
              style: TextStyle(
                fontSize: context.s(19),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Manba (SABOY / DOSTAFKA / YANDEX / stol nomi) — eng katta yozuv.
  Widget _bigLabel(BuildContext context, IncomingOrder order, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        order.bigLabel,
        maxLines: 1,
        style: TextStyle(
          fontSize: context.s(56),
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -1,
          color: color,
        ),
      ),
    );
  }

  Widget _customer(BuildContext context, IncomingOrder order) {
    final parts = <String>[
      if (order.customerName.isNotEmpty) order.customerName,
      if (order.phone.isNotEmpty) order.phone,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.person_rounded,
            size: context.s(18), color: AppColors.textMuted),
        SizedBox(width: context.s(6)),
        Flexible(
          child: Text(
            parts.join('  ·  '),
            style: TextStyle(
              fontSize: context.s(16),
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    );
  }

  /// Buyurtma tarkibi: nomi × soni — summasi, oxirida JAMI.
  Widget _items(BuildContext context, IncomingOrder order) {
    return Container(
      padding: EdgeInsets.all(context.s(14)),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'BUYURTMA · ${order.itemCount} ta',
            style: TextStyle(
              fontSize: context.s(12),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: AppColors.textFaint,
            ),
          ),
          SizedBox(height: context.s(8)),
          if (order.lines.isEmpty)
            Text(
              'Tarkib ko\'rsatilmadi — chekni oching',
              style: TextStyle(
                fontSize: context.s(15),
                color: AppColors.textMuted,
              ),
            ),
          for (final l in order.lines)
            Padding(
              padding: EdgeInsets.symmetric(vertical: context.s(4)),
              child: Row(
                children: [
                  Container(
                    width: context.s(40),
                    padding: EdgeInsets.symmetric(vertical: context.s(3)),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '×${l.qty}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: context.s(15),
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  SizedBox(width: context.s(10)),
                  Expanded(
                    child: Text(
                      l.name,
                      style: TextStyle(
                        fontSize: context.s(17),
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  SizedBox(width: context.s(10)),
                  Text(
                    formatMoney(l.total),
                    style: TextStyle(
                      fontSize: context.s(15),
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          Divider(height: context.s(18), color: AppColors.border),
          Row(
            children: [
              Text(
                'JAMI',
                style: TextStyle(
                  fontSize: context.s(14),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                formatMoney(order.total, suffix: ' so\'m'),
                style: TextStyle(
                  fontSize: context.s(22),
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, IncomingOrder order) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.s(12)),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warningSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_rounded,
              size: context.s(18), color: AppColors.warning),
          SizedBox(width: context.s(8)),
          Expanded(
            child: Text(
              order.note,
              style: TextStyle(
                fontSize: context.s(15),
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bir vaqtda bir nechta buyurtma kelsa — qolganlari shu yerda.
  Widget _queue(BuildContext context, List<IncomingOrder> rest) {
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
            'Navbatda yana ${rest.length} ta buyurtma',
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
              for (final o in rest)
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
                      Icon(o.icon, size: context.s(16), color: o.color),
                      SizedBox(width: context.s(6)),
                      Text(
                        '${o.bigLabel} · ${formatMoney(o.total)}',
                        style: TextStyle(
                          fontSize: context.s(14),
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
    IncomingOrder order,
    Color color,
    int restCount,
  ) {
    return SizedBox(
      width: double.infinity,
      height: context.s(64),
      child: FilledButton.icon(
        onPressed: () => NewOrderAlertService().dismiss(order),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        icon: Icon(Icons.check_rounded, size: context.s(26)),
        label: Text(
          restCount > 0 ? 'Ko\'rdim, keyingisi' : 'Ko\'rdim',
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
    return '$h:$m';
  }
}
