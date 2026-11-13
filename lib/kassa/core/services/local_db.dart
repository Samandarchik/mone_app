import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

// sqflite — faqat mobile/desktop.
// `sqflite_common_ffi` sqflite'ning hamma turlarini ham qayta eksport qiladi
// va Windows/Linux uchun FFI backendini beradi (sqflite'ning o'zida bu
// platformalar uchun nativ implementatsiya yo'q).
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    if (dart.library.html) 'local_db_web_stub.dart';
import 'package:path/path.dart' if (dart.library.html) 'local_db_web_stub.dart';

class LocalDB {
  static final LocalDB _instance = LocalDB._();
  factory LocalDB() => _instance;
  LocalDB._();

  // Web fallback — in-memory
  List<Map<String, dynamic>> _memCategories = [];
  List<Map<String, dynamic>> _memProducts = [];
  List<Map<String, dynamic>> _memZones = [];
  List<Map<String, dynamic>> _memTables = [];
  final Map<String, int> _memVersions = {'menu': 0, 'categories': 0, 'tables': 0};

  Database? _db;
  bool _isWeb = false;

  Future<void> init() async {
    _isWeb = kIsWeb;
    if (!_isWeb) {
      try {
        // Windows va Linux'da `sqflite` ning nativ implementatsiyasi YO'Q.
        //
        // Ilgari bu yerda `MissingPluginException` chiqib, quyidagi
        // `catch (_)` uni "web" deb belgilardi va butun kesh XOTIRAGA
        // o'tib ketardi. Ya'ni restorandagi ASOSIY Windows terminalida
        // hech qanday doimiy kesh yo'q edi: har ishga tushishda menyu
        // qaytadan yuklanardi va server javob bermasa kassir BO'SH stol
        // ro'yxatini ko'rib, umuman buyurtma ocholmasdi — kesh aynan shu
        // holat uchun yozilgan bo'lsa ham.
        if (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }
        final dbPath = join(await getDatabasesPath(), 'mone_kassa.db');
        _db = await openDatabase(
          dbPath,
          version: 2,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE IF NOT EXISTS versions (key TEXT PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0)');
            await db.execute('CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY, name_uz TEXT, name_ru TEXT, name_tr TEXT, icon TEXT, sort_order INTEGER, status TEXT, data TEXT)');
            await db.execute('CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, name_uz TEXT, name_ru TEXT, name_tr TEXT, category_id INTEGER, price INTEGER, old_price INTEGER, sort_order INTEGER, status TEXT, data TEXT)');
            await db.execute('CREATE TABLE IF NOT EXISTS zones (id INTEGER PRIMARY KEY, name TEXT, count INTEGER, sort_order INTEGER, data TEXT)');
            await db.execute('CREATE TABLE IF NOT EXISTS tables (id INTEGER PRIMARY KEY, zone_id INTEGER, sku TEXT UNIQUE, number INTEGER, label TEXT, seats INTEGER, qr_code TEXT, data TEXT)');
            await db.insert('versions', {'key': 'menu', 'version': 0});
            await db.insert('versions', {'key': 'categories', 'version': 0});
            await db.insert('versions', {'key': 'tables', 'version': 0});
          },
          onUpgrade: (db, oldV, newV) async {
            // v1 → v2: backend had no `number` field in JSON, so cached
            // tables had number=0 and sorted alphabetically. Wipe & resync.
            if (oldV < 2) {
              await db.delete('tables');
              await db.delete('zones');
              await db.insert(
                'versions',
                {'key': 'tables', 'version': -1},
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          },
        );
      } catch (_) {
        _isWeb = true; // fallback to memory
      }
    }
  }

  // ============ VERSIONS ============

  Future<int> getVersion(String key) async {
    if (_isWeb) return _memVersions[key] ?? 0;
    final r = await _db!.query('versions', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return 0;
    return r.first['version'] as int;
  }

  Future<void> setVersion(String key, int version) async {
    if (_isWeb) { _memVersions[key] = version; return; }
    await _db!.insert('versions', {'key': key, 'version': version}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, int>> getAllVersions() async {
    if (_isWeb) return Map.from(_memVersions);
    final rows = await _db!.query('versions');
    return {for (final r in rows) r['key'] as String: r['version'] as int};
  }

  // ============ CATEGORIES ============

  Future<void> saveCategories(List<dynamic> categories) async {
    if (_isWeb) { _memCategories = categories.map((c) => c as Map<String, dynamic>).toList(); return; }
    await _db!.transaction((txn) async {
      await txn.delete('categories');
      for (final c in categories) {
        await txn.insert('categories', {
          'id': c['id'], 'name_uz': c['name']?['uz'] ?? '', 'name_ru': c['name']?['ru'] ?? '',
          'name_tr': c['name']?['tr'] ?? '', 'icon': c['icon'] ?? '', 'sort_order': c['sort_order'] ?? 0,
          'status': c['status'] ?? 'active', 'data': jsonEncode(c),
        });
      }
    });
  }

  /// `includeInactive` — admin menyusi uchun.
  ///
  /// Kesh jadvali POS bilan BITTA: unga nofaol kategoriya/mahsulot ham
  /// yoziladi (admin ularni ko'rishi va qayta yoqishi shart), lekin
  /// standart o'qish — POS — faqat `active` ni oladi.
  Future<List<Map<String, dynamic>>> getCategories({bool includeInactive = false}) async {
    if (_isWeb) {
      if (includeInactive) return _memCategories;
      return _memCategories.where((c) => (c['status'] ?? 'active') == 'active').toList();
    }
    final rows = includeInactive
        ? await _db!.query('categories', orderBy: 'sort_order')
        : await _db!.query('categories', where: 'status = ?', whereArgs: ['active'], orderBy: 'sort_order');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  // ============ PRODUCTS ============

  Future<void> saveProducts(List<dynamic> products) async {
    if (_isWeb) { _memProducts = products.map((p) => p as Map<String, dynamic>).toList(); return; }
    await _db!.transaction((txn) async {
      await txn.delete('products');
      for (final p in products) {
        await txn.insert('products', {
          'id': p['id'], 'name_uz': p['name']?['uz'] ?? '', 'name_ru': p['name']?['ru'] ?? '',
          'name_tr': p['name']?['tr'] ?? '', 'category_id': p['category_id'] ?? 0,
          'price': p['price'] ?? 0, 'old_price': p['old_price'], 'sort_order': p['sort_order'] ?? 0,
          'status': p['status'] ?? 'active', 'data': jsonEncode(p),
        });
      }
    });
  }

  /// `includeInactive` — admin menyusi uchun (qarang: [getCategories]).
  Future<List<Map<String, dynamic>>> getProducts({int? categoryId, bool includeInactive = false}) async {
    if (_isWeb) {
      var list = _memProducts;
      if (!includeInactive) {
        list = list.where((p) => (p['status'] ?? 'active') == 'active').toList();
      }
      if (categoryId != null) {
        list = list.where((p) => p['category_id'] == categoryId).toList();
      }
      return list;
    }
    final conds = <String>[];
    final args = <Object?>[];
    if (categoryId != null) { conds.add('category_id = ?'); args.add(categoryId); }
    if (!includeInactive) { conds.add('status = ?'); args.add('active'); }
    final rows = await _db!.query('products',
        where: conds.isEmpty ? null : conds.join(' AND '),
        whereArgs: conds.isEmpty ? null : args,
        orderBy: 'sort_order');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  // ============ ZONES + TABLES ============

  Future<void> saveZonesAndTables(List<dynamic> zones, List<dynamic> tables) async {
    if (_isWeb) {
      _memZones = zones.map((z) => z as Map<String, dynamic>).toList();
      _memTables = tables.map((t) => t as Map<String, dynamic>).toList();
      return;
    }
    await _db!.transaction((txn) async {
      await txn.delete('zones');
      await txn.delete('tables');
      for (final z in zones) {
        await txn.insert('zones', {
          'id': z['id'], 'name': z['name'] is Map ? z['name']['uz'] : z['name'],
          'count': z['count'] ?? 0, 'sort_order': z['sort_order'] ?? 0, 'data': jsonEncode(z),
        });
      }
      for (final t in tables) {
        await txn.insert('tables', {
          'id': t['id'], 'zone_id': t['zone_id'], 'sku': t['sku'], 'number': t['number'] ?? 0,
          'label': t['label'] ?? '', 'seats': t['seats'] ?? 4, 'qr_code': t['qr_code'] ?? '', 'data': jsonEncode(t),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getZones() async {
    if (_isWeb) return _memZones;
    final rows = await _db!.query('zones', orderBy: 'sort_order');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> getTables({int? zoneId}) async {
    if (_isWeb) {
      if (zoneId != null) return _memTables.where((t) => t['zone_id'] == zoneId).toList();
      return _memTables;
    }
    if (zoneId != null) {
      final rows = await _db!.query('tables', where: 'zone_id = ?', whereArgs: [zoneId], orderBy: 'number');
      return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
    }
    final rows = await _db!.query('tables', orderBy: 'number');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> clear() async {
    if (_isWeb) { _memCategories.clear(); _memProducts.clear(); _memZones.clear(); _memTables.clear(); return; }
    await _db!.delete('categories');
    await _db!.delete('products');
    await _db!.delete('zones');
    await _db!.delete('tables');
    await _db!.execute("UPDATE versions SET version = 0");
  }
}
