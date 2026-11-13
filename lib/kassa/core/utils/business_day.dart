/// Ish kuni (business day) — kun chegarasi yarim tunda EMAS.
///
/// Kafe yarim tundan keyin ham ishlaydi: soat 00:52 da yopilgan chek
/// KECHAGI kechning savdosi. Ilgari ilova ham, backend ham kalendar kunini
/// ishlatardi va yarim tunda ro'yxat bo'shab qolar, kechqurungi savdo esa
/// ertangi kunga tushib ketardi.
///
/// Chegara — [kBusinessDayStartHour] (02:00). Ya'ni [02:00, ertasi 02:00)
/// oralig'i BITTA kun bo'lib, u boshlangan sana bilan nomlanadi:
///
///   21-avgust 23:40 → 21-avgust
///   22-avgust 00:52 → 21-avgust
///   22-avgust 01:59 → 21-avgust
///   22-avgust 02:00 → 22-avgust
///
/// Backendda aynan shu qoida: `BUSINESS_DAY_START_HOUR` (internal/db/business_day.go).
/// Ikkalasi bir xil bo'lishi SHART — aks holda ilova so'ragan sana bilan
/// server qaytargan oyna mos kelmaydi.
const int kBusinessDayStartHour = 2;

/// Berilgan vaqtga mos ish kuni (soat 00:00 ga qirqilgan sana).
DateTime businessDate(DateTime t) {
  final shifted = t.subtract(const Duration(hours: kBusinessDayStartHour));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Hozirgi ish kuni. Ekranlarda `DateTime.now()` o'rniga shu ishlatiladi.
DateTime businessToday() => businessDate(DateTime.now());

/// Kalendar sanani "YYYY-MM-DD" ga aylantirish (vaqt tashlanadi).
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// API uchun "YYYY-MM-DD".
String businessDateStr(DateTime t) => ymd(businessDate(t));

/// Hozirgi ish kuni "YYYY-MM-DD" ko'rinishida.
String businessTodayStr() => businessDateStr(DateTime.now());

/// Sana ish kuni bo'yicha "bugun"mi?
bool isBusinessToday(DateTime d) {
  final today = businessToday();
  return d.year == today.year && d.month == today.month && d.day == today.day;
}

/// Ish kuni QACHON boshlanadi — sana + [kBusinessDayStartHour] (02:00).
///
/// Tarix ekranlarida foydalanuvchi shu vaqtni O'ZGARTIRA oladi (masalan
/// 10:00), shuning uchun sana endi 00:00 emas, boshlanish vaqtini olib
/// yuradi. Defolt — 02:00, ya'ni avvalgi xatti-harakat.
DateTime businessDayStart(DateTime day) =>
    DateTime(day.year, day.month, day.day, kBusinessDayStartHour);

/// Hozirgi ish kunining boshlanishi (bugun 02:00 yoki kechasi — kechagi 02:00).
DateTime businessTodayStart() => businessDayStart(businessToday());

/// Vaqt oynasi [start, start+24soat) qaysi ISH KUNLARIga tegadi — API
/// «YYYY-MM-DD» ro'yxati.
///
/// Boshlanish 02:00 bo'lsa oyna aynan bitta ish kuni (bitta so'rov).
/// Boshqa soat tanlansa oyna ikkita ish kuniga bo'linadi: masalan
/// 10:00 → ertasi 10:00 = shu kunning 10:00–02:00 qismi + ertangi
/// kunning 02:00–10:00 qismi.
List<String> businessDatesForWindow(DateTime start, DateTime end) {
  final first = businessDate(start);
  final last = businessDate(end.subtract(const Duration(minutes: 1)));
  final out = <String>[];
  var d = first;
  while (!d.isAfter(last) && out.length < 4) {
    out.add(ymd(d));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

/// Server bergan vaqt matnidan («2026-08-22T21:22:03+05:00») MAHALLIY
/// DateTime. Ekranda vaqt aynan shu matnning 11–16 belgisidan olinadi
/// («21:22»), shuning uchun filtr ham xuddi shu qirqim bilan ishlaydi —
/// vaqt mintaqasi tufayli ro'yxatdagi soat bilan filtr farq qilmaydi.
DateTime? parseServerTime(dynamic ts) {
  final s = ts?.toString() ?? '';
  if (s.length < 16) return null;
  return DateTime.tryParse('${s.substring(0, 10)} ${s.substring(11, 16)}');
}
