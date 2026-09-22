// Tort illyustratsiyasi (cake_illustration.dart): spec tex kartadan
// (qoplama/glazur rangi, faktura, dekor) va painter har xil dekor bilan
// xatosiz chizadi.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_illustration.dart';

const TechCard _raffaello = TechCard(
  diameterCm: 22,
  heightCm: 8,
  shape: 'round',
  bases: [
    TechBase(name: 'Бисквит ванильный', ingredients: [
      TechItem(name: 'Мука', unit: 'g', amount: 300),
    ]),
    TechBase(name: 'Крем кокосовый', ingredients: [
      TechItem(name: 'Сливки 33%', unit: 'ml', amount: 500),
      TechItem(name: 'Кокосовая стружка', unit: 'g', amount: 120),
    ]),
    TechBase(name: 'Покрытие', ingredients: [
      TechItem(name: 'Крем чиз', unit: 'g', amount: 400),
      TechItem(name: 'Кокосовая стружка', unit: 'g', amount: 60),
    ]),
    TechBase(name: 'Карамельная глазурь', ingredients: [
      TechItem(name: 'Карамель', unit: 'g', amount: 100),
    ]),
    TechBase(name: 'Декор', ingredients: [
      TechItem(name: 'Рафаэлло конфеты', unit: 'pcs', amount: 8),
      TechItem(name: 'Безе мини', unit: 'pcs', amount: 8),
      TechItem(name: 'Миндальные лепестки', unit: 'g', amount: 30),
    ]),
  ],
);

void _paint(CakeIllustrationSpec spec, {String? label = 'Mone'}) {
  final rec = ui.PictureRecorder();
  CakeIllustrationPainter(spec: spec, label: label, subLabel: 'BAKERY & COFFEE')
      .paint(Canvas(rec), const Size(360, 240));
  rec.endRecording();
}

void main() {
  test('spec from Raffaello tech card: coconut coat, glaze top, decor', () {
    final s = CakeIllustrationSpec.fromTechCard('Торт Рафаэлло', _raffaello);
    expect(s.texture, CakeCoatTexture.coconut);
    // Dekor bloki: shariklar, beze, mindal.
    expect(s.decor,
        [CakeDecor.raffaello, CakeDecor.meringue, CakeDecor.almond]);
    // Tepa — karamel glazur, qoplamadan farqli.
    expect(s.top, isNot(s.coat));
    expect(s.dims.diameterCm, 22);
    expect(s.dims.heightCm, 8);
  });

  test('spec: no decor block → decor from cake name / coat', () {
    const card = TechCard(bases: [
      TechBase(name: 'Бисквит'),
      TechBase(name: 'Крем шоколадный', ingredients: [
        TechItem(name: 'Шоколад', unit: 'g', amount: 200),
      ]),
    ]);
    final s = CakeIllustrationSpec.fromTechCard('Торт с вишней', card);
    expect(s.decor, contains(CakeDecor.cherry));
    expect(s.texture, CakeCoatTexture.smooth);
    expect(s.top, s.coat);
    // Tex karta yo'q — nomdan.
    expect(CakeIllustrationSpec.fromTechCard('Клубничный', null).decor,
        [CakeDecor.strawberry]);
  });

  test('CakeBlockRole.of by block name', () {
    expect(CakeBlockRole.of(const TechBase(name: 'Бисквит')), CakeBlockRole.biscuit);
    expect(CakeBlockRole.of(const TechBase(name: 'Покрытие крем чиз')), CakeBlockRole.coat);
    expect(CakeBlockRole.of(const TechBase(name: 'Декор')), CakeBlockRole.decor);
    expect(CakeBlockRole.of(const TechBase(name: 'Пропитка')), CakeBlockRole.other);
    expect(CakeBlockRole.of(const TechBase(name: 'Крем кокосовый')), CakeBlockRole.filling);
  });

  test('painter draws every decor type and texture without exceptions', () {
    _paint(CakeIllustrationSpec.fromTechCard('Торт Рафаэлло', _raffaello));
    for (final d in CakeDecor.values) {
      _paint(CakeIllustrationSpec(decor: [d]));
    }
    _paint(const CakeIllustrationSpec(decor: []), label: null);
    _paint(const CakeIllustrationSpec(
      texture: CakeCoatTexture.nuts,
      decor: [CakeDecor.chocolate, CakeDecor.nut, CakeDecor.raspberry],
      ribbon: null,
    ));
    // Yassi/keng tort ham (rect) sig'adi.
    _paint(const CakeIllustrationSpec(
      dims: BiscuitDims(rect: true, widthCm: 30, lengthCm: 40, heightCm: 4),
    ));
  });

  testWidgets('CakeIllustrationView builds', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CakeIllustrationView(
          spec: CakeIllustrationSpec.fromTechCard('Торт Рафаэлло', _raffaello),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byType(CakeIllustrationView), findsOneWidget);
  });
}
