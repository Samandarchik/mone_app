import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/product_form_draft.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/catalog/tech_card.dart';

Product item() => Product(
      id: 14,
      name: 'Un',
      categoryId: 2,
      unit: 'кг',
      purchasable: true,
      sklads: [1],
      sources: ['toshkent'],
      buyStep: 25000,
      manualPrice: 12000,
      manualPriceAt: DateTime(2026, 10, 1),
    );

void main() {
  test('formani ochib saqlash default qadam, narx va retseptni o‘zgartirmaydi',
      () {
    final product = item().copyWith(
        techCard: const TechCard(
      bases: [
        TechBase(name: 'Asos', ingredients: [
          TechItem(productId: 3, name: 'Shakar', unit: 'g', amount: 200),
        ])
      ],
      salePrice: 55000,
    ));
    final saved = ProductFormDraft(product).build();
    expect(saved.toJson(), product.toJson());
    expect(saved.techCard, same(product.techCard));
    expect(saved.manualPrice, 12000);
    expect(saved.manualPriceAt, product.manualPriceAt);
    expect(saved.sellStep, 0);
    expect(saved.toJson().containsKey('manual_price'), isFalse);
  });

  test('4 andoza mavjud 3 kind va mustaqil kanallarga mos tushadi', () {
    final draft = ProductFormDraft(item());
    draft.applyTemplate(ProductTemplate.resale);
    expect(draft.kind, ProductKind.raw);
    expect(draft.hasSales, isTrue);
    expect(draft.hasPurchases, isTrue);
    draft.applyTemplate(ProductTemplate.finished);
    expect(draft.kind, ProductKind.product);
    expect(draft.hasSales, isTrue);
    expect(draft.hasPurchases, isFalse);
    draft.applyTemplate(ProductTemplate.preparation);
    expect(draft.kind, ProductKind.pf);
    expect(draft.hasSales, isFalse);
    expect(draft.hasPurchases, isFalse);
    draft.applyTemplate(ProductTemplate.ingredient);
    expect(draft.kind, ProductKind.raw);
    expect(draft.hasSales, isFalse);
    expect(draft.hasPurchases, isTrue);
    expect(draft.unit, 'кг');
    expect(draft.buyStep, '25');
  });

  test('pf ga o‘tib qaytishda kanallar va joylar yo‘qolmaydi', () {
    final draft =
        ProductFormDraft(item().copyWith(sellable: true, filials: [5]));
    draft.changeKind(ProductKind.pf);
    final pf = draft.build();
    expect(pf.sellable, isFalse);
    expect(pf.purchasable, isFalse);
    expect(pf.sklads, [1]);
    expect(pf.filials, [5]);
    draft.changeKind(ProductKind.raw);
    expect(draft.hasSales, isTrue);
    expect(draft.hasPurchases, isTrue);
  });

  test('kasr miqdor, vergul va default aniq konvertatsiya qilinadi', () {
    expect(ProductFormDraft.parseStep('0,5', 'кг'), 500);
    expect(ProductFormDraft.parseStep('25', 'кг'), 25000);
    expect(ProductFormDraft.parseStep('0.001', 'л'), 1);
    expect(ProductFormDraft.parseStep('3', 'шт'), 3);
    expect(ProductFormDraft.parseStep('', 'кг'), 0);
    expect(ProductFormDraft.parseStep('1.001', 'кг'), 1001);
  });

  test('noto‘g‘ri yoki yaxlitlashda yo‘qoladigan qadam saqlanmaydi', () {
    for (final text in [
      '-1',
      '0',
      'NaN',
      'Infinity',
      '1e5',
      'abc',
      '0.0001',
      '9007199254740992'
    ]) {
      expect(ProductFormDraft.parseStep(text, 'кг'), isNull, reason: text);
    }
    expect(ProductFormDraft.parseStep('0.5', 'шт'), isNull);
    final draft = ProductFormDraft(item())..buyStep = '-2';
    expect(draft.validate(), contains('buyStep'));
    expect(draft.build, throwsStateError);
  });

  test('yo‘qotish xatosi nolga aylantirilmaydi; litr ml bilan ko‘rsatiladi',
      () {
    final draft = ProductFormDraft(item())
      ..wasteBase = '1000'
      ..wasteAmount = '1000';
    expect(draft.validate(), contains('waste'));
    expect(draft.build, throwsStateError);
    draft.wasteAmount = '100';
    expect(draft.build().wasteFactor, closeTo(1000 / 900, 0.0001));
    draft.wasteBase = '';
    expect(draft.validate(), contains('waste'));
    draft.unit = 'л';
    expect(draft.wasteUnit, 'ml');
  });

  test('tarkib ixtiyoriy; yoqilgan kanallar uchun joy talab qilinadi', () {
    final draft = ProductFormDraft(item());
    expect(draft.sostav, isEmpty);
    expect(draft.validate(), isEmpty);
    draft.sklads.clear();
    expect(draft.validate(), contains('sklads'));
    draft.purchasable = false;
    expect(draft.validate(), isEmpty);
    draft.sellable = true;
    expect(draft.validate(), contains('filials'));
  });

  test('draftdagi ro‘yxat o‘zgarishi originalga tegmaydi', () {
    final product = item();
    final draft = ProductFormDraft(product)
      ..sklads.add(4)
      ..sources.add('samarqand');
    final saved = draft.build();
    draft.sklads.clear();
    expect(product.sklads, [1]);
    expect(product.sources, ['toshkent']);
    expect(saved.sklads, [1, 4]);
  });
}
