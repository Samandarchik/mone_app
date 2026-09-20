// Akt (`act`) hujjati: «Qayerdan (xomashyo ombori)» — `from_sklad` JSON
// bo'yicha borib-kelishi va tur bayroqlari (ACT_KONTRAKT §1–§3, §9).
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_recipe.dart';

void main() {
  group('CoreDocType — aktda «qayerdan» ixtiyoriy', () {
    test('act majburiy from ga kirmaydi, lekin ixtiyoriy from bor', () {
      expect(CoreDocType.hasFrom(CoreDocType.act), isFalse);
      expect(CoreDocType.hasOptionalFrom(CoreDocType.act), isTrue);
      expect(CoreDocType.hasAnyFrom(CoreDocType.act), isTrue);
      expect(CoreDocType.hasTo(CoreDocType.act), isTrue);
    });

    test('production — «dan» va «ga» ikkalasi ham majburiy (o\'zgarmadi)', () {
      expect(CoreDocType.hasFrom(CoreDocType.production), isTrue);
      expect(CoreDocType.hasTo(CoreDocType.production), isTrue);
      expect(CoreDocType.hasOptionalFrom(CoreDocType.production), isFalse);
    });

    test('boshqa turlarda ixtiyoriy «qayerdan» yo\'q', () {
      for (final t in CoreDocType.all) {
        if (t == CoreDocType.act) continue;
        expect(CoreDocType.hasOptionalFrom(t), isFalse, reason: t);
      }
    });
  });

  group('CoreDoc JSON — from_sklad', () {
    test('bir xil ombor: from_sklad = to_sklad yuboriladi', () {
      final doc = CoreDoc(
        type: CoreDocType.act,
        docDate: '2026-09-21',
        fromSklad: 2,
        toSklad: 2,
        lines: const [
          CoreDocLine(goodId: 4, unit: 'pcs', qty: 2000),
        ],
      );
      final j = doc.toJson();
      expect(j['type'], 'act');
      expect(j['from_sklad'], 2);
      expect(j['to_sklad'], 2);
      expect((j['lines'] as List).first, containsPair('flag', 0));
    });

    test('har xil ombor: xomashyo 1, mahsulot 2 + sarf qatorlari', () {
      final doc = CoreDoc(
        type: CoreDocType.act,
        docDate: '2026-09-21',
        fromSklad: 1,
        toSklad: 2,
        lines: const [
          CoreDocLine(goodId: 4, unit: 'pcs', qty: 2000),
          CoreDocLine(goodId: 1, unit: 'g', qty: 480, flag: 1),
        ],
      );
      final j = doc.toJson();
      expect(j['from_sklad'], 1);
      expect(j['to_sklad'], 2);
      final lines = j['lines'] as List;
      expect(lines.length, 2);
      expect((lines[0] as Map)['ord'], 1);
      expect((lines[1] as Map)['flag'], 1);
    });

    test('tanlanmagan bo\'lsa null ketadi (server to_sklad ni oladi)', () {
      final doc = CoreDoc(
        type: CoreDocType.act,
        docDate: '2026-09-21',
        toSklad: 5,
        lines: const [CoreDocLine(goodId: 4, qty: 1000)],
      );
      expect(doc.toJson()['from_sklad'], isNull);
    });

    test('server javobi o\'qiladi: from_sklad + flag=1 stock_after', () {
      final doc = CoreDoc.fromJson({
        'id': 2,
        'type': 'act',
        'number': 'А-000001',
        'doc_date': '2026-09-21',
        'from_sklad': 1,
        'to_sklad': 2,
        'status': 'posted',
        'total': 4600,
        'lines': [
          {'id': 3, 'ord': 1, 'good_id': 4, 'qty': 2000, 'flag': 0,
            'stock_after': 2000},
          {'id': 4, 'ord': 2, 'good_id': 1, 'qty': 480, 'flag': 1,
            'amount': 2400, 'stock_after': 9520},
        ],
      });
      expect(doc.fromSklad, 1);
      expect(doc.toSklad, 2);
      expect(doc.lines.where((l) => l.flag == 1).single.stockAfter, 9520);
      // Qayta yuborilganda xomashyo ombori yo'qolmaydi (PUT — to'liq almashtirish).
      expect(doc.toJson()['from_sklad'], 1);
    });
  });

  group('CoreRecipeExpand — yangi va eski server', () {
    test('yangi server: rule + cut o\'qiladi', () {
      final r = CoreRecipeExpand.fromJson({
        'good_id': 4,
        'date': '2026-09-21',
        'qty': 2000,
        'rule': 'expand_sub',
        'ingredients': [
          {'good_id': 1, 'good_name': 'Un', 'base_unit': 'g', 'qty': 480},
        ],
        'cut': [7, 9],
      });
      expect(r.newServer, isTrue);
      expect(r.hasCut, isTrue);
      expect(r.cut, [7, 9]);
      expect(r.ingredients.single['good_id'], 1);
    });

    test('eski server: rule/cut yo\'q — ingredientlar baribir o\'qiladi', () {
      final r = CoreRecipeExpand.fromJson({
        'ingredients': [
          {'good_id': 1, 'good_name': 'Un', 'base_unit': 'g', 'qty': 480},
        ],
      });
      expect(r.newServer, isFalse);
      expect(r.hasCut, isFalse);
      expect(r.ingredients.length, 1);
    });
  });
}
