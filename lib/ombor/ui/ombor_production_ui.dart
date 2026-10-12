// ombor/ui/ombor_production_ui.dart — Ombor: skladiga kelgan ishlab chiqarish buyurtmalari ro'yxati:
// OmborProductionUi (OmborProductionProvider). Real-time socket bilan yangilanadi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/catalog/catalog_repository.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/ombor/services/ombor_service.dart';
import 'package:uz_ai_dev/production/provider/production_orders_provider.dart';
import 'package:uz_ai_dev/production/provider/stock_provider.dart';
import 'package:uz_ai_dev/production/ui/widgets/production_order_widgets.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/ui/shef_home_ui.dart' show productionStatusChip;

// Ombor: o'z skladiga kelgan ishlab chiqarish buyurtmalari ro'yxati.
// Har karta: order_id, sana, shef nomi, mahsulotlar qisqacha, status chip.
class OmborProductionUi extends StatefulWidget {
  const OmborProductionUi({super.key});

  @override
  State<OmborProductionUi> createState() => _OmborProductionUiState();
}

class _OmborProductionUiState extends State<OmborProductionUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

  OmborProductionProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<OmborProductionProvider>();
      provider.fetchOrders();
      // Real-time: shef yangi buyurtma berganda ro'yxat refresh'siz yangilanadi.
      provider.connectSocket();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose() ichida context.read() xavfsiz emas — referensni saqlaymiz.
    _provider = context.read<OmborProductionProvider>();
  }

  @override
  void dispose() {
    _provider?.disconnectSocket();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Ishlab chiqarish',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<OmborProductionProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.orders.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.errorMessage != null && provider.orders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.fetchOrders(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: _accentColor,
            onRefresh: () => provider.fetchOrders(),
            child: provider.orders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 160),
                      Center(
                        child: Text(
                          'Hozircha ishlab chiqarish buyurtmalari yo\'q',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: provider.orders.length,
                    itemBuilder: (context, index) {
                      final order = provider.orders[index];
                      return ProductionOrderCard(
                        order: order,
                        showShef: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OmborProductionDetailUi(orderId: order.id),
                            ),
                          );
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

// Buyurtma tafsiloti: har mahsulot, har bo'lim uchun masalliqlar jadvali
// (nomi | kerak | qoldiq | yetadimi) va «Berdim» tugmasi. Rad etilgan bo'lim
// qizil, izoh bilan — qayta «Berdim» mumkin.
class OmborProductionDetailUi extends StatefulWidget {
  final int orderId;

  const OmborProductionDetailUi({super.key, required this.orderId});

  @override
  State<OmborProductionDetailUi> createState() =>
      _OmborProductionDetailUiState();
}

class _OmborProductionDetailUiState extends State<OmborProductionDetailUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);

  // Qoldiq qaysi sklad uchun yuklangan (order kelgach bir marta).
  int? _stockLoadedFor;

  // «Yetishmaganidan buyurtma» yuborilayotganda tugma spinner'i.
  bool _orderingShort = false;

  // Ishlab chiqariladigan mahsulotlar (tex kartali, полуфабрикат ham shu
  // yerda) id'lari — «Yetishmaganidan buyurtma» ularni CHIQARIB tashlaydi:
  // biskvit sotib olinmaydi, ishlab chiqariladi. Xatoda bo'sh qoladi
  // (eski xatti-harakat).
  Set<int> _producedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OmborProductionProvider>().refreshOrder(widget.orderId);
      _ensureStock();
      _loadProducedIds();
    });
  }

  // Ishlab chiqariladigan (пф / tayyor) mahsulot id'lari — «Yetishmaganidan
  // buyurtma» oqimida pf qatorlarini chiqarib tashlash uchun. Katalog
  // CatalogRepository'dan (GET /api/products): rolga qarab server pf'larni
  // yubormasligi mumkin — unda to'plam bo'sh qoladi va oqim avvalgidek ishlaydi.
  Future<void> _loadProducedIds() async {
    try {
      final products = await sl<CatalogRepository>().load();
      if (!mounted) return;
      setState(() => _producedIds = {
            for (final p in products)
              if (p.kind != ProductKind.raw) p.id
          });
    } catch (_) {
      // Jim — pf ajratib bo'lmasa, oqim avvalgidek ishlayveradi.
    }
  }

  // Buyurtma skladining qoldig'ini yuklash (order hali kelmagan bo'lsa
  // build'dagi Consumer keyingi kadrda yana chaqiradi).
  void _ensureStock() {
    final order =
        context.read<OmborProductionProvider>().orderById(widget.orderId);
    if (order == null || order.skladId == 0) return;
    if (_stockLoadedFor == order.skladId) return;
    _stockLoadedFor = order.skladId;
    final stock = context.read<StockProvider>();
    if (stock.stockFor(order.skladId) == null) {
      stock.fetchStock(order.skladId);
    } else {
      stock.refreshSilently(order.skladId);
    }
  }

  Future<void> _refreshAll() async {
    final provider = context.read<OmborProductionProvider>();
    await provider.refreshOrder(widget.orderId);
    final order = provider.orderById(widget.orderId);
    if (order != null && order.skladId != 0 && mounted) {
      await context.read<StockProvider>().refreshSilently(order.skladId);
    }
  }

  void _snack(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // «Berdim»: tasdiq dialogi (qoldiq yetmasa ogohlantirish bilan), keyin
  // issue + qoldiqni yangilash.
  Future<void> _issue(ProductionItem item, int pi, int si) async {
    final provider = context.read<OmborProductionProvider>();
    final stockProvider = context.read<StockProvider>();
    final order = provider.orderById(widget.orderId);
    if (order == null) return;

    final stage = item.stages[si];
    final shorts = shortIngredients(
      stage,
      (productId) => stockProvider.qtyFor(order.skladId, productId),
    );
    final unlinked =
        stage.ingredients.where((i) => !i.linked).toList(growable: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Berdim — tasdiqlash',
            style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.name}\n${si + 1}-bo\'lim: ${stage.name}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bo\'lim masalliqlari skladdan chiqim qilinadi.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            if (shorts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Qoldiq yetmaydi:\n'
                '${shorts.map((i) => '• ${i.name}').join('\n')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Qoldiq manfiyga tushishi mumkin. Baribir berilsinmi?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
            if (unlinked.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Qoldiqqa bog\'lanmagan (chiqim qilinmaydi):\n'
                '${unlinked.map((i) => '• ${i.name}').join('\n')}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: shorts.isEmpty ? Colors.green : Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Berdim'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await provider.issueStage(widget.orderId, pi, si);
    if (!mounted) return;
    if (err != null) {
      _snack(err);
      return;
    }
    _snack('Masalliq berildi', error: false);
    // Chiqim qoldiqni o'zgartirdi — qoldiqni jim yangilaymiz.
    final fresh = provider.orderById(widget.orderId);
    if (fresh != null && fresh.skladId != 0) {
      stockProvider.refreshSilently(fresh.skladId);
    }
  }

  // F2. «Yetishmaganidan buyurtma»: berilmagan/rad etilgan bo'limlardagi
  // bog'langan masalliqlar bo'yicha short = kerak − qoldiq > 0 bo'lganlarga
  // mavjud POST /api/orders orqali oddiy sklad-buyurtma yaratadi.
  Future<void> _orderShortage() async {
    final provider = context.read<OmborProductionProvider>();
    final stockProvider = context.read<StockProvider>();
    final order = provider.orderById(widget.orderId);
    if (order == null || _orderingShort) return;

    // Kutilayotgan bo'limlar bo'yicha mahsulotga jamlangan ehtiyoj.
    final need = <int, double>{};
    final names = <int, String>{};
    final units = <int, String>{};
    for (final item in order.items) {
      for (final stage in item.stages) {
        final pending = stage.materialStatus == MaterialStatus.none ||
            stage.materialStatus == MaterialStatus.radEtildi;
        if (!pending) continue;
        for (final ing in stage.ingredients) {
          if (!ing.linked || ing.productId == 0) continue;
          need[ing.productId] = (need[ing.productId] ?? 0) + ing.stockAmount;
          names[ing.productId] = ing.name;
          units[ing.productId] = ing.stockUnit;
        }
      }
    }

    // short = kerak − qoldiq (yozuv yo'q — 0). кг/л (API'da butun gramm/ml)
    // uchun BUTUN birlikka, boshqa birliklar uchun 2 xonaga yuqoriga
    // yaxlitlash (epsilon — float shovqini ortiqcha qo'shmasligi uchun).
    // Полуфабрикат (ishlab chiqariladigan) qatorlar sklad-buyurtmaga
    // KIRMAYDI — ular alohida ro'yxatda faqat eslatma sifatida ko'rinadi.
    final shorts = <int, double>{};
    final pfShorts = <int, double>{};
    need.forEach((pid, total) {
      final qoldiq = stockProvider.qtyFor(order.skladId, pid) ?? 0;
      final short = total - qoldiq;
      if (short > 0) {
        final rounded = qtyUnitFactor(units[pid]) == 1000
            ? (short - 1e-9).ceilToDouble()
            : (short * 100 - 1e-9).ceilToDouble() / 100;
        if (_producedIds.contains(pid)) {
          pfShorts[pid] = rounded;
        } else {
          shorts[pid] = rounded;
        }
      }
    });

    if (shorts.isEmpty && pfShorts.isEmpty) {
      _snack('Hammasi yetarli', error: false);
      return;
    }

    // Faqat полуфабрикат yetishmayapti — buyurtma yaratilmaydi, eslatma.
    if (shorts.isEmpty) {
      final pfEntries = pfShorts.entries.toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Yetishmaganidan buyurtma',
              style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sotib olinadigan masalliqlar yetarli. Faqat полуфабрикат '
                'yetishmayapti — u ishlab chiqariladi, sklad-buyurtma '
                'qilinmaydi:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              for (final e in pfEntries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${names[e.key]} — yetishmayapti '
                            '${formatQty(e.value, units[e.key])} '
                            '${units[e.key] ?? ''} '
                            '(полуфабрикат — ishlab chiqariladi)'
                        .trim(),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final entries = shorts.entries.toList();
    final pfEntries = pfShorts.entries.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Yetishmaganidan buyurtma',
            style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quyidagi masalliqlarga sklad-buyurtma yaratiladi:',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      // Qiymat API birlikda (кг/литр -> gramm) — UI'da kg.
                      '• ${names[e.key]} — yetishmayapti '
                      '${formatQty(e.value, units[e.key])} ${units[e.key] ?? ''}'
                          .trim(),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Jami: ${entries.length} ta mahsulot',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                // Полуфабрикат qatorlar buyurtmaga kirmaydi — eslatma.
                if (pfEntries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Buyurtmaga kirmaydi (полуфабрикат — ishlab chiqariladi):',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  for (final e in pfEntries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${names[e.key]} — yetishmayapti '
                                '${formatQty(e.value, units[e.key])} '
                                '${units[e.key] ?? ''}'
                            .trim(),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _orderingShort = true);
    try {
      // short qiymatlari allaqachon API birlikda (кг/л -> gramm) — butun
      // qiymat kasrsiz yuboriladi.
      final orderId = await OmborService().submitOrderReturningId([
        for (final e in entries)
          {
            'product_id': e.key,
            'count': e.value % 1 == 0 ? e.value.toInt() : e.value,
          },
      ]);
      if (!mounted) return;
      _snack('Buyurtma yaratildi: $orderId', error: false);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _orderingShort = false);
    }
  }

  // «Berdim» tugmasi: material_status "" yoki rad_etildi bo'lganda.
  // (Consumer2 provider o'zgarishida butun body'ni qayta quradi, shuning
  // uchun bu yerda read yetarli.)
  Widget? _stageAction(ProductionItem item, int pi, int si) {
    final provider = context.read<OmborProductionProvider>();
    final stage = item.stages[si];
    final canIssue = stage.materialStatus == MaterialStatus.none ||
        stage.materialStatus == MaterialStatus.radEtildi;
    if (!canIssue) return null;

    final busy = provider.busyStageKey ==
        OmborProductionProvider.stageKey(widget.orderId, pi, si);
    if (busy) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Boshqa bo'limda amal ketayotgan bo'lsa tugma o'chiq turadi.
    final anyBusy = provider.busyStageKey != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: anyBusy ? null : () => _issue(item, pi, si),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.outbox_outlined, size: 18),
        label: Text(
          stage.materialStatus == MaterialStatus.radEtildi
              ? 'Qayta berdim'
              : 'Berdim',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<OmborProductionProvider, StockProvider>(
      builder: (context, provider, stockProvider, child) {
        final order = provider.orderById(widget.orderId);
        // Order endi keldi-yu qoldiq hali yuklanmagan bo'lishi mumkin.
        if (order != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _ensureStock();
          });
        }

        return Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            backgroundColor: _bgColor,
            elevation: 0,
            title: Text(
              order == null || order.orderId.isEmpty
                  ? 'Buyurtma'
                  : order.orderId,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            actions: [
              if (order != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: productionStatusChip(order.status)),
                ),
            ],
          ),
          body: order == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : Column(
                  children: [
                    // F2: yetishmagan masalliqlarga sklad-buyurtma.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _orderingShort ? null : _orderShortage,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kProductionAccent,
                            side: const BorderSide(color: kProductionAccent),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: _orderingShort
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('Yetishmaganidan buyurtma'),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshAll,
                        child: ProductionOrderDetailBody(
                          order: order,
                          stockQtyOf: (productId) =>
                              stockProvider.qtyFor(order.skladId, productId),
                          stageAction: _stageAction,
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
