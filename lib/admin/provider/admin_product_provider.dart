// admin/provider/admin_product_provider.dart — mahsulotlarning YAGONA manbai
// (ProductProviderAdmin, ChangeNotifier): barcha mahsulotlarni bir marta
// yuklaydi (initializeProducts), kategoriya bo'yicha filtrlaydi
// (filterByCategory) va create/update/delete/reorderProducts/setManualPrice
// (qo'lda xarid narxi) ni xotirada yangilaydi — to'liq re-fetch YO'Q.
// ApiProductService bilan ishlaydi.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/services/api_product_service.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/data/local/products_cache.dart';

class ProductProviderAdmin extends ChangeNotifier with ClearableProvider {
  final ApiProductService _service = ApiProductService();

  // Lokal kesh: `/api/products/all` xom javobi app papkasidagi faylda.
  final ProductsCache _cache = ProductsCache();

  // Barcha mahsulotlar bir marta yuklanadi
  List<ProductModelAdmin> _allProducts = [];
  List<ProductModelAdmin> _filteredProducts = [];
  bool _isLoading = false;
  bool _isInitialized = false; // Ma'lumotlar yuklangani
  String? _error;
  int? _selectedCategoryId;

  // Getters
  List<ProductModelAdmin> get products => _allProducts;
  List<ProductModelAdmin> get filteredProducts => _filteredProducts;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;

  // Barcha mahsulotlarni yuklash: AVVAL lokal kesh (fon isolate'ida parse —
  // ro'yxat darhol ko'rinadi), KEYIN tarmoqdan yangilanadi va kesh qayta
  // yoziladi. Javob ~1.6 MB bo'lgani uchun na yuklab olish, na parse UI
  // oqimini bloklamaydi (ilgari shu yerda ANR chiqardi).
  Future<void> initializeProducts({bool forceRefresh = false}) async {
    // Agar allaqachon yuklangan bo'lsa va force refresh yo'q bo'lsa, qayta yuklamaymiz
    if (_isInitialized && !forceRefresh) {
      return;
    }

    // 1) Kesh — tarmoqni kutmasdan ko'rsatamiz (bo'sh ekran / spinner yo'q).
    if (_allProducts.isEmpty) {
      final cached = await _cache.read();
      if (cached != null && cached.isNotEmpty) {
        _allProducts = cached;
        _applyFilter();
        _isInitialized = true;
        _isLoading = false;
        notifyListeners();
      }
    }

    // 2) Tarmoq. Keshdan ko'rsatilgan bo'lsa spinner chiqarmaymiz — ro'yxat
    // ekranda turadi va yangi ma'lumot kelganda jimgina almashadi.
    final hadData = _allProducts.isNotEmpty;
    _error = null;
    _isLoading = !hadData;
    if (!hadData) notifyListeners();

    try {
      final raw = await _service.fetchAllProductsRaw();
      _allProducts = await compute(parseProductsJson, raw);
      _applyFilter();
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
      // Kesh yozish javobni kutib turmaydi.
      unawaited(_cache.write(raw));
    } catch (e) {
      _isLoading = false;
      // Keshdan ko'rsatilgan bo'lsa xatoni chiqarmaymiz — eski ro'yxat
      // ishlayveradi (offline rejim).
      if (!hadData) {
        _error = e.toString();
        _isInitialized = false;
      }
      notifyListeners();
    }
  }

  // Joriy filtrni (_selectedCategoryId) _allProducts ga qayta qo'llaydi.
  // Nusxa olamiz — bir xil List'ga alias bo'lsa, filter/remove'lar
  // _allProducts'ni ham buzib yuborardi.
  void _applyFilter() {
    _filteredProducts = _selectedCategoryId == null
        ? List.of(_allProducts)
        : _allProducts
            .where((product) => product.categoryId == _selectedCategoryId)
            .toList();
  }

  // Kategoriya bo'yicha filter (internetga murojaat qilmasdan)
  void filterByCategory(int categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilter();
    notifyListeners();
  }

  // Create new product
  Future<bool> createProduct(ProductModelAdmin product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newProduct = await _service.createProduct(product);

      // Barcha mahsulotlar ro'yxatiga qo'shish
      _allProducts.add(newProduct);

      // Agar hozirgi filter mos kelsa, filtered listga ham qo'shamiz
      if (_selectedCategoryId == null ||
          newProduct.categoryId == _selectedCategoryId) {
        _filteredProducts.add(newProduct);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update existing product
  Future<bool> updateProduct(ProductModelAdmin product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedProduct = await _service.updateProduct(product);

      // Barcha mahsulotlar ro'yxatida yangilash
      final index = _allProducts.indexWhere((p) => p.id == updatedProduct.id);
      if (index != -1) {
        _allProducts[index] = updatedProduct;
      }

      // Filtered listda yangilash
      final filteredIndex =
          _filteredProducts.indexWhere((p) => p.id == updatedProduct.id);
      if (filteredIndex != -1) {
        _filteredProducts[filteredIndex] = updatedProduct;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Bitta mahsulot (id bo'yicha). Topilmasa null. Ro'yxat bo'ylab chiziqli
  // qidiradi — build() ICHIDA emas, bir martalik chaqiruvlarda ishlating.
  ProductModelAdmin? productById(int id) {
    for (final p in _allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  // Masalliqning QO'LDA kiritilgan xarid narxi (PUT
  // /api/products/{id}/manual-price). price — BUTUN so'm, mahsulotning
  // TO'LIQ birligi uchun (кг → 1 kg narxi); 0 — qo'lda narxni O'CHIRISH.
  // Muvaffaqiyatda mahsulot XOTIRADA yangilanadi (to'liq re-fetch YO'Q).
  Future<bool> setManualPrice(int productId, int price) async {
    _error = null;
    try {
      final data = await _service.setManualPrice(productId, price);
      final saved = (data['manual_price'] as num?)?.toInt() ?? price;
      final at = DateTime.tryParse(data['manual_price_at']?.toString() ?? '');

      void patch(List<ProductModelAdmin> list) {
        final i = list.indexWhere((p) => p.id == productId);
        if (i != -1) {
          list[i] = list[i].copyWith(manualPrice: saved, manualPriceAt: at);
        }
      }

      patch(_allProducts);
      patch(_filteredProducts);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  // Delete product
  /// Serverda ALLAQACHON yangilangan mahsulotni lokal ro'yxatlarga qo'yadi
  /// (masalan tex karta rollback javobidan) — qayta fetch qilinmaydi.
  void applyServerProduct(ProductModelAdmin updated) {
    final index = _allProducts.indexWhere((p) => p.id == updated.id);
    if (index != -1) _allProducts[index] = updated;
    final filteredIndex = _filteredProducts.indexWhere((p) => p.id == updated.id);
    if (filteredIndex != -1) _filteredProducts[filteredIndex] = updated;
    notifyListeners();
  }

  Future<bool> deleteProduct(ProductModelAdmin product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deleteProduct(product);

      // Barcha ro'yxatlardan o'chirish
      _allProducts.removeWhere((p) => p.id == product.id);
      _filteredProducts.removeWhere((p) => p.id == product.id);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Reorder products within category
  // Eslatma: onReorderItem callback'i newIndex'ni allaqachon to'g'irlab beradi,
  // shuning uchun bu yerda qo'lda kompensatsiya kerak emas.
  Future<bool> reorderProducts(int categoryId, int oldIndex, int newIndex) async {
    final item = _filteredProducts.removeAt(oldIndex);
    _filteredProducts.insert(newIndex, item);
    notifyListeners();

    final ids = _filteredProducts.map((p) => p.id).toList();
    final success = await _service.reorderProducts(categoryId, ids);
    if (!success) {
      await initializeProducts(forceRefresh: true);
      filterByCategory(categoryId);
    }
    return success;
  }

  // Kategoriya bo'yicha mahsulotlar sonini olish
  int getProductCountByCategory(int categoryId) {
    return _allProducts.where((p) => p.categoryId == categoryId).length;
  }

  // Logout: mahsulotlar (YAGONA manba) va filtr/holat maydonlarini tozalaymiz.
  // Kesh fayli ham o'chadi — keyingi foydalanuvchiga eski ro'yxat ko'rinmasin.
  @override
  void clear() {
    unawaited(_cache.clear());
    _allProducts = [];
    _filteredProducts = [];
    _isLoading = false;
    _isInitialized = false;
    _error = null;
    _selectedCategoryId = null;
    notifyListeners();
  }
}
