// Tayyor tort ko'rinishi (cake_photo_view.dart): tortning O'Z fotosi, foni
// olib tashlangan (cake_cutout.dart), ekrandagi o'lchami tex kartadagi
// o'lchamdan — yozuv bilan emas, rasmning kattaligi bilan.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_cutout.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_photo_view.dart';

// Oq fonda jigarrang tort (yumaloq, yon tomoni bilan).
Future<ui.Image> _cakeOnWhite({int w = 300, int h = 300}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFAFAFA));
  final paint = Paint()..color = const Color(0xFF7A4B2A);
  const sinE = 0.3;
  final cx = w / 2, yBase = h * 0.72, r = w * 0.28, cake = h * 0.22;
  c.drawOval(
      Rect.fromCenter(
          center: Offset(cx, yBase), width: 2 * r, height: 2 * r * sinE),
      paint);
  c.drawRect(Rect.fromLTRB(cx - r, yBase - cake, cx + r, yBase), paint);
  c.drawOval(
      Rect.fromCenter(
          center: Offset(cx, yBase - cake),
          width: 2 * r,
          height: 2 * r * sinE),
      Paint()..color = const Color(0xFF9A6438));
  return rec.endRecording().toImage(w, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('size comes from the tech card: diameter, else the longer side', () {
    expect(cakeSizeCm(const TechCard(diameterCm: 26)), 26);
    expect(cakeSizeCm(const TechCard(widthCm: 30, lengthCm: 40)), 40);
    expect(cakeSizeCm(const TechCard()), 0);
    expect(cakeSizeCm(null), 0);
  });

  test('one cm→screen scale for every cake', () {
    final small = cakeSizeFraction(const TechCard(diameterCm: 16));
    final mid = cakeSizeFraction(const TechCard(diameterCm: 24));
    final full = cakeSizeFraction(const TechCard(diameterCm: 32));
    expect(small, lessThan(mid));
    expect(mid, lessThan(full));
    expect(full, 1.0);
    // 16 sm — 32 sm ning yarmi.
    expect(small / full, closeTo(0.5, 0.01));
    // Juda katta blokdan oshmaydi, juda kichigi ko'rinib turadi.
    expect(cakeSizeFraction(const TechCard(diameterCm: 60)), 1.0);
    expect(cakeSizeFraction(const TechCard(diameterCm: 2)),
        greaterThanOrEqualTo(0.2));
    // O'lcham yo'q — to'liq.
    expect(cakeSizeFraction(const TechCard()), 1.0);
  });

  test('cutout: white background becomes transparent and is cropped away',
      () async {
    final img = await _cakeOnWhite();
    final cut = await CakeCutout.fromImage(img);
    expect(cut.ok, isTrue);
    // Tortga qirqilgan — asl rasmdan kichikroq.
    expect(cut.image.width, lessThan(img.width));
    expect(cut.image.height, lessThan(img.height));
    // Burchak pikseli SHAFFOF (fon olib tashlangan).
    final data =
        await cut.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(data!.getUint8(3), 0);
  });

  testWidgets('no size text on the picture', (t) async {
    CakeCutout.clearCache();
    CakeCutout.loader = (_, __) async => _cakeOnWhite();
    addTearDown(() => CakeCutout.loader = null);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CakePhotoView(
          imageUrl: 'http://x/cake.jpg',
          card: TechCard(diameterCm: 26, heightCm: 8),
          height: 235,
        ),
      ),
    ));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(t.takeException(), isNull);
    // O'lcham YOZUV bilan ko'rsatilmaydi.
    expect(find.textContaining('26'), findsNothing);
    expect(find.textContaining('Ø'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a 32 cm cake is drawn twice as wide as a 16 cm one', (t) async {
    CakeCutout.clearCache();
    CakeCutout.loader = (_, __) async => _cakeOnWhite();
    addTearDown(() => CakeCutout.loader = null);

    Future<double> widthFor(int cm) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CakePhotoView(
              imageUrl: 'http://x/cake$cm.jpg',
              card: TechCard(diameterCm: cm),
              height: 235,
            ),
          ),
        ),
      ));
      await t.pump();
      // Rasm qutisi: blok balandligida va ANIQ kenglikda (tashqi quti
      // cheksiz kenglikda bo'ladi).
      final boxes = find.descendant(
        of: find.byType(CakePhotoView),
        matching: find.byType(SizedBox),
      );
      final inner = t.widgetList<SizedBox>(boxes).firstWhere(
            (s) => s.height == 235 && (s.width?.isFinite ?? false),
          );
      return inner.width!;
    }

    final big = await widthFor(32);
    final small = await widthFor(16);
    expect(big, closeTo(360, 1));
    expect(small, closeTo(180, 1));
  });
}
