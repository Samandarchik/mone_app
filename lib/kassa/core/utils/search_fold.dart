/// Qidiruvni ALIFBODAN QAT'I NAZAR moslashtirish uchun matnni umumiy shaklga
/// keltiradi: kirill harflarni lotinga o'giradi, o'zbekcha apostroflarni
/// (o', g', ʻ) olib tashlaydi va kichik harfga tushiradi.
///
/// Shu sababli kassir «choy» deb yozsa ham, «чой» deb yozsa ham bir xil
/// natijaga tushadi va ikkalasi ham topiladi (menyu nomi lotin/rus/turk
/// bo'lishidan qat'i nazar). Bir tomonga (lotinchaga) o'girib solishtirilgani
/// uchun ikkala yo'nalish ham ishlaydi.
///
/// Masalan: «чой» → «choy», «Осh» → «osh», «шашлык» → «shashlik».
String searchFold(String input) {
  var s = input.toLowerCase().trim();
  // O'zbekcha apostrof variantlari va yumshoq/qattiq belgilar — olib tashlanadi
  // ("o'rik" → "orik", "съезд" → "sezd").
  const strip = ['ʻ', 'ʼ', '‘', '’', '`', "'", 'ъ', 'ь'];
  for (final ch in strip) {
    s = s.replaceAll(ch, '');
  }
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_cyrToLat[ch] ?? ch);
  }
  return buf.toString();
}

/// Kirill (rus + o'zbek kirill) → lotin. Kichik harflar (kirish oldin
/// lowercase qilinadi). Ba'zi harflar ko'p belgiga o'giriladi (ч→ch).
const Map<String, String> _cyrToLat = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g', 'д': 'd', 'е': 'e',
  'ё': 'yo', 'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'қ': 'q',
  'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'ў': 'o', 'п': 'p', 'р': 'r',
  'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'x', 'ҳ': 'h', 'ц': 'ts',
  'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ы': 'i', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};
