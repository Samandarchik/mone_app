// shef/ui/shef_constructor_page.dart — shef KONSTRUKTORI (ShefConstructorPage):
// shef bosh ekranining o'ng pastki burchagidagi «Konstruktor» tugmasidan
// ochiladi. Tort HAQIQIY mahsulotlardan yig'iladi (tex kartalari bilan):
// tepada katta aylanadigan 3D rasm, uning OSTIDA bir qatorda 3 ta qadam
// tugmasi (1 · 2 · 3), undan pastda shu qadamning mahsulotlari (grid) —
// bosilsa tanlanadi va 3D darhol o'zgaradi.
//   1 — Biskvit: faqat biskvitning o'zi (П/Ф Бисквит sahifasidagidek:
//       o'lchami/turi tex kartadan, foto bo'lsa yon tomonda).
//   2 — Nachinka: O'SHA biskvit (o'lchami va korj rangi tanlangan
//       biskvitdan) ichida nachinka QATLAMLARI bilan — bo'lagi kesilgan,
//       kesimda nachinka. Odatda 2 qatlam; «+ Qatlam» yana qo'shadi (5
//       tagacha), «×» olib tashlaydi. «N-qatlam» chipi — faol qatlam: griddan
//       tanlangan nachinka shunga yoziladi, ya'ni har qatlam o'z mahsuloti,
//       o'z ranglari va o'z tex kartasi bilan. Chiplar ostida faol qatlamning
//       RANG PALITRASI: tanlangan rang shu qatlamda mahsulot rangidan ustun
//       (chipdagi nuqta — qatlamning hozirgi rangi). N nachinka -> N+1 korj, tort
//       balandligi o'zgarmaydi.
//   3 — Покрытие: o'sha tort tanlangan krem bilan tashqaridan TO'LIQ
//       qoplangan, bo'lagi kesilgan — kesimda nachinka ham, qoplama qatlami
//       ham ko'rinadi.
// Biskvitlar — nomi «Бисквит» bo'lgan kategoriyalar, nachinka va qoplamalar —
// «Начинка» kategoriyalari mahsulotlari (isBiskvitCategory /
// isNachinkaCategory). Ranglar bo'limlardagi bilan bir xil manbadan:
// FillingLook.resolve (palitra → foto → nom/tarkib) va FillingLook.coatOf
// («Покрытие rangi» palitrasi → nom/tarkib). Tanlov faqat shu ekranda yashaydi
// (saqlanmaydi). Eski lokal-katalogli cake_constructor_page.dart bunga
// aloqador emas.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/biskvit_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_photo_look.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);
const double _heroH = 205;

// Qadamlar: (tugma yozuvi, grid sarlavhasi).
const List<(String, String)> _steps = [
  ('Biskvit', 'Biskvitni tanlang'),
  ('Nachinka', 'Ichki nachinkani tanlang'),
  ('Покрытие', 'Tashqi qoplamani tanlang'),
];

class ShefConstructorPage extends StatefulWidget {
  const ShefConstructorPage({super.key});

  @override
  State<ShefConstructorPage> createState() => _ShefConstructorPageState();
}

class _ShefConstructorPageState extends State<ShefConstructorPage> {
  int _step = 0;
  // Tanlanganlar (null — ro'yxatdagi birinchisi).
  int? _biscuitId;
  int? _coatingId;
  // NACHINKA QATLAMLARI (tepadan pastga) — har biri o'z nachinka mahsuloti
  // (id; null — ro'yxatdagi birinchisi). Odatda 2 ta; «+ Qatlam» yana
  // qo'shadi (pastga). N nachinka → N+1 korj, hammasi biskvit balandligi
  // ichida.
  final List<int?> _fillingIds = [null, null];
  // Qatlam rangi FAQAT mahsulotning tex kartasidan (kartochkadagi «tex karta»
  // tugmasi → 2 ta nachinka palitrasi); konstruktorda alohida palitra yo'q.
  // Hozir nachinka tanlanayotgan qatlam (_fillingIds indeksi).
  int _activeLayer = 0;

  static const int _maxLayers = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Allaqachon yuklangan bo'lsa — jim (YAGONA manba, qayta GET yo'q).
      context.read<ProductProviderAdmin>().initializeProducts();
      // Пф kategoriyalari nomi shu ro'yxatdan ham topiladi.
      final shef = context.read<ShefProvider>();
      if (shef.pfStock.isEmpty) shef.fetchPfStock();
    });
  }

  // Mahsulotning тех картаси — bo'limlardagi bilan AYNAN bir xil rejimda
  // (narxsiz), hozirgi qadamga mos bo'limlar bilan: biskvit — foto; nachinka
  // — foto + 2 ta nachinka palitrasi; qoplama — «Покрытие rangi» palitrasi.
  // Saqlangach provider xotirada yangilanadi va 3D o'zi qayta chiziladi.
  void _openTechCard(ProductModelAdmin product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(
          product: product,
          canEditPrices: false,
          showBiscuitPhoto: _step != 2,
          showBiscuitColor: _step == 0,
          showFillingColor: _step == 1,
          showCoatingColor: _step == 2,
        ),
      ),
    );
  }

  static ProductModelAdmin? _pick(List<ProductModelAdmin> list, int? id) {
    if (list.isEmpty) return null;
    for (final p in list) {
      if (p.id == id) return p;
    }
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Konstruktor',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
        builder: (context, cats, products, _) {
          if (products.isLoading && products.products.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final pf = context.select<ShefProvider, List<PfStockRow>>(
            (p) => p.pfStock,
          );
          // Kategoriya nomi bo'yicha ajratish — BITTA o'tishda.
          final byId = shefCategoriesById(cats.categories, pf);
          final biscuits = <ProductModelAdmin>[];
          final fillings = <ProductModelAdmin>[];
          for (final p in products.products) {
            final name = byId[p.categoryId]?.name ?? '';
            if (isBiskvitCategory(name)) {
              biscuits.add(p);
            } else if (isNachinkaCategory(name)) {
              fillings.add(p);
            }
          }
          final biscuit = _pick(biscuits, _biscuitId);
          // Har nachinka qatlamining mahsuloti (tepadan pastga).
          final layers = [
            for (final id in _fillingIds) _pick(fillings, id),
          ];
          final coating = _pick(fillings, _coatingId);

          final items = _step == 0 ? biscuits : fillings;
          final selectedId =
              [biscuit?.id, layers[_activeLayer]?.id, coating?.id][_step];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: _hero(biscuit, layers, coating),
              ),
              // Qadam tugmalari — rasmning OSTIDA, bir qatorda.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _StepButton(
                        number: i + 1,
                        label: _steps[i].$1,
                        selected: _step == i,
                        onTap: () => setState(() => _step = i),
                      ),
                  ],
                ),
              ),
              // Tugmalar ostidagi hamma narsa — BITTA suriladigan maydon:
              // sarlavha, (2-qadamda) qatlamlar qatori va mahsulotlar gridi.
              // Tepadagi 3D va qadam tugmalari joyida qoladi.
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Text(
                          '${_step + 1}. ${_steps[_step].$2}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // 2-qadam: nachinka qatlamlari — qaysi qatlamga
                    // tanlanayotgani va «+ Qatlam». Rang — mahsulot tex
                    // kartasi ichidagi palitradan (kartochkadagi tugma).
                    if (_step == 1 && fillings.isNotEmpty)
                      SliverToBoxAdapter(child: _layerBar(layers)),
                    if (items.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyHint(biscuit: _step == 0),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 150,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            childCount: items.length,
                            (context, index) {
                              final p = items[index];
                              return _PickCard(
                                product: p,
                                step: _step,
                                selected: p.id == selectedId,
                                onTap: () => setState(() {
                                  if (_step == 0) {
                                    _biscuitId = p.id;
                                  } else if (_step == 1) {
                                    _fillingIds[_activeLayer] = p.id;
                                  } else {
                                    _coatingId = p.id;
                                  }
                                }),
                                onOpenTechCard: () => _openTechCard(p),
                              );
                            },
                          ),
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

  // Katta 3D: qadamga qarab biskvit / nachinkali / qoplangan tort.
  // [layers] — nachinka qatlamlari mahsulotlari, tepadan pastga.
  Widget _hero(
    ProductModelAdmin? biscuit,
    List<ProductModelAdmin?> layers,
    ProductModelAdmin? coating,
  ) {
    final palette = biscuit == null
        ? BiscuitPalette.classic
        : BiscuitPalette.of(biscuit.name, biscuit.techCard);
    if (_step == 0) {
      return Biscuit3DView(
        height: _heroH,
        dims: BiscuitDims.fromTechCard(biscuit?.techCard),
        palette: palette,
        fruits: biscuit == null
            ? const []
            : BiscuitFruit.detect(biscuit.name),
        photoUrl: biscuitPhotoUrlOf(biscuit?.techCard),
      );
    }

    // Har qatlamning ko'rinishi o'z mahsulotidan: palitra → foto →
    // nom/tarkib (FillingLook.resolve). Foto tahlili asinxron — natija
    // kelganda FillingPhotoLooksBuilder qayta quradi.
    final resolved = [
      for (final p in layers)
        p == null
            ? (FillingLook.neutral, null)
            : FillingLook.resolve(p.name, p.techCard),
    ];
    return FillingPhotoLooksBuilder(
      urls: [for (final (_, url) in resolved) url],
      builder: (context, photoLooks) => Filling3DView(
        height: _heroH,
        sponge: palette,
        // Tort o'lchami 1-qadamdagi biskvitniki — qadam almashganda ham,
        // nachinka qatlami qo'shilganda ham o'zgarmaydi: qatlamlar shu
        // balandlik ICHIGA sig'diriladi.
        dims: BiscuitDims.fromTechCard(biscuit?.techCard),
        // Tex kartada 2 ta palitra bor: 1-qatlam (yuqori) va 2-qatlam
        // (pastki). k-qatlam o'z mahsulotining (k juft -> 1-, toq -> 2-)
        // palitrasini oladi: bitta mahsulot ikki qatlamda turganda
        // avvalgidek «yuqori/pastki» ranglar chiqadi.
        fillings: [
          for (var k = 0; k < resolved.length; k++)
            (photoLooks[k] ?? resolved[k].$1).bandsOf(k.isEven ? 0 : 1),
        ],
        // 3-qadam: tashqaridan qoplangan, lekin bo'lagi kesilgan — ichidagi
        // nachinka ham ko'rinadi.
        coat: _step == 2
            ? (coating == null
                ? FillingLook.neutral.color
                : FillingLook.coatOf(coating.name, coating.techCard))
            : null,
        coatCut: true,
      ),
    );
  }

  // Qatlamning hozirgi asosiy rangi — chipdagi rangli nuqta uchun (foto
  // tahlili kutilmaydi: mahsulot tex karta palitrasi → nom-tarkib).
  Color _layerDot(int k, ProductModelAdmin? p) {
    if (p == null) return FillingLook.neutral.color;
    final bands =
        FillingLook.resolve(p.name, p.techCard).$1.bandsOf(k.isEven ? 0 : 1);
    return bands.reduce((a, b) => b.part > a.part ? b : a).color;
  }

  // Nachinka qatlamlari qatori: «1-qatlam», «2-qatlam» ... (tepadan pastga) —
  // bosilsa shu qatlam faol bo'ladi (grid tanlovi unga yoziladi); «×» —
  // qatlamni olib tashlash; oxirida «+ Qatlam».
  Widget _layerBar(List<ProductModelAdmin?> layers) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < layers.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                // Qatlamning hozirgi rangi.
                avatar: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _layerDot(i, layers[i]),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                label: Text('${i + 1}-qatlam'),
                selected: _activeLayer == i,
                showCheckmark: false,
                selectedColor: _accentColor.withValues(alpha: 0.35),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: _activeLayer == i
                      ? _accentColor
                      : Colors.grey.shade300,
                ),
                onPressed: () => setState(() => _activeLayer = i),
                deleteIcon: const Icon(Icons.close, size: 16),
                // Yagona qatlamni olib tashlab bo'lmaydi.
                onDeleted: layers.length < 2
                    ? null
                    : () => setState(() {
                          _fillingIds.removeAt(i);
                          if (_activeLayer >= _fillingIds.length) {
                            _activeLayer = _fillingIds.length - 1;
                          }
                        }),
              ),
            ),
          if (layers.length < _maxLayers)
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Qatlam'),
              backgroundColor: Colors.white,
              side: const BorderSide(color: _accentColor),
              // Yangi qatlam eng PASTGA qo'shiladi va faol bo'ladi; boshlanishiga
              // ustidagi qatlamning nachinkasi — keyin griddan almashtiriladi.
              onPressed: () => setState(() {
                _fillingIds.add(layers.last?.id);
                _activeLayer = _fillingIds.length - 1;
              }),
            ),
        ],
      ),
    );
  }
}

// Rasm ostidagi qadam tugmasi: raqamli doira + ostida yozuv.
class _StepButton extends StatelessWidget {
  final int number;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StepButton({
    required this.number,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _accentColor : Colors.white,
                border: Border.all(
                  color: selected ? _accentColor : Colors.grey.shade400,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.white : Colors.brown.shade700,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.brown.shade800 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Griddagi bitta mahsulot: rasm (yo'q bo'lsa qadamga mos chizma) + nom.
class _PickCard extends StatelessWidget {
  final ProductModelAdmin product;
  final int step;
  final bool selected;
  final VoidCallback onTap;
  // Shu mahsulotning тех картаси — kartani IKKI MARTA bosish.
  final VoidCallback onOpenTechCard;

  const _PickCard({
    required this.product,
    required this.step,
    required this.selected,
    required this.onTap,
    required this.onOpenTechCard,
  });

  @override
  Widget build(BuildContext context) {
    final Widget drawn;
    if (step == 0) {
      drawn = BiscuitThumb(
        dims: BiscuitDims.fromTechCard(product.techCard),
        palette: BiscuitPalette.of(product.name, product.techCard),
        fruits: BiscuitFruit.detect(product.name),
        photoUrl: biscuitPhotoUrlOf(product.techCard),
      );
    } else if (step == 1) {
      final (look, photoUrl) =
          FillingLook.resolve(product.name, product.techCard);
      drawn = FillingThumb(look: look, photoUrl: photoUrl);
    } else {
      drawn = FillingThumb(
        look: FillingLook.neutral,
        coat: FillingLook.coatOf(product.name, product.techCard),
      );
    }
    // Qoplama qadamida mahsulotning o'z rasmi ko'rsatilmaydi: u nachinkaning
    // rasmi, qoplangan tortniki emas.
    final image = product.imageUrl ?? '';
    final url = (step == 2 || image.isEmpty) ? null : '${AppUrls.baseUrl}$image';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        // Bo'limlardagidek: ikki marta bosish — тех карта.
        onDoubleTap: onOpenTechCard,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: _accentColor, width: 2)
                : Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, box) => url != null
                        ? AppNetworkImage(
                            imageUrl: url,
                            width: box.maxWidth,
                            height: box.maxHeight,
                            fit: BoxFit.cover,
                            placeholder: (_) => drawn,
                            errorWidget: (_) => drawn,
                          )
                        : SizedBox.expand(child: drawn),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Qadam uchun mahsulot topilmadi.
class _EmptyHint extends StatelessWidget {
  final bool biscuit;

  const _EmptyHint({required this.biscuit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        biscuit
            ? 'Biskvit topilmadi.\nNomi «Бисквит» bo\'lgan kategoriyada '
                'mahsulot bo\'lishi kerak'
            : 'Nachinka topilmadi.\nNomi «Начинка» bo\'lgan kategoriyada '
                'mahsulot bo\'lishi kerak',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade600),
      ),
    );
  }
}
