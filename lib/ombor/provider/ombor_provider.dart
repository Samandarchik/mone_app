// ombor/provider/ombor_provider.dart — Ombor (bozor) roli markaziy provideri: OmborProvider
// (ChangeNotifier). Holat: productsByCategory, allCategories, savat (_cart — kalit (mahsulot,
// manba), qiymat milli-birlik butun son), myOrders; submitOrder/acceptOrderItem/deleteOrderItem
// va WebSocket real-time yangilanish.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/network/order_socket.dart';
import 'package:uz_ai_dev/core/utils/order_sequence.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/ombor/models/ombor_order_model.dart';
import 'package:uz_ai_dev/ombor/models/ombor_product_model.dart';
import 'package:uz_ai_dev/core/widgets/order_period.dart';
import 'package:uz_ai_dev/ombor/services/ombor_service.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';

// Savat qatori kaliti: (mahsulot, manba). Bitta mahsulot bir nechta manbadan
// (masalan Samarqand + Toshkent) ALOHIDA miqdor bilan buyurtma qilinishi
// mumkin — backend har manbani o'z bozorchisiga alohida buyurtma qiladi.
// Record qiymat bo'yicha solishtiriladi (== / hashCode), Map kaliti bo'la oladi.
typedef OmborCartKey = ({int productId, String source});

// Ombor bosh ekrani uchun holat boshqaruvchi.
class OmborProvider extends ChangeNotifier with ClearableProvider {
  final OmborService _service = OmborService();

  Map<String, List<OmborProduct>> productsByCategory = {};
  // GET /api/categories dan kelgan ro'yxat (rasm + server tartibi).
  List<OmborCategory> allCategories = [];
  bool isLoading = false;
  String? errorMessage;

  List<String> get categories => productsByCategory.keys.toList();

  // ─────────────────────── Ombor skladlari ───────────────────────
  // SharedPreferences'dagi 'user' JSON dan bir marta o'qiladi. Kartochkadagi
  // «Qoldiq» qatori va «Kam qolganlar» sahifasi shu skladlar bo'yicha ishlaydi.
  List<int> skladIds = [];
  bool _skladsLoaded = false;

  // Birinchi (asosiy) sklad — kartochkada qoldiq shu sklad bo'yicha ko'rinadi.
  int? get primarySkladId => skladIds.isEmpty ? null : skladIds.first;

  Future<void> ensureSklads() async {
    if (_skladsLoaded) return;
    _skladsLoaded = true;
    skladIds = await loadUserSklads();
    notifyListeners();
  }

  // Admin paneldagi kabi ko'rsatiladigan kategoriyalar: server tartibida,
  // faqat bozor mahsuloti borlari. /api/categories da topilmagan guruh
  // nomlari ham yo'qolmasligi uchun oxiriga (rasmsiz) qo'shiladi.
  List<OmborCategory> get orderedCategories {
    final result = <OmborCategory>[];
    final seen = <String>{};
    for (final c in allCategories) {
      if (productsByCategory.containsKey(c.name)) {
        result.add(c);
        seen.add(c.name);
      }
    }
    for (final name in productsByCategory.keys) {
      if (!seen.contains(name)) {
        result.add(OmborCategory(id: 0, name: name));
      }
    }
    return result;
  }

  // Kategoriya ichidagi mahsulotlar soni (ro'yxat subtitle uchun).
  int productCount(String categoryName) =>
      productsByCategory[categoryName]?.length ?? 0;

  // Mahsulotni id bo'yicha topish (savat submit'da type kerak).
  OmborProduct? findProductById(int productId) {
    for (final products in productsByCategory.values) {
      for (final p in products) {
        if (p.id == productId) return p;
      }
    }
    return null;
  }

  // Qidiruv uchun barcha mahsulotlar (kategoriya nomi bilan birga).
  List<MapEntry<String, OmborProduct>> get allProductsWithCategory {
    final result = <MapEntry<String, OmborProduct>>[];
    productsByCategory.forEach((category, products) {
      for (final p in products) {
        result.add(MapEntry(category, p));
      }
    });
    return result;
  }

  // ─────────────────────── Savatcha holati ───────────────────────
  // (product_id, manba) -> miqdor * 1000 ("milli-birlik", BUTUN son). Float
  // emas: 0.4 -> 400; 400+400+400 = 1200 -> 1.2 (float xatosi yo'q).
  // Ko'rsatishda va yuborishda /1000 qilinadi. Bitta manbali mahsulot —
  // bitta qator (o'sha yagona manba bilan), ko'p manbali — har manbaga
  // alohida qator.
  final Map<OmborCartKey, int> _cart = {};

  Map<OmborCartKey, int> get cart => Map.unmodifiable(_cart);

  // Savatdagi qatorlar soni (mahsulot × manba — har biri alohida item).
  int get cartItemCount => _cart.length;

  // Savatdagi umumiy miqdor (milli-birlik yig'indisi; ko'rsatishda /1000).
  int get cartTotalMilli => _cart.values.fold(0, (sum, c) => sum + c);

  bool isSubmitting = false;

  // Mahsulotning shu manbadagi miqdori milli-birlikda (0 = savatda yo'q).
  int countMilli(int productId, String source) =>
      _cart[(productId: productId, source: source)] ?? 0;

  // Bir qadam (stepMilli = bozor gramm * 1000) qo'shish.
  void addToCart(int productId, String source, int stepMilli) {
    final key = (productId: productId, source: source);
    _cart[key] = (_cart[key] ?? 0) + stepMilli;
    notifyListeners();
  }

  // Bir qadam kamaytirish; 0 ga tushsa savatdan olib tashlanadi.
  void decrement(int productId, String source, int stepMilli) {
    final key = (productId: productId, source: source);
    final next = (_cart[key] ?? 0) - stepMilli;
    if (next <= 0) {
      _cart.remove(key);
    } else {
      _cart[key] = next;
    }
    notifyListeners();
  }

  // Miqdorni to'g'ridan-to'g'ri o'rnatish (qo'lda kiritilganda).
  // 0 yoki manfiy bo'lsa savatdan olib tashlanadi.
  void setCountMilli(int productId, String source, int milli) {
    final key = (productId: productId, source: source);
    if (milli <= 0) {
      _cart.remove(key);
    } else {
      _cart[key] = milli;
    }
    notifyListeners();
  }

  // Katalog yangilanganda: savatdagi qator manbasi mahsulotda endi YO'Q
  // bo'lsa (admin manbani o'zgartirgan) — miqdor mahsulotning asosiy
  // manbasiga ko'chiriladi (u yerda bor bo'lsa qo'shiladi). Aks holda qator
  // kartochkada ko'rinmay qolib, yuborishda server uni rad etardi.
  // Katalogdan butunlay chiqib ketgan mahsulot qatoriga tegilmaydi.
  void _reconcileCartSources() {
    if (_cart.isEmpty) return;
    final moved = <OmborCartKey, int>{};
    _cart.removeWhere((key, milli) {
      final product = findProductById(key.productId);
      if (product == null || product.sources.contains(key.source)) {
        return false;
      }
      final to = (productId: key.productId, source: product.primarySource);
      moved[to] = (moved[to] ?? 0) + milli;
      return true;
    });
    moved.forEach((key, milli) => _cart[key] = (_cart[key] ?? 0) + milli);
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  Future<void> fetchProducts() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Mahsulotlar va kategoriyalar parallel yuklanadi. Kategoriyalar
      // faqat rasm/tartib uchun — xatosi asosiy ro'yxatni to'xtatmaydi.
      final productsFuture = _service.fetchProducts();
      try {
        allCategories = await _service.fetchCategories();
      } catch (_) {
        allCategories = [];
      }
      productsByCategory = await productsFuture;
      _reconcileCartSources();
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────── Mening buyurtmalarim ───────────────────────
  // Buyurtmalar YAGONA qoida bo'yicha tartiblanadi (created ASC, keyin id) —
  // yuk keltiruvchi va bugalter ekranlaridagi bilan bir xil ketma-ketlik.
  // Sabab va qoida: core/utils/order_sequence.dart.
  static void _sortOrders(List<OmborOrder> list) =>
      sortOrderSeq(list, createdOf: (o) => o.created, idOf: (o) => o.id);

  List<OmborOrder> myOrders = [];
  bool isLoadingOrders = false;
  String? ordersError;

  // Yopiq buyurtmalar tarixi oynasi (30/90 kun yoki hammasi).
  // Saqlanmaydi — ilova qayta ochilganda default 30 kunga qaytadi.
  OrderPeriod ordersPeriod = OrderPeriod.last30;

  // Hozir qabul qilinayotgan item (order id + product id) — qator tugmasida
  // spinner ko'rsatish uchun.
  int? acceptingItemOrderId;
  int? acceptingItemProductId;

  // Hozir o'chirilayotgan item (order id + product id) — qatordagi o'chirish
  // ikonkasida spinner ko'rsatish uchun.
  int? deletingItemOrderId;
  int? deletingItemProductId;

  // GET /api/orders -> ombor userning o'z buyurtmalari.
  // Ro'yxat yaratilgan vaqti bo'yicha o'sish tartibida ([_sortOrders]) —
  // omborchi savatga qo'shgan ketma-ketlik saqlanadi va yuk keltiruvchi
  // ekrani bilan bir xil bo'ladi.
  //
  // Bir vaqtda ikkita so'rov ketmasligi uchun yengil guard: bosh ekran ham,
  // «Buyurtmalarim» tabи ham ochilishida chaqiradi — parallel javoblar bir
  // birini eskisi bilan almashtirib qo'ymasin.
  // MUHIM: `active: true` — javobda faqat HALI QABUL QILINMAGAN buyurtmalar
  // keladi. Ilgari 30 kunlik butun tarix (asosan qabul qilingan buyurtmalar,
  // har biri o'nlab itemi bilan) yuklanardi va «Buyurtmalarim» ekrani
  // ularning ~hammasini tashlab yuborardi — shuning uchun ekran uzoq
  // ochilardi. Tarix endi kun bo'yicha alohida so'raladi
  // ([fetchHistoryOrders]), shuning uchun bu ro'yxatga umuman kerak emas.
  Future<void> fetchMyOrders() async {
    if (isLoadingOrders) return;
    isLoadingOrders = true;
    ordersError = null;
    notifyListeners();

    try {
      final orders = await _service.fetchMyOrders(
        days: ordersPeriod.days,
        all: ordersPeriod.isAll,
        activeOnly: true,
      );
      _sortOrders(orders);
      myOrders = orders;
    } catch (e) {
      ordersError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      isLoadingOrders = false;
      notifyListeners();
    }
  }

  // Davr almashtirilganda ro'yxat serverdan qayta yuklanadi.
  Future<void> setOrdersPeriod(OrderPeriod period) async {
    if (period == ordersPeriod) return;
    ordersPeriod = period;
    notifyListeners();
    await fetchMyOrders();
  }

  // ───────────────── Qabul qilinganlar tarixi (kun bo'yicha) ─────────────────
  //
  // Tarix ekrani BIR kunni ko'rsatadi, shuning uchun butun oyna emas, aynan
  // o'sha kun so'raladi (GET /api/orders?date=YYYY-MM-DD). Ro'yxat myOrders'dan
  // ALOHIDA turadi: bosh ekrandagi aktiv buyurtmalar keshi tarix bilan
  // shishmaydi va tarixdan chiqilganda o'zi bo'shatiladi.
  List<OmborOrder> historyOrders = [];
  bool isLoadingHistory = false;
  String? historyError;

  // Hozir ko'rsatilayotgan kun ("YYYY-MM-DD") — socket hodisasi shu kunga
  // tegishlimi yoki yo'qmi shundan aniqlanadi.
  String? historyDateKey;

  static String dateKeyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> fetchHistoryOrders(DateTime day) async {
    final key = dateKeyOf(day);
    historyDateKey = key;
    isLoadingHistory = true;
    historyError = null;
    notifyListeners();

    try {
      final orders = await _service.fetchMyOrders(date: key);
      // Kun almashtirilib ulgurilgan bo'lsa eskirgan javobni yozmaymiz.
      if (historyDateKey != key) return;
      _sortOrders(orders);
      historyOrders = orders;
    } catch (e) {
      if (historyDateKey != key) return;
      historyError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (historyDateKey == key) {
        isLoadingHistory = false;
      }
      notifyListeners();
    }
  }

  // Tarix ekranidan chiqilganda keshni bo'shatamiz — bu ro'yxat boshqa hech
  // qayerda ishlatilmaydi, xotirada turishining ma'nosi yo'q.
  void clearHistoryOrders() {
    if (historyOrders.isEmpty && historyDateKey == null) return;
    historyOrders = [];
    historyDateKey = null;
    historyError = null;
    isLoadingHistory = false;
    notifyListeners();
  }

  // Shu mahsulotga BUYURTMA BERILGAN, lekin HALI KELMAGAN miqdor.
  // Kartochkadagi «Buyurtma: X кг» yozuvi uchun — ombor «Kam qolganlar»
  // sahifasidan bir narsani ikki marta buyurtma qilib yubormasligi kerak.
  //
  // Faqat quyidagi itemlar qo'shiladi:
  //  - !accepted — qabul qilingan item allaqachon sklad qoldig'iga kirim
  //    qilingan (backend: stockKirimOnAccept), ya'ni «Qoldiq» ichida
  //    sanalgan. Uni bu yerda ham sanasak — ikki marta hisoblangan bo'lardi.
  //    Aynan item'ning O'Z accepted bayrog'i (order statusi emas) ikki sonni
  //    bir-biridan ajratib turadi: qisman qabul qilingan buyurtmada kelgan
  //    itemlar «Qoldiq»da, kelmaganlari esa shu yerda.
  //  - !deleted — o'chirilgan item umuman kelmaydi.
  //  - itemType == '' — faqat katalog mahsuloti ('rasxod'/'proche' emas).
  //
  // Qiymat gramm kontraktida (кг/л -> butun гр/мл) — ko'rsatishda formatQty.
  // Berilgan, lekin hali kelmagan miqdor — O(1).
  //
  // Ilgari bu metod har chaqiruvda BARCHA buyurtmalar × ularning itemlari
  // bo'ylab yurardi. Har mahsulot kartochkasi uni har build'da chaqiradi, ya'ni
  // grid'dagi N ta kartochka × (buyurtmalar × itemlar) — bitta «+» bosilganda
  // ham o'n minglab takrorlanish. Endi indeks bir marta yasalib keshlanadi.
  //
  // Kesh HAR notifyListeners'da bekor qilinadi, shuning uchun myOrders qanday
  // o'zgarmasin (fetch, socket, accept, delete) eskirib qola olmaydi — UI
  // faqat notifyListeners'dan keyin qayta chiziladi.
  Map<int, double>? _orderedIndex;

  @override
  void notifyListeners() {
    _orderedIndex = null;
    super.notifyListeners();
  }

  double orderedQty(int productId) {
    var idx = _orderedIndex;
    if (idx == null) {
      idx = <int, double>{};
      for (final order in myOrders) {
        for (final item in order.items) {
          if (item.accepted || item.deleted) continue;
          if (item.itemType.isNotEmpty) continue;
          idx[item.productId] = (idx[item.productId] ?? 0) + item.count;
        }
      }
      _orderedIndex = idx;
    }
    return idx[productId] ?? 0;
  }

  // Savatdagi mahsulotlardan buyurtma yuborish.
  // Muvaffaqiyatda savatni tozalaydi va backend message'ini qaytaradi.
  // Xato bo'lsa Exception otadi (UI uni ushlab SnackBar ko'rsatadi).
  Future<String> submitOrder() async {
    // Qayta yuborishni bloklash: tugma tez ikki marta bosilsa ham (UI guard
    // build vaqtida ishlaydi) ikkita bir xil buyurtma yaratilmasin.
    if (isSubmitting) return '';
    if (_cart.isEmpty) {
      throw Exception('Savat bo\'sh');
    }

    isSubmitting = true;
    notifyListeners();

    try {
      // API kontrakt: кг/л mahsulotda count — BUTUN gramm/ml. Savat milli
      // birlikda saqlanadi (kg×1000 == gramm), shuning uchun qiymat
      // o'zgarishsiz yuboriladi. Boshqa birliklar: /1000 (eski semantika).
      // Har savat qatori — alohida item, source bilan: bitta product_id
      // turli manbalar bilan bir necha marta kelishi mumkin (backend har
      // manbani o'z bozorchisiga alohida buyurtma qiladi).
      final items = _cart.entries.map((e) {
        final productId = e.key.productId;
        final type = findProductById(productId)?.type;
        final num count;
        if (qtyUnitFactor(type) == 1000) {
          count = e.value; // milli == gramm/ml, butun son
        } else {
          final v = e.value / 1000.0;
          count = v % 1 == 0 ? v.toInt() : v;
        }
        return {
          'product_id': productId,
          'count': count,
          'source': e.key.source,
        };
      }).toList();
      final message = await _service.submitOrder(items);
      _cart.clear();
      return message;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  // Bitta mahsulotni qabul qilish: kelgan soni + rasm/video (kamida bittasi).
  // Muvaffaqiyatda backend qaytargan TO'LIQ yangilangan order myOrders'da
  // id bo'yicha almashtiriladi (qayta GET shart emas). Xato bo'lsa
  // Exception otadi (UI uni ushlab SnackBar ko'rsatadi).
  Future<void> acceptOrderItem(
    int orderId,
    int productId,
    double received,
    String? imagePath,
    String? videoPath,
  ) async {
    acceptingItemOrderId = orderId;
    acceptingItemProductId = productId;
    notifyListeners();
    try {
      final updated = await _service.acceptOrderItem(
        orderId,
        productId,
        received,
        imagePath,
        videoPath,
      );
      // Oxirgi item qabul qilinganda buyurtma "qabul_qilindi" bo'ladi va
      // applyOrderUpdate uni aktivlar keshidan chiqarib tashlaydi.
      applyOrderUpdate(updated);
    } finally {
      acceptingItemOrderId = null;
      acceptingItemProductId = null;
      notifyListeners();
    }
  }

  // Bitta mahsulotni buyurtmadan o'chirish (soft-delete). Muvaffaqiyatda
  // backend qaytargan TO'LIQ yangilangan order myOrders'da id bo'yicha
  // almashtiriladi (qayta GET shart emas). Xato bo'lsa Exception otadi
  // (UI uni ushlab SnackBar ko'rsatadi).
  Future<void> deleteOrderItem(int orderId, int productId) async {
    deletingItemOrderId = orderId;
    deletingItemProductId = productId;
    notifyListeners();
    try {
      final updated = await _service.deleteOrderItem(orderId, productId);
      // Qolgan itemlar allaqachon qabul qilingan bo'lsa, o'chirish buyurtmani
      // "qabul_qilindi" holatiga o'tkazishi mumkin — applyOrderUpdate uni
      // aktivlar keshidan chiqaradi.
      applyOrderUpdate(updated);
    } finally {
      deletingItemOrderId = null;
      deletingItemProductId = null;
      notifyListeners();
    }
  }

  // ─────────────────────── Real-time (WebSocket) ───────────────────────
  StreamSubscription<OrderSocketEvent>? _socketSub;

  // WebSocket'ga ulanib, buyurtma hodisalarini tinglaymiz. fetchMyOrders bilan
  // birga ishlaydi (u boshlang'ich sync, bu — real-time yangilanish).
  void connectSocket() {
    // connect/disconnect juftligi _socketSub orqali balanslanadi —
    // OrderSocket ref-count to'g'ri ishlashi uchun (qarang: order_socket.dart).
    if (_socketSub != null) return;
    _socketSub = OrderSocket.instance.events.listen(_onSocketEvent);
    OrderSocket.instance.connect();
  }

  // Ekrandan chiqqanda yoki logout'da ulanishni uzamiz.
  void disconnectSocket() {
    if (_socketSub == null) return;
    _socketSub!.cancel();
    _socketSub = null;
    OrderSocket.instance.disconnect();
  }

  // Kelgan hodisani myOrders'ga qo'llash: deleted -> o'chir, aks holda upsert.
  void _onSocketEvent(OrderSocketEvent event) {
    final id = event.order['id'];
    final orderId = (id is int) ? id : int.tryParse(id?.toString() ?? '');
    if (orderId == null) return;

    if (event.action == 'deleted') {
      myOrders.removeWhere((o) => o.id == orderId);
      historyOrders.removeWhere((o) => o.id == orderId);
      notifyListeners();
      return;
    }

    applyOrderUpdate(OmborOrder.fromJson(event.order));
  }

  // Yangilangan buyurtmani ikkala keshga (aktivlar + ochiq turgan tarix kuni)
  // qo'llaydi. Socket hodisasi ham, accept/delete javobi ham shu yerdan o'tadi.
  //
  // QABUL QILINGAN buyurtma myOrders'dan CHIQARIB TASHLANADI: u endi
  // «Buyurtmalarim» ekranida ko'rinmaydi (ekran allaqachon uni filtrlab
  // tashlardi), demak xotirada ushlab turishning ma'nosi yo'q. Shu bilan
  // ekran ochiq turgan kun davomida kesh o'sib ketmaydi.
  void applyOrderUpdate(OmborOrder order) {
    if (order.isAccepted) {
      myOrders.removeWhere((o) => o.id == order.id);
    } else {
      final index = myOrders.indexWhere((o) => o.id == order.id);
      if (index >= 0) {
        myOrders[index] = order; // bor bo'lsa almashtir
      } else {
        myOrders.add(order); // yo'q bo'lsa qo'sh
      }
      // Yagona ketma-ketlik (created ASC, keyin id) qayta tiklanadi.
      _sortOrders(myOrders);
    }

    // Tarix ekrani ochiq va buyurtma o'sha kunga tegishli bo'lsa — u yerda ham
    // yangilaymiz (qabul qilingani endi aynan shu ro'yxatda ko'rinishi kerak).
    final key = historyDateKey;
    if (key != null &&
        order.created.length >= 10 &&
        order.created.substring(0, 10) == key) {
      final hIndex = historyOrders.indexWhere((o) => o.id == order.id);
      if (hIndex >= 0) {
        historyOrders[hIndex] = order;
      } else {
        historyOrders.add(order);
        _sortOrders(historyOrders);
      }
    }

    notifyListeners();
  }

  // Logout: socketni uzib, katalog/savat/buyurtma va holat maydonlarini
  // boshlang'ich holatga qaytaramiz.
  @override
  void clear() {
    disconnectSocket();
    productsByCategory = {};
    allCategories = [];
    isLoading = false;
    errorMessage = null;
    skladIds = [];
    _skladsLoaded = false;
    _cart.clear();
    isSubmitting = false;
    myOrders = [];
    isLoadingOrders = false;
    ordersError = null;
    ordersPeriod = OrderPeriod.last30;
    historyOrders = [];
    isLoadingHistory = false;
    historyError = null;
    historyDateKey = null;
    acceptingItemOrderId = null;
    acceptingItemProductId = null;
    deletingItemOrderId = null;
    deletingItemProductId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnectSocket();
    super.dispose();
  }
}
