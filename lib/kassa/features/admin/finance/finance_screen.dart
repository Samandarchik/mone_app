import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';
import '../../../core/utils/business_day.dart';
import '../../../core/utils/payment_label.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  /// Ish kuni (02:00 chegarasi) — kechasi 00:30 da ochilsa kechagi kun.
  DateTime _selectedDate = businessToday();
  Map<String, dynamic>? _data;
  List<dynamic>? _expenses;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final date = _selectedDate.toIso8601String().substring(0, 10);
      final results = await Future.wait([
        ApiService().getFinanceDaily(date),
        ApiService().getFinanceExpenses(date),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0] as Map<String, dynamic>;
          _expenses = results[1] as List<dynamic>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      subtitle: AdminDateBar.label(_selectedDate),
      loading: _loading,
      onRefresh: _load,
      toolbar: AdminDateBar(
        date: _selectedDate,
        onChanged: (d) {
          setState(() => _selectedDate = d);
          _load();
        },
      ),
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          if (_data != null) ...[
            // Profit hero
            _buildProfitHero(),
            const SizedBox(height: 12),

            // Income
            _SectionCard(
              title: 'Daromad',
              icon: Icons.trending_up_rounded,
              accent: AppColors.success,
              children: [
                _row('Buyurtmalar',
                    '${_data!['income']?['total_orders'] ?? 0} ta'),
                _row(
                  'Jami tushum',
                  formatMoney(_data!['income']?['total_revenue'],
                      suffix: ' so\'m'),
                  bold: true,
                  color: AppColors.success,
                ),
                const Divider(height: 16, color: AppColors.borderSoft),
                ...((_data!['income']?['by_payment_method']
                                as Map<String, dynamic>? ??
                            {})
                        .entries)
                    .map((e) => _row(
                          paymentLabel(e.key),
                          formatMoney(e.value, suffix: ' so\'m'),
                        )),
              ],
            ),
            const SizedBox(height: 12),

            // Expenses
            _SectionCard(
              title: 'Xarajatlar',
              icon: Icons.trending_down_rounded,
              accent: AppColors.danger,
              children: [
                _row(
                  'Jami xarajat',
                  formatMoney(_data!['expenses']?['total'],
                      suffix: ' so\'m'),
                  bold: true,
                  color: AppColors.danger,
                ),
                if ((_data!['expenses']?['by_category']
                            as List<dynamic>? ??
                        [])
                    .isNotEmpty) ...[
                  const Divider(height: 16, color: AppColors.borderSoft),
                  ...((_data!['expenses']?['by_category']
                              as List<dynamic>? ??
                          [])
                      .map((c) => _row(
                            c['category_name']?['uz'] ?? '?',
                            formatMoney(c['total'], suffix: ' so\'m'),
                          ))),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Expense details
            if (_expenses != null && _expenses!.isNotEmpty) ...[
              _SectionCard(
                title: 'Xarajatlar tafsiloti',
                icon: Icons.receipt_long_rounded,
                accent: AppColors.warning,
                children: [
                  ..._expenses!.asMap().entries.map((entry) {
                    final i = entry.key;
                    final e = entry.value;
                    final last = i == _expenses!.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: last
                            ? null
                            : const Border(
                                bottom: BorderSide(
                                    color: AppColors.borderSoft),
                              ),
                      ),
                      child: Row(
                        children: [
                          const IconAvatar(
                            icon: Icons.receipt_long_rounded,
                            color: AppColors.warning,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e['description'] ?? 'Xarajat',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  e['category_name']?['uz'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '- ${formatMoney(e['amount'], suffix: ' so\'m')}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildProfitHero() {
    final netProfit = _data!['profit']?['net_profit'] ?? 0;
    final num pn = netProfit is num ? netProfit : 0;
    final isPositive = pn >= 0;
    final color = isPositive ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [const Color(0xFFDC2626), const Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPositive
                    ? Icons.account_balance_wallet_rounded
                    : Icons.warning_amber_rounded,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'Sof foyda',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(netProfit, suffix: ' so\'m'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v,
          {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textMuted)),
            Text(
              v,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 15 : 13,
                color: color ?? AppColors.text,
              ),
            ),
          ],
        ),
      );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

