/// Mahsulot birligi (type) uchun yagona kanonik ro'yxat — hammasi kichik harfda.
const List<String> kProductTypeOptions = [
  'шт',
  'кг',
  'гр',
  'л',
  'мл',
  'пачка',
  'порция',
  'упаковка',
  'м',
];

/// Eski/xato yozilgan qiymatlarni kanonik kichik-harf shaklga keltiradi
/// (katta harf, ortiqcha probel, lotincha "p", "литр"→"л", "кл"→"кг").
String normalizeProductType(String raw) {
  final t = raw.trim().toLowerCase().replaceAll('p', 'р');
  const map = {'литр': 'л', 'кл': 'кг'};
  return map[t] ?? t;
}

/// UI nomlari; API qiymatlari tarixiy shaklda qoladi.
String productUnitLabel(String unit) =>
    const {
      'шт': 'dona',
      'кг': 'kg',
      'гр': 'g',
      'л': 'litr',
      'мл': 'ml',
      'пачка': 'pachka',
      'порция': 'porsiya',
      'упаковка': 'qadoq',
      'м': 'metr',
    }[unit] ??
    (unit.isEmpty ? 'birlik' : unit);
