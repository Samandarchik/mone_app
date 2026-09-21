// admin/ui/widgets/filling_color_palette.dart — tex kartadagi RANG PALITRASI
// (FillingColorPalette): tayyor ranglar doirachalari. Tanlangan rang tex
// kartada saqlanadi (tech_card.filling_color, "#RRGGBB") va shef «П/Ф
// Начинка» sahifasidagi 3D tortda nachinka AYNAN shu rangda chiziladi —
// foto va nom/tarkibdan ustun. Xuddi shu palitra «Покрытие» bo'limida
// qoplama rangi uchun ham ishlatiladi (tech_card.coating_color, [title]).
// «Biskvit rangi» (biscuit_color) uchun ham shu. Palitra odatda YIG'ILGAN
// (bir qator rang) — sarlavhadagi strelka hamma ranglarni ochadi/yig'adi.
// Tanlangan rangni yana bosish yoki «Rangsiz» — tanlovni olib tashlaydi
// (rang yana foto / tex kartadan aniqlanadi).
// fillingColorFromHex / fillingColorToHex — saqlash formati bilan o'girish.
import 'package:flutter/material.dart';

// "#RRGGBB" → Color; bo'sh yoki noto'g'ri qiymat — null.
Color? fillingColorFromHex(String hex) {
  final h = hex.trim();
  if (h.length != 7 || !h.startsWith('#')) return null;
  final v = int.tryParse(h.substring(1), radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

// Color → "#RRGGBB" (katta harf; shaffoflik saqlanmaydi).
String fillingColorToHex(Color c) {
  String two(double ch) =>
      (ch * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
}

// Nachinka/krem/jele uchun tayyor ranglar: oqish-qaymoq, sariq-karamel,
// jigarrang-shokolad, qizil-rezavor, binafsha, yashil.
const List<Color> kFillingPalette = [
  Color(0xFFFFFFFF),
  Color(0xFFFFF3DC),
  Color(0xFFF6E7C8),
  Color(0xFFF3E2A0),
  Color(0xFFF5E26B),
  Color(0xFFF4D35E),
  Color(0xFFF6A821),
  Color(0xFFF28C28),
  Color(0xFFF7A94B),
  Color(0xFFE0A74E),
  Color(0xFFC8863C),
  Color(0xFFB98A55),
  Color(0xFFA47551),
  Color(0xFF8A5A2E),
  Color(0xFF5A3420),
  Color(0xFF2E1A12),
  Color(0xFFF8BBD0),
  Color(0xFFF26C7A),
  Color(0xFFD9364A),
  Color(0xFFC2185B),
  Color(0xFF9E1230),
  Color(0xFF6A1B3A),
  Color(0xFFB39DDB),
  Color(0xFF7E57C2),
  Color(0xFF4B3B8F),
  Color(0xFFCFE09C),
  Color(0xFFA8C66C),
  Color(0xFF8BC34A),
  Color(0xFF5E8C3A),
  Color(0xFF9E9E9E),
];


// Yig'ilgan holatda ko'rinadigan ranglar soni (bir qator).
const int _kCollapsedCount = 6;

class FillingColorPalette extends StatefulWidget {
  // Tanlangan rang ("#RRGGBB") yoki '' — tanlanmagan.
  final String value;
  final ValueChanged<String> onChanged;
  // Sarlavha: «Nachinka rangi», «Покрытие rangi», «Biskvit rangi» ...
  final String title;

  const FillingColorPalette({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = 'Nachinka rangi',
  });

  @override
  State<FillingColorPalette> createState() => _FillingColorPaletteState();
}

class _FillingColorPaletteState extends State<FillingColorPalette> {
  // Palitra tex kartada ko'p joy egallamasin: odatda YIG'ILGAN — faqat bir
  // qator rang (tanlangani har doim ko'rinadi); sarlavhadagi strelka bosilsa
  // hamma ranglar ochiladi, yana bosilsa yig'iladi.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selected = fillingColorFromHex(widget.value);
    final selectedHex = selected == null ? null : fillingColorToHex(selected);

    // Yig'ilganda: birinchi bir nechta rang; tanlangan rang ular orasida
    // bo'lmasa — eng boshiga qo'yiladi (nima tanlangani ko'rinib tursin).
    final List<Color> shown;
    if (_expanded) {
      shown = kFillingPalette;
    } else {
      final first = kFillingPalette.take(_kCollapsedCount).toList();
      final inFirst = selectedHex == null ||
          first.any((c) => fillingColorToHex(c) == selectedHex);
      shown = inFirst
          ? first
          : [selected!, ...first.take(_kCollapsedCount - 1)];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sarlavha qatori butunlay bosiladi — strelka ochadi/yig'adi.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                const Icon(Icons.palette_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (selected != null)
                  TextButton.icon(
                    onPressed: () => widget.onChanged(''),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.red,
                    ),
                    icon: const Icon(Icons.format_color_reset_outlined,
                        size: 16),
                    label: const Text('Rangsiz'),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.brown.shade700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in shown)
                  _Swatch(
                    color: c,
                    selected: selectedHex == fillingColorToHex(c),
                    onTap: () {
                      final hex = fillingColorToHex(c);
                      // Tanlanganini yana bosish — tanlovni olib tashlash.
                      widget.onChanged(hex == selectedHex ? '' : hex);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Belgi rangi fon yorug'ligiga qarab (och rangda qora, to'qda oq).
    final onColor =
        color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? const Color(0xFF5D4037) : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected ? Icon(Icons.check, size: 18, color: onColor) : null,
      ),
    );
  }
}
