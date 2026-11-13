import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// Mone ulanishi — kassa katalogi Mone'dan keladi, cheklar va smenalar
/// Mone'ga yuboriladi (backend: internal/monesync). Bu ekran holatni
/// ko'rsatadi va «Hozir sinxronlash» beradi. Sozlamalar server .env da
/// (MONE_API_BASE, POSMONE_INTEGRATION_KEY) — bu yerda o'zgartirilmaydi.
class MoneScreen extends StatefulWidget {
  const MoneScreen({super.key});
  @override
  State<MoneScreen> createState() => _MoneScreenState();
}

class _MoneScreenState extends State<MoneScreen> {
  Map<String, dynamic> _st = const {};
  List<Map<String, dynamic>> _rejected = const [];
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Holat jonli: worker har 20 s da aylanadi.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final st = await ApiService().getMoneStatus();
      final rj = await ApiService().getMoneRejected();
      if (!mounted) return;
      setState(() {
        _st = st;
        _rejected = rj;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Holat olinmadi: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final res = await ApiService().syncMone();
      if (!mounted) return;
      final ok = res['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Mone bilan sinxronlandi'
            : 'Sinxron xatosi: ${res['error'] ?? res['message'] ?? 'noma\'lum'}'),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sinxron xatosi: $e'), backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _syncing = false);
      _load(quiet: true);
    }
  }

  String _time(dynamic v) {
    if (v is! String || v.isEmpty) return '—';
    final d = DateTime.tryParse(v)?.toLocal();
    if (d == null || d.year < 2000) return '—';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 170,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: color ?? Colors.black87)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final enabled = _st['enabled'] == true;
    final lastError = '${_st['last_error'] ?? ''}';
    final healthy = enabled && lastError.isEmpty && _st['last_ok_at'] != null;
    final cat = _st['last_catalog'] is Map ? _st['last_catalog'] as Map : const {};
    final push = _st['last_push'] is Map ? _st['last_push'] as Map : const {};
    final unsent = _n(_st['unsent']);
    final noPrice = _n(cat['products_no_price']);

    return AdminPage(
      subtitle: !enabled
          ? 'Mone ulanmagan'
          : healthy
              ? 'Mone bilan aloqa bor'
              : 'Mone bilan aloqa yo\'q',
      loading: _loading && _st.isEmpty,
      error: _st.isEmpty ? _error : null,
      onRetry: _load,
      onRefresh: _load,
      constrained: true,
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          AdminSection(
            title: 'Mone',
            subtitle: 'Mahsulotlar Mone\'dan keladi, savdo Mone\'ga ketadi',
            icon: Icons.sync_alt_rounded,
            color: AppColors.primary,
            trailing: StatusBadge(
              label: !enabled ? 'O\'chiq' : (healthy ? 'Ulangan' : 'Xato'),
              color: !enabled
                  ? AppColors.textMuted
                  : (healthy ? AppColors.success : AppColors.danger),
              icon: healthy ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            ),
            children: [
              if (!enabled)
                const Text(
                  'Server .env faylida MONE_API_BASE va POSMONE_INTEGRATION_KEY '
                  'berilmagan — kassa mustaqil ishlayapti.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                )
              else ...[
                _row('Filial', '${_st['filial_name'] ?? ''} (#${_n(_st['filial_id'])})',
                    color: _n(_st['filial_id']) == 0 ? AppColors.danger : null),
                _row('Kassa ID', '${_st['station_id'] ?? ''}'),
                _row('Oxirgi muvaffaqiyat', _time(_st['last_ok_at'])),
                if (lastError.isNotEmpty)
                  _row('Xato', lastError, color: AppColors.danger),
                _row('Joriy smena cheklari',
                    '${_n(push['waiting'])} ta — smena yopilganda Mone\'ga ketadi'),
                _row('Yuborilmagan cheklar', '$unsent',
                    color: unsent > 0 ? AppColors.warning : AppColors.success),
                _row('Rad etilgan / ogohlantirish', '${_rejected.length}',
                    color: _rejected.isNotEmpty ? AppColors.danger : null),
                _row('Oxirgi yuborish',
                    'chek ${_n(push['checks_sent'])}, smena yopildi ${_n(push['shifts_closed'])}'),
                _row('Katalog',
                    'yangi ${_n(cat['products_created'])}, yangilangan ${_n(cat['products_updated'])}, '
                        'yashirilgan ${_n(cat['products_deactivated'])}'),
                if (noPrice > 0)
                  _row('Narxsiz mahsulot', '$noPrice ta — Mone\'da sotuv narxini qo\'ying',
                      color: AppColors.warning),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _syncing ? null : _sync,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync_rounded, size: 20),
                    label: Text(_syncing ? 'Sinxronlanmoqda…' : 'Hozir sinxronlash',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
          if (_rejected.isNotEmpty)
            AdminSection(
              title: 'Rad etilgan / ogohlantirishlar',
              subtitle: 'Mone qabul qilmagan yoki to\'liq bog\'lanmagan yozuvlar',
              icon: Icons.report_gmailerrorred_rounded,
              color: AppColors.danger,
              children: [
                for (final r in _rejected)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${r['kind']} #${r['ref_id']} · ${_time(r['pushed_at'])}\n${r['info']}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
