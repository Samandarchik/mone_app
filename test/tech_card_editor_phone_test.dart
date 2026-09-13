// test/tech_card_editor_phone_test.dart — TechCardEditorPage TELEFON
// tartibining regressiya qo'riqchisi.
//
// NEGA: sahifa Excel «тех карта» varag'ini takrorlaydi va qatorda 4 ta
// QAT'IY kenglikdagi ustun bor edi (52+68+68+80 = 268dp). 360dp telefonda
// sahifa padding'idan keyin masalliq NOMIGA atigi ~68dp qolardi — ya'ni
// 3-4 harf. Endi tor blokda «Цена» ustuni qatordan chiqib, nom ostidagi
// kichik satrga tushadi va nom ustuni ~2.5 barobar kengayadi.
//
// Test 360x800 (oddiy telefon) da sahifani chizadi va tekshiradi:
//   1) hech qaerda RenderFlex overflow yo'q;
//   2) masalliq nomi ustuni yetarlicha keng (>= 140dp);
//   3) narx yo'qolmagan — nom ostidagi satrda ko'rinadi va bosiladi.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/di/di.dart';

// Tarmoqqa umuman chiqmaydigan Dio adapteri: sahifaning initState'dagi
// `/api/prices/latest` so'rovi darhol xato bilan tugaydi (haqiqiy soket ham,
// kutish taymeri ham yaratilmaydi).
class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      Future.error(DioException.connectionError(
          requestOptions: options, reason: 'offline (test)'));
}

// Uzun nomli masalliqlar — aynan shular eski tartibda «Сах...» bo'lib
// qirqilardi.
const String _longName = 'Сахарная пудра мелкого помола';

ProductModelAdmin _product() => ProductModelAdmin.fromJson({
      'id': 1,
      'name': 'Торт Наполеон классический большой',
      'category_id': 1,
      'type': 'шт',
      'tech_card': {
        'batch_qty': 12,
        'list_qty': 2,
        'shape': 'round',
        'diameter_cm': 26,
        'height_cm': 8,
        'bases': [
          {
            'name': 'Бисквит',
            'color': '#E54C5E',
            'ingredients': [
              {'name': _longName, 'unit': 'g', 'amount': 1500, 'product_id': 2},
              {'name': 'Мука высший сорт', 'unit': 'g', 'amount': 3000},
              {'name': 'Яйцо куриное', 'unit': 'pcs', 'amount': 24},
            ],
          },
          {
            'name': 'Крем сливочный',
            'color': '#75BD42',
            'ingredients': [
              {'name': 'Сливки 33%', 'unit': 'ml', 'amount': 2000},
            ],
          },
        ],
        'consumables': [
          {'name': 'Коробка картонная 26см', 'unit': 'pcs', 'amount': 12},
        ],
        'profit_mode': 'percent',
        'profit_value': 30,
        'overhead_mode': 'percent',
        'overhead_value': 12,
        'sale_price': 185000,
      },
    });

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<ProductProviderAdmin>(
      create: (_) => ProductProviderAdmin(),
      child: MaterialApp(home: TechCardEditorPage(product: _product())),
    ),
  );
  await tester.pump();
  // Sahifa initState'da narx so'rovini boshlaydi — kutayotgan taymerlar
  // sinov tugashidan oldin ishlab bo'lsin.
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() {
    // Sahifa initState'da narxlarni so'raydi — Dio ro'yxatdan o'tmasa
    // GetIt otib yuboradi. So'rovning o'zi tarmoqqa chiqmay xato beradi va
    // sahifa uni JIM yutadi (narxlar «—» bo'lib qoladi).
    if (!sl.isRegistered<Dio>()) {
      sl.registerSingleton<Dio>(Dio()..httpClientAdapter = _OfflineAdapter());
    }
  });

  testWidgets('360dp telefonda overflow yo\'q va nom ustuni keng',
      (tester) async {
    await _pumpAt(tester, const Size(360, 800));
    expect(tester.takeException(), isNull);

    // Masalliq nomi to'liq matn sifatida topilishi kerak (Text widget'i
    // bor — qirqilishi ellipsis bilan bo'ladi, lekin kengligi muhim).
    final nameFinder = find.text(_longName);
    expect(nameFinder, findsOneWidget);

    // Eski tartibda bu ~52dp edi (68dp katak − 16dp padding).
    final nameW = tester.getSize(nameFinder).width;
    expect(nameW, greaterThanOrEqualTo(140),
        reason: 'nom ustuni juda tor: $nameW dp');
  });

  testWidgets('telefonda narx nom ostidagi satrda qoladi', (tester) async {
    await _pumpAt(tester, const Size(360, 800));
    // Narxlar yuklanmagan (tarmoq yo'q) — lekin narxlanadigan masalliq
    // uchun «narx yo'q» satri chiqishi kerak, ya'ni siqilgan tartib ishlagan.
    expect(find.text('narx yo\'q'), findsWidgets);
  });

  testWidgets('kichik (320dp) telefonda ham overflow yo\'q', (tester) async {
    await _pumpAt(tester, const Size(320, 720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('planshetda (900dp) overflow yo\'q', (tester) async {
    await _pumpAt(tester, const Size(900, 1200));
    expect(tester.takeException(), isNull);
  });
}
