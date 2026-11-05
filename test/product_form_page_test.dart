import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/model/user_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/product_form_page.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'helpers/catalog_test_env.dart';

class _Categories extends CategoryProviderAdmin {
  @override
  Future<void> getCategories() async {}
}

class _Filials extends FilialProviderAdmin {
  @override
  Future<void> getFilials() async {}
}

class _Products extends ProductProviderAdmin {
  final requests = <Product>[];
  Completer<Product?>? pending;
  @override
  String? get error => 'Server saqlashni rad etdi';
  @override
  Future<Product?> saveProduct(Product product) async {
    requests.add(product);
    return pending == null ? null : await pending!.future;
  }
}

void main() {
  late _Products products;
  late _Categories categories;
  late _Filials filials;
  setUp(() {
    registerTestCatalog();
    products = _Products();
    categories = _Categories();
    categories.categories.add(CategoryProductAdmin(
        id: 2, name: 'Xomashyo', imageUrl: null, printerId: 1));
    filials = _Filials();
    filials.filials.add(Filial(id: 3, name: 'Markaz'));
  });
  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> open(WidgetTester tester, ProductFormPage page) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<CategoryProviderAdmin>.value(value: categories),
      ChangeNotifierProvider<FilialProviderAdmin>.value(value: filials),
      ChangeNotifierProvider<ProductProviderAdmin>.value(value: products),
    ], child: MaterialApp(home: page)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('kichik ekranda PF uchun faqat asosiy ma’lumot va retsept',
      (t) async {
    await open(t,
        const ProductFormPage(initialCategoryId: 2, initialSemiFinished: true));
    expect(find.text('2. Sotuv'), findsNothing);
    expect(find.text('3. Xarid'), findsNothing);
    expect(find.text('Saqlab, retseptni ochish'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('name')), 'Krem');
    await t.tap(find.byKey(const ValueKey('save-product')));
    await t.pumpAndSettle();
    expect(products.requests, hasLength(1));
    expect(products.requests.single.kind, ProductKind.pf);
    expect(products.requests.single.categoryId, 2);
    expect(products.requests.single.sostav, isEmpty);
    expect(find.text('Server saqlashni rad etdi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('majburiy maydon xatosida so‘rov yuborilmaydi', (t) async {
    await open(t, const ProductFormPage());
    await t.tap(find.byKey(const ValueKey('save-product')));
    await t.pumpAndSettle();
    expect(products.requests, isEmpty);
    expect(find.textContaining('Mahsulot nomini kiriting'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('xarid xatosi foydalanuvchi yozgan miqdorni saqlab qoladi',
      (t) async {
    await open(
        t,
        ProductFormPage(
            product: Product(
          id: 12,
          name: 'Un',
          categoryId: 2,
          unit: 'кг',
          purchasable: true,
          sklads: [1],
          buyStep: 25000,
        )));
    final input = find.byKey(const ValueKey('buyStep'));
    await t.ensureVisible(input);
    await t.enterText(input, '-25');
    await t.tap(find.byKey(const ValueKey('save-product')));
    await t.pumpAndSettle();
    expect(products.requests, isEmpty);
    expect(find.textContaining('Musbat miqdor kiriting'), findsWidgets);
    await t.ensureVisible(input);
    await t.enterText(input, '0,5');
    await t.tap(find.byKey(const ValueKey('save-product')));
    await t.pumpAndSettle();
    expect(products.requests.single.buyStep, 500);
    expect(find.text('Server saqlashni rad etdi'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('saqlash tugamaguncha ikkinchi so‘rov ketmaydi', (t) async {
    products.pending = Completer<Product?>();
    await open(
        t,
        ProductFormPage(
            product: Product(
          id: 12,
          name: 'Krem',
          categoryId: 2,
          unit: 'шт',
          kind: ProductKind.pf,
        )));
    final save = find.byKey(const ValueKey('save-product'));
    await t.tap(save);
    await t.pump();
    await t.tap(save);
    await t.pump();
    expect(products.requests, hasLength(1));
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    products.pending!.complete(null);
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(save).onPressed, isNotNull);
    expect(t.takeException(), isNull);
  });
}
