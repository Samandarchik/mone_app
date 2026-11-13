import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/business_day.dart';
import '../../../core/utils/order_number.dart';
import '../../../core/utils/payment_label.dart';
import '../../../core/utils/search_fold.dart';
import '../../../core/widgets/other_payment_comment_dialog.dart';
import '../../admin/widgets/admin_page.dart';
import '../../admin/widgets/admin_widgets.dart';

class OrdersPanel extends StatefulWidget {
  const OrdersPanel({super.key});
  @override
  State<OrdersPanel> createState() => _OrdersPanelState();
}

class _OrdersPanelState extends State<OrdersPanel> {
  List<dynamic> _orders = [];
  bool _loading = true;
  bool _showHistory = false;
  List<dynamic> _historyOrders = [];
  bool _historyLoading = false;
  StreamSubscription? _wssSub;

  /// Tarix filtri: 0 hammasi, 1 ZAL, 2 TASHQARI, 3 Saboy, 4 Dostafka.
  int _typeFilter = 0;
  static const _typeFilters = [
    'Hammasi',
    'ZAL',
    'TASHQARI',
    'Saboy',
    'Dostafka',
  ];

  /// Qidiruv (chek raqami, stol, mahsulot, mijoz) — kirill/lotin farqsiz.
  String _query = '';

  /// Tarix oynasi QAYERDAN boshlanadi. Defolt — bugungi ish kunining
  /// boshlanishi (02:00), ya'ni avvalgi xatti-harakat. Foydalanuvchi sana
  /// oynasida soatni o'zgartirsa (masalan 10:00) ro'yxat shu vaqtdan
  /// keyingi 24 soatni ko'rsatadi.
  DateTime _windowStart = businessTodayStart();

  DateTime get _windowEnd => _windowStart.add(const Duration(days: 1));

  /// Boshlanish defolt 02:00 danmi? Shunday bo'lsa hech nima o'zgarmaydi:
  /// bitta so'rov, serverning ish kuni oynasi, mahalliy filtr yo'q.
  bool get _customWindow =>
      _windowStart.hour != kBusinessDayStartHour || _windowStart.minute != 0;

  /// Oyna boshlangan KALENDAR sana — chek raqamini qisqartirishda ishlatiladi.
  String get _dateStr => ymd(_windowStart);

  /// Chek shu oynaga tushadimi (faqat soat almashtirilgan bo'lsa tekshiriladi).
  bool _inWindow(dynamic o) {
    if (!_customWindow) return true;
    final t = parseServerTime(o['created_at']);
    if (t == null) return true;
    return !t.isBefore(_windowStart) && t.isBefore(_windowEnd);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen((e) {
      final ev = e['event'];
      if (ev == 'order:new' || ev == 'order:updated' || ev == 'order:closed') {
        _load();
        // Tarix ochiq turgan bo'lsa u ham jonli yangilanadi (masalan, boshqa
        // kassada to'lov usuli o'zgartirilsa).
        if (_showHistory) _loadHistory();
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
      final o = await ApiService().getOrders();
      final filtered = o.where((order) {
        final type = order['type'] as String? ?? '';
        return type == 'takeaway' || type == 'delivery';
      }).toList();
      if (mounted) {
        setState(() {
          _orders = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    try {
      // 02:00 dan boshqa soat tanlansa oyna ikkita ish kuniga bo'linadi
      // (masalan 10:00 → ertasi 10:00), shuning uchun ikkala kun olinadi
      // va oynadan tashqaridagilar tashlanadi.
      final dates = businessDatesForWindow(_windowStart, _windowEnd);
      final lists = await Future.wait(
        dates.map((d) => ApiService().getOrders(status: 'all', date: d)),
      );
      final merged = <dynamic>[];
      for (final l in lists) {
        merged.addAll(l);
      }
      final filtered = merged.where((order) {
        final s = order['status'] as String? ?? '';
        if (s != 'completed' && s != 'cancelled') return false;
        return _inWindow(order);
      }).toList();
      if (lists.length > 1) {
        // Ikki kunlik ro'yxat qo'shilgani uchun tartib qayta tiklanadi:
        // yangisi tepada.
        filtered.sort(
          (a, b) => (b['created_at'] ?? '').toString().compareTo(
            (a['created_at'] ?? '').toString(),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _historyOrders = filtered;
          _historyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  /// Stol SKU'sidan zona raqami: «2-4» ham, «Z2-4» ham bo'lishi mumkin.
  /// Stollar ikki xil davrda yaratilgani uchun bazada ikkala format bor —
  /// ilgari faqat «2-» tekshirilardi va yangi stollardagi cheklar (jumladan
  /// QR orqali tushganlari) tarixda umuman ko'rinmasdi.
  static int? _zoneOfSku(String sku) {
    final m = RegExp(r'^Z?(\d+)-').firstMatch(sku);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// Tarix: toifa filtri + qidiruv.
  List<dynamic> get _filteredHistory => _historyOrders
      .where((o) => _matchesType(o as Map<String, dynamic>) && _matchesQuery(o))
      .toList();

  /// Aktiv (saboy/dostafka): faqat qidiruv — toifa filtri tarixniki.
  List<dynamic> get _filteredActive =>
      _orders.where((o) => _matchesQuery(o as Map<String, dynamic>)).toList();

  bool _matchesType(Map<String, dynamic> o) {
    final type = o['type'] as String? ?? '';
    final sku = o['table_sku'] as String? ?? '';
    switch (_typeFilter) {
      case 1:
        return type == 'dine_in' && _zoneOfSku(sku) == 1;
      case 2:
        return type == 'dine_in' && _zoneOfSku(sku) == 2;
      case 3:
        return type == 'takeaway';
      case 4:
        return type == 'delivery';
      default:
        return true;
    }
  }

  /// Chek raqami, stol, zona, mijoz, to'lov usuli va MAHSULOT NOMLARI
  /// bo'yicha qidiriladi. `searchFold` tufayli «choy» ham, «чой» ham topadi.
  bool _matchesQuery(Map<String, dynamic> o) {
    final q = searchFold(_query);
    if (q.isEmpty) return true;
    final buf = StringBuffer()
      ..write(o['order_number'] ?? '')
      ..write(' ')
      ..write(shortOrderNumber(o['order_number']))
      ..write(' ')
      ..write(o['table_label'] ?? '')
      ..write(' ')
      ..write(o['table_sku'] ?? '')
      ..write(' ')
      ..write(o['zone_name'] ?? '')
      ..write(' ')
      ..write(o['customer_name'] ?? '')
      ..write(' ')
      ..write(o['customer_phone'] ?? '')
      ..write(' ')
      ..write(_payLabel(o['payment_method']?.toString()));
    for (final it in (o['items'] as List<dynamic>? ?? [])) {
      if (it is! Map) continue;
      final snap = it['snapshot'] as Map<String, dynamic>? ?? {};
      buf.write(' ${menuName(snap['name'])}');
    }
    return searchFold(buf.toString()).contains(q);
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'delivery':
        return Icons.delivery_dining_rounded;
      case 'takeaway':
        return Icons.takeout_dining_rounded;
      default:
        return Icons.table_restaurant_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'delivery':
        return AppColors.success;
      case 'takeaway':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'delivery':
        return 'Dostafka';
      case 'takeaway':
        return 'Saboy';
      default:
        return 'Restoran';
    }
  }

  // ---- Yandex Eda cheklari ----
  //
  // Yandexdan tushgan zakaz oddiy dostafka cheki bo'lib keladi
  // (`type='delivery'`), shuning uchun manbani AYTIB turish shart: kassir
  // mijozga o'zi qo'ng'iroq qilmasin va pulni qayta olmasin — Yandex zakazi
  // allaqachon to'langan, kuryerni ham Yandex yuboradi.
  static bool _isYandex(Map<String, dynamic> o) => o['source'] == 'yandex';

  Color _srcColor(Map<String, dynamic> o) =>
      _isYandex(o) ? kYandexColor : _typeColor(o['type'] as String? ?? '');

  String _srcLabel(Map<String, dynamic> o) =>
      _isYandex(o) ? 'Yandex Eda' : _typeLabel(o['type'] as String? ?? '');

  /// To'lov usullari — yopilgan chekda keyin almashtirish mumkin bo'lganlari
  /// (asoschilar qilinadigan_ishlar'dan — qarang kPaymentMethods).
  static List<(String, String, IconData)> get _payMethods =>
      [for (final m in kPaymentMethods) (m.$1, m.$2, m.$3)];

  /// «2026-08-21T18:50:12+05:00» → «18:50».
  static String _hhmm(dynamic ts) {
    final s = ts?.toString() ?? '';
    return s.length >= 16 ? s.substring(11, 16) : '';
  }

  /// To'lov (yopilish) vaqti — yopilgan chekda `updated_at` aynan shu:
  /// server chek yopilganda uni NOW() qiladi. Ochiq/bekor chekda ko'rsatilmaydi.
  static String _paidTime(Map<String, dynamic> o) {
    if (o['status'] != 'completed') return '';
    return _hhmm(o['updated_at']);
  }

  /// Chek holati — bazadagi kalit emas, o'qiladigan nom.
  static String _statusLabel(String? s) => switch (s) {
    'completed' => 'Yopilgan',
    'cancelled' => 'Bekor',
    'new' => 'Yangi',
    'preparing' => 'Tayyorlanmoqda',
    'ready' => 'Tayyor',
    'delivered' => 'Yuborildi',
    _ => s ?? '',
  };

  static Color _statusColor(String? s) => switch (s) {
    'completed' => AppColors.success,
    'cancelled' => AppColors.danger,
    'new' => AppColors.danger,
    'preparing' => AppColors.warning,
    'ready' => AppColors.success,
    'delivered' => AppColors.info,
    _ => AppColors.textMuted,
  };

  static String _payLabel(String? m) =>
      (m == null || m.isEmpty) ? '' : paymentLabel(m);


  /// Yopilgan chekni qaytarish mumkinmi: faqat smena OCHIQ bo'lsa va chek
  /// shu smenada ochilgan bo'lsa (server ham xuddi shuni tekshiradi —
  /// yopilgan smenaning hisoboti muzlatilgan, unga tegib bo'lmaydi).
  bool _canRevert(Map<String, dynamic> o) {
    if (o['status'] != 'completed') return false;
    final shift = AppState().shift;
    if (shift?['status'] != 'open') return false;
    final openedAt = DateTime.tryParse(shift?['opened_at']?.toString() ?? '');
    final createdAt = DateTime.tryParse(o['created_at']?.toString() ?? '');
    if (openedAt != null && createdAt != null && createdAt.isBefore(openedAt)) {
      return false;
    }
    return true;
  }

  void _showOrderDetail(Map<String, dynamic> o) {
    final items = o['items'] as List<dynamic>? ?? [];
    final createdAt = o['created_at'] ?? '';
    String timeStr = createdAt.length >= 16 ? createdAt.substring(11, 16) : '';
    final type = o['type'] ?? '';
    final color = _srcColor(o);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          // Mahsulot soniga qarab: bitta qatorli chek uchun ham
          // ekranning 85% i ochilib, yarmi bo'sh qolardi
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppRadius.xxl),
              topRight: Radius.circular(AppRadius.xxl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                        IconAvatar(icon: _typeIcon(type), color: color),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${shortOrderNumber(o['order_number'])}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            Text(
                              _srcLabel(o),
                              style: TextStyle(
                                color: _isYandex(o)
                                    ? kYandexColor
                                    : AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: _isYandex(o)
                                    ? FontWeight.w800
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        StatusBadge(
                          label: _statusLabel(o['status']?.toString()),
                          color: _statusColor(o['status']?.toString()),
                        ),
                      ],
                    ),
                    if (timeStr.isNotEmpty ||
                        o['payment_method'] != null ||
                        o['customer_name'] != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (timeStr.isNotEmpty)
                            KMetaChip(
                              icon: Icons.schedule_rounded,
                              label: 'Ochilgan $timeStr',
                            ),
                          if (_paidTime(o).isNotEmpty)
                            KMetaChip(
                              icon: Icons.check_circle_rounded,
                              label: 'To\'langan ${_paidTime(o)}',
                            ),
                          if (o['payment_method'] != null)
                            KMetaChip(
                              icon: Icons.payment_rounded,
                              label: _payLabel(o['payment_method']?.toString()),
                            ),
                          if (o['table_sku'] != null)
                            KMetaChip(
                              icon: Icons.table_restaurant_rounded,
                              label: o['table_sku'],
                            ),
                          if (o['customer_name'] != null)
                            KMetaChip(
                              icon: Icons.person_rounded,
                              label:
                                  '${o['customer_name']} ${o['customer_phone'] ?? ''}',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 16, color: AppColors.borderSoft),
                  itemBuilder: (ctx, i) {
                    final item = items[i] as Map<String, dynamic>;
                    final snap =
                        item['snapshot'] as Map<String, dynamic>? ?? {};
                    final nameMap = snap['name'] as Map<String, dynamic>? ?? {};
                    final addedBy =
                        item['added_by'] as Map<String, dynamic>? ?? {};
                    final addedAt = item['added_at'] ?? '';
                    String itemTime = addedAt.length >= 16
                        ? addedAt.substring(11, 16)
                        : '';

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '${item['quantity']}x',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Row(
                                children: [
                                  if ((addedBy['name'] ?? '').isNotEmpty)
                                    Text(
                                      addedBy['name'],
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textFaint,
                                      ),
                                    ),
                                  if (itemTime.isNotEmpty)
                                    Text(
                                      ' • $itemTime',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textFaint,
                                      ),
                                    ),
                                ],
                              ),
                              if (item['note'] != null &&
                                  item['note'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    item['note'].toString(),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(item['total'], suffix: ' so\'m'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
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
                    top: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Jami',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          formatMoney(o['total'], suffix: ' so\'m'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (_canRevert(o)) ...[
                      // To'lov usulini keyin almashtirish: kassir chekni
                      // adashib Click deb yopgan bo'lsa, shu yerdan Naqd/
                      // Payme'ga o'tkazadi. Shartlari revert bilan bir xil —
                      // faqat ochiq smenaning cheki (yopiq smena hisoboti
                      // muzlatilgan).
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'To\'lov usuli',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _payMethods.map((m) {
                          final selected =
                              (o['payment_method']?.toString() ?? '') == m.$1;
                          return InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: selected
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _changePayment(o, m.$1);
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.success
                                    : AppColors.surface,
                                border: Border.all(
                                  color: selected
                                      ? AppColors.success
                                      : AppColors.border,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    m.$3,
                                    size: 14,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    m.$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? Colors.white
                                          : AppColors.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _revertOrder(o['order_number']);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Chekni qaytarish'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const _statuses = [
    {'key': 'new', 'label': 'Yangi', 'color': AppColors.danger},
    {'key': 'preparing', 'label': 'Tayyorlanmoqda', 'color': AppColors.warning},
    {'key': 'ready', 'label': 'Tayyor', 'color': AppColors.success},
    {'key': 'delivered', 'label': 'Yuborildi', 'color': AppColors.info},
    {'key': 'cancelled', 'label': 'Bekor', 'color': AppColors.textFaint},
  ];

  Future<void> _updateStatus(String orderNumber, String newStatus) async {
    // BEKOR QILISH — alohida HTTP amali.
    //
    // Serverda bu endi `orders:cancel` ruxsatiga bog'langan (oshxona
    // ekrani kassaning chekini bekor qila olmasligi kerak). HTTP yo'li
    // WSS'dan ishonchliroq: javob keladi, xato ko'rinadi va tasdiq
    // so'raladi.
    if (newStatus == 'cancelled') {
      await _cancelOrder(orderNumber);
      return;
    }

    // `WssService.send` XATONI YUTADI (`catch (_) {}`) va socket uzilgan
    // bo'lsa hech narsa yubormaydi. Ilgari UI darhol yangi statusni
    // chizardi: kassir "Tayyor" deb belgilaydi, kuryer chaqiriladi, server
    // esa bu haqda hech qachon bilmaydi.
    if (!WssService().isConnected) {
      _toast('Aloqa yo‘q — status o‘zgartirilmadi', error: true);
      return;
    }
    WssService().send('order:update_status', {
      'order_number': orderNumber,
      'status': newStatus,
    });
    setState(() {
      for (var o in _orders) {
        if (o['order_number'] == orderNumber) {
          o['status'] = newStatus;
        }
      }
    });
  }

  /// Chekni bekor qilish — TASDIQ so'raladi.
  ///
  /// Ilgari "Bekor" chipi "Yangi / Tayyorlanmoqda / Tayyor / Yuborildi"
  /// bilan bitta qatorda turardi va bitta bosishda 400 000 so'mlik
  /// dostafkani izsiz bekor qilardi.
  Future<void> _cancelOrder(String orderNumber) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chekni bekor qilish'),
        content: Text(
          '$orderNumber bekor qilinsinmi?\n'
          'Mahsulotlar omborga qaytariladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo‘q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Bekor qilish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService().cancelOrder(orderNumber);
      if (!mounted) return;
      setState(() {
        _orders.removeWhere((o) => o['order_number'] == orderNumber);
      });
      _toast('Chek bekor qilindi');
    } catch (e) {
      var msg = 'Bekor qilinmadi';
      if (e is DioException && e.response?.data is Map) {
        msg = (e.response!.data as Map)['message']?.toString() ?? msg;
      }
      _toast(msg, error: true);
    }
  }

  bool _reverting = false;

  /// Yopilgan chekni faol holatga qaytarish — TASDIQ so'raladi.
  /// Server smena ochiqligini qayta tekshiradi; yopiq bo'lsa xato qaytadi.
  Future<void> _revertOrder(String orderNumber) async {
    if (_reverting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chekni qaytarish'),
        content: Text(
          '$orderNumber faol holatga qaytarilsinmi?\n'
          'To\'lov bekor bo\'ladi va chek yana ochiq bo\'ladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo‘q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Qaytarish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _reverting = true;
    try {
      await ApiService().revertOrder(orderNumber);
      if (!mounted) return;
      _toast('Chek faol holatga qaytarildi');
      _load();
      _loadHistory();
    } catch (e) {
      var msg = 'Qaytarilmadi';
      if (e is DioException && e.response?.data is Map) {
        msg = (e.response!.data as Map)['message']?.toString() ?? msg;
      }
      _toast(msg, error: true);
    } finally {
      _reverting = false;
    }
  }

  /// Yopilgan chekning to'lov usulini o'zgartirish — TASDIQ so'raladi.
  /// Server smena ochiqligini va chek shu smenaniki ekanini qayta tekshiradi.
  Future<void> _changePayment(Map<String, dynamic> o, String method) async {
    final orderNumber = o['order_number']?.toString() ?? '';
    final oldLabel = _payLabel(o['payment_method']?.toString());
    final newLabel = _payLabel(method);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('To\'lov usulini o\'zgartirish'),
        content: Text('$orderNumber\n$oldLabel → $newLabel o\'zgartirilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O\'zgartirish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // «Boshqa» ga o'tkazilsa — izoh shart (summa bilan guruhga ketadi)
    String? comment;
    if (method == 'other') {
      comment = await askOtherPaymentComment(
        context,
        amount: (o['total'] as num?)?.toInt() ?? 0,
      );
      if (comment == null || !mounted) return;
    }
    try {
      await ApiService().changeOrderPayment(
        orderNumber,
        method,
        paymentComment: comment,
      );
      if (!mounted) return;
      _toast('To\'lov usuli: $newLabel');
      _loadHistory();
    } catch (e) {
      var msg = 'O\'zgartirilmadi';
      if (e is DioException && e.response?.data is Map) {
        msg = (e.response!.data as Map)['message']?.toString() ?? msg;
      }
      _toast(msg, error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger : AppColors.success,
      ),
    );
  }

  // ============================================================
  // EKRAN — admin «Buyurtmalar» sahifasi bilan BIR XIL karkas.
  //
  // Ilgari bu yerda o'zining sarlavhasi, pastda ZAL/TASHQARI/Saboy/Dostafka
  // tab paneli va stol bo'yicha yig'iladigan akkordeon bor edi: kassir bitta
  // chekni ko'rish uchun avval stolni ochib o'tirardi, qidiruv va sana esa
  // umuman yo'q edi (tarix «oxirgi 100 ta chek» bo'lib kelardi).
  //
  // Endi super admindagidek: sarlavha + qidiruv, Aktiv/Tarix segmenti,
  // sana qatori, filtr chiplari va YASSI cheklar ro'yxati — hammasi bir
  // qarashda ko'rinadi.
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final list = _showHistory ? _filteredHistory : _filteredActive;

    return AdminPage(
      helpKey: 'pos.orders',
      title: 'Buyurtmalar',
      icon: Icons.receipt_long_rounded,
      accent: AppColors.primary,
      subtitle: _subtitle(list),
      loading: _showHistory ? _historyLoading : _loading,
      onRefresh: _showHistory ? _loadHistory : _load,
      onSearchChanged: (v) => setState(() => _query = v),
      searchHint: 'Chek raqami, stol, mahsulot yoki mijoz…',
      segments: const ['Aktiv', 'Tarix'],
      segmentIndex: _showHistory ? 1 : 0,
      onSegmentChanged: (i) {
        final history = i == 1;
        setState(() => _showHistory = history);
        // Har safar qayta o'qiladi: tanlangan sana o'zgargan bo'lishi ham,
        // boshqa kassada chek yopilgan bo'lishi ham mumkin.
        if (history) _loadHistory();
      },
      toolbar: _showHistory ? _historyToolbar() : null,
      child: list.isEmpty ? _emptyState() : _ordersList(list),
    );
  }

  /// Sarlavha ostidagi izoh: nechta chek va jami qancha (bekor qilinganlar
  /// summaga kirmaydi).
  String _subtitle(List<dynamic> list) {
    var sum = 0;
    for (final o in list) {
      if (o['status'] == 'cancelled') continue;
      final t = o['total'];
      if (t is num) sum += t.toInt();
    }
    return '${list.length} ta chek · ${formatMoney(sum, suffix: ' so\'m')}';
  }

  Widget _historyToolbar() {
    return Column(
      children: [
        AdminDateBar(
          date: _windowStart,
          withTime: true,
          onChanged: (d) {
            _windowStart = d;
            _loadHistory();
          },
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _typeFilters.length; i++)
                _filterChip(_typeFilters[i], i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, int value) {
    final selected = _typeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => setState(() => _typeFilter = value),
        child: AnimatedContainer(
          duration: AppDuration.normal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

  Widget _emptyState() {
    if (_showHistory) {
      return AdminEmpty(
        icon: Icons.receipt_long_outlined,
        title: _query.isEmpty ? 'Buyurtma yo‘q' : 'Topilmadi',
        message: _query.isEmpty
            ? 'Tanlangan kunda bu toifada chek yo‘q. '
                  'Sanani yoki filtrni o‘zgartiring.'
            : 'Boshqa raqam yoki nom bilan qidirib ko‘ring.',
        color: AppColors.info,
      );
    }
    return AdminEmpty(
      icon: Icons.delivery_dining_outlined,
      title: _query.isEmpty ? 'Saboy/Dostafka buyurtma yo‘q' : 'Topilmadi',
      message: _query.isEmpty
          ? 'Yangi buyurtmalar shu yerda paydo bo‘ladi'
          : 'Boshqa raqam yoki nom bilan qidirib ko‘ring.',
      color: AppColors.warning,
    );
  }

  Widget _ordersList(List<dynamic> list) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) => _orderCard(list[i] as Map<String, dynamic>),
    );
  }

  // ============================================================
  // Chek kartasi — admin ro'yxatidagi bilan bir xil: «№19 · ZAL-2»,
  // vaqt, holat belgisi, ostida mahsulot nomlari, o'ngda summa.
  // Aktiv (saboy/dostafka) chekda ostiga oshxona holati chiplari
  // qo'shiladi — bu POS ning o'z ishi, adminda u yo'q.
  // ============================================================

  Widget _orderCard(Map<String, dynamic> o) {
    final type = o['type'] as String? ?? '';
    final status = o['status'] as String? ?? '';
    final isCancelled = status == 'cancelled';
    final isOpen = !isCancelled && status != 'completed';
    final yandex = _isYandex(o);
    final color = isCancelled ? AppColors.danger : _srcColor(o);
    final items = o['items'] as List<dynamic>? ?? [];
    final payMethod = o['payment_method']?.toString() ?? '';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => _showOrderDetail(o),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconAvatar(icon: _typeIcon(type), color: color, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${_displayOrderNum(o['order_number'])} · '
                              '${_placeLabel(o)}',
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
                              _timeText(o),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textFaint,
                              ),
                            ),
                            if (yandex)
                              const StatusBadge(
                                label: 'Yandex',
                                color: kYandexColor,
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
                            if (!isOpen && !isCancelled && payMethod.isNotEmpty)
                              StatusBadge(
                                label: _payLabel(payMethod),
                                color: AppColors.textMuted,
                                icon: Icons.payments_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _itemsSummary(items),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if ((o['customer_name'] ?? '').toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                KMetaChip(
                                  icon: Icons.person_rounded,
                                  label: o['customer_name'].toString(),
                                ),
                                if ((o['customer_phone'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  KMetaChip(
                                    icon: Icons.phone_rounded,
                                    label: o['customer_phone'].toString(),
                                  ),
                              ],
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
              if (!_showHistory) ...[
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.borderSoft),
                const SizedBox(height: 8),
                _statusChips(o),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Oshxona holati — faqat aktiv saboy/dostafka chekida.
  Widget _statusChips(Map<String, dynamic> o) {
    final current = o['status'] as String? ?? 'new';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _statuses.map((s) {
        final key = s['key'] as String;
        final label = s['label'] as String;
        final c = s['color'] as Color;
        final selected = current == key;
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () {
            if (key != current) _updateStatus(o['order_number'], key);
          },
          child: AnimatedContainer(
            duration: AppDuration.normal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c : c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white : c,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Chek qaysi joyniki: stol nomi («ZAL-2»), bo'lmasa buyurtma turi.
  String _placeLabel(Map<String, dynamic> o) {
    final label = (o['table_label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    final sku = (o['table_sku'] ?? '').toString().trim();
    if (sku.isNotEmpty) return sku;
    return _srcLabel(o);
  }

  /// «12:31» yoki yopilgan chekda «12:31 → 18:15» (ochilgan → to'langan).
  String _timeText(Map<String, dynamic> o) {
    final opened = _hhmm(o['created_at']);
    final paid = _paidTime(o);
    if (opened.isNotEmpty && paid.isNotEmpty) return '$opened → $paid';
    return opened;
  }

  /// Ro'yxatda chek raqami QISQA: «26-08-22-P25» → «№25». Sana allaqachon
  /// tepadagi filtrda turibdi. Raqamdagi sana tanlangan kundan farq qilsa
  /// (ish kuni qoidasidan oldingi eski cheklar) — qisqartma qo'shiladi:
  /// «№25 · 22-08».
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
          final ref = _showHistory ? _dateStr : businessTodayStr();
          if (numDate != ref) return '№$n · ${d.group(3)}-${d.group(2)}';
        }
        return '№$n';
      }
    }
    return shortOrderNumber(s);
  }

  /// Chek qatorining ostidagi mahsulotlar — har biri alohida qatorda:
  /// «2 × Вишнёвая Милка». Uzun chekda faqat 3 tasi, qolgani «+N ta yana».
  static String _itemsSummary(List<dynamic> items) {
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
    if (parts.length > 3) {
      return [...parts.take(3), '+${parts.length - 3} ta yana'].join('\n');
    }
    return parts.join('\n');
  }
}
