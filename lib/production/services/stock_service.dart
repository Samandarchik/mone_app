// production/services/stock_service.dart — sklad qoldig'i (stock) Dio servisi:
// StockService — /api/stock (+adjust/min/inventory/inventories/moves) va katalog
// uchun /api/ombor/products endpointlari.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/production/models/inventory_act_model.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';

// Sklad qoldig'i (inventar) uchun Dio servis: qoldiqlar, korreksiya va
// harakatlar tarixi. Ombor — o'z skladi, admin — istalgan sklad.
class StockService {
  final Dio dio = sl<Dio>();

  // API kontrakt: кг/л miqdorlar butun gramm/ml — butun qiymat kasrsiz
  // yuboriladi (1500, 1500.0 emas).
  static num _asWire(double v) => v % 1 == 0 ? v.toInt() : v;

  Never _throwDio(DioException e, String fallback) {
    if (e.response != null) {
      final body = e.response!.data;
      final msg = (body is Map && body['message'] != null)
          ? body['message'].toString()
          : 'Server xatosi: ${e.response!.statusCode}';
      throw Exception(msg);
    }
    throw Exception('Tarmoq xatosi: ${e.message ?? fallback}');
  }

  // GET /api/stock?sklad_id=N -> skladdagi qoldiqlar ro'yxati.
  //
  // includeAll: true bo'lsa `include_all=1` qo'shiladi — javobga skladga
  // tegishli, lekin hali qoldiq yozuvi YO'Q katalog mahsulotlari ham
  // qo'shiladi (qty: 0, min_qty: 0, low: false). Faqat inventarizatsiya
  // sahifasi uchun: «nima yo'q» ni ham sanash kerak. Boshqa ekranlar
  // (ombor kartalari, «Kam qolganlar») bu bayroqsiz chaqiradi — ular uchun
  // «yozuv yo'q ⇒ ko'rsatilmaydi» qoidasi saqlanadi.
  Future<List<StockRow>> fetchStock(int skladId, {bool includeAll = false}) async {
    try {
      final response = await dio.get(
        AppUrls.stock,
        queryParameters: {
          'sklad_id': skladId,
          if (includeAll) 'include_all': 1,
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return StockRow.listFromJson(body['data']);
        return [];
      }
      throw Exception('Qoldiqni yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'qoldiq yuklanmadi');
    }
  }

  // POST /api/stock/adjust — qo'lda korreksiya (+/- qty). Muvaffaqiyatda
  // backend message'i qaytadi.
  Future<String> adjust({
    required int skladId,
    required int productId,
    required double qty,
    required String comment,
  }) async {
    try {
      final response = await dio.post(
        AppUrls.stockAdjust,
        data: {
          'sklad_id': skladId,
          'product_id': productId,
          'qty': _asWire(qty),
          'comment': comment,
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['message'] != null) {
          return body['message'].toString();
        }
        return 'Korreksiya saqlandi';
      }
      throw Exception('Korreksiya saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'korreksiya saqlanmadi');
    }
  }

  // POST /api/stock/write-off — spisaniya (brak): musbat qty skladdan
  // chiqim bo'lib yoziladi, sabab majburiy. POS spisaniyasi bilan bitta
  // audit hisobotida ko'rinadi.
  Future<String> writeOff({
    required int skladId,
    required int productId,
    required double qty,
    required String reason,
  }) async {
    try {
      final response = await dio.post(
        AppUrls.stockWriteOff,
        data: {
          'sklad_id': skladId,
          'product_id': productId,
          'qty': _asWire(qty),
          'reason': reason,
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['message'] != null) {
          return body['message'].toString();
        }
        return 'Spisaniya qayd etildi';
      }
      throw Exception('Spisaniya saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'spisaniya saqlanmadi');
    }
  }

  // POST /api/stock/min — mahsulot uchun minimal qoldiq chegarasi.
  Future<String> setMin({
    required int skladId,
    required int productId,
    required double minQty,
  }) async {
    try {
      final response = await dio.post(
        AppUrls.stockMin,
        data: {
          'sklad_id': skladId,
          'product_id': productId,
          'min_qty': _asWire(minQty),
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['message'] != null) {
          return body['message'].toString();
        }
        return 'Min chegara saqlandi';
      }
      throw Exception('Min chegara saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'min chegara saqlanmadi');
    }
  }

  // POST /api/stock/inventory — inventarizatsiya: real sanab chiqilgan
  // qoldiqlar. Farqlar korreksiya bo'lib yoziladi; nechta qator
  // o'zgargani (changed) qaytadi.
  Future<int> inventory({
    required int skladId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final response = await dio.post(
        AppUrls.stockInventory,
        data: {'sklad_id': skladId, 'items': items},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        final data = (body is Map) ? body['data'] : null;
        final changed = (data is Map) ? data['changed'] : null;
        if (changed is num) return changed.toInt();
        return int.tryParse(changed?.toString() ?? '') ?? 0;
      }
      throw Exception('Inventarizatsiya saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'inventarizatsiya saqlanmadi');
    }
  }

  // GET /api/stock/inventories?sklad_id=N&limit=K — inventarizatsiya
  // dalolatnomalari ro'yxati (eng yangisi birinchi). Javobda `items` YO'Q —
  // qatorlar faqat fetchInventory(id) da keladi.
  Future<List<InventoryAct>> fetchInventories(
    int skladId, {
    int limit = 20,
  }) async {
    try {
      final response = await dio.get(
        AppUrls.stockInventories,
        queryParameters: {'sklad_id': skladId, 'limit': limit},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return InventoryAct.listFromJson(body['data']);
        return [];
      }
      throw Exception('Dalolatnomalar yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'dalolatnomalar yuklanmadi');
    }
  }

  // GET /api/stock/inventories/{id} — bitta dalolatnoma, farqli qatorlari
  // (items) va sanash paytidagi narxlari bilan.
  Future<InventoryAct> fetchInventory(int id) async {
    try {
      final response = await dio.get('${AppUrls.stockInventories}/$id');
      if (response.statusCode == 200) {
        final body = response.data;
        final data = (body is Map) ? body['data'] : null;
        if (data is Map) {
          return InventoryAct.fromJson(Map<String, dynamic>.from(data));
        }
        throw Exception('Dalolatnoma topilmadi');
      }
      throw Exception('Dalolatnoma yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'dalolatnoma yuklanmadi');
    }
  }

  // GET /api/stock/moves?sklad_id=N[&product_id=M][&limit=K] — harakatlar
  // tarixi (created bo'yicha kamayuvchi).
  Future<List<StockMove>> fetchMoves(
    int skladId, {
    int? productId,
    int? limit,
  }) async {
    try {
      final response = await dio.get(
        AppUrls.stockMoves,
        queryParameters: {
          'sklad_id': skladId,
          if (productId != null) 'product_id': productId,
          if (limit != null) 'limit': limit,
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return StockMove.listFromJson(body['data']);
        return [];
      }
      throw Exception('Tarix yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'tarix yuklanmadi');
    }
  }


}
