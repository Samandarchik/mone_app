import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/payment_label.dart';
import 'write_off_screen.dart';
import '../../../core/widgets/tutorial_widgets.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  /// Smena yopish so'rovi ketyapti — ikki marta bosishdan himoya.
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    AppState().addListener(_onChanged);
  }

  @override
  void dispose() {
    AppState().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? get _shift => AppState().shift;
  bool get _isOpen => _shift?['status'] == 'open';

  /// Pul maydonini o'qish: "1 250 000" / "1.250.000" kabi yozuvlar ham
  /// to'g'ri tushuniladi. Ilgari bunday matn JIMGINA 0 bo'lib ketib, smena
  /// hisobotida bo'lmagan kamomad ko'rsatardi.
  ///
  /// Maydon BO'SH qolganmi yoki ataylab 0 yozilganmi — farqlanadi.
  /// Bo'sh bo'lsa null qaytadi: smena summasiz ochilmaydi/yopilmaydi.
  int? _parseSumOrNull(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  void _openShift() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smenani ochish'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Kassadagi naqd summa',
            suffixText: 'so\'m',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: const [MoneyInputFormatter()],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          // Summa kiritilmaguncha tugma o'chiq turadi: bo'sh maydon
          // jimgina 0 bo'lib ketsa, smena oxirida bo'lmagan kamomad chiqadi.
          AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              final entered = _parseSumOrNull(c.text);
              return FilledButton(
                onPressed: entered == null
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        try {
                          await ApiService().openShift(entered);
                        } catch (e) {
                          if (mounted) {
                            String msg = 'Xatolik yuz berdi';
                            if (e is DioException && e.response?.data is Map) {
                              msg = (e.response!.data as Map)['message'] ?? msg;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(msg),
                                  backgroundColor: AppColors.danger),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success),
                child: const Text('Ochish'),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Smena yopilgandan keyingi hisobot — kassir uchun eng muhim raqam.
  void _showSummary(Map<String, dynamic> res) {
    final summary = res['summary'];
    if (summary is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Smena yopildi'),
        backgroundColor: AppColors.success,
      ));
      return;
    }
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    final expected = asInt(summary['expected_cash']);
    final actual = asInt(summary['actual_cash']);
    final diff = asInt(summary['cash_difference']);
    final revenue = summary['revenue'];
    final total = revenue is Map ? asInt(revenue['total']) : 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smena yopildi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryRow('Tushum', total),
            _summaryRow('Xarajat', asInt(summary['expenses_total'])),
            const Divider(),
            _summaryRow('Kutilgan naqd', expected),
            _summaryRow('Haqiqiy naqd', actual),
            const Divider(),
            _summaryRow(
              diff == 0 ? 'Farq yo‘q' : (diff > 0 ? 'Izlishik' : 'Kamomad'),
              diff.abs(),
              color: diff == 0
                  ? AppColors.success
                  : (diff > 0 ? AppColors.info : AppColors.danger),
              bold: true,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, int value,
      {Color color = AppColors.text, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: color)),
          const Spacer(),
          Text(
            formatMoney(value, suffix: ' so\'m'),
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Kutilgan naqd bilan kiritilgan summa mos kelmasa — kassir farqni
  /// KO'RIB tasdiqlashi shart. Ilgari «500» deb yozib qo'yish smenani
  /// jimgina 1 650 kamomad bilan yopib yuborardi.
  Future<bool?> _confirmDiff(int expected, int actual) {
    final diff = actual - expected;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(diff > 0 ? 'Izlishik bor' : 'Kamomad bor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryRow('Kutilgan naqd', expected),
            _summaryRow('Kiritilgan summa', actual),
            const Divider(),
            _summaryRow(
              diff > 0 ? 'Izlishik' : 'Kamomad',
              diff.abs(),
              color: diff > 0 ? AppColors.info : AppColors.danger,
              bold: true,
            ),
            const SizedBox(height: 10),
            const Text(
              'Shu farq bilan smenani yopasizmi?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo‘q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Ha, yopish'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitClose(int actual) async {
    // Ikki marta bosishdan himoya: ilgari hech qanday qo'riqchi yo'q edi
    // va WSS "sekinlashsa" kassir ikkinchi marta, boshqa summa bilan
    // bosardi.
    if (_closing) return;
    _closing = true;
    try {
      final res = await ApiService().closeShift(actual);
      if (!mounted) return;
      // Hisobot NATIJASI ko'rsatiladi. Ilgari javob tashlab yuborilardi:
      // kassir kamomad/izlishik raqamini — smena yopishning butun
      // ma'nosini — umuman ko'rmasdi va ekranda hech narsa
      // o'zgarmagani uchun qayta bosardi.
      _showSummary(res);
    } catch (e) {
      if (mounted) {
        String msg = 'Xatolik yuz berdi';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['message'] ?? msg;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      _closing = false;
    }
  }

  void _closeShift() {
    final stats = _shift?['current_stats'] as Map<String, dynamic>? ?? {};
    final ec = stats['current_expected_cash'];
    final expected = ec is num ? ec.toInt() : 0;
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smenani yopish'),
        content: AnimatedBuilder(
          animation: c,
          builder: (_, _) {
            final actual = _parseSumOrNull(c.text);
            final diff = (actual ?? expected) - expected;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _summaryRow('Kutilgan naqd', expected, bold: true),
                const Divider(),
                TextField(
                  controller: c,
                  decoration: const InputDecoration(
                    labelText: 'Kassadagi haqiqiy summa',
                    suffixText: 'so\'m',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                ),
                const SizedBox(height: 8),
                // Farq kassir tugmani bosishidan OLDIN ko'rinadi.
                if (actual != null)
                  _summaryRow(
                    diff == 0
                        ? 'Farq yo‘q'
                        : (diff > 0 ? 'Izlishik' : 'Kamomad'),
                    diff.abs(),
                    color: diff == 0
                        ? AppColors.success
                        : (diff > 0 ? AppColors.info : AppColors.danger),
                    bold: true,
                  )
                else
                  const Text(
                    'Summani kiriting',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          // Summa kiritilmaguncha yopilmaydi.
          AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              final actual = _parseSumOrNull(c.text);
              return FilledButton(
                onPressed: actual == null
                    ? null
                    : () async {
                        if (_closing) return;
                        if (actual != expected) {
                          final ok = await _confirmDiff(expected, actual);
                          if (ok != true) return;
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _submitClose(actual);
                      },
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('Yopish'),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOpen) {
      return EmptyState(
        icon: Icons.lock_rounded,
        title: 'Smena yopiq',
        subtitle: 'Ish boshlash uchun smenani oching',
        color: AppColors.danger,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 280,
              child: FilledButton.icon(
                onPressed: _openShift,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Smenani ochish',
                    style: TextStyle(fontSize: 15)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => showTutorialsFor(context, 'pos.shift'),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('Qanday ishlaydi? — video'),
            ),
          ],
        ),
      );
    }

    final stats = _shift!['current_stats'] as Map<String, dynamic>? ?? {};
    final byPayment = stats['by_payment'] as Map<String, dynamic>? ?? {};
    final payMethods = reportPaymentMethods(byPayment);
    final byType = stats['by_type'] as Map<String, dynamic>? ?? {};
    final dineIn = byType['dine_in'] as Map<String, dynamic>? ?? {};
    final takeaway = byType['takeaway'] as Map<String, dynamic>? ?? {};
    final delivery = byType['delivery'] as Map<String, dynamic>? ?? {};

    // Planshetda o'qishga qulay kenglikda markazda — ilgari hisobot
    // qatorlari 1000pt ga cho'zilib, yorliq bilan summa orasi ochilib
    // ketardi (chapda «Naqd», o'ng chekkada raqam).
    return KMaxWidth(
      maxWidth: context.isTabletUi ? 720 : double.infinity,
      child: ListView(
      padding: EdgeInsets.fromLTRB(
          context.gutter, context.isTabletUi ? 18 : 12, context.gutter, 24),
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.lock_open_rounded,
                  size: 20, color: AppColors.success),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smena ochiq',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      letterSpacing: -0.4),
                ),
                Text('Joriy holat',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(width: 8),
            const TutorialHelpButton('pos.shift', size: 26),
            const Spacer(),
            StatusBadge(
              label: '${stats['total_orders'] ?? 0}',
              color: AppColors.primary,
              icon: Icons.receipt_long_rounded,
              fontSize: 11,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Hero revenue card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.coloredGlow(AppColors.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Jami tushum',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatMoney(stats['total_revenue'], suffix: ' so\'m'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Boshlang\'ich naqd: ${formatMoney(_shift!['opening_cash'], suffix: ' so\'m')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Payments
        KSection(
          title: 'To\'lov usullari',
          icon: Icons.account_balance_wallet_rounded,
          children: [
            for (final (i, m) in payMethods.indexed)
              _payRow(m.$3, m.$2, byPayment[m.$1], m.$4,
                  last: i == payMethods.length - 1),
          ],
        ),
        const SizedBox(height: 12),

        // Order types
        KSection(
          title: 'Buyurtma turlari',
          icon: Icons.category_rounded,
          children: [
            _typeRow(Icons.table_restaurant_rounded, 'Restoran',
                dineIn['count'], dineIn['total'], AppColors.info),
            _typeRow(Icons.takeout_dining_rounded, 'Saboy',
                takeaway['count'], takeaway['total'], AppColors.warning),
            _typeRow(Icons.delivery_dining_rounded, 'Dostafka',
                delivery['count'], delivery['total'], AppColors.success,
                last: true),
          ],
        ),
        const SizedBox(height: 12),

        // Cash flow
        KSection(
          title: 'Naqd hisob',
          icon: Icons.savings_rounded,
          children: [
            KKeyValueRow(
              label: 'Boshlang\'ich naqd',
              value: formatMoney(_shift!['opening_cash'], suffix: ' so\'m'),
            ),
            KKeyValueRow(
              label: 'Naqd tushum',
              value: formatMoney(byPayment['cash'], suffix: ' so\'m'),
              valueColor: AppColors.success,
            ),
            KKeyValueRow(
              label: 'Xarajatlar',
              value:
                  '- ${formatMoney(stats['expenses_total'], suffix: ' so\'m')}',
              valueColor: AppColors.danger,
            ),
            KKeyValueRow(
              label: 'Kutilgan naqd',
              value: formatMoney(stats['current_expected_cash'],
                  suffix: ' so\'m'),
              bold: true,
              divider: false,
            ),
          ],
        ),
        const SizedBox(height: 12),

        if ((stats['active_sd_orders'] ?? 0) > 0)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${stats['active_sd_orders']} ta saboy/dostafka yopilmagan',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),

        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const WriteOffScreen()),
              );
            },
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Spisaniya',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _closeShift,
            icon: const Icon(Icons.lock_rounded, size: 18),
            label: const Text('Smenani yopish',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _payRow(
      IconData icon, String label, dynamic amount, Color color,
      {bool last = false}) {
    final val = amount is int ? amount : 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.borderSoft),
              ),
      ),
      child: Row(
        children: [
          IconAvatar(icon: icon, color: color, size: 32),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            formatMoney(val, suffix: ' so\'m'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: val > 0 ? color : AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeRow(IconData icon, String label, dynamic count,
      dynamic total, Color color,
      {bool last = false}) {
    final c = count is int ? count : 0;
    final t = total is int ? total : 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.borderSoft),
              ),
      ),
      child: Row(
        children: [
          IconAvatar(icon: icon, color: color, size: 32),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text('$c ta buyurtma',
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textFaint)),
            ],
          ),
          const Spacer(),
          Text(
            formatMoney(t, suffix: ' so\'m'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: t > 0 ? color : AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}
