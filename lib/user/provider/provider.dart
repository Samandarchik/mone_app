// user/provider/provider.dart — Seller (user) roli markaziy provideri va modellari: ProductProvider
// (ChangeNotifier — productsByCategory, categories, selectedProducts savat, submitOrder), modellar
// Product/CategoryModel/OrderItem va ProductService (GET category/product1, POST AppUrls.orders).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/catalog/catalog_repository.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';

// Tolerant JSON yordamchilari (naqsh: production/models/stock_model.dart) —
// server int/double/string/null yuborsa ham parsing yiqilmaydi.
int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ??
      (double.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
}

// Category Model
class CategoryModel {
  final int id;
  final String name;
  final int print;
  final String? imageUrl;

  CategoryModel({
    required this.id,
    required this.name,
    required this.print,
    this.imageUrl,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      print: _asInt(json['printer']),
      imageUrl: json['image_url']?.toString(),
    );
  }
}

// Order Item Model
class OrderItem {
  final int productId;
  final double count; // API birlikda: кг/л uchun butun gramm/ml

  OrderItem({
    required this.productId,
    required this.count,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      // Butun qiymatlar kasrsiz yuborilsin (1500, 1500.0 emas)
      'count': count % 1 == 0 ? count.toInt() : count,
    };
  }
}

class ProductProvider extends ChangeNotifier with ClearableProvider {
  Map<String, List<Product>> productsByCategory = {};
  List<CategoryModel> categories = [];
  Map<int, double> selectedProducts = {}; // productId: quantity (double)
  Map<int, int> productPrintMap = {}; // productId: print number
  bool isLoading = false;
  bool isSubmitting = false;
  String? errorMessage;
  final service = ProductService();

  // Kategoriyalarni yuklash
  Future<void> fetchCategories() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      categories = await service.fetchCategories();
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  // Mahsulotlarni yuklash
  Future<void> fetchProducts() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final service = ProductService();
      final result = await service.fetchProducts();
      productsByCategory = result['products'];
      productPrintMap = result['printMap'];
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  List<Product> getProductsByCategory(String category) {
    return productsByCategory[category] ?? [];
  }

  double getProductQuantity(int productId) {
    return selectedProducts[productId] ?? 0.0;
  }

  // Mahsulotni id bo'yicha topish
  Product? findProductById(int productId) {
    for (var products in productsByCategory.values) {
      for (var p in products) {
        if (p.id == productId) return p;
      }
    }
    return null;
  }

  // Mahsulot qadami (API birlikda: кг/л uchun gramm/ml, boshqalar uchun o'z
  // birligi) — sellStep (eng kichik birlikda butun), yo'q bo'lsa 1 to'liq birlik.
  double _getIncrementAmount(int productId) {
    final product = findProductById(productId);
    if (product != null) return product.sellStepOrDefault.toDouble();
    return 1.0;
  }

  // Floating point precision muammosini hal qilish
  double _roundToPrecision(double value, int decimals) {
    double mod = 1.0;
    for (int i = 0; i < decimals; i++) {
      mod *= 10;
    }
    return (value * mod).round() / mod;
  }

  void incrementProduct(int productId) {
    double amount = _getIncrementAmount(productId);
    double newValue = (selectedProducts[productId] ?? 0.0) + amount;
    selectedProducts[productId] = _roundToPrecision(newValue, 3);
    notifyListeners();
  }

  void decrementProduct(int productId) {
    if (selectedProducts.containsKey(productId)) {
      double amount = _getIncrementAmount(productId);
      double newQuantity = selectedProducts[productId]! - amount;
      newQuantity = _roundToPrecision(newQuantity, 3);
      if (newQuantity > 0) {
        selectedProducts[productId] = newQuantity;
      } else {
        selectedProducts.remove(productId);
      }
      notifyListeners();
    }
  }

  void setProductQuantity(int productId, double quantity) {
    if (quantity > 0) {
      selectedProducts[productId] = quantity;
    } else {
      selectedProducts.remove(productId);
    }
    notifyListeners();
  }

  double get totalSelectedProducts {
    // UI birlikda yig'indi (кг/л mahsulotlar gramm emas, kg sifatida)
    double sum = 0.0;
    selectedProducts.forEach((productId, qty) {
      final product = findProductById(productId);
      sum += qtyToUi(qty, product?.unit);
    });
    return sum;
  }

  void clearSelection() {
    selectedProducts.clear();
    notifyListeners();
  }

  // Logout: barcha katalog + savat + holat maydonlarini boshlang'ich holatga.
  @override
  void clear() {
    productsByCategory = {};
    categories = [];
    selectedProducts = {};
    productPrintMap = {};
    isLoading = false;
    isSubmitting = false;
    errorMessage = null;
    notifyListeners();
  }

  // Buyurtmani print bo'yicha guruhlash va yuborish.
  // Chek chiqmagan guruhlar bo'lsa ogohlantirish matnini qaytaradi, aks holda null.
  Future<String?> submitOrder() async {
    isSubmitting = true;
    notifyListeners();

    // Chek chiqmagan guruhlarning ogohlantirishlari (takrorlanmasin)
    final Set<String> printWarnings = {};

    try {
      // Print bo'yicha guruhlash
      Map<int, List<OrderItem>> ordersByPrint = {};

      selectedProducts.forEach((productId, count) {
        int printNumber = productPrintMap[productId] ?? 1;

        if (!ordersByPrint.containsKey(printNumber)) {
          ordersByPrint[printNumber] = [];
        }

        ordersByPrint[printNumber]!.add(
          OrderItem(
            productId: productId,
            count: count,
          ),
        );
      });

      // Print raqami bo'yicha tartiblash (1, 2, 3...)
      List<int> sortedPrintNumbers = ordersByPrint.keys.toList()..sort();

      // Har bir print uchun ketma-ket yuborish
      final service = ProductService();
      for (int printNumber in sortedPrintNumbers) {
        List<OrderItem> items = ordersByPrint[printNumber]!;

        Map<String, dynamic> orderData = {
          'items': items.map((item) => item.toJson()).toList(),
        };

        final warning = await service.submitOrder(orderData);
        if (warning != null) {
          printWarnings.add(warning);
        }

        // Guruh qabul qilindi — savatdan darhol olib tashlaymiz:
        // keyingi guruh yiqilsa, retry bu guruhni qayta yubormaydi
        for (var item in items) {
          selectedProducts.remove(item.productId);
        }
        notifyListeners();

        // Keyingi printerga yuborishdan oldin biroz kutish
        if (printNumber != sortedPrintNumbers.last) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }

      // Hammasi yuborildi — qolgan holatni tozalash
      clearSelection();

      // Chek chiqmagan guruh(lar) bo'lsa — ogohlantirishni qaytaramiz
      return printWarnings.isEmpty ? null : printWarnings.join('\n');
    } catch (e) {
      // 'Exception: ' matryoshka prefikslarini olib tashlab toza xabar uzatamiz
      var message = e.toString();
      while (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }
      throw Exception(message);
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }
}

class ProductService {
  Dio dio = sl<Dio>();

  // Kategoriyalarni olish
  Future<List<CategoryModel>> fetchCategories() async {
    try {
      final response = await dio.get(AppUrls.category);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        return data.map((item) => CategoryModel.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load categories: $e');
    }
  }

  // Mahsulotlarni olish — CatalogRepository (GET /api/products; server
  // seller uchun o'z filiali sotiladigan mahsulotlarini qaytaradi).
  // Kategoriya nomi bo'yicha guruhlanadi + har mahsulot uchun print raqami
  // (kategoriyaning `printer` maydoni).
  Future<Map<String, dynamic>> fetchProducts() async {
    try {
      final repo = sl<CatalogRepository>();
      final productsFuture = repo.load(force: true);
      // Kategoriyalar — print raqami uchun.
      final categoriesResponse = await fetchCategories();
      final categoryPrintMap = <String, int>{
        for (final c in categoriesResponse) c.name: c.print,
      };
      final products = await productsFuture;
      final productsByCategory = repo.groupedByCategory(products);
      final productPrintMap = <int, int>{
        for (final p in products) p.id: categoryPrintMap[p.categoryName] ?? 1,
      };
      return {
        'products': productsByCategory,
        'printMap': productPrintMap,
      };
    } catch (e) {
      throw Exception('Failed to load products: $e');
    }
  }

  // Buyurtma yuborish. Buyurtma qabul qilinib, lekin chek printerga
  // chiqmagan bo'lsa (status == 'print_error') — server xabarini
  // ogohlantirish sifatida qaytaradi, aks holda null.
  Future<String?> submitOrder(Map<String, dynamic> orderData) async {
    try {
      final response = await dio.post(
        AppUrls.orders,
        data: orderData,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to submit order: ${response.statusCode}');
      }

      // 200, lekin chek chiqmagan bo'lishi mumkin — data.status'ni tekshiramiz
      final data = response.data;
      if (data is Map && data['data'] is Map) {
        final status = (data['data'] as Map)['status'];
        if (status == 'print_error') {
          final message = data['message'];
          if (message is String && message.isNotEmpty) {
            return message;
          }
        }
      }
      return null;
    } on DioException catch (e) {
      // Server JSON'ida aniq 'message' bo'lsa (masalan 503 — printer
      // ishlamayapti), foydalanuvchiga FAQAT o'sha matnni ko'rsatamiz
      final data = e.response?.data;
      final serverMessage = data is Map ? data['message'] : null;
      if (serverMessage is String && serverMessage.isNotEmpty) {
        throw Exception(serverMessage);
      }
      throw Exception('Failed to submit order: $e');
    } catch (e) {
      throw Exception('Failed to submit order: $e');
    }
  }
}
