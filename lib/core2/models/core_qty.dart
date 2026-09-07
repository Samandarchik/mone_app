// core2/models/core_qty.dart — mone_core miqdorlari uchun konvert YAGONA
// manbai. Serverga faqat BUTUN base birlik (g/ml/pcs/m) va butun so'm
// yuboriladi; UI kg/l ko'rsatadi. Umumiy `qty_units.dart` (кг/л type
// satrlari) ustiga base-kod (`g`,`ml`) va tovar birliklari (`to_base`)
// bilan ishlaydigan qatlam. Qo'lda `*1000` YOZMA — shu helperlarni ishlat.
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';

/// Base kodni umumiy `qty_units` type'iga o'giradi: g → 'kg' (faktor 1000),
/// ml → 'l' (1000), qolganlari o'zi (faktor 1).
String _displayType(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return 'kg';
    case 'ml':
      return 'l';
    default:
      return baseUnit;
  }
}

/// Ko'rsatish birligi nomi: g→kg, ml→l, pcs→dona, m→m.
String coreDisplayUnit(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return 'kg';
    case 'ml':
      return 'l';
    case 'pcs':
      return 'dona';
    default:
      return baseUnit;
  }
}

/// Base miqdorni UI matniga: 25000 (g) → "25", 1500 (g) → "1.5", 7 (pcs) → "7".
String coreFormatQty(num baseQty, String baseUnit) =>
    formatQty(baseQty, _displayType(baseUnit));

/// "25 kg" / "7 dona" ko'rinishida.
String coreFormatQtyUnit(num baseQty, String baseUnit) =>
    '${coreFormatQty(baseQty, baseUnit)} ${coreDisplayUnit(baseUnit)}';

/// Base miqdor → UI soni (kg/l) — ko'rsatish uchun (saqlanmaydi).
double coreQtyToUi(num baseQty, String baseUnit) =>
    qtyToUi(baseQty, _displayType(baseUnit));

/// Tanlangan birlikda kiritilgan UI soni → BUTUN base miqdor.
/// (2.5 kg, to_base=1000) → 2500. Manfiy/NaN → 0.
int coreQtyFromUi(num uiQty, CoreGoodUnit unit) {
  if (uiQty.isNaN || uiQty.isInfinite) return 0;
  return (uiQty * unit.toBase).round();
}

/// Base miqdorni tanlangan birlikdagi UI soniga (2500, kg/1000) → 2.5.
double coreQtyInUnit(num baseQty, CoreGoodUnit unit) =>
    unit.toBase == 0 ? baseQty.toDouble() : baseQty / unit.toBase;

/// Base miqdorni tanlangan birlikda formatlaydi (max 3 kasr, nolsiz).
String coreFormatInUnit(num baseQty, CoreGoodUnit unit) {
  final ui = coreQtyInUnit(baseQty, unit);
  if (ui == ui.roundToDouble()) return ui.toInt().toString();
  return ui.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

/// Qator summasi: narx (1 birlik, butun so'm) × miqdor (birlikda) → BUTUN so'm.
int coreLineAmount(int baseQty, int price, CoreGoodUnit unit) {
  if (unit.toBase <= 0) return baseQty * price;
  // Butun arifmetika: (qty*price)/to_base yaxlitlab.
  final num v = baseQty * price / unit.toBase;
  return v.round();
}

/// Matndan UI soni (vergul ham nuqta kabi). Bo'sh/xato → null.
double? parseUiQty(String? text) {
  final t = (text ?? '').trim().replaceAll(',', '.').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
