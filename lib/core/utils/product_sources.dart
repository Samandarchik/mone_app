// core/utils/product_sources.dart — bozor mahsulotining «Yuk qayerdan keladi»
// manbalari (samarqand / toshkent / zagranitsa) uchun YAGONA manba: kanonik
// tartib, foydalanuvchiga ko'rsatiladigan nomlar va JSON parse qoidasi.
//
// API KONTRAKT: mahsulot `sources` ro'yxati (kanonik tartib, dublikatsiz, hech
// qachon bo'sh emas) + eski APK'lar uchun `source` (= sources[0], asosiy manba).
// Eski backend / eski qatorlar `sources` yubormasligi mumkin — shunda
// `[source]`, u ham bo'sh bo'lsa `['samarqand']`.
// Admin mahsulot modeli ham, ombor katalogi ham SHUNI ishlatadi.

// Kanonik tartib: samarqand → toshkent → zagranitsa.
const List<String> kProductSources = ['samarqand', 'toshkent', 'zagranitsa'];

// Manba bo'lmasa (eski qator) — standart manba.
const String kDefaultProductSource = 'samarqand';

// Manba kodi -> ko'rsatiladigan nom.
const Map<String, String> kProductSourceLabels = {
  'samarqand': 'Samarqand',
  'toshkent': 'Toshkent',
  'zagranitsa': 'Zagranitsa',
};

// Bitta manba kodining nomi (noma'lum kod o'zicha qaytadi).
String productSourceLabel(String code) => kProductSourceLabels[code] ?? code;

// Dublikatsiz, kanonik tartibdagi ro'yxat. Noma'lum (kelajakdagi) kodlar
// tashlanmaydi — kelgan tartibida oxiriga qo'shiladi.
List<String> canonicalProductSources(Iterable<String> values) {
  final seen = <String>{};
  for (final v in values) {
    final s = v.trim();
    if (s.isNotEmpty) seen.add(s);
  }
  return [
    for (final s in kProductSources)
      if (seen.contains(s)) s,
    for (final s in seen)
      if (!kProductSources.contains(s)) s,
  ];
}

// Parse qoidasi: `sources` yo'q / null / bo'sh -> [source]; `source` ham
// bo'sh -> ['samarqand']. Natija hech qachon bo'sh emas.
List<String> parseProductSources(Object? sources, Object? source) {
  if (sources is List) {
    final list =
        canonicalProductSources(sources.map((e) => e?.toString() ?? ''));
    if (list.isNotEmpty) return list;
  }
  final single = source?.toString().trim() ?? '';
  return [single.isEmpty ? kDefaultProductSource : single];
}
