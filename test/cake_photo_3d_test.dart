// Fotodan 3D tort (cake_photo_3d.dart): sintetik rasmda siluet tahlili —
// proporsiya, yaruslar, kamera burchagi, shakl; model qurilishi va
// aylantirish (painter xatosiz, burchak o'zgarganda mesh o'zgarmaydi).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_photo_3d.dart';

// Oq fonda tort: [tiers] — (yarim kenglik, balandlik) pastdan tepaga, ellips
// tepa/past gardishlari bilan (kamera balandligi sinE). [decorH] — eng tepa
// yarus USTIDAGI bezak (makaron/rezavor/shokolad «yelpig'ich»): markazda
// shuncha px ko'tarilgan, kenglikning ~65% ini egallaydi.
Future<ui.Image> _cakeImage({
  required List<(double, double)> tiers,
  double sinE = 0.3,
  bool square = false,
  double decorH = 0,
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
  // Bezak: tepa yuzasining markazida, gardishdan ancha baland — silueti
  // markazda «cho'qqi» beradi (yumaloq tort kvadrat bo'lib ko'rinmasin).
  if (decorH > 0 && tiers.isNotEmpty) {
    final rTop = tiers.last.$1;
    final dR = 0.65 * rTop;
    final decor = Paint()..color = const Color(0xFFD8B26A);
    for (var i = -2; i <= 2; i++) {
      final dx = i * dR / 2.4;
      final hh = decorH * (1 - 0.25 * i.abs());
      c.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx, yBase - hh / 2),
          width: dR / 2.6,
          height: hh,
        ),
        decor,
      );
    }
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

  // Regressiya: qizil yumaloq tort (ustida makaron/rezavor/shokolad
  // «yelpig'ich») 3D'da KVADRAT bo'lib chiqardi — markazdagi baland bezak
  // silueti «tom» (^) shaklini taqlid qilardi.
  test('round cake with tall centre decor is NOT square', () async {
    final img = await _cakeImage(tiers: [(110, 90)], sinE: 0.3, decorH: 55);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);
    expect(s.square, isFalse);
    // Bezak kamera burchagini ham shishirmasligi kerak.
    expect(s.sinE, closeTo(0.3, 0.08));
  });

  // Regressiya: tort OQ PATNIS (podstavka) ustida — patnis tortdan keng va
  // fon bilan deyarli bir xil. Ilgari siluet pastki qatorlarda patnisniki
  // bo'lib, model TORTDAN emas, PATNISDAN qurilardi.
  test('cake on a wide light board: the CAKE is the volume, not the board',
      () async {
    const cakeR = 90.0, boardR = 135.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 400, 400),
        Paint()..color = const Color(0xFFFAFAFA));
    const cx = 200.0, yBase = 300.0, sinE = 0.3;
    // Patnis: oq, fondan arzimas darajada to'qroq + yumshoq soya.
    c.drawOval(
      Rect.fromCenter(
          center: const Offset(cx, yBase + 10),
          width: 2 * boardR,
          height: 2 * boardR * sinE),
      Paint()
        ..color = const Color(0xFFEDEDEF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    c.drawOval(
      Rect.fromCenter(
          center: const Offset(cx, yBase),
          width: 2 * boardR,
          height: 2 * boardR * sinE),
      Paint()..color = const Color(0xFFF2F2F4),
    );
    // Tort: to'q shokolad.
    const dark = Color(0xFF2E1B10);
    c.drawOval(
      Rect.fromCenter(
          center: const Offset(cx, yBase),
          width: 2 * cakeR,
          height: 2 * cakeR * sinE),
      Paint()..color = dark,
    );
    c.drawRect(const Rect.fromLTRB(cx - cakeR, yBase - 100, cx + cakeR, yBase),
        Paint()..color = dark);
    c.drawOval(
      Rect.fromCenter(
          center: const Offset(cx, yBase - 100),
          width: 2 * cakeR,
          height: 2 * cakeR * sinE),
      Paint()..color = const Color(0xFFB0651F),
    );
    final img = await rec.endRecording().toImage(400, 400);
    final s = analyzeCakePhoto(await _rgba(img), img.width, img.height);

    // Model radiusi TORTNIKI (90), patnisniki (135) emas.
    expect(s.a, closeTo(cakeR, 6));
    expect(s.sinE, closeTo(sinE, 0.1));
    // Pastda keng disk (patnis) qolmadi: profil hamma joyda ~1.
    for (final (_, r) in s.profile) {
      expect(r, greaterThan(0.85));
    }
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

  testWidgets('viewer: static — no angle chips, drag does not move it',
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
    // Burchak tugmalari OLIB TASHLANGAN.
    for (final label in ['Old', 'Yon', 'Orqa', 'Tepa', '360°']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byType(ActionChip), findsNothing);

    // Surish/chimdish — model QIMIRLAMAYDI: burchak ham, masshtab ham
    // o'zgarmaydi.
    final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CakePhotoPainter);
    expect(painterFinder, findsOneWidget);
    final before = t.widget<CustomPaint>(painterFinder).painter as CakePhotoPainter;
    await t.drag(painterFinder, const Offset(120, 40));
    await t.pump(const Duration(milliseconds: 50));
    await t.drag(painterFinder, const Offset(-80, -60));
    await t.pump(const Duration(milliseconds: 50));
    expect(t.takeException(), isNull);
    final after = t.widget<CustomPaint>(painterFinder).painter as CakePhotoPainter;
    expect(identical(before.model, after.model), isTrue);
    expect(after.yaw, before.yaw);
    expect(after.pitch, before.pitch);
    expect(after.zoom, before.zoom);
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
