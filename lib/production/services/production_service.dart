// production/services/production_service.dart — ombor/admin/bugalter ishlab
// chiqarish Dio servisi: ProductionService — /api/production/{products,orders,
// cost,stats}, /api/prices/{latest,history}, /api/analytics/profit endpointlari.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/admin/model/profit_analytics_model.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/production/models/latest_price_model.dart';
import 'package:uz_ai_dev/production/models/price_history_model.dart';
import 'package:uz_ai_dev/production/models/production_cost_model.dart';
import 'package:uz_ai_dev/production/models/production_plan_model.dart';
import 'package:uz_ai_dev/production/models/production_stats_model.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';

// Ishlab chiqarish buyurtmalari — ombor/admin/bugalter tomoni uchun Dio
// servis. Server ro'yxatni rolga qarab filtrlaydi: ombor — o'z skladlari,
// admin/bugalter — hammasi. Modellari shef bilan umumiy
// (lib/shef/model/production_model.dart).
class ProductionService {
  final Dio dio = sl<Dio>();

  // DioException'dan foydalanuvchiga ko'rsatiladigan xabar yasash.
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



  // GET /api/production/orders -> rolga mos buyurtmalar ro'yxati.
  Future<List<ProductionOrder>> fetchOrders() async {
    try {
      final response = await dio.get(AppUrls.productionOrders);
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return ProductionOrder.listFromJson(body['data']);
        return [];
      }
      throw Exception(
          'Buyurtmalarni yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'buyurtmalar yuklanmadi');
    }
  }

  // GET /api/production/orders/{id} -> bitta buyurtma (to'liq).
  Future<ProductionOrder?> fetchOrder(int id) async {
    try {
      final response = await dio.get('${AppUrls.productionOrders}/$id');
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Buyurtmani yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'buyurtma yuklanmadi');
    }
  }

  // POST .../{id}/items/{pi}/stages/{si}/issue — ombor «Berdim»:
  // chiqim + material_status=berildi. pi/si — 0-based indekslar.
  Future<ProductionOrder?> issueStage(int orderId, int pi, int si) async {
    try {
      final response = await dio.post(
        '${AppUrls.productionOrders}/$orderId/items/$pi/stages/$si/issue',
      );
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'berish saqlanmadi');
    }
  }

  // DELETE /api/production/orders/{id} — FAQAT bugalter o'chira oladi.
  Future<void> deleteOrder(int id) async {
    try {
      final response = await dio.delete('${AppUrls.productionOrders}/$id');
      if (response.statusCode == 200) return;
      throw Exception('O\'chirilmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'o\'chirilmadi');
    }
  }

  // PUT /api/production/orders/{id}/status — FAQAT bugalter statusni qo'lda
  // almashtiradi. Body: {status: yangi|jarayonda|tayyor}.
  Future<ProductionOrder?> updateStatus(int id, String status) async {
    try {
      final response = await dio.put(
        '${AppUrls.productionOrders}/$id/status',
        data: {'status': status},
      );
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Status saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'status saqlanmadi');
    }
  }

  // GET /api/production/cost?product_id=N — mahsulot tannarxi (1 partiya +
  // 1 dona, masalliqlar ro'yxati bilan). Faqat admin/bugalter.
  Future<ProductionCost> fetchCost(int productId) async {
    try {
      final response = await dio.get(
        AppUrls.productionCost,
        queryParameters: {'product_id': productId},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return ProductionCost.fromJson(
              Map<String, dynamic>.from(body['data']));
        }
      }
      throw Exception('Tannarx yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'tannarx yuklanmadi');
    }
  }

  // GET /api/production/requirements — kunlik ishlab chiqarish rejasi (MRP):
  // filial buyurtmalaridan tort → П/Ф → xomashyo ehtiyoji va defitsit.
  // admin/superadmin/shef/bugalter.
  Future<ProductionPlan> fetchRequirements({String? date, int? skladId}) async {
    try {
      final response = await dio.get(
        AppUrls.productionRequirements,
        queryParameters: {
          if (date != null) 'date': date,
          if (skladId != null) 'sklad_id': skladId,
        },
      );
      return ProductionPlan.fromJson(
          Map<String, dynamic>.from(response.data['data']));
    } on DioException catch (e) {
      _throwDio(e, 'reja yuklanmadi');
    }
  }

  // GET /api/prices/latest — barcha mahsulotlarning oxirgi xarid narxi
  // (eng kichik birlik uchun). Kalit: product_id. Narxlanmaganlar yo'q.
  // Faqat admin/bugalter.
  Future<Map<int, LatestPrice>> fetchLatestPrices() async {
    try {
      final response = await dio.get(AppUrls.latestPrices);
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return LatestPrice.mapFromJson(body['data']);
        return {};
      }
      throw Exception('Narxlar yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'narxlar yuklanmadi');
    }
  }

  // GET /api/prices/history?product_id=N&limit=K — bitta mahsulotning xarid
  // narxlari tarixi (eng yangisi birinchi). Faqat admin/bugalter.
  Future<List<PriceHistoryEntry>> fetchPriceHistory(
    int productId, {
    int limit = 20,
  }) async {
    try {
      final response = await dio.get(
        AppUrls.pricesHistory,
        queryParameters: {'product_id': productId, 'limit': limit},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return PriceHistoryEntry.listFromJson(body['data']);
        return [];
      }
      throw Exception('Tarix yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'tarix yuklanmadi');
    }
  }

  // GET /api/production/stats?from=&to= — ishlab chiqarish statistikasi
  // (admin/bugalter). Sanalar YYYY-MM-DD; berilmasa backend default (30 kun).
  Future<ProductionStats> fetchStats({String? from, String? to}) async {
    try {
      final response = await dio.get(
        AppUrls.productionStats,
        queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return ProductionStats.fromJson(
              Map<String, dynamic>.from(body['data']));
        }
      }
      throw Exception('Statistika yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'statistika yuklanmadi');
    }
  }

  // GET /api/analytics/profit?days=N — foyda analitikasi (admin/bugalter).
  // days ∈ {7, 30, 90}. Tortlar bo'yicha tushum/tannarx/foyda, kunlik marja
  // dinamikasi va masalliq narx sakrashlari.
  Future<ProfitAnalytics> fetchProfitAnalytics(int days) async {
    try {
      final response = await dio.get(
        AppUrls.profitAnalytics,
        queryParameters: {'days': days},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return ProfitAnalytics.fromJson(
              Map<String, dynamic>.from(body['data']));
        }
      }
      throw Exception('Analitika yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'analitika yuklanmadi');
    }
  }

  // Javob body'sidan buyurtmani o'qish: { data: {order} } yoki to'g'ridan-
  // to'g'ri obyekt. Topilmasa null (chaqiruvchi refetch qiladi).
  ProductionOrder? _orderFromBody(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return ProductionOrder.fromJson(Map<String, dynamic>.from(body['data']));
    }
    if (body is Map && body['id'] != null) {
      return ProductionOrder.fromJson(Map<String, dynamic>.from(body));
    }
    return null;
  }
}
