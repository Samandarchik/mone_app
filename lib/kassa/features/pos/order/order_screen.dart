import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/services/local_db.dart';
import '../../../core/services/app_state.dart';
import '../../../core/services/ui_prefs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/payment_label.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/search_fold.dart';
import '../../../core/widgets/media_image.dart';
import '../../../core/widgets/other_payment_comment_dialog.dart';

class OrderScreen extends StatefulWidget {
  final String? tableSKU;
  final String tableLabel;
  final Map<String, dynamic>? order;
  final String orderType;

  /// Chrome uslubidagi tab rejimi: bir vaqtda bir nechta stol ochiq
  /// turadi. Host (OrderTabsScreen) tab qatorini boshqaradi; null bo'lsa
  /// ekran eski, yakka rejimda ishlaydi.
  final OrderTabsController? tabsHost;

  const OrderScreen({
    super.key,
    this.tableSKU,
    required this.tableLabel,
    this.order,
    this.orderType = 'dine_in',
    this.tabsHost,
  });

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Map<String, dynamic>? _menu;
  int _selectedCatIndex = 0;
  final _catPageController = PageController();
  // Menyu qidiruvi
  final _searchCtrl = TextEditingController();
  String _search = '';
  final List<Map<String, dynamic>> _cart = [];
  final ValueNotifier<int> _cartVersion = ValueNotifier<int>(0);
  final List<Map<String, dynamic>> _cancelCart = [];
  // Chekbay ko'rinishda hamma chek ochiq turadi; bu yerda faqat
  // foydalanuvchi qo'lda yopgan cheklar (order_number) saqlanadi
  final Set<String> _collapsedChecks = {};
  List<dynamic> _checks = [];
  int _grandTotal = 0;
  bool _loading = true;
  bool _sending = false;
  bool _cancelling = false;
  bool _closing = false;
  bool _printing = false;
  StreamSubscription? _wssSub;

  void _bumpCart() => _cartVersion.value = _cartVersion.value + 1;

  @override
  void initState() {
    super.initState();
    if (widget.order != null) {
      _checks = [widget.order!];
      _grandTotal = widget.order!['total'] as int? ?? 0;
    }
    final cachedCats = AppState().cachedCategories;
    final cachedProds = AppState().cachedProducts;
    if (cachedCats != null && cachedProds != null && cachedCats.isNotEmpty) {
      _menu = {'categories': cachedCats, 'products': cachedProds};
      _loading = false;
    }
    _loadMenu();
    _loadTable();
    _wssSub = WssService().eventStream.listen(_onEvent);
    AppState().addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stol raqami almashtirilganda (tab boshqa stolga o'tkazilganda)
    // cheklar yangi stoldan qayta yuklanadi; savat esa saqlanib qoladi
    if (oldWidget.tableSKU != widget.tableSKU) {
      setState(() {
        _checks = [];
        _grandTotal = 0;
      });
      _loadTable();
    }
  }

  @override
  void dispose() {
    AppState().removeListener(_onAppStateChanged);
    _wssSub?.cancel();
    _catPageController.dispose();
    _searchCtrl.dispose();
    _cartVersion.dispose();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['event'] == 'order:items_added' ||
        e['event'] == 'order:new' ||
        e['event'] == 'order:updated') {
      _loadTable();
    }
  }

  Future<void> _loadMenu() async {
    try {
      // Nofaollar ham yuklanadi — ko'rsatishda rolga qarab filtrlanadi
      // (qarang: _showInactive).
      final cats = await LocalDB().getCategories(includeInactive: true);
      final prods = await LocalDB().getProducts(includeInactive: true);
      if (cats.isEmpty) {
        final m = await ApiService().getMenu(
          force: true,
          includeInactive: true,
        );
        final fetchedCats = m['categories'] as List<dynamic>? ?? [];
        final fetchedProds = m['products'] as List<dynamic>? ?? [];
        await LocalDB().saveCategories(fetchedCats);
        await LocalDB().saveProducts(fetchedProds);
        AppState().setMenuCache(
          fetchedCats.cast<Map<String, dynamic>>(),
          fetchedProds.cast<Map<String, dynamic>>(),
        );
        if (mounted) {
          setState(() {
            _menu = m;
            _loading = false;
          });
        }
      } else {
        AppState().setMenuCache(cats, prods);
        if (mounted) {
          setState(() {
            _menu = {'categories': cats, 'products': prods};
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTable() async {
    if (widget.tableSKU != null) {
      try {
        final t = await ApiService().getTable(widget.tableSKU!);
        if (mounted) {
          setState(() {
            _checks = (t['checks'] as List<dynamic>?) ?? [];
            _grandTotal = t['grand_total'] as int? ?? 0;
          });
        }
      } catch (_) {}
    } else if (widget.order != null) {
      try {
        final orderNum = widget.order!['order_number'] as String?;
        if (orderNum == null) return;
        final orders = await ApiService().getOrders();
        final updated = orders
            .where((o) => o['order_number'] == orderNum)
            .toList();
        if (mounted && updated.isNotEmpty) {
          setState(() {
            _checks = updated;
            _grandTotal = updated.first['total'] as int? ?? 0;
          });
        }
      } catch (_) {}
    }
  }

  /// Nofaol mahsulot/kategoriyalar faqat super_admin va kassirga ko'rinadi.
  bool get _showInactive => AppState().canSeeInactiveMenu;

  List<dynamic> get _categories {
    final cats = _menu?['categories'] as List<dynamic>? ?? [];
    if (_showInactive) return cats;
    return cats.where((c) => (c['status'] ?? 'active') == 'active').toList();
  }

  /// Qoldig'i 0 mahsulot sotuvda KO'RINMAYDI — pishirilib ("Tayyor") yoki
  /// Ombor orqali bazaga qo'shilgandagina ro'yxatga chiqadi.
  ///
  /// Nofaol mahsulot esa super_admin/kassirga qoldiqdan QAT'I NAZAR
  /// ko'rinadi (kulrang, «Nofaol» belgisi bilan) — aks holda uni menyudan
  /// umuman topib bo'lmasdi. Boshqa rollarga chiqmaydi.
  List<dynamic> get _stockedProducts {
    final menuProducts = _menu?['products'] as List<dynamic>? ?? [];
    return menuProducts.where((p) {
      if ((p['status'] ?? 'active') != 'active') return _showInactive;
      // Yumshoq (test) rejimda qoldiqsiz mahsulot ham ko'rinadi va sotiladi.
      if (AppState().stockSoft) return true;
      final c = AppState().getStockCount(p['id']);
      // Qoldiq qatori yo'q (null) = kuzatilmaydi, cheksiz — server ham shunday
      // (ReserveStock). Mone rejimida retseptli mahsulotlarda qator bo'lmaydi.
      return c == null || c > 0;
    }).toList();
  }

  List<List<dynamic>> get _catPages {
    final all = _stockedProducts;
    // Kategoriya bo'lmasa (yoki menyu hali yuklanmagan) — bitta umumiy sahifa
    if (_categories.isEmpty) return [all];
    return [
      for (final c in _categories)
        all.where((p) => p['category_id'] == c['id']).toList(),
    ];
  }

  void _addToCart(Map<String, dynamic> product) {
    // Nofaol mahsulot sotilmaydi — server ham rad etadi (status='active'
    // sharti bilan qidiradi). Kartochka faqat ko'rish uchun turadi.
    if ((product['status'] ?? 'active') != 'active') {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${menuName(product['name'])}: nofaol mahsulot — sotib bo\'lmaydi. Admin menyusidan faollashtiring.',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    final stockCount = AppState().getStockCount(product['id']);
    final existing = _cart.indexWhere((c) => c['product_id'] == product['id']);
    final currentInCart = existing >= 0
        ? (_cart[existing]['quantity'] as int)
        : 0;

    if (!AppState().stockSoft &&
        stockCount != null &&
        (currentInCart + 1) > stockCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${menuName(product['name'])}: faqat $stockCount ta qolgan',
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (existing >= 0) {
      _cart[existing]['quantity'] = currentInCart + 1;
    } else {
      _cart.add({
        'product_id': product['id'],
        'name': menuName(product['name']),
        'price': product['price'],
        'quantity': 1,
        'note': null,
      });
    }
    _bumpCart();
  }

  /// Yuborilgan chek qatoriga bosilganda shu mahsulot savatga QAYTA
  /// qo'shiladi — kassir menyudan boshqatdan qidirib o'tirmaydi.
  /// Qoldiq tekshiruvi `_addToCart`ning o'zida.
  void _reAddFromCheck(int productId) {
    final products = _menu?['products'] as List<dynamic>? ?? [];
    for (final p in products) {
      if (p['id'] == productId) {
        _addToCart((p as Map).cast<String, dynamic>());
        return;
      }
    }
  }

  /// Savatdagi qatorni bittaga oshirish — «+» tugmasi uchun.
  /// Qoldiqdan oshib ketmasin: menyudagi bosishda ham xuddi shu tekshiruv.
  /// `true` — oshdi, `false` — qoldiq yetmadi.
  bool _incrementCartLine(Map<String, dynamic> c) {
    final stock = AppState().getStockCount(c['product_id']);
    final q = c['quantity'] as int? ?? 0;
    if (!AppState().stockSoft && stock != null && q + 1 > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${c['name']}: faqat $stock ta qolgan'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
      return false;
    }
    c['quantity'] = q + 1;
    _bumpCart();
    return true;
  }

  int get _cartTotal => _cart.fold(
    0,
    (sum, item) => sum + (item['price'] as int) * (item['quantity'] as int),
  );
  int get _cartCount =>
      _cart.fold(0, (sum, item) => sum + (item['quantity'] as int));

  /// Chek maydonini xavfsiz o'qish. JSON soni int ham, double ham bo'lishi
  /// mumkin — ilgari `as int?` ishlatilgan va double kelganda ekran
  /// TypeError bilan yiqilardi.
  int _checkField(dynamic c, String key) {
    final v = (c as Map)[key];
    return v is num ? v.toInt() : 0;
  }

  Iterable<dynamic> get _liveChecks =>
      _checks.where((c) => (c as Map)['status'] != 'cancelled');

  int get _grandSubtotal =>
      _liveChecks.fold<int>(0, (sum, c) => sum + _checkField(c, 'subtotal'));

  int get _grandServiceFee =>
      _liveChecks.fold<int>(0, (sum, c) => sum + _checkField(c, 'service_fee'));

  /// Yetkazib berish haqi — dostafka cheklarida bo'ladi.
  int get _grandDeliveryFee => _liveChecks.fold<int>(
    0,
    (sum, c) => sum + _checkField(c, 'delivery_fee'),
  );

  /// Chekda allaqachon qo'llangan chegirma (promo-kod va h.k.).
  int get _grandDiscount =>
      _liveChecks.fold<int>(0, (sum, c) => sum + _checkField(c, 'discount'));

  /// Server undiradigan HAQIQIY summa.
  ///
  /// MUHIM: server `SUM(orders.total)` ni oladi, `total` esa
  /// `subtotal + service_fee + delivery_fee - discount`. Xizmat haqi olib
  /// tashlangan — yangi cheklarda `service_fee` doim 0, lekin fee bilan
  /// yozilgan ESKI ochiq cheklarda u jamiga kirishi shart, aks holda
  /// aralash to'lovda server "payments_mismatch" qaytaradi.
  int _payableTotal() {
    final total =
        _grandSubtotal + _grandServiceFee + _grandDeliveryFee - _grandDiscount;
    return total < 0 ? 0 : total;
  }

  /// Mahsulot kartochkasining rasm qismi.
  ///
  /// Rasm YO'Q bo'lsa (ko'p restoranda menyuning katta qismi shunday)
  /// ilgari bu yerda bir xil kulrang "vilka" ikonkasi turardi: butun grid
  /// bir-biriga o'xshash bo'sh kulrang to'rtburchakka aylanardi va kassir
  /// mahsulotni faqat ostidagi mayda yozuvdan ajratardi. Endi rasm
  /// o'rnida mahsulot nomining bosh harfi rangli plitkada chiqadi —
  /// ranglar nom bo'yicha barqaror, ya'ni bir mahsulot doim bir xil
  /// rangda bo'ladi va ko'z bilan tez topiladi.
  Widget _productMedia(
    Map<String, dynamic> p,
    bool soldOut,
    int? stockCount, {
    bool inactive = false,
  }) {
    final media = p['media'] as List<dynamic>? ?? [];
    final imageUrl = media.isNotEmpty ? (media[0]['url'] as String?) : null;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final name = menuName(p['name']);
    final tint = _productTint(name);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasImage ? AppColors.surfaceAlt : tint.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            MediaImage(path: imageUrl)
          else
            Center(
              child: LayoutBuilder(
                builder: (ctx, c) => Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: c.maxHeight * 0.52,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: tint.withValues(alpha: 0.55),
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
          if (inactive)
            Container(
              color: Colors.black.withValues(alpha: 0.30),
              child: const Center(
                child: Text(
                  'Nofaol',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else if (soldOut)
            Container(
              color: AppColors.danger.withValues(alpha: 0.15),
              child: const Center(
                child: Text(
                  'Tugadi',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            )
          else if (stockCount != null)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.text.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '$stockCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Nom bo'yicha barqaror rang (bir mahsulot — doim bir rang)
  static const _tints = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.info,
    AppColors.accent,
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
  ];

  Color _productTint(String name) {
    if (name.isEmpty) return AppColors.primary;
    var h = 0;
    for (final code in name.codeUnits) {
      h = (h * 31 + code) & 0x7FFFFFFF;
    }
    return _tints[h % _tints.length];
  }

  // ============================================================
  // Cart bottom sheet (full)
  // ============================================================

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return Container(
            // Balandlik SAVAT HAJMIGA qarab: ilgari doim ekranning 85% ini
            // egallardi — ikki qatorli savat uchun ham yarim ekran bo'sh
            // oq maydon ochilar, kassir uni "yuklanmadi" deb o'ylardi.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.xxl),
                topRight: Radius.circular(AppRadius.xxl),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHandle(),
                // header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_rounded,
                          color: AppColors.success,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Yangi chek',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // `Flexible` + `shrinkWrap`: ro'yxat o'z bo'yiga qarab
                // joylashadi, ko'paysa maksimal balandlikda aylanadi
                Flexible(
                  child: _cart.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: EmptyState(
                            icon: Icons.shopping_cart_outlined,
                            title: 'Savatcha bo\'sh',
                            subtitle: 'Mahsulot qo\'shing',
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          itemCount: _cart.length,
                          itemBuilder: (ctx, i) {
                            final c = _cart[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _CartTile(
                                item: c,
                                onDecrement: () {
                                  if ((c['quantity'] as int) > 1) {
                                    c['quantity'] = c['quantity'] - 1;
                                  } else {
                                    _cart.removeAt(i);
                                  }
                                  _bumpCart();
                                  setS(() {});
                                },
                                onIncrement: () {
                                  if (_incrementCartLine(c)) setS(() {});
                                },
                                onRemove: () {
                                  _cart.removeAt(i);
                                  _bumpCart();
                                  setS(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
                if (_cart.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Jami',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Text(
                              formatMoney(_cartTotal, suffix: ' so\'m'),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _sending
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    await _confirmAndSubmit();
                                  },
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                              _sending ? 'Yuborilmoqda...' : 'Yuborish',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // Checks bottom sheet (full) — view items, cancel, pay, print
  // ============================================================

  void _openChecksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            void rebuild() => setS(() {});
            return Container(
              // Chek soniga qarab — bitta chek uchun butun ekranni
              // egallamaydi (qarang: `_openCartSheet`)
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.xxl),
                  topRight: Radius.circular(AppRadius.xxl),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Cheklar (${_checks.length})',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                            Text(
                              'Jami $_checksItemCount ta mahsulot',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      children: _buildChecksDetail(rebuild),
                    ),
                  ),
                  if (_cancelCart.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: _buildCancelCart(rebuild),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Column(
                      children: [
                        // Mahsulotlar/Jami qatorlari olib tashlangan —
                        // umumiy summa tepadagi panelda ko'rinib turadi
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: _cancelCart.isNotEmpty
                                      ? null
                                      : _printReceipt,
                                  icon: const Icon(
                                    Icons.print_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Chek',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 50,
                                child: FilledButton.icon(
                                  onPressed: _cancelCart.isNotEmpty
                                      ? null
                                      : () async {
                                          Navigator.pop(ctx);
                                          await _closeOrder();
                                        },
                                  icon: const Icon(
                                    Icons.payments_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'To\'lovni yopish',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // Submit / Close / Cancel / Print
  // ============================================================

  Future<void> _confirmAndSubmit() async {
    if (_cart.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yuborilsinmi?'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._cart.map(
                (c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${c['name']} x${c['quantity']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        formatMoney(
                          (c['price'] as int) * (c['quantity'] as int),
                          suffix: ' so\'m',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Jami',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    formatMoney(_cartTotal, suffix: ' so\'m'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _submitOrder();
  }

  /// Savatni serverga yuboradi. `exitAfter: false` bo'lsa ekran ochiq
  /// qoladi va cheklar qayta yuklanadi (Chek/To'lov oldidan yuborish).
  /// Muvaffaqiyatli yuborilsa `true` qaytaradi.
  Future<bool> _submitOrder({bool exitAfter = true}) async {
    if (_cart.isEmpty) return false;
    setState(() => _sending = true);

    final items = _cart
        .map(
          (c) => {
            'product_id': c['product_id'],
            'quantity': c['quantity'],
            'note': c['note'],
          },
        )
        .toList();

    String? createdOrderNumber;
    try {
      final res = await ApiService().createOrder({
        'type': widget.orderType,
        'table_sku': widget.tableSKU,
        'items': items,
        'note': null,
      });
      createdOrderNumber = res['order_number'] as String?;
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e, fallback: 'Chek yuborilmadi')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return false;
    }

    if (!mounted) return true;

    if (widget.orderType == 'takeaway' && createdOrderNumber != null) {
      ApiService()
          .printReceipt(orderNumber: createdOrderNumber)
          .catchError((_) {});
    }

    _cart.clear();
    if (exitAfter) {
      _exitScreen();
    } else {
      setState(() => _sending = false);
      _bumpCart();
      // Chek/To'lov davom etishidan oldin cheklar (va jami summa)
      // yangi yuborilgan mahsulotlarni o'z ichiga olishi kerak.
      await _loadTable();
    }
    return true;
  }

  /// Chek chiqarish yoki To'lov oldidan savat tekshiruvi. Savatda hali
  /// yuborilmagan mahsulot bo'lsa kassirdan so'raydi: yuborib davom
  /// etish, tashlab yuborish yoki bekor qilish. Davom etish mumkin
  /// bo'lsa `true` qaytaradi.
  ///
  /// Ilgari Chek/To'lov savatni JIMGINA e'tiborsiz qoldirardi: kassir
  /// yangi mahsulot tanlab, Yuborishni unutib to'lovni yopsa, tanlangan
  /// mahsulotlar chekka kirmay qolardi.
  Future<bool> _resolvePendingCart() async {
    if (_cart.isEmpty) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Savatda yuborilmagan mahsulot bor'),
        content: Text(
          '${_cart.length} ta qator hali yuborilmagan. Nima qilamiz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Bekor'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Tashlab yuborish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'send'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'stay') return false;
    if (action == 'send') {
      return _submitOrder(exitAfter: false);
    }
    // Tashlab yuborish — savat tozalanadi, amal davom etadi
    setState(_cart.clear);
    _bumpCart();
    return true;
  }

  /// Ekrandan chiqish: tab rejimida faqat SHU tab yopiladi (boshqa ochiq
  /// stollar joyida qoladi), yakka rejimda butun ekran yopiladi.
  void _exitScreen() {
    final host = widget.tabsHost;
    if (host != null) {
      host.closeTabFor(this);
    } else {
      Navigator.pop(context);
    }
  }

  /// Ekranni yopish. Savatda yozilmagan mahsulot bo'lsa AVVAL so'raladi.
  ///
  /// Ilgari bu tugma savatni jimgina YUBORARDI: kassir mijoz fikridan
  /// qaytgani uchun ortga chiqmoqchi bo'lganda buyurtma oshxonaga ketib,
  /// cheki chiqib bo'lardi. Savatni tashlab yuborishning boshqa yo'li ham
  /// yo'q edi — har bir qatorni qo'lda o'chirish kerak edi.
  Future<void> _handleClose() async {
    if (_sending) return;
    if (_cart.isEmpty) {
      _exitScreen();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Savatda yozilmagan mahsulot bor'),
        content: Text(
          '${_cart.length} ta qator hali yuborilmagan. Nima qilamiz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Qolaman'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Tashlab yuborish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'send'),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'stay') return;
    if (action == 'send') {
      _submitOrder();
      return;
    }
    setState(_cart.clear);
    _bumpCart();
    if (mounted) _exitScreen();
  }

  // ============================================================
  // Stol tanlash paneli — tab qatoridagi «+» bosilganda ochiladi
  // ============================================================

  /// «ZAL-3» → «3»: zona nomi sarlavhada turgani uchun chipda faqat raqam.
  String _shortTableLabel(Map<String, dynamic> t, String zoneName) {
    final label = (t['label'] ?? '').toString().trim();
    if (label.isNotEmpty && zoneName.isNotEmpty) {
      final prefix = '$zoneName-'.toLowerCase();
      if (label.toLowerCase().startsWith(prefix)) {
        final rest = label.substring(prefix.length).trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    if (label.isNotEmpty) return label;
    final number = t['number'];
    if (number is int && number > 0) return '$number';
    return (t['sku'] ?? '').toString();
  }

  /// Barcha zona/stollarni pastdan chiqib keladigan panelda ko'rsatadi.
  ///
  /// Oddiy rejim («+»): tanlangan stol yangi tab sifatida ochiladi
  /// (allaqachon ochiq bo'lsa — o'sha tab faollashadi).
  /// `change: true` (faol tab bosilganda): joriy tabning STOLI almashadi —
  /// yuborilgan cheklar serverda yangi stolga ko'chiriladi, savat saqlanadi.
  Future<void> _openTablePicker({bool change = false}) async {
    List<Map<String, dynamic>> zones;
    final tablesByZone = <int, List<Map<String, dynamic>>>{};
    try {
      zones = await LocalDB().getZones();
      for (final z in zones) {
        final zid = z['id'] as int? ?? 0;
        tablesByZone[zid] = await LocalDB().getTables(zoneId: zid);
      }
    } catch (_) {
      return;
    }
    if (!mounted || zones.isEmpty) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      // Desktop/planshetda panel butun ekranga yoyilib ketmasin —
      // kataklar bir joyda to'planib tursin
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.table_restaurant_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        change ? 'Stol raqamini almashtirish' : 'Stol ochish',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    for (final z in zones) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(
                          (z['name'] is Map ? z['name']['uz'] : z['name'] ?? '')
                              .toString(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t
                              in tablesByZone[z['id'] as int? ?? 0] ?? [])
                            _tablePickChip(
                              ctx,
                              t,
                              (z['name'] is Map
                                      ? z['name']['uz']
                                      : z['name'] ?? '')
                                  .toString(),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (change) {
      await _changeTableTo(picked);
      return;
    }
    final host = widget.tabsHost;
    if (host != null) {
      host.requestAddTable(picked);
    } else {
      _switchTable(picked);
    }
  }

  /// Joriy tabning stolini almashtirish. Yuborilgan cheklar bo'lsa server
  /// ularni yangi stolga ko'chiradi; yuborilmagan savat esa shu tabda
  /// turgani uchun o'z-o'zidan saqlanib qoladi.
  Future<void> _changeTableTo(Map<String, dynamic> t) async {
    final newSku = (t['sku'] ?? '').toString();
    final curSku = widget.tableSKU;
    final host = widget.tabsHost;
    if (newSku.isEmpty || curSku == null || newSku == curSku || host == null) {
      return;
    }
    void warn(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    }

    if (host.isOpen(newSku)) {
      warn('Bu stol boshqa tabda ochiq — avval o\'sha tabni yoping');
      return;
    }
    if (AppState().getTableStatus(newSku) != 'free') {
      warn(
        'Bu stol band — cheklar aralashib ketmasligi uchun bo\'sh stol tanlang',
      );
      return;
    }
    final newLabel = (t['label'] ?? newSku).toString();
    if (_checks.isNotEmpty) {
      try {
        await ApiService().changeOrderTable(curSku, newSku);
      } catch (e) {
        if (mounted) {
          warn(friendlyError(e, fallback: 'Stol almashtirilmadi'));
        }
        return;
      }
    }
    if (!mounted) return;
    host.changeTabTable(this, newSku, newLabel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Stol $newLabel ga almashtirildi'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Paneldagi bitta stol katagi: yashil — bo'sh, qizil — band,
  /// ko'k — allaqachon tab sifatida ochiq (bosilsa o'sha tab faollashadi).
  Widget _tablePickChip(
    BuildContext sheetCtx,
    Map<String, dynamic> t,
    String zoneName,
  ) {
    final sku = (t['sku'] ?? '').toString();
    final isOpen = widget.tabsHost?.isOpen(sku) ?? (sku == widget.tableSKU);
    final free = AppState().getTableStatus(sku) == 'free';
    final color = isOpen
        ? AppColors.primary
        : free
        ? AppColors.success
        : AppColors.danger;

    return Material(
      color: isOpen ? AppColors.primary : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.pop(sheetCtx, t),
        // O'lcham QAT'IY: ilgari Container `alignment` tufayli butun enga
        // cho'zilib, har bir stol alohida qator bo'lib qolgan edi —
        // ro'yxatni aylantirib tanlash noqulay edi. Endi stollar ekranidagi
        // kabi ixcham kataklar setka bo'lib teriladi.
        child: SizedBox(
          width: 78,
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _shortTableLabel(t, zoneName),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: isOpen ? Colors.white : color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isOpen ? 'ochiq' : (free ? 'bo\'sh' : 'band'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isOpen ? Colors.white70 : color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tanlangan stolning buyurtma ekraniga o'tish. Savatda yozilmagan
  /// mahsulot bo'lsa — avval so'raladi (yuborilmagan qatorlar boshqa
  /// stolga o'tganda saqlanmaydi).
  Future<void> _switchTable(Map<String, dynamic> t) async {
    final sku = (t['sku'] ?? '').toString();
    if (sku.isEmpty || sku == widget.tableSKU || _sending) return;
    if (_cart.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Savatda yozilmagan mahsulot bor'),
          content: Text(
            '${_cart.length} ta qator hali yuborilmagan. '
            'Boshqa stolga o\'tsangiz ular yo\'qoladi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Qolaman'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Tashlab o\'tish'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OrderScreen(
          tableSKU: sku,
          tableLabel: (t['label'] ?? sku).toString(),
        ),
      ),
    );
  }

  Future<void> _printReceipt() async {
    // Ikki marta bosishdan himoya: printer sekin bo'lsa kassir qayta bosib,
    // har bosishda yangi chek chiqarardi.
    if (_printing) return;
    _printing = true;
    try {
      // Savatda yuborilmagan mahsulot bo'lsa — avval so'raladi
      if (!await _resolvePendingCart()) return;
      if (widget.tableSKU != null) {
        await ApiService().printReceipt(tableSku: widget.tableSKU);
      } else if (_checks.isNotEmpty) {
        await ApiService().printReceipt(
          orderNumber: _checks.first['order_number'],
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chek chiqarilmoqda...'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chek chiqmadi — printerni tekshiring'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      _printing = false;
    }
  }

  Future<void> _closeOrder() async {
    if (widget.tableSKU == null && _checks.isEmpty) return;
    // Ikki marta bosishdan himoya. Ilgari tugma umuman bloklanmasdi va
    // sekin tarmoqda kassir ikkinchi marta bosib yuborardi: server ikkala
    // so'rovni ham bajarib, chegirma IKKI MARTA ayirilardi va mijozning
    // sodiqlik ballari ikki marta yozilardi.
    if (_closing) return;
    _closing = true;

    // Savatda yuborilmagan mahsulot bo'lsa — avval so'raladi. Yuborilsa
    // cheklar qayta yuklanib, to'lov oynasida jami YANGI mahsulotlar
    // bilan chiqadi.
    if (!await _resolvePendingCart()) {
      _closing = false;
      return;
    }
    if (!mounted) {
      _closing = false;
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final sub = _grandSubtotal;
        final total = _payableTotal();
        return AlertDialog(
          title: const Text('To\'lov'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _payRow('Mahsulotlar', formatMoney(sub, suffix: ' so\'m')),
                // Yetkazib berish va chegirma — ilgari to'lov oynasida
                // umuman ko'rsatilmasdi va jamiga ham kirmasdi.
                if (_grandDeliveryFee > 0)
                  _payRow(
                    'Yetkazib berish',
                    formatMoney(_grandDeliveryFee, suffix: ' so\'m'),
                  ),
                if (_grandDiscount > 0)
                  _payRow(
                    'Chegirma',
                    '− ${formatMoney(_grandDiscount, suffix: ' so\'m')}',
                    color: AppColors.success,
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Jami',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        formatMoney(total, suffix: ' so\'m'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'TO\'LOV USULI',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.6,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                ..._paymentMethods(ctx),
              ],
            ),
          ),
        );
      },
    );
    if (result == null) {
      _closing = false;
      return;
    }

    try {
      final payments = (result['payments'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final method = (result['method'] as String?) ?? 'split';
      if (widget.tableSKU != null) {
        await ApiService().closeOrderByTable(
          widget.tableSKU!,
          method,
          discount: result['discount'] ?? 0,
          payments: payments,
          paymentComment: result['comment'] as String?,
        );
      } else {
        final orderNum = _checks.isNotEmpty
            ? _checks.first['order_number'] as String?
            : null;
        if (orderNum != null) {
          await ApiService().closeOrderByNumber(
            orderNum,
            method,
            discount: result['discount'] ?? 0,
            payments: payments,
            paymentComment: result['comment'] as String?,
          );
        }
      }
      if (mounted) _exitScreen();
    } catch (e) {
      var msg = 'Xato: $e';
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] is String) {
          msg = data['message'] as String;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      // `mounted` tekshirilmaydi: ekran yopilgan bo'lsa ham bayroq
      // tozalanishi kerak (singleton emas, lekin qayta ochilishi mumkin).
      _closing = false;
    }
  }

  // To'lov usullari — kartochkalar to'ri (qator-qator ro'yxat emas):
  // ko'z bilan tez topiladi, barmoq bilan bosish oson.
  List<Widget> _paymentMethods(BuildContext ctx) {
    Future<void> pick(String method) async {
      // «Boshqa» — izoh shart (summa bilan guruhga ketadi)
      if (method == 'other') {
        final comment = await askOtherPaymentComment(
          ctx,
          amount: _payableTotal(),
        );
        if (comment == null || !ctx.mounted) return;
        Navigator.pop(ctx, {'method': 'other', 'comment': comment});
        return;
      }
      Navigator.pop(ctx, {'method': method});
    }

    Future<void> split() async {
      // Bir necha chekli stolda ham ishlaydi — server to'lov
      // qismlarini cheklar bo'ylab o'zi taqsimlaydi.
      // Summa server hisoblaydigan qiymat bilan AYNAN bir xil
      // bo'lishi shart, aks holda server "payments_mismatch"
      // qaytaradi va chekni umuman yopib bo'lmaydi.
      final payTotal = _payableTotal();
      final payments = await showDialog<List<Map<String, dynamic>>>(
        context: ctx,
        builder: (_) => _SplitPaymentDialog(total: payTotal),
      );
      if (payments == null || !ctx.mounted) return;
      // Aralashda «Boshqa» qismi bo'lsa — shu qism uchun izoh
      final other = payments
          .where((p) => p['method'] == 'other')
          .fold<int>(0, (s, p) => s + ((p['amount'] as num?)?.toInt() ?? 0));
      String? comment;
      if (other > 0) {
        comment = await askOtherPaymentComment(ctx, amount: other);
        if (comment == null || !ctx.mounted) return;
      }
      Navigator.pop(ctx, {'payments': payments, 'comment': ?comment});
    }

    final cards = <Widget>[
      for (final m in kPaymentMethods)
        _PayMethodCard(
          label: m.$2,
          icon: m.$3,
          color: m.$4,
          onTap: () => pick(m.$1),
        ),
      // Aralash to'lov — bitta chekni 2-3 usul bilan yopish
      _PayMethodCard(
        label: 'Aralash',
        icon: Icons.call_split_rounded,
        color: AppColors.primary,
        highlighted: true,
        onTap: split,
      ),
    ];

    return [
      LayoutBuilder(
        builder: (context, c) {
          const gap = 8.0;
          final cols = c.maxWidth >= 360 ? 4 : 3;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final card in cards) SizedBox(width: w, child: card),
            ],
          );
        },
      ),
    ];
  }

  Widget _payRow(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: color,
          ),
        ),
      ],
    ),
  );

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final width = MediaQuery.of(context).size.width;
    // Keng ekran (desktop/planshet): chapda buyurtma paneli, o'ngda menyu
    final wide = width >= AppBreakpoints.phone;
    // Panel ekranning ~30% i: ilgari 1400pt gacha qat'iy 320pt edi va
    // 13 dyuymli planshetda chek ro'yxati siqilib turardi.
    final panelWidth = (width * 0.30).clamp(300.0, 420.0);

    // Sistem «orqaga» si (iOS da chetdan surish, Android tugmasi) endi
    // «Yopish» tugmasi bilan BIR XIL ishlaydi.
    //
    // Ilgari `PopScope` yo'q edi: iOS chetdan surish sahifani darrov
    // yopar, savatdagi yuborilmagan qatorlar hech qanday savolsiz
    // yo'qolardi — «Savatda yozilmagan mahsulot bor» dialogi faqat
    // tepa-chapdagi «Yopish» tugmasidan o'tganda chiqardi.
    //
    // `canPop` savat o'zgarganda qayta hisoblanishi uchun `_cartVersion`
    // tinglanadi: `_addToCart` `setState` chaqirmaydi.
    final scaffold = Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(wide ? 64 : 56),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 12 : 8, 6, wide ? 20 : 12, 6),
              child: Row(
                children: [
                  // Back / close — tab rejimida BARCHA tablarni yopib
                  // stollar ekraniga qaytadi (har bir tabning o'z «×» i bor)
                  Material(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        final host = widget.tabsHost;
                        if (host != null) {
                          host.requestCloseAll();
                        } else {
                          _handleClose();
                        }
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 14 : 10,
                          vertical: wide ? 11 : 9,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.close_rounded,
                              color: AppColors.danger,
                              size: wide ? 22 : 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Yopish',
                              style: TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w800,
                                fontSize: wide ? 15 : 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: wide ? 14 : 10),
                  // Tab qatori (Chrome uslubida): har bir ochiq stol —
                  // alohida tab, oxirida «+» yangi stol ochadi. Yakka
                  // rejimda oddiy stol nomi ko'rsatiladi.
                  if (widget.tabsHost != null)
                    Expanded(child: _buildTabStrip(wide))
                  else
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 14 : 10,
                        vertical: wide ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        widget.tableLabel,
                        style: TextStyle(
                          fontSize: wide ? 16 : 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  if (_checks.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    // Bosilganda cheklar ro'yxati (chekbay) ochiladi
                    InkWell(
                      onTap: _openChecksSheet,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: StatusBadge(
                        label: '${_checks.length}',
                        color: AppColors.info,
                        icon: Icons.receipt_rounded,
                        fontSize: wide ? 13 : 11,
                      ),
                    ),
                  ],
                  if (widget.tabsHost == null)
                    const Spacer()
                  else
                    SizedBox(width: wide ? 12 : 8),
                  if (_grandTotal > 0)
                    Text(
                      formatMoney(_grandTotal, suffix: ' so\'m'),
                      style: TextStyle(
                        fontSize: wide ? 18 : 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Keng ekran: CHAPDA kategoriyalar (tik ro'yxat), o'rtada menyu,
      // O'NGDA chek paneli (savat + yuborilgan cheklar + to'lov).
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: (width * 0.19).clamp(200.0, 280.0),
                  child: _buildCategorySidebar(_catPages),
                ),
                Expanded(child: _buildMenuArea(wide: true)),
                SizedBox(width: panelWidth, child: _buildOrderPanel()),
              ],
            )
          : _buildMenuArea(wide: false),
      bottomNavigationBar: wide
          ? null
          : ValueListenableBuilder<int>(
              valueListenable: _cartVersion,
              builder: (ctx, _, _) => _BottomBar(
                cartCount: _cartCount,
                cartTotal: _cartTotal,
                checksCount: _checks.length,
                grandTotal: _grandTotal,
                sending: _sending,
                onCartTap: _openCartSheet,
                onChecksTap: _openChecksSheet,
                onSubmit: _confirmAndSubmit,
                onPay: _closeOrder,
              ),
            ),
    );

    // Tab rejimida orqaga/yopish HOST (OrderTabsScreen) zimmasida:
    // IndexedStack ichida har bir tab o'z PopScope'ini qo'shsa, orqaga
    // bosilganda hammasining dialogi baravar ochilib ketardi.
    if (widget.tabsHost != null) return scaffold;
    return ValueListenableBuilder<int>(
      valueListenable: _cartVersion,
      builder: (ctx, _, child) => PopScope(
        canPop: _cart.isEmpty && !_sending,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleClose();
        },
        child: child!,
      ),
      child: scaffold,
    );
  }

  // ============================================================
  // Tab qatori — Chrome uslubida: ochiq stollar + «+» tugmasi
  // ============================================================

  Widget _buildTabStrip(bool wide) {
    final host = widget.tabsHost!;
    final tabs = host.tabs;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) _tabChip(i, tabs[i], wide),
          // Yangi stol ochish — Chrome'dagi «+» kabi
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: _openTablePicker,
              child: Container(
                padding: EdgeInsets.all(wide ? 8 : 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: wide ? 20 : 18,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(int i, OrderTabInfo tab, bool wide) {
    final host = widget.tabsHost!;
    final active = i == host.activeIndex;
    final fg = active ? AppColors.primary : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          // Nofaol tab bosilsa — unga o'tiladi. Faol tab bosilsa — tab
          // YOPILADI: kichkina «×» ni mo'ljalga olish shart emas, butun chip
          // yopish tugmasi. Yuborilgan buyurtmasi bo'lsa host mahsulotlar
          // ro'yxati bilan tasdiqlash so'raydi. Yakka tabda esa eski odat:
          // stol raqamini almashtirish paneli ochiladi.
          onTap: active
              ? (host.tabs.length > 1
                    ? () => host.requestCloseTab(i)
                    : (widget.tableSKU != null
                          ? () => _openTablePicker(change: true)
                          : null))
              : () => host.selectTab(i),
          // Stol raqamini almashtirish endi bosib turishda
          onLongPress: active && widget.tableSKU != null
              ? () => _openTablePicker(change: true)
              : null,
          child: Container(
            // Faol va nofaol tab bir xil balandlikda tursin deb faol
            // tabga shaffof ramka beriladi
            decoration: BoxDecoration(
              border: Border.all(
                color: active ? Colors.transparent : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 12 : 9,
              vertical: wide ? 8 : 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: wide ? 15 : 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                // «×» faqat bittadan ko'p tab ochiq bo'lganda —
                // oxirgi tabni yopish «Yopish» tugmasining ishi
                if (host.tabs.length > 1) ...[
                  SizedBox(width: wide ? 4 : 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () => host.requestCloseTab(i),
                    // Padding — barmoq bilan tegish maydonini kengaytiradi
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: wide ? 17 : 14,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Menyu qismi (kategoriya chiplari + mahsulot gridi)
  // ============================================================

  Widget _buildMenuArea({required bool wide}) {
    final pages = _catPages;
    final searching = _search.isNotEmpty;
    return Column(
      children: [
        _buildSearchField(),
        // Qidiruv yozilganda kategoriya tanlagich kerak emas —
        // natija butun menyu bo'yicha chiqadi
        if (!searching && !wide) _buildCategoryPicker(pages),
        Expanded(
          child: searching
              ? _buildProductGrid(
                  _searchResults,
                  wide: wide,
                  empty: 'Topilmadi',
                )
              : PageView.builder(
                  controller: _catPageController,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _selectedCatIndex = i),
                  itemBuilder: (ctx, pageIndex) =>
                      _buildProductGrid(pages[pageIndex], wide: wide),
                ),
        ),
      ],
    );
  }

  /// Menyu bo'yicha qidiruv — nom (uz/ru/tr) bo'yicha, katta-kichik harf farqsiz
  Widget _buildSearchField() {
    final fs = context.isTabletUi ? 16.5 : 14.5;
    return Container(
      padding: EdgeInsets.fromLTRB(
        context.isTabletUi ? 16 : 12,
        8,
        context.isTabletUi ? 16 : 12,
        8,
      ),
      color: AppColors.surface,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: fs, color: AppColors.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Mahsulot qidirish...',
          hintStyle: TextStyle(fontSize: fs, color: AppColors.textFaint),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: context.isTabletUi ? 22 : 20,
            color: AppColors.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                    FocusScope.of(context).unfocus();
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceAlt,
          contentPadding: EdgeInsets.symmetric(
            vertical: context.isTabletUi ? 14 : 11,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  /// Qidiruvga mos, sotuvda turgan mahsulotlar (butun menyu bo'yicha)
  List<dynamic> get _searchResults {
    if (_search.isEmpty) return const [];
    // Raqamli qidiruv — narx bo'yicha ham ("80" → 80 000, probel bilan ham)
    final digits = _search.replaceAll(' ', '');
    final byPrice = digits.isNotEmpty && int.tryParse(digits) != null;
    // Alifbodan qat'i nazar: «choy» ↔ «чой» — ikkalasi bir shaklga o'giriladi
    final q = searchFold(_search);
    // Qidiruv butun menyu bo'yicha — qoldig'i bor barcha mahsulot
    return _stockedProducts.where((p) {
      final names = p['name'] as Map<String, dynamic>? ?? {};
      if (q.isNotEmpty &&
          names.values.any((n) => n is String && searchFold(n).contains(q))) {
        return true;
      }
      final price = p['price'];
      return byPrice &&
          price is num &&
          price.toInt().toString().startsWith(digits);
    }).toList();
  }

  Widget _buildProductGrid(
    List<dynamic> products, {
    required bool wide,
    String empty = 'Mahsulot yo\'q',
  }) {
    if (products.isEmpty) {
      return EmptyState(icon: Icons.fastfood_rounded, title: empty);
    }
    // Savatdagi miqdor kartochkada ko'rinishi uchun grid `_cartVersion`ni
    // tinglaydi: `_addToCart` `setState` chaqirmaydi (u faqat notifier'ni
    // ko'taradi), shusiz nishon yangilanmay qolardi.
    return ValueListenableBuilder<int>(
      valueListenable: _cartVersion,
      builder: (ctx, _, _) => ValueListenableBuilder<double>(
        valueListenable: UiPrefs().menuScale,
        builder: (ctx, scale, _) => LayoutBuilder(
          builder: (ctx, c) {
            // Ustun kengligi ekranga moslashadi: telefonda 3 ta, planshetda
            // kartochka kattaroq (barmoq bilan urish qulay bo'lsin).
            // `scale` — kassir sozlamadan tanlagan masshtab (UiPrefs).
            // Keng ekranda kartochka ixcham (menyu katta — ko'proq sig'sin).
            final target =
                (c.maxWidth >= 1000
                    ? 128.0
                    : wide
                    ? 118.0
                    : c.maxWidth >= AppBreakpoints.phone
                    ? 152.0
                    : c.maxWidth < 360
                    ? 104.0
                    : 118.0) *
                scale;
            final gap = wide ? 6.0 : (c.maxWidth >= AppBreakpoints.phone ? 10.0 : 8.0);
            final pad = wide ? 8.0 : ctx.gutter;
            final cols = ((c.maxWidth - pad * 2 + gap) / (target + gap))
                .floor()
                .clamp(2, scale < 0.99 ? 12 : 8);
            final tileW = (c.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
            // Balandlik kenglikdan kelib chiqadi: rasm + ostida qat'iy
            // balandlikdagi matn bloki (nom 2 qator + narx). Matn bloki
            // qat'iy bo'lgani uchun bir qatordagi hamma kartochkada rasm
            // bir xil o'lchamda chiqadi.
            final tileH = wide
                ? tileW * 0.42 + 54
                : tileW * 0.60 + (tileW < 120 ? 56 : 64);

            return GridView.builder(
              padding: EdgeInsets.fromLTRB(pad, 6, pad, wide ? 16 : 100),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tileH,
              ),
              itemCount: products.length,
              itemBuilder: (ctx, i) {
                final p = products[i];
                final stockCount = AppState().getStockCount(p['id']);
                final soldOut =
                    !AppState().stockSoft &&
                    stockCount != null &&
                    stockCount <= 0;
                final inactive = (p['status'] ?? 'active') != 'active';
                final inCart = _cart
                    .where((c) => c['product_id'] == p['id'])
                    .fold<int>(0, (s, c) => s + (c['quantity'] as int? ?? 0));
                return _ProductCard(
                  product: p,
                  soldOut: soldOut,
                  inactive: inactive,
                  inCart: inCart,
                  compact: wide || tileW < 120,
                  buildImage: () =>
                      _productMedia(p, soldOut, stockCount, inactive: inactive),
                  // Nofaolga bosilsa _addToCart tushuntirish snackbar'ini
                  // chiqaradi (savatga tushmaydi).
                  onTap: soldOut && !inactive ? null : () => _addToCart(p),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Kategoriya nomi
  String _catName(int i) {
    if (i < 0 || i >= _categories.length) return '';
    return menuName(_categories[i]['name']);
  }

  void _selectCategory(int i, int pageCount) {
    // Ro'yxat ochiq qoladi — kassir ketma-ket kategoriya almashtira oladi
    setState(() => _selectedCatIndex = i);
    if (i < pageCount && _catPageController.hasClients) {
      // Ko'p sahifa oshib o'tilganda animatsiya sekin —
      // to'g'ridan-to'g'ri sakraydi
      _catPageController.jumpToPage(i);
    }
  }

  /// Keng ekran: CHAP tomondagi tik kategoriya ro'yxati (bo'sh kategoriya
  /// ko'rsatilmaydi). Tanlash PageView sahifasini almashtiradi.
  Widget _buildCategorySidebar(List<List<dynamic>> pages) {
    final count = _categories.length;
    int countAt(int i) => i >= 0 && i < pages.length ? pages[i].length : 0;
    // Mone guruhi (БАР / КУХНЯ / МАГАЗИН…) bo'yicha jamlanadi: guruh birinchi
    // uchragan tartibda, ichida server tartibi. Guruh bo'lmasa — oddiy ro'yxat.
    final byGroup = <String, List<int>>{};
    for (var i = 0; i < count; i++) {
      if (countAt(i) == 0) continue;
      final g = (_categories[i]['group'] ?? '').toString().trim();
      byGroup.putIfAbsent(g, () => []).add(i);
    }
    final showHeaders = byGroup.keys.any((g) => g.isNotEmpty);
    final entries = <Object>[]; // String = sarlavha, int = kategoriya indeksi
    byGroup.forEach((g, ids) {
      if (showHeaders) entries.add(g.isEmpty ? 'BOSHQA' : g);
      entries.addAll(ids);
    });
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: entries.length,
        itemBuilder: (ctx, k) {
          final e = entries[k];
          if (e is String) {
            return Padding(
              padding: EdgeInsets.fromLTRB(6, k == 0 ? 4 : 14, 6, 6),
              child: Text(
                e.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textFaint,
                ),
              ),
            );
          }
          final i = e as int;
          final sel = _selectedCatIndex == i && _search.isEmpty;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: sel ? AppColors.primary : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  if (_search.isNotEmpty) {
                    _searchCtrl.clear();
                    _search = '';
                  }
                  _selectCategory(i, count);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _catName(i),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel ? Colors.white : AppColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${countAt(i)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white70 : AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Kategoriya tanlagich — bitta qatorda, gorizontal aylantiriladi
  Widget _buildCategoryPicker(List<List<dynamic>> pages) {
    final count = _categories.length;
    int countAt(int i) => i >= 0 && i < pages.length ? pages[i].length : 0;
    final big = context.isTabletUi;

    return Container(
      height: big ? 58 : 50,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: big ? 16 : 12, vertical: 8),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => _CategoryTile(
          label: _catName(i),
          count: countAt(i),
          selected: _selectedCatIndex == i,
          onTap: () => _selectCategory(i, count),
        ),
      ),
    );
  }

  // ============================================================
  // Chap panel (desktop) — savat + yuborilgan cheklar
  // ============================================================

  Widget _buildOrderPanel() {
    void rebuild() => setState(() {});

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _cartVersion,
        // `empty` SHU YERDA hisoblanadi.
        //
        // Ilgari u `builder` dan TASHQARIDA edi: menyudan mahsulot
        // bosilganda `_addToCart` faqat `_cartVersion` ni ko'taradi
        // (`setState` chaqirmaydi), shuning uchun `builder` qayta ishlar,
        // lekin eski `empty=true` qiymati bilan — planshetda savatga
        // qo'shilgan mahsulot panelda ko'rinmay, «Savatcha bo'sh» yozuvi
        // qolib ketardi (pastdagi summa esa yangilanardi).
        builder: (ctx, _, _) {
          final empty = _cart.isEmpty && _checks.isEmpty;
          return Column(
            children: [
              // Sarlavha
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.primary,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Buyurtma',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const Spacer(),
                    if (_checks.isNotEmpty)
                      StatusBadge(
                        label: '${_checks.length} chek',
                        color: AppColors.info,
                        fontSize: 11,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: empty
                    ? const EmptyState(
                        icon: Icons.shopping_cart_outlined,
                        title: 'Savatcha bo\'sh',
                        subtitle: 'Mahsulot tanlang',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        children: [
                          if (_cart.isNotEmpty) ...[
                            _panelSectionLabel(
                              'Yangi chek',
                              '$_cartCount ta',
                              color: AppColors.success,
                            ),
                            ..._cart.asMap().entries.map((e) {
                              final i = e.key;
                              final c = e.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _CartTile(
                                  item: c,
                                  onDecrement: () {
                                    if ((c['quantity'] as int) > 1) {
                                      c['quantity'] = c['quantity'] - 1;
                                    } else {
                                      _cart.remove(c);
                                    }
                                    _bumpCart();
                                    rebuild();
                                  },
                                  onIncrement: () {
                                    if (_incrementCartLine(c)) rebuild();
                                  },
                                  onRemove: () {
                                    if (i < _cart.length) _cart.remove(c);
                                    _bumpCart();
                                    rebuild();
                                  },
                                ),
                              );
                            }),
                            const SizedBox(height: 6),
                          ],
                          if (_checks.isNotEmpty)
                            ..._buildChecksMerged(rebuild),
                        ],
                      ),
              ),
              if (_cancelCart.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: _buildCancelCart(rebuild),
                ),
              // Pastki qism — jamilar va tugmalar
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  children: [
                    if (_cart.isNotEmpty) ...[
                      KKeyValueRow(
                        label: 'Savat',
                        value: formatMoney(_cartTotal, suffix: ' so\'m'),
                        bold: true,
                        valueColor: AppColors.success,
                        divider: false,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: _sending ? null : _confirmAndSubmit,
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            _sending ? 'Yuborilmoqda...' : 'Yuborish',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                          ),
                        ),
                      ),
                      if (_checks.isNotEmpty) const SizedBox(height: 10),
                    ],
                    if (_checks.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: _cancelCart.isNotEmpty
                                    ? null
                                    : _printReceipt,
                                icon: const Icon(Icons.print_rounded, size: 17),
                                label: const Text(
                                  'Chek',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 46,
                              child: FilledButton.icon(
                                onPressed: _cancelCart.isNotEmpty
                                    ? null
                                    : _closeOrder,
                                icon: const Icon(
                                  Icons.payments_rounded,
                                  size: 17,
                                ),
                                label: const Text(
                                  'To\'lov',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (empty)
                      const Text(
                        'Mahsulot tanlang',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panelSectionLabel(
    String title,
    String trailing, {
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
      ],
    ),
  );

  // ============================================================
  // Cancel cart (in checks sheet)
  // ============================================================

  Widget _buildCancelCart(VoidCallback rebuild) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          ..._cancelCart.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      _removeFromCancelCart(i);
                      rebuild();
                    },
                    child: const Icon(
                      Icons.add_circle_rounded,
                      size: 20,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${c['name']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${c['qty']} ta',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney((c['price'] as int) * (c['qty'] as int)),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton.icon(
              onPressed: _cancelling
                  ? null
                  : () async {
                      await _submitCancel();
                      rebuild();
                    },
              icon: _cancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded, size: 16),
              label: Text(
                'Bekor qilish ${formatMoney(_cancelCartTotal, suffix: ' so\'m')}',
                style: const TextStyle(fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Checks detail (returns list of widgets for ListView)
  // ============================================================

  // ============================================================
  // Cheklar — panelda birlashgan ro'yxat, sheet'da chekbay ko'rinish
  // ============================================================

  /// Barcha faol cheklardagi mahsulotlarni bitta ro'yxatga yig'adi.
  /// Bir mahsulot bir necha chekda bo'lsa — soni qo'shilib ketadi.
  List<Map<String, dynamic>> _mergedCheckItems() {
    final byProduct = <int, Map<String, dynamic>>{};
    for (final raw in _checks) {
      final check = raw as Map<String, dynamic>;
      if (check['status'] == 'cancelled') continue;
      final orderNum = check['order_number'] as String? ?? '';
      for (final item in (check['items'] as List<dynamic>? ?? [])) {
        final qty = item['quantity'] as int? ?? 0;
        if (qty <= 0) continue;
        final pid = item['product_id'] as int? ?? 0;
        final price = item['price'] as int? ?? 0;
        final snap = item['snapshot'] as Map<String, dynamic>? ?? {};
        final nameMap = snap['name'] as Map<String, dynamic>? ?? {};
        final addedBy = item['added_by'] as Map<String, dynamic>? ?? {};
        final e = byProduct.putIfAbsent(
          pid,
          () => {
            'product_id': pid,
            'name': menuName(nameMap, fallback: '?'),
            'price': price,
            'quantity': 0,
            'total': 0,
            'waiters': <String>{},
            'sources': <Map<String, dynamic>>[],
          },
        );
        e['quantity'] = (e['quantity'] as int) + qty;
        e['total'] = (e['total'] as int) + price * qty;
        final w = addedBy['name'] as String?;
        if (w != null && w.isNotEmpty) (e['waiters'] as Set<String>).add(w);
        (e['sources'] as List).add({
          'order_number': orderNum,
          'qty': qty,
          'price': price,
        });
      }
    }
    return byProduct.values.toList();
  }

  /// Faol cheklardagi jami mahsulot soni (sarlavhada ko'rsatiladi)
  int get _checksItemCount => _mergedCheckItems().fold<int>(
    0,
    (sum, e) => sum + (e['quantity'] as int),
  );

  /// Birlashgan qator o'chirilayotganda: shu mahsulot hali qolgan
  /// birinchi chekdan bekor qilishga qo'shiladi
  void _cancelFromMerged(Map<String, dynamic> entry) {
    final pid = entry['product_id'] as int;
    final name = entry['name'] as String;
    for (final src in (entry['sources'] as List)) {
      final orderNum = src['order_number'] as String;
      final inCheck = src['qty'] as int;
      final pending = _cancelCart
          .where((c) => c['order_number'] == orderNum && c['product_id'] == pid)
          .fold<int>(0, (sum, c) => sum + (c['qty'] as int));
      if (pending < inCheck) {
        _addToCancelCart(orderNum, pid, name, src['price'] as int);
        return;
      }
    }
  }

  /// Qator bosib turilganda (long press) chiqadigan o'chirish menyusi.
  /// Kichkina "−" tugmasini mo'ljallash noqulay edi — endi butun qator
  /// bosib turiladi. Qaytgan son bekor qilish savatiga tushadi, serverga
  /// esa faqat "Bekor qilish" tugmasi bosilganda ketadi.
  Future<int> _askDeleteCount(String name, int qty) async {
    HapticFeedback.mediumImpact();
    final count = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 1),
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  label: const Text(
                    '1 ta o\'chirish',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
              if (qty > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, qty),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: Text(
                      'Hammasini o\'chirish (x$qty)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
        ],
      ),
    );
    return count ?? 0;
  }

  /// Chekka bo'linmagan, umumiy mahsulotlar ro'yxati (panelda ko'rinadi)
  List<Widget> _buildChecksMerged(VoidCallback rebuild) {
    final entries = _mergedCheckItems();
    if (entries.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Yuborilgan mahsulot yo\'q',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        ),
      ];
    }

    return entries.map<Widget>((e) {
      final pid = e['product_id'] as int;
      final qty = e['quantity'] as int;
      final name = e['name'] as String;
      final waiters = (e['waiters'] as Set<String>).join(', ');
      final pending = _cancelCart
          .where((c) => c['product_id'] == pid)
          .fold<int>(0, (sum, c) => sum + (c['qty'] as int));
      final displayQty = qty - pending;
      final price = e['price'] as int;

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            // Qator bosilganda mahsulot savatga qayta qo'shiladi —
            // yuborilgandan keyin ham qidirmasdan yana buyurtma qilinadi.
            // Bosib turilganda (long press) o'chirish menyusi chiqadi.
            onTap: () {
              _reAddFromCheck(pid);
              rebuild();
            },
            onLongPress: displayQty > 0
                ? () async {
                    final n = await _askDeleteCount(name, displayQty);
                    for (var i = 0; i < n; i++) {
                      _cancelFromMerged(e);
                    }
                    if (n > 0) rebuild();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            decoration: displayQty <= 0
                                ? TextDecoration.lineThrough
                                : null,
                            color: displayQty <= 0
                                ? AppColors.textFaint
                                : AppColors.text,
                          ),
                        ),
                        Row(
                          children: [
                            if (waiters.isNotEmpty)
                              Text(
                                waiters,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textFaint,
                                ),
                              ),
                            if (pending > 0) ...[
                              if (waiters.isNotEmpty) const SizedBox(width: 6),
                              Text(
                                '(-$pending)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'x${displayQty > 0 ? displayQty : 0}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: displayQty <= 0
                          ? AppColors.textFaint
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMoney(price * (displayQty > 0 ? displayQty : 0)),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: displayQty <= 0
                          ? AppColors.textFaint
                          : AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildChecksDetail(VoidCallback rebuild) {
    return _checks.map<Widget>((checkRaw) {
      final check = checkRaw as Map<String, dynamic>;
      final checkNum = check['order_number'] ?? '';
      final items = check['items'] as List<dynamic>? ?? [];
      final checkSubtotal = check['subtotal'] as int? ?? 0;
      final createdAt = check['created_at'] ?? '';
      String timeStr = '';
      if (createdAt.length >= 16) timeStr = createdAt.substring(11, 16);
      final cancelled = check['status'] == 'cancelled';
      // Chek odatda ochiq — sarlavhani bosganda yig'ib qo'yish mumkin
      final expanded = !_collapsedChecks.contains(checkNum);
      final pendingInCheck = _cancelCart
          .where((c) => c['order_number'] == checkNum)
          .fold<int>(0, (sum, c) => sum + (c['qty'] as int));

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: cancelled ? AppColors.dangerSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: cancelled
                ? AppColors.danger.withValues(alpha: 0.3)
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: cancelled
                  ? AppColors.danger.withValues(alpha: 0.08)
                  : AppColors.surfaceAlt,
              borderRadius: expanded
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.md),
                      topRight: Radius.circular(AppRadius.md),
                    )
                  : BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: expanded
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.md),
                        topRight: Radius.circular(AppRadius.md),
                      )
                    : BorderRadius.circular(AppRadius.md),
                onTap: () {
                  if (expanded) {
                    _collapsedChecks.add(checkNum);
                  } else {
                    _collapsedChecks.remove(checkNum);
                  }
                  rebuild();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                  child: Row(
                    children: [
                      Text(
                        '#$checkNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: cancelled ? AppColors.danger : AppColors.text,
                        ),
                      ),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                      if (cancelled) ...[
                        const SizedBox(width: 6),
                        const StatusBadge(
                          label: 'Bekor',
                          color: AppColors.danger,
                        ),
                      ],
                      // Yopiq turganda ham nechta mahsulot borligi ko'rinadi
                      if (!expanded) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${items.length} ta',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      if (pendingInCheck > 0) ...[
                        const SizedBox(width: 6),
                        StatusBadge(
                          label: '-$pendingInCheck',
                          color: AppColors.warning,
                          fontSize: 10,
                        ),
                      ],
                      const Spacer(),
                      Text(
                        formatMoney(checkSubtotal, suffix: ' so\'m'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: cancelled
                              ? AppColors.textMuted
                              : AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded)
              ...items.map((item) {
                final snap = item['snapshot'] as Map<String, dynamic>? ?? {};
                final nameMap = snap['name'] as Map<String, dynamic>? ?? {};
                final addedBy = item['added_by'] as Map<String, dynamic>? ?? {};
                final qty = item['quantity'] as int? ?? 0;
                final cancelledQty = item['cancelled_qty'] as int? ?? 0;
                final isItemCancelled = qty == 0;
                final productId = item['product_id'] as int? ?? 0;
                final price = item['price'] as int? ?? 0;
                final name = menuName(nameMap, fallback: '?');

                final pendingCancel = _cancelCart
                    .where(
                      (c) =>
                          c['order_number'] == checkNum &&
                          c['product_id'] == productId,
                    )
                    .fold(0, (sum, c) => sum + (c['qty'] as int));
                final displayQty = qty - pendingCancel;
                final canCancel =
                    !cancelled && !isItemCancelled && displayQty > 0;

                // Qator bosilganda mahsulot savatga qayta qo'shiladi —
                // yuborilgandan keyin ham qidirmasdan yana buyurtma qilinadi.
                // Bosib turilganda (long press) o'chirish menyusi chiqadi.
                return InkWell(
                  onTap: () {
                    _reAddFromCheck(productId);
                    rebuild();
                  },
                  onLongPress: canCancel
                      ? () async {
                          final n = await _askDeleteCount(name, displayQty);
                          for (var i = 0; i < n; i++) {
                            _addToCancelCart(checkNum, productId, name, price);
                          }
                          if (n > 0) rebuild();
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 13,
                                  decoration:
                                      (isItemCancelled || displayQty <= 0)
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: (isItemCancelled || displayQty <= 0)
                                      ? AppColors.textFaint
                                      : AppColors.text,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    addedBy['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textFaint,
                                    ),
                                  ),
                                  if (cancelledQty > 0) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '($cancelledQty bekor)',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ],
                                  if (pendingCancel > 0) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '(-$pendingCancel)',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'x${isItemCancelled ? 0 : displayQty}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: (isItemCancelled || displayQty <= 0)
                                ? AppColors.textFaint
                                : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatMoney(
                            price * (isItemCancelled ? 0 : displayQty),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: (isItemCancelled || displayQty <= 0)
                                ? AppColors.textFaint
                                : AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (expanded) const SizedBox(height: 6),
          ],
        ),
      );
    }).toList();
  }

  // Cancel cart helpers
  void _addToCancelCart(
    String orderNumber,
    int productId,
    String name,
    int price,
  ) {
    int currentQty = 0;
    for (final check in _checks) {
      if (check['order_number'] == orderNumber) {
        for (final item in (check['items'] as List<dynamic>? ?? [])) {
          if ((item['product_id'] as int?) == productId) {
            currentQty = item['quantity'] as int? ?? 0;
            break;
          }
        }
      }
    }

    final existing = _cancelCart.indexWhere(
      (c) => c['order_number'] == orderNumber && c['product_id'] == productId,
    );
    final inCart = existing >= 0 ? (_cancelCart[existing]['qty'] as int) : 0;

    if (inCart >= currentQty) return;

    setState(() {
      if (existing >= 0) {
        _cancelCart[existing]['qty'] = inCart + 1;
      } else {
        _cancelCart.add({
          'order_number': orderNumber,
          'product_id': productId,
          'name': name,
          'qty': 1,
          'price': price,
        });
      }
    });
  }

  void _removeFromCancelCart(int index) {
    setState(() {
      if (_cancelCart[index]['qty'] > 1) {
        _cancelCart[index]['qty'] = (_cancelCart[index]['qty'] as int) - 1;
      } else {
        _cancelCart.removeAt(index);
      }
    });
  }

  Future<void> _submitCancel() async {
    if (_cancelCart.isEmpty) return;
    // SINXRON qo'riqchi. Tugma `_cancelling` bo'yicha bloklanadi, LEKIN u
    // modal varaq ichida chiziladi — varaq alohida route bo'lgani uchun
    // ota-ekranning `setState`i uni qayta chizmaydi. Ya'ni tugma amalda
    // hech qachon o'chmasdi va ikkinchi bosish ikkinchi so'rovni yuborardi:
    // 2 ta o'rniga 4 ta porsiya bekor bo'lardi.
    if (_cancelling) return;
    _cancelling = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekor qilishni tasdiqlash'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._cancelCart.map(
                (c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        '${c['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        '${c['qty']} ta',
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  const Text(
                    'Jami qaytariladi',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    formatMoney(_cancelCartTotal, suffix: ' so\'m'),
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Bekor qilish'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      _cancelling = false;
      return;
    }

    if (mounted) setState(() {});
    // Ro'yxatning NUSXASI bo'yicha yuriladi: so'rov davomida foydalanuvchi
    // savatni o'zgartirsa, asl ro'yxat bo'ylab iteratsiya
    // `ConcurrentModificationError` bilan ekranni yiqitardi.
    final queue = List<Map<String, dynamic>>.from(_cancelCart);
    // Muvaffaqiyatli o'tganlari kuzatiladi — xatoda BUTUN savat
    // tozalanmaydi, aks holda kassir qaysi qator o'tganini bilmay qolardi.
    final done = <Map<String, dynamic>>[];
    try {
      for (final c in queue) {
        await ApiService().cancelItem(
          c['order_number'],
          c['product_id'],
          cancelQty: c['qty'],
        );
        done.add(c);
      }
      if (mounted) {
        setState(() {
          _cancelCart.clear();
          _cancelling = false;
        });
      } else {
        _cancelling = false;
      }
      await _loadTable();
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final c in done) {
            _cancelCart.remove(c);
          }
          _cancelling = false;
        });
      } else {
        _cancelling = false;
      }
      await _loadTable();
      if (mounted) {
        String msg = 'Xatolik yuz berdi';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['message'] ?? msg;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  int get _cancelCartTotal {
    int total = 0;
    for (final c in _cancelCart) {
      total += (c['price'] as int) * (c['qty'] as int);
    }
    return total;
  }
}

// ============================================================
// Bottom action bar — context aware
// ============================================================

class _BottomBar extends StatelessWidget {
  final int cartCount;
  final int cartTotal;
  final int checksCount;
  final int grandTotal;
  final bool sending;
  final VoidCallback onCartTap;
  final VoidCallback onChecksTap;
  final VoidCallback onSubmit;
  final VoidCallback onPay;

  const _BottomBar({
    required this.cartCount,
    required this.cartTotal,
    required this.checksCount,
    required this.grandTotal,
    required this.sending,
    required this.onCartTap,
    required this.onChecksTap,
    required this.onSubmit,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final hasCart = cartCount > 0;
    final hasChecks = checksCount > 0;

    if (!hasCart && !hasChecks) {
      return Container(
        height: 56,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: const Center(
          child: Text(
            'Mahsulot tanlang',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              if (hasChecks && !hasCart)
                Expanded(
                  child: _PillButton(
                    icon: Icons.receipt_long_rounded,
                    label: '$checksCount chek',
                    value: formatMoney(grandTotal, suffix: ' so\'m'),
                    color: AppColors.primary,
                    onTap: onChecksTap,
                  ),
                ),
              if (hasCart) ...[
                if (hasChecks)
                  _IconPillButton(
                    icon: Icons.receipt_long_rounded,
                    label: '$checksCount',
                    color: AppColors.primary,
                    onTap: onChecksTap,
                  ),
                if (hasChecks) const SizedBox(width: 6),
                Expanded(
                  child: _PillButton(
                    icon: Icons.shopping_cart_rounded,
                    label: '$cartCount ta',
                    value: formatMoney(cartTotal, suffix: ' so\'m'),
                    color: AppColors.success,
                    onTap: onCartTap,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              SizedBox(
                height: 50,
                child: hasCart
                    ? FilledButton.icon(
                        onPressed: sending ? null : onSubmit,
                        icon: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: const Text(
                          'Yuborish',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: onPay,
                        icon: const Icon(Icons.payments_rounded, size: 18),
                        label: const Text(
                          'To\'lov',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_less_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IconPillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Sheet handle
// ============================================================

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

// ============================================================
// Kategoriya katakchasi (ochilgan ro'yxatda)
// ============================================================

class _CategoryTile extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.text;
    return Material(
      color: selected ? AppColors.primary : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Product card
// ============================================================

class _ProductCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool soldOut;

  /// Nofaol mahsulot (faqat super_admin/kassir ko'radi) — kulrang chiqadi,
  /// savatga qo'shilmaydi.
  final bool inactive;

  /// Shu mahsulotdan savatda nechta bor — kartochkada nishon bo'lib chiqadi
  final int inCart;

  /// Tor ekran (kichik telefon) — shrift va bo'shliqlar kichikroq
  final bool compact;
  final Widget Function() buildImage;
  final VoidCallback? onTap;

  const _ProductCard({
    required this.product,
    required this.soldOut,
    this.inactive = false,
    required this.inCart,
    required this.compact,
    required this.buildImage,
    required this.onTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  Timer? _repeatTimer;
  bool _pressed = false;

  void _startRepeat() {
    if (widget.onTap == null) return;
    widget.onTap!();
    // Nofaolda bosib turish takrorlanmaydi — har bosishda baribir faqat
    // ogohlantirish chiqadi.
    if (widget.inactive) return;
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 130),
      (_) => widget.onTap?.call(),
    );
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPressStart: disabled
          ? null
          : (_) {
              setState(() => _pressed = true);
              _startRepeat();
            },
      onLongPressEnd: disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              _stopRepeat();
            },
      onLongPressCancel: disabled
          ? null
          : () {
              setState(() => _pressed = false);
              _stopRepeat();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: AppDuration.fast,
        child: Opacity(
          opacity: widget.soldOut || widget.inactive ? 0.5 : 1.0,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: _pressed
                        ? AppColors.primary
                        : widget.inCart > 0
                        ? AppColors.success.withValues(alpha: 0.55)
                        : AppColors.border,
                    width: _pressed || widget.inCart > 0 ? 1.4 : 1,
                  ),
                ),
                padding: EdgeInsets.all(widget.compact ? 5 : 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: widget.buildImage()),
                    SizedBox(height: widget.compact ? 4 : 5),
                    // Nom ikki qatorgacha — «Ice Matcha Strawberry» kabi
                    // uzun nomlar ilgari bir qatorda kesilib ketardi va
                    // ikki mahsulotni farqlab bo'lmasdi. Blok balandligi
                    // QAT'IY: aks holda qisqa nomli kartochkada narx
                    // yuqoriga siljib, qator tekis ko'rinmasdi.
                    SizedBox(
                      height: (widget.compact ? 11 : 12.5) * 1.18 * 2,
                      child: Text(
                        menuName(widget.product['name']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: widget.compact ? 11 : 12.5,
                          height: 1.18,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(widget.product['price']),
                      maxLines: 1,
                      style: TextStyle(
                        color: widget.soldOut || widget.inactive
                            ? AppColors.textFaint
                            : AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: widget.compact ? 12 : 13.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // Savatdagi miqdor — kassir nechta bosganini ko'rib tursin
              if (widget.inCart > 0)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: AppShadows.coloredGlow(
                        AppColors.success,
                        opacity: 0.35,
                      ),
                    ),
                    child: Text(
                      '${widget.inCart}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Cart tile (in cart sheet)
// ============================================================

/// Savatdagi bitta qator.
///
/// ILGARI: qatorning ISTALGAN joyiga tegish miqdorni kamaytirardi va
/// buni hech narsa ko'rsatib turmasdi — ro'yxatni aylantirmoqchi bo'lgan
/// kassir bexosdan mahsulotni o'chirib yuborardi, oshirish uchun esa
/// orqaga qaytib menyudan qidirish kerak edi. Endi «− 3 +» boshqaruvi:
/// amal ko'rinib turadi, oshirish ham shu yerda.
class _CartTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;

  const _CartTile({
    required this.item,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  @override
  State<_CartTile> createState() => _CartTileState();
}

class _CartTileState extends State<_CartTile> {
  Timer? _timer;

  // Mahsulot kartasi bosilganda + bo'lgani kabi, chek qatori bosilganda −.
  // Bosib turilsa KStepper'dagidek takrorlanib kamayadi.
  void _startRepeat() {
    widget.onDecrement();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => widget.onDecrement(),
    );
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    final qty = c['quantity'] as int? ?? 0;
    final price = c['price'] as int? ?? 0;
    final line = price * qty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDecrement,
      onLongPressStart: (_) => _startRepeat(),
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${c['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Joy tor bo'lsa (planshetdagi yon panel) faqat qator
                  // summasi qoladi: ilgari «7 000 × 2  14 000 so'm»
                  // sig'may, qizil overflow chizig'i chiqardi.
                  LayoutBuilder(
                    builder: (ctx, c) {
                      final total = Text(
                        formatMoney(line, suffix: ' so\'m'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMuted,
                        ),
                      );
                      if (c.maxWidth < 200) return total;
                      return Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${formatMoney(price)} × $qty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textFaint,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: total),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            KStepper(
              value: qty,
              onDecrement: widget.onDecrement,
              onIncrement: widget.onIncrement,
              height: 32,
            ),
            // Butun qatorni bir bosishda olib tashlash
            IconButton(
              onPressed: widget.onRemove,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              icon: const Icon(
                Icons.close_rounded,
                size: 17,
                color: AppColors.textFaint,
              ),
              tooltip: 'O\'chirish',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ARALASH TO'LOV (split payment) dialogi
// ============================================================
//
// Bitta oddiy ro'yxat: har bir usul qatorida summa maydoni. Kassir kerakli
// usullarga summani yozadi, xolos. Ilgarigi «1-to'lov / 2-to'lov», har
// qatorda chip tanlash, qator qo'shish/o'chirish va ikki rejim («Oddiy» /
// «Boshqa kombinatsiya») tushunarsiz edi — olib tashlandi.
//
// Usul tugmasi bosilsa qoldiq o'zi yoziladi (maydon to'la bo'lsa —
// tozalaydi). To'lov faqat pastdagi «To'lash» tugmasi bilan o'tadi
// (xato summa yozilganda tasdiqsiz yopilib ketmasligi uchun).

class _SplitPaymentDialog extends StatefulWidget {
  final int total;
  const _SplitPaymentDialog({required this.total});

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  static const _methods = kPaymentMethods;

  // Backend qoidasi: 2..3 ta usul, har biri > 0, yig'indi == jami
  static const _minParts = 2;
  static const _maxParts = 3;

  final Map<String, TextEditingController> _amounts = {
    for (final m in _methods) m.$1: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  // parseIntField: maydon "1 200 000" ko'rinishida formatlanadi,
  // int.tryParse probel ko'rsa null qaytarib summani nolga tushirardi.
  int _amountOf(String method) => parseIntField(_amounts[method]!.text) ?? 0;

  List<(String, String, IconData, Color)> get _used =>
      _methods.where((m) => _amountOf(m.$1) > 0).toList();

  int get _sum => _used.fold(0, (s, m) => s + _amountOf(m.$1));
  int get _remainder => widget.total - _sum;

  bool get _canPay =>
      _remainder == 0 && _used.length >= _minParts && _used.length <= _maxParts;

  // Qoldiqni maydonga yozadi. Matn butunlay belgilangan holda qoladi —
  // kassir boshqa summa yozmoqchi bo'lsa, tozalamasdan to'g'ridan-to'g'ri
  // teradi (yozilgan raqam avtomatik summaning o'rnini bosadi).
  void _fillRemainder(String method) {
    final t = formatMoney(_remainder);
    _amounts[method]!.value = TextEditingValue(
      text: t,
      selection: TextSelection(baseOffset: 0, extentOffset: t.length),
    );
  }

  // Usul tugmasi: maydon bo'sh bo'lsa qoldiqni yozadi, to'la bo'lsa
  // tozalaydi. Klaviatura ataylab ochilmaydi — faqat maydon bosilganda.
  void _tapMethod(String method) {
    setState(() {
      if (_amountOf(method) > 0) {
        _amounts[method]!.clear();
      } else if (_remainder > 0) {
        _fillRemainder(method);
      }
    });
  }

  // Summa maydoniga bosilganda ham xuddi shunday: bo'sh bo'lsa qoldiq
  // o'zi yoziladi (kassir 44 000 ni qo'lda termaydi).
  void _tapField(String method) {
    if (_amountOf(method) == 0 && _remainder > 0) {
      setState(() => _fillRemainder(method));
    }
  }

  Widget _totalBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'To\'lanadigan jami',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          Text(
            formatMoney(widget.total, suffix: ' so\'m'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodRow((String, String, IconData, Color) m) {
    final active = _amountOf(m.$1) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 156,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => _tapMethod(m.$1),
              icon: Icon(
                m.$3,
                size: 20,
                color: active ? m.$4 : AppColors.textFaint,
              ),
              label: Text(
                m.$2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: active ? AppColors.text : AppColors.textMuted,
                backgroundColor: active ? AppColors.primarySoft : null,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(
                  color: active ? AppColors.primary : AppColors.border,
                  width: active ? 2 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 50,
              child: TextField(
                controller: _amounts[m.$1],
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInputFormatter()],
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.text : AppColors.textMuted,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0',
                  hintStyle: const TextStyle(color: AppColors.textGhost),
                  // Bo'sh maydon fokusda "0so'm" bo'lib qolmasin —
                  // suffiks faqat summa bor bo'lganda
                  suffixText: active ? 'so\'m' : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onTap: () => _tapField(m.$1),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Pastdagi holat qatori: qoldiq / ortiqcha / tayyor taqsimot.
  // Kassir «To'lash» nima uchun o'chiqligini shu yerdan darhol ko'radi.
  Widget _statusBox() {
    final used = _used;
    final Color color;
    final Color bg;
    final IconData icon;
    final String title;
    String? hint;

    if (used.length > _maxParts) {
      color = AppColors.danger;
      bg = AppColors.dangerTint;
      icon = Icons.error_outline_rounded;
      title = 'Ko\'pi bilan $_maxParts ta usul';
      hint = 'Ortiqcha usulning summasini o\'chiring';
    } else if (_remainder > 0) {
      color = AppColors.warning;
      bg = AppColors.warningTint;
      icon = Icons.hourglass_bottom_rounded;
      title = 'Qoldiq: ${formatMoney(_remainder, suffix: ' so\'m')}';
      hint = used.length >= _maxParts
          ? 'Summalarni to\'g\'rilang'
          : 'Keyingi usulni bossangiz qoldiq o\'zi yoziladi';
    } else if (_remainder < 0) {
      color = AppColors.danger;
      bg = AppColors.dangerTint;
      icon = Icons.error_outline_rounded;
      title = 'Ortiqcha: ${formatMoney(-_remainder, suffix: ' so\'m')}';
      hint = 'Yig\'indi jamidan oshib ketdi';
    } else if (used.length < _minParts) {
      color = AppColors.warning;
      bg = AppColors.warningTint;
      icon = Icons.info_outline_rounded;
      title = 'Kamida $_minParts ta usul kerak';
      hint = 'Bitta usul bo\'lsa oddiy to\'lovdan foydalaning';
    } else {
      color = AppColors.success;
      bg = AppColors.successTint;
      icon = Icons.check_circle_rounded;
      title = used
          .map((m) => '${m.$2} ${formatMoney(_amountOf(m.$1))}')
          .join('  +  ');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.call_split_rounded, size: 20, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Aralash to\'lov'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _totalBox(),
              const SizedBox(height: 10),
              const Text(
                'Har bir usulga qancha to\'lanishini yozing',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              ..._methods.map(_methodRow),
              const SizedBox(height: 4),
              _statusBox(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: _canPay
              ? () => Navigator.pop(
                  context,
                  _used
                      .map(
                        (m) => <String, dynamic>{
                          'method': m.$1,
                          'amount': _amountOf(m.$1),
                        },
                      )
                      .toList(),
                )
              : null,
          child: const Text('To\'lash'),
        ),
      ],
    );
  }
}

// ============================================================
// Chrome uslubidagi tablar — bir vaqtda bir nechta stol ochish
// ============================================================

/// Tab qatoridagi bitta yozuv (stol yoki saboy/dostafka buyurtmasi).
class OrderTabInfo {
  final String? tableSKU;
  final String label;
  const OrderTabInfo({required this.tableSKU, required this.label});
}

/// OrderScreen tab qatorini chizish va boshqarish uchun hostga shu
/// interfeys orqali murojaat qiladi.
abstract class OrderTabsController {
  List<OrderTabInfo> get tabs;
  int get activeIndex;

  /// Stol allaqachon tab sifatida ochiqmi
  bool isOpen(String sku);

  void selectTab(int index);

  /// Stolni yangi tab qilib ochadi; allaqachon ochiq bo'lsa — faollashtiradi
  void requestAddTable(Map<String, dynamic> table);

  /// Tabni «×» orqali yopish — savatda yuborilmagan qator bo'lsa so'raydi
  Future<void> requestCloseTab(int index);

  /// «Yopish» tugmasi — barcha tablarni yopib stollar ekraniga qaytadi
  Future<void> requestCloseAll();

  /// Tabni SO'ROQSIZ yopish — to'lov yoki yuborishdan keyin ekranning
  /// o'zi chaqiradi (savat allaqachon bo'sh yoki qasddan tashlangan)
  void closeTabFor(State<OrderScreen> state);

  /// Tabning stolini almashtirish (stol raqami o'zgarganda) — server
  /// tomonida cheklar allaqachon ko'chirilgan bo'ladi
  void changeTabTable(State<OrderScreen> state, String sku, String label);
}

class _OrderTab {
  // Stol almashtirilganda (changeTabTable) shu ikkala maydon yangilanadi,
  // shuning uchun final emas
  String? tableSKU;
  String label;
  final Map<String, dynamic>? order;
  final String orderType;
  final GlobalKey<_OrderScreenState> key = GlobalKey<_OrderScreenState>();
  _OrderTab({
    required this.tableSKU,
    required this.label,
    this.order,
    this.orderType = 'dine_in',
  });
}

/// Bir nechta OrderScreen'ni Chrome tablari kabi ushlab turadigan host.
/// IndexedStack ishlatilgani uchun tab almashtirilganda har bir stolning
/// holati (savat, cheklar, qidiruv) YO'QOLMAYDI.
class OrderTabsScreen extends StatefulWidget {
  final String? tableSKU;
  final String tableLabel;
  final Map<String, dynamic>? order;
  final String orderType;

  const OrderTabsScreen({
    super.key,
    this.tableSKU,
    required this.tableLabel,
    this.order,
    this.orderType = 'dine_in',
  });

  @override
  State<OrderTabsScreen> createState() => _OrderTabsScreenState();
}

class _OrderTabsScreenState extends State<OrderTabsScreen>
    implements OrderTabsController {
  final List<_OrderTab> _tabs = [];
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _tabs.add(
      _OrderTab(
        tableSKU: widget.tableSKU,
        label: widget.tableLabel,
        order: widget.order,
        orderType: widget.orderType,
      ),
    );
  }

  @override
  List<OrderTabInfo> get tabs => [
    for (final t in _tabs) OrderTabInfo(tableSKU: t.tableSKU, label: t.label),
  ];

  @override
  int get activeIndex => _active;

  @override
  bool isOpen(String sku) => _tabs.any((t) => t.tableSKU == sku);

  @override
  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _active) return;
    setState(() => _active = index);
  }

  @override
  void requestAddTable(Map<String, dynamic> table) {
    final sku = (table['sku'] ?? '').toString();
    if (sku.isEmpty) return;
    final existing = _tabs.indexWhere((t) => t.tableSKU == sku);
    if (existing >= 0) {
      selectTab(existing);
      return;
    }
    setState(() {
      _tabs.add(
        _OrderTab(tableSKU: sku, label: (table['label'] ?? sku).toString()),
      );
      _active = _tabs.length - 1;
    });
  }

  /// Tab o'chirilganda faol indeksni to'g'rilab qo'yish
  void _removeTabAt(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_active >= index && _active > 0) _active--;
      if (_active >= _tabs.length) _active = _tabs.length - 1;
    });
  }

  /// Host allaqachon yopilganmi — «hammasini yuborish»da oxirgi tab o'zini
  /// yopganda host ham pop bo'ladi; keyin yana pop qilinsa ostidagi
  /// stollar ekrani ham yopilib ketardi.
  bool _popped = false;

  void _popHost() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.pop(context);
  }

  @override
  Future<void> requestCloseTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    // Dialog ochiq turganda ro'yxat o'zgarishi mumkin (masalan, to'lov
    // tugab tab o'zi yopilsa) — shuning uchun indeks emas, tab'ning o'zi
    // eslab qolinadi va keyin qayta topiladi
    final tab = _tabs[index];
    final st = tab.key.currentState;
    final cartCount = st?._cart.length ?? 0;
    // Savat dialogida «Tashlab yopish» tanlansa yopish allaqachon
    // tasdiqlangan bo'ladi — ketma-ket ikkinchi dialog chiqarilmaydi
    var alreadyConfirmed = false;
    if (cartCount > 0) {
      // Kassir nimani tashlayotganini ko'rib tursin — avval o'sha tabga
      // o'tamiz, keyin so'raymiz
      if (_active != index) setState(() => _active = index);
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Savatda yozilmagan mahsulot bor'),
          content: Text(
            '${tab.label}: $cartCount ta qator hali yuborilmagan. '
            'Nima qilamiz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'stay'),
              child: const Text('Qolaman'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Tashlab yopish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'send'),
              child: const Text('Yuborish'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == 'stay') return;
      if (action == 'send') {
        // Muvaffaqiyatli yuborilganda tab o'zini yopadi; xato bo'lsa
        // savat va tab joyida qoladi, snackbar chiqadi
        await tab.key.currentState?._submitOrder();
        return;
      }
      alreadyConfirmed = true;
    }
    // Yuborilgan buyurtmasi bor tab — kassir NIMANI yopayotganini darhol
    // ko'rib tasdiqlasin (butun chip yopish tugmasi bo'lgani uchun
    // tasodifiy bosishdan himoya). Tab yopilganda buyurtma bekor
    // bo'lmaydi — stol band qolaveradi.
    if (!alreadyConfirmed) {
      final items = st?._mergedCheckItems() ?? const [];
      if (items.isNotEmpty) {
        // Kassir nimani yopayotganini ko'rib tursin
        if (_active != index) setState(() => _active = index);
        final ok = await _confirmCloseTabWithChecks(
          tab.label,
          items,
          st?._grandTotal ?? 0,
        );
        if (!mounted || !ok) return;
      }
    }
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    if (_tabs.length == 1) {
      _popHost();
      return;
    }
    _removeTabAt(i);
  }

  /// Yuborilgan buyurtmasi bor tabni yopishdan oldingi tasdiqlash —
  /// dialogda darhol mahsulotlar ro'yxati va jami summa ko'rinadi.
  Future<bool> _confirmCloseTabWithChecks(
    String label,
    List<Map<String, dynamic>> items,
    int total,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label — tab yopilsinmi?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${e['name']} x${e['quantity']}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                formatMoney(e['total'] as int),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Jami',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    formatMoney(total, suffix: ' so\'m'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Buyurtma bekor bo\'lmaydi — stol band qolaveradi.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Qolaman'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yopish'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Future<void> requestCloseAll() async {
    // Yakka tab — eski xatti-harakat aynan saqlanadi (Yuborish varianti
    // bilan dialog ham shu yerdan chiqadi)
    if (_tabs.length == 1) {
      await _tabs.single.key.currentState?._handleClose();
      return;
    }
    final dirtyTabs = [
      for (final t in _tabs)
        if (t.key.currentState?._cart.isNotEmpty ?? false) t,
    ];
    if (dirtyTabs.isEmpty) {
      _popHost();
      return;
    }
    final labels = dirtyTabs.map((t) => t.label).join(', ');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yuborilmagan mahsulotlar bor'),
        content: Text(
          '$labels: savatda hali yuborilmagan qatorlar bor. Nima qilamiz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Qolaman'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Tashlab yopish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'send'),
            child: const Text('Hammasini yuborish'),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == 'stay') return;
    if (action == 'discard') {
      _popHost();
      return;
    }
    await _sendAllAndClose(dirtyTabs);
  }

  /// Barcha savati bor tablarni birma-bir oshxonaga yuboradi.
  /// Muvaffaqiyatli yuborilgan tab o'zini yopadi; hammasi ketgach qolgan
  /// (bo'sh) tablar ham yopilib, stollar ekraniga qaytiladi. Birortasi
  /// yuborilmay qolsa ekran ochiq qoladi — kassir xatoni ko'rib, o'sha
  /// stolda qayta urinadi.
  Future<void> _sendAllAndClose(List<_OrderTab> dirtyTabs) async {
    for (final t in dirtyTabs) {
      final st = t.key.currentState;
      if (st == null) continue;
      await st._submitOrder();
      // Tab hali ro'yxatda va savati bo'sh emas — yuborish yiqilgan
      if (_tabs.contains(t) &&
          (t.key.currentState?._cart.isNotEmpty ?? false)) {
        final i = _tabs.indexOf(t);
        if (mounted && i >= 0 && _active != i) {
          setState(() => _active = i);
        }
        return;
      }
    }
    _popHost();
  }

  @override
  void closeTabFor(State<OrderScreen> state) {
    final i = _tabs.indexWhere((t) => t.key.currentState == state);
    if (i < 0) return;
    if (_tabs.length == 1) {
      _popHost();
      return;
    }
    _removeTabAt(i);
  }

  @override
  void changeTabTable(State<OrderScreen> state, String sku, String label) {
    final i = _tabs.indexWhere((t) => t.key.currentState == state);
    if (i < 0) return;
    setState(() {
      _tabs[i].tableSKU = sku;
      _tabs[i].label = label;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Sistem «orqaga» si (iOS chetdan surish, Android tugmasi) «Yopish»
      // bilan bir xil: avval yuborilmagan savatlar tekshiriladi
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) requestCloseAll();
      },
      child: IndexedStack(
        index: _active,
        children: [
          for (final t in _tabs)
            OrderScreen(
              key: t.key,
              tableSKU: t.tableSKU,
              tableLabel: t.label,
              order: t.order,
              orderType: t.orderType,
              tabsHost: this,
            ),
        ],
      ),
    );
  }
}

/// To'lov oynasidagi bitta usul kartochkasi: rangli doira ichida ikonka,
/// ostida nom.
class _PayMethodCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool highlighted;
  final VoidCallback onTap;

  const _PayMethodCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: highlighted ? AppColors.primarySoft : AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: highlighted ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? AppColors.primary : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
