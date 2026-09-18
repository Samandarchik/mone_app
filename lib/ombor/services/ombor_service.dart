// ombor/services/ombor_service.dart — Ombor (bozor) Dio servisi: OmborService. Endpointlar
// AppUrls.orders (POST buyurtma / GET o'z buyurtmalari), omborProducts, category; item
// accept (POST .../accept) va soft-delete (DELETE .../items/{productId}).
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/ombor/models/ombor_order_model.dart';
import 'package:uz_ai_dev/ombor/models/ombor_product_model.dart';

// Ombor (bozor) mahsulotlari uchun Dio servis.
// Bearer token avtomatik ravishda Dio interceptor orqali qo'shiladi.
class OmborService {
  final Dio dio = sl<Dio>();

  // POST /api/orders -> savatdagi mahsulotlarni buyurtma qilish.
  // items: [{"product_id": 1, "count": 5, "source": "toshkent"}, ...] —
  // source HAR qatorda; bitta product_id turli manbalar bilan bir necha
  // marta kelishi mumkin (backend har manbaga alohida buyurtma yaratadi).
  // Javob: {"success": true, "message": "...", "data": {order}}
  Future<String> submitOrder(List<Map<String, dynamic>> items) async {
    try {
      final response = await dio.post(
        AppUrls.orders,
        data: {'items': items},
      );

      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status >= 200 && status < 300) {
        if (body is Map && body['message'] != null) {
          return body['message'].toString();
        }
        return 'Buyurtma yuborildi';
      }
      throw Exception('Buyurtma yuborib bo\'lmadi: $status');
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Buyurtma yuborishda kutilmagan xato: $e');
    }
  }

  // POST /api/orders -> buyurtma yaratib, yaratilgan buyurtmaning order_id
  // sini qaytaradi (F2 «Yetishmaganidan buyurtma» snackbar'i uchun).
  Future<String> submitOrderReturningId(
      List<Map<String, dynamic>> items) async {
    try {
      final response = await dio.post(
        AppUrls.orders,
        data: {'items': items},
      );

      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status >= 200 && status < 300) {
        final data = (body is Map) ? body['data'] : null;
        if (data is Map) {
          final oid = data['order_id']?.toString() ?? '';
          if (oid.isNotEmpty) return oid;
          if (data['id'] != null) return '№${data['id']}';
        }
        if (body is Map && body['message'] != null) {
          return body['message'].toString();
        }
        return '';
      }
      throw Exception('Buyurtma yuborib bo\'lmadi: $status');
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Buyurtma yuborishda kutilmagan xato: $e');
    }
  }

  // GET /api/ombor/products -> kategoriya bo'yicha guruhlangan mahsulotlar
  Future<Map<String, List<OmborProduct>>> fetchProducts() async {
    try {
      final response = await dio.get(AppUrls.omborProducts);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData =
            Map<String, dynamic>.from(response.data);
        final data = responseData['data'];
        if (data is Map) {
          return parseOmborProducts(Map<String, dynamic>.from(data));
        }
        return {};
      } else {
        throw Exception('Mahsulotlarni yuklab bo\'lmadi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Mahsulotlarni yuklashda kutilmagan xato: $e');
    }
  }

  // GET /api/categories -> kategoriyalar ro'yxati (rasm + nom, server tartibida).
  // Admin paneldagi kabi kategoriya ro'yxatini ko'rsatish uchun.
  Future<List<OmborCategory>> fetchCategories() async {
    try {
      final response = await dio.get(AppUrls.category);

      if (response.statusCode == 200) {
        final body = response.data;
        final data = (body is Map) ? body['data'] : null;
        if (data is List) {
          return data
              .map((e) => OmborCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        return <OmborCategory>[];
      } else {
        throw Exception(
            'Kategoriyalarni yuklab bo\'lmadi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Kategoriyalarni yuklashda kutilmagan xato: $e');
    }
  }

  // GET /api/orders -> ombor userning O'Z buyurtmalari ro'yxati.
  //
  // days/all — tarix oynasi: aktiv buyurtmalar har doim keladi, yopiqlari
  // esa faqat oxirgi `days` kun ichida (null — server default 30 kun,
  // all=true -> to'liq tarix).
  //
  // activeOnly — faqat HALI QABUL QILINMAGAN buyurtmalar (?active=1).
  // «Buyurtmalarim» ekrani aynan shularni ko'rsatadi; qabul qilinganlari
  // tarix ekranida, u esa kun bo'yicha alohida so'raladi ([fetchOrdersByDate]).
  // Shunday qilib bosh ekran 30 kunlik tarixni bekorga yuklab olmaydi.
  //
  // date — "YYYY-MM-DD": faqat shu kundagi buyurtmalar (?date=...).
  // Vaqt oynasidan mustaqil, ya'ni istalgan eski kun ochiladi.
  //
  // Javob: {"success": true, "message": "...", "data": [ {order}, ... ]}
  Future<List<OmborOrder>> fetchMyOrders({
    int? days,
    bool all = false,
    bool activeOnly = false,
    String? date,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (date != null) {
        query['date'] = date;
      } else if (all) {
        query['all'] = 1;
      } else if (days != null) {
        query['days'] = days;
      }
      if (activeOnly) {
        query['active'] = 1;
      }
      final response = await dio.get(
        AppUrls.orders,
        queryParameters: query.isEmpty ? null : query,
      );

      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map) {
          return parseOmborOrders(body['data']);
        }
        return <OmborOrder>[];
      } else {
        throw Exception('Buyurtmalarni yuklab bo\'lmadi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Buyurtmalarni yuklashda kutilmagan xato: $e');
    }
  }

  // POST /api/orders/{id}/items/{productId}/accept -> BITTA mahsulotni
  // qabul qilish (kelgan soni + rasm/video). Kamida bitta rasm yoki video
  // majburiy (UI shuni tekshiradi). Order statusi created/narxlandi
  // bo'lsagina ishlaydi; hamma item qabul bo'lsa backend statusni
  // 'qabul_qilindi' qiladi.
  // Javob: {"success": true, "message": "...", "data": {to'liq yangilangan order}}
  Future<OmborOrder> acceptOrderItem(
    int orderId,
    int productId,
    double received,
    String? imagePath,
    String? videoPath,
  ) async {
    try {
      final form = FormData();
      // Butun qiymat kasrsiz yuborilsin: 1500.0 emas, "1500" (кг/л — gramm).
      final receivedStr = received % 1 == 0
          ? received.toInt().toString()
          : received.toString();
      form.fields.add(MapEntry('received', receivedStr));
      if (imagePath != null) {
        form.files.add(MapEntry(
          'image',
          await MultipartFile.fromFile(imagePath),
        ));
      }
      if (videoPath != null) {
        form.files.add(MapEntry(
          'video',
          await MultipartFile.fromFile(videoPath),
        ));
      }
      final response = await dio.post(
        '${AppUrls.orders}/$orderId/items/$productId/accept',
        data: form,
      );
      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status >= 200 && status < 300) {
        final data = (body is Map) ? body['data'] : null;
        if (data is Map) {
          return OmborOrder.fromJson(Map<String, dynamic>.from(data));
        }
      }
      throw Exception('Qabul qilib bo\'lmadi: $status');
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('Qabul qilishda kutilmagan xato: $e');
    }
  }

  // DELETE /api/orders/{id}/items/{productId} -> BITTA mahsulotni buyurtmadan
  // o'chirish (soft-delete: item deleted=true bo'lib qoladi). Faqat katalog
  // item (item_type bo'sh), qabul qilinmagan, narxlanmagan (subtotal=0,
  // received=0) va order statusi 'qabul_qilindi' bo'lmaganda ishlaydi.
  // Javob: {"success": true, "message": "...", "data": {to'liq yangilangan order}}
  Future<OmborOrder> deleteOrderItem(int orderId, int productId) async {
    try {
      final response = await dio.delete(
        '${AppUrls.orders}/$orderId/items/$productId',
      );
      final status = response.statusCode ?? 0;
      final body = response.data;
      if (status >= 200 && status < 300) {
        final data = (body is Map) ? body['data'] : null;
        if (data is Map) {
          return OmborOrder.fromJson(Map<String, dynamic>.from(data));
        }
      }
      throw Exception('O\'chirib bo\'lmadi: $status');
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        final msg = (body is Map && body['message'] != null)
            ? body['message']
            : 'Server xatosi: ${e.response!.statusCode}';
        throw Exception(msg);
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    } catch (e) {
      throw Exception('O\'chirishda kutilmagan xato: $e');
    }
  }
}
