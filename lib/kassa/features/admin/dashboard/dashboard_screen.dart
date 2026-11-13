import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/payment_label.dart';
import '../../../core/theme/ui_kit.dart';
import '../admin_nav.dart';
import '../widgets/admin_page.dart';
import 'dart:async';
import '../../../core/utils/business_day.dart';
import '../../../core/utils/order_number.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _shift;
  Map<String, dynamic>? _finance;
  List<dynamic> _activeOrders = [];
  bool _loading = true;
  StreamSubscription? _wssSub;

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen(_onWssEvent);
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  void _onWssEvent(Map<String, dynamic> event) {
    final e = event['event'];
    if (e == 'order:new' ||
        e == 'order:closed' ||
        e == 'order:updated' ||
        e == 'shift:opened' ||
        e == 'shift:closed') {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      // Ish kuni (02:00 chegarasi): kechasi 01:00 da bosh sahifa hali
      // o'sha kechning tushumini ko'rsatadi, nol emas.
      final today = businessTodayStr();
      final results = await Future.wait([
        ApiService().getShift(),
        ApiService().getFinanceDaily(today),
        ApiService().getOrders(status: 'active'),
      ]);
      if (mounted) {
        setState(() {
          _shift = results[0] as Map<String, dynamic>;
          _finance = results[1] as Map<String, dynamic>;
          _activeOrders = results[2] as List<dynamic>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _shift?['status'] == 'open';
    final wide = context.isTabletUi;

    // Keng ekranda ikki ustun: chapda pul, o'ngda operatsion holat.
    // (Ilgari hammasi bitta tor ustunda edi va planshetda ekranning
    // uchdan ikki qismi bo'sh turardi.)
    final left = <Widget>[
      _buildRevenueHero(),
      const SizedBox(height: 12),
      _buildMiniStatsRow(),
      const SizedBox(height: 12),
      _buildPaymentCard(),
    ];
    final right = <Widget>[
      _buildOrderTypesCard(),
      const SizedBox(height: 12),
      _buildExpensesCard(),
      const SizedBox(height: 12),
      _buildActiveOrdersCard(),
    ];

    return AdminPage(
      subtitle: isOpen
          ? 'Smena ochiq · ${_shift?['opened_by']?['name'] ?? ''}'
          : 'Smena yopiq',
      loading: _loading,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          _buildShiftCard(),
          const SizedBox(height: 12),
          _quickActions(context),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: left)),
                const SizedBox(width: 12),
                Expanded(child: Column(children: right)),
              ],
            )
          else ...[
            ...left,
            const SizedBox(height: 12),
            ...right,
          ],
        ],
      ),
    );
  }

  /// Eng ko'p ishlatiladigan bo'limlarga bitta bosishda o'tish.
  Widget _quickActions(BuildContext context) {
    final scope = AdminScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    const items = [
      ('orders', 'Buyurtmalar', Icons.receipt_long_rounded, AppColors.info),
      ('finance', 'Moliya', Icons.account_balance_wallet_rounded,
          AppColors.success),
      ('products', 'Menyu', Icons.restaurant_menu_rounded, AppColors.warning),
      ('ingredients', 'Ombor', Icons.inventory_2_rounded, Color(0xFF06B6D4)),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (id, label, icon, color) = items[i];
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => scope.go(id),
              child: Container(
                width: 104,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShiftCard() {
    final isOpen = _shift?['status'] == 'open';
    final stats = _shift?['current_stats'] as Map<String, dynamic>? ?? {};
    final color = isOpen ? AppColors.success : AppColors.danger;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOpen ? 'Smena ochiq' : 'Smena yopiq',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (isOpen && _shift?['opened_by'] != null)
                  Text(
                    '${_shift!['opened_by']['name'] ?? ''}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (isOpen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${stats['total_orders'] ?? 0} buyurtma',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textFaint,
                  ),
                ),
                Text(
                  formatMoney(stats['total_revenue'], suffix: ' so\'m'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRevenueHero() {
    if (_finance == null) return const SizedBox();
    final income = _finance!['income'] as Map<String, dynamic>? ?? {};
    final profit = _finance!['profit'] as Map<String, dynamic>? ?? {};
    final revenue = income['total_revenue'] ?? 0;
    final netProfit = profit['net_profit'] ?? 0;
    final isPositive = (netProfit is num ? netProfit : 0) >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
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
              const Icon(Icons.trending_up_rounded,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                'Bugungi tushum',
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
            formatMoney(revenue, suffix: ' so\'m'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: Colors.white,
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'Foyda: ${formatMoney(netProfit, suffix: " so'm")}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatsRow() {
    if (_finance == null) return const SizedBox();
    final income = _finance!['income'] as Map<String, dynamic>? ?? {};
    final expenses = _finance!['expenses'] as Map<String, dynamic>? ?? {};
    return LayoutBuilder(
      builder: (context, constraints) {
        // 2-col grid on phone, 3-col side-by-side
        return Row(
          children: [
            Expanded(
              child: _miniCard(
                'Buyurtma',
                '${income['total_orders'] ?? 0}',
                AppColors.info,
                Icons.receipt_long_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniCard(
                'Xarajat',
                formatMoney(expenses['total']),
                AppColors.danger,
                Icons.trending_down_rounded,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _miniCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    if (_finance == null) return const SizedBox();
    final byPayment =
        _finance!['income']?['by_payment_method'] as Map<String, dynamic>? ??
            {};
    const methods = kPaymentMethods;
    return _SectionCard(
      title: 'To\'lov usullari',
      icon: Icons.account_balance_wallet_rounded,
      children: [
        for (var i = 0; i < methods.length; i++)
          _payRow(
            methods[i].$3,
            methods[i].$2,
            byPayment[methods[i].$1],
            methods[i].$4,
            last: i == methods.length - 1,
          ),
      ],
    );
  }

  Widget _payRow(IconData icon, String label, dynamic amount, Color color,
      {bool last = false}) {
    final val = amount is int ? amount : (amount is num ? amount.toInt() : 0);
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
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: val > 0 ? color : AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypesCard() {
    if (_finance == null) return const SizedBox();
    final income = _finance!['income'] as Map<String, dynamic>? ?? {};
    final total = income['total_orders'] ?? 0;
    final cancelled = income['cancelled_orders'] ?? 0;
    return _SectionCard(
      title: 'Buyurtmalar',
      icon: Icons.category_rounded,
      trailing: Row(
        children: [
          Text(
            '$total ta',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.text),
          ),
          if (cancelled > 0) ...[
            const SizedBox(width: 4),
            StatusBadge(
              label: '$cancelled bekor',
              color: AppColors.danger,
              fontSize: 10,
            ),
          ],
        ],
      ),
      children: [
        _typeRow(
            Icons.table_restaurant_rounded, 'Restoran', AppColors.info),
        _typeRow(
            Icons.takeout_dining_rounded, 'Saboy', AppColors.warning),
        _typeRow(Icons.delivery_dining_rounded, 'Dostafka',
            AppColors.success,
            last: true),
      ],
    );
  }

  Widget _typeRow(IconData icon, String label, Color color,
      {bool last = false}) {
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
        ],
      ),
    );
  }

  Widget _buildExpensesCard() {
    if (_finance == null) return const SizedBox();
    final expenses = _finance!['expenses'] as Map<String, dynamic>? ?? {};
    final total = expenses['total'] ?? 0;
    final cats = expenses['by_category'] as List<dynamic>? ?? [];
    return _SectionCard(
      title: 'Xarajatlar',
      icon: Icons.payments_outlined,
      trailing: Text(
        formatMoney(total, suffix: ' so\'m'),
        style: const TextStyle(
            fontWeight: FontWeight.w800, color: AppColors.danger),
      ),
      children: [
        if (cats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Xarajat yo\'q',
              style: TextStyle(color: AppColors.textFaint, fontSize: 13),
            ),
          )
        else
          ...cats.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            final last = i == cats.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                border: last
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.borderSoft)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c['category_name']?['uz'] ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    formatMoney(c['total'], suffix: ' so\'m'),
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildActiveOrdersCard() {
    return _SectionCard(
      title: 'Aktiv buyurtmalar',
      icon: Icons.local_fire_department_rounded,
      trailing: StatusBadge(
        label: '${_activeOrders.length}',
        color: _activeOrders.isNotEmpty
            ? AppColors.warning
            : AppColors.textFaint,
      ),
      children: [
        if (_activeOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'Aktiv buyurtma yo\'q',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13),
              ),
            ),
          )
        else
          ..._activeOrders.take(15).toList().asMap().entries.map((e) {
            final i = e.key;
            final o = e.value;
            final last = i == (_activeOrders.length.clamp(0, 15) - 1);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: last
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.borderSoft)),
              ),
              child: Row(
                children: [
                  _typeIcon(o['type']),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${shortOrderNumber(o['order_number'])}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          o['status'] ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textFaint),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(o['total'], suffix: ' so\'m'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _typeIcon(String? type) {
    Color c;
    IconData ic;
    switch (type) {
      case 'dine_in':
        ic = Icons.table_restaurant_rounded;
        c = AppColors.info;
        break;
      case 'takeaway':
        ic = Icons.takeout_dining_rounded;
        c = AppColors.warning;
        break;
      case 'delivery':
        ic = Icons.delivery_dining_rounded;
        c = AppColors.success;
        break;
      default:
        ic = Icons.receipt_rounded;
        c = AppColors.textFaint;
    }
    return IconAvatar(icon: ic, color: c, size: 32);
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> children;
  const _SectionCard({
    required this.title,
    required this.icon,
    this.trailing,
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
              Icon(icon, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}
