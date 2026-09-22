// Shef: tex kartaga KIRISH va konstruktor (regressiya qorovuli).
// Tex karta kartani IKKI MARTA bosish bilan ochiladi — bo'limlar gridida ham,
// konstruktorda ham (bir marta konstruktorda tex kartaga umuman kirib
// bo'lmay qolgan edi). Kartada alohida «kitob» tugmasi YO'Q.
// Yana: palitra yig'iladigan; konstruktorning nachinka qadamida qatlamlar
// («+ Qatlam» / «×») va faol qatlamning rang palitrasi.
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
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';
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

// Rang doirachalari (FillingColorPalette ichidagi 36px doiralar).
Finder _swatches() => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
    w.constraints?.maxWidth == 36);

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
    ]);
    products.products.addAll([
      _product(10, 'Бисквит Турецкий 18 см', 1, 'П/Ф Бисквит'),
      _product(20, 'Начинка клубничная', 2, 'П/Ф Начинка'),
    ]);
  });

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(497, 850);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(page, cats, products));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
  }

  // Kartani ikki marta bosish (nomi ustida) va marshrut ochilguncha kutish.
  Future<void> doubleTap(WidgetTester t, String name) async {
    final target = find.text(name);
    expect(target, findsOneWidget);
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 80));
    await t.tap(target);
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(t.takeException(), isNull);
  }

  testWidgets('section page: double tap opens the tech card; no book button',
      (t) async {
    await open(
      t,
      const ShefTechCardProductsPage(
        categoryId: 2,
        categoryName: 'П/Ф Начинка',
        showFillingCake: true,
      ),
    );
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    await doubleTap(t, 'Начинка клубничная');
    expect(find.byType(TechCardEditorPage), findsOneWidget);
  });

  testWidgets('constructor step 2: double tap opens the single filling palette',
      (t) async {
    await open(t, const ShefConstructorPage());
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));
    await doubleTap(t, 'Начинка клубничная');
    expect(find.byType(TechCardEditorPage), findsOneWidget);
    // Nachinka uchun YAGONA palitra — qatlamlar bo'yicha ikkinchisi yo'q.
    expect(find.text('Nachinka rangi'), findsOneWidget);
    expect(find.textContaining('qatlam'), findsNothing);
    expect(find.byType(FillingColorPalette), findsOneWidget);
  });

  testWidgets('constructor step 3: double tap opens the coating palette',
      (t) async {
    await open(t, const ShefConstructorPage());
    await t.tap(find.text('3'));
    await t.pump(const Duration(milliseconds: 400));
    await doubleTap(t, 'Начинка клубничная');
    expect(find.text('Покрытие rangi'), findsOneWidget);
  });

  testWidgets('constructor step 1: double tap opens the biscuit colour palette',
      (t) async {
    await open(t, const ShefConstructorPage());
    await doubleTap(t, 'Бисквит Турецкий 18 см');
    expect(find.text('Biskvit rangi'), findsOneWidget);
  });

  testWidgets('palette: collapsed by default, arrow expands and collapses',
      (t) async {
    await open(
      t,
      TechCardEditorPage(
        product: _product(20, 'Начинка клубничная', 2, 'П/Ф Начинка'),
        canEditPrices: false,
        showCoatingColor: true,
      ),
    );
    // Yig'ilgan: faqat sarlavha qatori — ranglar yo'q, o'ngda tanlangan
    // rang doirachasi (28px) va strelka.
    expect(_swatches(), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await t.tap(find.byIcon(Icons.expand_more));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(_swatches(), findsNWidgets(kFillingPalette.length));
    // Rang tanlash — sarlavhadagi doiracha shu rangda, «Rangsiz» chiqadi.
    await t.tap(_swatches().at(3));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Rangsiz'), findsOneWidget);
    await t.tap(find.byIcon(Icons.expand_less));
    await t.pump(const Duration(milliseconds: 300));
    expect(_swatches(), findsNothing);
    expect(find.text('Rangsiz'), findsNothing);
  });

  testWidgets('constructor: «+ Qatlam» adds a FILLING layer, × removes it',
      (t) async {
    await open(t, const ShefConstructorPage());
    // «Biskvit + ... + ...» matni olib tashlangan; qatlam chiplari 1-qadamda
    // (biskvit) YO'Q — ular nachinka qadamida.
    expect(find.textContaining('  +  '), findsNothing);
    expect(find.text('1-qatlam'), findsNothing);
    expect(find.text('Qatlam'), findsNothing);

    // 2-qadam: odatda 2 ta nachinka qatlami; «+ Qatlam» uchinchisini qo'shadi.
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('1-qatlam'), findsOneWidget);
    expect(find.text('2-qatlam'), findsOneWidget);
    expect(find.text('3-qatlam'), findsNothing);
    await t.tap(find.text('Qatlam'));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.text('3-qatlam'), findsOneWidget);

    // Ko'p qatlam bilan 3-qadam (qoplama) ham xatosiz chiziladi.
    for (final step in ['3', '1', '2']) {
      await t.tap(find.text(step));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
    }

    // Faqat eng ustki qatlamda «×» faol (bitta ishlaydigan tugma); qatorda
    // gorizontal surish — u ekrandan tashqarida bo'lishi mumkin.
    await t.ensureVisible(find.byIcon(Icons.close).last);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byIcon(Icons.close).last);
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.text('3-qatlam'), findsNothing);
    expect(find.text('2-qatlam'), findsOneWidget);
  });

  testWidgets('constructor: tapping a filling card shows THAT tech card',
      (t) async {
    await open(t, const ShefConstructorPage());
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));
    // Grid kartalari (nachinka mahsulotlari) bor; bosilsa tanlanadi va 3D
    // xatosiz qayta chiziladi — nachinka tanlangan tex kartadan.
    final cards = find.byType(FillingThumb);
    expect(cards, findsWidgets);
    await t.tap(cards.last);
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.byType(Filling3DView), findsOneWidget);
  });

  testWidgets('constructor: layer chips are enabled and toggle selection',
      (t) async {
    await open(t, const ShefConstructorPage());
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));
    InputChip chip(String label) => t.widget<InputChip>(
        find.ancestor(of: find.text(label), matching: find.byType(InputChip)));
    // Hamma chip faol (xira emas) va hech biri tanlanmagan.
    expect(chip('1-qatlam').isEnabled, isTrue);
    expect(chip('2-qatlam').isEnabled, isTrue);
    expect(chip('1-qatlam').selected, isFalse);
    // Bosish — tanlanadi; qayta bosish — tanlov olinadi.
    await t.tap(find.text('2-qatlam'));
    await t.pump(const Duration(milliseconds: 300));
    expect(chip('2-qatlam').selected, isTrue);
    expect(chip('1-qatlam').selected, isFalse);
    await t.tap(find.text('2-qatlam'));
    await t.pump(const Duration(milliseconds: 300));
    expect(chip('2-qatlam').selected, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('constructor: no colour palette outside the tech card',
      (t) async {
    await open(t, const ShefConstructorPage());
    await t.tap(find.text('2'));
    await t.pump(const Duration(milliseconds: 400));

    // 2-qadamda qatlam chiplari bor, lekin palitra YO'Q — rang faqat
    // mahsulot tex kartasi ichida (yagona nachinka palitrasi).
    expect(find.text('1-qatlam'), findsOneWidget);
    expect(find.textContaining('qatlam rangi'), findsNothing);
    expect(_swatches(), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });
}
