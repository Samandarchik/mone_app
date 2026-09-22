// FillingCakePainter + sidePhoto: tayyor tort fotosi qoplangan BUTUN tortga
// o'raladi (yon devor + tepa) — haqiqiy ui.Image bilan chizish xatosiz.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

// Kichik sinov rasmi (ikki rangli).
Future<ui.Image> _image() {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = Colors.pink);
  c.drawRect(const Rect.fromLTWH(20, 0, 20, 30), Paint()..color = Colors.white);
  return rec.endRecording().toImage(40, 30);
}

void _paint(FillingCakePainter p) {
  final rec = ui.PictureRecorder();
  p.paint(Canvas(rec), const Size(320, 205));
  rec.endRecording();
}

void main() {
  testWidgets('coated whole cake with photo paints at several rotations',
      (t) async {
    final img = await _image();
    addTearDown(img.dispose);
    for (final rot in [0.0, 0.7, 2.0, 3.5, 5.9]) {
      _paint(FillingCakePainter(
        look: FillingLook.neutral,
        coat: const Color(0xFFF8BBD0),
        sponge: BiscuitPalette.classic,
        dims: const BiscuitDims(diameterCm: 22, heightCm: 8),
        fillings: const [
          [FillingBand(Color(0xFFFFF3DC), 1)],
        ],
        sidePhoto: img,
        tilt: 0.36,
        rotation: rot,
      ));
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('photo is ignored for the cut cake and the slice', (t) async {
    final img = await _image();
    addTearDown(img.dispose);
    // Kesilgan qoplangan tort (konstruktor) va yalang'och tort — foto
    // o'ralmaydi, lekin chizish xatosiz.
    _paint(FillingCakePainter(
      look: FillingLook.neutral,
      coat: const Color(0xFFF8BBD0),
      coatCut: true,
      sidePhoto: img,
      tilt: 0.36,
      rotation: 0.4,
    ));
    _paint(FillingCakePainter(
      look: FillingLook.neutral,
      sidePhoto: img,
      slice: true,
      tilt: 0.36,
      rotation: 0,
    ));
    expect(t.takeException(), isNull);
    // shouldRepaint — foto o'zgarsa qayta chiziladi.
    final a = FillingCakePainter(
        look: FillingLook.neutral, coat: Colors.pink, tilt: 0.36, rotation: 0);
    final b = FillingCakePainter(
        look: FillingLook.neutral,
        coat: Colors.pink,
        sidePhoto: img,
        tilt: 0.36,
        rotation: 0);
    expect(b.shouldRepaint(a), isTrue);
  });
}
