// Tex karta muharriri BISKVIT rejimi (TechCardEditorPage.biscuitMode):
// karta boshida «Выпечка» (vaqt/harorat) maydonlari, partiya faqat шт'da —
// гр'da saqlangan karta 1 шт ga o'giriladi, гр almashtirgichi yo'q.
// Sarlavha jadvalidagi «Вес всех ингредиентов» ustuni rejimga bog'liq emas:
// hamma kartada bor, tahrirlanadi va retseptni mutanosib qayta hisoblaydi.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';

// «Бисквит Турецкий»: гр rejimida saqlangan — 302 гр = masalliqlar yig'indisi.
ProductModelAdmin _biscuit({String unit = 'g', int batchQty = 302}) =>
    ProductModelAdmin(
      id: 10,
      name: 'Бисквит Турецкий',
      categoryId: 1,
      type: 'шт',
      categoryName: 'П/Ф Бисквит',
      filials: const [],
      filialNames: const [],
      isSemiFinished: true,
      techCard: TechCard(
        diameterCm: 15,
        shape: 'round',
        batchUnit: unit,
        batchQty: batchQty,
        bakeTimeMin: 25,
        bases: const [
          TechBase(name: 'Тесто', ingredients: [
            TechItem(name: 'Мука', unit: 'g', amount: 200),
            TechItem(name: 'Сахар', unit: 'g', amount: 102),
          ]),
        ],
      ),
    );

void main() {
  setUpAll(() {
    if (!GetIt.instance.isRegistered<Dio>()) {
      GetIt.instance.registerSingleton<Dio>(Dio());
    }
  });

  Future<void> open(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(497, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => ProductProviderAdmin(),
      child: MaterialApp(home: page),
    ));
    await t.pump(const Duration(seconds: 5));
    expect(t.takeException(), isNull);
  }

  testWidgets('biscuit mode: baking fields first, weight per piece, шт only',
      (t) async {
    await open(
      t,
      TechCardEditorPage(
        product: _biscuit(),
        canEditPrices: false,
        showBiscuitPhoto: true,
        biscuitMode: true,
      ),
    );
    // Karta boshida «Выпечка»: vaqt to'ldirilgan (25), harorat bo'sh.
    expect(find.text('Выпечка'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
    expect(find.text('мин'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    final bakingY = t.getTopLeft(find.text('Выпечка')).dy;
    expect(bakingY, lessThan(t.getTopLeft(find.text('Наименование')).dy));

    // Гр'da saqlangan karta → шт: sarlavhada «Штук» (Грамм emas), 1 шт,
    // «Вес всех ингредиентов» = masalliqlar yig'indisi 302 г.
    expect(find.text('Грамм'), findsNothing);
    expect(find.text('Штук'), findsOneWidget);
    expect(find.text('Вес всех ингредиентов'), findsOneWidget);
    expect(find.widgetWithText(TextField, '302'), findsOneWidget);
    expect(find.text('Общее количество:'), findsOneWidget);
    // Гр almashtirgichi yo'q — faqat «шт» yozuvi.
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
    expect(find.text('шт'), findsNWidgets(2));

    // Harorat kiritilsa — kartaga yoziladi (saqlashda ketadi).
    final tempField = find.ancestor(
      of: find.text('°C'),
      matching: find.byType(TextField),
    );
    await t.enterText(tempField, '180');
    await t.pump(const Duration(milliseconds: 300));
    final state = t.state(find.byType(TechCardEditorPage)) as dynamic;
    final TechCard card = state.c.build();
    expect(card.bakeTempC, 180);
    expect(card.bakeTimeMin, 25);
    expect(card.batchUnit, '');
    expect(card.batchQty, 1);
    expect(card.listQty, 1);
  });

  testWidgets('without biscuit mode: cooking row stays, biscuit extras go',
      (t) async {
    await open(
      t,
      TechCardEditorPage(product: _biscuit(), canEditPrices: false),
    );
    // Vaqt/harorat qatori HAMMA kartada — «Приготовление» nomi bilan.
    expect(find.text('Выпечка'), findsNothing);
    expect(find.text('Приготовление'), findsOneWidget);
    expect(find.text('мин'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    // Og'irlik ustuni bu yerda ham bor.
    expect(find.text('Вес всех ингредиентов'), findsOneWidget);
    expect(find.text('Грамм'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
  });

  testWidgets('total ingredient weight is editable → recipe scales', (t) async {
    await open(
      t,
      TechCardEditorPage(
        product: _biscuit(),
        canEditPrices: false,
        biscuitMode: true,
      ),
    );
    // Мука 200 + Сахар 102 = 302 г.
    final weightField = find.widgetWithText(TextField, '302');
    expect(weightField, findsOneWidget);

    // 604 г — ikki barobar: har masalliq ham ikki barobar bo'ladi.
    await t.enterText(weightField, '604');
    await t.pump(const Duration(milliseconds: 300));
    final state = t.state(find.byType(TechCardEditorPage)) as dynamic;
    final TechCard card = state.c.build();
    expect(card.bases.first.ingredients[0].amount, 400); // Мука
    expect(card.bases.first.ingredients[1].amount, 204); // Сахар
    expect(card.computedBatchWeightG, 604);
  });

  testWidgets('tech card ends with a Сохранить button', (t) async {
    await open(
      t,
      TechCardEditorPage(product: _biscuit(), canEditPrices: false),
    );
    final button = find.widgetWithText(ElevatedButton, 'Сохранить');
    expect(button, findsOneWidget);
    // Kartaning OXIRIDA — masalliqlar jadvalidan pastda.
    expect(
      t.getTopLeft(button).dy,
      greaterThan(t.getTopLeft(find.text('Наименование')).dy),
    );
  });
}
