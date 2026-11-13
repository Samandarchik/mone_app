import 'dart:async';

import 'api_service.dart';
import 'wss_service.dart';

/// Local ↔ online o'rtasida avtomatik almashtirish.
///
/// Ilova **asosiy (online) serverdan** boshlaydi; local server ishga tushishda
/// bir marta izlanadi ([ApiService.detectLocal]) va topilsa unga o'tiladi.
///
/// **Local tirikligi WebSocket bilan o'lchanadi.** WSS uzilishi (yoki 10s
/// ichida ping kelmasligi) server yiqilganini HTTP timeout'ni kutmasdan
/// bildiradi — kassir "aylanayotgan" ekranga qarab turmaydi.
///
/// - WSS uzilib, [_failoverGrace] ichida qayta ulanmasa → onlinega o'tamiz.
/// - Onlineda ishlaganda local `/api/health` har [_probeInterval] da so'raladi;
///   ketma-ket [_probesToReturn] marta javob bersa → localga qaytamiz
///   (bitta tasodifiy javobdan keyin qaytib, yana yiqilib "sakrash"ni
///   oldini olish uchun).
///
/// Onlineda yaratilgan buyurtmalar local ko'tarilgach sync orqali tushadi va
/// oshxona cheki ana shunda chop etiladi — cloud LAN printerga yeta olmaydi.
class EndpointManager {
  static final EndpointManager _instance = EndpointManager._();
  factory EndpointManager() => _instance;
  EndpointManager._();

  static const _failoverGrace = Duration(seconds: 8);
  static const _probeInterval = Duration(seconds: 15);
  static const _watchdogInterval = Duration(seconds: 5);
  static const _probesToReturn = 2;

  StreamSubscription<bool>? _wssSub;
  StreamSubscription<bool>? _endpointSub;
  Timer? _graceTimer;
  Timer? _probeTimer;
  Timer? _watchdogTimer;
  int _okProbes = 0;
  bool _started = false;
  bool _probing = false;

  final _noticeController = StreamController<bool>.broadcast();

  /// Avto-almashish sodir bo'lganda signal (true = cloudga o'tdi).
  /// UI foydalanuvchini ogohlantirishi uchun.
  Stream<bool> get noticeStream => _noticeController.stream;

  void start() {
    if (_started) return;
    _started = true;

    // Local topilmagan bo'lsa ham onlinedan ishlayveramiz, lekin uni davriy
    // izlashda davom etamiz: server ilovadan keyinroq ko'tarilishi mumkin
    // (Windows'da xizmat sekin ishga tushsa yoki kabel keyin ulansa).
    if (ApiService().isUsingCloud) _startProbe();

    _wssSub = WssService().connectionStream.listen((connected) {
      if (connected) {
        _graceTimer?.cancel();
        _graceTimer = null;
      } else if (!ApiService().isUsingCloud) {
        _armFailover();
      }
    });

    // connectionStream faqat holat O'ZGARGANDA signal beradi. Agar ilova
    // localga umuman ulanolmayotgan bo'lsa (masalan cloudda ishlab turib
    // localga qaytdik-u, u yerda WSS ko'tarilmadi) — hech qanday o'zgarish
    // bo'lmaydi va failover tetiklamay qolardi. Watchdog shu teshikni yopadi.
    _watchdogTimer = Timer.periodic(_watchdogInterval, (_) {
      if (ApiService().isUsingCloud) return;
      if (WssService().isAlive && !WssService().isConnected) _armFailover();
    });

    _endpointSub = ApiService().endpointStream.listen((useCloud) {
      _graceTimer?.cancel();
      _graceTimer = null;
      _okProbes = 0;
      if (useCloud) {
        _startProbe();
      } else {
        _stopProbe();
      }
      // Yangi manzil bilan realtime kanalni darhol ko'tarish.
      WssService().reconnect();
      _noticeController.add(useCloud);
    });
  }

  void _armFailover() {
    // Foydalanuvchi LOCAL'ni qo'lda tanlagan bo'lsa avtomatik bulutga
    // o'tkazmaymiz — u ataylab shu serverda ishlayapti.
    if (ApiService().pinnedCloud == false) return;
    if (!ApiService().hasCloud || _graceTimer != null) return;
    _graceTimer = Timer(_failoverGrace, () {
      _graceTimer = null;
      // Shu orada o'zi tiklangan bo'lsa — tegmaymiz.
      if (WssService().isConnected || ApiService().isUsingCloud) return;
      ApiService().switchToCloud();
    });
  }

  void _startProbe() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probeOnce());
  }

  void _stopProbe() {
    _probeTimer?.cancel();
    _probeTimer = null;
    _okProbes = 0;
  }

  Future<void> _probeOnce() async {
    if (_probing || !ApiService().isUsingCloud) return;
    _probing = true;
    try {
      final alive = await ApiService().probeLocal();
      if (!ApiService().isUsingCloud) return;
      if (!alive) {
        _okProbes = 0;
        return;
      }
      _okProbes++;
      if (_okProbes >= _probesToReturn) {
        _okProbes = 0;
        // QO'LDA "online" tanlangan bo'lsa QAYTARMAYMIZ.
        //
        // Ilgari bu shart yo'q edi: admin bulutni tanlab ma'lumot kiritsa,
        // ~30 soniyadan keyin ilova jimgina local'ga qaytar va o'sha
        // ma'lumot "yo'q bo'lib qolgandek" ko'rinardi. Aslida u bulutda
        // saqlangan, faqat ekran boshqa serverdan o'qiyotgan edi.
        if (ApiService().pinnedCloud == true) return;
        ApiService().switchToLocal();
      }
    } finally {
      _probing = false;
    }
  }

  /// Foydalanuvchi qo'lda almashtirsa — endpointStream orqali grace/probe
  /// holati va WSS baribir qayta sozlanadi.
  ///
  /// `manual: true` — tanlov ESLAB QOLINADI va avtomatika uni bekor
  /// qilmaydi (qarang: ApiService.pinnedCloud).
  bool forceCloud() => ApiService().switchToCloud(manual: true);
  bool forceLocal() => ApiService().switchToLocal(manual: true);

  /// Avtomatik rejimga qaytarish.
  void resetToAuto() {
    ApiService().unpinEndpoint();
    _okProbes = 0;
  }

  void stop() {
    _started = false;
    _wssSub?.cancel();
    _wssSub = null;
    _endpointSub?.cancel();
    _endpointSub = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _stopProbe();
  }
}
