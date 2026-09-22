// shef/ui/shef_cake_constructor_page.dart — TORTNING O'Z konstruktori
// (ShefCakeConstructorPage): «Торты» bo'limida (shef_cakes_page.dart) tort
// bosilganda ochiladi. Umumiy konstruktordan (shef_constructor_page.dart —
// kategoriyalardan biskvit/nachinka/qoplama TANLASH) farqi: bu yerda hech
// narsa tanlanmaydi — hammasi shu tortning TEX KARTASIDAN (masalan Рафаэлло)
// chiziladi. 3 qadam (rasm ostidagi tugmalar):
//   1 — Biskvit: tortning biskvitining o'zi (3D) — rangi/turi tex kartadagi
//       biskvit blokidan (nomi/masalliqlari), o'lchami tex kartadan.
//   2 — Kesim: shu tortning BO'LAGI kesilgan holda — kesimda nachinka
//       qatlamlari (tex kartadagi krem/nachinka/konfi bloklari, pastdan
//       yuqoriga, har biri o'z rangida). Nachinka bloki bo'lmasa — faqat
//       biskvit.
//   3 — Tort: TAYYOR TORT — vektor ILLYUSTRATSIYA (cake_illustration.dart,
//       referens: Mone'ning yassi grafikasi — patnis, lenta va bant, glazur,
//       dekor doirasi). Qoplama/glazur rangi, kokos/yong'oq fakturasi va
//       dekor (Рафаэлло, безе, миндаль, mevalar ...) — tex karta
//       bloklaridan (CakeIllustrationSpec.fromTechCard).
// Qadam ostida shu qadamga tegishli tex karta BLOKLARI: nomi, rol chipi,
// rasmi (tex kartadagi blok rasmi), og'irligi, bo'limi va masalliqlar.
// Blok roli nomidan (CakeBlockRole.of): бисквит/корж → biskvit; покрытие/
// глазурь/выравнивание → qoplama; декор/украшение → bezak; пропитка/сироп/
// сборка → bosqich (qatlam qo'shmaydi); qolgani (крем, начинка, конфи, мусс)
// → nachinka. Ranglar — boshqa bo'limlardagi kabi tortning tex kartasidagi
// palitralardan: «Biskvit rangi» (korjlar), «Nachinka rangi» (hamma nachinka
// qatlami bir rangda), «Покрытие rangi» (qoplama); tanlanmagan bo'lsa —
// avtomatik, tort nomi/bloklari/masalliqlaridan (BiscuitPalette.of /
// FillingLook.fromTechCard / coatOf). Tex karta AppBar tugmasidan
// tahrirlanadi — saqlangach (provider) konstruktor o'zi yangilanadi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_illustration.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

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

// Tex kartadagi blok rasmi to'liq URL'i (yo'q — null).
String? _blockImageUrl(TechBase b) {
  final raw = b.imageUrl;
  if (raw.isEmpty) return null;
  return raw.startsWith('http') ? raw : '${AppUrls.baseUrl}$raw';
}

class ShefCakeConstructorPage extends StatefulWidget {
  final ProductModelAdmin cake;

  const ShefCakeConstructorPage({super.key, required this.cake});

  @override
  State<ShefCakeConstructorPage> createState() =>
      _ShefCakeConstructorPageState();
}

class _ShefCakeConstructorPageState extends State<ShefCakeConstructorPage> {
  int _step = 0;

  // Tort tex kartasi — boshqa bo'limlardagi kabi 3 ta palitra (Biskvit /
  // Nachinka / Покрытие rangi); saqlangach konstruktor shu ranglarda.
  void _openTechCard(ProductModelAdmin cake) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TechCardEditorPage(
          product: cake,
          canEditPrices: false,
          showBiscuitColor: true,
          showFillingColor: true,
          showCoatingColor: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tex karta saqlangach provider xotirada yangilanadi — eng yangi nusxa.
    final cake = context.select<ProductProviderAdmin, ProductModelAdmin>(
      (p) => p.products.firstWhere(
        (x) => x.id == widget.cake.id,
        orElse: () => widget.cake,
      ),
    );
    final card = cake.techCard;
    final blocks = card?.bases ?? const <TechBase>[];

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
                  child: _hero(cake, card!, blocks),
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
                Expanded(
                  child: _BlocksPanel(
                    title: '${_step + 1}. ${_steps[_step].$2}',
                    blocks: _blocksOfStep(blocks),
                    emptyHint: _steps[_step].$3,
                    card: card,
                  ),
                ),
              ],
            ),
    );
  }

  // Qadamga tegishli bloklar: 1 — biskvit; 2 — nachinka; 3 — qoplama, bezak
  // va boshqa bosqichlar (tartib saqlanadi).
  List<TechBase> _blocksOfStep(List<TechBase> blocks) {
    bool keep(CakeBlockRole r) => switch (_step) {
          0 => r == CakeBlockRole.biscuit,
          1 => r == CakeBlockRole.filling,
          _ => r == CakeBlockRole.coat ||
              r == CakeBlockRole.decor ||
              r == CakeBlockRole.other,
        };
    return [for (final b in blocks) if (keep(CakeBlockRole.of(b))) b];
  }

  // 3D: qadamga qarab biskvit / kesilgan bo'lakli tort / butun tort.
  Widget _hero(ProductModelAdmin cake, TechCard card, List<TechBase> blocks) {
    final dims = BiscuitDims.fromTechCard(card);
    // Nachinka qatlamlari soni — tex kartadagi nachinka bloklari soni.
    var fillCount = 0;
    for (final b in blocks) {
      if (CakeBlockRole.of(b) == CakeBlockRole.filling) fillCount++;
    }
    // Ranglar — boshqa bo'limlardagi kabi, TORT tex kartasining palitralari:
    // korjlar — «Biskvit rangi» (biscuit_color), nachinka — «Nachinka rangi»
    // (filling_color, hamma qatlam bir xil). Palitrada tanlanmagan bo'lsa —
    // avtomatik: tort nomi / bloklar / masalliqlardan.
    final sponge = BiscuitPalette.of(cake.name, card);
    final fillingLook = FillingLook.fromTechCard(cake.name, card);
    final fillings = [
      for (var i = 0; i < fillCount; i++) fillingLook.bandsOf(0),
    ];

    // 1 — biskvitning o'zi; 2 — nachinka bloki bo'lmasa ham biskvit.
    if (_step == 0 || (_step == 1 && fillings.isEmpty)) {
      return Biscuit3DView(
        height: _heroH,
        dims: dims,
        palette: sponge,
        fruits: BiscuitFruit.detect(cake.name),
      );
    }
    // 3 — TAYYOR TORT: vektor illyustratsiya (cake_illustration.dart) —
    // qoplama/glazur rangi, faktura va dekor tex kartadan.
    if (_step == 2) {
      return CakeIllustrationView(
        height: _heroH + 30,
        spec: CakeIllustrationSpec.fromTechCard(cake.name, card),
      );
    }
    // 2 — bo'lagi kesilgan «yalang'och» tort, kesimda nachinka. Painter
    // qatlamlarni TEPADAN pastga oladi — teskari tartib.
    return Filling3DView(
      height: _heroH,
      sponge: sponge,
      dims: dims,
      fillings: fillings.reversed.toList(),
      look: FillingLook.neutral,
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

// Qadamning bloklari: sarlavha, so'ng har blok — nomi + rol chipi, rasmi,
// og'irligi/bo'limi va masalliqlar (miqdor — tex kartadagidek, butun partiya
// uchun). Blok yo'q — izoh.
class _BlocksPanel extends StatelessWidget {
  final String title;
  final List<TechBase> blocks;
  final String emptyHint;
  final TechCard card;

  const _BlocksPanel({
    required this.title,
    required this.blocks,
    required this.emptyHint,
    required this.card,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              emptyHint,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          for (final b in blocks) _BlockCard(block: b, card: card),
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  final TechBase block;
  final TechCard card;

  const _BlockCard({required this.block, required this.card});

  @override
  Widget build(BuildContext context) {
    final role = CakeBlockRole.of(block);
    final url = _blockImageUrl(block);
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AppNetworkImage(
                    imageUrl: url,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
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
