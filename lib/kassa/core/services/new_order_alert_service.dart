import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';
import '../utils/app_navigator.dart';
import '../widgets/new_order_dialog.dart';
import 'wss_service.dart';

/// Buyurtma qayerdan kelgani.
enum IncomingOrderKind {
  /// Telegram mini-app — olib ketish.
  takeaway,

  /// Telegram mini-app — yetkazib berish.
  delivery,

  /// Yandex Eda zakazi.
  yandex,

  /// Mehmon stol QR orqali o'zi buyurtma berdi.
  table,
}

/// Chekning bitta qatori.
@immutable
class IncomingOrderLine {
  const IncomingOrderLine({
    required this.name,
    required this.qty,
    required this.total,
  });

  final String name;
  final int qty;
  final int total;
}

/// Serverdan (kassa emas) kelgan bitta yangi buyurtma.
@immutable
class IncomingOrder {
  const IncomingOrder({
    required this.number,
    required this.kind,
    required this.lines,
    required this.total,
    required this.at,
    this.tableLabel = '',
    this.customerName = '',
    this.phone = '',
    this.note = '',
  });

  final String number;
  final IncomingOrderKind kind;
  final List<IncomingOrderLine> lines;
  final int total;
  final DateTime at;
  final String tableLabel;
  final String customerName;
  final String phone;
  final String note;

  String get title => switch (kind) {
        IncomingOrderKind.takeaway => 'YANGI SABOY BUYURTMASI',
        IncomingOrderKind.delivery => 'YANGI DOSTAFKA BUYURTMASI',
        IncomingOrderKind.yandex => 'YANGI YANDEX EDA ZAKAZI',
        IncomingOrderKind.table => 'STOLDAN YANGI BUYURTMA',
      };

  /// Ekrandagi eng katta yozuv: saboy/dostafka/Yandex yoki stol nomi.
  String get bigLabel => switch (kind) {
        IncomingOrderKind.takeaway => 'SABOY',
        IncomingOrderKind.delivery => 'DOSTAFKA',
        IncomingOrderKind.yandex => 'YANDEX',
        IncomingOrderKind.table => tableLabel.isEmpty ? 'STOL' : tableLabel,
      };

  IconData get icon => switch (kind) {
        IncomingOrderKind.takeaway => Icons.shopping_bag_rounded,
        IncomingOrderKind.delivery => Icons.delivery_dining_rounded,
        IncomingOrderKind.yandex => Icons.local_taxi_rounded,
        IncomingOrderKind.table => Icons.table_restaurant_rounded,
      };

  Color get color => switch (kind) {
        IncomingOrderKind.takeaway => AppColors.success,
        IncomingOrderKind.delivery => AppColors.info,
        IncomingOrderKind.yandex => AppColors.warning,
        IncomingOrderKind.table => AppColors.primary,
      };

  int get itemCount => lines.fold(0, (s, l) => s + l.qty);
}

/// Serverdan kelgan har bir YANGI buyurtma (Telegram mini-app saboy/dostafka,
/// Yandex Eda, stol QR) uchun kassa ekranida KATTA ogohlantirish — mehmon
/// chaqirig'i (StaffCallService) bilan bir xil uslubda.
///
/// Nega kerak: bunday chek kassir hech narsa bosmasdan paydo bo'ladi.
/// Buyurtmalar panelidagi kichik qator ko'zga tashlanmaydi va chek
/// yarim soat e'tiborsiz qolishi mumkin. Dialog buyurtma TARKIBINI
/// ko'rsatadi va faqat «Ko'rdim» bosilganda yopiladi.
///
/// Kassaning o'zida ochilgan cheklar (source = pos) ko'rsatilmaydi.
class NewOrderAlertService {
  static final NewOrderAlertService _instance = NewOrderAlertService._();
  factory NewOrderAlertService() => _instance;
  NewOrderAlertService._();

  /// Hali «Ko'rdim» bosilmagan buyurtmalar — eng eskisi birinchi.
  final ValueNotifier<List<IncomingOrder>> pending =
      ValueNotifier<List<IncomingOrder>>(const []);

  /// Bir marta ko'rsatilgan chek raqamlari: `order:new` bir chek uchun ikki
  /// marta kelishi mumkin (jonli event + replikatsiya).
  final Set<String> _seen = <String>{};

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _retryTimer;
  bool _dialogOpen = false;
  bool? _dialogAlive;

  void onDialogInit() => _dialogAlive = true;

  void onDialogDispose() {
    _dialogAlive = false;
    _dialogOpen = false;
  }

  void start() {
    _sub ??= WssService().eventStream.listen(_onEvent);
  }

  /// Chiqishda tozalanadi.
  void clear() {
    _retryTimer?.cancel();
    _retryTimer = null;
    pending.value = const [];
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['event'] != 'order:new') return;
    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;
    final order = payload['order'];
    if (order is! Map<String, dynamic>) return;

    final parsed = parseIncoming(order);
    if (parsed == null) return;
    add(parsed);
  }

  /// `order:new` payload'idagi chekni o'qiydi. Kassada ochilgan (source=pos)
  /// yoki manbasi noma'lum chek uchun `null`.
  static IncomingOrder? parseIncoming(Map<String, dynamic> order) {
    final number = (order['order_number'] as String?)?.trim() ?? '';
    if (number.isEmpty) return null;
    final source = (order['source'] as String?)?.trim().toLowerCase() ?? '';
    final type = (order['type'] as String?)?.trim().toLowerCase() ?? '';
    final tableSku = (order['table_sku'] as String?)?.trim() ?? '';

    final IncomingOrderKind kind;
    switch (source) {
      case 'yandex':
        kind = IncomingOrderKind.yandex;
      case 'online':
      case 'telegram':
      case 'web':
        kind = type == 'takeaway'
            ? IncomingOrderKind.takeaway
            : IncomingOrderKind.delivery;
      case 'qr':
      case 'guest':
        kind = IncomingOrderKind.table;
      default:
        return null; // pos yoki noma'lum — kassir o'zi ochgan
    }

    final lines = <IncomingOrderLine>[];
    final items = order['items'];
    if (items is List) {
      for (final it in items) {
        if (it is! Map) continue;
        final qty = _int(it['quantity']);
        if (qty <= 0) continue;
        var total = _int(it['total']);
        if (total == 0) total = _int(it['price']) * qty;
        final snap = it['snapshot'];
        var name = '';
        if (snap is Map) name = menuName(snap['name']);
        if (name.isEmpty) name = menuName(it['name']);
        if (name.isEmpty) name = 'Mahsulot';
        lines.add(IncomingOrderLine(name: name, qty: qty, total: total));
      }
    }

    return IncomingOrder(
      number: number,
      kind: kind,
      lines: lines,
      total: _int(order['total']),
      at: DateTime.tryParse(order['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      tableLabel: tableSku,
      customerName: (order['customer_name'] as String?)?.trim() ?? '',
      phone: (order['customer_phone'] as String?)?.trim() ?? '',
      note: (order['note'] as String?)?.trim() ?? '',
    );
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  void add(IncomingOrder order) {
    if (!_seen.add(order.number)) return;
    if (_seen.length > 500) _seen.remove(_seen.first);
    pending.value = [...pending.value, order];
    _alert();
    _show();
  }

  void _alert() {
    HapticFeedback.heavyImpact().catchError((_) {});
    SystemSound.play(SystemSoundType.alert).catchError((_) {});
  }

  /// Kassir «Ko'rdim»ni bosdi — ro'yxatdan chiqadi. Ro'yxat bo'shasa dialog
  /// o'zi yopiladi (qarang: NewOrderDialog).
  void dismiss(IncomingOrder order) {
    pending.value =
        pending.value.where((o) => o.number != order.number).toList();
  }

  void _show() {
    if (pending.value.isEmpty) return;
    if (_dialogOpen && _dialogAlive != false) return;

    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      _retryTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
        if (pending.value.isEmpty || (_dialogOpen && _dialogAlive != false)) {
          t.cancel();
          _retryTimer = null;
          return;
        }
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          t.cancel();
          _retryTimer = null;
          _show();
        }
      });
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;
    _dialogOpen = true;
    _dialogAlive = null;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const NewOrderDialog(),
    ).whenComplete(() {
      _dialogOpen = false;
      if (pending.value.isNotEmpty) _show();
    });
  }
}
