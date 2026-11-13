import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Admin panelidagi BARCHA «qo'shish / tahrirlash» oynalari shu orqali
/// ochiladi.
///
/// NEGA: ilgari har biri qo'lda yig'ilgan `AlertDialog` edi — maydonlar
/// bir-biriga yopishgan, «O'chirish» tugmasi «Saqlash» ning yonida turardi
/// (tasodifan bosish oson), telefonda klaviatura maydonni bekitardi va
/// saqlash paytida tugma ikki marta bosilishi mumkin edi.
///
/// Endi: telefonda pastdan chiqadigan keng varaq, planshetda markazdagi
/// oyna; maydonlar orasida havo bor; «Saqlash» pastda kenglikni to'liq
/// egallaydi va bosilganda bloklanadi; «O'chirish» esa yuqori burchakdagi
/// alohida qizil tugma (tasdiq so'raydi).
Future<bool?> showAdminForm({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData icon = Icons.edit_rounded,
  Color color = AppColors.primary,
  required List<Widget> Function(BuildContext ctx, StateSetter refresh) fields,

  /// `true` qaytarsa oyna yopiladi. Xatoni o'zi ko'rsatadi.
  required Future<bool> Function() onSubmit,
  String submitLabel = 'Saqlash',
  Future<bool> Function()? onDelete,
  String deleteLabel = 'O‘chirish',
}) {
  final isPhone = context.isPhoneUi;
  final form = _AdminFormShell(
    title: title,
    subtitle: subtitle,
    icon: icon,
    color: color,
    fields: fields,
    onSubmit: onSubmit,
    submitLabel: submitLabel,
    onDelete: onDelete,
    deleteLabel: deleteLabel,
    isPhone: isPhone,
  );

  if (isPhone) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: form,
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: form,
      ),
    ),
  );
}

class _AdminFormShell extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> Function(BuildContext, StateSetter) fields;
  final Future<bool> Function() onSubmit;
  final String submitLabel;
  final Future<bool> Function()? onDelete;
  final String deleteLabel;
  final bool isPhone;

  const _AdminFormShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.fields,
    required this.onSubmit,
    required this.submitLabel,
    required this.onDelete,
    required this.deleteLabel,
    required this.isPhone,
  });

  @override
  State<_AdminFormShell> createState() => _AdminFormShellState();
}

class _AdminFormShellState extends State<_AdminFormShell> {
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.onSubmit();
      if (ok && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final ok = await confirmAction(
      context: context,
      title: widget.deleteLabel,
      message: '«${widget.title}» butunlay o‘chiriladi. Davom etamizmi?',
      confirmLabel: widget.deleteLabel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final done = await widget.onDelete!();
      if (done && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.isPhone
        ? const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl))
        : BorderRadius.circular(AppRadius.xl);

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (widget.isPhone ? 0.92 : 0.86),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isPhone)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.onDelete != null)
                  IconButton(
                    tooltip: widget.deleteLabel,
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      backgroundColor: AppColors.dangerSoft,
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Yopish',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.surfaceAlt,
                    foregroundColor: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.fields(context, setState),
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Bekor qilish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.color,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.submitLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Maydonlar
// ============================================================

/// Yorliqli matn maydoni — yorliq maydon USTIDA turadi (ichidagi
/// suzuvchi yorliq kiritish paytida o'qilmay qolardi).
class AdminField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final IconData? icon;
  final String? prefixText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> formatters;
  final int? maxLength;
  final int maxLines;
  final bool obscure;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const AdminField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.icon,
    this.prefixText,
    this.suffixText,
    this.keyboardType,
    this.formatters = const [],
    this.maxLength,
    this.maxLines = 1,
    this.obscure = false,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label, icon: icon),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            maxLength: maxLength,
            maxLines: maxLines,
            obscureText: obscure,
            autofocus: autofocus,
            enabled: enabled,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              // `prefixText` FAQAT fokusda ko'rinadi — «+998» kabi doimiy
              // prefiks ko'rinmay qolib, admin raqamni to'liq yozib
              // yuborardi. Shuning uchun alohida widget bo'lib turadi.
              prefixIcon: prefixText == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: Text(
                          prefixText!,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
              suffixText: suffixText,
              counterText: '',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            ),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Text(
                helper!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
              ),
            ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _FieldLabel(this.text, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Yorliqli tanlov (dropdown).
class AdminDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  const AdminDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label, icon: icon),
          DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            borderRadius: BorderRadius.circular(AppRadius.md),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            items: [
              for (final e in items.entries)
                DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

/// Tanlov tugmalari qatori (rol, tur, holat…) — dropdown'dan tez.
class AdminChoice<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final Map<T, Color>? colors;

  const AdminChoice({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in items.entries)
                _ChoicePill(
                  label: e.value,
                  selected: e.key == value,
                  color: colors?[e.key] ?? AppColors.primary,
                  onTap: () => onChanged(e.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Yoqish/o'chirish qatori.
class AdminSwitchRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final Color? color;

  const AdminSwitchRow({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: value ? c : AppColors.textFaint),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (hint != null)
                        Text(
                          hint!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged, activeThumbColor: c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Tasdiqlash va xabarlar
// ============================================================

Future<bool?> confirmAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Tasdiqlash',
  String cancelLabel = 'Bekor qilish',
  bool danger = false,
}) {
  final color = danger ? AppColors.danger : AppColors.primary;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
          color: color,
          size: 26,
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

void showOk(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

void showErr(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Server xatosidan foydalanuvchi tushunadigan xabar chiqarish.
String apiErrorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    final code = error.response?.statusCode;
    if (code == 403) return 'Bu amalga ruxsatingiz yo‘q';
    if (code == 401) return 'Sessiya tugadi — qayta kiring';
    if (code == 404) return 'Topilmadi';
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Serverga ulanib bo‘lmadi';
    }
  }
  final s = error.toString();
  final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(s);
  if (m != null) return m.group(1)!;
  if (s.contains('403')) return 'Bu amalga ruxsatingiz yo‘q';
  if (s.contains('401')) return 'Sessiya tugadi — qayta kiring';
  if (s.contains('SocketException') || s.contains('Connection')) {
    return 'Serverga ulanib bo‘lmadi';
  }
  return 'Amal bajarilmadi';
}
