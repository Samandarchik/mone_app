// Vizual tekshiruv uchun: illyustratsiyani PNG'ga chizib chiqaradi
// (CAKE_RENDER_OUT muhit o'zgaruvchisi berilganda). Odatiy testda o'tkaziladi.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_illustration.dart';

const TechCard _raffaello = TechCard(
  diameterCm: 22,
  heightCm: 8,
  bases: [
    TechBase(name: 'Бисквит ванильный'),
    TechBase(name: 'Крем кокосовый'),
    TechBase(name: 'Покрытие', ingredients: [
      TechItem(name: 'Крем чиз', unit: 'g', amount: 400),
      TechItem(name: 'Кокосовая стружка', unit: 'g', amount: 60),
    ]),
    TechBase(name: 'Карамельная глазурь'),
    TechBase(name: 'Декор', ingredients: [
      TechItem(name: 'Рафаэлло конфеты', unit: 'pcs', amount: 8),
      TechItem(name: 'Безе мини', unit: 'pcs', amount: 8),
      TechItem(name: 'Миндальные лепестки', unit: 'g', amount: 30),
    ]),
  ],
);

const TechCard _berry = TechCard(
  diameterCm: 18,
  heightCm: 10,
  bases: [
    TechBase(name: 'Бисквит шоколадный'),
    TechBase(name: 'Крем клубничный'),
    TechBase(name: 'Покрытие крем чиз'),
    TechBase(name: 'Декор', ingredients: [
      TechItem(name: 'Клубника', unit: 'g', amount: 100),
      TechItem(name: 'Малина', unit: 'g', amount: 60),
      TechItem(name: 'Шоколад кусочки', unit: 'g', amount: 30),
    ]),
  ],
);

Future<void> _render(String file, CakeIllustrationSpec spec) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 720, 480),
      Paint()..color = const Color(0xFFFAF6F1));
  CakeIllustrationPainter(spec: spec, label: 'Mone', subLabel: 'BAKERY & COFFEE')
      .paint(canvas, const Size(720, 480));
  final img = await rec.endRecording().toImage(720, 480);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(file).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final out = Platform.environment['CAKE_RENDER_OUT'];
  test('render illustrations to PNG', () async {
    if (out == null || out.isEmpty) return;
    await _render('$out/raffaello.png',
        CakeIllustrationSpec.fromTechCard('Торт Рафаэлло', _raffaello));
    await _render('$out/berry.png',
        CakeIllustrationSpec.fromTechCard('Торт Клубничный', _berry));
    await _render('$out/plain.png',
        CakeIllustrationSpec.fromTechCard('Торт Медовик', const TechCard()));
  }, skip: out == null || out.isEmpty);
}
