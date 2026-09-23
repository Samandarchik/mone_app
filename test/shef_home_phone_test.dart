// Shef bosh menyusi (shef_home_ui.dart) telefon ekranida: kartalar
// ezilmaydi/yoyilmaydi (balandligi qat'iy, overflow yo'q), sarlavha bir
// qatorda, 4 ta asosiy karta hammasi bor.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_home_ui.dart';

void main() {
  setUpAll(() {
    if (!GetIt.instance.isRegistered<Dio>()) {
      GetIt.instance.registerSingleton<Dio>(Dio());
    }
  });

  Future<void> open(WidgetTester t, Size size) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CategoryProviderAdmin()),
        ChangeNotifierProvider(create: (_) => ProductProviderAdmin()),
        ChangeNotifierProvider(create: (_) => ShefProvider()),
        ChangeNotifierProvider(create: (_) => CoreSession()),
      ],
      child: const MaterialApp(home: ShefHomeUi()),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('phone 360×640: no overflow, fixed-height cards', (t) async {
    await open(t, const Size(360, 640));
    expect(t.takeException(), isNull);
    for (final title in ['Торты', 'Полуфабрикат', 'Готовый', 'Тех карта']) {
      expect(find.text(title), findsOneWidget);
    }
    // Kartalar balandligi qat'iy — ezilmaydi.
    final tortlar = t.getRect(find.ancestor(
      of: find.text('Торты'),
      matching: find.byType(Material),
    ).first);
    expect(tortlar.height, 178);
    // 2 ustun: «Полуфабрикат» «Торты» bilan bir qatorda.
    final pf = t.getRect(find.ancestor(
      of: find.text('Полуфабрикат'),
      matching: find.byType(Material),
    ).first);
    expect(pf.top, tortlar.top);
  });

  testWidgets('very narrow 240px: cards go one below another', (t) async {
    await open(t, const Size(240, 700));
    expect(t.takeException(), isNull);
    final a = t.getRect(find.ancestor(
      of: find.text('Торты'),
      matching: find.byType(Material),
    ).first);
    final b = t.getRect(find.ancestor(
      of: find.text('Полуфабрикат'),
      matching: find.byType(Material),
    ).first);
    expect(b.top, greaterThan(a.bottom - 1));
  });
}
