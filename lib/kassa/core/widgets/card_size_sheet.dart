import 'package:flutter/material.dart';
import '../services/ui_prefs.dart';
import '../theme/app_theme.dart';

/// Stol va menyu kartalarining o'lchamini sozlash oynasi.
///
/// Slayder surilgan zahoti orqadagi ekranga darhol qo'llanadi (jonli
/// ko'rinadi) va qurilmada saqlanadi — ilova qayta ochilganda ham qoladi.
Future<void> showCardSizeSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
    ),
    builder: (ctx) => const _CardSizeSheet(),
  );
}

class _CardSizeSheet extends StatefulWidget {
  const _CardSizeSheet();

  @override
  State<_CardSizeSheet> createState() => _CardSizeSheetState();
}

class _CardSizeSheetState extends State<_CardSizeSheet> {
  @override
  Widget build(BuildContext context) {
    final prefs = UiPrefs();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(context.gutter, 10, context.gutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Karta o\'lchamlari',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    prefs.setTableScale(1.0);
                    prefs.setMenuScale(1.0);
                    setState(() {});
                  },
                  child: const Text('Standart'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _ScaleRow(
              icon: Icons.table_restaurant_rounded,
              label: 'Stol kartalari',
              value: prefs.tableScale.value,
              onChanged: (v) {
                prefs.setTableScale(v);
                setState(() {});
              },
            ),
            _ScaleRow(
              icon: Icons.restaurant_menu_rounded,
              label: 'Menyu kartalari',
              value: prefs.menuScale.value,
              onChanged: (v) {
                prefs.setMenuScale(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Faqat shu qurilmada saqlanadi',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ScaleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: UiPrefs.minScale,
          max: UiPrefs.maxScale,
          divisions:
              ((UiPrefs.maxScale - UiPrefs.minScale) / 0.1).round(),
          label: '${(value * 100).round()}%',
          onChanged: onChanged,
        ),
      ],
    );
  }
}
