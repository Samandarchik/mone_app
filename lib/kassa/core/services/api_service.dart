import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_cache.dart';

enum AppMode { pos, superadmin, waiter, user }

/// So'rov ataylab ONLINE serverga bog'langan — failover uni ko'chirmasin.
const String _pinnedCloudFlag = 'pinned_cloud';

/// Asosiy (online) server — sozlamada so'raladigan YAGONA manzil.
/// Ilova shundan boshlaydi; restoran ichidagi local server topilsa unga o'tadi.
const String kServerUrl = 'https://moneapp.monebakeryuz.uz';

/// Local server porti. Windows master'da ilova serverning o'zi bilan bitta
/// mashinada turadi — shuning uchun manzil so'ralmaydi, `localhost` tekshiriladi.
const int kLocalServerPort = 8085;
const String kLocalhostUrl = 'http://localhost:$kLocalServerPort';

/// Restoran WiFi'sidagi Windows master manzili — planshet/boshqa terminallar
/// uchun standart. IP Windows'da qo'lda o'rnatilgan (DHCP o'zgartirmaydi).
/// Sozlamada bo'sh qolsa ham ishga tushishda shu manzil sinab ko'riladi.
const String kLanServerUrl = 'http://192.168.0.103:$kLocalServerPort';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  late Dio _dio;
  bool _dioReady = false;
  String _baseUrl = kServerUrl;

  /// Asosiy (online) server — foydalanuvchi kiritadi, doim mavjud.
  String? _serverUrl;

  /// Ixtiyoriy: restoran ichidagi tezkor manzil, qo'lda kiritiladi. Bo'sh
  /// qolsa ham [kLanServerUrl] va `localhost` avtomatik tekshiriladi — bu
  /// faqat boshqa restoran/tarmoq uchun majburiy.
  String? _lanUrl;

  /// Ishga tushishda aniqlangan local manzil (`_lanUrl` yoki `localhost`).
  /// Local server topilmagan bo'lsa `null`.
  String? _localUrl;

  String? _token;
  AppMode _mode = AppMode.pos;
  bool _configured = false;

  /// Hozir local serverdami. UI shu orqali LOCAL/ONLINE ko'rsatadi.
  bool _useLocal = false;

  /// Ikki tomonlama failover "sakrash"ini cheklash (ikkalasi ham o'lgan bo'lsa
  /// har bir so'rov manzilni almashtirib yurmasligi uchun).
  DateTime? _lastFailover;
  static const _failoverCooldown = Duration(seconds: 10);

  final _endpointController = StreamController<bool>.broadcast();

  /// Faol server almashganda signal beradi (true = online, false = local).
  Stream<bool> get endpointStream => _endpointController.stream;

  final _authFailedController = StreamController<void>.broadcast();

  /// Server tokenni qabul qilmadi (401 yoki "token yaroqsiz" 403).
  ///
  /// NEGA KERAK: token 12 soat amal qiladi. Ilgari bu holat HECH QAYERDA
  /// ushlanmasdi: WebSocket ulanish paytida tekshirilgani uchun ochiq
  /// qolaverardi, HTTP so'rovlar esa jimgina xato bera boshlardi — kassir
  /// chek yopolmay qolardi va sababi ekranda ko'rinmasdi. Endi ilova login
  /// ekraniga qaytaradi.
  Stream<void> get authFailedStream => _authFailedController.stream;
  bool get isUsingCloud => !_useLocal;
  String? get localUrl => _localUrl;
  String? get cloudUrl => _serverUrl;

  /// Qo'lda kiritilgan LAN manzil (sozlamalar formasi uchun).
  String? get lanUrl => _lanUrl;
  bool get hasCloud => (_serverUrl ?? '').isNotEmpty;
  bool get hasLocal => (_localUrl ?? '').isNotEmpty;

  /// Menyu rasmlari **doim asosiy serverdan** olinadi — local va online
  /// nodelarda fayllar 60 soniyada bir replikatsiya qilinadi, shuning uchun
  /// faol manzil bo'yicha yuklash "rasm bor, lekin ochilmadi" xatosini berardi.
  /// Yuklab olingan rasm diskda saqlanadi ([MediaCache]).
  String get mediaBaseUrl => _serverUrl ?? _baseUrl;

  // In-memory cache
  Map<String, dynamic>? _menuCache;
  List<dynamic>? _zonesCache;
  List<dynamic>? _stocksCache;
  List<dynamic>? _usersCache;

  void invalidateMenu() {
    _menuCache = null;
  }

  void invalidateZones() {
    _zonesCache = null;
  }

  void invalidateStocks() {
    _stocksCache = null;
  }

  void invalidateUsers() {
    _usersCache = null;
  }

  void invalidateAll() {
    _menuCache = null;
    _zonesCache = null;
    _stocksCache = null;
    _usersCache = null;
  }

  /// Ilovani sozlash — main.dart dan chaqiriladi
  void configure(AppMode mode, {String? serverUrl, String? lanUrl}) {
    _mode = mode;
    if (serverUrl != null) _serverUrl = serverUrl;
    if (lanUrl != null) _lanUrl = lanUrl;
  }

  AppMode get mode => _mode;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('kassa_token');

    // Eski kalitlardan ko'chirish: ilgari ikkita manzil so'ralardi
    // (local_url = asosiy, cloud_url = zaxira). Endi asosiysi — online server.
    final legacyLocal =
        prefs.getString('kassa_local_url') ?? prefs.getString('kassa_base_url');
    final savedServer =
        prefs.getString('kassa_server_url') ??
        prefs.getString('kassa_cloud_url') ??
        legacyLocal;
    final savedLan =
        prefs.getString('kassa_lan_url') ??
        (legacyLocal != null && legacyLocal != savedServer
            ? legacyLocal
            : null);

    _serverUrl ??= savedServer;
    _lanUrl ??= savedLan;

    switch (_mode) {
      case AppMode.pos:
      case AppMode.waiter:
        _configured = (_serverUrl ?? '').isNotEmpty;
        break;
      case AppMode.superadmin:
      case AppMode.user:
        _serverUrl ??= kServerUrl;
        _configured = true;
        break;
    }

    // Ilova doim asosiy (online) serverdan boshlaydi.
    _useLocal = false;
    _baseUrl = _serverUrl ?? kServerUrl;
    _setupDio();

    // Local server tirikmi — ishga tushishda BIR MARTA tekshiriladi. Bu login
    // qilinishidan oldin bo'ladi: keyinroq almashsak token yaroqsiz bo'lib
    // (local va cloud JWT_SECRET'i har xil) kassir qaytadan PIN kiritardi.
    if (await detectLocal()) _setActive(useLocal: true);
  }

  /// Local turganda kutish qisqa (onlinega tez o'tish uchun), online'da —
  /// uzoqroq, chunki VPS internet orqali sekinroq javob berishi mumkin.
  Duration get _connectTimeout =>
      Duration(seconds: (_useLocal && hasCloud) ? 5 : 10);

  void _setupDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: _connectTimeout,
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
      ),
    );
    _dioReady = true;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // Token eskirgan/yaroqsiz — ilovani login ekraniga qaytaramiz.
          // Login so'rovining o'zidagi 401 "PIN noto'g'ri" degani, u bundan
          // mustasno.
          final path = error.requestOptions.path;
          if (error.response?.statusCode == 401 &&
              _token != null &&
              !path.startsWith('/api/auth/')) {
            if (!_authFailedController.isClosed) {
              _authFailedController.add(null);
            }
            handler.next(error);
            return;
          }
          // Faol manzil javob bermadi — ikkinchisi bo'lsa butun ilovani unga
          // o'tkazamiz. Qaytishni EndpointManager /api/health orqali o'zi hal
          // qiladi: ilgari har bir muvaffaqiyatli javobdan keyin primary'ga
          // qaytilardi, natijada server o'chgan bo'lsa HAR bir so'rov avval
          // 5s local'da kutardi.
          // ONLINE'ga bog'langan so'rov (retseptlar) failover'ni
          // TETIKLAMAYDI: bulut javob bermagani uchun butun ilovani
          // local'ga ko'chirish (yoki teskarisi) noto'g'ri bo'lardi —
          // kassa ishlayotgan serverdan uzilib qolardi.
          if (error.requestOptions.extra[_pinnedCloudFlag] == true) {
            handler.next(error);
            return;
          }
          // Faol server qoidasi (pos_backend internal/nodestate): bulut
          // «passive_node» (409) qaytardi — filialning lokal serveri ishlayapti.
          // So'rov bajarilMAGAN (server yozishdan oldin rad etadi), shuning
          // uchun lokal topilsa uni o'sha yerga qayta yuborish XAVFSIZ.
          if (!_useLocal && _isPassiveNode(error)) {
            final opts = error.requestOptions;
            probeLocal().then((alive) {
              if (!alive || !hasLocal) {
                handler.next(error); // lokal bu qurilmadan ko'rinmaydi
                return;
              }
              _setActive(useLocal: true);
              opts.baseUrl = _baseUrl;
              opts.connectTimeout = _connectTimeout;
              _dio.fetch(opts).then(
                (r) => handler.resolve(r),
                onError: (e) => handler.next(
                  e is DioException
                      ? e
                      : DioException(requestOptions: opts, error: e),
                ),
              );
            });
            return;
          }
          if (_isConnectionError(error) && _canFailover()) {
            _setActive(useLocal: !_useLocal);
            final opts = error.requestOptions;

            // SO'ROVNI QAYTA YUBORISH — FAQAT xavfsiz (idempotent) metodlarda.
            //
            // MUHIM: `connectionError`/`unknown` xatosi so'rov serverga
            // YETIB BORGANDAN KEYIN ham chiqadi (masalan javob paytida WiFi
            // uzilsa). Ilgari bunday POST ikkinchi serverga aynan qaytadan
            // yuborilardi: local master chekni allaqachon yozgan bo'lsa,
            // cloud'da IKKINCHI chek tug'ilardi — mijozdan ikki marta pul,
            // qoldiqdan ikki marta chiqim. Chek yopish ham ikki marta
            // hisoblanardi.
            //
            // GET/HEAD ni qayta yuborish xavfsiz — ular hech narsani
            // o'zgartirmaydi. Yozuvchi so'rovlar esa xato bilan qaytadi va
            // kassir o'zi qayta bosishga qaror qiladi.
            if (_isIdempotent(opts.method)) {
              opts.baseUrl = _baseUrl;
              opts.connectTimeout = _connectTimeout;
              _dio
                  .fetch(opts)
                  .then(
                    (r) => handler.resolve(r),
                    onError: (e) => handler.next(
                      e is DioException
                          ? e
                          : DioException(requestOptions: opts, error: e),
                    ),
                  );
              return;
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  bool _isPassiveNode(DioException error) {
    if (error.response?.statusCode != 409) return false;
    final d = error.response?.data;
    return d is Map && d['error'] == 'passive_node';
  }

  bool _isConnectionError(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown ||
        // `receiveTimeout` ham qo'shildi: server TCP'ni qabul qiladi-yu,
        // javob bermaydi (masalan baza qulflanib qolgan). Ilgari bu holat
        // failover'ni umuman tetiklamasdi — WebSocket "yashil" ko'rinib
        // turar, har bir so'rov esa 10 soniya kutib xato berardi.
        error.type == DioExceptionType.receiveTimeout;
  }

  /// Qayta yuborish xavfsiz bo'lgan metodlar.
  bool _isIdempotent(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD' || m == 'OPTIONS';
  }

  /// Xato bo'lganda ikkinchi manzilga o'tish mumkinmi. Ikkalasi ham o'lgan
  /// bo'lsa har bir so'rov manzilni almashtirib "sakramasligi" uchun cooldown.
  bool _canFailover() {
    final target = _useLocal ? _serverUrl : _localUrl;
    if ((target ?? '').isEmpty) return false;
    final last = _lastFailover;
    if (last != null && DateTime.now().difference(last) < _failoverCooldown) {
      return false;
    }
    return true;
  }

  /// Faol serverni almashtirish. O'zgarish bo'lsa kesh tozalanadi va
  /// endpointStream orqali xabar beriladi (WSS qayta ulanadi, UI yangilanadi).
  void _setActive({required bool useLocal}) {
    final target = useLocal ? _localUrl : _serverUrl;
    if (target == null || target.isEmpty) return;
    final changed = _useLocal != useLocal || _baseUrl != target;
    _useLocal = useLocal;
    _baseUrl = target;
    if (_dioReady) {
      _dio.options.baseUrl = target;
      _dio.options.connectTimeout = _connectTimeout;
    } else {
      _setupDio();
    }
    if (changed) {
      _lastFailover = DateTime.now();
      invalidateAll();
      if (!_endpointController.isClosed) _endpointController.add(!_useLocal);
    }
  }

  /// Foydalanuvchi QO'LDA tanlagan server (`true` = online, `null` = avtomatik).
  ///
  /// NEGA KERAK: `EndpointManager` har 15 soniyada local'ni tekshirib, ikki
  /// marta javob bersa avtomatik unga QAYTARDI. Ya'ni admin "online"ni tanlab
  /// retsept saqlasa, ~30 soniyadan keyin ilova jimgina local'ga o'tib
  /// ketardi va o'sha retseptni qayta ochganda BO'SH ko'rardi — "saqlandi
  /// dedi, lekin saqlanmagan". Ma'lumot aslida bulutda edi.
  bool? _pinnedCloud;

  bool? get pinnedCloud => _pinnedCloud;

  /// Avtomatik almashishga ruxsat bormi (qo'lda tanlov qilinmagan).
  bool get isAutoEndpoint => _pinnedCloud == null;

  /// Qo'lda tanlashni bekor qilish — yana avtomatik rejim.
  void unpinEndpoint() => _pinnedCloud = null;

  /// Online serverga o'tish — local javob bermaganda.
  /// Server sozlanmagan yoki allaqachon onlineda bo'lsa `false` qaytaradi.
  ///
  /// [manual] — foydalanuvchi o'zi tanladi: avtomatik qaytarish taqiqlanadi.
  bool switchToCloud({bool manual = false}) {
    if (manual) _pinnedCloud = true;
    if (!hasCloud || !_useLocal) return false;
    _setActive(useLocal: false);
    return true;
  }

  /// Local server topilganda/ko'tarilganda unga o'tish.
  bool switchToLocal({bool manual = false}) {
    if (manual) _pinnedCloud = false;
    if (_useLocal || !hasLocal) return false;
    _setActive(useLocal: true);
    return true;
  }

  /// Local serverni izlash. Tartib: qo'lda kiritilgan LAN manzil → `localhost`
  /// (ilova server bilan bitta Windows mashinada turgan hol, eng ishonchli) →
  /// standart LAN manzili [kLanServerUrl] (planshetlar hech nima kiritmasa ham
  /// restoran ichida local'ni topsin).
  /// Topilsa [_localUrl] to'ldiriladi — faol manzil bu yerda o'zgarmaydi.
  Future<bool> detectLocal() async {
    final candidates = <String>{
      if ((_lanUrl ?? '').isNotEmpty) _lanUrl!,
      if (_localhostReachable) kLocalhostUrl,
      kLanServerUrl,
    }.toList();
    // Parallel — hammasi javobsiz bo'lsa ham kutish 2 soniyadan oshmaydi.
    final alive = await Future.wait(candidates.map(_ping));
    for (var i = 0; i < candidates.length; i++) {
      if (alive[i]) {
        _localUrl = candidates[i];
        return true;
      }
    }
    _localUrl = null;
    return false;
  }

  /// `localhost` faqat server bilan bitta mashinada turgan desktop ilovada
  /// mantiqiy — planshet/telefonda bu qurilmaning o'zi, u yerda server yo'q.
  bool get _localhostReachable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Local server tirikmi — `/api/health` ga qisqa so'rov (auth talab qilmaydi,
  /// asosiy Dio'ga tegmaydi, shuning uchun failover mantiqini buzmaydi).
  /// Local hali topilmagan bo'lsa qaytadan izlaydi.
  Future<bool> probeLocal() async {
    final url = _localUrl;
    if (url == null || url.isEmpty) return detectLocal();
    if (await _ping(url)) return true;
    _localUrl = null;
    return false;
  }

  Future<bool> _ping(String url) async {
    try {
      final probe = Dio(
        BaseOptions(
          baseUrl: url,
          connectTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
          headers: {'ngrok-skip-browser-warning': 'true'},
          validateStatus: (_) => true,
        ),
      );
      final res = await probe.get('/api/health');
      // Faqat 200 + {"status":"ok"} — shu port bandmi degani yetarli emas:
      // boshqa xizmat yoki WiFi captive portal ham javob berishi mumkin.
      // 503 ("degraded") = server tirik, lekin bazasi yo'q — unga o'tmaymiz.
      if (res.statusCode != 200) return false;
      final data = res.data;
      return data is Map && data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  String get baseUrl => _baseUrl;

  /// Foydalanuvchi server manzilini kiritganmi (birinchi ochilish uchun)
  bool get isConfigured => _configured;

  /// URL ni normallashtirish: bo'sh joyni kesish, sxema bo'lmasa http:// qo'shish,
  /// oxiridagi '/' larni olib tashlash
  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// URL to'g'ri host ega bo'lgan http/https manzilmi
  static bool isValidUrl(String raw) {
    final u = normalizeUrl(raw);
    final uri = Uri.tryParse(u);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Server manzilini saqlash. `serverUrl` — asosiy (online) manzil, majburiy.
  /// `lanUrl` — ixtiyoriy: restoran ichidagi tezkor manzil (planshetlar uchun);
  /// bo'sh qolsa local faqat `localhost` orqali izlanadi.
  /// Saqlangandan keyin local qaytadan aniqlanadi.
  Future<void> setEndpoints({required String serverUrl, String? lanUrl}) async {
    final server = normalizeUrl(serverUrl);
    final rawLan = lanUrl?.trim() ?? '';
    final lan = rawLan.isEmpty ? null : normalizeUrl(rawLan);

    _serverUrl = server;
    _lanUrl = lan;
    _localUrl = null;
    _configured = true;
    _setActive(useLocal: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kassa_server_url', server);
    if (lan != null) {
      await prefs.setString('kassa_lan_url', lan);
    } else {
      await prefs.remove('kassa_lan_url');
    }
    // Eski kalitlar endi kerak emas — qolib ketsa init() ularni qayta tiklaydi.
    await prefs.remove('kassa_local_url');
    await prefs.remove('kassa_base_url');
    await prefs.remove('kassa_cloud_url');

    if (await detectLocal()) _setActive(useLocal: true);
  }

  /// Faqat asosiy manzilni yangilash (LAN manzil saqlanib qoladi).
  Future<void> setBaseUrl(String url) =>
      setEndpoints(serverUrl: url, lanUrl: _lanUrl);

  Future<void> setToken(String? token) async {
    _token = token;
    _setupDio();
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      await prefs.setString('kassa_token', token);
    } else {
      await prefs.remove('kassa_token');
    }
  }

  String? get token => _token;

  bool get isLocal => _mode == AppMode.pos || _mode == AppMode.waiter;

  // Auth
  Future<Map<String, dynamic>> login(String phone, String pin) async {
    final res = await _dio.post(
      '/api/auth/login',
      data: {'phone': phone, 'pin': pin},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> loginByPin(String pin) async {
    final res = await _dio.post('/api/auth/pin-login', data: {'pin': pin});
    return res.data;
  }

  // Menu (cached)
  //
  // `includeInactive` — admin menyusi uchun: nofaol mahsulotlar ham
  // qaytariladi, aks holda ularni qayta yoqib bo'lmaydi. Bunday javob
  // KESHLANMAYDI — POS keshiga nofaol mahsulot tushib qolmasin.
  Future<Map<String, dynamic>> getMenu({
    bool force = false,
    bool includeInactive = false,
  }) async {
    if (includeInactive) {
      final res = await _dio.get(
        '/api/menu',
        queryParameters: const {'include_inactive': '1'},
      );
      return Map<String, dynamic>.from(res.data);
    }
    if (!force && _menuCache != null) return _menuCache!;
    final res = await _dio.get('/api/menu');
    _menuCache = res.data;
    return res.data;
  }

  // Zones (cached)
  Future<List<dynamic>> getZones({bool force = false}) async {
    if (!force && _zonesCache != null) return _zonesCache!;
    final res = await _dio.get('/api/zones');
    _zonesCache = res.data;
    return res.data;
  }

  // Table
  Future<Map<String, dynamic>> getTable(String sku) async {
    final res = await _dio.get('/api/table/$sku');
    return res.data;
  }

  // Orders
  Future<List<dynamic>> getOrders({
    String status = 'active',
    String? date,
  }) async {
    final res = await _dio.get(
      '/api/orders',
      queryParameters: {'status': status, 'date': ?date},
    );
    return res.data;
  }

  // Stocks (cached)
  Future<List<dynamic>> getStocks({bool force = false}) async {
    if (!force && _stocksCache != null) return _stocksCache!;
    final res = await _dio.get('/api/stocks');
    _stocksCache = res.data;
    return res.data;
  }

  // Shift
  Future<Map<String, dynamic>> getShift() async {
    final res = await _dio.get('/api/shift/current');
    return res.data;
  }

  Future<Map<String, dynamic>> openShift(int openingCash) async {
    final res = await _dio.post(
      '/api/shift/open',
      data: {'opening_cash': openingCash},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> closeShift(int actualCash) async {
    final res = await _dio.post(
      '/api/shift/close',
      data: {'actual_cash': actualCash},
    );
    return res.data;
  }

  // Finance
  Future<Map<String, dynamic>> getFinanceDaily(String date) async {
    final res = await _dio.get(
      '/api/finance/daily',
      queryParameters: {'date': date},
    );
    return res.data;
  }

  Future<List<dynamic>> getFinanceExpenses(
    String date, {
    int? categoryId,
  }) async {
    final params = <String, dynamic>{'date': date};
    if (categoryId != null) params['category_id'] = categoryId;
    final res = await _dio.get(
      '/api/finance/daily/expenses',
      queryParameters: params,
    );
    return res.data;
  }

  // Expense categories
  Future<List<dynamic>> getExpenseCategories() async {
    final res = await _dio.get('/api/expense-categories');
    return res.data;
  }

  // Expense category CRUD
  Future<Map<String, dynamic>> createExpenseCategory(
    String nameUz, {
    String nameRu = '',
    String nameTr = '',
  }) async {
    final res = await _dio.post(
      '/api/expense-category',
      data: {'name_uz': nameUz, 'name_ru': nameRu, 'name_tr': nameTr},
    );
    return res.data;
  }

  Future<void> deleteExpenseCategory(int id) async {
    await _dio.delete('/api/expense-category/$id');
  }

  // Expenses
  Future<Map<String, dynamic>> createExpense(
    int categoryId,
    int amount,
    String description,
  ) async {
    final res = await _dio.post(
      '/api/expense',
      data: {
        'category_id': categoryId,
        'amount': amount,
        'description': description,
      },
    );
    return res.data;
  }

  /// Server faqat joriy ochiq smena ichidagi xarajatni o'chiradi.
  Future<void> deleteExpense(int id) async {
    await _dio.delete('/api/expense/$id');
  }

  // Users (cached)
  Future<List<dynamic>> getUsers({bool force = false}) async {
    if (!force && _usersCache != null) return _usersCache!;
    final res = await _dio.get('/api/users');
    _usersCache = res.data;
    return res.data;
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/user', data: data);
    return res.data;
  }

  Future<void> updateUser(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/user/$id', data: data);
  }

  Future<void> deleteUser(int id) async {
    await _dio.delete('/api/user/$id');
  }

  // Order create (HTTP)
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/order/create', data: data);
    return res.data;
  }

  // Order close by table (HTTP) — barcha cheklarni yopadi
  Future<Map<String, dynamic>> closeOrderByTable(
    String tableSKU,
    String paymentMethod, {
    int discount = 0,
    List<Map<String, dynamic>>? payments,
    String? paymentComment,
    String? uzqrInvoiceId,
  }) async {
    final res = await _dio.post(
      '/api/order/close',
      data: {
        'table_sku': tableSKU,
        'payment_method': paymentMethod,
        'discount': discount,
        'payments': ?payments,
        'payment_comment': ?paymentComment,
        'uzqr_invoice_id': ?uzqrInvoiceId,
      },
    );
    return res.data;
  }

  // Stol raqamini almashtirish — stoldagi BARCHA ochiq cheklar boshqa
  // stolga ko'chadi (kassir stolni adashib ochgan bo'lsa)
  Future<Map<String, dynamic>> changeOrderTable(
    String fromSku,
    String toSku,
  ) async {
    final res = await _dio.post(
      '/api/order/change-table',
      data: {'from_table_sku': fromSku, 'to_table_sku': toSku},
    );
    return res.data;
  }

  // Item cancel (1 ta mahsulotni bekor qilish)
  Future<Map<String, dynamic>> cancelItem(
    String orderNumber,
    int productId, {
    int cancelQty = 1,
  }) async {
    final res = await _dio.post(
      '/api/order/cancel-item',
      data: {
        'order_number': orderNumber,
        'product_id': productId,
        'cancel_qty': cancelQty,
      },
    );
    return res.data;
  }

  // Order cancel (chekni bekor qilish)
  Future<Map<String, dynamic>> cancelOrder(String orderNumber) async {
    final res = await _dio.post(
      '/api/order/cancel',
      data: {'order_number': orderNumber},
    );
    return res.data;
  }

  // Order revert (yopilgan chekni faol holatga qaytarish — smena ochiq bo'lsa)
  Future<Map<String, dynamic>> revertOrder(String orderNumber) async {
    final res = await _dio.post(
      '/api/order/revert',
      data: {'order_number': orderNumber},
    );
    return res.data;
  }

  // Yopilgan chekning to'lov usulini o'zgartirish (smena ochiq bo'lsa).
  // Aralash (split) chek ham bitta usulga o'tadi.
  Future<Map<String, dynamic>> changeOrderPayment(
    String orderNumber,
    String paymentMethod, {
    String? paymentComment,
  }) async {
    final res = await _dio.post(
      '/api/order/change-payment',
      data: {
        'order_number': orderNumber,
        'payment_method': paymentMethod,
        'payment_comment': ?paymentComment,
      },
    );
    return res.data;
  }

  // ===== UzQR — dinamik QR orqali to'lov (pos_backend api/uzqr.go) =====

  /// QR ochadi. Javob: {invoice_id, status (1 kutilmoqda / 2 to'langan),
  /// amount, qr_text}. Summasi boshqa to'langan invoys bo'lsa 409
  /// `uzqr_paid_exists` {invoice_id, amount}.
  Future<Map<String, dynamic>> uzqrCreateInvoice({
    required int amount,
    String? tableSku,
    String? orderNumber,
  }) async {
    final res = await _dio.post(
      '/api/uzqr/invoice',
      data: {
        'amount': amount,
        'table_sku': ?tableSku,
        'order_number': ?orderNumber,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> uzqrInvoiceStatus(String invoiceId) async {
    final res = await _dio.get(
      '/api/uzqr/invoice/status',
      queryParameters: {'invoice_id': invoiceId},
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Kutishni bekor qiladi; status=2 qaytsa mijoz ulgurib to'lagan.
  Future<Map<String, dynamic>> uzqrCancelInvoice(String invoiceId) async {
    final res = await _dio.post(
      '/api/uzqr/invoice/cancel',
      data: {'invoice_id': invoiceId},
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Chekka yozilmagan to'lovni mijozga qaytaradi (asinxron: refund_status).
  Future<Map<String, dynamic>> uzqrRefund(String invoiceId) async {
    final res = await _dio.post(
      '/api/uzqr/refund',
      data: {'invoice_id': invoiceId},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> uzqrRefundStatus(String invoiceId) async {
    final res = await _dio.get(
      '/api/uzqr/refund/status',
      queryParameters: {'invoice_id': invoiceId},
    );
    return Map<String, dynamic>.from(res.data);
  }

  // Order close by order_number (Saboy/Dostafka)
  Future<Map<String, dynamic>> closeOrderByNumber(
    String orderNumber,
    String paymentMethod, {
    int discount = 0,
    List<Map<String, dynamic>>? payments,
    String? paymentComment,
    String? uzqrInvoiceId,
  }) async {
    final res = await _dio.post(
      '/api/order/close',
      data: {
        'order_number': orderNumber,
        'payment_method': paymentMethod,
        'discount': discount,
        'payments': ?payments,
        'payment_comment': ?paymentComment,
        'uzqr_invoice_id': ?uzqrInvoiceId,
      },
    );
    return res.data;
  }

  // Products
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/product', data: data);
    return res.data;
  }

  Future<void> deleteProduct(int id) async {
    await _dio.delete('/api/product/$id');
  }

  Future<Map<String, dynamic>> uploadProductImage(
    int productId,
    String filePath,
  ) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post(
      '/api/upload/product-image/$productId',
      data: formData,
    );
    await _cacheUploaded(res.data, filePath);
    return res.data;
  }

  /// Yangi rasm faol serverga tushdi, asosiy serverga esa ≤60s da
  /// replikatsiya bo'ladi. Shu oraliqda rasm ochilmay qolmasin — yuklangan
  /// faylni darhol keshga qo'yamiz.
  Future<void> _cacheUploaded(dynamic response, String filePath) async {
    if (response is! Map) return;
    // mahsulot → image_url, kategoriya → icon_url
    final url = (response['image_url'] ?? response['icon_url']) as String?;
    if (url != null && url.isNotEmpty) {
      await MediaCache().putFile(url, filePath);
    }
  }

  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.put('/api/product/$id', data: data);
    return res.data;
  }

  /// Mahsulotni Yandex Eda menyusiga chiqarish / olib tashlash.
  ///
  /// Yandex menyuni O'ZI tortadi (pull-model), shuning uchun bu chaqiruv
  /// mahsulotni BELGILAYDI. Javobda Yandexda turadigan narx (`yandex_price`)
  /// va nimasi yetishmayotgani (`warnings`) qaytadi.
  Future<Map<String, dynamic>> setProductYandex(
    int id,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/api/product/$id/yandex', data: data);
    return res.data as Map<String, dynamic>;
  }

  /// Yandexga AYNAN nima ketishini ko'rish (rus tilida, ustamali narx bilan).
  Future<Map<String, dynamic>> getYandexMenuPreview() async {
    final res = await _dio.get('/api/yandex/menu-preview');
    return res.data as Map<String, dynamic>;
  }

  /// Integratsiya holati: kalitlar bormi, kabinetga qaysi manzil beriladi,
  /// nechta mahsulot chiqarilgan.
  Future<Map<String, dynamic>> getYandexStatus() async {
    final res = await _dio.get('/api/yandex/status');
    return res.data as Map<String, dynamic>;
  }

  /// Yandex «to'liq stop» — hamma taom qoldig'i 0, zakaz qabul qilinmaydi.
  Future<void> setYandexStopAll(bool stop) async {
    await _dio.put('/api/yandex/stop-all', data: {'stop': stop});
  }

  // Stock
  Future<void> setStock(int productId, int count) async {
    await _dio.post(
      '/api/stock/set',
      data: {'product_id': productId, 'count': count},
    );
  }

  /// "Tayyor keladi" mahsulot kirimi — kelgan soni bazaga QO'SHILADI
  Future<Map<String, dynamic>> addStock(int productId, int qty) async {
    final res = await _dio.post(
      '/api/stock/add',
      data: {'product_id': productId, 'qty': qty},
    );
    return res.data;
  }

  Future<void> removeStock(int productId) async {
    await _dio.post('/api/stock/remove', data: {'product_id': productId});
  }

  Future<void> reorder(
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> products,
  ) async {
    await _dio.post(
      '/api/reorder',
      data: {'categories': categories, 'products': products},
    );
  }

  // Categories
  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/category', data: data);
    return res.data;
  }

  // Zones
  Future<Map<String, dynamic>> createZone(String name, int count) async {
    final res = await _dio.post(
      '/api/zone',
      data: {'name': name, 'count': count},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> updateZone(
    int id,
    String name,
    int count,
  ) async {
    final res = await _dio.put(
      '/api/zone/$id',
      data: {'name': name, 'count': count},
    );
    return res.data;
  }

  Future<void> deleteZone(int id) async {
    await _dio.delete('/api/zone/$id');
  }

  // Printers
  Future<List<dynamic>> getPrinters() async {
    final res = await _dio.get('/api/printers');
    return res.data;
  }

  Future<Map<String, dynamic>> createPrinter(
    String name,
    String address,
  ) async {
    final res = await _dio.post(
      '/api/printers',
      data: {'name': name, 'address': address},
    );
    return res.data;
  }

  Future<void> updatePrinter(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/printers/$id', data: data);
  }

  Future<void> deletePrinter(int id) async {
    await _dio.delete('/api/printers/$id');
  }

  // Chek printeri — qaysi printerga chek chiqadi
  Future<Map<String, dynamic>> getReceiptPrinter() async {
    final res = await _dio.get('/api/settings/receipt-printer');
    return Map<String, dynamic>.from(res.data);
  }

  /// [printerId] null bo'lsa — avtomatik tanlov ("chek" nomli printer / birinchi aktiv)
  Future<void> setReceiptPrinter(int? printerId) async {
    await _dio.put(
      '/api/settings/receipt-printer',
      data: {'printer_id': printerId},
    );
  }

  // Print receipt
  Future<void> printReceipt({
    String? orderNumber,
    String? tableSku,
    String? printerAddress,
  }) async {
    await _dio.post(
      '/api/order/print-receipt',
      data: {
        'order_number': ?orderNumber,
        'table_sku': ?tableSku,
        'printer_address': ?printerAddress,
      },
    );
  }

  // Category update
  Future<void> updateCategory(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/category/$id', data: data);
  }

  Future<void> deleteCategory(int id) async {
    await _dio.delete('/api/category/$id');
  }

  Future<Map<String, dynamic>> uploadCategoryImage(
    int categoryId,
    String filePath,
  ) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post(
      '/api/upload/category-image/$categoryId',
      data: formData,
    );
    await _cacheUploaded(res.data, filePath);
    return res.data;
  }

  // Spisaniya (hisobdan chiqarish)
  Future<Map<String, dynamic>> createWriteOff(
    int productId,
    int qty,
    String reason,
    String? note,
  ) async {
    final res = await _dio.post(
      '/api/write-offs',
      data: {
        'product_id': productId,
        'qty': qty,
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getWriteOffs() async {
    final res = await _dio.get(
      '/api/write-offs',
      queryParameters: {'limit': 50},
    );
    return res.data;
  }

  // Inventarizatsiya
  Future<Map<String, dynamic>> submitInventory(
    List<Map<String, dynamic>> items,
  ) async {
    final res = await _dio.post('/api/inventory', data: {'items': items});
    return res.data;
  }

  // ===== Ingredientlar ombori =====

  Future<Map<String, dynamic>> getIngredients() async {
    final res = await _dio.get('/api/ingredients');
    return res.data;
  }

  Future<Map<String, dynamic>> createIngredient(
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/api/ingredient', data: data);
    return res.data;
  }

  Future<void> updateIngredient(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/ingredient/$id', data: data);
  }

  Future<void> deleteIngredient(int id) async {
    await _dio.delete('/api/ingredient/$id');
  }

  // Korreksiya — haqiqiy qoldiqni kiritish
  Future<Map<String, dynamic>> adjustIngredient(
    int ingredientId,
    int newCount,
    String comment,
  ) async {
    final res = await _dio.post(
      '/api/ingredient/adjust',
      data: {
        'ingredient_id': ingredientId,
        'new_count': newCount,
        'comment': comment,
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getIngredientMoves({
    int? ingredientId,
    int limit = 50,
  }) async {
    final res = await _dio.get(
      '/api/ingredient/moves',
      queryParameters: {'ingredient_id': ?ingredientId, 'limit': limit},
    );
    return res.data;
  }

  // ===== Bozor (xaridlar) =====

  Future<Map<String, dynamic>> getBozorList() async {
    final res = await _dio.get('/api/bozor/list');
    return res.data;
  }

  Future<Map<String, dynamic>> createPurchase(
    String note,
    List<Map<String, dynamic>> items, {
    int? supplierId,
  }) async {
    final res = await _dio.post(
      '/api/purchase',
      data: {'note': note, 'items': items, 'supplier_id': ?supplierId},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getPurchases({int limit = 50}) async {
    final res = await _dio.get(
      '/api/purchases',
      queryParameters: {'limit': limit},
    );
    return res.data;
  }

  Future<void> deletePurchase(int id) async {
    await _dio.delete('/api/purchase/$id');
  }

  // ===== Yetkazib beruvchilar va ingredient partiyalari =====

  Future<List<dynamic>> getSuppliers() async {
    final res = await _dio.get('/api/suppliers');
    return res.data as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> createSupplier(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/suppliers', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> updateSupplier(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/suppliers/$id', data: data);
  }

  Future<void> deleteSupplier(int id) async {
    await _dio.delete('/api/suppliers/$id');
  }

  Future<Map<String, dynamic>> getIngredientBatches({
    int? ingredientId,
    String? status,
  }) async {
    final res = await _dio.get(
      '/api/ingredient-batches',
      queryParameters: {
        'ingredient_id': ?ingredientId,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> createIngredientBatch(
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/api/ingredient-batches', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> updateIngredientBatch(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/ingredient-batches/$id', data: data);
  }

  Future<void> writeOffIngredientBatch(int id, {String note = ''}) async {
    await _dio.post(
      '/api/ingredient-batches/$id/write-off',
      data: {'note': note.trim()},
    );
  }

  Future<void> deleteIngredientBatch(int id) async {
    await _dio.delete('/api/ingredient-batches/$id');
  }

  // ===== Retseptlar (partiya bo'yicha) =====
  //
  // RETSEPTLAR DOIM ASOSIY (ONLINE) SERVERDA saqlanadi va o'qiladi.
  //
  // NEGA: retsept — sekin o'zgaradigan, bitta "haqiqat manbai" bo'lishi
  // kerak bo'lgan ma'lumot. Ilova esa local va online o'rtasida avtomatik
  // almashadi, ya'ni retsept bir serverga yozilib, ekran ikkinchisidan
  // o'qishi mumkin edi — foydalanuvchi "saqlandi dedi, lekin saqlanmagan"
  // holatini ko'rardi. Endi manzil qat'iy: qaysi serverda ishlayotganidan
  // qat'i nazar retsept online'ga ketadi.
  //
  // Online sozlanmagan (to'liq offline o'rnatish) bo'lsa — odatdagi
  // nisbiy manzil ishlatiladi.

  /// Retsept endpointining TO'LIQ manzili (online serverga bog'langan).
  String _recipePath(String path) {
    final cloud = _serverUrl;
    if (cloud == null || cloud.isEmpty) return path;
    return '$cloud$path';
  }

  /// Bu so'rov ataylab online serverga ketyapti — failover uni boshqa
  /// serverga ko'chirmasin va butun ilovani almashtirmasin.
  Options get _pinnedCloudOptions =>
      Options(extra: const {_pinnedCloudFlag: true});

  Future<Map<String, dynamic>> getRecipes() async {
    final res = await _dio.get(
      _recipePath('/api/recipes'),
      options: _pinnedCloudOptions,
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getRecipe(int productId) async {
    final res = await _dio.get(
      _recipePath('/api/recipe'),
      queryParameters: {'product_id': productId},
      options: _pinnedCloudOptions,
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> saveRecipe(
    int productId,
    int batchQty,
    List<Map<String, dynamic>> items,
  ) async {
    final res = await _dio.put(
      _recipePath('/api/recipe'),
      data: {'product_id': productId, 'batch_qty': batchQty, 'items': items},
      options: _pinnedCloudOptions,
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> deleteRecipe(int productId) async {
    await _dio.delete(
      _recipePath('/api/recipe/$productId'),
      options: _pinnedCloudOptions,
    );
  }

  Future<Map<String, dynamic>> getRecipeCostPinned(int productId) async {
    final res = await _dio.get(
      _recipePath('/api/recipe/cost'),
      queryParameters: {'product_id': productId},
      options: _pinnedCloudOptions,
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Audit jurnalidan retseptlarni tiklash.
  ///
  /// [apply] `false` — faqat hisobot (hech narsa yozilmaydi).
  /// [overwrite] `true` — farq qilayotganlarini ham jurnaldagi oxirgi
  /// holatga qaytaradi.
  Future<Map<String, dynamic>> recoverRecipes({
    bool apply = false,
    bool overwrite = false,
  }) async {
    final path = _recipePath('/api/recipes/recover');
    final query = overwrite ? {'mode': 'all'} : <String, dynamic>{};
    final res = apply
        ? await _dio.post(
            path,
            queryParameters: query,
            options: _pinnedCloudOptions,
          )
        : await _dio.get(
            path,
            queryParameters: query,
            options: _pinnedCloudOptions,
          );
    return Map<String, dynamic>.from(res.data);
  }

  /// Retsept online serverda saqlanadimi (foydalanuvchiga aytish uchun).
  bool get recipesGoOnline => (_serverUrl ?? '').isNotEmpty;

  Future<Map<String, dynamic>> getRecipeCost(int productId) async {
    final res = await _dio.get(
      '/api/recipe/cost',
      queryParameters: {'product_id': productId},
    );
    return res.data;
  }

  // ===== Pishirish =====

  Future<Map<String, dynamic>> getCookingNeeded() async {
    final res = await _dio.get('/api/cooking/needed');
    return res.data;
  }

  Future<Map<String, dynamic>> startCooking(int productId, int qty) async {
    final res = await _dio.post(
      '/api/cooking/start',
      data: {'product_id': productId, 'qty': qty},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> finishCooking(int id) async {
    final res = await _dio.post('/api/cooking/$id/done');
    return res.data;
  }

  Future<Map<String, dynamic>> cancelCooking(int id) async {
    final res = await _dio.post('/api/cooking/$id/cancel');
    return res.data;
  }

  Future<Map<String, dynamic>> getCookings({
    String? status,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      '/api/cookings',
      queryParameters: {'status': ?status, 'limit': limit},
    );
    return res.data;
  }

  // Tayyor mahsulot limiti (shu miqdorgacha pishiriladi)
  Future<void> setStockLimit(int productId, int limitQty) async {
    await _dio.post(
      '/api/stock/limit',
      data: {'product_id': productId, 'limit_qty': limitQty},
    );
  }

  // ===== Analitika =====

  Future<Map<String, dynamic>> getProductAnalytics() async {
    final res = await _dio.get('/api/analytics/products');
    return res.data;
  }

  Future<Map<String, dynamic>> getAnalyticsOverview({
    required String from,
    required String to,
  }) async {
    final res = await _dio.get(
      '/api/analytics/overview',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<int>> exportAnalyticsCsv({
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<List<int>>(
      '/api/analytics/export.csv',
      queryParameters: {'from': from, 'to': to},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? <int>[];
  }

  // ===== CRM, sodiqlik va promo-kodlar =====

  Future<Map<String, dynamic>> getCustomers({
    String search = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/customers',
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getCustomer(int id) async {
    final res = await _dio.get('/api/customers/$id');
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- Telegram klientski bazasi ----------
  //
  // Botga `/start` bosgan odamlar. Ro'yxat replikatsiya qilinadi, ya'ni
  // kassa local serverga ulangan bo'lsa ham to'liq ko'rinadi; xabarni esa
  // bot ishlaydigan node (bulut) yuboradi.

  Future<Map<String, dynamic>> getTgCustomers({
    String search = '',
    String filter = '',
    int limit = 200,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/tg/customers',
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (filter.trim().isNotEmpty) 'filter': filter.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Ommaviy xabar nechta odamga ketishi (yuborishdan oldin ko'rsatiladi).
  Future<Map<String, dynamic>> getTgBroadcastPreview(String audience) async {
    final res = await _dio.get(
      '/api/tg/broadcast/preview',
      queryParameters: {'audience': audience},
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Ommaviy xabar uchun rasmni serverga yuklaydi va nisbiy yo'lini
  /// qaytaradi (`/uploads/broadcasts/...`). Telegramga rasmni yuborish
  /// paytida bot ishlaydigan node yuklaydi.
  Future<String> uploadTgBroadcastPhoto(String filePath) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post('/api/tg/broadcast/photo', data: formData);
    final url = (res.data['photo_url'] ?? '') as String;
    // Ko'rish uchun darhol keshga — sync tugaguncha boshqa node'da yo'q.
    if (url.isNotEmpty) await MediaCache().putFile(url, filePath);
    return url;
  }

  /// [scheduledAt] berilsa xabar o'sha vaqtda yuboriladi (aks holda darhol).
  Future<Map<String, dynamic>> sendTgBroadcast({
    required String text,
    String audience = 'all',
    String photoUrl = '',
    String buttonText = '',
    String buttonUrl = '',
    DateTime? scheduledAt,
  }) async {
    final res = await _dio.post(
      '/api/tg/broadcast',
      data: {
        'text': text,
        'audience': audience,
        'photo_url': photoUrl,
        'button_text': buttonText,
        'button_url': buttonUrl,
        if (scheduledAt != null)
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  // ---------- Mijoz izohlari ----------

  Future<Map<String, dynamic>> getReviews({
    int days = 30,
    int minRating = 0,
    int maxRating = 0,
    bool unhandled = false,
    String search = '',
    int limit = 100,
  }) async {
    final res = await _dio.get(
      '/api/reviews',
      queryParameters: {
        'days': days,
        if (minRating > 0) 'min_rating': minRating,
        if (maxRating > 0) 'max_rating': maxRating,
        if (unhandled) 'unhandled': 1,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'limit': limit,
      },
    );
    return Map<String, dynamic>.from(res.data);
  }

  /// Mijozga javob yozadi — telegram orqali o'ziga yetadi.
  Future<void> replyToReview(int id, String text) async {
    await _dio.post('/api/reviews/$id/reply', data: {'text': text});
  }

  Future<void> setReviewHandled(int id, bool handled) async {
    await _dio.post('/api/reviews/$id/handled', data: {'handled': handled});
  }

  Future<List<Map<String, dynamic>>> getTgBroadcasts({int limit = 30}) async {
    final res = await _dio.get(
      '/api/tg/broadcasts',
      queryParameters: {'limit': limit},
    );
    final items = (res.data['items'] as List?) ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> cancelTgBroadcast(int id) async {
    await _dio.post('/api/tg/broadcast/$id/cancel');
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/customers', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> updateCustomer(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/customers/$id', data: data);
  }

  Future<Map<String, dynamic>> updateCustomerLoyalty(
    int id, {
    required String type,
    required int points,
    String note = '',
  }) async {
    final res = await _dio.post(
      '/api/customers/$id/loyalty',
      data: {'type': type, 'points': points, 'note': note.trim()},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<dynamic>> getPromos() async {
    final res = await _dio.get('/api/promos');
    return res.data as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> createPromo(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/promos', data: data);
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> updatePromo(int id, Map<String, dynamic> data) async {
    await _dio.put('/api/promos/$id', data: data);
  }

  Future<void> deletePromo(int id) async {
    await _dio.delete('/api/promos/$id');
  }

  // ===== Bulut sozlamalari (super_admin) =====

  Future<Map<String, dynamic>> getCloudSettings() async {
    final res = await _dio.get('/api/settings/cloud');
    return res.data;
  }

  Future<void> setCloudSettings(String url, String token) async {
    await _dio.put('/api/settings/cloud', data: {'url': url, 'token': token});
  }

  // ===== Mone integratsiyasi (katalog Mone'dan, cheklar/smenalar Mone'ga) =====

  /// Mone filial bo'limlari (Bar, Oshxona…) va ularga biriktirilgan printerlar.
  Future<List<dynamic>> getMoneDepartments() async {
    final res = await _dio.get('/api/mone/departments');
    return res.data is List ? res.data as List : const [];
  }

  Future<Map<String, dynamic>> getMoneStatus() async {
    final res = await _dio.get('/api/mone/status');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Darhol sinxron: katalog majburan + cheklar/smenalar. Xatoda ham holat
  /// qaytadi ({ok:false, error, status}) — 502 javobi istisno emas.
  Future<Map<String, dynamic>> syncMone() async {
    final res = await _dio.post('/api/mone/sync',
        options: Options(
            validateStatus: (s) => s != null && s < 600,
            receiveTimeout: const Duration(minutes: 2)));
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    return {'ok': false, 'error': 'HTTP ${res.statusCode}'};
  }

  // ===== Markazdan kelgan yuk va smena qoldig'i (Mone filial_supply) =====
  // Miqdorlar MILLI butun son: кг/л → гр/мл, шт → dona×1000.

  /// Filialga kelgan, hali qabul qilinmagan buyurtmalar: {orders:[...]}.
  Future<List<Map<String, dynamic>>> getMoneIncoming() async {
    final res = await _dio.get('/api/mone/incoming');
    final list = (res.data is Map ? res.data['orders'] : null) as List? ?? const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  /// Kelgan sonni tasdiqlash. items: [{product_id, received_milli}] —
  /// ro'yxatda yo'q qator = to'liq keldi.
  Future<Map<String, dynamic>> acceptMoneIncoming(
      int orderId, List<Map<String, dynamic>> items) async {
    final res = await _dio.post('/api/mone/incoming/accept',
        data: {'order_id': orderId, 'items': items});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Bo'lim qoldig'i (tizim soni) + oldingi smena kassiri.
  Future<Map<String, dynamic>> getMoneStockCountDraft({int? departmentId}) async {
    final res = await _dio.get('/api/mone/stock-count/draft',
        queryParameters: {if (departmentId != null) 'department_id': departmentId},
        options: Options(receiveTimeout: const Duration(minutes: 2)));
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Sanalgan son. items: [{product_id, counted_milli}] — yuborilmagan qator
  /// tizimdagidek qoladi.
  Future<Map<String, dynamic>> saveMoneStockCount(
      int? departmentId, List<Map<String, dynamic>> items) async {
    final res = await _dio.post('/api/mone/stock-count', data: {
      if (departmentId != null) 'department_id': departmentId,
      'items': items,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<Map<String, dynamic>>> getMoneRejected() async {
    final res = await _dio.get('/api/mone/rejected');
    final list = res.data is List ? res.data as List : const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  // ===== Asoschilar — to'lov oynasidagi «ichki hisob» usullari =====
  // Manba: qilinadigan_ishlar «Получатель расхода (владелец)», Mone orqali
  // kassa serveriga sinxron (pos_backend db/owners.go).

  Future<Map<String, dynamic>> getKassaOwners() async {
    final res = await _dio.get('/api/kassa/owners');
    return res.data is Map ? Map<String, dynamic>.from(res.data) : const {};
  }

  /// Asoschiga so'rovlar holati (so'nggi 3 kun).
  Future<List<Map<String, dynamic>>> getOwnerRequests() async {
    final res = await _dio.get('/api/kassa/owner-requests');
    final list = res.data is List ? res.data as List : const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  // ===== Qoldiq nazorati rejimi: strict (qat'iy) / soft (test, minusga ruxsat) =====

  Future<String> getStockMode() async {
    final res = await _dio.get('/api/settings/stock-mode');
    return (res.data['mode'] as String?) ?? 'strict';
  }

  Future<void> setStockMode(String mode) async {
    await _dio.put('/api/settings/stock-mode', data: {'mode': mode});
  }

  // ===== Tizim nazorati: monitoring, audit va backup =====

  Future<Map<String, dynamic>> getOperationsSummary() async {
    final res = await _dio.get('/api/operations/summary');
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<dynamic>> getAuditLogs({int limit = 100}) async {
    final res = await _dio.get('/api/audit', queryParameters: {'limit': limit});
    return res.data['items'] as List<dynamic>? ?? [];
  }

  Future<Map<String, dynamic>> getBackups() async {
    final res = await _dio.get('/api/backups');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> createBackup() async {
    final res = await _dio.post('/api/backups');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> scheduleBackupRestore(String filename) async {
    final safeName = Uri.encodeComponent(filename);
    final res = await _dio.post('/api/backups/$safeName/restore');
    return Map<String, dynamic>.from(res.data);
  }

  // ===== Musiqa (YouTube fon musiqasi) =====
  //
  // Pleer restorandagi Windows kassada chalinadi; bu metodlar qaysi serverga
  // ulangan bo'lsak o'shanga boradi — buyruq bulut orqali kelsa ham sync
  // kassagacha yetkazadi. Holat yangilanishi `music:state` / `music:changed`
  // WSS eventlari bilan keladi.

  Future<Map<String, dynamic>> musicState() async {
    final res = await _dio.get('/api/music/state');
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<dynamic>> musicSearch(String query) async {
    final res = await _dio.get(
      '/api/music/search',
      queryParameters: {'q': query},
    );
    return res.data['results'] as List<dynamic>? ?? [];
  }

  Future<void> musicCommand(String action, [num? value]) async {
    await _dio.post(
      '/api/music/command',
      data: {'action': action, 'value': ?value},
    );
  }

  Future<void> musicQueueAdd(
    Map<String, dynamic> item, {
    bool playNow = false,
  }) async {
    await _dio.post(
      '/api/music/queue',
      data: {
        'video_id': item['video_id'],
        'title': item['title'] ?? '',
        'channel': item['channel'] ?? '',
        'duration_sec': item['duration_sec'] ?? 0,
        'thumbnail': item['thumbnail'] ?? '',
        'play_now': playNow,
      },
    );
  }

  Future<void> musicQueueRemove(int id) async {
    await _dio.delete('/api/music/queue/$id');
  }

  Future<void> musicQueueReorder(List<int> ids) async {
    await _dio.post('/api/music/queue/reorder', data: {'ids': ids});
  }

  Future<void> musicQueueClear() async {
    await _dio.post('/api/music/queue/clear');
  }

  Future<Map<String, dynamic>> musicPlaylistCreate(
    String name, {
    bool fromQueue = true,
  }) async {
    final res = await _dio.post(
      '/api/music/playlists',
      data: {'name': name, 'from_queue': fromQueue},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> musicPlaylistAddItem(
    int playlistId,
    Map<String, dynamic> item,
  ) async {
    await _dio.post(
      '/api/music/playlists/$playlistId/items',
      data: {
        'video_id': item['video_id'],
        'title': item['title'] ?? '',
        'channel': item['channel'] ?? '',
        'duration_sec': item['duration_sec'] ?? 0,
        'thumbnail': item['thumbnail'] ?? '',
      },
    );
  }

  Future<List<dynamic>> musicPlaylistItems(int id) async {
    final res = await _dio.get('/api/music/playlists/$id');
    return res.data['items'] as List<dynamic>? ?? [];
  }

  Future<void> musicPlaylistPlay(int id) async {
    await _dio.post('/api/music/playlists/$id/play');
  }

  Future<void> musicPlaylistRemoveItem(int playlistId, int itemId) async {
    await _dio.delete('/api/music/playlists/$playlistId/items/$itemId');
  }

  Future<void> musicPlaylistDelete(int id) async {
    await _dio.delete('/api/music/playlists/$id');
  }

  // Health
  Future<Map<String, dynamic>> getHealth() async {
    final res = await _dio.get('/api/health');
    return res.data;
  }
}
