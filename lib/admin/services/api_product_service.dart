// admin/services/api_product_service.dart — mahsulot CRUD servisi
// (ApiProductService): AppUrls.productAll (getAllProducts), AppUrls.product ga
// post/put/delete (createProduct/updateProduct/deleteProduct),
// AppUrls.productReorder ga PUT (reorderProducts) va
// AppUrls.productManualPrice ga PUT (setManualPrice — qo'lda xarid narxi).
// ProductModelAdmin bilan.
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card_version.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/data/local/products_cache.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

class ApiProductService {
  final Dio dio = sl<Dio>();

  // Mahsulotlar ro'yxatining XOM javobi (~1.6 MB): `ResponseType.plain` —
  // Dio uni UI oqimida dekod QILMAYDI. Dekod + fromJson `compute()` fon
  // isolate'ida bajariladi (`parseProductsJson`), xom matn esa keshga
  // yoziladi (`ProductsCache`). Ilgari bu yerda 1342 ta fromJson main
  // isolate'da ishlab ANR («isn't responding») berardi.
  Future<String> fetchAllProductsRaw() async {
    try {
      final response = await dio.get<String>(
        AppUrls.productAll,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode == 200) return response.data ?? '';
      throw Exception('Server xatosi: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Server xatosi: ${e.response!.statusCode} - ${e.response!.statusMessage}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  // Get all products — xom javob + FON isolate'da parse.
  Future<List<ProductModelAdmin>> getAllProducts() async {
    try {
      final raw = await fetchAllProductsRaw();
      return compute(parseProductsJson, raw);
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Server xatosi: ${e.response!.statusCode} - ${e.response!.statusMessage}');
      } else {
        throw Exception('Tarmoq xatosi: ${e.message}');
      }
    } catch (e) {
      debugPrint('Ошибка getAllProducts: $e');
      throw Exception('Kutilmagan Ошибка: $e');
    }
  }

  // Create new product
  Future<ProductModelAdmin> createProduct(ProductModelAdmin product) async {
    try {
      final response = await dio.post(
        AppUrls.product, // product endpoint
        data: product.toCreateJson(),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = response.data['data'] ?? response.data;
        return ProductModelAdmin.fromJson(responseData);
      } else {
        throw Exception('Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Mahsulot yaratishda Ошибка: ${parseDioError(e)}');
      } else {
        throw Exception('Tarmoq xatosi: ${e.message}');
      }
    } catch (e) {
      debugPrint('Ошибка createProduct: $e');
      throw Exception('Mahsulot yaratishda kutilmagan Ошибка: $e');
    }
  }

  // Update existing product
  Future<ProductModelAdmin> updateProduct(ProductModelAdmin product) async {
    try {
      final response = await dio.put(
        '${AppUrls.product}/${product.id}',
        data: product.toUpdateJson(),
      );
      if (response.statusCode == 200) {
        final responseData = response.data['data'] ?? response.data;
        return ProductModelAdmin.fromJson(responseData);
      } else {
        throw Exception('Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404) {
          throw Exception('Mahsulot topilmadi');
        }
        throw Exception('Mahsulot yangilashda Ошибка: ${parseDioError(e)}');
      } else {
        throw Exception('Tarmoq xatosi: ${e.message}');
      }
    } catch (e) {
      throw Exception('Mahsulot yangilashda kutilmagan Ошибка: $e');
    }
  }

  // Delete product
  Future<ProductModelAdmin> deleteProduct(ProductModelAdmin product) async {
    try {
      final response = await dio.delete(
        '${AppUrls.product}/${product.id}',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.statusCode == 204 || response.data == null) {
          return product;
        } else {
          final responseData = response.data['data'] ?? response.data;
          return ProductModelAdmin.fromJson(responseData);
        }
      } else {
        throw Exception('Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404) {
          throw Exception('Mahsulot topilmadi');
        } else if (e.response!.statusCode == 409) {
          // Server qaysi retseptlarda ishlatilganini aytadi — o'sha matnni ko'rsatamiz.
          throw Exception(parseDioError(e,
              fallback: 'Mahsulot o\'chirib bo\'lmaydi, u retseptlarda ishlatilmoqda'));
        }
        throw Exception('Mahsulot o\'chirishda Ошибка: ${parseDioError(e)}');
      } else {
        throw Exception('Tarmoq xatosi: ${e.message}');
      }
    } catch (e) {
      debugPrint('Ошибка deleteProduct: $e');
      throw Exception('Mahsulot o\'chirishda kutilmagan Ошибка: $e');
    }
  }

  // PUT /api/products/{id}/manual-price — masalliqning QO'LDA kiritilgan
  // xarid narxi (BUTUN so'm, mahsulotning TO'LIQ birligi uchun; 0 —
  // o'chirish). Javob data: {product_id, manual_price, manual_price_at}.
  Future<Map<String, dynamic>> setManualPrice(int productId, int price) async {
    try {
      final response = await dio.put(
        AppUrls.productManualPrice(productId),
        data: {'manual_price': price},
      );
      if (response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['data'] is Map) {
          return Map<String, dynamic>.from(body['data']);
        }
        return {'product_id': productId, 'manual_price': price};
      }
      throw Exception('Server xatosi: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404) {
          throw Exception('Mahsulot topilmadi');
        }
        throw Exception('Narx saqlanmadi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  // Retsept (tex karta) tarixi — meta ro'yxat, eng yangisi birinchi.
  Future<List<TechCardVersionMeta>> fetchTechCardVersions(int productId) async {
    try {
      final response = await dio.get(AppUrls.techCardVersions(productId));
      final data = response.data['data'];
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => TechCardVersionMeta.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      throw Exception('Tarix yuklanmadi: ${parseDioError(e)}');
    }
  }

  // Tex kartani tanlangan versiyaga qaytarish. Javob — yangilangan mahsulot.
  Future<ProductModelAdmin> rollbackTechCard(int productId, int versionId) async {
    try {
      final response = await dio.post(
        AppUrls.techCardRollback(productId),
        data: {'version_id': versionId},
      );
      return ProductModelAdmin.fromJson(response.data['data']);
    } on DioException catch (e) {
      throw Exception('Qaytarib bo\'lmadi: ${parseDioError(e)}');
    }
  }

  // Reorder products by category
  Future<bool> reorderProducts(int categoryId, List<int> ids) async {
    try {
      final response = await dio.put(
        AppUrls.productReorder,
        data: {'category_id': categoryId, 'ids': ids},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Ошибка reorderProducts: $e');
      return false;
    }
  }
}
