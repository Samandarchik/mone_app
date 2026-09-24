// «П/Ф → Бисквиты»: tex kartada suratga olingan foto (biscuit_photo_url) —
// shu biskvitning ASOSIY rasmi. Kartada ham, tepada ham aynan o'sha foto
// (3D chizma emas); har biskvit — o'z fotosi; foto yo'q — avvalgi ko'rinish;
// almashtirilsa/o'chirilsa ro'yxat yangilanadi. Biskvit bo'limidagi
// «Бисквит» (showBaking) ro'yxatida ham foto va tex kartada «Rasm qo'shish».
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
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';

const _photoA = '/static/biskvit_15.jpg';
const _photoB = '/static/biskvit_18.jpg';

ProductModelAdmin _biscuit(int id, String name, {String photo = ''}) =>
    ProductModelAdmin(
      id: id,
      name: name,
      categoryId: 1,
      type: 'шт',
      categoryName: 'П/Ф Бисквит',
      filials: const [],
      filialNames: const [],
      techCard: TechCard(
        diameterCm: 18,
        heightCm: 6,
        shape: 'round',
        biscuitPhotoUrl: photo,
        // Pishirish chipi qisqa bo'lsin (test shrifti Ahem juda keng —
        // bo'sh chip matni «Pishirish rejimini kiriting» 497px'ga sig'maydi).
        bakeTimeMin: 30,
        bakeTempC: 180,
        bases: const [
          TechBase(name: 'Основа', ingredients: [
            TechItem(name: 'Мука', unit: 'g', amount: 500),
          ]),
        ],
      ),
    );

String _full(String raw) => '${AppUrls.baseUrl}$raw';

Finder _image(String url) => find.byWidgetPredicate(
    (w) => w is AppNetworkImage && w.imageUrl == url);

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
    cats.categories.add(CategoryProductAdmin(
        id: 1, name: 'П/Ф Бисквит', imageUrl: null, printerId: 1));
  });

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(497, 900);
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

  const sectionPage = ShefTechCardProductsPage(
    categoryId: 1,
    categoryName: 'П/Ф Бисквит',
    showCakeConstructor: true,
  );

  testWidgets('each biscuit shows its OWN photo, no 3D instead of it',
      (t) async {
    products.products.addAll([
      _biscuit(10, 'Бисквит Турецкий 15 см', photo: _photoA),
      _biscuit(11, 'Бисквит Турецкий 18 см', photo: _photoB),
    ]);
    await open(t, sectionPage);

    // Kartalar: har biri o'z fotosi (A — 15 sm, B — 18 sm).
    final cardA = find.ancestor(
        of: find.text('Бисквит Турецкий 15 см'), matching: find.byType(Column));
    final cardB = find.ancestor(
        of: find.text('Бисквит Турецкий 18 см'), matching: find.byType(Column));
    expect(find.descendant(of: cardA.first, matching: _image(_full(_photoA))),
        findsOneWidget);
    expect(find.descendant(of: cardA.first, matching: _image(_full(_photoB))),
        findsNothing);
    expect(find.descendant(of: cardB.first, matching: _image(_full(_photoB))),
        findsOneWidget);
    expect(find.descendant(of: cardB.first, matching: _image(_full(_photoA))),
        findsNothing);

    // Foto bor — 3D chizma yo'q (tepada ham, kartalarda ham).
    expect(find.byType(Biscuit3DView), findsNothing);
    expect(find.byType(BiscuitThumb), findsNothing);

    // Tepada tanlangan biskvitning o'z fotosi; boshqasini tanlasa — uniki.
    await t.tap(find.text('Бисквит Турецкий 18 см'));
    await t.pump(const Duration(milliseconds: 400));
    // Kartadagi + tepadagi = 2 ta B fotosi.
    expect(_image(_full(_photoB)), findsNWidgets(2));
    expect(_image(_full(_photoA)), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('no photo → previous look (3D) stays', (t) async {
    products.products.add(_biscuit(10, 'Бисквит Турецкий 15 см'));
    await open(t, sectionPage);
    expect(find.byType(Biscuit3DView), findsOneWidget);
    expect(find.byType(BiscuitThumb), findsOneWidget);
  });

  testWidgets('photo replaced / removed in tech card → list updates',
      (t) async {
    products.products.add(_biscuit(10, 'Бисквит Турецкий 15 см', photo: _photoA));
    await open(t, sectionPage);
    expect(_image(_full(_photoA)), findsWidgets);

    // Almashtirish (saqlangach provider yangi mahsulotni qo'yadi).
    products.products[0] =
        _biscuit(10, 'Бисквит Турецкий 15 см', photo: _photoB);
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    products.notifyListeners();
    await t.pump(const Duration(milliseconds: 300));
    expect(_image(_full(_photoB)), findsWidgets);
    expect(_image(_full(_photoA)), findsNothing);

    // O'chirish — foto yo'q, avvalgi ko'rinish (3D), eski foto qolmaydi.
    products.products[0] = _biscuit(10, 'Бисквит Турецкий 15 см');
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    products.notifyListeners();
    await t.pump(const Duration(milliseconds: 300));
    expect(_image(_full(_photoB)), findsNothing);
    expect(find.byType(Biscuit3DView), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Biskvit section list (showBaking): photo + tech card photo button',
      (t) async {
    products.products.add(_biscuit(10, 'Бисквит Турецкий 15 см', photo: _photoA));
    await open(
      t,
      const ShefTechCardProductsPage(
        categoryId: 1,
        categoryName: 'П/Ф Бисквит',
        showBaking: true,
      ),
    );
    expect(_image(_full(_photoA)), findsOneWidget);

    await t.tap(find.textContaining('Бисквит Турецкий 15 см'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(TechCardEditorPage), findsOneWidget);
    // Tex kartada foto bo'limi: shu biskvitning fotosi + almashtirish/o'chirish.
    expect(find.text('Almashtirish'), findsOneWidget);
    expect(_image(_full(_photoA)), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
