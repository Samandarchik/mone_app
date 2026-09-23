// Fotodan 3D tort (cake_photo_3d.dart): sintetik rasmda siluet tahlili —
// proporsiya, yaruslar, kamera burchagi, shakl; model qurilishi va
// aylantirish (painter xatosiz, burchak o'zgarganda mesh o'zgarmaydi).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_photo_3d.dart';

// Oq fonda tort: [tiers] — (yarim kenglik, balandlik) pastdan tepaga, ellips
// tepa/past gardishlari bilan (kamera balandligi sinE).
Future<ui.Image> _cakeImage({
  required List<(double, double)> tiers,
  double sinE = 0.3,
  bool square = false,
  int w = 320,
  int h = 320,
  Color color = const Color(0xFF8B5A2B),
}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white);
  final cx = w / 2;
  var yBase = h * 0.86;
  final paint = Paint()..color = color;
  final top = Paint()..color = color.withValues(alpha: 0.85);
  for (final (r, height) in tiers) {
    final b = r * sinE;
    if (square) {
      // 3/4 rakurs: burchak kameraga — siluet olti burchak («tom» kontur).
      final path = Path()
        ..moveTo(cx - r, yBase - height)
        ..lineTo(cx, yBase - height - b)
        ..lineTo(cx + r, yBase - height)
        ..lineTo(cx + r, yBase)
        ..lineTo(cx, yBase + b)
        ..lineTo(cx - r, yBase)
        ..close();
      c.drawPath(path, paint);
    } else {
      c.drawOval(Rect.fromCenter(center: Offset(cx, yBase), width: 2 * r, height: 2 * b), paint);
      c.drawRect(Rect.fromLTRB(cx - r, yBase - height, cx + r, yBase), paint);
      c.drawOval(
          Rect.fromCenter(center: Offset(cx, yBase - height), width: 2 * r, height: 2 * b), top);
    }
    yBase -= height;
  }
  return rec.endRecording().toImage(w, h);
}

Future<Uint8List> _rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('single tier: proportions and camera angle from silhouette', () async {
    // r = 100, balandlik 120, sinE = 0.3.
    final img = await _cakeImage(tiers: [(100, 120)], sinE: 0.3);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);
    expect(s.square, isFalse);
    expect(s.tiers, 1);
    expect(s.sinE, closeTo(0.3, 0.06));
    // Balandlik / radius = 120 / 100 / cosE ≈ 1.26.
    expect(s.heightRatio, closeTo(1.26, 0.15));
    expect(s.a, closeTo(100, 3));
    for (final (_, r) in s.profile) {
      expect(r, closeTo(1.0, 0.06));
    }
  });

  test('wide flat cake stays wide and flat', () async {
    final img = await _cakeImage(tiers: [(130, 45)], sinE: 0.35);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);
    expect(s.tiers, 1);
    expect(s.heightRatio, lessThan(0.5));
  });

  test('two tiers: step in the profile, radii preserved', () async {
    final img = await _cakeImage(tiers: [(120, 70), (70, 70)], sinE: 0.3, h: 360);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);
    expect(s.tiers, 2);
    // Pastki yarus radius 1, tepa yarus ≈ 70/120.
    expect(s.profile.first.$2, closeTo(1.0, 0.06));
    expect(s.profile.last.$2, closeTo(70 / 120, 0.06));
  });

  test('square cake detected from flat top contour', () async {
    final img = await _cakeImage(tiers: [(100, 100)], sinE: 0.3, square: true);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);
    expect(s.square, isTrue);
  });

  test('no background found → whole image is the cake (no crash)', () async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 64, 64),
        Paint()..color = const Color(0xFF8B5A2B));
    final img = await rec.endRecording().toImage(64, 64);
    final s = analyzeCakePhoto(await _rgba(img), 64, 64);
    expect(s.profile, isNotEmpty);
    expect(s.a, greaterThan(20));
  });

  testWidgets('viewer: loads via loader, rotates by drag, shows angle chips',
      (t) async {
    final img = await _cakeImage(tiers: [(100, 120)]);
    CakePhotoModel.clearCache();
    CakePhotoModel.loader = (_, __) async => img;
    addTearDown(() => CakePhotoModel.loader = null);

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CakePhoto3DView(
          imageUrl: 'http://x/cake.jpg',
          height: 240,
        ),
      ),
    ));
    // Model qurilishi — engine async (toImage); haqiqiy vaqtda kutamiz.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Qayta urinish'), findsNothing);
    for (final label in ['Old', 'Yon', 'Orqa', 'Tepa']) {
      expect(find.text(label), findsOneWidget);
    }

    // Surish — burish; xatosiz chiziladi.
    final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CakePhotoPainter);
    expect(painterFinder, findsOneWidget);
    final before = t.widget<CustomPaint>(painterFinder).painter as CakePhotoPainter;
    await t.drag(painterFinder, const Offset(120, 40));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
    final after = t.widget<CustomPaint>(painterFinder).painter as CakePhotoPainter;
    // Model (mesh, tekstura) O'SHA — faqat burchak o'zgargan.
    expect(identical(before.model, after.model), isTrue);
    expect(after.pitch, isNot(before.pitch));

    // Tepadan ko'rish tugmasi.
    await t.tap(find.text('Tepa'));
    await t.pump(); // animatsiya boshlanadi
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    final topView = t.widget<CustomPaint>(painterFinder).painter as CakePhotoPainter;
    expect(topView.pitch, closeTo(1.45, 0.01));
  });

  testWidgets('viewer: load failure → error, no generic model', (t) async {
    CakePhotoModel.clearCache();
    CakePhotoModel.loader = (_, __) async => throw Exception('no image');
    addTearDown(() => CakePhotoModel.loader = null);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CakePhoto3DView(
          imageUrl: 'http://x/none.jpg',
          height: 240,
        ),
      ),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(t.takeException(), isNull);
    // Umumiy model EMAS — xato va qayta urinish.
    expect(find.text('Qayta urinish'), findsOneWidget);
    expect(find.textContaining('3D model qurilmadi'), findsOneWidget);
  });
}
