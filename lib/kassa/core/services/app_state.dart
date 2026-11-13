import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'wss_service.dart';
import 'local_db.dart';

/// Global app state — WSS orqali real-time yangiendilanadi
/// Menu/categories/tables — SQLite dan (version bilan sync)
/// Table statuses + orders — in-memory (WSS dan)
class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._();
  factory AppState() => _instance;
  AppState._();

  // Real-time data (WSS dan)

  Map<String, TableState> tables = {}; // sku → TableState
  List<Map<String, dynamic>> activeOrders = [];
  List<Map<String, dynamic>> stocks = [];

  /// Qoldiq nazorati: true = yumshoq (test) rejim — qoldiq yetmasa ham
  /// sotiladi, qoldiq minusga tushadi; qoldiqsiz mahsulot ham POS'da
  /// ko'rinadi. Server WSS init (`stock_mode`) va `stock_mode:changed`
  /// eventi bilan beradi.
  bool stockSoft = false;
  Map<String, dynamic>? shift; // to'liq shift data (init:ok dan)

  /// Kirgan foydalanuvchi roli (login'da to'ldiriladi, logout'da tozalanadi).
  /// POS menyusida nofaol mahsulotlarni kimga ko'rsatishni shu hal qiladi.
  String? role;

  /// Kirgan xodimning ismi — admin panelining yon panelida ko'rsatiladi.
  String? userName;

  /// Nofaol mahsulot/kategoriyalar menyuda ko'rinsinmi — faqat super_admin
  /// va kassirga. Ofitsiant/oshxona faqat faollarni ko'radi.
  bool get canSeeInactiveMenu => role == 'super_admin' || role == 'cashier';

  // In-memory menu cache (instant access, no DB hit)
  List<Map<String, dynamic>>? _cachedCategories;
  List<Map<String, dynamic>>? _cachedProducts;
  List<Map<String, dynamic>>? get cachedCategories => _cachedCategories;
  List<Map<String, dynamic>>? get cachedProducts => _cachedProducts;
  void setMenuCache(
      List<Map<String, dynamic>> cats, List<Map<String, dynamic>> prods) {
    _cachedCategories = cats;
    _cachedProducts = prods;
  }
  void invalidateMenuCache() {
    _cachedCategories = null;
    _cachedProducts = null;
  }

  // Local versions
  int _menuVersion = 0;
  int _categoriesVersion = 0;
  int _tablesVersion = 0;

  /// Serverning oxirgi e'lon qilgan stollar versiyasi (init:ok dan).
  int _serverTablesVersion = 1;

  StreamSubscription? _wssSub;
  bool _initialized = false;

  /// Log — faqat debug rejimda. `print` release build'da ham yozardi.
  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Load local versions
    final versions = await LocalDB().getAllVersions();
    _menuVersion = versions['menu'] ?? 0;
    _categoriesVersion = versions['categories'] ?? 0;
    _tablesVersion = versions['tables'] ?? 0;

    // Pre-warm menu cache (sinxron OrderScreen uchun, DB hit yo'q).
    // Nofaollar HAM olinadi — kim ko'rishini OrderScreen rolga qarab
    // hal qiladi (qarang: canSeeInactiveMenu).
    final cats = await LocalDB().getCategories(includeInactive: true);
    final prods = await LocalDB().getProducts(includeInactive: true);
    if (cats.isNotEmpty) {
      setMenuCache(cats, prods);
    }

    // Listen WSS
    _wssSub = WssService().eventStream.listen(_handleEvent);

    // HTTP ZAXIRASI.
    //
    // MUAMMO: smena, qoldiq va faol cheklar FAQAT WebSocket'ning `init:ok`
    // xabaridan to'lardi. Agar WSS ko'tarilmasa (proxy ws'ni bloklasa,
    // bulut rejimida yoki tarmoq WebSocket'ga ruxsat bermasa) — oddiy HTTP
    // mukammal ishlab tursa ham — POS BUTUNLAY ishlamay qolardi: "Smena
    // ochilmagan" deb turar, menyu bo'sh ko'rinar, kassir bitta ham
    // buyurtma ocholmasdi.
    //
    // Endi WSS uzilib qolsa HTTP orqali yuklab olamiz.
    WssService().connectionStream.listen((connected) {
      if (!connected) _scheduleHttpFallback();
    });
    _scheduleHttpFallback();
  }

  Timer? _fallbackTimer;

  void _scheduleHttpFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 6), () {
      if (WssService().isConnected) return;
      // Faqat tizimga kirgan bo'lsak — tokensiz so'rov 401 beradi.
      if ((ApiService().token ?? '').isEmpty) return;
      loadOverHttp();
    });
  }

  /// Smena, qoldiq va faol cheklarni HTTP orqali yuklash.
  /// WSS ishlamayotganda POS ishlashda davom etishi uchun.
  Future<void> loadOverHttp() async {
    try {
      final results = await Future.wait([
        ApiService().getShift(),
        ApiService().getStocks(force: true),
        ApiService().getOrders(),
      ]);
      final shiftData = results[0] as Map<String, dynamic>;
      shift = shiftData;
      stocks = (results[1] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      activeOrders = (results[2] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
      _log('HTTP fallback: smena/qoldiq/cheklar yuklandi');
      notifyListeners();
    } catch (e) {
      _log('HTTP fallback failed: $e');
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    final e = event['event'] as String?;
    final payload = event['payload'];

    switch (e) {
      // ===== Table status =====
      case 'table:status_changed':
        if (payload is Map<String, dynamic>) {
          final sku = payload['table_sku'] as String?;
          if (sku != null) {
            tables[sku] = TableState(
              status: payload['status'] ?? 'free',
              orderNumber: payload['order_number'] as String?,
            );
            notifyListeners();
          }
        }

      // ===== New order =====
      case 'order:new':
        if (payload is Map<String, dynamic>) {
          final order = payload['order'] as Map<String, dynamic>?;
          if (order != null) {
            // Dedupe: qaytarilgan (revert) chek uchun `order:new` va sync'dan
            // kelgan `order:updated` (to'liq qator) ikkalasi ham qo'shishi
            // mumkin — bitta chek ro'yxatda ikki marta ko'rinmasin.
            activeOrders.removeWhere(
                (o) => o['order_number'] == order['order_number']);
            activeOrders.insert(0, order);
            // Update table status
            final sku = order['table_sku'] as String?;
            if (sku != null) {
              tables[sku] = TableState(
                status: 'occupied',
                orderNumber: order['order_number'] as String?,
              );
            }
            notifyListeners();
          }
        }

      // ===== Order closed =====
      case 'order:closed':
        if (payload is Map<String, dynamic>) {
          // FAQAT server aytgan chek raqamlari olib tashlanadi.
          //
          // Ilgari `table_sku` bo'yicha ham tozalanardi va bu jiddiy xato
          // edi: stolda 3 ta alohida chek bo'lsa, bittasi yopilganda
          // qolgan IKKITASI ham POS ekranidan yo'qolardi — ular to'lanmagan
          // holda ochiq qolar, lekin kassir ularni ko'rmasdi.
          final nums = <String>{};
          final single = payload['order_number'];
          if (single is String && single.isNotEmpty) nums.add(single);
          final list = payload['order_numbers'];
          if (list is List) {
            for (final n in list) {
              if (n is String && n.isNotEmpty) nums.add(n);
            }
          }
          if (nums.isNotEmpty) {
            activeOrders.removeWhere((o) => nums.contains(o['order_number']));
          }
          notifyListeners();
        }

      // ===== Order cancelled =====
      // Sync qatlami boshqa node'da bekor qilingan chek uchun AYNAN shu
      // nomni yuboradi (internal/sync/apply.go). Ilgari u hech qayerda
      // ushlanmasdi: chek POS'da "faol" bo'lib qolib, smenani yopishga
      // to'sqinlik qilardi.
      case 'order:cancelled':
        if (payload is Map<String, dynamic>) {
          final num = payload['order_number'];
          if (num is String && num.isNotEmpty) {
            activeOrders.removeWhere((o) => o['order_number'] == num);
          }
          notifyListeners();
        }

      // ===== To'liq resync tugadi =====
      // Server snapshot paytida minglab xabar o'rniga bitta umumiy signal
      // yuboradi (internal/sync/replication.go). Bularsiz qoldiq va faol
      // cheklar resync'dan keyin eski holatda muzlab qolardi.
      case 'stock:refresh':
        _scheduleStocksSync();

      // ===== Qoldiq nazorati rejimi o'zgardi (strict/soft) =====
      case 'stock_mode:changed':
        if (payload is Map<String, dynamic>) {
          stockSoft = payload['mode'] == 'soft';
          notifyListeners();
        }
      case 'orders:refresh':
        _scheduleOrdersSync();

      // ===== Order updated =====
      case 'order:updated':
        if (payload is Map<String, dynamic>) {
          // IKKI XIL SHAKL keladi:
          //   - to'g'ridan-to'g'ri: {order_number, status, total, ...}
          //   - sync qatlamidan:    {"order": {...to'liq qator...}}
          // Ilgari faqat birinchisi o'qilardi va boshqa node'da o'zgargan
          // chek POS'da eski summa bilan qolib ketardi.
          final data = payload['order'] is Map<String, dynamic>
              ? payload['order'] as Map<String, dynamic>
              : payload;
          final orderNum = data['order_number'] as String?;
          if (orderNum == null || orderNum.isEmpty) return;

          final st = data['status'];
          // Yopilgan/bekor qilingan chek faol ro'yxatda qolmasin.
          if (st is String && (st == 'completed' || st == 'cancelled')) {
            activeOrders.removeWhere((o) => o['order_number'] == orderNum);
            notifyListeners();
            return;
          }
          // Boshqa node'da FAOL holatga qaytarilgan (revert) chek: sync
          // qatlami to'liq qatorni `order:updated` bilan yuboradi, lekin u
          // ro'yxatda yo'q — qo'shmasak kassir uni ko'rmay qolardi.
          final known =
              activeOrders.any((o) => o['order_number'] == orderNum);
          if (!known &&
              payload['order'] is Map<String, dynamic> &&
              st is String &&
              st.isNotEmpty) {
            activeOrders.insert(0, data);
            final sku = data['table_sku'] as String?;
            if (sku != null && sku.isNotEmpty) {
              tables[sku] = TableState(
                status: 'occupied',
                orderNumber: orderNum,
              );
            }
            notifyListeners();
            return;
          }
          for (var o in activeOrders) {
            if (o['order_number'] == orderNum) {
              // FAQAT kelgan maydonlar yangilanadi. Ilgari status shartsiz
              // yozilardi: payloadda status bo'lmasa null tushib, chek holati
              // "yangi"ga qaytib, eski summa ko'rinib qolardi.
              if (st is String && st.isNotEmpty) o['status'] = st;
              // `is int` EMAS, `is num`: JSON soni Dart'ga double bo'lib
              // kelishi mumkin va u holda summa jimgina eskisicha qolardi.
              final sub = data['subtotal'];
              if (sub is num) o['subtotal'] = sub.toInt();
              final tot = data['total'];
              if (tot is num) o['total'] = tot.toInt();
              final sf = data['service_fee'];
              if (sf is num) o['service_fee'] = sf.toInt();
              final disc = data['discount'];
              if (disc is num) o['discount'] = disc.toInt();
              final items = data['items'];
              if (items is List) o['items'] = items;
            }
          }
          notifyListeners();
        }

      // ===== Order items added =====
      case 'order:items_added':
        notifyListeners();

      // ===== Stock updated =====
      case 'stock:updated':
        if (payload is Map<String, dynamic>) {
          final pid = payload['product_id'];
          stocks.removeWhere((s) => s['product_id'] == pid);
          if (payload['count'] != null) {
            stocks.add({'product_id': pid, 'count': payload['count']});
          }
          notifyListeners();
        }

      // ===== Menu outdated =====
      // Debounce SHART: to'liq resync paytida server har bir mahsulot/
      // kategoriya uchun bittadan "menu:outdated" yuborishi mumkin (132 ta
      // mahsulot = 132 ta to'liq menyu yuklab olish). Endi oxirgi xabardan
      // keyin bir marta yangilanadi.
      case 'menu:outdated':
      case 'menu:refresh':
        _scheduleMenuSync();

      // ===== Zonalar/stollar (sync yoki admin o'zgartirgan) =====
      case 'zones:updated':
        _scheduleTablesSync();

      // ===== Shift =====
      case 'shift:opened':
        if (payload is Map<String, dynamic>) {
          shift = {'status': 'open', ...payload};
        }
        notifyListeners();
      case 'shift:closed':
        shift = {'status': 'no_shift'};
        notifyListeners();
      case 'shift:stats':
        // Real-time shift stats update
        if (payload is Map<String, dynamic> && shift != null) {
          shift!['current_stats'] = payload;
        }
        notifyListeners();
    }
  }

  /// WSS init:ok dan keyin chaqiriladi
  Future<void> onInitOK(Map<String, dynamic> data) async {
    // Versions from server
    final serverVersions = data['versions'] as Map<String, dynamic>? ?? {};
    final serverMenuV = serverVersions['menu'] as int? ?? 0;
    final serverCatV = serverVersions['categories'] as int? ?? 0;
    final serverTablesV = serverVersions['tables'] as int? ?? 0;

    // Sync if outdated
    _serverTablesVersion = serverTablesV;
    if (serverMenuV != _menuVersion || serverCatV != _categoriesVersion) {
      await _syncMenu();
    }
    if (serverTablesV != _tablesVersion) {
      await _syncTables();
    }

    // Table statuses from init
    final tablesData = data['tables'] as Map<String, dynamic>? ?? {};
    tables.clear();
    tablesData.forEach((sku, value) {
      if (value is Map<String, dynamic>) {
        tables[sku] = TableState(
          status: value['status'] ?? 'free',
          orderNumber: value['order_number'] as String?,
        );
      }
    });

    // Active orders
    final ordersData = data['active_orders'] as List<dynamic>? ?? [];
    activeOrders = ordersData.map((o) => o as Map<String, dynamic>).toList();

    // Stocks
    final stocksData = data['stocks'] as List<dynamic>? ?? [];
    stocks = stocksData.map((s) => s as Map<String, dynamic>).toList();
    stockSoft = data['stock_mode'] == 'soft';

    // Shift — full data from init:ok
    shift = data['shift'] as Map<String, dynamic>?;

    notifyListeners();
  }

  static const _syncDebounce = Duration(milliseconds: 1200);
  Timer? _menuSyncTimer;
  Timer? _tablesSyncTimer;

  void _scheduleMenuSync() {
    _menuSyncTimer?.cancel();
    _menuSyncTimer = Timer(_syncDebounce, _syncMenu);
  }

  void _scheduleTablesSync() {
    _tablesSyncTimer?.cancel();
    _tablesSyncTimer = Timer(_syncDebounce, _syncTables);
  }

  Timer? _stocksSyncTimer;
  Timer? _ordersSyncTimer;

  void _scheduleStocksSync() {
    _stocksSyncTimer?.cancel();
    _stocksSyncTimer = Timer(_syncDebounce, _syncStocks);
  }

  void _scheduleOrdersSync() {
    _ordersSyncTimer?.cancel();
    _ordersSyncTimer = Timer(_syncDebounce, _syncActiveOrders);
  }

  /// Qoldiqlarni serverdan qaytadan olish (to'liq resync'dan keyin).
  Future<void> _syncStocks() async {
    try {
      final list = await ApiService().getStocks(force: true);
      stocks = list.whereType<Map<String, dynamic>>().toList();
      _log('SYNC: stocks refreshed (${stocks.length})');
      notifyListeners();
    } catch (e) {
      _log('SYNC: stocks refresh failed: $e');
    }
  }

  /// Faol cheklarni serverdan qaytadan olish (to'liq resync'dan keyin).
  Future<void> _syncActiveOrders() async {
    try {
      final list = await ApiService().getOrders();
      activeOrders = list.whereType<Map<String, dynamic>>().toList();
      _log('SYNC: active orders refreshed (${activeOrders.length})');
      notifyListeners();
    } catch (e) {
      _log('SYNC: orders refresh failed: $e');
    }
  }

  Future<void> _syncMenu() async {
    try {
      _log('SYNC: fetching menu from server...');
      // `includeInactive` — lokal kesh POS bilan admin menyusi uchun BITTA.
      // Faqat `active` ni saqlasak, sync har safar nofaol mahsulotlarni
      // keshdan o'chirib yuborardi va admin menyuda ular ko'rinmasdi.
      // O'qishda POS baribir `status='active'` bilan filtrlaydi.
      final menu = await ApiService().getMenu(force: true, includeInactive: true);
      final categories = menu['categories'] as List<dynamic>? ?? [];
      final products = menu['products'] as List<dynamic>? ?? [];
      final version = menu['version'] as int? ?? 0;
      if (menu.containsKey('stock_mode')) {
        stockSoft = menu['stock_mode'] == 'soft';
      }

      await LocalDB().saveCategories(categories);
      await LocalDB().saveProducts(products);
      await LocalDB().setVersion('menu', version);
      await LocalDB().setVersion('categories', version);
      _menuVersion = version;
      _categoriesVersion = version;
      // Memory cache ni ham yangilash — OrderScreen sinxron o'qiydi.
      // Nofaollar HAM keshda turadi: super_admin va kassir ularni menyuda
      // ko'rishi kerak. Boshqa rollar uchun OrderScreen o'zi filtrlaydi.
      setMenuCache(
        categories.cast<Map<String, dynamic>>().toList(),
        products.cast<Map<String, dynamic>>().toList(),
      );
      _log(
        'SYNC: menu updated to v$version (${categories.length} cats, ${products.length} prods)',
      );
      notifyListeners();
    } catch (e) {
      _log('SYNC: menu sync failed: $e');
    }
  }

  Future<void> _syncTables() async {
    try {
      _log('SYNC: fetching tables from server...');
      final zones = await ApiService().getZones(force: true);
      // Extract tables from zones
      final allTables = <Map<String, dynamic>>[];
      final zonesList = <Map<String, dynamic>>[];

      for (final z in zones) {
        final zMap = z as Map<String, dynamic>;
        zonesList.add(zMap);
        final ztables = zMap['tables'] as List<dynamic>? ?? [];
        for (final t in ztables) {
          final tMap = t as Map<String, dynamic>;
          tMap['zone_id'] = zMap['id'];
          allTables.add(tMap);
        }
      }

      await LocalDB().saveZonesAndTables(zonesList, allTables);
      // Serverdan kelgan versiyani yozamiz, o'zimiznikini OSHIRMAYMIZ.
      // Ilgari bu yerda `_tablesVersion + 1` bo'lgan: bir marta qo'lda
      // yangilangandan keyin local versiya serverникidan doim katta bo'lib
      // qolardi va stollar HAR BIR qayta ulanishda qaytadan yuklanardi.
      await LocalDB().setVersion('tables', _serverTablesVersion);
      _tablesVersion = _serverTablesVersion;
      _log(
        'SYNC: tables updated (${zonesList.length} zones, ${allTables.length} tables)',
      );
      notifyListeners();
    } catch (e) {
      _log('SYNC: tables sync failed: $e');
    }
  }

  /// Force sync everything
  Future<void> forceSync() async {
    await _syncMenu();
    await _syncTables();
  }

  // ===== Getters for UI =====

  String getTableStatus(String sku) {
    return tables[sku]?.status ?? 'free';
  }

  String? getTableOrderNumber(String sku) {
    return tables[sku]?.orderNumber;
  }

  int? getStockCount(int productId) {
    for (final s in stocks) {
      if (s['product_id'] == productId) return s['count'] as int?;
    }
    return null; // null = unlimited
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    _menuSyncTimer?.cancel();
    _tablesSyncTimer?.cancel();
    _stocksSyncTimer?.cancel();
    _ordersSyncTimer?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  /// Chiqishda holatni tozalash — keyingi kassir oldingi smenani ko'rmasin.
  ///
  /// Ilgari `logout` faqat tokenni o'chirardi: yangi kassir kirganda (server
  /// javob bermasa yoki `init:ok` kelgunicha) oldingi kassirning faol
  /// cheklarini, stol holatini va OCHIQ smenasini ko'rar va ular ustida
  /// amal bajara olardi.
  void reset() {
    tables = {};
    activeOrders = [];
    stocks = [];
    shift = null;
    role = null;
    userName = null;
    invalidateMenuCache();
    _menuSyncTimer?.cancel();
    _tablesSyncTimer?.cancel();
    _stocksSyncTimer?.cancel();
    _ordersSyncTimer?.cancel();
    _fallbackTimer?.cancel();
    notifyListeners();
  }
}

class TableState {
  final String status;
  final String? orderNumber;
  TableState({required this.status, this.orderNumber});
}
