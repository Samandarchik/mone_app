// «Tarqatish» matritsasining sof mantig'i — `lib/core2/ui/distribute_logic.dart`:
// matritsa → `POST /docs/quick-batch` tanasi (bo'sh ustun va 0 kataklar
// yuborilmaydi), qator/ustun jamlari, qoldiqdan oshib ketish, yuborishdan
// oldingi tekshiruv, xatodagi `details.index` → ombor.
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/core2/ui/distribute_logic.dart';

// Manba: «Резка и Украшение» (11). Do'konlar: Гелион 5, Мархабо 18,
// Сибирский 23, Фреско 24 (SH5_BIZNES_MANTIQ P14).
const int kFrom = 11;
const List<int> kShops = [5, 18, 23, 24];

const _rows = <DistGoodRow>[
  DistGoodRow(goodId: 10479, name: 'Чизкейк Малина', unit: 'pcs', stock: 30000),
  DistGoodRow(goodId: 10624, name: 'Ассорти Ириска', unit: 'pcs', stock: 12000),
  DistGoodRow(goodId: 10245, name: 'Panna paste', unit: 'kg', stock: 5000),
];

/// 3 tovar × 4 do'kon: uchinchi do'kon (23) butunlay bo'sh, ikkinchi tovar
/// faqat bitta do'konga ketadi.
final _matrix = <int, Map<int, int>>{
  10479: {5: 12000, 18: 8000, 24: 4000},
  10624: {5: 6000, 23: 0},
  10245: {18: 2500, 24: 1500},
};

int _qtyOf(int goodId, int skladId) => _matrix[goodId]?[skladId] ?? 0;

void main() {
  group('Matritsa → quick-batch tanasi', () {
    final batch = distBuildBatch(
      fromSklad: kFrom,
      dests: kShops,
      rows: _rows,
      qtyOf: _qtyOf,
      docDate: '2026-09-21',
      comment: 'tarqatish 04:00',
    );

    test('bo\'sh ustun uchun hujjat YARATILMAYDI', () {
      expect(batch.count, 3);
      expect(batch.dests, [5, 18, 24], reason: 'Сибирский (23) bo\'sh');
    });

    test('0 kataklar qator bo\'lib yuborilmaydi', () {
      final first = batch.docs.first;
      final lines = first['lines'] as List;
      expect(lines.length, 2, reason: 'Гелион: 2 tovar (10245 yo\'q)');
      expect((lines.first as Map)['good_id'], 10479);
      expect((lines.first as Map)['qty'], 12000);
      expect((lines.first as Map)['unit'], 'pcs');
    });

    test('hujjat sarlavhasi: tur, sana, omborlar, izoh', () {
      final d = batch.docs[1];
      expect(d['type'], 'transfer');
      expect(d['doc_date'], '2026-09-21');
      expect(d['from_sklad'], kFrom);
      expect(d['to_sklad'], 18);
      expect(d['comment'], 'tarqatish 04:00');
      expect((d['lines'] as List).length, 2); // 10479 + 10245
    });

    test('so\'rov tanasi — {"docs": [...]}', () {
      expect(batch.toJson(), {'docs': batch.docs});
      expect(batch.isEmpty, isFalse);
    });

    test('hujjatlar tartibi = tanlangan omborlar tartibi', () {
      final order = [for (final d in batch.docs) d['to_sklad']];
      expect(order, batch.dests);
    });

    test('manbaga teng va takroriy ombor tashlab yuboriladi', () {
      final b = distBuildBatch(
        fromSklad: kFrom,
        dests: const [5, kFrom, 5, 18],
        rows: _rows,
        qtyOf: _qtyOf,
      );
      expect(b.dests, [5, 18]);
    });

    test('hamma katak 0 bo\'lsa hujjat yo\'q', () {
      final b = distBuildBatch(
        fromSklad: kFrom,
        dests: kShops,
        rows: _rows,
        qtyOf: (_, __) => 0,
      );
      expect(b.isEmpty, isTrue);
      expect(b.count, 0);
    });

    test('manfiy katak ham yuborilmaydi', () {
      final b = distBuildBatch(
        fromSklad: kFrom,
        dests: const [5],
        rows: _rows,
        qtyOf: (g, s) => g == 10479 ? -5 : 0,
      );
      expect(b.isEmpty, isTrue);
    });

    test('sana/izoh bo\'sh bo\'lsa maydon yuborilmaydi', () {
      final b = distBuildBatch(
        fromSklad: kFrom,
        dests: const [5],
        rows: _rows,
        qtyOf: _qtyOf,
        comment: '   ',
      );
      expect(b.docs.first.containsKey('doc_date'), isFalse);
      expect(b.docs.first.containsKey('comment'), isFalse);
    });

    test('akt uchun ham ishlaydi (type almashtiriladi)', () {
      final b = distBuildBatch(
        fromSklad: kFrom,
        dests: const [5],
        rows: _rows,
        qtyOf: _qtyOf,
        type: 'act',
      );
      expect(b.docs.first['type'], 'act');
    });
  });

  group('Jamlar va qoldiq', () {
    test('qator jami = ustunlar yig\'indisi', () {
      expect(distRowTotal(10479, kShops, _qtyOf), 24000);
      expect(distRowTotal(10624, kShops, _qtyOf), 6000);
      expect(distRowTotal(10245, kShops, _qtyOf), 4000);
    });

    test('ustun jami bo\'sh ustunda 0', () {
      expect(distColumnTotal(5, _rows, _qtyOf), 18000);
      expect(distColumnTotal(23, _rows, _qtyOf), 0);
    });

    test('qator jami qoldiqdan oshsa qizil eslatma', () {
      // Чизкейк: 24 000 ≤ 30 000 — normal.
      expect(distRowOverStock(24000, 30000), isFalse);
      // Ассорти: 12 000 qoldiqda, 12 001 so'ralsa — oshib ketdi.
      expect(distRowOverStock(12001, 12000), isTrue);
      expect(distRowOverStock(12000, 12000), isFalse);
    });

    test('bo\'sh qatorda (0) eslatma chiqmaydi', () {
      expect(distRowOverStock(0, 0), isFalse);
      expect(distRowOverStock(0, -500), isFalse);
    });

    test('nolmas kataklar soni', () {
      expect(distFilledCells(_rows, kShops, _qtyOf), 6);
    });

    test('ustun xulosasi: bir xil birlikda — miqdor', () {
      // Гелион (5): ikkala tovar ham «pcs».
      final s = distColumnSummary(5, _rows, _qtyOf);
      expect(s.goods, 2);
      expect(s.qty, 18000);
      expect(s.unit, 'pcs');
    });

    test('aralash birlik (pcs + kg) — miqdor yig\'ilmaydi', () {
      // Мархабо (18): Чизкейк «pcs» + Panna paste «kg».
      final s = distColumnSummary(18, _rows, _qtyOf);
      expect(s.goods, 2);
      expect(s.qty, isNull);
      expect(s.unit, isEmpty);
    });

    test('bo\'sh ustun xulosasi bo\'sh', () {
      expect(distColumnSummary(23, _rows, _qtyOf).isEmpty, isTrue);
    });
  });

  group('Yuborishdan oldingi tekshiruv', () {
    test('hammasi joyida — xato yo\'q', () {
      expect(
        distValidate(
            fromSklad: kFrom, dests: kShops, rows: _rows, qtyOf: _qtyOf),
        isNull,
      );
    });

    test('manba tanlanmagan', () {
      expect(
        distValidate(
            fromSklad: null, dests: kShops, rows: _rows, qtyOf: _qtyOf),
        'Qaysi ombordan — tanlang',
      );
    });

    test('bitta ombor — kamida 2 ta kerak', () {
      final err = distValidate(
          fromSklad: kFrom, dests: const [5], rows: _rows, qtyOf: _qtyOf);
      expect(err, contains('Kamida 2'));
    });

    test('manbaning o\'zi tanlansa hisobga olinmaydi', () {
      final err = distValidate(
          fromSklad: kFrom,
          dests: const [5, kFrom],
          rows: _rows,
          qtyOf: _qtyOf);
      expect(err, contains('Kamida 2'));
    });

    test('8 tadan ko\'p ombor', () {
      final err = distValidate(
        fromSklad: kFrom,
        dests: const [1, 2, 3, 4, 5, 6, 7, 8, 9],
        rows: _rows,
        qtyOf: _qtyOf,
      );
      expect(err, contains('8 ta'));
    });

    test('tovar yo\'q / miqdor yo\'q', () {
      expect(
        distValidate(
            fromSklad: kFrom, dests: kShops, rows: const [], qtyOf: _qtyOf),
        'Kamida bitta tovar qo\'shing',
      );
      expect(
        distValidate(
            fromSklad: kFrom,
            dests: kShops,
            rows: _rows,
            qtyOf: (_, __) => 0),
        'Miqdorlar kiritilmagan',
      );
    });
  });

  group('Xato ustuni (`details.index`) va ogohlantirish guruhlari', () {
    final batch = distBuildBatch(
      fromSklad: kFrom,
      dests: kShops,
      rows: _rows,
      qtyOf: _qtyOf,
    );

    test('index → YUBORILGAN ustun (bo\'sh ustun o\'tkazib yuborilgan)', () {
      expect(batch.destOfIndex(0), 5);
      expect(batch.destOfIndex(1), 18);
      // 2 — Фреско (24), chunki Сибирский (23) umuman yuborilmagan.
      expect(batch.destOfIndex(2), 24);
    });

    test('noto\'g\'ri/yo\'q index — null', () {
      expect(batch.destOfIndex(null), isNull);
      expect(batch.destOfIndex(-1), isNull);
      expect(batch.destOfIndex(9), isNull);
      expect(batch.destOfIndex('1'), 18, reason: 'matn ham qabul qilinadi');
    });

    test('ogohlantirishlar hujjat bo\'yicha guruhlanadi', () {
      final groups = distGroupByDoc<int>(const [0, 0, 1, -1], (i) => i);
      expect(groups[0]?.length, 2);
      expect(groups[1]?.length, 1);
      expect(groups[null]?.length, 1, reason: '−1 — hujjatga bog\'lanmagan');
    });
  });
}
