import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';

class KitchenTab extends StatefulWidget {
  const KitchenTab({super.key});
  @override
  State<KitchenTab> createState() => _KitchenTabState();
}

class _KitchenTabState extends State<KitchenTab> {
  List<dynamic> _orders = [];
  bool _loading = true;
  StreamSubscription? _wssSub;
  final Set<String> _servedItems = {};

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen((e) {
      final ev = e['event'];
      if (ev == 'order:new' ||
          ev == 'order:items_added' ||
          ev == 'order:closed' ||
          ev == 'order:updated') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await ApiService().getOrders(status: 'active');
      if (mounted) {
        setState(() {
          _orders = o;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _buildKitchenItems() {
    final items = <Map<String, dynamic>>[];

    for (final order in _orders) {
      final orderNum = order['order_number'] ?? '';
      final tableSKU = order['table_sku'] ?? '';
      final orderItems = order['items'] as List<dynamic>? ?? [];
      final createdAt = order['created_at'] ?? '';
      final orderType = order['type'] ?? '';

      String tableLabel;
      if (orderType == 'takeaway') {
        tableLabel = 'SABOY';
      } else if (orderType == 'delivery') {
        tableLabel = 'DOSTAFKA';
      } else {
        tableLabel = tableSKU.toString().replaceAll('-', '-STOL-');
        if (tableLabel.isEmpty) tableLabel = '???';
      }

      for (final item in orderItems) {
        final snap = item['snapshot'] as Map<String, dynamic>? ?? {};
        final nameMap = snap['name'] as Map<String, dynamic>? ?? {};
        final name = menuName(nameMap, fallback: '?');
        final qty = item['quantity'] ?? 1;
        final itemId = item['id'] ?? 0;
        final uniqueKey = '$orderNum-$itemId';

        items.add({
          'key': uniqueKey,
          'order_number': orderNum,
          'table_sku': tableSKU,
          'table_label': tableLabel,
          'order_type': orderType,
          'name': name,
          'quantity': qty,
          'created_at': createdAt,
          'served': _servedItems.contains(uniqueKey),
          'note': item['note'],
        });
      }
    }

    items.sort((a, b) {
      if (a['served'] != b['served']) return a['served'] ? 1 : -1;
      return (a['created_at'] as String).compareTo(b['created_at'] as String);
    });

    return items;
  }

  void _toggleServed(String key) {
    setState(() {
      if (_servedItems.contains(key)) {
        _servedItems.remove(key);
      } else {
        _servedItems.add(key);
      }
    });
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'takeaway':
        return AppColors.warning;
      case 'delivery':
        return AppColors.success;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final items = _buildKitchenItems();
    final pendingItems = items.where((i) => !i['served']).toList();
    final servedItems = items.where((i) => i['served']).toList();

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.restaurant_rounded,
        title: 'Tayyorlanadigan buyurtma yo\'q',
        subtitle: 'Yangi buyurtmalar shu yerda paydo bo\'ladi',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (pendingItems.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.local_fire_department_rounded,
              color: AppColors.danger,
              label: 'Tayyorlanishi kerak',
              count: pendingItems.length,
            ),
            const SizedBox(height: 8),
            ...pendingItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildItemCard(item, false),
                )),
          ],
          if (servedItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionHeader(
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
              label: 'Berildi',
              count: servedItems.length,
            ),
            const SizedBox(height: 8),
            ...servedItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildItemCard(item, true),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, bool served) {
    final tableLabel = item['table_label'] ?? '';
    final name = item['name'] ?? '';
    final qty = item['quantity'] ?? 1;
    final note = item['note'];
    final key = item['key'] as String;
    final color = _typeColor(item['order_type'] ?? '');

    return Material(
      color: served ? AppColors.successSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _toggleServed(key),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: served
                  ? AppColors.success.withValues(alpha: 0.25)
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 44,
                decoration: BoxDecoration(
                  color: served ? AppColors.success : AppColors.danger,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            tableLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '$qty ta',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        decoration: served
                            ? TextDecoration.lineThrough
                            : null,
                        color: served
                            ? AppColors.textFaint
                            : AppColors.text,
                      ),
                    ),
                    if (note != null &&
                        note.toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          note.toString(),
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  served
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: served ? AppColors.success : AppColors.textFaint,
                  size: 28,
                ),
                onPressed: () => _toggleServed(key),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        StatusBadge(label: '$count', color: color, fontSize: 10),
      ],
    );
  }
}
