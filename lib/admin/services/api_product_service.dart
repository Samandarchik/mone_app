// admin/services/api_product_service.dart — mahsulot CRUD servisi
// (ApiProductService): AppUrls.productAll (getAllProducts), AppUrls.product ga
// post/put/delete (createProduct/updateProduct/deleteProduct),
// AppUrls.productReorder ga PUT (reorderProducts) va
// AppUrls.productManualPrice ga PUT (setManualPrice — qo'lda xarid narxi).
// Product bilan.
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/admin/model/tech_card_version.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

// Server 400 javobidagi `data.unlinked` — bog'lanmagan retsept qatorlari
// nomlari ([] — bunday xato emas).
List<String> unlinkedNamesOf(dynamic body) {
  if (body is! Map) return const [];
  final data = body['data'];
  if (data is! Map) return const [];
  final list = data['unlinked'];
  if (list is! List) return const [];
  return [for (final e in list) e.toString()];
}

// Retseptda mahsulotga bog'lanmagan qatorlar bor — saqlanmadi.
class UnlinkedRecipeLinesException implements Exception {
  final List<String> names;
  const UnlinkedRecipeLinesException(this.names);

  @override
  String toString() => 'Bog\'lanmagan masalliqlar: ${names.join(', ')}';
}

class ApiProductService {
  final Dio dio = sl<Dio>();

  // Create new product
  Future<Product> createProduct(Product product) async {
    try {
      final response = await dio.post(
        AppUrls.product, // product endpoint
        data: product.toJson(),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final responseData = response.data['data'] ?? response.data;
        return Product.fromJson(responseData);
      } else {
        throw Exception('Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        final unlinked = unlinkedNamesOf(e.response!.data);
        if (unlinked.isNotEmpty) {
          throw UnlinkedRecipeLinesException(unlinked);
        }
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
  Future<Product> updateProduct(Product product) async {
    try {
      final response = await dio.put(
        '${AppUrls.product}/${product.id}',
        data: product.toJson(),
      );
      if (response.statusCode == 200) {
        final responseData = response.data['data'] ?? response.data;
        return Product.fromJson(responseData);
      } else {
        throw Exception('Server xatosi: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 404) {
          throw Exception('Mahsulot topilmadi');
        }
        // 400 + data.unlinked — retseptda mahsulotga bog'lanmagan qatorlar:
        // server nomlarini qaytaradi, muharrir ularni ko'rsatadi.
        final unlinked = unlinkedNamesOf(e.response!.data);
        if (unlinked.isNotEmpty) {
          throw UnlinkedRecipeLinesException(unlinked);
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
  Future<Product> deleteProduct(Product product) async {
    try {
      final response = await dio.delete(
        '${AppUrls.product}/${product.id}',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.statusCode == 204 || response.data == null) {
          return product;
        } else {
          final responseData = response.data['data'] ?? response.data;
          return Product.fromJson(responseData);
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
  Future<Product> rollbackTechCard(int productId, int versionId) async {
    try {
      final response = await dio.post(
        AppUrls.techCardRollback(productId),
        data: {'version_id': versionId},
      );
      return Product.fromJson(response.data['data']);
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
