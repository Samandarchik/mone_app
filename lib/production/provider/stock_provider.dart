// production/provider/stock_provider.dart — sklad qoldig'i (stock) holati:
// StockProvider (sklad bo'yicha qoldiq keshi + katalog) — adjust/setMin/
// submitInventory/fetchMoves StockService orqali.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/catalog/catalog_repository.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';
import 'package:uz_ai_dev/production/services/stock_service.dart';

// Sklad qoldig'i holati: sklad bo'yicha qoldiqlar keshi, korreksiya va
// harakatlar tarixi. Ombor (o'z skladi) va admin (hamma sklad) sahifalari
// bitta shu provider'ni ishlatadi.
class StockProvider extends ChangeNotifier with ClearableProvider {
  final StockService _service = StockService();

  final Map<int, List<StockRow>> _bySklad = {};
  final Set<int> _loading = {};
  final Map<int, String> _errors = {};

  bool isSubmitting = false; // korreksiya yuborilayotganda

  bool _disposed = false;

  // productId -> StockRow indeksi (sklad bo'yicha). Kartochkalar qoldiqni har
  // build'da qidiradi; ro'yxat bo'ylab chiziqli qidiruv N ta kartochka ×
  // M ta qoldiq qatori = N×M taqqoslash bo'lardi. Indeks kesh sifatida
  // yasaladi va HAR notifyListeners'da bekor qilinadi — shuning uchun eskirib
  // qola olmaydi (UI faqat notifyListeners'dan keyin qayta chiziladi).
  Map<int, Map<int, StockRow>>? _rowIndex;

  Map<int, Map<int, StockRow>> get _index {
    var idx = _rowIndex;
    if (idx != null) return idx;
    idx = {};
    _bySklad.forEach((skladId, rows) {
      idx![skladId] = {for (final r in rows) r.productId: r};
    });
    _rowIndex = idx;
    return idx;
  }

  @override
  void notifyListeners() {
    _rowIndex = null;
    super.notifyListeners();
  }

  // null — hali yuklanmagan; bo'sh ro'yxat — yuklangan lekin qoldiq yo'q.
  List<StockRow>? stockFor(int skladId) => _bySklad[skladId];

  // Bitta mahsulotning qoldiq qatori — O(1). Yozuv topilmasa null.
  StockRow? rowFor(int skladId, int productId) => _index[skladId]?[productId];

  bool isLoading(int skladId) => _loading.contains(skladId);

  String? errorFor(int skladId) => _errors[skladId];

  // Mahsulot qoldig'i: yozuv bo'lmasa null (0 dan farqli — «yozuv yo'q»).
  double? qtyFor(int skladId, int productId) =>
      rowFor(skladId, productId)?.qty;

  // Mahsulot birligi (type): avval sklad qoldiq qatorlaridan, bo'lmasa
  // katalogdan. Topilmasa null (formatlashda faktor 1 ishlaydi).
  String? typeFor(int skladId, int productId) {
    final rows = _bySklad[skladId];
    if (rows != null) {
      for (final r in rows) {
        if (r.productId == productId && r.type.isNotEmpty) return r.type;
      }
    }
    for (final c in catalog) {
      if (c.id == productId && c.unit.isNotEmpty) return c.unit;
    }
    return null;
  }

  Future<void> fetchStock(int skladId) async {
    _loading.add(skladId);
    _errors.remove(skladId);
    notifyListeners();

    try {
      _bySklad[skladId] = await _service.fetchStock(skladId);
    } catch (e) {
      _errors[skladId] = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading.remove(skladId);
      if (!_disposed) notifyListeners();
    }
  }

  // Spinner'siz jim yangilash («Berdim» dan keyin qoldiqni yangilash).
  Future<void> refreshSilently(int skladId) async {
    try {
      _bySklad[skladId] = await _service.fetchStock(skladId);
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Jim — foydalanuvchi pull-to-refresh bilan qayta oladi.
    }
  }

  // Korreksiya (+/- qty). Muvaffaqiyatda skladni jim yangilaydi va null
  // qaytaradi; xatoda xabar matni qaytadi (UI snackbar ko'rsatadi).
  /// Spisaniya (brak) — muvaffaqiyatda null, aks holda xato matni.
  Future<String?> writeOff({
    required int skladId,
    required int productId,
    required double qty,
    required String reason,
  }) async {
    isSubmitting = true;
    notifyListeners();
    try {
      await _service.writeOff(
        skladId: skladId,
        productId: productId,
        qty: qty,
        reason: reason,
      );
      await refreshSilently(skladId);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<String?> adjust({
    required int skladId,
    required int productId,
    required double qty,
    required String comment,
  }) async {
    isSubmitting = true;
    notifyListeners();
    try {
      await _service.adjust(
        skladId: skladId,
        productId: productId,
        qty: qty,
        comment: comment,
      );
      await refreshSilently(skladId);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      isSubmitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Min chegara o'rnatish. Muvaffaqiyatda skladni jim yangilaydi va null
  // qaytaradi; xatoda xabar matni qaytadi (UI snackbar ko'rsatadi).
  Future<String?> setMin({
    required int skladId,
    required int productId,
    required double minQty,
  }) async {
    isSubmitting = true;
    notifyListeners();
    try {
      await _service.setMin(
        skladId: skladId,
        productId: productId,
        minQty: minQty,
      );
      await refreshSilently(skladId);
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      isSubmitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Inventarizatsiya yuborish. Muvaffaqiyatda (changed, null) qaytadi va
  // sklad jim yangilanadi; xatoda (null, xabar).
  Future<(int?, String?)> submitInventory({
    required int skladId,
    required List<Map<String, dynamic>> items,
  }) async {
    isSubmitting = true;
    notifyListeners();
    try {
      final changed = await _service.inventory(skladId: skladId, items: items);
      await refreshSilently(skladId);
      return (changed, null);
    } catch (e) {
      return (null, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      isSubmitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Harakatlar tarixi — keshlamasdan to'g'ridan-to'g'ri (bottom sheet o'zi
  // FutureBuilder bilan boshqaradi).
  Future<List<StockMove>> fetchMoves(
    int skladId, {
    int? productId,
    int? limit,
  }) =>
      _service.fetchMoves(skladId, productId: productId, limit: limit);

  // ───────────── Korreksiya dialogi uchun katalog (bir marta) ─────────────
  List<Product> catalog = [];
  bool _catalogLoaded = false;

  // Katalog — CatalogRepository (GET /api/products): korreksiya dialogida
  // qoldiqda hali yozuvi yo'q XOMASHYO (kind raw) tanlanadi; server rolga
  // qarab filtrlaydi (ombor: sotib olinadiganlar). Xato — jim bo'sh ro'yxat.
  Future<void> ensureCatalog() async {
    if (_catalogLoaded) return;
    try {
      final all = await sl<CatalogRepository>().load();
      catalog = all.where((p) => p.kind == ProductKind.raw).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      catalog = [];
    }
    _catalogLoaded = true;
    if (!_disposed) notifyListeners();
  }

  // Logout: sklad qoldiq keshi, katalog va yuklanish/xato holatini tozalaymiz.
  @override
  void clear() {
    _bySklad.clear();
    _loading.clear();
    _errors.clear();
    isSubmitting = false;
    catalog = [];
    _catalogLoaded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
