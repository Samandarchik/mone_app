// «Торты» bo'limi (shef_cakes_page.dart): tortlar gridi, tort bosilsa
// konstruktor shu tort bilan (tanlovlar tex kartadan), ikki marta — tex
// karta; isTortCategory — nom bo'yicha.
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
import 'package:uz_ai_dev/shef/ui/shef_cakes_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

ProductModelAdmin _product(
  int id,
  String name,
  int cat,
  String catName, {
  TechCard? card,
}) =>
    ProductModelAdmin(
      id: id,
      name: name,
      categoryId: cat,
      type: 'шт',
      categoryName: catName,
      filials: const [],
      filialNames: const [],
      techCard: card ??
          const TechCard(
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

// Tort tex kartasi: biskvit (id 10) + 2 ta nachinka (id 20, 21) + krem (id 22).
const TechCard _cakeCard = TechCard(
  diameterCm: 22,
  heightCm: 8,
  shape: 'round',
  pieceWeightG: 1500,
  bases: [
    TechBase(name: 'Сборка', ingredients: [
      TechItem(productId: 10, name: 'Бисквит', unit: 'pcs', amount: 1),
      TechItem(productId: 20, name: 'Начинка клубничная', unit: 'g', amount: 300),
      TechItem(productId: 21, name: 'Начинка шоколадная', unit: 'g', amount: 300),
      TechItem(productId: 22, name: 'Крем сырный', unit: 'g', amount: 400),
    ]),
  ],
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
      CategoryProductAdmin(
          id: 1, name: 'П/Ф Бисквит', imageUrl: null, printerId: 1),
      CategoryProductAdmin(
          id: 2, name: 'П/Ф Начинка', imageUrl: null, printerId: 1),
      CategoryProductAdmin(id: 3, name: 'Торты', imageUrl: null, printerId: 1),
    ]);
    products.products.addAll([
      _product(10, 'Бисквит Турецкий', 1, 'П/Ф Бисквит'),
      _product(11, 'Бисквит Шоколадный', 1, 'П/Ф Бисквит'),
      _product(20, 'Начинка клубничная', 2, 'П/Ф Начинка'),
      _product(21, 'Начинка шоколадная', 2, 'П/Ф Начинка'),
      _product(22, 'Крем сырный', 2, 'П/Ф Начинка'),
      _product(30, 'Торт Клубничный', 3, 'Торты', card: _cakeCard),
      _product(31, 'Торт без карты', 3, 'Торты', card: const TechCard()),
    ]);
  });

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(497, 850);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: cats),
        ChangeNotifierProvider.value(value: products),
        ChangeNotifierProvider(create: (_) => ShefProvider()),
      ],
      child: MaterialApp(home: page),
    ));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
  }

  test('isTortCategory: nom bo\'yicha, biskvit/nachinka emas', () {
    expect(isTortCategory('Торты'), isTrue);
    expect(isTortCategory('Tortlar'), isTrue);
    expect(isTortCategory('Бисквит для торта'), isFalse);
    expect(isTortCategory('Начинка для торта'), isFalse);
    expect(isTortCategory('Выпечка'), isFalse);
  });

  testWidgets('cakes grid: names, size line and tech card status', (t) async {
    await open(
      t,
      const ShefCakesPage(categoryId: 3, categoryName: 'Торты'),
    );
    expect(find.text('Торт Клубничный'), findsOneWidget);
    expect(find.text('Торт без карты'), findsOneWidget);
    // Boshqa kategoriya mahsulotlari chiqmaydi.
    expect(find.text('Начинка клубничная'), findsNothing);
    expect(find.text('Ø 22 sm · 8 sm · 1.5 kg'), findsOneWidget);
    expect(find.text('Тех карта bor'), findsOneWidget);
    expect(find.text('Тех карта to\'ldirilmagan'), findsOneWidget);
    // Foto yo'q — qoplangan tort chizmasi.
    expect(find.byType(FillingThumb), findsNWidgets(2));
  });

  testWidgets('tap a cake → constructor with that cake preselected',
      (t) async {
    await open(
      t,
      const ShefCakesPage(categoryId: 3, categoryName: 'Торты'),
    );
    await t.tap(find.text('Торт Клубничный'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(ShefConstructorPage), findsOneWidget);
    // Sarlavha — tort nomi; 3-qadamdan (qoplangan tort) boshlanadi.
    expect(find.text('Торт Клубничный'), findsOneWidget);
    expect(find.byType(Filling3DView), findsOneWidget);
    expect(find.text('3. Tashqi qoplamani tanlang'), findsOneWidget);
    // 2-qadam: tex kartadagi 2 ta nachinka — 2 ta qatlam chipi.
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('1-qatlam'), findsOneWidget);
    expect(find.text('2-qatlam'), findsOneWidget);
    expect(find.text('3-qatlam'), findsNothing);
  });

  testWidgets('double tap a cake → its tech card', (t) async {
    await open(
      t,
      const ShefCakesPage(categoryId: 3, categoryName: 'Торты'),
    );
    final target = find.text('Торт Клубничный');
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
    expect(find.byType(ShefConstructorPage), findsNothing);
  });
}
