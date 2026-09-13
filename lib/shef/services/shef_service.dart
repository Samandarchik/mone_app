// shef/services/shef_service.dart — shef (ishlab chiqarish) Dio servisi:
// ShefService — /api/production/{products,orders} (yaratish + accept/reject/
// progress), полуфабрикат limiti uchun /api/production/pf-availability va
// pf qoldig'i ro'yxati uchun /api/production/pf-stock.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';

// Shef (ishlab chiqarish) uchun Dio servis.
// Bearer token Dio interceptor orqali avtomatik qo'shiladi.
// Javob shakli loyihadagi umumiy naqsh: { success, message, data }.
class ShefService {
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

  // GET /api/production/products -> tex kartasi bor mahsulotlar.
  Future<List<ProductionProduct>> fetchProducts() async {
    try {
      final response = await dio.get(AppUrls.productionProducts);
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return ProductionProduct.listFromJson(body['data']);
        return [];
      }
      throw Exception('Mahsulotlarni yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'mahsulotlar yuklanmadi');
    }
  }

  // GET /api/production/pf-availability?product_id=N&qty=Q — tanlangan
  // mahsulot uchun полуфабрикат qoldig'i bo'yicha limit (shef o'z skladi).
  // max_qty null — cheklov yo'q (tex kartada pf ishlatilmagan).
  Future<PfAvailability> fetchPfAvailability(int productId, int qty) async {
    try {
      final response = await dio.get(
        AppUrls.pfAvailability,
        queryParameters: {'product_id': productId, 'qty': qty},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return PfAvailability.fromJson(
              Map<String, dynamic>.from(body['data']));
        }
        return const PfAvailability();
      }
      throw Exception('Qoldiq ma\'lumoti yuklanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'qoldiq ma\'lumoti yuklanmadi');
    }
  }

  // GET /api/production/pf-stock — полуфабрикат qoldig'i (butun ro'yxat).
  // Shef o'z skladini oladi, shuning uchun sklad_id YUBORILMAYDI.
  // ready: true — пф EMAS, TAYYOR mahsulotlar qoldig'i («Готовый» ekrani).
  // Backend bir xil javob shaklini beradi, faqat filtr teskari (kind=ready).
  Future<PfStockData> fetchPfStock({bool ready = false}) async {
    try {
      final response = await dio.get(
        AppUrls.pfStock,
        queryParameters: ready ? const {'kind': 'ready'} : null,
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return PfStockData.fromJson(Map<String, dynamic>.from(body['data']));
        }
        return const PfStockData();
      }
      throw Exception('Qoldiqni yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'qoldiq yuklanmadi');
    }
  }

  // GET /api/production/orders -> shefning o'z buyurtmalari.
  Future<List<ProductionOrder>> fetchOrders() async {
    try {
      final response = await dio.get(AppUrls.productionOrders);
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) return ProductionOrder.listFromJson(body['data']);
        return [];
      }
      throw Exception('Buyurtmalarni yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'buyurtmalar yuklanmadi');
    }
  }

  // GET /api/production/orders/{id} -> bitta buyurtma (to'liq).
  Future<ProductionOrder?> fetchOrder(int id) async {
    try {
      final response = await dio.get('${AppUrls.productionOrders}/$id');
      if (response.statusCode == 200) {
        return _orderFromBody(response.data);
      }
      throw Exception('Buyurtmani yuklab bo\'lmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'buyurtma yuklanmadi');
    }
  }

  // POST /api/production/orders — buyurtma yaratish.
  // Body: { "items": [ {"product_id": 12, "qty": 130}, ... ] }.
  // Server snapshot va partiya hisobini o'zi qiladi.
  Future<ProductionOrder?> createOrder(List<Map<String, dynamic>> items) async {
    try {
      final response = await dio.post(
        AppUrls.productionOrders,
        data: {'items': items},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return _orderFromBody(response.data);
      }
      throw Exception('Buyurtma yaratilmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'buyurtma yaratilmadi');
    }
  }

  // POST .../{id}/items/{pi}/stages/{si}/accept — masalliqni qabul qilish.
  Future<ProductionOrder?> acceptStage(int orderId, int pi, int si) async {
    try {
      final response = await dio.post(
        '${AppUrls.productionOrders}/$orderId/items/$pi/stages/$si/accept',
      );
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'qabul saqlanmadi');
    }
  }

  // POST .../{id}/items/{pi}/stages/{si}/reject — rad etish (izoh bilan).
  Future<ProductionOrder?> rejectStage(
    int orderId,
    int pi,
    int si,
    String comment,
  ) async {
    try {
      final response = await dio.post(
        '${AppUrls.productionOrders}/$orderId/items/$pi/stages/$si/reject',
        data: {'comment': comment},
      );
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'rad etish saqlanmadi');
    }
  }

  // PUT .../{id}/items/{pi}/stages/{si}/progress — done_qty kiritish.
  // Noto'g'ri qiymatga server 400 + message qaytaradi.
  Future<ProductionOrder?> setProgress(
    int orderId,
    int pi,
    int si,
    int doneQty,
  ) async {
    try {
      final response = await dio.put(
        '${AppUrls.productionOrders}/$orderId/items/$pi/stages/$si/progress',
        data: {'done_qty': doneQty},
      );
      if (response.statusCode == 200) return _orderFromBody(response.data);
      throw Exception('Saqlanmadi: ${response.statusCode}');
    } on DioException catch (e) {
      _throwDio(e, 'progress saqlanmadi');
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
