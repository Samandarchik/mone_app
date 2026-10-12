// core/catalog/catalog_repository.dart — katalogning YAGONA manbai
// (CatalogRepository, GetIt singleton `sl<CatalogRepository>()`): hamma rol
// mahsulotlarni SHU yerdan oladi. Endpoint bitta — GET /api/products; rol
// bo'yicha filtr SERVERDA (seller: o'z filiali sotiladiganlari; ombor:
// sotib olinadiganlar; shef: retseptlilar; admin: hammasi). Shu sabab klient
// «qaysi endpoint» deb o'ylamaydi, faqat `withRecipe` (admin/shef uchun
// `?include=recipe`) tanlaydi.
//
// Oqim: `load()` — avval xotira, yo'q bo'lsa disk kesh (darhol ko'rinadi),
// keyin tarmoq (fon isolate'ida parse) va kesh yangilanadi. create/update/
// delete'dan keyin `upsertLocal`/`removeLocal` — to'liq re-fetch YO'Q.
// Logout: `clear()` (xotira + disk).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/core/catalog/catalog_cache.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';

class CatalogRepository extends ChangeNotifier {
  CatalogRepository(this._dio, {CatalogCache? cache})
      : _cache = cache ?? CatalogCache();

  final Dio _dio;
  final CatalogCache _cache;

  List<Product> _products = [];
  Map<int, Product>? _byId;
  bool _loaded = false;
  bool _hasRecipes = false;
  Future<List<Product>>? _inflight;

  // Joriy ro'yxat (server tartibida). O'ZGARTIRMA — upsertLocal/removeLocal.
  List<Product> get products => _products;

  // Tarmoqdan (yoki keshdan) kamida bir marta yuklanganmi.
  bool get isLoaded => _loaded;

  // Oxirgi yuklash retsept bilan bo'lganmi (?include=recipe).
  bool get hasRecipes => _hasRecipes;

  // ---- yuklash ----

  /// Disk keshdan o'qiydi (faqat xotira bo'sh bo'lsa). Kesh bo'lmasa null.
  Future<List<Product>?> loadCached() async {
    if (_products.isNotEmpty) return _products;
    final cached = await _cache.read();
    if (cached == null || cached.isEmpty) return null;
    if (_products.isEmpty) {
      _set(cached, loaded: true, hasRecipes: cached.any((p) => p.techCard != null));
    }
    return _products;
  }

  /// Katalogni yuklaydi. Yuklangan bo'lsa va `force` yo'q bo'lsa — xotiradagi
  /// ro'yxat (retsept kerak bo'lib, oldingi yuklash retseptsiz bo'lsa qayta
  /// so'raydi). Parallel chaqiruvlar bitta so'rovni kutadi.
  Future<List<Product>> load({bool withRecipe = false, bool force = false}) {
    if (_loaded && !force && (!withRecipe || _hasRecipes)) {
      return Future.value(_products);
    }
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _fetch(withRecipe || _hasRecipes);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<List<Product>> _fetch(bool withRecipe) async {
    final raw = await _fetchRaw(withRecipe);
    final list = await compute(parseCatalogJson, raw);
    _set(list, loaded: true, hasRecipes: withRecipe);
    // Kesh yozish javobni kutib turmaydi.
    unawaited(_cache.write(raw));
    return _products;
  }

  // Xom javob (~1.6 MB bo'lishi mumkin): `ResponseType.plain` — Dio uni UI
  // oqimida dekod QILMAYDI, parse `compute()` da.
  Future<String> _fetchRaw(bool withRecipe) async {
    try {
      final response = await _dio.get<String>(
        AppUrls.products,
        queryParameters: withRecipe ? {'include': 'recipe'} : null,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode == 200) return response.data ?? '';
      throw Exception('Server xatosi: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        String? msg;
        if (body is Map && body['message'] != null) {
          msg = body['message'].toString();
        }
        throw Exception(msg ??
            'Server xatosi: ${e.response!.statusCode} - ${e.response!.statusMessage}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  void _set(List<Product> list, {required bool loaded, required bool hasRecipes}) {
    _products = list;
    _byId = null;
    _loaded = loaded;
    _hasRecipes = hasRecipes;
    notifyListeners();
  }

  // ---- qidiruv/filtr ----

  // Indeks dangasa quriladi; ro'yxat tashqaridan (testlarda addAll) o'zgargan
  // bo'lsa uzunlik farqi bo'yicha qayta quriladi.
  Product? byId(int id) {
    var index = _byId;
    if (index == null || index.length != _products.length) {
      index = _byId = {for (final p in _products) p.id: p};
    }
    return index[id];
  }

  List<Product> byCategory(int categoryId) =>
      _products.where((p) => p.categoryId == categoryId).toList();

  List<Product> byKind(ProductKind kind) =>
      _products.where((p) => p.kind == kind).toList();

  /// Kategoriya NOMI bo'yicha guruhlash, server tartibi saqlanadi (kategoriya
  /// nomi bo'sh bo'lgan mahsulotlar «» kalitiga tushmaydi — tashlanadi).
  Map<String, List<Product>> groupedByCategory([List<Product>? source]) {
    final result = <String, List<Product>>{};
    for (final p in source ?? _products) {
      if (p.categoryName.isEmpty) continue;
      result.putIfAbsent(p.categoryName, () => []).add(p);
    }
    return result;
  }

  // ---- lokal yangilash (serverda allaqachon saqlangan) ----

  /// Mahsulotni ro'yxatga qo'yadi/almashtiradi (id bo'yicha).
  void upsertLocal(Product product) {
    final i = _products.indexWhere((p) => p.id == product.id);
    final next = List<Product>.of(_products);
    if (i == -1) {
      next.add(product);
    } else {
      next[i] = product;
    }
    _set(next, loaded: _loaded, hasRecipes: _hasRecipes);
  }

  void removeLocal(int id) {
    if (!_products.any((p) => p.id == id)) return;
    _set(_products.where((p) => p.id != id).toList(),
        loaded: _loaded, hasRecipes: _hasRecipes);
  }

  /// Butun ro'yxatni almashtiradi (masalan tartiblashdan keyin).
  void replaceAll(List<Product> list) =>
      _set(List<Product>.of(list), loaded: _loaded, hasRecipes: _hasRecipes);

  /// Logout: xotira + disk kesh tozalanadi.
  void clear() {
    unawaited(_cache.clear());
    _products = [];
    _byId = null;
    _loaded = false;
    _hasRecipes = false;
    _inflight = null;
    notifyListeners();
  }
}
