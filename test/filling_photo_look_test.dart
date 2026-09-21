// FillingPhotoLook.analyze — nachinka ko'rinishi tex kartadagi FOTODAN.
// Kesilgan tort fotosida qatlamlar tepadan pastga ketadi: ikki korj
// orasidagi hamma narsa — nachinka (yo'llari va nisbati bilan).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_photo_look.dart';

const _bg = Color(0xFF4A494B); // to'q kulrang fon
const _sponge = Color(0xFFCDB894); // och biskvit (haqiqiy fotodagidek)
const _cream = Color(0xFFF1E8DC);
const _jelly = Color(0xFFB0121E);
const _chocolate = Color(0xFF3A2216);

// «Foto»: fon, o'rtada gorizontal qatlamlar — (rang, qatorlar soni).
ByteData _photo(List<(Color, int)> bands, {int w = 120}) {
  final rows = <Color>[
    for (var i = 0; i < 20; i++) _bg,
    for (final (c, n) in bands)
      for (var i = 0; i < n; i++) c,
    for (var i = 0; i < 20; i++) _bg,
  ];
  final h = rows.length;
  final data = ByteData(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = (x >= 10 && x < w - 10) ? rows[y] : _bg;
      final i = (y * w + x) * 4;
      data.setUint8(i, (c.r * 255).round());
      data.setUint8(i + 1, (c.g * 255).round());
      data.setUint8(i + 2, (c.b * 255).round());
      data.setUint8(i + 3, 255);
    }
  }
  return data;
}

int _height(List<(Color, int)> bands) =>
    40 + bands.fold(0, (s, b) => s + b.$2);

bool _near(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 45;

void main() {
  test('krem – jele – krem: nachinka qatlami uch yo\'ldan, nisbati bilan', () {
    const bands = [
      (_sponge, 24),
      (_cream, 6),
      (_jelly, 12),
      (_cream, 6),
      (_sponge, 24),
      (_cream, 6),
      (_jelly, 12),
      (_cream, 6),
      (_sponge, 24),
    ];
    final look = FillingPhotoLook.analyze(_photo(bands), 120, _height(bands));
    expect(look, isNotNull);
    for (final k in [0, 1]) {
      final layer = look!.bandsOf(k);
      expect(layer.length, 3, reason: 'layer $k');
      expect(_near(layer[0].color, _cream), isTrue);
      expect(_near(layer[1].color, _jelly), isTrue);
      expect(_near(layer[2].color, _cream), isTrue);
      // Jele kremdan ~2 marta qalin.
      expect(layer[1].part / layer[0].part, closeTo(2, 0.6));
    }
  });

  test('ikki oraliq ikki xil: 1-qatlam qaymoq, 2-qatlam shokolad', () {
    const bands = [
      (_sponge, 24),
      (_cream, 14),
      (_sponge, 24),
      (_chocolate, 14),
      (_sponge, 24),
    ];
    final look = FillingPhotoLook.analyze(_photo(bands), 120, _height(bands));
    expect(look, isNotNull);
    expect(look!.bandsOf(0).length, 1);
    expect(_near(look.bandsOf(0).single.color, _cream), isTrue);
    expect(_near(look.bandsOf(1).single.color, _chocolate), isTrue);
  });

  test('bitta oraliq — ikkala nachinka qatlami bir xil', () {
    const bands = [(_sponge, 30), (_jelly, 16), (_sponge, 30)];
    final look = FillingPhotoLook.analyze(_photo(bands), 120, _height(bands));
    expect(look, isNotNull);
    expect(_near(look!.bandsOf(0).single.color, _jelly), isTrue);
    expect(look.bandsOf(1), look.bandsOf(0));
  });

  test('faqat biskvit va fon — null (rang тех картадан qoladi)', () {
    const bands = [(_sponge, 80)];
    final look = FillingPhotoLook.analyze(_photo(bands), 120, _height(bands));
    expect(look, isNull);
  });

  test('FillingLook: fotosiz — bitta rangli qatlam', () {
    const look = FillingLook(_jelly);
    expect(look.bandsOf(0), [const FillingBand(_jelly, 1)]);
    expect(look.bandsOf(1), [const FillingBand(_jelly, 1)]);
  });
}
