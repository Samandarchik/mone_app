import 'dart:async';
import 'dart:typed_data';
import '../../../core/utils/payment_label.dart';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../../../core/utils/business_day.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const _darkRed = Color(0xFF7F1D1D);

  Map<String, dynamic> _report = {};
  List<dynamic> _productMargins = [];
  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  StreamSubscription? _wssSub;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final today = businessToday();
    _to = today;
    _from = today.subtract(const Duration(days: 6));
    unawaited(_load());
    _wssSub = WssService().eventStream.listen((event) {
      final name = event['event'];
      if (name == 'order:closed' ||
          name == 'ingredient:updated' ||
          name == 'menu:outdated' ||
          name == 'shift:closed') {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final generation = ++_loadGeneration;
    if (!quiet && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await Future.wait<dynamic>([
        ApiService().getAnalyticsOverview(
          from: _apiDate(_from),
          to: _apiDate(_to),
        ),
        ApiService().getProductAnalytics(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _report = _map(result[0]);
        _productMargins = _list(_map(result[1])['products']);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _setPreset(int days) async {
    final today = businessToday();
    setState(() {
      _to = today;
      _from = today.subtract(Duration(days: days - 1));
    });
    await _load();
  }

  Future<void> _pickRange() async {
    final today = businessToday();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Hisobot oralig‘ini tanlang',
      cancelText: 'Bekor',
      confirmText: 'Tanlash',
      saveText: 'Tanlash',
    );
    if (picked == null || !mounted) return;
    if (picked.duration.inDays + 1 > 366) {
      _toast('Hisobot oralig‘i 366 kundan oshmasligi kerak', error: true);
      return;
    }
    setState(() {
      _from = _dateOnly(picked.start);
      _to = _dateOnly(picked.end);
    });
    await _load();
  }

  Future<void> _exportCsv() async {
    const csvType = XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
      mimeTypes: ['text/csv'],
    );
    final fileName = 'mone-kassa-hisobot-${_apiDate(_from)}_${_apiDate(_to)}.csv';
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [csvType],
    );
    if (location == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final bytes = await ApiService().exportAnalyticsCsv(
        from: _apiDate(_from),
        to: _apiDate(_to),
      );
      if (bytes.isEmpty) throw StateError('CSV fayl bo‘sh');
      final file = XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: 'text/csv',
        name: fileName,
      );
      await file.saveTo(location.path);
      if (mounted) _toast('CSV hisobot saqlandi');
    } catch (error) {
      if (mounted) _toast(_errorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.danger : AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  int? get _activePreset {
    final today = businessToday();
    if (_to != today) return null;
    final days = _to.difference(_from).inDays + 1;
    return const [7, 30, 90].contains(days) ? days : null;
  }

  @override
  Widget build(BuildContext context) {
    final summary = _map(_report['summary']);
    final customers = _map(_report['customers']);
    final trend = _maps(_report['trend']);
    final topProducts = _maps(_report['top_products']);
    final topCategories = _maps(_report['top_categories']);
    final byType = _maps(_report['by_type']);
    final byPayment = _maps(_report['by_payment']);
    final bySource = _maps(_report['by_source']);
    final peakHours = _maps(_report['peak_hours']);

    return AdminPage(
      subtitle: '${_displayDate(_from)} — ${_displayDate(_to)}',
      loading: _loading && _report.isEmpty,
      error: _report.isEmpty ? _error : null,
      onRetry: _load,
      onRefresh: _load,
      primaryAction: AdminAction(
        label: _exporting ? 'Tayyorlanmoqda…' : 'CSV yuklash',
        icon: Icons.download_rounded,
        onPressed: _exporting ? null : _exportCsv,
        color: const Color(0xFF14B8A6),
      ),
      actions: [
        AdminIconAction(
          icon: Icons.date_range_rounded,
          tooltip: 'Sana oralig‘i',
          onPressed: _pickRange,
        ),
      ],
      toolbar: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final days in const [7, 30, 90]) ...[
              KChip(
                label: '$days kun',
                selected: _activePreset == days,
                accent: const Color(0xFF14B8A6),
                onTap: () => _setPreset(days),
              ),
              const SizedBox(width: 8),
            ],
            KChip(
              label: 'Boshqa oraliq',
              icon: Icons.tune_rounded,
              selected: _activePreset == null,
              accent: const Color(0xFF14B8A6),
              onTap: _pickRange,
            ),
          ],
        ),
      ),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          if (_error != null) ...[
            _InlineWarning(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          _buildSummary(summary),
          if (_int(summary['incomplete_cost_products']) > 0) ...[
            const SizedBox(height: 10),
            _CostWarning(count: _int(summary['incomplete_cost_products'])),
          ],
          const SizedBox(height: 12),
          _TrendCard(points: trend),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final typeCard = _BreakdownCard(
                title: 'Buyurtma turlari',
                icon: Icons.restaurant_rounded,
                color: AppColors.primary,
                items: byType,
                keyName: 'type',
                valueName: 'revenue',
                label: _orderTypeLabel,
                showCount: true,
              );
              final paymentCard = _BreakdownCard(
                title: 'To‘lov usullari',
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.success,
                items: byPayment,
                keyName: 'method',
                valueName: 'total',
                label: _paymentLabel,
              );
              if (!wide) {
                return Column(
                  children: [typeCard, const SizedBox(height: 12), paymentCard],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: typeCard),
                  const SizedBox(width: 12),
                  Expanded(child: paymentCard),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _TopProductsCard(items: topProducts),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 880;
              final categories = _TopCategoriesCard(items: topCategories);
              final hours = _PeakHoursCard(items: peakHours);
              if (!wide) {
                return Column(
                  children: [categories, const SizedBox(height: 12), hours],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: categories),
                  const SizedBox(width: 12),
                  Expanded(child: hours),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildCustomerAndSource(customers, bySource),
          const SizedBox(height: 12),
          _buildMargins(),
        ],
      ),
    );
  }

  Widget _buildSummary(Map<String, dynamic> summary) {
    final netProfit = _int(summary['net_profit']);
    final stats = [
      (
        'Tushum',
        formatMoney(summary['revenue'], suffix: ' so‘m'),
        Icons.payments_rounded,
        AppColors.success,
        '${_int(summary['completed_orders'])} ta yopilgan chek',
      ),
      (
        'O‘rtacha chek',
        formatMoney(summary['average_check'], suffix: ' so‘m'),
        Icons.receipt_long_rounded,
        AppColors.info,
        '${_int(summary['cancelled_orders'])} ta bekor',
      ),
      (
        'Taxminiy tannarx',
        formatMoney(summary['estimated_cogs'], suffix: ' so‘m'),
        Icons.inventory_2_rounded,
        AppColors.warning,
        'Joriy retsept va xarid narxida',
      ),
      (
        'Xarajatlar',
        formatMoney(summary['expenses'], suffix: ' so‘m'),
        Icons.trending_down_rounded,
        AppColors.danger,
        'Chegirma: ${formatMoney(summary['discounts'], suffix: ' so‘m')}',
      ),
      (
        'Yalpi foyda',
        formatMoney(summary['gross_profit'], suffix: ' so‘m'),
        Icons.show_chart_rounded,
        _int(summary['gross_profit']) >= 0
            ? AppColors.success
            : AppColors.danger,
        'Tushum − tannarx',
      ),
      (
        'Sof foyda',
        formatMoney(netProfit, suffix: ' so‘m'),
        Icons.account_balance_rounded,
        netProfit >= 0 ? AppColors.primary : _darkRed,
        'Tushum − tannarx − xarajat',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: KStat(
                  label: stat.$1,
                  value: stat.$2,
                  icon: stat.$3,
                  color: stat.$4,
                  hint: stat.$5,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCustomerAndSource(
    Map<String, dynamic> customers,
    List<Map<String, dynamic>> sources,
  ) {
    final customerCard = KSection(
      title: 'Mijozlar',
      icon: Icons.people_alt_rounded,
      iconColor: const Color(0xFFDB2777),
      children: [
        const SizedBox(height: 10),
        _MiniGrid(
          items: [
            ('Aniqlangan chek', _int(customers['identified_orders'])),
            ('Noyob mijoz', _int(customers['unique_customers'])),
            ('Yangi mijoz', _int(customers['new_customers'])),
            ('Qaytgan mijoz', _int(customers['returning_customers'])),
          ],
        ),
      ],
    );
    final sourceCard = _BreakdownCard(
      title: 'Buyurtma manbalari',
      icon: Icons.hub_rounded,
      color: const Color(0xFF7C3AED),
      items: sources,
      keyName: 'source',
      valueName: 'revenue',
      label: _sourceLabel,
      showCount: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            children: [customerCard, const SizedBox(height: 12), sourceCard],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: customerCard),
            const SizedBox(width: 12),
            Expanded(child: sourceCard),
          ],
        );
      },
    );
  }

  Widget _buildMargins() {
    final losing = _productMargins.where((product) {
      return _int(product['profit']) < 0;
    }).length;
    final incomplete = _productMargins.where((product) {
      return product['incomplete'] == true;
    }).length;
    return KSection(
      title: 'Joriy menyu marjasi',
      icon: Icons.price_check_rounded,
      iconColor: losing > 0 ? AppColors.danger : AppColors.success,
      trailing: Text(
        '$losing zarar · $incomplete to‘liq emas',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        const SizedBox(height: 8),
        if (_productMargins.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Retseptli mahsulotlar yo‘q',
              style: TextStyle(color: AppColors.textMuted),
            ),
          )
        else
          for (final product in _productMargins.take(12)) _marginRow(product),
        if (_productMargins.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Eng past marjali 12 ta mahsulot ko‘rsatildi.',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _marginRow(dynamic product) {
    final profit = _int(product['profit']);
    final percent = _int(product['profit_percent']);
    final incomplete = product['incomplete'] == true;
    final color = _profitColor(percent);
    return InkWell(
      onTap: incomplete ? () => _showMissingIngredients(product) : null,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Icon(
              profit < 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product['name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (incomplete) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    'Tannarx ${formatMoney(product['piece_cost'], suffix: ' so‘m')} · '
                    'Narx ${formatMoney(product['price'], suffix: ' so‘m')}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percent%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 105,
              child: Text(
                formatMoney(profit, suffix: ' so‘m'),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMissingIngredients(dynamic product) {
    final missing = _list(
      product['missing_ingredients'],
    ).map((item) => item.toString()).toList();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product['name']?.toString() ?? 'Mahsulot'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quyidagi ingredientlar narxi kiritilmagan:',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              if (missing.isEmpty)
                const Text('Narx ma’lumoti to‘liq emas')
              else
                for (final name in missing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.money_off_rounded,
                          color: AppColors.danger,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Text(name),
                      ],
                    ),
                  ),
              const SizedBox(height: 10),
              const Text(
                'Bozor bo‘limida xarid narxi kiritilgach tannarx '
                'avtomatik yangilanadi.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
  }

  Color _profitColor(int percent) {
    if (percent < 0) return _darkRed;
    if (percent < 15) return AppColors.danger;
    if (percent < 30) return AppColors.warning;
    return AppColors.success;
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.points});

  final List<Map<String, dynamic>> points;

  @override
  Widget build(BuildContext context) {
    final sampled = _sampleTrend(points, 18);
    final maxValue = sampled.fold<int>(
      0,
      (max, point) =>
          _int(point['revenue']) > max ? _int(point['revenue']) : max,
    );
    return KSection(
      title: 'Kunlik tushum va sof foyda',
      icon: Icons.stacked_bar_chart_rounded,
      iconColor: AppColors.info,
      children: [
        const SizedBox(height: 12),
        if (sampled.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: Text('Sotuv ma’lumoti yo‘q')),
          )
        else
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in sampled)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${point['date']}\nTushum: ${formatMoney(point['revenue'], suffix: ' so‘m')}\n'
                          'Sof foyda: ${formatMoney(point['net_profit'], suffix: ' so‘m')}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              _compactMoney(point['revenue']),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(
                                color: AppColors.textFaint,
                                fontSize: 8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: maxValue <= 0
                                  ? 3.0
                                  : 118.0 * _int(point['revenue']) / maxValue +
                                        3.0,
                              decoration: BoxDecoration(
                                color: _int(point['net_profit']) >= 0
                                    ? AppColors.info
                                    : AppColors.danger,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _shortTrendDate(point['date']),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _LegendDot(color: AppColors.info, text: 'Foydali kun'),
            SizedBox(width: 12),
            _LegendDot(color: AppColors.danger, text: 'Zararli kun'),
          ],
        ),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.keyName,
    required this.valueName,
    required this.label,
    this.showCount = false,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> items;
  final String keyName;
  final String valueName;
  final String Function(String) label;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<int>(
      0,
      (max, item) => _int(item[valueName]) > max ? _int(item[valueName]) : max,
    );
    return KSection(
      title: title,
      icon: icon,
      iconColor: color,
      children: [
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                'Ma’lumot yo‘q',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label(item[keyName]?.toString() ?? ''),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (showCount)
                        Text(
                          '${_int(item['count'])} ta · ',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      Text(
                        formatMoney(item[valueName], suffix: ' so‘m'),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: maxValue <= 0
                          ? 0
                          : _int(item[valueName]) / maxValue,
                      backgroundColor: AppColors.surfaceAlt,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return KSection(
      title: 'Eng ko‘p sotilgan mahsulotlar',
      icon: Icons.emoji_events_rounded,
      iconColor: AppColors.warning,
      children: [
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('Sotuvlar yo‘q')),
          )
        else
          for (var index = 0; index < items.take(10).length; index++)
            _ProductSaleRow(index: index, item: items[index]),
      ],
    );
  }
}

class _ProductSaleRow extends StatelessWidget {
  const _ProductSaleRow({required this.index, required this.item});

  final int index;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final profit = _int(item['profit']);
    final incomplete = item['incomplete'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: index < 3 ? AppColors.warningTint : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: index < 3 ? AppColors.warning : AppColors.textMuted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (incomplete) ...[
                      const SizedBox(width: 5),
                      const Tooltip(
                        message: 'Tannarx to‘liq emas',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${_int(item['quantity'])} dona · '
                  '${formatMoney(item['revenue'], suffix: ' so‘m')} tushum',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(profit, suffix: ' so‘m'),
                style: TextStyle(
                  color: profit >= 0 ? AppColors.success : AppColors.danger,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              Text(
                '${_int(item['profit_percent'])}%',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return KSection(
      title: 'Kategoriyalar',
      icon: Icons.category_rounded,
      iconColor: const Color(0xFF7C3AED),
      children: [
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: Text('Ma’lumot yo‘q')),
          )
        else
          for (final item in items.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const IconAvatar(
                icon: Icons.restaurant_menu_rounded,
                color: Color(0xFF7C3AED),
                size: 34,
              ),
              title: Text(
                item['name']?.toString() ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${_int(item['quantity'])} dona',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: Text(
                formatMoney(item['revenue'], suffix: ' so‘m'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      ],
    );
  }
}

class _PeakHoursCard extends StatelessWidget {
  const _PeakHoursCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return KSection(
      title: 'Tig‘iz soatlar',
      icon: Icons.schedule_rounded,
      iconColor: AppColors.info,
      children: [
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: Text('Ma’lumot yo‘q')),
          )
        else
          for (final item in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.infoSoft,
                child: Text(
                  _int(item['hour']).toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: AppColors.info,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              title: Text(
                '${_int(item['hour']).toString().padLeft(2, '0')}:00 — '
                '${(_int(item['hour']) + 1).toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${_int(item['orders'])} ta chek',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: Text(
                formatMoney(item['revenue'], suffix: ' so‘m'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
      ],
    );
  }
}

class _MiniGrid extends StatelessWidget {
  const _MiniGrid({required this.items});

  final List<(String, int)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              Container(
                width: width,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.$2}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.$1,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CostWarning extends StatelessWidget {
  const _CostWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ta sotilgan mahsulot tannarxi to‘liq emas. '
              'Sof foyda taxminiy va asl qiymatdan yuqori ko‘rinishi mumkin.',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.danger,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          IconButton(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Qayta urinish',
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
      ],
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _apiDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

String _displayDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}';
}

String _shortTrendDate(dynamic value) {
  final parts = value?.toString().split('-') ?? [];
  if (parts.length != 3) return '';
  return '${parts[2]}.${parts[1]}';
}

String _compactMoney(dynamic value) {
  final amount = _int(value);
  if (amount.abs() >= 1000000000) {
    return '${(amount / 1000000000).toStringAsFixed(1)} mlrd';
  }
  if (amount.abs() >= 1000000) {
    return '${(amount / 1000000).toStringAsFixed(1)} mln';
  }
  if (amount.abs() >= 1000) {
    return '${(amount / 1000).toStringAsFixed(0)}k';
  }
  return '$amount';
}

List<Map<String, dynamic>> _sampleTrend(
  List<Map<String, dynamic>> points,
  int limit,
) {
  if (points.length <= limit) return points;
  final sampled = <Map<String, dynamic>>[];
  for (var index = 0; index < limit; index++) {
    final source = (index * (points.length - 1) / (limit - 1)).round();
    sampled.add(points[source]);
  }
  return sampled;
}

String _orderTypeLabel(String value) => switch (value) {
  'dine_in' => 'Zalda',
  'takeaway' => 'Olib ketish',
  'delivery' => 'Yetkazib berish',
  _ => value.isEmpty ? 'Boshqa' : value,
};

String _paymentLabel(String value) => paymentLabel(value);

String _sourceLabel(String value) => switch (value) {
  'pos' => 'POS',
  'qr' => 'QR mijoz',
  'online' => 'Onlayn',
  _ => value.isEmpty ? 'Boshqa' : value,
};

String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Server bilan aloqa yo‘q';
    }
  }
  return error is StateError ? error.message.toString() : 'Ma’lumot olinmadi';
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<dynamic> _list(dynamic value) => value is List ? value : [];

List<Map<String, dynamic>> _maps(dynamic value) =>
    _list(value).map(_map).toList();

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
