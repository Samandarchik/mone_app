import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'app_state.dart';
import 'windows_update_service.dart';

class WssService {
  static final WssService _instance = WssService._();
  factory WssService() => _instance;
  WssService._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _connected = false;
  bool _alive = false; // user called connect, not disconnect

  // Generation counter — stale callbacks from old connections are ignored
  int _gen = 0;

  final _authFailedController = StreamController<bool>.broadcast();
  /// Token yaroqsiz bo'lganda signal — ilova qayta login so'rashi kerak.
  Stream<bool> get authFailedStream => _authFailedController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  bool get isConnected => _connected;

  /// `connect()` chaqirilgan va `disconnect()` qilinmagan — ya'ni ilova
  /// realtime kanalni ushlab turishi kerak (login qilingan holat).
  bool get isAlive => _alive;

  String? _lastToken;
  int _lastMenuVersion = 0;
  String _lastSource = 'pos';

  void connect({
    String? token,
    int menuVersion = 0,
    String source = 'pos',
  }) {
    _lastToken = token ?? _lastToken;
    _lastMenuVersion = menuVersion;
    _lastSource = source;
    _alive = true;
    _reconnect();
  }

  /// Yangi base URL bilan qayta ulanish (server manzili o'zgarganda).
  /// Backoff nolga tushadi — yangi manzilga eski serverning 10s kutishini
  /// olib o'tish shart emas.
  void reconnect() {
    if (!_alive) return;
    _retry = 0;
    _reconnect();
  }

  void _reconnect() {
    if (!_alive) return;

    // New generation — all old callbacks become stale
    final gen = ++_gen;

    // Clean up old connection without triggering onDone loop
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close().catchError((_) {});
    } catch (_) {}
    _channel = null;

    final baseUrl = ApiService().baseUrl;
    final wsUrl =
        '${baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://')}/ws';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Server o'chgan bo'lsa ulanish xatosi `ready`/`done` future'lariga
      // tushadi; hech kim ushlamasa har bir qayta urinishda bittadan
      // "Unhandled Exception: WebSocketChannelException" log'ga chiqadi
      // (server yiqilgan tunda — minglab satr). Uzilishning o'zi quyidagi
      // onDone/onError da allaqachon qayta ishlanadi.
      _channel!.ready.catchError((_) {});
      _channel!.sink.done.catchError((_) {});

      _channel!.sink.add(jsonEncode({
        'event': 'init',
        'payload': {
          'token': _lastToken != null ? 'Bearer $_lastToken' : null,
          'menu_version': _lastMenuVersion,
          'source': _lastSource,
        },
      }));

      _subscription = _channel!.stream.listen(
        (data) {
          if (gen != _gen) return; // stale
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleMessage(gen, msg);
        },
        onDone: () {
          if (gen != _gen) return; // stale
          _setConnected(false);
          _scheduleReconnect(gen);
        },
        onError: (_) {
          if (gen != _gen) return; // stale
          _setConnected(false);
          _scheduleReconnect(gen);
        },
        cancelOnError: false,
      );
    } catch (_) {
      _setConnected(false);
      _scheduleReconnect(gen);
    }
  }

  void _handleMessage(int gen, Map<String, dynamic> msg) {
    if (gen != _gen) return;
    final event = msg['event'] as String?;
    if (event == null) return;

    if (event == 'init:ok') {
      _retry = 0;
      _setConnected(true);
      _startPingTimer(gen);
      if (kDebugMode) debugPrint('WSS connected');
      final payload = msg['payload'] as Map<String, dynamic>? ?? {};
      AppState().onInitOK(payload);
      _eventController.add(msg);
      // Server qayta ko'tarilgan bo'lishi mumkin (odatda deploy'dan keyin) —
      // ilova yangilanishini ham shu zahoti tekshirib qo'yamiz (60s throttle
      // ichida, faqat Windows release build'da ishlaydi).
      WindowsUpdateService.checkForUpdate();
    } else if (event == 'init:error') {
      // Token eskirgan/yaroqsiz. Ilgari bu event umuman ushlanmasdi va ilova
      // sekundiga ~3 marta qayta ulanishga urinib, tunni shu holda o'tkazardi
      // (realtime o'lik, sabab ko'rinmaydi, serverga esa ulanish bo'roni).
      _alive = false;
      _gen++;
      _setConnected(false);
      _eventController.add(msg);
      _authFailedController.add(true);
      return;
    } else if (event == 'error' &&
        (msg['payload'] is Map) &&
        (msg['payload'] as Map)['code'] == 'passive_node') {
      // Bulut passiv: filial lokal serveri ishlayapti — unga o'tamiz
      // (ApiService endpointStream orqali WSS ham qayta ulanadi).
      _eventController.add(msg);
      ApiService().probeLocal().then((alive) {
        if (alive) ApiService().switchToLocal();
      });
      return;
    } else if (event == 'ping') {
      try {
        _channel?.sink.add(jsonEncode({
          'event': 'pong',
          'payload': {'timestamp': DateTime.now().toUtc().toIso8601String()},
        }));
      } catch (_) {}
      _startPingTimer(gen); // reset timer on each ping
    } else {
      if (event == 'app:update_available') {
        // Backend GitHub'da yangi ilova relizini ko'rdi — 30 daqiqalik
        // davriy tekshiruvni kutmasdan darhol yangilaymiz.
        WindowsUpdateService.checkForUpdate(force: true);
      }
      _eventController.add(msg);
    }
  }

  void _startPingTimer(int gen) {
    _pingTimer?.cancel();
    _pingTimer = Timer(const Duration(seconds: 10), () {
      if (gen != _gen) return;
      if (kDebugMode) debugPrint('WSS ping timeout');
      _setConnected(false);
      _scheduleReconnect(gen);
    });
  }

  int _retry = 0;

  void _scheduleReconnect(int gen) {
    if (gen != _gen || !_alive) return;
    _reconnectTimer?.cancel();
    // Asta-sekin ortuvchi kutish (0.3s → 10s). Ilgari doimiy 300ms edi:
    // server o'chgan bo'lsa har bir terminal sekundiga 3 marta urinib,
    // tarmoqni va serverni ko'tarilishiga imkon bermasdi.
    final delayMs = (300 * (1 << (_retry.clamp(0, 5)))).clamp(300, 10000);
    _retry++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (gen != _gen || !_alive) return;
      _reconnect();
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _connectionController.add(value);
  }

  void disconnect() {
    _alive = false;
    _gen++;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close().catchError((_) {});
    } catch (_) {}
    _channel = null;
    _setConnected(false);
  }

  void send(String event, Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode({'event': event, 'payload': payload}));
    } catch (_) {}
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _eventController.close();
    _authFailedController.close();
  }
}
