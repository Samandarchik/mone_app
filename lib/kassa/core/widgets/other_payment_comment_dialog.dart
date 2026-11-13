import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// «Boshqa» usulida to'lov izohi — nima evaziga to'langani (masalan,
/// «egasining mehmoni», «perechislenie»). Izoh SHART: summa bilan birga
/// admin guruhiga ketadi. Bekor qilinsa `null` qaytadi.
///
/// [ownerName] berilsa — asoschi (qilinadigan_ishlar «Получатель») nomiga
/// to'lov: izoh unga «Бепул» so'rovi bilan rasm/golos o'rniga boradi.
Future<String?> askOtherPaymentComment(
  BuildContext context, {
  required int amount,
  String? ownerName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _OtherPaymentCommentDialog(amount: amount, ownerName: ownerName),
  );
}

class _OtherPaymentCommentDialog extends StatefulWidget {
  final int amount;
  final String? ownerName;
  const _OtherPaymentCommentDialog({required this.amount, this.ownerName});

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
    final owner = (widget.ownerName ?? '').isNotEmpty;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            owner ? Icons.person_rounded : Icons.more_horiz_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              owner ? widget.ownerName! : 'Boshqa to\'lov',
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
            Text(
              owner
                  ? 'Izoh yozing — asoschiga qabul qilish uchun so\'rov bo\'lib boradi'
                  : 'Izoh yozing — summa bilan birga guruhga yuboriladi',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: owner
                    ? 'Masalan: mehmonlar uchun olib ketdi'
                    : 'Masalan: egasining mehmoni',
                border: const OutlineInputBorder(),
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
