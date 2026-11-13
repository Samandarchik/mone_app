import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';
import '../../../core/utils/business_day.dart';
import '../../../core/utils/order_number.dart';
import '../../../core/utils/payment_label.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;
  String _filter = 'all'; // all, completed, cancelled, active
  /// Tarix oynasi QAYERDAN boshlanadi. Defolt — bugungi ish kunining
  /// boshlanishi (02:00), ya'ni avvalgi xatti-harakat. Sana oynasida soat
  /// almashtirilsa ro'yxat shu vaqtdan keyingi 24 soatni ko'rsatadi.
  DateTime _windowStart = businessTodayStart();

  /// Chek raqami / stol / mijoz bo'yicha mahalliy qidiruv.
  String _query = '';

  List<dynamic> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _orders;
    return _orders.where((o) {
      // Ham asl, ham qisqartirilgan raqam bo'yicha qidiriladi: ekranda
      // «P22» ko'ringan eski chekning bazadagi raqami «P000022».
      final rawNum = (o['order_number'] ?? '').toString().toLowerCase();
      final shortNum = shortOrderNumber(o['order_number']).toLowerCase();
      final table = (o['table_label'] ?? o['table_sku'] ?? '')
          .toString()
          .toLowerCase();
      final zone = (o['zone_name'] ?? '').toString().toLowerCase();
      final waiter = (o['waiter_name'] ?? '').toString().toLowerCase();
      final customer = (o['customer_name'] ?? '').toString().toLowerCase();
      return rawNum.contains(q) ||
          shortNum.contains(q) ||
          table.contains(q) ||
          zone.contains(q) ||
          waiter.contains(q) ||
          customer.contains(q);
    }).toList();
  }

  /// Chek ichidagi mahsulotlar — ro'yxatda «1 ta mahsulot» emas, nomlarning
  /// o'zi ko'rinadi. HAR BIRI ALOHIDA QATORDA:
  ///
  ///     2 × Вишнёвая Милка
  ///     2 × Дубайская Матильда
  ///
  /// Bitta qatorga vergul bilan tizib qo'yilsa uzun nomlar bir-biriga
  /// qo'shilib ketib o'qib bo'lmasdi. Bekor qilingan qatorlar (miqdori 0)
  /// tashlanadi, uzun cheklarda esa faqat dastlabki 3 tasi ko'rinadi.
  static const int _maxItemLines = 3;

  String _itemsSummary(dynamic o) {
    final items = o['items'] as List<dynamic>? ?? [];
    final parts = <String>[];
    for (final it in items) {
      if (it is! Map) continue;
      final snap = it['snapshot'] as Map<String, dynamic>? ?? {};
      final name = menuName(snap['name']);
      if (name.isEmpty) continue;
      final qty = it['quantity'] as int? ?? 0;
      if (qty == 0) continue;
      parts.add(qty > 1 ? '$qty × $name' : name);
    }
    if (parts.isEmpty) return '${items.length} ta mahsulot';
    if (parts.length > _maxItemLines) {
      final rest = parts.length - _maxItemLines;
      return [...parts.take(_maxItemLines), '+$rest ta yana'].join('\n');
    }
    return parts.join('\n');
  }

  /// Chek qaysi stolniki — o'qiladigan nom. Stol bo'lmasa (saboy/dostafka)
  /// buyurtma turi qaytadi.
  String _tableLabel(dynamic o) {
    final label = (o['table_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    final sku = (o['table_sku'] ?? '').toString().trim();
    if (sku.isNotEmpty) return sku;
    return _typeLabel(o['type'] as String?);
  }

  /// Cheklarni stol bo'yicha guruhlash. Stolsiz cheklar (saboy, dostafka)
  /// turi bo'yicha bitta guruhga yig'iladi.
  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _windowEnd => _windowStart.add(const Duration(days: 1));

  /// Boshlanish defolt 02:00 danmi? Shunday bo'lsa hech nima o'zgarmaydi:
  /// bitta so'rov, serverning ish kuni oynasi, mahalliy filtr yo'q.
  bool get _customWindow =>
      _windowStart.hour != kBusinessDayStartHour || _windowStart.minute != 0;

  /// Oyna boshlangan KALENDAR sana — chek raqamini qisqartirishda ishlatiladi.
  String get _dateStr => ymd(_windowStart);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 02:00 dan boshqa soat tanlansa oyna ikkita ish kuniga bo'linadi
      // (masalan 10:00 → ertasi 10:00) — ikkala kun olinib, oynadan
      // tashqaridagi cheklar tashlanadi.
      final dates = businessDatesForWindow(_windowStart, _windowEnd);
      final lists = await Future.wait(
        dates.map((d) => ApiService().getOrders(status: _filter, date: d)),
      );
      final merged = <dynamic>[];
      for (final l in lists) {
        merged.addAll(l);
      }
      final o = _customWindow
          ? merged.where((order) {
              final t = parseServerTime(order['created_at']);
              if (t == null) return true;
              return !t.isBefore(_windowStart) && t.isBefore(_windowEnd);
            }).toList()
          : merged;
      if (lists.length > 1) {
        // Ikki kunlik ro'yxat qo'shilgani uchun tartib qayta tiklanadi.
        o.sort((a, b) => (b['created_at'] ?? '')
            .toString()
            .compareTo((a['created_at'] ?? '').toString()));
      }
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

  /// Ro'yxatda chek raqami QISQA ko'rinadi: «26-08-22-P000003» → «№3».
  /// Sana allaqachon tepadagi filtrda turibdi, shuning uchun uzun prefiks
  /// faqat qatorni o'qishga xalaqit berardi. To'liq raqam tafsilotda qoladi.
  ///
  /// ISTISNO: raqamdagi sana tanlangan ish kunidan farq qilsa — qisqartma
  /// qo'shiladi («№3 · 22-08»). Ish kuni qoidasidan OLDIN yaratilgan
  /// cheklarda yarim tundan keyingi savdo yangi sana bilan raqamlangan; ular
  /// endi kechagi kunda ko'rinadi va aks holda o'sha kunning o'z №3 si bilan
  /// bir xil bo'lib qolardi.
  String _displayOrderNum(dynamic orderNumber) {
    final s = orderNumber?.toString() ?? '';
    if (s.isEmpty) return '';
    final m = RegExp(r'(\d+)$').firstMatch(s);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null) {
        final d = RegExp(r'(\d{2})-(\d{2})-(\d{2})-').firstMatch(s);
        if (d != null) {
          final numDate = '20${d.group(1)}-${d.group(2)}-${d.group(3)}';
          if (numDate != _dateStr) return '№$n · ${d.group(3)}-${d.group(2)}';
        }
        return '№$n';
      }
    }
    // Raqam bilan tugamasa — hech bo'lmasa yil prefiksini olib tashlaymiz.
    final firstDash = s.indexOf('-');
    if (firstDash == 2 || firstDash == 4) {
      return s.substring(firstDash + 1);
    }
    return s;
  }

  String _time(String? t) =>
      (t != null && t.length >= 16) ? t.substring(11, 16) : '';

  String _typeLabel(String? t) =>
      const {
        'dine_in': 'Restoran',
        'takeaway': 'Saboy',
        'delivery': 'Dostafka',
      }[t ?? ''] ??
      (t ?? '');

  Color _typeColor(String? t) {
    switch (t) {
      case 'dine_in':
        return AppColors.info;
      case 'takeaway':
        return AppColors.warning;
      case 'delivery':
        return AppColors.success;
      default:
        return AppColors.textFaint;
    }
  }

  IconData _typeIconData(String? t) {
    switch (t) {
      case 'dine_in':
        return Icons.table_restaurant_rounded;
      case 'takeaway':
        return Icons.takeout_dining_rounded;
      case 'delivery':
        return Icons.delivery_dining_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  int get _totalSum {
    int sum = 0;
    for (final o in _orders) {
      if (o['status'] != 'cancelled') {
        sum += (o['total'] as int? ?? 0);
      }
    }
    return sum;
  }

  void _showDetail(Map<String, dynamic> o) {
    final items = o['items'] as List<dynamic>? ?? [];
    final type = o['type'] as String? ?? '';
    final color = _typeColor(type);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Container(
          width: 460,
          constraints: const BoxConstraints(maxHeight: 560),
          color: AppColors.surface,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.12),
                      color.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconAvatar(icon: _typeIconData(type), color: color),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shortOrderNumber(o['order_number']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            Text(
                              _typeLabel(type),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (_time(o['created_at']).isNotEmpty)
                          StatusBadge(
                            label: _time(o['created_at']),
                            color: AppColors.textMuted,
                            icon: Icons.schedule_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (o['table_sku'] != null)
                          _MetaChip(
                              icon: Icons.table_restaurant_rounded,
                              label: (o['zone_name'] ?? '')
                                      .toString()
                                      .isNotEmpty
                                  ? '${_tableLabel(o)} · ${o['zone_name']}'
                                  : _tableLabel(o)),
                        if ((o['waiter_name'] ?? '').toString().isNotEmpty)
                          _MetaChip(
                              icon: Icons.person_rounded,
                              label: o['waiter_name']),
                        if (o['payment_method'] != null)
                          _MetaChip(
                              icon: Icons.payments_rounded,
                              label: paymentLabel(o['payment_method']?.toString())),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 14, color: AppColors.borderSoft),
                  itemBuilder: (ctx, i) {
                    final item = items[i] as Map<String, dynamic>;
                    final snap =
                        item['snapshot'] as Map<String, dynamic>? ?? {};
                    final nameMap =
                        snap['name'] as Map<String, dynamic>? ?? {};
                    final qty = item['quantity'] as int? ?? 0;
                    final cancelledQty = item['cancelled_qty'] as int? ?? 0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: qty == 0
                                ? AppColors.dangerSoft
                                : AppColors.primarySoft,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '${qty}x',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: qty == 0
                                  ? AppColors.danger
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                menuName(nameMap, fallback: '?'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  decoration: qty == 0
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: qty == 0
                                      ? AppColors.textFaint
                                      : AppColors.text,
                                ),
                              ),
                              if (cancelledQty > 0)
                                Text(
                                  '$cancelledQty ta bekor qilingan',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.danger,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(item['total'], suffix: ' so\'m'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceAlt,
                  border: Border(
                      top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Jami',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted),
                    ),
                    Text(
                      formatMoney(o['total'], suffix: ' so\'m'),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return AdminPage(
      subtitle: '${list.length} ta chek · '
          '${formatMoney(_totalSum, suffix: ' so‘m')}',
      loading: _loading,
      onRefresh: _load,
      onSearchChanged: (v) => setState(() => _query = v),
      searchHint: 'Chek raqami, stol, ofitsiant yoki mijoz…',
      toolbar: Column(
        children: [
          AdminDateBar(
            date: _windowStart,
            withTime: true,
            onChanged: (d) {
              _windowStart = d;
              _load();
            },
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('Hammasi', 'all'),
                _filterChip('Aktiv', 'active'),
                _filterChip('Yopilgan', 'completed'),
                _filterChip('Bekor', 'cancelled'),
              ],
            ),
          ),
        ],
      ),
      child: list.isEmpty
          ? AdminEmpty(
              icon: Icons.table_restaurant_outlined,
              title: _query.isEmpty ? 'Buyurtma yo‘q' : 'Topilmadi',
              message: _query.isEmpty
                  ? 'Tanlangan kunda bu holatdagi chek yo‘q. '
                      'Sanani yoki filtrni o‘zgartiring.'
                  : 'Boshqa raqam bilan qidirib ko‘ring.',
              color: AppColors.info,
            )
          : _ordersList(list),
    );
  }

  // ============================================================
  // Stollar bo'yicha ko'rinish
  // ============================================================

  // ============================================================
  // Cheklar ro'yxati — Poster uslubida YASSI: har chek alohida qator,
  // sarlavhasida «№19 · Stol 1». Guruh/akkordeon YO'Q — kassir ochib
  // o'tirmaydi, hammasi bir qarashda ko'rinadi.
  // ============================================================

  Widget _ordersList(List<dynamic> list) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _orderCard(list[i]),
    );
  }

  Widget _orderCard(dynamic o) {
    final type = o['type'] as String? ?? '';
    final status = o['status'] as String? ?? '';
    final isCancelled = status == 'cancelled';
    final isOpen = !isCancelled && status != 'completed';
    final color = isCancelled ? AppColors.danger : _typeColor(type);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => _showDetail(o as Map<String, dynamic>),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isOpen
                  ? AppColors.success.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconAvatar(icon: _typeIconData(type), color: color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster'dagi «№ 7420, Стол 1» kabi: raqam + stol birga.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_displayOrderNum(o['order_number'])} · ${_tableLabel(o)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: isCancelled
                                ? AppColors.textFaint
                                : AppColors.text,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          _time(o['created_at']),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textFaint,
                          ),
                        ),
                        if (isOpen)
                          const StatusBadge(
                            label: 'Ochiq',
                            color: AppColors.success,
                          ),
                        if (isCancelled)
                          const StatusBadge(
                            label: 'Bekor',
                            color: AppColors.danger,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _itemsSummary(o),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(o['total'], suffix: ' so\'m'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: isCancelled ? AppColors.textFaint : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () {
          setState(() => _filter = value);
          _load();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? Colors.white : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
