/// Miqdor birliklari uchun yagona manba.
///
/// API KONTRAKT: birligi (type) кг-oilasi (кг/kg/кл) yoki л-oilasi
/// (л/литр/l/litr) bo'lgan mahsulotlarda API orqali yuradigan HAR QANDAY
/// miqdor — BUTUN gramm/millilitr (1.5 kg -> 1500). Boshqa birliklar
/// (шт, гр, мл, пачка, порция, упаковка, м) o'zgarmagan.
/// UI'da esa foydalanuvchi hamon kg/l ko'radi va kiritadi.
library;

/// кг/л mahsulotlar API'da BUTUN gr/ml sifatida yuradi (1.5 kg -> 1500).
int qtyUnitFactor(String? type) {
  final t = (type ?? '').trim().toLowerCase();
  switch (t) {
    case 'кг':
    case 'kg':
    case 'кл':
    case 'л':
    case 'литр':
    case 'l':
    case 'litr':
      return 1000;
    default:
      return 1;
  }
}

/// API qiymatini (gramm/ml) UI qiymatiga (kg/l) o'giradi.
double qtyToUi(num apiQty, String? type) => apiQty / qtyUnitFactor(type);

/// UI'da kiritilgan (kg/l) qiymatni API butun soniga o'giradi.
num qtyFromUi(num uiQty, String? type) {
  final f = qtyUnitFactor(type);
  if (f == 1) return uiQty;
  return (uiQty * f).round();
}

// ESLATMA: bu yerda ilgari qtyFromUiSafe (gramm-yozish himoyasi: 1000+
// kiritilsa gramm deb olinardi) bor edi. U eski APK'lar kg maydoniga gramm
// yozgan davr uchun edi; majburiy update joriy qilingach olib tashlandi —
// endi kg maydoniga yozilgan 1000 haqiqatan 1000 kg deb yuboriladi
// (ilgari 1 kg bo'lib qolardi). Server tomonidagi legacyQtyIn faqat ESKI
// (X-Qty-Unit headersiz) klientlarga tegadi, yangi ilovaga ta'siri yo'q.

/// API miqdorini UI ko'rinishida formatlaydi (max 3 kasr, oxirgi nollar olib
/// tashlanadi): 1500 (кг) -> "1.5", 2000 (кг) -> "2", 7 (шт) -> "7".
String formatQty(num apiQty, String? type) {
  final ui = qtyToUi(apiQty, type);
  if (ui == ui.roundToDouble()) return ui.toInt().toString();
  return ui.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

/// "1.5 кг" ko'rinishida formatlaydi.
String formatQtyUnit(num apiQty, String? type) =>
    '${formatQty(apiQty, type)} ${type ?? ''}'.trim();

// Nomdagi "1шт=900гр", "1пачка = 0.5 кг" — dona nomi va hajmi.
final _packInName = RegExp(
  r'1\s*([^\s\d=()]+)\s*=\s*(\d+(?:[.,]\d+)?)\s*(кг|kg|гр|gr|г|g|мл|ml|л|l)',
  caseSensitive: false,
);

/// кг/л mahsulot uchun dona sonini qo'shib formatlaydi: "2шт = 1.8 кг".
/// Dona hajmi (eng kichik birlikda): sellStep (to'liq birlikdan farqli
/// bo'lsa), aks holda nomdagi "1шт=900гр". Dona nomi nomdan ("пачка"),
/// topilmasa "шт". Hajm noma'lum yoki miqdor donaga bo'linmasa — "1.8 кг".
String formatQtyWithPacks(num apiQty, String? type, int sellStep,
    {String name = ''}) {
  final plain = formatQtyUnit(apiQty, type);
  final f = qtyUnitFactor(type);
  if (f == 1 || apiQty <= 0) return plain;

  var label = 'шт';
  num pack = 0;
  final m = _packInName.firstMatch(name);
  if (m != null) {
    label = m.group(1)!;
    final v = double.tryParse(m.group(2)!.replaceAll(',', '.')) ?? 0;
    final u = m.group(3)!.toLowerCase();
    final big = u == 'кг' || u == 'kg' || u == 'л' || u == 'l';
    pack = (v * (big ? 1000 : 1)).round();
  }
  if (sellStep > 0 && sellStep != f) pack = sellStep;
  if (pack <= 0) return plain;

  final packs = apiQty / pack;
  if ((packs - packs.round()).abs() > 1e-6 || packs.round() <= 0) return plain;
  return '${packs.round()}$label = $plain';
}
