// ombor/ui/ombor_category_products_ui.dart — Ombor: bitta kategoriya bozor mahsulotlari grid ekrani:
// OmborCategoryProductsUi (OmborProvider + StockProvider). ensureOmborStock() qoldiq keshini yuklaydi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/ombor/models/ombor_product_model.dart';
import 'package:uz_ai_dev/ombor/provider/ombor_provider.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';
import 'package:uz_ai_dev/production/provider/stock_provider.dart';

// Ombor skladlari qoldig'ini yuklab qo'yish: avval skladlar ro'yxati
// (SharedPreferences), keyin har sklad uchun GET /api/stock. Faqat HALI
// yuklanmagan sklad so'raladi — qayta build'da takroriy so'rov ketmaydi.
// Kartochkadagi «Qoldiq» qatori shu keshdan o'qiydi.
Future<void> ensureOmborStock(BuildContext context) async {
  final ombor = context.read<OmborProvider>();
  await ombor.ensureSklads();
  if (!context.mounted) return;
  final stock = context.read<StockProvider>();
  for (final id in ombor.skladIds) {
    if (stock.stockFor(id) == null && !stock.isLoading(id)) {
      stock.fetchStock(id);
    }
  }
}

// Bitta kategoriya ichidagi bozor mahsulotlari — user panelidagi
// ProductsScreen kabi GRID ko'rinishda.
class OmborCategoryProductsUi extends StatefulWidget {
  final String categoryName;
  const OmborCategoryProductsUi({super.key, required this.categoryName});

  @override
  State<OmborCategoryProductsUi> createState() =>
      _OmborCategoryProductsUiState();
}

class _OmborCategoryProductsUiState extends State<OmborCategoryProductsUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);

  @override
  void initState() {
    super.initState();
    // Kartochkalardagi «Qoldiq» qatori uchun (kesh bor bo'lsa so'rov ketmaydi).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ensureOmborStock(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: Text(widget.categoryName),
      ),
      // Selector (Consumer emas): grid faqat MAHSULOTLAR ro'yxati
      // o'zgarganda qayta quriladi. Consumer bo'lganida savatga har «+»
      // bosilganda (addToCart -> notifyListeners) butun GridView, ya'ni
      // ekrandagi hamma kartochka qaytadan quriladi — kartochkalarning o'zi
      // esa savat holatini ichkarida allaqachon kuzatadi.
      body: Selector<OmborProvider, List<OmborProduct>>(
        selector: (_, provider) =>
            provider.productsByCategory[widget.categoryName] ?? const [],
        builder: (context, products, child) {
          if (products.isEmpty) {
            return const Center(child: Text('Mahsulotlar topilmadi'));
          }

          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) =>
                OmborProductCard(product: products[index], isGrid: true),
          );
        },
      ),
      bottomNavigationBar: const OmborCartBar(),
    );
  }
}

// Pastdagi savat paneli: nechta mahsulot tanlangani + "Buyurtma berish".
class OmborCartBar extends StatelessWidget {
  const OmborCartBar({super.key});

  static const Color _accentColor = Color(0xFFC5A97B);

  Future<void> _submit(BuildContext context, OmborProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await provider.submitOrder();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Buyurtma yuborildi' : message),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<OmborProvider>(
      builder: (context, provider, child) {
        if (provider.cartItemCount == 0) {
          return const SizedBox.shrink();
        }

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${provider.cartItemCount} ta mahsulot',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Jami: ${formatMilli(provider.cartTotalMilli)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed:
                      provider.isSubmitting ? null : () => provider.clearCart(),
                  child: const Text(
                    'Tozalash',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: provider.isSubmitting
                      ? null
                      : () => _submit(context, provider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  child: provider.isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Buyurtma berish'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// User panelidagi mahsulot kartochkasi uslubi: rasm tepada, nomi, pastda
// "Qo'shish" yoki -/+ miqdor tugmasi.
// - kartochka bosilsa: bir qadam qo'shiladi
// - uzoq bosilsa: miqdorni qo'lda kiritish oynasi
// - rasm bosilsa: rasm katta ochiladi
// Ko'p manbali mahsulot (Samarqand + Toshkent): pastda har manba uchun
// alohida qator («Samarqand [- 5 кг +]») — har manbaning miqdori alohida
// savat qatori bo'lib, backend'da o'z bozorchisiga alohida buyurtma bo'ladi.
// Bunday kartochkaga oddiy bosish savatga QO'SHMAYDI (qaysi manbaga ekani
// noma'lum) — qo'shish qatordagi [+] orqali; uzoq bosish hamma manba
// miqdorini bitta oynada so'raydi.
// isGrid=true -> grid katakchasi (rasm cho'ziluvchan), false -> gorizontal
// ro'yxat kartasi (eni 180, rasm balandligi 160).
// skladId berilsa qoldiq aynan shu sklad bo'yicha; berilmasa ombor
// skladlaridan birinchi topilgani.
class OmborProductCard extends StatelessWidget {
  final OmborProduct product;
  final bool isGrid;
  final int? skladId;
  const OmborProductCard({
    super.key,
    required this.product,
    this.isGrid = false,
    this.skladId,
  });

  static const Color _accentColor = Color(0xFFC5A97B);
  // Ko'p manbali kartochkada hali tanlanmagan manba qatori matni.
  static const Color _idleSourceColor = Color(0xFF7A5C2E);
  static const double _sourceRowHeight = 32;

  // Bir qadam = kartochkada ko'rsatilgan pachka miqdori * 1000 (milli-birlik,
  // butun son). Subtitle bilan BIR XIL fallback: bozor gramm -> mone gramm ->
  // 1. Masalan 0.5 ko'rsatilgan mahsulotda + har bosilganda +0.5 qo'shiladi.
  int get _stepMilli {
    final qty = product.bozorGrams ?? product.grams;
    if (qty == null || qty <= 0) return 1000;
    return (qty * 1000).round();
  }

  String get _subtitle {
    final unit =
        (product.type != null && product.type!.isNotEmpty) ? product.type! : '';
    // Pachka miqdori = bozor gramm; bo'lmasa mone gramm.
    final qty = product.bozorGrams ?? product.grams;
    String qtyText = '';
    if (qty != null) {
      final v = qty.toDouble();
      final u = unit.toLowerCase();
      final isKg = u == 'kg' || u == 'кг';
      // 1 kg dan kam bo'lsa grammda: 0.4 kg -> "400 gr".
      if (isKg && v > 0 && v < 1) {
        qtyText = '${(v * 1000).round()} gr';
      } else {
        // Ortiqcha nollarsiz: 0.4 -> "0.4", 2 -> "2".
        final s = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
        qtyText = unit.isNotEmpty ? '$s $unit' : s;
      }
    } else {
      qtyText = unit;
    }
    final source = product.sourceLabel;
    if (qtyText.isNotEmpty && source.isNotEmpty) return '$qtyText • $source';
    return qtyText.isNotEmpty ? qtyText : source;
  }

  // «Qoldiq» qatori — faqat sklad qoldig'ida yozuv bo'lsa ko'rinadi.
  Widget _buildQoldiq(StockRow row) {
    final low = row.low;
    final color = low
        ? Colors.orange.shade800
        : row.minQty > 0
            ? Colors.green.shade700
            : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: Row(
        children: [
          if (low) ...[
            Icon(Icons.warning_amber_rounded, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Expanded(
            child: Text(
              omborQoldiqText(row),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Uzoq bosilganda miqdorni qo'lda kiritish oynasi (_OmborQtyDialog):
  // xohlagancha buyurtma berish mumkin. sources — qaysi manba(lar) miqdori
  // kiritiladi: bitta -> bitta «Miqdor» maydoni (ilgarigidek); bir nechta ->
  // har manbaga o'z nomi bilan alohida maydon.
  Future<void> _showQtyInputDialog(
      BuildContext context, List<String> sources) async {
    final provider = context.read<OmborProvider>();
    final values = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => _OmborQtyDialog(
        title: product.name,
        type: product.type,
        sources: sources,
        current: {
          for (final s in sources) s: provider.countMilli(product.id, s),
        },
      ),
    );

    values?.forEach((source, milli) {
      provider.setCountMilli(product.id, source, milli);
    });
  }

  // Rasm bosilsa katta (to'liq) ko'rinishda ochiladi.
  void _showImageDialog(BuildContext context) {
    if (product.imageUrl == null || product.imageUrl!.isEmpty) return;
    showDialog(
      context: context,
      // To'liq ko'rinish ham ekran kengligida dekod qilinadi — telefon
      // ekrani manba fayldan (1024px) tor bo'lsa ortiqcha piksel saqlanmaydi.
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: AppNetworkImage(
          imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
          fit: BoxFit.contain,
          placeholder: (context) => const Center(
            child: CircularProgressIndicator(color: _accentColor),
          ),
          errorWidget: (context) => const Icon(
            Icons.error,
            size: 40,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;
    if (!hasImage) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.inventory_2_outlined,
            color: Colors.grey, size: 40),
      );
    }
    // AppNetworkImage kartochka kengligida dekod qiladi (memCacheWidth) —
    // 1024px'lik asl fayl RAM'da ~3 MB emas, ~0.7 MB joy egallaydi. Katta
    // kategoriyada grid'ni aylantirganda ImageCache to'lib ketmaydi, ya'ni
    // qayta-qayta dekod (va undan kelib chiqadigan «qotish») bo'lmaydi.
    return AppNetworkImage(
      imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (context) => Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _accentColor,
          ),
        ),
      ),
    );
  }

  // Pastki tugma: tanlanmagan -> "Qo'shish"; tanlangan -> [-  miqdor  +].
  // Faqat BITTA manbali mahsulot uchun — savat qatori o'sha yagona manba bilan.
  Widget _buildButton(BuildContext context, OmborProvider provider) {
    final source = product.primarySource;
    final milli = provider.countMilli(product.id, source);
    final isSelected = milli > 0;

    if (!isSelected) {
      return ElevatedButton(
        onPressed: () => provider.addToCart(product.id, source, _stepMilli),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.zero,
          elevation: 0,
        ),
        child: const Text(
          'Qo\'shish',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final type = product.type;
    final qtyText = (type != null && type.isNotEmpty)
        ? '${formatMilli(milli)} $type'
        : formatMilli(milli);

    return Container(
      decoration: BoxDecoration(
        color: _accentColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      provider.decrement(product.id, source, _stepMilli),
                  child: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 12),
                    child:
                        const Icon(Icons.remove, color: Colors.white, size: 20),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      provider.addToCart(product.id, source, _stepMilli),
                  child: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 12),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Text(
                qtyText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Ko'p manbali mahsulot: har manba uchun alohida qator —
  //   Samarqand   [ -  5 кг  + ]
  //   Toshkent    [ -  3 кг  + ]
  // Stepper yagona manbali tugma kabi: chap yarmi «-», o'ng yarmi «+».
  // Miqdori yo'q manba — och rangli «Qo'shish» (bosilsa bir qadam).
  // Qatorni uzoq bosish — faqat SHU manba miqdorini qo'lda kiritish.
  Widget _buildSourceRows(BuildContext context, OmborProvider provider) {
    final sources = product.sources;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sources.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _buildSourceRow(context, provider, sources[i]),
        ],
      ],
    );
  }

  Widget _buildSourceRow(
      BuildContext context, OmborProvider provider, String source) {
    final milli = provider.countMilli(product.id, source);
    final isSelected = milli > 0;

    final Widget control;
    if (!isSelected) {
      control = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => provider.addToCart(product.id, source, _stepMilli),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Qo\'shish',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _idleSourceColor,
            ),
          ),
        ),
      );
    } else {
      final type = product.type;
      final qtyText = (type != null && type.isNotEmpty)
          ? '${formatMilli(milli)} $type'
          : formatMilli(milli);
      control = Container(
        decoration: BoxDecoration(
          color: _accentColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        provider.decrement(product.id, source, _stepMilli),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 6),
                      child: const Icon(Icons.remove,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        provider.addToCart(product.id, source, _stepMilli),
                    child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 6),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
            // Uzun miqdor (masalan «125.5 кг») ikonkalar ustiga chiqmasin.
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      qtyText,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showQtyInputDialog(context, [source]),
      child: SizedBox(
        height: _sourceRowHeight,
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                productSourceLabel(source),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(flex: 6, child: control),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sklad qoldig'i (bo'lmasa null — qator umuman ko'rsatilmaydi).
    final stockRow = omborStockRow(context, product.id, skladId: skladId);
    final multi = product.isMultiSource;
    // Ko'p manbali kartochkada pastdagi qatorlar balandroq — gorizontal
    // ro'yxatdagi (balandligi qat'iy 296) kartochkada ham rasm grid'dagi
    // kabi qolgan joyni egallaydi, aks holda Column toshib ketardi.
    final flexImage = isGrid || multi;

    return Consumer<OmborProvider>(
      builder: (context, provider, child) {
        final image = GestureDetector(
          onTap: () => _showImageDialog(context),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
            child: flexImage
                ? SizedBox(width: double.infinity, child: _buildImage())
                : SizedBox(
                    width: double.infinity, height: 150, child: _buildImage()),
          ),
        );

        return GestureDetector(
          // Ko'p manbali mahsulotda qaysi manbaga qo'shish noma'lum —
          // kartochka bosilganda hech narsa qilinmaydi (qatordagi [+] bor).
          onTap: multi
              ? null
              : () => provider.addToCart(
                  product.id, product.primarySource, _stepMilli),
          onLongPress: () => _showQtyInputDialog(context, product.sources),
          child: Container(
            width: isGrid ? null : 180,
            margin: isGrid
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                flexImage ? Expanded(child: image) : image,
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (_subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                    child: Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                if (stockRow != null) _buildQoldiq(stockRow),
                // Berilgan, lekin hali kelmagan buyurtma (0 bo'lsa ko'rinmaydi).
                OmborBuyurtmaLabel(productId: product.id, type: product.type),
                if (!flexImage) const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: multi
                      ? _buildSourceRows(context, provider)
                      : SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: _buildButton(context, provider),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Miqdorni qo'lda kiritish oynasi. "." yoki "," bilan kasr kiritilsa kasr
// saqlanadi (0.5 -> 0.5). Natija: manba -> milli-birlik (BUTUN son); bo'sh
// qoldirilgan maydon natijaga kirmaydi (o'sha manba miqdoriga tegilmaydi).
//
// Controller'lar SHU vidjet holatida: route to'liq yopilgach (yopilish
// animatsiyasidan keyin) dispose bo'ladi. showDialog qaytishi bilan dispose
// qilinsa, yopilish animatsiyasida TextField qayta qurilib «TextEditingController
// was used after being disposed» xatosi chiqadi.
class _OmborQtyDialog extends StatefulWidget {
  final String title;
  final String? type;
  final List<String> sources;
  // Manba -> hozirgi savatdagi miqdor (milli) — maydon ichidagi «Hozir: X».
  final Map<String, int> current;

  const _OmborQtyDialog({
    required this.title,
    required this.type,
    required this.sources,
    required this.current,
  });

  @override
  State<_OmborQtyDialog> createState() => _OmborQtyDialogState();
}

class _OmborQtyDialogState extends State<_OmborQtyDialog> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.sources) TextEditingController(),
  ];

  bool get _multi => widget.sources.length > 1;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // Kiritilgan matn -> milli-birlik (BUTUN son); noto'g'ri bo'lsa null.
  int? _parseMilli(String text) {
    // Vergul ham nuqta kabi qabul qilinadi: "2,5" -> "2.5".
    final raw = text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null) return null;
    // GRAMM-YOZISH HIMOYASI: кг/л mahsulotda 1000+ kiritilsa omborchi
    // grammda yozgan deb olinadi ("20 kg" o'rniga "20000" yozish odati) —
    // milli panjarada gramm == milli, ko'paytirilmaydi. Aks holda kasr
    // saqlanib ×1000: 0.5 -> 500 milli, 2.5 -> 2500 milli.
    if (qtyUnitFactor(widget.type) != 1 && value >= 1000) {
      return value.round();
    }
    return (value * 1000).round();
  }

  void _confirm() {
    final result = <String, int>{};
    for (var i = 0; i < widget.sources.length; i++) {
      final text = _controllers[i].text.trim();
      if (text.isEmpty) continue;
      final milli = _parseMilli(text);
      if (milli == null) return;
      result[widget.sources[i]] = milli;
    }
    // Hech narsa kiritilmagan — oyna ochiq qoladi (ilgarigidek).
    if (result.isEmpty) return;
    Navigator.pop(context, result);
  }

  Widget _field(int i) {
    final source = widget.sources[i];
    final current = widget.current[source] ?? 0;
    final isLast = i == widget.sources.length - 1;
    return TextField(
      controller: _controllers[i],
      autofocus: i == 0,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: _multi && !isLast ? TextInputAction.next : null,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: _multi ? productSourceLabel(source) : 'Miqdor',
        hintText: current > 0
            ? 'Hozir: ${formatMilli(current)}'
            : 'Miqdorni kiriting',
        border: const OutlineInputBorder(),
      ),
      onSubmitted: isLast ? (_) => _confirm() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: _multi
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.sources.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                      child: _field(i),
                    ),
                ],
              ),
            )
          : _field(0),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Bekor',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        ElevatedButton(
          onPressed: _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: OmborProductCard._accentColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}

// Mahsulotning sklad qoldig'i qatori. skladId berilsa — aynan shu sklad;
// berilmasa ombor skladlari bo'ylab birinchi topilgani (odatda ombor bitta
// skladga biriktirilgan). Yozuv topilmasa null — «noma'lum», 0 EMAS: shuning
// uchun kartochkada qator umuman ko'rsatilmaydi.
StockRow? omborStockRow(BuildContext context, int productId, {int? skladId}) {
  final stock = context.watch<StockProvider>();
  // skladIds fetch'da bir marta o'rnatiladi — butun provider'ni watch qilish
  // o'rniga faqat shu maydonni kuzatamiz (savatga «+» bosilganda kartochka
  // bekorga qayta chizilmasin).
  final ids = skladId != null
      ? <int>[skladId]
      : context.select<OmborProvider, List<int>>((p) => p.skladIds);
  // rowFor — indeks bo'yicha O(1). Ilgari bu yer har kartochka uchun butun
  // qoldiq ro'yxatini chiziqli kezardi.
  for (final id in ids) {
    final row = stock.rowFor(id, productId);
    if (row != null) return row;
  }
  return null;
}

// «Qoldiq» matni — chegara (min_qty) va joriy qoldiq munosabati:
//  - chegara bor, qoldiq undan yuqori -> «Qoldiq: 5+1=6 кг»
//  - chegara bor, qoldiq undan past   -> «Qoldiq: 5-1=4 кг»
//  - chegara yo'q (min_qty == 0)      -> «Qoldiq: 6 кг»
// Sonlar UI birlikda: кг/л mahsulotda API gramm/ml bo'lib keladi -> kg/l.
String omborQoldiqText(StockRow row) {
  final unit = row.type.trim();
  final suffix = unit.isEmpty ? '' : ' $unit';
  final qty = formatQty(row.qty, row.type);
  if (row.minQty <= 0) return 'Qoldiq: $qty$suffix';
  final min = formatQty(row.minQty, row.type);
  final diff = formatQty((row.qty - row.minQty).abs(), row.type);
  // Ishora backend'ning low bayrog'idan — matn va rang doim mos bo'lsin.
  final sign = row.low ? '-' : '+';
  return 'Qoldiq: $min$sign$diff=$qty$suffix';
}

// «Buyurtma: 10 кг» yozuvi — shu mahsulotga buyurtma BERILGAN, lekin hali
// KELMAGAN miqdor (OmborProvider.orderedQty). «Qoldiq» qatoridan keyin
// alohida qatorda turadi: ombor «Kam qolganlar» sahifasidan bir mahsulotni
// ikki marta buyurtma qilib yubormasligi uchun.
//
// Alohida qator (yonma-yon emas) — chunki kartochka tor (grid'da ~165px,
// ro'yxatda 180px): bitta qatorda ikkala yozuv ham qirqilib ketardi.
// Rangi qoldiq holatlaridan (yashil/to'q sariq/kulrang) ataylab farqli.
// Miqdor 0 bo'lsa hech narsa chizilmaydi.
class OmborBuyurtmaLabel extends StatelessWidget {
  final int productId;
  // Birlik — «Qoldiq» qatoridagi kabi (кг/л da qiymat butun гр/мл bo'lib
  // keladi, formatQty uni kg/l ga qaytaradi).
  final String? type;
  final EdgeInsetsGeometry padding;

  const OmborBuyurtmaLabel({
    super.key,
    required this.productId,
    required this.type,
    this.padding = const EdgeInsets.fromLTRB(8, 0, 8, 2),
  });

  static const Color _orderedColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final qty = context.watch<OmborProvider>().orderedQty(productId);
    if (qty <= 0) return const SizedBox.shrink();

    final unit = (type ?? '').trim();
    final qtyText = formatQty(qty, type);
    final text = unit.isEmpty
        ? 'Buyurtma: $qtyText'
        : 'Buyurtma: $qtyText $unit';

    return Padding(
      padding: padding,
      child: Row(
        children: [
          const Icon(Icons.shopping_cart_outlined,
              size: 11, color: _orderedColor),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _orderedColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Milli-birlikni (qiymat*1000) faqat butun son arifmetikasi bilan formatlash:
// 1200 -> "1.2", 400 -> "0.4", 2000 -> "2". Float umuman ishlatilmaydi.
String formatMilli(int milli) {
  final whole = milli ~/ 1000;
  final frac = milli % 1000;
  if (frac == 0) return '$whole';
  final f = frac.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
  return '$whole.$f';
}
