import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_navigator.dart';
import '../widgets/staff_call_dialog.dart';
import 'wss_service.dart';

/// Mehmon nima so'raganini bildiradi.
enum StaffCallKind {
  /// "Ofitsiant" tugmasi — stolga borish kerak.
  waiter,

  /// "Hisob" tugmasi — chek olib borish kerak.
  bill,
}

/// Bitta chaqiruv: qaysi stol, nima so'radi, qachon.
@immutable
class StaffCall {
  const StaffCall({
    required this.tableSku,
    required this.label,
    required this.kind,
    required this.at,
  });

  final String tableSku;

  /// Stol nomi ("ZAL-7"). Ekranda ANA SHU katta qilib ko'rsatiladi.
  final String label;
  final StaffCallKind kind;
  final DateTime at;

  String get title => switch (kind) {
        StaffCallKind.waiter => 'OFITSIANT CHAQIRILMOQDA',
        StaffCallKind.bill => 'HISOB SO\'RALMOQDA',
      };

  IconData get icon => switch (kind) {
        StaffCallKind.waiter => Icons.room_service_rounded,
        StaffCallKind.bill => Icons.receipt_long_rounded,
      };

  /// Bir xil chaqiruvni ikki marta ko'rsatmaslik uchun.
  String get dedupKey => '$tableSku|${kind.name}';
}

/// Mehmon saytdan/QR dan ofitsiant chaqirsa yoki hisob so'rasa — kassa
/// ekranida KATTA ogohlantirish chiqaradi.
///
/// Ilgari server `waiter:called` eventini yuborardi-yu, ilova uni umuman
/// ushlamasdi: chaqiruv faqat serverdagi karnaydan ovoz sifatida eshitilardi.
/// Shovqinli zalda yoki ovoz o'chirilgan bo'lsa mehmon javobsiz qolardi.
///
/// Ogohlantirish O'ZI YO'QOLMAYDI — xodim "Yopish"ni bosmaguncha turadi
/// (chetiga bosish ham, "orqaga" ham yopmaydi). Bir vaqtda bir nechta stol
/// chaqirsa navbat bilan ko'rsatiladi.
class StaffCallService {
  static final StaffCallService _instance = StaffCallService._();
  factory StaffCallService() => _instance;
  StaffCallService._();

  /// Hali yopilmagan chaqiruvlar — eng eskisi birinchi.
  final ValueNotifier<List<StaffCall>> pending =
      ValueNotifier<List<StaffCall>>(const []);

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _retryTimer;
  bool _dialogOpen = false;

  /// Dialog daraxtda bormi: `null` — ochildi, lekin hali birinchi kadri
  /// chizilmadi.
  ///
  /// NEGA shunchaki `_dialogOpen` yetmaydi: navigator almashsa (chiqish →
  /// login ekrani) dialog `whenComplete`siz yo'q bo'lib ketishi mumkin va
  /// bayroq abadiy `true` qolib, keyingi chaqiruvlar UMUMAN
  /// ko'rsatilmasdi.
  bool? _dialogAlive;

  /// `StaffCallDialog` o'zi xabar beradi.
  void onDialogInit() => _dialogAlive = true;

  void onDialogDispose() {
    _dialogAlive = false;
    _dialogOpen = false;
  }

  void start() {
    _sub ??= WssService().eventStream.listen(_onEvent);
  }

  /// Chiqishda tozalanadi — keyingi kassir oldingi smenaning chaqiruvini
  /// ko'rmasin.
  void clear() {
    _retryTimer?.cancel();
    _retryTimer = null;
    pending.value = const [];
  }

  void _onEvent(Map<String, dynamic> event) {
    final kind = switch (event['event']) {
      'waiter:called' => StaffCallKind.waiter,
      'bill:requested' => StaffCallKind.bill,
      _ => null,
    };
    if (kind == null) return;

    final payload = event['payload'];
    if (payload is! Map<String, dynamic>) return;

    final sku = (payload['table_sku'] as String?)?.trim() ?? '';
    var label = (payload['label'] as String?)?.trim() ?? '';
    if (label.isEmpty) label = sku;
    if (label.isEmpty) return;

    add(StaffCall(
      tableSku: sku.isEmpty ? label : sku,
      label: label,
      kind: kind,
      at: DateTime.tryParse(payload['called_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    ));
  }

  void add(StaffCall call) {
    if (pending.value.any((c) => c.dedupKey == call.dedupKey)) return;
    pending.value = [...pending.value, call];
    _alert();
    _show();
  }

  /// Ovoz + tebranish. Platforma qo'llab-quvvatlamasa (Windows'da tebranish
  /// yo'q) xato jimgina yutiladi — ushlanmagan Future xatosi log'ni
  /// to'ldirmasin.
  void _alert() {
    HapticFeedback.heavyImpact().catchError((_) {});
    SystemSound.play(SystemSoundType.alert).catchError((_) {});
  }

  /// Xodim "Yopish"ni bosdi — chaqiruv ro'yxatdan chiqadi. Ro'yxat bo'shasa
  /// dialogning o'zi yopiladi (qarang: `StaffCallDialog`).
  void dismiss(StaffCall call) {
    pending.value =
        pending.value.where((c) => c.dedupKey != call.dedupKey).toList();
  }

  void _show() {
    if (pending.value.isEmpty) return;
    if (_dialogOpen && _dialogAlive != false) return;

    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) {
      // Ilova hali ko'tarilmagan (yoki login ekranida navigator tayyor
      // emas) — chaqiruv yo'qolib ketmasin, biroz keyin qayta urinamiz.
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
      builder: (_) => const StaffCallDialog(),
    ).whenComplete(() {
      _dialogOpen = false;
      // Dialog yopilgach navbatda yana chaqiruv qolgan bo'lsa (masalan
      // ro'yxat bo'shashi bilan yangisi kelib qolsa) — qaytadan chiqaramiz.
      if (pending.value.isNotEmpty) _show();
    });
  }
}
