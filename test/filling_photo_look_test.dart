// FillingPhotoLook.analyze — nachinka ranglari tex kartadagi FOTODAN:
// fon va biskvit rangi tashlanadi, qolgan 1–2 ta asosiy rang olinadi.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_photo_look.dart';

const _bg = Color(0xFF9AA7B5); // kulrang-ko'k stol
const _sponge = Color(0xFFF2CE7E); // oltin biskvit
const _kaymak = Color(0xFFFBF1DC);
const _chocolate = Color(0xFF5A3420);
const _strawberry = Color(0xFFD9364A);

// 96×96 «foto»: fon, o'rtada gorizontal qatlamlar ([bands] — tepadan pastga).
ByteData _photo(List<Color> bands, {Color background = _bg}) {
  const w = 96, h = 96;
  final data = ByteData(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var c = background;
      if (x >= 12 && x < 84 && y >= 16 && y < 80) {
        c = bands[((y - 16) / 64 * bands.length).floor()];
      }
      final i = (y * w + x) * 4;
      data.setUint8(i, (c.r * 255).round());
      data.setUint8(i + 1, (c.g * 255).round());
      data.setUint8(i + 2, (c.b * 255).round());
      data.setUint8(i + 3, 255);
    }
  }
  return data;
}

bool _near(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 40;

void main() {
  test('kaymoq + shokolad: ikki qatlam ikki rangda, biskvit/fon tashlanadi',
      () {
    final look = FillingPhotoLook.analyze(
      _photo(const [_sponge, _kaymak, _sponge, _chocolate, _sponge]),
      96,
      96,
    );
    expect(look, isNotNull);
    final colors = [look!.color, look.color2];
    expect(colors.any((c) => c != null && _near(c, _kaymak)), isTrue);
    expect(colors.any((c) => c != null && _near(c, _chocolate)), isTrue);
  });

  test('bitta nachinka rangi — ikkinchisi null', () {
    final look = FillingPhotoLook.analyze(
      _photo(const [_sponge, _strawberry, _sponge, _strawberry, _sponge]),
      96,
      96,
    );
    expect(look, isNotNull);
    expect(_near(look!.color, _strawberry), isTrue);
    expect(look.color2, isNull);
  });

  test('faqat biskvit va fon — null (rang тех картадан qoladi)', () {
    final look = FillingPhotoLook.analyze(_photo(const [_sponge]), 96, 96);
    expect(look, isNull);
  });
}
