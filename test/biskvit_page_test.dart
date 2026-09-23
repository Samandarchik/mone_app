// Biskvit bo'limi (biskvit_page.dart): kirilishi bilan tepada HAMMA tortlar
// (nomi «Торт» bo'lgan kategoriyalar mahsulotlari), tort bosilsa tortning o'z
// konstruktori; kategoriya kartalari pastda.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/biskvit_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_cake_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_cakes_page.dart';

ProductModelAdmin _product(int id, String name, int cat, String catName) =>
    ProductModelAdmin(
      id: id,
      name: name,
      categoryId: cat,
      type: 'шт',
      categoryName: catName,
      filials: const [],
      filialNames: const [],
      techCard: const TechCard(bases: [
        TechBase(name: 'Бисквит', ingredients: [
          TechItem(name: 'Мука', unit: 'g', amount: 300),
        ]),
      ]),
    );

void main() {
  late CategoryProviderAdmin cats;
  late ProductProviderAdmin products;

  setUpAll(() {
    if (!GetIt.instance.isRegistered<Dio>()) {
      GetIt.instance.registerSingleton<Dio>(Dio());
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cats = CategoryProviderAdmin();
    products = ProductProviderAdmin();
    cats.categories.addAll([
      CategoryProductAdmin(
          id: 1, name: 'П/Ф Бисквит', imageUrl: null, printerId: 1),
      CategoryProductAdmin(id: 3, name: 'Торты', imageUrl: null, printerId: 1),
      CategoryProductAdmin(
          id: 4, name: 'Tortlar premium', imageUrl: null, printerId: 1),
    ]);
    products.products.addAll([
      _product(10, 'Бисквит Турецкий', 1, 'П/Ф Бисквит'),
      _product(30, 'Торт Рафаэлло', 3, 'Торты'),
      _product(31, 'Торт Медовик', 4, 'Tortlar premium'),
    ]);
  });

  Future<void> open(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: cats),
        ChangeNotifierProvider.value(value: products),
        ChangeNotifierProvider(create: (_) => ShefProvider()),
      ],
      child: const MaterialApp(home: BiskvitPage()),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
  }

  testWidgets('all cakes appear at once, from every «Торт» category',
      (t) async {
    await open(t, const Size(497, 900));
    expect(find.text('Tortlar'), findsOneWidget);
    expect(find.text('Торт Рафаэлло'), findsOneWidget);
    expect(find.text('Торт Медовик'), findsOneWidget);
    expect(find.byType(CakeCard), findsNWidgets(2));
    // Biskvit — tort emas.
    expect(find.text('Бисквит Турецкий'), findsNothing);
    // Tort bosilsa — tortning o'z konstruktori.
    await t.tap(find.text('Торт Рафаэлло'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(ShefCakeConstructorPage), findsOneWidget);
  });

  testWidgets('narrow screen: cards keep their height, one per row',
      (t) async {
    await open(t, const Size(240, 900));
    expect(t.takeException(), isNull);
    final cards = t.widgetList<CakeCard>(find.byType(CakeCard)).toList();
    expect(cards.length, 2);
    // Ikkinchi karta BIRINCHISINING OSTIDA (bitta ustun), o'lchami qat'iy.
    final a = t.getRect(find.byType(CakeCard).first);
    final b = t.getRect(find.byType(CakeCard).last);
    expect(b.top, greaterThan(a.bottom - 1));
    expect(a.height, 246);
  });
}
