/// Chek raqamini KO'RSATISH uchun qisqartirish.
///
/// Backend 2026-08-22 gacha raqamni nol bilan to'ldirib yozardi:
/// `26-08-22-P000022`. Nollar hech qanday ma'no bermasdi, chekda va
/// ro'yxatda esa raqamni o'qishga xalaqit berardi. Yangi raqamlar
/// to'ldirilmaydi (`26-08-22-P22`), eski cheklar esa bazada o'z uzun
/// raqami bilan qoladi — ular allaqachon bosilgan va loyalty/telegram
/// yozuvlariga bog'langan.
///
/// Shuning uchun nollar faqat EKRANDA olib tashlanadi. Serverga so'rov
/// yuborilganda HAMISHA asl `order_number` ishlatiladi.
///
/// Backendda aynan shu qoida: `db.ShortOrderNumber`.
final RegExp _padZeros = RegExp(r'-([A-Z])0+(\d)');

/// `26-08-22-P000022` → `26-08-22-P22`. Yangi formatga tegmaydi.
String shortOrderNumber(dynamic number) {
  final s = number?.toString() ?? '';
  if (s.isEmpty) return '';
  return s.replaceAllMapped(_padZeros, (m) => '-${m[1]}${m[2]}');
}
