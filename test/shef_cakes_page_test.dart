// «Торты» bo'limi (shef_cakes_page.dart): tortlar gridi, tort bosilsa
// TORTNING O'Z konstruktori (shef_cake_constructor_page.dart — qadamlar tex
// karta bloklari, 3D shulardan yig'iladi), ikki marta — tex karta;
// isTortCategory — nom bo'yicha.
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
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_cake_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_cakes_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_constructor_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_illustration.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

ProductModelAdmin _product(int id, String name, int cat, String catName,
        {TechCard card = const TechCard()}) =>
    ProductModelAdmin(
      id: id,
      name: name,
      categoryId: cat,
      type: 'шт',
      categoryName: catName,
      filials: const [],
      filialNames: const [],
      techCard: card,
    );

// «Рафаэлло» tex kartasi: 4 blok — biskvit, kokos kremi, qoplama, dekor.
const TechCard _raffaello = TechCard(
  diameterCm: 22,
  heightCm: 8,
  shape: 'round',
  pieceWeightG: 1500,
  stages: [TechStage(name: 'Бисквит'), TechStage(name: 'Крем')],
  bases: [
    TechBase(name: 'Бисквит ванильный', stage: 1, ingredients: [
      TechItem(name: 'Мука', unit: 'g', amount: 300),
      TechItem(name: 'Яйцо', unit: 'pcs', amount: 6),
    ]),
    TechBase(name: 'Крем кокосовый', stage: 2, ingredients: [
      TechItem(name: 'Сливки 33%', unit: 'ml', amount: 500),
      TechItem(name: 'Кокосовая стружка', unit: 'g', amount: 120),
    ]),
    TechBase(name: 'Покрытие', stage: 2, ingredients: [
      TechItem(name: 'Крем чиз', unit: 'g', amount: 400),
    ]),
    TechBase(name: 'Декор', stage: 2, ingredients: [
      TechItem(name: 'Рафаэлло конфеты', unit: 'pcs', amount: 8),
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
          id: 2, name: 'П/Ф Начинка', imageUrl: null, printerId: 1),
      CategoryProductAdmin(id: 3, name: 'Торты', imageUrl: null, printerId: 1),
    ]);
    products.products.addAll([
      _product(20, 'Начинка клубничная', 2, 'П/Ф Начинка'),
      _product(30, 'Торт Рафаэлло', 3, 'Торты', card: _raffaello),
      _product(31, 'Торт без карты', 3, 'Торты'),
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

  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 600));
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
        t, const ShefCakesPage(categoryId: 3, categoryName: 'Торты'));
    expect(find.text('Торт Рафаэлло'), findsOneWidget);
    expect(find.text('Торт без карты'), findsOneWidget);
    // Boshqa kategoriya mahsulotlari chiqmaydi.
    expect(find.text('Начинка клубничная'), findsNothing);
    expect(find.text('Ø 22 sm · 8 sm · 1.5 kg'), findsOneWidget);
    expect(find.text('Тех карта bor'), findsOneWidget);
    expect(find.text('Тех карта to\'ldirilmagan'), findsOneWidget);
    // Foto yo'q — tortning vektor illyustratsiyasi.
    expect(find.byType(CakeIllustrationView), findsNWidgets(2));
  });

  testWidgets('tap a cake → ITS OWN constructor built from tech card blocks',
      (t) async {
    await open(
        t, const ShefCakesPage(categoryId: 3, categoryName: 'Торты'));
    await t.tap(find.text('Торт Рафаэлло'));
    await settle(t);
    expect(find.byType(ShefCakeConstructorPage), findsOneWidget);
    // Umumiy konstruktor EMAS.
    expect(find.byType(ShefConstructorPage), findsNothing);
    expect(find.text('Торт Рафаэлло'), findsOneWidget);

    // 1-qadam (boshlanish) — tortning biskviti (3D), ostida biskvit bloki
    // va masalliqlari.
    expect(find.byType(Biscuit3DView), findsOneWidget);
    expect(find.byType(Filling3DView), findsNothing);
    expect(find.text('1. Tortning biskviti'), findsOneWidget);
    expect(find.text('Бисквит ванильный'), findsOneWidget);
    expect(find.text('Мука'), findsOneWidget);
    expect(find.text('300 г'), findsOneWidget);
    expect(find.text('Og\'irligi 300 г'), findsOneWidget);
    // Boshqa qadam bloklari bu yerda yo'q.
    expect(find.text('Крем кокосовый'), findsNothing);

    // 2-qadam — bo'lak kesimi, kesimda tex kartadagi nachinka.
    await t.tap(find.text('2'));
    await settle(t);
    expect(find.byType(Filling3DView), findsOneWidget);
    expect(find.byType(Biscuit3DView), findsNothing);
    expect(find.text('2. Bo\'lak kesimi — nachinka'), findsOneWidget);
    expect(find.text('Крем кокосовый'), findsOneWidget);
    expect(find.text('Nachinka'), findsOneWidget);
    expect(find.text('Кокосовая стружка'), findsOneWidget);
    expect(find.text('Покрытие'), findsNothing);

    // 3-qadam — tayyor tort illyustratsiyasi; qoplama va dekor bloklari.
    await t.tap(find.text('3'));
    await settle(t);
    expect(find.byType(Filling3DView), findsNothing);
    expect(find.byType(CakeIllustrationView), findsOneWidget);
    expect(find.text('3. Tayyor tort'), findsOneWidget);
    expect(find.text('Покрытие'), findsOneWidget);
    expect(find.text('Qoplama'), findsOneWidget);
    expect(find.text('Декор'), findsOneWidget);
    expect(find.text('Bezak'), findsOneWidget);
    expect(find.text('Рафаэлло конфеты'), findsOneWidget);
    expect(find.text('8 дона'), findsOneWidget);
  });

  testWidgets('step 3 illustration spec comes from the tech card',
      (t) async {
    await open(t, ShefCakeConstructorPage(cake: products.products[1]));
    await t.tap(find.text('3'));
    await settle(t);
    final view =
        t.widget<CakeIllustrationView>(find.byType(CakeIllustrationView));
    expect(view.spec.decor, contains(CakeDecor.raffaello));
    expect(view.spec.texture, CakeCoatTexture.coconut);
    expect(view.label, 'Mone');
    // Tortning fotosi bu yerda ishlatilmaydi.
    expect(find.byType(AppNetworkImage), findsNothing);
  });

  testWidgets('cake with only a biscuit block: step 2 falls back to biscuit',
      (t) async {
    final cake = _product(
      32,
      'Торт Медовик',
      3,
      'Торты',
      card: const TechCard(
        diameterCm: 20,
        heightCm: 6,
        bases: [
          TechBase(name: 'Коржи медовые', ingredients: [
            TechItem(name: 'Мёд', unit: 'g', amount: 200),
          ]),
        ],
      ),
    );
    await open(t, ShefCakeConstructorPage(cake: cake));
    await t.tap(find.text('2'));
    await settle(t);
    expect(find.byType(Biscuit3DView), findsOneWidget);
    expect(find.textContaining('nachinka bloki'), findsOneWidget);
    await t.tap(find.text('3'));
    await settle(t);
    expect(find.byType(CakeIllustrationView), findsOneWidget);
    expect(find.textContaining('qoplama/dekor bloki yo\'q'), findsOneWidget);
  });

  testWidgets('cake without tech card → hint with tech card button',
      (t) async {
    await open(t, ShefCakeConstructorPage(cake: products.products.last));
    expect(find.text('Tex kartani ochish'), findsOneWidget);
    expect(find.byType(Filling3DView), findsNothing);
    await t.tap(find.text('Tex kartani ochish'));
    await settle(t);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
  });

  testWidgets('double tap a cake → its tech card', (t) async {
    await open(
        t, const ShefCakesPage(categoryId: 3, categoryName: 'Торты'));
    final target = find.text('Торт Рафаэлло');
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(target);
    await settle(t);
    expect(find.byType(TechCardEditorPage), findsOneWidget);
    expect(find.byType(ShefCakeConstructorPage), findsNothing);
  });
}
