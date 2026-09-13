// yuk/ui/yuk_transfer_history_ui.dart — targovlidan kelgan pullar tarixi ekrani:
// YukTransferHistoryUi (+ _TransferHistoryCard). Qabul/rad/kutilayotgan pullar bitta
// ro'yxatda + holat bo'yicha jami; YukService.fetchTransfers va transfer socketiga tayanadi
// (faqat ko'rish — qabul/rad bosh ekranda).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uz_ai_dev/core/network/order_socket.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/core/widgets/full_screen_image.dart';
import 'package:uz_ai_dev/yuk/models/yuk_transfer_model.dart';
import 'package:uz_ai_dev/yuk/services/yuk_service.dart';

// Targovli tizimidan kelgan BARCHA pullar tarixi: qabul qilingan, rad
// etilgan va hali kutilayotganlar bitta ro'yxatda (yangisi tepada), tepada
// holatlar bo'yicha jami summalar. Bosh ekran AppBar'idagi hamyon
// tugmasidan ochiladi. Qabul qilish/rad etish bu yerda EMAS — bosh
// ekrandagi kutilayotgan pul kartasida.
class YukTransferHistoryUi extends StatefulWidget {
  const YukTransferHistoryUi({super.key});

  @override
  State<YukTransferHistoryUi> createState() => _YukTransferHistoryUiState();
}

class _YukTransferHistoryUiState extends State<YukTransferHistoryUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);

  final YukService _service = YukService();
  StreamSubscription<TransferSocketEvent>? _socketSub;

  List<YukTransfer> _transfers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Real-time: yangi pul kelsa yoki qaror qilinsa ro'yxat yangilanadi
    // (socket bosh ekran tomonidan allaqachon ulangan).
    _socketSub = OrderSocket.instance.transferEvents.listen((_) => _load());
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _service.fetchTransfers();
      if (!mounted) return;
      setState(() {
        _transfers = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_transfers.isEmpty) {
          _error = '$e'.replaceFirst('Exception: ', '');
        }
      });
    }
  }

  double _totalFor(String status) => _transfers
      .where((t) => t.status == status)
      .fold(0, (sum, t) => sum + t.amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Pullar tarixi (Targovli)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _load();
                          },
                          child: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _transfers.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Center(
                              child: Text(
                                'Hozircha pul kelmagan',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _summary(),
                            const SizedBox(height: 12),
                            for (final t in _transfers)
                              _TransferHistoryCard(transfer: t),
                          ],
                        ),
                ),
    );
  }

  // Tepadagi jami ko'rsatkichlar: olingan / kutilmoqda / rad etilgan.
  Widget _summary() {
    final accepted = _totalFor('accepted');
    final pending = _totalFor('pending');
    final rejected = _totalFor('rejected');
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            _summaryRow(
              'Qabul qilingan',
              accepted,
              Colors.green.shade700,
              Icons.check_circle,
            ),
            if (pending > 0) ...[
              const Divider(height: 14),
              _summaryRow(
                'Kutilmoqda',
                pending,
                Colors.orange.shade800,
                Icons.hourglass_top,
              ),
            ],
            if (rejected > 0) ...[
              const Divider(height: 14),
              _summaryRow(
                'Rad etilgan',
                rejected,
                Colors.red.shade700,
                Icons.cancel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double sum, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
        Text(
          '${_fmtMoney(sum)} so\'m',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// Bitta pul yozuvi kartasi (faqat ko'rish).
/// Targovli'dan kelgan pulning chek rasmi (kichik prevyu, bosilsa to'liq
/// ekran). Bosh ekran kartasi (`yuk_home_ui.dart`) ham shuni ishlatadi.
class TransferReceiptImage extends StatelessWidget {
  final String url;
  const TransferReceiptImage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openFullScreenImage(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: AppNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            maxDecodeWidth: 800,
          ),
        ),
      ),
    );
  }
}

class _TransferHistoryCard extends StatelessWidget {
  final YukTransfer transfer;
  const _TransferHistoryCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final dateStr = t.created == null
        ? ''
        : DateFormat('dd.MM.yyyy HH:mm').format(t.created!.toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_fmtMoney(t.amount)} so\'m',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _statusChip(t.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (t.isOnline) 'Onlayn to\'lov',
                if (dateStr.isNotEmpty) dateStr,
                if (t.senderName.isNotEmpty) 'Yubordi: ${t.senderName}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (t.comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.comment, style: const TextStyle(fontSize: 13)),
              ),
            // Chek rasmi (targovli «Онлайн» to'lovi) — bosilsa to'liq ekran.
            if (t.hasImage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TransferReceiptImage(url: t.imageFullUrl),
              ),
            if (t.status == 'rejected' && t.reviewText.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Sabab: ${t.reviewText}',
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    late Color color;
    late String text;
    late IconData icon;
    switch (status) {
      case 'accepted':
        color = Colors.green.shade700;
        text = 'Qabul qilingan';
        icon = Icons.check_circle;
      case 'rejected':
        color = Colors.red.shade700;
        text = 'Rad etilgan';
        icon = Icons.cancel;
      default:
        color = Colors.orange.shade800;
        text = 'Kutilmoqda';
        icon = Icons.hourglass_top;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Pul summasi: har 3 xonadan keyin probel (masalan 1 500 000). Butun so'm.
String _fmtMoney(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}
