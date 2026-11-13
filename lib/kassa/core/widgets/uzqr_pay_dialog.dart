import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// UzQR orqali to'lov: server dinamik QR ochadi, mijoz bank ilovasida
/// skanerlab to'laydi, kassa har 3 soniyada holatni so'raydi.
///
/// To'lov tasdiqlansa `invoice_id` qaytadi — chek AYNAN shu invoys bilan
/// yopiladi (server pul kelganini o'zi tekshiradi). Bekor qilinsa `null`.
Future<String?> showUzqrPayDialog(
  BuildContext context, {
  required int amount,
  String? tableSku,
  String? orderNumber,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UzqrPayDialog(
      amount: amount,
      tableSku: tableSku,
      orderNumber: orderNumber,
    ),
  );
}

enum _Stage { creating, waiting, paid, error, paidExists, refunding, refunded }

class _UzqrPayDialog extends StatefulWidget {
  final int amount;
  final String? tableSku;
  final String? orderNumber;
  const _UzqrPayDialog({required this.amount, this.tableSku, this.orderNumber});

  @override
  State<_UzqrPayDialog> createState() => _UzqrPayDialogState();
}

class _UzqrPayDialogState extends State<_UzqrPayDialog> {
  /// Hujjat bo'yicha polling oralig'i — 3 soniya.
  static const _pollEvery = Duration(seconds: 3);

  _Stage _stage = _Stage.creating;
  String? _invoiceId;
  String? _qrText;
  String _message = '';

  /// Aloqa uzilganda QR ostida ko'rinadigan ogohlantirish (polling davom etadi).
  String _pollWarning = '';

  /// Summasi mos kelmagan, avval to'langan invoys (qaytarish uchun).
  String? _paidInvoiceId;
  int _paidAmount = 0;

  Timer? _timer;
  bool _busy = false;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _errText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Server bilan aloqa yo\'q';
    }
    return '$e';
  }

  Future<void> _create() async {
    _timer?.cancel();
    setState(() {
      _stage = _Stage.creating;
      _message = '';
      _pollWarning = '';
    });
    try {
      final res = await ApiService().uzqrCreateInvoice(
        amount: widget.amount,
        tableSku: widget.tableSku,
        orderNumber: widget.orderNumber,
      );
      if (!mounted) return;
      _invoiceId = res['invoice_id']?.toString();
      if ((res['status'] as num?)?.toInt() == 2) {
        _onPaid();
        return;
      }
      setState(() {
        _qrText = res['qr_text']?.toString();
        _stage = _Stage.waiting;
      });
      _timer = Timer.periodic(_pollEvery, (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      final data = e is DioException ? e.response?.data : null;
      if (data is Map && data['error'] == 'uzqr_paid_exists') {
        setState(() {
          _paidInvoiceId = data['invoice_id']?.toString();
          _paidAmount = (data['amount'] as num?)?.toInt() ?? 0;
          _message = _errText(e);
          _stage = _Stage.paidExists;
        });
        return;
      }
      setState(() {
        _message = _errText(e);
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _poll() async {
    final id = _invoiceId;
    if (id == null || _polling || _busy || _stage != _Stage.waiting) return;
    _polling = true;
    try {
      final res = await ApiService().uzqrInvoiceStatus(id);
      if (!mounted || _stage != _Stage.waiting) return;
      final status = (res['status'] as num?)?.toInt() ?? 1;
      if (status == 2) {
        _onPaid();
      } else if (status == 3) {
        _timer?.cancel();
        setState(() {
          _message = 'To\'lov rad etildi yoki QR bekor qilindi';
          _stage = _Stage.error;
        });
      } else if (_pollWarning.isNotEmpty) {
        setState(() => _pollWarning = '');
      }
    } catch (e) {
      // Vaqtinchalik uzilish — QR joyida qoladi, keyingi so'rov qayta urinadi.
      if (mounted && _stage == _Stage.waiting) {
        setState(() => _pollWarning = _errText(e));
      }
    } finally {
      _polling = false;
    }
  }

  void _onPaid() {
    _timer?.cancel();
    setState(() => _stage = _Stage.paid);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.pop(context, _invoiceId);
    });
  }

  /// «Bekor qilish»: QR serverda o'chiriladi. Mijoz ulgurib to'lagan bo'lsa
  /// server status=2 qaytaradi — to'lov muvaffaqiyatli deb davom etamiz.
  Future<void> _cancel() async {
    final id = _invoiceId;
    if (id == null || _stage != _Stage.waiting) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ApiService().uzqrCancelInvoice(id);
      if (!mounted) return;
      if ((res['status'] as num?)?.toInt() == 2) {
        setState(() => _busy = false);
        _onPaid();
        return;
      }
      _timer?.cancel();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pollWarning =
            'QR bekor qilinmadi: ${_errText(e)}. Qayta urinib ko\'ring.';
      });
    }
  }

  Future<void> _refund() async {
    final id = _paidInvoiceId;
    if (id == null) return;
    setState(() {
      _stage = _Stage.refunding;
      _message = '';
    });
    try {
      var res = await ApiService().uzqrRefund(id);
      // Qaytarish asinxron — yakuniy holatgacha 3 soniyada bir so'raymiz.
      while (mounted && (res['refund_status'] as num?)?.toInt() == 1) {
        await Future.delayed(_pollEvery);
        if (!mounted) return;
        try {
          res = await ApiService().uzqrRefundStatus(id);
        } catch (_) {
          // vaqtinchalik uzilish — qayta so'raymiz
        }
      }
      if (!mounted) return;
      if ((res['refund_status'] as num?)?.toInt() == 2) {
        setState(() => _stage = _Stage.refunded);
      } else {
        setState(() {
          _message = 'Qaytarish rad etildi. Keyinroq qayta urinib ko\'ring.';
          _stage = _Stage.paidExists;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = _errText(e);
        _stage = _Stage.paidExists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, size: 22, color: AppColors.primary),
            SizedBox(width: 8),
            Text('UzQR orqali to\'lov'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMoney(widget.amount, suffix: ' so\'m'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              _body(),
            ],
          ),
        ),
        actions: _actions(),
      ),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.creating:
        return const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        );
      case _Stage.waiting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: QrImageView(
                data: _qrText ?? '',
                size: 260,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Mijoz bank ilovasida skanerlasin — to\'lov kutilmoqda',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
            if (_pollWarning.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _pollWarning,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ],
          ],
        );
      case _Stage.paid:
        return const _Status(
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          text: 'To\'lov qabul qilindi',
        );
      case _Stage.error:
        return _Status(
          icon: Icons.error_outline_rounded,
          color: AppColors.danger,
          text: _message,
        );
      case _Stage.paidExists:
        return _Status(
          icon: Icons.info_outline_rounded,
          color: AppColors.warning,
          text: _message,
        );
      case _Stage.refunding:
        return const SizedBox(
          height: 160,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('Pul mijozga qaytarilmoqda…'),
            ],
          ),
        );
      case _Stage.refunded:
        return _Status(
          icon: Icons.undo_rounded,
          color: AppColors.success,
          text:
              '${formatMoney(_paidAmount, suffix: ' so\'m')} mijozga qaytarildi',
        );
    }
  }

  List<Widget> _actions() {
    switch (_stage) {
      case _Stage.creating:
      case _Stage.paid:
      case _Stage.refunding:
        return const [];
      case _Stage.waiting:
        return [
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: Text(_busy ? 'Bekor qilinmoqda…' : 'To\'lovni bekor qilish'),
          ),
        ];
      case _Stage.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
          FilledButton(onPressed: _create, child: const Text('Qayta urinish')),
        ];
      case _Stage.paidExists:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _refund,
            child: Text(
              '${formatMoney(_paidAmount, suffix: ' so\'m')} ni qaytarish',
            ),
          ),
        ];
      case _Stage.refunded:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
          FilledButton(onPressed: _create, child: const Text('Yangi QR')),
        ];
    }
  }
}

class _Status extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Status({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
