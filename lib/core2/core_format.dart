// core2/core_format.dart — «Oson rejim» (Bugun / Tez kiritish) uchun YAGONA
// ko'rsatish formati. Tamoyil: foydalanuvchi hech qachon base birlik
// (g/ml/mpcs/mm) ko'rmaydi — faqat kg / l / dona / m, kasr VERGUL bilan,
// pul bo'sh joyli minglik + «so'm», sana `17.09.2026`.
//
// Konvert mantig'i takrorlanmaydi: miqdor `core2/models/core_qty.dart`
// (coreFormatQty / coreFormatInUnit), pul `core/utils/money_input.dart`
// (formatMoneyInput) ustiga yupqa qatlam. Bu fayl Flutter'ga bog'liq emas.
//
// Nomlar `core_widgets.dart` dagi `coreMoney`/`coreDate` bilan URISHMAYDI
// (ikkalasi bitta faylga import qilinadi): bu yerdagilar `…Uz` bilan tugaydi.
import 'package:intl/intl.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';

/// Kasrli sonni o'zbekcha ko'rinishda: 2.5 → «2,5», 3 → «3» (max 3 kasr).
String coreNumUz(num v, {int maxFrac = 3}) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  final s = d.toStringAsFixed(maxFrac).replaceAll(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

/// Butun so'm → «1 250 000» (bo'sh joyli minglik, «so'm» siz).
String coreMoneyUz(num v) => formatMoneyInput(v);

/// Butun so'm → «1 250 000 so'm».
String coreSumUz(num v) => '${formatMoneyInput(v)} so\'m';

/// Base miqdor → «2,5» (ko'rsatish birligida, birliksiz).
String coreQtyUz(num baseQty, String baseUnit) =>
    coreFormatQty(baseQty, baseUnit).replaceAll('.', ',');

/// Base miqdor → «2,5 kg» / «12 dona».
String coreQtyUnitUz(num baseQty, String baseUnit) =>
    '${coreQtyUz(baseQty, baseUnit)} ${coreUnitUz(baseUnit)}';

/// Base miqdor TANLANGAN birlikda → «2,5» (birliksiz).
String coreQtyInUnitUz(num baseQty, CoreGoodUnit unit) =>
    coreFormatInUnit(baseQty, unit).replaceAll('.', ',');

/// Base miqdor TANLANGAN birlikda → «2,5 kg».
String coreQtyUnitInUz(num baseQty, CoreGoodUnit unit) =>
    '${coreQtyInUnitUz(baseQty, unit)} ${coreUnitUz(unit.unit)}';

/// Birlik kodi → odam o'qiydigan nom: g/kg → «kg», mpcs/pcs → «dona»,
/// portion → «porsiya», ml/l → «l», mm/m → «m».
String coreUnitUz(String unitCode) {
  switch (unitCode) {
    case 'g':
    case 'kg':
      return 'kg';
    case 'ml':
    case 'l':
      return 'l';
    case 'mpcs':
    case 'pcs':
      return 'dona';
    case 'portion':
      return 'porsiya';
    case 'mm':
    case 'm':
      return 'm';
    default:
      return coreDisplayUnit(unitCode);
  }
}

/// «YYYY-MM-DD» (yoki RFC3339) → «17.09.2026». Bo'sh → «—».
String coreDateUz(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = iso.length > 10 ? dt.toLocal() : dt;
  return DateFormat('dd.MM.yyyy').format(local);
}

/// RFC3339 → «14:35» (vaqt topilmasa bo'sh satr).
String coreTimeUz(String? rfc) {
  if (rfc == null || rfc.length <= 10) return '';
  final dt = DateTime.tryParse(rfc);
  return dt == null ? '' : DateFormat('HH:mm').format(dt.toLocal());
}

/// Kun yorlig'i: «Bugun» / «Kecha» / «17.09.2026».
String coreDayUz(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = coreIsoDay(iso);
  if (d == coreToday()) return 'Bugun';
  if (d == coreDaysAgo(1)) return 'Kecha';
  return coreDateUz(d);
}

/// «YYYY-MM-DD» bugungi kun.
String coreToday() => DateFormat('yyyy-MM-dd').format(DateTime.now());

/// Bugundan [days] kun oldingi sana, «YYYY-MM-DD».
String coreDaysAgo(int days) => DateFormat('yyyy-MM-dd')
    .format(DateTime.now().subtract(Duration(days: days)));

/// Har qanday sana matnidan faqat kun qismi («2026-09-17T…» → «2026-09-17»).
String coreIsoDay(String iso) => iso.split('T').first;

/// Salomlashuv: soatga qarab «Xayrli tong» / «Xayrli kun» / «Xayrli kech».
String coreGreetingUz([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 11) return 'Xayrli tong';
  if (h < 18) return 'Xayrli kun';
  return 'Xayrli kech';
}
