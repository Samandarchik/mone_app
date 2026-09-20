// «Sanash» (inventarizatsiya) oson rejimining sof mantig'i:
// ommaviy to'ldirish qamrovi («Hammasini 0» / «Hammasini hisobdagidek»),
// bekor qilish (undo), toifa (guruh) rejimidagi xulosa va taom/p-f `flag`
// qoidasi — `lib/core2/ui/inventory_count_logic.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/core2/ui/inventory_count_logic.dart';

/// Test qatori: tovar, guruh (toifa), hisob qoldig'i, 1 base birlik narxi.
class _Row {
  final int id;
  final String group;
  final int current;
  final int? price;
  const _Row(this.id, this.group, this.current, [this.price]);
}

const _rows = <_Row>[
  _Row(1, 'Выпечка', 5000, 12),
  _Row(2, 'Выпечка', 2000, 30),
  _Row(3, 'Напитки', 7000, 5),
  _Row(4, 'Хозтовары', 1000, 100),
];

List<InvFillTarget> _zeroTargets(Iterable<_Row> rows) => [
      for (final r in rows)
        InvFillTarget(
            goodId: r.id, value: '0', current: r.current, price: r.price),
    ];

List<InvFillTarget> _bookTargets(Iterable<_Row> rows) => [
      for (final r in rows)
        InvFillTarget(
            goodId: r.id,
            value: '${r.current}',
            current: r.current,
            price: r.price),
    ];

void main() {
  group('Ommaviy to\'ldirish — kiritilgan fakt ustidan YOZILMAYDI', () {
    test('«Hammasini 0»: faqat sanalmagan qatorlar rejaga tushadi', () {
      final facts = <int, String>{2: '1,5'}; // 2-tovar qo'lda sanalgan
      final plan = _zeroTargets(_rows);
      final res = invPlanBulkFill(plan, (id) => facts[id]);
      expect(res.map((t) => t.goodId), [1, 3, 4]);
      expect(res.every((t) => t.value == '0'), isTrue);
    });

    test('bo\'sh/probelli matn — «sanalmagan» hisoblanadi', () {
      final facts = <int, String>{1: '', 3: '   '};
      final res = invPlanBulkFill(_zeroTargets(_rows), (id) => facts[id]);
      expect(res.length, 4);
    });

    test('«0» kiritilgan qator — SANALGAN, ustidan yozilmaydi', () {
      final facts = <int, String>{4: '0'};
      final res = invPlanBulkFill(_zeroTargets(_rows), (id) => facts[id]);
      expect(res.map((t) => t.goodId), [1, 2, 3]);
    });

    test('«Hammasini hisobdagidek» — fakt = hisob qoldig\'i', () {
      final facts = <int, String>{1: '3'};
      final res = invPlanBulkFill(_bookTargets(_rows), (id) => facts[id]);
      expect(res.map((t) => t.goodId), [2, 3, 4]);
      expect(res.first.value, '2000');
    });

    test('toifa qamrovi: faqat tanlangan guruh qatorlari', () {
      final scope = invScopeRows(_rows, {'Выпечка'}, (r) => r.group);
      final res = invPlanBulkFill(_zeroTargets(scope), (_) => null);
      expect(res.map((t) => t.goodId), [1, 2]);
    });

    test('takror qator bir marta olinadi', () {
      final res = invPlanBulkFill(
        _zeroTargets([..._rows, const _Row(1, 'Выпечка', 5000, 12)]),
        (_) => null,
      );
      expect(res.length, 4);
    });

    test('hammasi sanalgan bo\'lsa reja bo\'sh', () {
      final facts = {for (final r in _rows) r.id: '1'};
      expect(invPlanBulkFill(_zeroTargets(_rows), (id) => facts[id]), isEmpty);
    });

    test('nolga tushiriladigan summa = Σ qoldiq × narx', () {
      final res = invPlanBulkFill(_zeroTargets(_rows), (_) => null);
      final money = res.fold<int>(0, (s, t) => s + t.amount);
      expect(money, 5000 * 12 + 2000 * 30 + 7000 * 5 + 1000 * 100);
    });
  });

  group('Bekor qilish (undo)', () {
    test('oldingi faktlar tiklanadi, sanalganlar tegilmaydi', () {
      final facts = <int, String>{2: '1,5'};
      final plan = invPlanBulkFill(_zeroTargets(_rows), (id) => facts[id]);
      final undo = invUndoOf(plan, (id) => facts[id], wasZeroed: false);
      // Ommaviy amal qo'llanadi.
      for (final t in plan) {
        facts[t.goodId] = t.value;
      }
      expect(facts[1], '0');
      expect(facts[2], '1,5');
      // Bekor qilish.
      undo.previous.forEach((id, text) => facts[id] = text);
      expect(undo.count, 3);
      expect(facts[1], '');
      expect(facts[3], '');
      expect(facts[2], '1,5', reason: 'qo\'lda kiritilgan fakt saqlanadi');
      expect(undo.wasZeroed, isFalse);
    });

    test('undo oldingi «nolga tushirish» belgisini eslab qoladi', () {
      final undo = invUndoOf(
          _zeroTargets(_rows.take(1)), (_) => null,
          wasZeroed: true);
      expect(undo.wasZeroed, isTrue);
      expect(undo.isEmpty, isFalse);
    });
  });

  group('Toifa rejimi — xulosa va «sanalmaganlar»', () {
    bool counted(int id) => id == 1 || id == 3;

    test('tanlov bo\'sh — hamma qator hisobga kiradi', () {
      final scope = invScopeRows(_rows, <String>{}, (r) => r.group);
      final p = invProgress(scope.map((r) => r.id), counted);
      expect(p.total, 4);
      expect(p.counted, 2);
      expect(p.uncounted, 2);
    });

    test('faqat tanlangan guruhlar hisoblanadi', () {
      final scope = invScopeRows(_rows, {'Выпечка'}, (r) => r.group);
      final p = invProgress(scope.map((r) => r.id), counted);
      expect(p.total, 2);
      expect(p.counted, 1);
      expect(p.uncounted, 1, reason: 'Напитки/Хозтовары ogohlantirmaydi');
      expect(p.ratio, 0.5);
    });

    test('bir nechta toifa tanlansa ikkalasi ham kiradi', () {
      final scope =
          invScopeRows(_rows, {'Выпечка', 'Напитки'}, (r) => r.group);
      expect(scope.length, 3);
      expect(invInGroupScope({'Выпечка'}, 'Хозтовары'), isFalse);
      expect(invInGroupScope(<String>{}, 'Хозтовары'), isTrue);
    });

    test('bo\'sh qamrovda taraqqiyot 0 (nolga bo\'linish yo\'q)', () {
      final p = invProgress(const <int>[], counted);
      expect(p.total, 0);
      expect(p.ratio, 0);
    });
  });

  group('Taom/p-f `flag` — tegilmasa bugungi natija', () {
    test('almashtirgichga tegilmagan: komplekt → 1, xom → 0', () {
      expect(invLineFlag(isComplect: true), 1);
      expect(invLineFlag(isComplect: false), 0);
      expect(invLineFlag(isComplect: true, expand: null), 1);
      expect(invLineFlag(isComplect: false, expand: null), 0);
    });

    test('«o\'zi» → 1 (yoyilmaydi), «tarkibi» → 0 (ingredientlarga)', () {
      expect(invLineFlag(isComplect: true, expand: false), 1);
      expect(invLineFlag(isComplect: true, expand: true), 0);
    });

    test('komplekt bo\'lmagan tovarda tanlov natijani o\'zgartirmaydi', () {
      expect(invLineFlag(isComplect: false, expand: true), 0);
      expect(invLineFlag(isComplect: false, expand: false), 0);
    });
  });

  group('Hujjat izohi — prefiks va toifa nomlari', () {
    test('bo\'sh izoh o\'zgarmaydi', () {
      expect(invBuildComment(), '');
    });

    test('«[nolga tushirish] » prefiksi qo\'yiladi', () {
      expect(invBuildComment(base: 'Хозы', zeroed: true),
          '$kInvZeroTag Хозы');
    });

    test('toifa nomlari qo\'shiladi (SH5 odati)', () {
      expect(invBuildComment(groups: const ['Выпечка', 'Напитки']),
          'Выпечка, Напитки');
    });

    test('takror chaqirilsa natija O\'ZGARMAYDI (avto-saqlash)', () {
      final first = invBuildComment(
          base: 'qo\'lda', zeroed: true, groups: const ['Выпечка']);
      final parts = InvComment.parse(first);
      final second = invBuildComment(
          base: parts.base, zeroed: parts.zeroed, groups: const ['Выпечка']);
      expect(second, first);
      expect(InvComment.parse(second).base, 'qo\'lda · Выпечка');
    });

    test('ikkala prefiks ham ajratiladi', () {
      final p = InvComment.parse('$kInvZeroTag $kInvHandoverTag Выпечка');
      expect(p.zeroed, isTrue);
      expect(p.handover, isTrue);
      expect(p.base, 'Выпечка');
      expect(
        invBuildComment(
            base: p.base, zeroed: p.zeroed, handover: p.handover),
        '$kInvZeroTag $kInvHandoverTag Выпечка',
      );
    });

    test('eslatma takror qo\'shilmaydi', () {
      const note = 'topshirdi: Мафтуна 21.09.2026 14:35';
      final c = invBuildComment(base: '', handover: true, note: note);
      final again = invBuildComment(
          base: InvComment.parse(c).base, handover: true, note: note);
      expect(again, c);
    });

    test('topshirilgan qoralama aniqlanadi', () {
      expect(invIsHandover('$kInvHandoverTag Выпечка'), isTrue);
      expect(invIsHandover('Выпечка'), isFalse);
      expect(invIsZeroed('$kInvZeroTag Хозы'), isTrue);
      expect(invIsZeroed('Хозы'), isFalse);
    });
  });
}
