// admin/ui/widgets/filling_color_palette.dart — tex kartadagi RANG PALITRASI
// (FillingColorPalette): tayyor ranglar doirachalari. Tanlangan rang tex
// kartada saqlanadi (tech_card.filling_color, "#RRGGBB") va shef «П/Ф
// Начинка» sahifasidagi 3D tortda nachinka AYNAN shu rangda chiziladi —
// foto va nom/tarkibdan ustun. Xuddi shu palitra «Покрытие» bo'limida
// qoplama rangi uchun ham ishlatiladi (tech_card.coating_color, [title]).
// Tanlangan rangni yana bosish yoki «Rangsiz»
// — tanlovni olib tashlaydi (rang yana foto / tex kartadan aniqlanadi).
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

class FillingColorPalette extends StatelessWidget {
  // Tanlangan rang ("#RRGGBB") yoki '' — tanlanmagan.
  final String value;
  final ValueChanged<String> onChanged;
  // Sarlavha: «Nachinka rangi» (П/Ф Начинка) yoki «Покрытие rangi».
  final String title;

  const FillingColorPalette({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = 'Nachinka rangi',
  });

  @override
  Widget build(BuildContext context) {
    final selected = fillingColorFromHex(value);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (selected != null)
                TextButton.icon(
                  onPressed: () => onChanged(''),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.format_color_reset_outlined, size: 16),
                  label: const Text('Rangsiz'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kFillingPalette)
                _Swatch(
                  color: c,
                  selected: selected != null &&
                      fillingColorToHex(selected) == fillingColorToHex(c),
                  onTap: () {
                    final hex = fillingColorToHex(c);
                    // Tanlanganini yana bosish — tanlovni olib tashlash.
                    onChanged(hex == value.trim().toUpperCase() ? '' : hex);
                  },
                ),
            ],
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
