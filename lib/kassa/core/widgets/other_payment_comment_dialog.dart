import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// «Boshqa» usulida to'lov izohi — nima evaziga to'langani (masalan,
/// «egasining mehmoni», «perechislenie»). Izoh SHART: summa bilan birga
/// admin guruhiga ketadi. Bekor qilinsa `null` qaytadi.
Future<String?> askOtherPaymentComment(
  BuildContext context, {
  required int amount,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OtherPaymentCommentDialog(amount: amount),
  );
}

class _OtherPaymentCommentDialog extends StatefulWidget {
  final int amount;
  const _OtherPaymentCommentDialog({required this.amount});

  @override
  State<_OtherPaymentCommentDialog> createState() =>
      _OtherPaymentCommentDialogState();
}

class _OtherPaymentCommentDialogState
    extends State<_OtherPaymentCommentDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canSave => _ctrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.more_horiz_rounded, size: 20, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Boshqa to\'lov'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatMoney(widget.amount, suffix: ' so\'m'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Izoh yozing — summa bilan birga guruhga yuboriladi',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Masalan: egasining mehmoni',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.pop(context, _ctrl.text.trim())
              : null,
          child: const Text('To\'lash'),
        ),
      ],
    );
  }
}
