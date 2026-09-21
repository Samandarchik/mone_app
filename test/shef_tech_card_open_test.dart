// Shef: tex kartaga KIRISH yo'llari (regressiya qorovuli). Bir marta konstruktorda
// tex kartaga umuman kirib bo'lmay qolgan edi — kartada na tugma, na ikki marta
// bosish bor edi. Tekshiriladi: konstruktor kartasidagi tugma (2-qadam — ikkita
// nachinka palitrasi, 3-qadam — «Покрытие rangi»), bo'lim gridi kartasidagi tugma
// va eski usul — kartani ikki marta bosish.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';

ProductModelAdmin _product(int id, String name, int cat, String catName) =>
    ProductModelAdmin(
      id: id,
      name: name,
      categoryId: cat,
      type: 'шт',
      categoryName: catName,
      filials: const [],
      filialNames: const [],
      techCard: const TechCard(
        diameterCm: 18,
        heightCm: 6,
        shape: 'round',
        bases: [
          TechBase(name: 'Основа', ingredients: [
            TechItem(name: 'Сливки', unit: 'ml', amount: 500),
          ]),
        ],
      ),
    );

Widget _app(Widget home, CategoryProviderAdmin cats,
        ProductProviderAdmin products) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: cats),
        ChangeNotifierProvider.value(value: products),
        ChangeNotifierProvider(create: (_) => ShefProvider()),
      ],
      child: MaterialApp(home: home),
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
    cats = CategoryProviderAdmin();
    products = ProductProviderAdmin();
    cats.categories.addAll([
      CategoryProductAdmin(id: 1, name: 'П/Ф Бисквит', imageUrl: null, printerId: 1),
      CategoryProductAdmin(id: 2, name: 'П/Ф Начинка', imageUrl: null, printerId: 1),
    ]);
    products.products.addAll([
      _product(10, 'Бисквит Турецкий 18 см', 1, 'П/Ф Бисквит'),
      _product(20, 'Начинка клубничная', 2, 'П/Ф Начинка'),
    ]);
  });

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(497, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('constructor: button on a card opens the tech card', (t) async {
    await size(t);
    await t.pumpWidget(_app(const ShefConstructorPage(), cats, products));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);

    // 2-qadam (nachinka) → kartadagi tugma → тех карта, 2 ta palitra bilan.
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(TechCardOpenButton), findsOneWidget);
    await t.tap(find.byType(TechCardOpenButton));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
    expect(find.textContaining('1-qatlam'), findsOneWidget);
    expect(find.textContaining('2-qatlam'), findsOneWidget);
  });

  testWidgets('constructor: step 3 opens the coating palette', (t) async {
    await size(t);
    await t.pumpWidget(_app(const ShefConstructorPage(), cats, products));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('3'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byType(TechCardOpenButton));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.text('Покрытие rangi'), findsOneWidget);
  });

  testWidgets('section page: button on a card opens the tech card', (t) async {
    await size(t);
    await t.pumpWidget(_app(
      const ShefTechCardProductsPage(
        categoryId: 2,
        categoryName: 'П/Ф Начинка',
        showFillingCake: true,
      ),
      cats,
      products,
    ));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    await t.tap(find.byType(TechCardOpenButton));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
  });

  doubleTapTests(() => cats, () => products);
}

void doubleTapTests(
  CategoryProviderAdmin Function() cats,
  ProductProviderAdmin Function() products,
) {
  testWidgets('section page: DOUBLE TAP on a card opens the tech card',
      (t) async {
    t.view.physicalSize = const Size(497, 850);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(
      const ShefTechCardProductsPage(
        categoryId: 2,
        categoryName: 'П/Ф Начинка',
        showFillingCake: true,
      ),
      cats(),
      products(),
    ));
    await t.pump(const Duration(milliseconds: 400));
    final name = find.text('Начинка клубничная');
    expect(name, findsOneWidget);
    await t.tap(name);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(name);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
  });
}
