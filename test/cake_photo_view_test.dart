// Tayyor tort ko'rinishi (cake_photo_view.dart): tortning O'Z fotosi,
// ekrandagi o'lchami tex kartadagi diametrga qarab; 3D qurilmaydi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_photo_view.dart';

void main() {
  test('size comes from the tech card: diameter, else the longer side', () {
    expect(cakeSizeCm(const TechCard(diameterCm: 26)), 26);
    expect(cakeSizeCm(const TechCard(widthCm: 30, lengthCm: 40)), 40);
    expect(cakeSizeCm(const TechCard()), 0);
    expect(cakeSizeCm(null), 0);
  });

  test('bigger cake is drawn bigger; tiny and huge are clamped', () {
    final small = cakeSizeFraction(const TechCard(diameterCm: 16));
    final mid = cakeSizeFraction(const TechCard(diameterCm: 24));
    final full = cakeSizeFraction(const TechCard(diameterCm: 30));
    expect(small, lessThan(mid));
    expect(mid, lessThan(full));
    expect(full, 1.0);
    // Juda katta — baribir blokdan oshmaydi.
    expect(cakeSizeFraction(const TechCard(diameterCm: 60)), 1.0);
    // Juda kichik — ko'rinmay qolmaydi.
    expect(cakeSizeFraction(const TechCard(diameterCm: 4)),
        greaterThanOrEqualTo(0.4));
    // O'lcham yo'q — to'liq kenglik.
    expect(cakeSizeFraction(const TechCard()), 1.0);
  });

  test('size label', () {
    expect(cakeSizeLabel(const TechCard(diameterCm: 26, heightCm: 8)),
        'Ø 26 sm · balandligi 8 sm');
    expect(cakeSizeLabel(const TechCard(widthCm: 30, lengthCm: 40)),
        '30×40 sm');
    expect(cakeSizeLabel(const TechCard()), '');
  });

  testWidgets('shows the size line; without a size — a hint', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CakePhotoView(
          imageUrl: 'http://x/cake.jpg',
          card: TechCard(diameterCm: 26, heightCm: 8),
          height: 235,
        ),
      ),
    ));
    await t.pump();
    expect(find.text('Ø 26 sm · balandligi 8 sm'), findsOneWidget);

    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CakePhotoView(
          imageUrl: 'http://x/cake.jpg',
          card: TechCard(),
          height: 235,
        ),
      ),
    ));
    await t.pump();
    expect(find.textContaining('O\'lcham'), findsOneWidget);
  });

  testWidgets('a 30 cm cake is drawn wider than a 16 cm one', (t) async {
    Future<double> widthFor(int cm) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CakePhotoView(
              imageUrl: 'http://x/cake.jpg',
              card: TechCard(diameterCm: cm),
              height: 235,
            ),
          ),
        ),
      ));
      await t.pump();
      final box = find.descendant(
        of: find.byType(CakePhotoView),
        matching: find.byType(SizedBox),
      );
      return t.widgetList<SizedBox>(box).map((s) => s.width ?? 0).reduce(
            (a, b) => a > b ? a : b,
          );
    }

    final big = await widthFor(30);
    final small = await widthFor(16);
    expect(big, greaterThan(small));
    expect(big, closeTo(360, 1));
  });
}
