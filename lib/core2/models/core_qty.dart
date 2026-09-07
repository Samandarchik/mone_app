// core2/models/core_qty.dart — mone_core miqdorlari uchun konvert YAGONA
// manbai. Serverga faqat BUTUN base birlik va butun so'm yuboriladi.
// Base birliklar (server `/units`): g (kg=1000 g), ml (l=1000 ml),
// mpcs = 0.001 dona (pcs/portion = 1000 mpcs), mm (m = 1000 mm). Ya'ni
// HAMMA base 1/1000 — UI kg / l / dona / m ko'rsatadi. Umumiy
// `qty_units.dart` (кг/л type satrlari) ustiga base-kod bilan ishlaydigan
// qatlam. Qo'lda `*1000` YOZMA — shu helperlarni ishlat.
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';

/// Base kodning «katta» birligi va faktori (server `/units` jadvali bilan
/// bir xil): g→kg, ml→l, mpcs→pcs, mm→m (hammasi ×1000). Noma'lum kod —
/// o'zi, faktor 1 (eski `pcs`/`m` base sifatida kelsa ham buzilmaydi).
CoreGoodUnit coreDisplayUnitOf(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return const CoreGoodUnit(unit: 'kg', toBase: 1000);
    case 'ml':
      return const CoreGoodUnit(unit: 'l', toBase: 1000);
    case 'mpcs':
      return const CoreGoodUnit(unit: 'pcs', toBase: 1000);
    case 'mm':
      return const CoreGoodUnit(unit: 'm', toBase: 1000);
    default:
      return CoreGoodUnit(unit: baseUnit, toBase: 1);
  }
}

/// Birlik kodi → base faktori (`/units.factor`): kg/l/pcs/portion/m = 1000,
/// g/ml/mpcs/mm = 1. Tovar `units` ro'yxatida bo'lsa o'sha `to_base` ustun.
int coreUnitFactor(String unitCode) {
  switch (unitCode) {
    case 'kg':
    case 'l':
    case 'pcs':
    case 'portion':
    case 'm':
      return 1000;
    default:
      return 1;
  }
}

/// Ko'rsatish birligi nomi: g→kg, ml→l, mpcs/pcs→dona, mm→m, portion→порция.
String coreDisplayUnit(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return 'kg';
    case 'ml':
      return 'l';
    case 'mpcs':
    case 'pcs':
      return 'dona';
    case 'mm':
      return 'm';
    case 'portion':
      return 'порция';
    default:
      return baseUnit;
  }
}

/// Base miqdorni UI matniga: 25000 (g) → "25", 1500 (g) → "1.5",
/// 7000 (mpcs) → "7". Faktor 1000 bo'lsa `qty_units.formatQty` ning kg
/// yo'li (÷1000) ishlatiladi — konvert bitta joyda qoladi.
String coreFormatQty(num baseQty, String baseUnit) {
  final f = coreDisplayUnitOf(baseUnit).toBase;
  return formatQty(baseQty, f == 1000 ? 'kg' : baseUnit);
}

/// "25 kg" / "7 dona" ko'rinishida.
String coreFormatQtyUnit(num baseQty, String baseUnit) =>
    '${coreFormatQty(baseQty, baseUnit)} ${coreDisplayUnit(baseUnit)}';

/// Base miqdor → UI soni (kg/l/dona) — ko'rsatish uchun (saqlanmaydi).
double coreQtyToUi(num baseQty, String baseUnit) {
  final f = coreDisplayUnitOf(baseUnit).toBase;
  return qtyToUi(baseQty, f == 1000 ? 'kg' : baseUnit);
}

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

/// Base miqdor + BIRLIK KODI (masalan retsept `yield_unit: "kg"`, hujjat
/// qatori `unit: "pcs"`) → "1.004 kg". Faktor `/units` jadvalidagidek.
String coreFormatQtyAs(num baseQty, String unitCode) {
  final u = CoreGoodUnit(unit: unitCode, toBase: coreUnitFactor(unitCode));
  return '${coreFormatInUnit(baseQty, u)} ${coreDisplayUnit(unitCode)}';
}

/// Qator summasi: narx (1 birlik, butun so'm) × miqdor (birlikda) → BUTUN so'm.
int coreLineAmount(int baseQty, int price, CoreGoodUnit unit) {
  if (unit.toBase <= 0) return baseQty * price;
  final num v = baseQty * price / unit.toBase;
  return v.round();
}

/// Matndan UI soni (vergul ham nuqta kabi). Bo'sh/xato → null.
double? parseUiQty(String? text) {
  final t = (text ?? '').trim().replaceAll(',', '.').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
