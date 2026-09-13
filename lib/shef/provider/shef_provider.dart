// shef/provider/shef_provider.dart — shef roli holati: ShefProvider (orders,
// tex kartali products, полуфабрикат qoldig'i, socket) — buyurtma yaratish va
// masalliq accept/reject/progress ShefService orqali.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/network/order_socket.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/services/shef_service.dart';

// Shef roli uchun holat boshqaruvchi: ishlab chiqarish buyurtmalari ro'yxati,
// yaratish, masalliq qabul/rad va bo'lim progressi.
class ShefProvider extends ChangeNotifier with ClearableProvider {
  final ShefService _service = ShefService();

  // Mening buyurtmalarim (bosh ekran ro'yxati).
  List<ProductionOrder> orders = [];
  bool isLoading = false;
  String? errorMessage;

  // Buyurtma yaratish sahifasi: tex kartali mahsulotlar.
  List<ProductionProduct> products = [];
  bool isLoadingProducts = false;
  String? productsError;

  // «Полуфабрикат qoldig'i» ekrani (PfStockPage) uchun.
  List<PfStockRow> pfStock = [];
  int pfStockSkladId = 0;
  bool isLoadingPfStock = false;
  String? pfStockError;

  // Buyurtma yuborilayotganda tugma spinner'i uchun.
  bool isSubmitting = false;

  // Hozir amal bajarilayotgan bo'lim kaliti: "orderId:pi:si"
  // (accept/reject/progress tugmalarida spinner ko'rsatish uchun).
  String? busyStageKey;

  static String stageKey(int orderId, int pi, int si) => '$orderId:$pi:$si';

  ProductionOrder? orderById(int id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  Future<void> fetchOrders() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      orders = await _service.fetchOrders();
      _sortOrders();
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Spinner'siz jim yangilash (socket hodisalari va detal refreshlar uchun).
  Future<void> refreshSilently() async {
    try {
      orders = await _service.fetchOrders();
      _sortOrders();
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Jim qolamiz — foydalanuvchi pull-to-refresh bilan qayta oladi.
    }
  }

  void _sortOrders() {
    orders.sort((a, b) {
      final da = DateTime.tryParse(a.created) ?? DateTime(2000);
      final db = DateTime.tryParse(b.created) ?? DateTime(2000);
      return db.compareTo(da); // yangisi tepada
    });
  }

  // Bitta buyurtmani serverdan qayta olib lokal ro'yxatga qo'llash
  // (tafsilot sahifasidagi pull-to-refresh).
  Future<void> refreshOrder(int id) async {
    try {
      final updated = await _service.fetchOrder(id);
      if (updated != null) _upsert(updated);
      if (!_disposed) notifyListeners();
    } catch (_) {
      // Jim — tafsilot ekrani eski holatda qolaveradi.
    }
  }

  void _upsert(ProductionOrder order) {
    final i = orders.indexWhere((o) => o.id == order.id);
    if (i >= 0) {
      orders[i] = order;
    } else {
      orders.insert(0, order);
    }
  }

  Future<void> fetchProducts() async {
    isLoadingProducts = true;
    productsError = null;
    notifyListeners();

    try {
      products = await _service.fetchProducts();
    } catch (e) {
      productsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoadingProducts = false;
      notifyListeners();
    }
  }

  // Полуфабрикат qoldig'i. Ekran ochilganda va pull-to-refresh'da chaqiriladi;
  // parallel (ikkilangan) so'rov ketmasligi uchun yuklanayotgan bo'lsa chiqamiz.
  Future<void> fetchPfStock() async {
    if (isLoadingPfStock) return;
    isLoadingPfStock = true;
    pfStockError = null;
    notifyListeners();

    try {
      final data = await _service.fetchPfStock();
      pfStock = data.items;
      pfStockSkladId = data.skladId;
    } catch (e) {
      pfStockError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoadingPfStock = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Buyurtma yaratish. cart: productId -> qty (faqat qty > 0 lar yuboriladi).
  // Muvaffaqiyatda true; xatoda errorMessage to'ldirilib false.
  Future<bool> createOrder(Map<int, int> cart) async {
    final items = [
      for (final e in cart.entries)
        if (e.value > 0) {'product_id': e.key, 'qty': e.value},
    ];
    if (items.isEmpty) {
      errorMessage = 'Kamida bitta mahsulot miqdorini kiriting';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final created = await _service.createOrder(items);
      if (created != null) {
        _upsert(created);
        _sortOrders();
      } else {
        await refreshSilently();
      }
      return true;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isSubmitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Bo'lim amali (accept/reject/progress) uchun umumiy o'ram: spinner kaliti,
  // muvaffaqiyatda yangilangan buyurtmani qo'llash. Xato xabari qaytadi
  // (null — muvaffaqiyat); UI snackbar ko'rsatadi.
  Future<String?> _stageAction(
    int orderId,
    int pi,
    int si,
    Future<ProductionOrder?> Function() action,
  ) async {
    busyStageKey = stageKey(orderId, pi, si);
    notifyListeners();
    try {
      final updated = await action();
      if (updated != null) {
        _upsert(updated);
      } else {
        // Server buyurtmani qaytarmasa — o'zimiz qayta olamiz.
        final fresh = await _service.fetchOrder(orderId);
        if (fresh != null) _upsert(fresh);
      }
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } finally {
      busyStageKey = null;
      if (!_disposed) notifyListeners();
    }
  }

  // Shef: «Qabul qildim» — material_status = qabul_qilindi.
  Future<String?> acceptStage(int orderId, int pi, int si) =>
      _stageAction(orderId, pi, si,
          () => _service.acceptStage(orderId, pi, si));

  // Shef: «Qabul qilmadim» (izoh bilan) — material_status = rad_etildi.
  Future<String?> rejectStage(int orderId, int pi, int si, String comment) =>
      _stageAction(orderId, pi, si,
          () => _service.rejectStage(orderId, pi, si, comment));

  // Shef: bo'limda tugatilgan sonni kiritish (kumulyativ).
  Future<String?> setProgress(int orderId, int pi, int si, int doneQty) =>
      _stageAction(orderId, pi, si,
          () => _service.setProgress(orderId, pi, si, doneQty));

  // ─────────────────────── Real-time (WebSocket) ───────────────────────
  StreamSubscription<ProductionSocketEvent>? _socketSub;

  // production hodisasida ro'yxatni jim yangilaymiz (payload'siz signal).
  void connectSocket() {
    // connect/disconnect juftligi _socketSub orqali balanslanadi —
    // OrderSocket ref-count to'g'ri ishlashi uchun (qarang: order_socket.dart).
    if (_socketSub != null) return;
    _socketSub =
        OrderSocket.instance.productionEvents.listen((_) => refreshSilently());
    OrderSocket.instance.connect();
  }

  void disconnectSocket() {
    if (_socketSub == null) return;
    _socketSub!.cancel();
    _socketSub = null;
    OrderSocket.instance.disconnect();
  }

  bool _disposed = false;

  // Logout: socketni uzib, buyurtmalar/mahsulotlar va holat maydonlarini
  // boshlang'ich holatga qaytaramiz.
  @override
  void clear() {
    disconnectSocket();
    orders = [];
    isLoading = false;
    errorMessage = null;
    products = [];
    isLoadingProducts = false;
    productsError = null;
    pfStock = [];
    pfStockSkladId = 0;
    isLoadingPfStock = false;
    pfStockError = null;
    isSubmitting = false;
    busyStageKey = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnectSocket();
    super.dispose();
  }
}
