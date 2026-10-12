// admin/provider/admin_product_provider.dart — admin/shef ekranlari uchun
// mahsulot holati (ProductProviderAdmin, ChangeNotifier). Ma'lumotning O'ZI
// endi YAGONA manbada — CatalogRepository (core/catalog): bu provider uni
// retsept bilan (`withRecipe: true`) yuklaydi, kategoriya bo'yicha filtrlaydi
// (filterByCategory) va create/update/delete/reorder/setManualPrice'dan keyin
// repozitoriyni LOKAL yangilaydi — to'liq re-fetch YO'Q. ApiProductService
// bilan ishlaydi.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/admin/services/api_product_service.dart';
import 'package:uz_ai_dev/core/catalog/catalog_repository.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/di/di.dart';

class ProductProviderAdmin extends ChangeNotifier with ClearableProvider {
  final ApiProductService _service = ApiProductService();
  final CatalogRepository _repo = sl<CatalogRepository>();

  List<Product> _filteredProducts = [];
  bool _isLoading = false;
  bool _isInitialized = false; // Ma'lumotlar yuklangani
  String? _error;
  int? _selectedCategoryId;

  // Getters
  List<Product> get products => _repo.products;
  List<Product> get filteredProducts => _filteredProducts;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;

  // Barcha mahsulotlarni (retsept bilan) yuklash: AVVAL lokal kesh (fon
  // isolate'ida parse — ro'yxat darhol ko'rinadi), KEYIN tarmoqdan yangilanadi.
  // Javob ~1.6 MB bo'lgani uchun na yuklab olish, na parse UI oqimini
  // bloklamaydi (CatalogRepository + CatalogCache).
  Future<void> initializeProducts({bool forceRefresh = false}) async {
    if (_isInitialized && !forceRefresh && _repo.hasRecipes) {
      return;
    }

    // 1) Kesh — tarmoqni kutmasdan ko'rsatamiz (bo'sh ekran / spinner yo'q).
    if (products.isEmpty) {
      final cached = await _repo.loadCached();
      if (cached != null && cached.isNotEmpty) {
        _applyFilter();
        _isInitialized = true;
        _isLoading = false;
        notifyListeners();
      }
    }

    // 2) Tarmoq. Keshdan ko'rsatilgan bo'lsa spinner chiqarmaymiz — ro'yxat
    // ekranda turadi va yangi ma'lumot kelganda jimgina almashadi.
    final hadData = products.isNotEmpty;
    _error = null;
    _isLoading = !hadData;
    if (!hadData) notifyListeners();

    try {
      await _repo.load(withRecipe: true, force: true);
      _applyFilter();
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
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

  // Joriy filtrni (_selectedCategoryId) repozitoriy ro'yxatiga qayta qo'llaydi.
  // Nusxa olamiz — bir xil List'ga alias bo'lsa reorder repo'ni ham buzardi.
  void _applyFilter() {
    _filteredProducts = _selectedCategoryId == null
        ? List.of(products)
        : products
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
  Future<bool> createProduct(Product product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newProduct = await _service.createProduct(product);
      _repo.upsertLocal(newProduct);
      _applyFilter();
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
  Future<bool> updateProduct(Product product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedProduct = await _service.updateProduct(product);
      _repo.upsertLocal(updatedProduct);
      _applyFilter();
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

  // Bitta mahsulot (id bo'yicha). Topilmasa null.
  Product? productById(int id) => _repo.byId(id);

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
      final current = _repo.byId(productId);
      if (current != null) {
        _repo.upsertLocal(
            current.copyWith(manualPrice: saved, manualPriceAt: at));
        _applyFilter();
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Serverda ALLAQACHON yangilangan mahsulotni lokal ro'yxatlarga qo'yadi
  /// (masalan tex karta rollback javobidan) — qayta fetch qilinmaydi.
  void applyServerProduct(Product updated) {
    _repo.upsertLocal(updated);
    _applyFilter();
    notifyListeners();
  }

  // Delete product
  Future<bool> deleteProduct(Product product) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deleteProduct(product);
      _repo.removeLocal(product.id);
      _applyFilter();
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
    return products.where((p) => p.categoryId == categoryId).length;
  }

  // Logout: filtr/holat maydonlarini tozalaymiz. Katalogning o'zi (xotira +
  // disk kesh) CatalogRepository.clear() da — session.dart chaqiradi.
  @override
  void clear() {
    _filteredProducts = [];
    _isLoading = false;
    _isInitialized = false;
    _error = null;
    _selectedCategoryId = null;
    notifyListeners();
  }
}
