import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'app_theme.dart';
import '../utils/business_day.dart';

/// Cross-platform image picker.
/// - iOS/Android: image_picker (gallery/camera)
/// - macOS/Windows/Linux: file_selector
Future<String?> pickImagePath({
  ImageSource source = ImageSource.gallery,
  double? maxWidth,
  int imageQuality = 80,
}) async {
  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  if (isMobile) {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: maxWidth ?? 800,
      imageQuality: imageQuality,
    );
    return picked?.path;
  }
  const typeGroup = XTypeGroup(
    label: 'images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'],
  );
  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  return file?.path;
}

// ============================================================
// Status badge
// ============================================================

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: color),
            const SizedBox(width: 4),
          ],
          // Uzun yorliq (masalan «Super admin») tor ekranda qatorni
          // yorib chiqmasin — qisqartiriladi.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Empty state
// ============================================================

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textFaint;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: c),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Icon avatar
// ============================================================

class IconAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

// ============================================================
// KCard — shared card container with subtle border
// ============================================================

class KCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const KCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    this.radius = AppRadius.lg,
    this.shadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: shadow,
      ),
      child: child,
    );
    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: inner,
      ),
    );
  }
}

// ============================================================
// KMaxWidth — planshetda kontentni markazga, o'qishga qulay kenglikda
// ============================================================
//
// Telefonda hech narsani o'zgartirmaydi (`readableWidth` = infinity),
// planshetda esa ro'yxat 1024pt ga cho'zilib ketmaydi.

class KMaxWidth extends StatelessWidget {
  final Widget child;
  final double? maxWidth;

  const KMaxWidth({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final w = maxWidth ?? context.readableWidth;
    if (w == double.infinity) return child;
    return Align(
      alignment: Alignment.topCenter,
      // heightFactor'siz Align bo'sh (loose) balandlikda BUTUN joyni oladi —
      // bottomNavigationBar ichida bu panel ekranni to'liq qoplab, body'ga
      // 0px qoldirardi (kirim ekranidagi «ro'yxat ko'rinmayapti» xatosi).
      // 1.0 = balandlik bolaga teng; ListView/Center baribir o'zi cho'ziladi.
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w),
        child: child,
      ),
    );
  }
}

// ============================================================
// KStepper — «−  3  +» miqdor boshqaruvi
// ============================================================
//
// NEGA KERAK: savatda miqdorni kamaytirish uchun butun qatorni bosish
// kerak edi — bu ko'rinmas va xavfli (tasodifiy tegish mahsulotni
// kamaytirardi). Endi aniq tugmalar bor.

class KStepper extends StatefulWidget {
  final int value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final double height;

  const KStepper({
    super.key,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.height = 34,
  });

  @override
  State<KStepper> createState() => _KStepperState();
}

class _KStepperState extends State<KStepper> {
  Timer? _timer;

  /// Uzoq bosib turilganda takrorlash — 10 ta kosa qo'shish uchun
  /// 10 marta bosish shart emas.
  void _startRepeat(VoidCallback action) {
    action();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) => action());
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(
            icon: widget.value <= 1
                ? Icons.delete_outline_rounded
                : Icons.remove_rounded,
            color: AppColors.danger,
            action: widget.onDecrement,
            size: h,
          ),
          Container(
            constraints: BoxConstraints(minWidth: h * 0.9),
            alignment: Alignment.center,
            child: Text(
              '${widget.value}',
              style: TextStyle(
                fontSize: h * 0.42,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
          _btn(
            icon: Icons.add_rounded,
            color: AppColors.success,
            action: widget.onIncrement,
            size: h,
          ),
        ],
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    required Color color,
    required VoidCallback action,
    required double size,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action,
      onLongPressStart: (_) => _startRepeat(action),
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.48, color: color),
      ),
    );
  }
}

// ============================================================
// KSection — labeled section with optional trailing
// ============================================================

class KSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const KSection({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.trailing,
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor ?? AppColors.textMuted),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

// ============================================================
// KChip — clickable pill chip (selected / unselected)
// ============================================================

class KChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final int? badge;

  /// Planshetda kattaroq — 13px yozuv 13 dyuymli ekranda mayda ko'rinadi
  final bool big;

  const KChip({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    this.accent = AppColors.primary,
    required this.onTap,
    this.badge,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.text;
    final bg = selected ? accent : AppColors.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: AppDuration.normal,
          padding: EdgeInsets.symmetric(
              horizontal: big ? 18 : 14, vertical: big ? 11 : 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? accent : AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: big ? 18 : 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: big ? 15 : 13,
                  color: fg,
                ),
              ),
              if (badge != null && badge! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// KStat — small stat tile (label + value)
// ============================================================

class KStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;

  const KStat({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              letterSpacing: -0.3,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// KKeyValueRow — label : value row
// ============================================================

class KKeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool divider;

  const KKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: divider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// KMetaChip — small info chip with icon
// ============================================================

class KMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const KMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Cupertino date picker bottom sheet
// ============================================================

Future<DateTime?> pickDateCupertino(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
  String title = 'Sana tanlash',
  // Sanadan tashqari BOSHLANISH VAQTI ham tanlanadi.
  //
  // Tarix ekranlarida kun 02:00 dan boshlanadi (ish kuni chegarasi).
  // Shu soatni almashtirish uchun oynaga soat:daqiqa g'ildiragi qo'shiladi.
  // O'chirilgan holda (defolt) oyna avvalgidek — faqat kun g'ildiraklari.
  bool withTime = false,
}) async {
  DateTime selected = initial;
  int hour = initial.hour;
  int minute = initial.minute;

  DateTime result() => withTime
      ? DateTime(selected.year, selected.month, selected.day, hour, minute)
      : selected;

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      // Kichik ekranda (telefon) ikkita g'ildirak sig'ishi uchun balandlik
      // kamaytiriladi — aks holda pastki oyna ekrandan chiqib ketadi.
      final screenH = MediaQuery.of(ctx).size.height;
      final compact = withTime && screenH < 640;
      final dateH = withTime ? (compact ? 150.0 : 190.0) : 240.0;
      final timeH = compact ? 120.0 : 150.0;

      const wheelTheme = CupertinoThemeData(
        brightness: Brightness.light,
        textTheme: CupertinoTextThemeData(
          dateTimePickerTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      );

      return Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Bekor',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      onPressed: () => Navigator.pop(ctx, result()),
                      child: const Text(
                        'Tayyor',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: dateH,
                child: CupertinoTheme(
                  data: wheelTheme,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: initial,
                    minimumDate: minimum,
                    maximumDate: maximum,
                    onDateTimeChanged: (d) => selected = d,
                  ),
                ),
              ),
              if (withTime) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      const Text(
                        'Boshlanish vaqti',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'defolt ${kBusinessDayStartHour.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: timeH,
                  child: CupertinoTheme(
                    data: wheelTheme,
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: true,
                      initialDateTime: initial,
                      onDateTimeChanged: (t) {
                        hour = t.hour;
                        minute = t.minute;
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

// ============================================================
// Xatoni odam tushunadigan matnga aylantirish
// ============================================================
//
// NEGA KERAK: bir qancha joyda xato `Text('$e')` bo'lib ekranga
// chiqardi. Kassir chek yuborganda qizil oynada shunday matn ko'rardi:
// «DioException [bad response]: This exception was thrown because the
// response has a status code of 404 and RequestOptions.validateStatus
// was configured to throw for this status code...» — ya'ni bir ekran
// inglizcha texnik matn, hech qanday ko'rsatmasiz.

String friendlyError(Object e, {String fallback = 'Xatolik yuz berdi'}) {
  if (e is DioException) {
    // Server o'zi tushuntirgan bo'lsa — o'shani ko'rsatamiz
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'] ?? data['error'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
    }
    final code = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server javob bermadi — qayta urining';
      case DioExceptionType.connectionError:
        return 'Serverga ulanib bo\'lmadi — tarmoqni tekshiring';
      case DioExceptionType.cancel:
        return 'So\'rov bekor qilindi';
      default:
        break;
    }
    if (code == 401 || code == 403) return 'Bu amalga ruxsatingiz yo\'q';
    if (code == 404) return 'Topilmadi — ma\'lumot eskirgan bo\'lishi mumkin';
    if (code == 409) return 'Bu amal allaqachon bajarilgan';
    if (code != null && code >= 500) return 'Server xatosi ($code)';
    if (code != null) return '$fallback ($code)';
    return fallback;
  }
  if (e is FormatException) return 'Server noto\'g\'ri javob qaytardi';
  return fallback;
}

// ============================================================
// Menyu nomi — POS interfeysida RUS tilida
// ============================================================

/// Mahsulot/kategoriya nomini POS'da ko'rsatish: asosiy til RUSCHA,
/// ruscha bo'sh bo'lsa o'zbekcha, keyin turkchaga o'tadi. `name` ham
/// `{uz,ru,tr}` map, ham oddiy satr bo'lishi mumkin (eski snapshotlar).
String menuName(dynamic name, {String fallback = ''}) {
  if (name is Map) {
    for (final k in const ['ru', 'uz', 'tr']) {
      final v = name[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return fallback;
  }
  final s = (name ?? '').toString();
  return s.isEmpty ? fallback : s;
}

// ============================================================
// Money formatter
// ============================================================

String formatMoney(dynamic v, {String suffix = ''}) {
  if (v == null) return '0$suffix';
  final n = v is int ? v : (v is num ? v.toInt() : 0);
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}${buf.toString()}$suffix';
}

// ============================================================
// Ingredient miqdorini o'qishga qulay ko'rinishda chiqarish
// gr/ml — 1000 dan katta bo'lsa kg/l ekvivalenti qavsda
// Masalan: "7 778 gr (7.78 kg)", "500 ml", "12 dona"
// ============================================================

String formatQty(dynamic v, String unit) {
  final n = v is int ? v : (v is num ? v.toInt() : 0);
  final base = '${formatMoney(n)} $unit';
  if ((unit == 'gr' || unit == 'ml') && n.abs() >= 1000) {
    final big = n / 1000.0;
    final bigUnit = unit == 'gr' ? 'kg' : 'l';
    String s = big.toStringAsFixed(2);
    if (s.endsWith('.00')) {
      s = big.toStringAsFixed(0);
    } else if (s.endsWith('0')) {
      s = big.toStringAsFixed(1);
    }
    return '$base ($s $bigUnit)';
  }
  return base;
}

// Ingredient birligi uchun narx yorlig'i: gr→kg, ml→l
String unitPriceLabel(String unit) {
  switch (unit) {
    case 'gr':
      return 'so\'m/kg';
    case 'ml':
      return 'so\'m/l';
    case 'm':
      return 'so\'m/m';
    default:
      return 'so\'m/dona';
  }
}

/// Raqamli maydonni bo'sh joy va ajratgichlarga chidamli o'qish.
///
/// NEGA KERAK: ilova summalarni "150 000" ko'rinishida ko'rsatadi, shuning
/// uchun foydalanuvchi ham shunday yozadi. `int.tryParse` esa bunda `null`
/// qaytaradi va u ko'p joyda `?? 0` bilan JIMGINA nolga aylanardi:
/// minimal qoldiq 0 bo'lib "kam qoldi" ogohlantirishi butunlay o'chib
/// ketardi, promo minimal summasi 0 bo'lib chegirma har buyurtmaga
/// tushardi, maksimal chegirma esa cheksiz bo'lib qolardi.
int? parseIntField(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(RegExp(r"[\s\u00A0']"), '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) return null;
  return int.tryParse(cleaned);
}

/// Summa maydonlari uchun: yozilayotganda 3 xonadan keyin probel qo'yadi
/// ("200000" \u2192 "200 000") va raqamdan boshqa belgini o'tkazmaydi.
///
/// Faqat butun sonli (so'm) maydonlarga ulanadi \u2014 kasrli (0.5 kg kabi)
/// maydonlarga ulansa nuqtani yeb yuboradi. O'qish tomoni [parseIntField]
/// bo'lishi shart: oddiy `int.tryParse` probel ko'rsa null qaytaradi.
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();

    // Kursordan oldin nechta RAQAM turgani formatlashdan keyin ham saqlanadi
    // (probellar soni o'zgarsa ham kursor sakramaydi).
    final sel = newValue.selection.baseOffset < 0
        ? newValue.text.length
        : newValue.selection.baseOffset.clamp(0, newValue.text.length);
    var digitsBeforeCursor = 0;
    for (var i = 0; i < sel; i++) {
      final c = newValue.text.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) digitsBeforeCursor++;
    }

    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();

    var offset = 0, seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCursor) {
      if (formatted[offset] != ' ') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
