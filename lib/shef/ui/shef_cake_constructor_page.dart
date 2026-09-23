// shef/ui/shef_cake_constructor_page.dart — TORTNING O'Z TO'LIQ konstruktori
// (ShefCakeConstructorPage): Biskvit bo'limi / «Торты» bo'limida
// (biskvit_page.dart, shef_cakes_page.dart) tort bosilganda ochiladi.
// Umumiy konstruktordan (shef_constructor_page.dart — kategoriyalardan
// biskvit/nachinka/qoplama TANLASH) farqi: bu yerda hech narsa tanlanmaydi
// — hammasi SHU TORTNING TEX KARTASIDAN va undagi ПОЛУФАБРИКАТЛАРНИНГ o'z
// tex kartalaridan chiziladi. 3 qadam (rasm ostidagi tugmalar):
//   1 — Biskvit: tortning biskviti O'Z TEX KARTASI bo'yicha. Tort tex
//       kartasidagi masalliq qatori product_id bilan «Бисквит»
//       kategoriyasidagi (yoki nomi biskvit bo'lgan tex kartali) пф'ga
//       bog'langan bo'lsa — o'sha пф: rangi («Biskvit rangi» palitrasi /
//       nom-tarkib), mevalari, tex kartadagi fotosi (yon tomonga o'raladi),
//       pishirish vaqti/harorati — xuddi «П/Ф Бисквит» sahifasidagidek.
//       Ostida пф'ning o'z tex kartasi (bloklari, masalliqlari) — bosilsa
//       muharrirda ochiladi. Пф topilmasa — tortning o'z biskvit bloki.
//   2 — Kesim: O'SHA biskvit (rangi/o'lchami 1-qadamdan) ichida nachinka
//       qatlamlari, bo'lagi kesilgan — kesimda nachinka. Har qatlam —
//       tort tex kartasidagi nachinka ПФ'ining o'z tex kartasi bo'yicha
//       (FillingLook.resolve: «Nachinka rangi» palitrasi → пф fotosidagi
//       kesim qatlamlari → nom/tarkib), tartib bilan: 1-qatlam (pastki) —
//       1-пф, 2-qatlam — 2-пф ... Qatlam soni — chiplar: boshlanishida
//       пф'lar soni, «+ Qatlam» qo'shadi, «×» olib tashlaydi; chip bosilsa
//       ostida faqat shu qatlamning пф tex kartasi. Пф bo'lmasa — tortning
//       nachinka bloklari, hammasi «Nachinka rangi» palitrasida.
//   3 — Tort: TAYYOR TORT — tortning O'Z FOTOSI, ekrandagi o'lchami tex
//       kartadagi DIAMETRGA qarab (cake_photo_view.dart, CakePhotoView):
//       Ø 30 sm blokni to'ldiradi, Ø 16 sm kichik chiqadi — tortlar
//       bir-biriga nisbatan to'g'ri kattalikda ko'rinadi. 3D qurish YO'Q:
//       fotodan siluet bo'yicha model qurish tashlandi (Mone fotolarida
//       tort oq patnis ustida, fon ham oq — siluet patnis bilan qo'shilib
//       ketardi). Foto YO'Q bo'lsagina — vektor ILLYUSTRATSIYA tex kartadan
//       (cake_illustration.dart). Ostida qoplama/dekor bloklari.
// Blok roli nomidan (CakeBlockRole.of): бисквит/корж → biskvit; покрытие/
// глазурь/выравнивание → qoplama; декор/украшение → bezak; пропитка/сироп/
// сборка → bosqich; qolgani (крем, начинка, конфи, мусс) → nachinka.
// Пф'lar (CakeParts.resolve) — mahsulotlar ProductProviderAdmin (YAGONA
// manba) dan; tex karta AppBar tugmasidan tahrirlanadi — saqlangach
// (provider) konstruktor o'zi yangilanadi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_illustration.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_photo_view.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_photo_look.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);
const double _heroH = 205;

// Qadamlar: (tugma yozuvi, sarlavha, blok yo'q bo'lganda izoh).
const List<(String, String, String)> _steps = [
  (
    'Biskvit',
    'Tortning biskviti',
    'Tex kartada biskvit bloki (Бисквит / Корж) topilmadi — rang tort '
        'nomi/tarkibidan',
  ),
  (
    'Kesim',
    'Bo\'lak kesimi — nachinka',
    'Tex kartada nachinka bloki (Крем / Начинка / Конфи ...) yo\'q — '
        'faqat biskvit',
  ),
  (
    'Tort',
    'Tayyor tort',
    'Tex kartada qoplama/dekor bloki yo\'q',
  ),
];

// Nisbiy yo'l → to'liq URL (bo'sh — null).
String? _fullUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return raw.startsWith('http') ? raw : '${AppUrls.baseUrl}$raw';
}

// Tex kartada o'lcham kiritilganmi (diametr / eni / balandlik).
bool _hasSize(TechCard? c) =>
    c != null &&
    ((c.diameterCm ?? 0) > 0 ||
        (c.widthCm ?? 0) > 0 ||
        (c.lengthCm ?? 0) > 0 ||
        (c.heightCm ?? 0) > 0);

// «Ø 22 sm · 6 sm» / «30×40 sm · 5 sm» (bo'lgan qismlari); yo'q — ''.
String _sizeLine(TechCard? c) {
  if (c == null) return '';
  final parts = <String>[];
  final d = c.diameterCm ?? 0;
  final w = c.widthCm ?? 0;
  final l = c.lengthCm ?? 0;
  final h = c.heightCm ?? 0;
  if (d > 0) {
    parts.add('Ø $d sm');
  } else if (w > 0 && l > 0) {
    parts.add('$w×$l sm');
  }
  if (h > 0) parts.add('$h sm');
  return parts.join(' · ');
}

// Tort tex kartasining qismlari: undagi ПОЛУФАБРИКАТЛАР (biskvit пф va
// nachinka пф'lari — o'z tex kartalari bilan) va tortning o'z bloklari
// rol bo'yicha.
class CakeParts {
  // Biskvit пф (birinchi topilgani); null — пф yo'q, tortning o'z bloki.
  final ProductModelAdmin? biscuit;
  // Nachinka пф'lari — tex kartadagi tartibda (1-qatlam = birinchisi).
  final List<ProductModelAdmin> fillings;
  final List<TechBase> biscuitBlocks;
  final List<TechBase> fillingBlocks;
  // Qoplama, bezak va boshqa bosqichlar (tartib saqlanadi).
  final List<TechBase> finishBlocks;

  const CakeParts({
    this.biscuit,
    this.fillings = const [],
    this.biscuitBlocks = const [],
    this.fillingBlocks = const [],
    this.finishBlocks = const [],
  });

  // Tort tex kartasi + mahsulotlar xaritasi (id → mahsulot). Masalliq qatori
  // product_id bilan mahsulotga bog'langan va u mahsulot пф bo'lsa (pfRoleOf)
  // — ro'yxatga (takrorsiz, blok/masalliq tartibida).
  factory CakeParts.resolve(TechCard card, Map<int, ProductModelAdmin> byId) {
    ProductModelAdmin? biscuit;
    final fillings = <ProductModelAdmin>[];
    final seen = <int>{};
    final biscuitBlocks = <TechBase>[];
    final fillingBlocks = <TechBase>[];
    final finishBlocks = <TechBase>[];
    for (final b in card.bases) {
      switch (CakeBlockRole.of(b)) {
        case CakeBlockRole.biscuit:
          biscuitBlocks.add(b);
        case CakeBlockRole.filling:
          fillingBlocks.add(b);
        case CakeBlockRole.coat:
        case CakeBlockRole.decor:
        case CakeBlockRole.other:
          finishBlocks.add(b);
      }
      for (final i in b.ingredients) {
        if (i.productId <= 0) continue;
        final p = byId[i.productId];
        if (p == null || !seen.add(p.id)) continue;
        switch (pfRoleOf(p)) {
          case CakeBlockRole.biscuit:
            biscuit ??= p;
          case CakeBlockRole.filling:
            fillings.add(p);
          default:
            break;
        }
      }
    }
    return CakeParts(
      biscuit: biscuit,
      fillings: fillings,
      biscuitBlocks: biscuitBlocks,
      fillingBlocks: fillingBlocks,
      finishBlocks: finishBlocks,
    );
  }

  // Mahsulot tortda qaysi пф: «Бисквит» kategoriyasi → biskvit, «Начинка»
  // kategoriyasi → nachinka; boshqa kategoriyada — faqat tex kartali
  // полуфабрикат bo'lsa, nomidan (CakeBlockRole.of). null — пф emas.
  static CakeBlockRole? pfRoleOf(ProductModelAdmin p) {
    if (isBiskvitCategory(p.categoryName)) return CakeBlockRole.biscuit;
    if (isNachinkaCategory(p.categoryName)) return CakeBlockRole.filling;
    final card = p.techCard;
    if (!p.isSemiFinished || card == null || card.bases.isEmpty) return null;
    final role = CakeBlockRole.of(TechBase(name: p.name));
    return (role == CakeBlockRole.biscuit || role == CakeBlockRole.filling)
        ? role
        : null;
  }
}

// 1-qadam biskviti: o'lchami, rangi, mevalari, fotosi.
typedef _BiscuitLook = ({
  BiscuitDims dims,
  BiscuitPalette palette,
  List<BiscuitFruit> fruits,
  String? photoUrl,
});

class ShefCakeConstructorPage extends StatefulWidget {
  final ProductModelAdmin cake;

  const ShefCakeConstructorPage({super.key, required this.cake});

  @override
  State<ShefCakeConstructorPage> createState() =>
      _ShefCakeConstructorPageState();
}

class _ShefCakeConstructorPageState extends State<ShefCakeConstructorPage> {
  int _step = 0;
  // 2-qadam: nachinka QATLAMLARI soni (chiplar: «1-qatlam», «2-qatlam» ...,
  // «+ Qatlam», «×»). null — hali o'zgartirilmagan: nachinka пф'lari soni
  // (пф yo'q — tortning nachinka bloklari soni).
  int? _layerCount;
  // Chip bilan tanlangan qatlam — ostidagi panelda faqat shu qatlamning
  // пф tex kartasi / bloki. null — hammasi.
  int? _activeLayer;

  static const int _maxLayers = 5;

  int _layersOf(CakeParts parts) {
    final n = _layerCount;
    if (n != null) return n.clamp(1, _maxLayers);
    if (parts.fillings.isNotEmpty) {
      return parts.fillings.length.clamp(1, _maxLayers);
    }
    return parts.fillingBlocks.length.clamp(0, _maxLayers);
  }

  // Tort tex kartasi — boshqa bo'limlardagi kabi yagona «Nachinka rangi»
  // palitrasi; saqlangach konstruktor shu rangda.
  void _openTechCard(ProductModelAdmin cake) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(
          product: cake,
          canEditPrices: false,
          showFillingColor: true,
        ),
      ),
    );
  }

  // Пф'ning o'z tex kartasi — «П/Ф Бисквит» / «П/Ф Начинка» sahifalaridagi
  // rejimda (foto; nachinkada palitra ham). Saqlangach 3D o'zi yangilanadi.
  void _openPfCard(ProductModelAdmin pf, CakeBlockRole role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(
          product: pf,
          canEditPrices: false,
          showBiscuitPhoto: true,
          showFillingColor: role == CakeBlockRole.filling,
          biscuitMode: role == CakeBlockRole.biscuit,
        ),
      ),
    );
  }

  // 1-qadam biskviti: пф bo'lsa — uning tex kartasidan (rang palitrasi /
  // nom-tarkib, mevalar nomidan, foto); o'lcham — tortniki (kiritilgan
  // bo'lsa), aks holda пф'niki. Пф yo'q — tort nomi/bloklaridan.
  _BiscuitLook _biscuitLook(
      ProductModelAdmin cake, TechCard card, CakeParts parts) {
    final pf = parts.biscuit;
    if (pf == null) {
      return (
        dims: BiscuitDims.fromTechCard(card),
        palette: BiscuitPalette.detect(cake.name, card),
        fruits: BiscuitFruit.detect(cake.name),
        photoUrl: null,
      );
    }
    final pc = pf.techCard;
    return (
      dims: BiscuitDims.fromTechCard(_hasSize(card) ? card : pc),
      palette: BiscuitPalette.of(pf.name, pc),
      fruits: BiscuitFruit.detect(pf.name),
      photoUrl: biscuitPhotoUrlOf(pc),
    );
  }

  // Nachinka qatlamlari (PASTDAN yuqoriga): har biri (ko'rinish, foto URL).
  // Пф bo'lsa — k-qatlam → k-пф (navbat bilan), o'z tex kartasidan
  // (palitra → foto → nom/tarkib); пф yo'q — tortning «Nachinka rangi».
  List<(FillingLook, String?)> _layerSources(
      ProductModelAdmin cake, TechCard card, CakeParts parts) {
    final n = _layersOf(parts);
    if (parts.fillings.isEmpty) {
      final look = FillingLook.fromTechCard(cake.name, card);
      return [for (var k = 0; k < n; k++) (look, null)];
    }
    return [
      for (var k = 0; k < n; k++)
        () {
          final pf = parts.fillings[k % parts.fillings.length];
          return FillingLook.resolve(pf.name, pf.techCard);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Tex karta saqlangach provider xotirada yangilanadi — eng yangi nusxa;
    // пф'lar ham shu ro'yxatdan (YAGONA manba).
    final products = context.select<ProductProviderAdmin,
        List<ProductModelAdmin>>((p) => p.products);
    final cake = products.firstWhere(
      (x) => x.id == widget.cake.id,
      orElse: () => widget.cake,
    );
    final card = cake.techCard;
    final blocks = card?.bases ?? const <TechBase>[];
    final parts = card == null
        ? const CakeParts()
        : CakeParts.resolve(card, {for (final p in products) p.id: p});

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: Text(
          cake.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Tex karta',
            icon: const Icon(Icons.menu_book_outlined),
            color: Colors.brown.shade700,
            onPressed: () => _openTechCard(cake),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: blocks.isEmpty
          ? _EmptyCard(onOpen: () => _openTechCard(cake))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: _hero(cake, card!, parts),
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
                // 2-qadam: qatlam chiplari (sarlavha o'rniga — joy tejash).
                if (_step == 1) _layerBar(cake, card, parts),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      // 2-qadamda sarlavha yo'q — chiplar o'zi aytib turadi.
                      if (_step != 1)
                        Text(
                          '${_step + 1}. ${_steps[_step].$2}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ..._panel(cake, card, parts),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );

  // Qadam paneli: 1 — biskvit пф tex kartasi (+ tortning biskvit bloklari);
  // 2 — nachinka пф tex kartalari (chip tanlangan bo'lsa — faqat shu
  // qatlamniki) yoki tortning nachinka bloklari; 3 — tort fotosi va
  // qoplama/bezak/bosqich bloklari.
  List<Widget> _panel(ProductModelAdmin cake, TechCard card, CakeParts parts) {
    switch (_step) {
      case 0:
        final pf = parts.biscuit;
        return [
          if (pf != null)
            _PfSection(
              pf: pf,
              role: CakeBlockRole.biscuit,
              dims: _biscuitLook(cake, card, parts).dims,
              onOpen: () => _openPfCard(pf, CakeBlockRole.biscuit),
            ),
          for (final b in parts.biscuitBlocks) _BlockCard(block: b, card: card),
          if (pf == null && parts.biscuitBlocks.isEmpty) _hint(_steps[0].$3),
        ];
      case 1:
        final k = _activeLayer;
        if (parts.fillings.isNotEmpty) {
          final n = parts.fillings.length;
          final list = k == null
              ? parts.fillings
              : [parts.fillings[k % n]];
          return [
            for (final pf in list)
              _PfSection(
                pf: pf,
                role: CakeBlockRole.filling,
                dims: _biscuitLook(cake, card, parts).dims,
                onOpen: () => _openPfCard(pf, CakeBlockRole.filling),
              ),
          ];
        }
        final blocks = parts.fillingBlocks;
        if (blocks.isEmpty) return [_hint(_steps[1].$3)];
        final list = k == null ? blocks : [blocks[k % blocks.length]];
        return [for (final b in list) _BlockCard(block: b, card: card)];
      default:
        // Foto tepada (hero) — pastda takrorlanmaydi.
        return [
          for (final b in parts.finishBlocks) _BlockCard(block: b, card: card),
          if (parts.finishBlocks.isEmpty) _hint(_steps[2].$3),
        ];
    }
  }

  // Nachinka qatlamlari qatori — umumiy konstruktordagi bilan bir xil
  // ko'rinish: «1-qatlam» (pastki) ... rangli nuqta bilan (qatlam пф'ining
  // rangi), «×» olib tashlaydi, «+ Qatlam» ustiga qo'shadi. Chip bosilsa
  // shu qatlam tanlanadi (panelda uning пф tex kartasi), qayta bosilsa
  // tanlov olinadi.
  Widget _layerBar(ProductModelAdmin cake, TechCard card, CakeParts parts) {
    final n = _layersOf(parts);
    final sources = _layerSources(cake, card, parts);
    const chipText = TextStyle(fontSize: 12);
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                avatar: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: sources[i].$1.color,
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                label: Text('${i + 1}-qatlam', style: chipText),
                labelPadding: const EdgeInsets.only(left: 2, right: 4),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                selected: _activeLayer == i,
                showCheckmark: false,
                selectedColor: _accentColor.withValues(alpha: 0.35),
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: _activeLayer == i ? _accentColor : Colors.grey.shade300,
                ),
                onPressed: () => setState(
                    () => _activeLayer = _activeLayer == i ? null : i),
                deleteIcon: const Icon(Icons.close, size: 14),
                // Yagona qatlamni olib tashlab bo'lmaydi.
                onDeleted: n < 2
                    ? null
                    : () => setState(() {
                          _layerCount = n - 1;
                          final a = _activeLayer;
                          if (a != null && a >= n - 1) _activeLayer = null;
                        }),
              ),
            ),
          if (n < _maxLayers)
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Qatlam', style: chipText),
              labelPadding: const EdgeInsets.only(left: 2, right: 4),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              backgroundColor: Colors.white,
              side: const BorderSide(color: _accentColor),
              onPressed: () => setState(() => _layerCount = n + 1),
            ),
        ],
      ),
    );
  }

  // Rasm: qadamga qarab biskvit (пф tex kartasi bo'yicha) / kesilgan
  // bo'lakli tort (пф nachinkalari) / tayyor tort illyustratsiyasi (fotodan).
  Widget _hero(ProductModelAdmin cake, TechCard card, CakeParts parts) {
    final biscuit = _biscuitLook(cake, card, parts);

    // 1 — biskvitning o'zi; 2 — nachinka bo'lmasa ham biskvit.
    if (_step == 0 || (_step == 1 && _layersOf(parts) == 0)) {
      return Biscuit3DView(
        height: _heroH,
        dims: biscuit.dims,
        palette: biscuit.palette,
        fruits: biscuit.fruits,
        photoUrl: biscuit.photoUrl,
      );
    }
    // 3 — TAYYOR TORT: tortning O'Z fotosi, ekrandagi o'lchami tex
    // kartadagi diametrga qarab (cake_photo_view.dart). 3D qurish YO'Q:
    // Mone fotolarida tort oq patnis ustida, fon ham oq — siluet patnis
    // bilan qo'shilib ketar va model goh patnisdan qurilardi.
    // Foto YO'Q — tex kartadan chizilgan vektor illyustratsiya.
    if (_step == 2) {
      final url = _fullUrl(cake.imageUrl);
      if (url == null) {
        return CakeIllustrationView(
          height: _heroH + 30,
          spec: CakeIllustrationSpec.fromTechCard(cake.name, card),
        );
      }
      return CakePhotoView(imageUrl: url, card: card, height: _heroH + 30);
    }
    // 2 — bo'lagi kesilgan «yalang'och» tort, kesimda nachinka. Har qatlam
    // o'z пф'ining tex kartasidan; пф fotosi bo'lsa — kesim qatlamlari
    // fotodan (FillingPhotoLooksBuilder). Painter qatlamlarni TEPADAN
    // pastga oladi — teskari tartib.
    final sources = _layerSources(cake, card, parts);
    return FillingPhotoLooksBuilder(
      urls: [for (final s in sources) s.$2],
      builder: (context, photoLooks) => Filling3DView(
        height: _heroH,
        sponge: biscuit.palette,
        dims: biscuit.dims,
        fillings: [
          for (var k = sources.length - 1; k >= 0; k--)
            (photoLooks[k] ?? sources[k].$1).bandsOf(0),
        ],
        look: FillingLook.neutral,
      ),
    );
  }
}

// Tex kartada blok yo'q — tex kartaga yo'naltirish.
class _EmptyCard extends StatelessWidget {
  final VoidCallback onOpen;

  const _EmptyCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tortning tex kartasi to\'ldirilmagan.\nBloklarni (Бисквит, '
              'Крем, Покрытие ...) tex kartada qo\'shing — konstruktor '
              'shulardan chiziladi',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onOpen,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Tex kartani ochish'),
            ),
          ],
        ),
      ),
    );
  }
}

// Rasm ostidagi qadam tugmasi: raqamli doira + ostida yozuv
// (umumiy konstruktordagi bilan bir xil ko'rinish).
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
            const SizedBox(height: 4),
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

// Полуфабрикатнинг O'Z TEX KARTASI bo'limi: sarlavha kartasi (kichik
// rasm — biskvit / nachinkali bo'lak, nomi, «Полуфабрикат», o'lchami,
// pishirish rejimi; bosilsa tex kartasi muharrirda) va ostida uning
// bloklari masalliqlari bilan.
class _PfSection extends StatelessWidget {
  final ProductModelAdmin pf;
  final CakeBlockRole role;
  // Biskvit rasmi uchun tort o'lchami (1-qadamdagi bilan bir xil).
  final BiscuitDims dims;
  final VoidCallback onOpen;

  const _PfSection({
    required this.pf,
    required this.role,
    required this.dims,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final card = pf.techCard;
    final bases = card?.bases ?? const <TechBase>[];
    final Widget thumb;
    if (role == CakeBlockRole.biscuit) {
      thumb = BiscuitThumb(
        dims: dims,
        palette: BiscuitPalette.of(pf.name, card),
        fruits: BiscuitFruit.detect(pf.name),
        photoUrl: biscuitPhotoUrlOf(card),
      );
    } else {
      final (look, photoUrl) = FillingLook.resolve(pf.name, card);
      thumb = FillingThumb(look: look, photoUrl: photoUrl);
    }
    final info = <String>[
      'Полуфабрикат',
      if (_sizeLine(card).isNotEmpty) _sizeLine(card),
      if (card != null && (card.bakeTimeMin > 0 || card.bakeTempC > 0))
        [
          if (card.bakeTimeMin > 0) '${card.bakeTimeMin} daq',
          if (card.bakeTempC > 0) '${card.bakeTempC} °C',
        ].join(' · '),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: _accentColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onOpen,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _accentColor),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 72, height: 60, child: thumb),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pf.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            info.join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.brown.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.menu_book_outlined,
                      size: 20,
                      color: Colors.brown.shade700,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (bases.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Пф tex kartasida blok yo\'q',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          for (final b in bases) _BlockCard(block: b, card: card!),
      ],
    );
  }
}

// Tex karta bloki: nomi + rol chipi, rasmi (blok rasmi), og'irligi/bo'limi
// va masalliqlar (miqdor — tex kartadagidek, butun partiya uchun).
class _BlockCard extends StatelessWidget {
  final TechBase block;
  final TechCard card;

  const _BlockCard({required this.block, required this.card});

  @override
  Widget build(BuildContext context) {
    final role = CakeBlockRole.of(block);
    final url = _fullUrl(block.imageUrl);
    final weight = block.weightG > 0 ? block.weightG : block.computedWeightG;
    final stages = card.stages;
    final stageName = (stages.isNotEmpty &&
            block.stage >= 1 &&
            block.stage <= stages.length)
        ? stages[block.stage - 1].name
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      block.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    role.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.brown.shade700,
                    ),
                  ),
                ],
              ),
              if (url != null) ...[
                const SizedBox(height: 8),
                // Blok rasmi to'liq va cho'zilmasdan (contain, 4:3).
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ColoredBox(
                      color: const Color(0xFFF7F5FC),
                      child: AppNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
              if (weight > 0 || stageName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (weight > 0)
                      _InfoText(
                        icon: Icons.scale_outlined,
                        text: 'Og\'irligi $weight г',
                      ),
                    if (stageName.isNotEmpty)
                      _InfoText(
                        icon: Icons.account_tree_outlined,
                        text: stageName,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              if (block.ingredients.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Blokda masalliq yo\'q',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              else
                for (var i = 0; i < block.ingredients.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _IngredientRow(item: block.ingredients[i]),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.brown.shade700),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12.5, color: Colors.brown.shade700),
        ),
      ],
    );
  }
}

// Masalliq qatori: nom — miqdor birlik (tex kartadagi butun son).
class _IngredientRow extends StatelessWidget {
  final TechItem item;

  const _IngredientRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${item.amount} ${techUnitLabel(item.unit)}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
