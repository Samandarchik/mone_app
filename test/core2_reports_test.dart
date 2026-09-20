// «Ombor 2.0» hisobotlari: model parsing (CORE_DEBT_KONTRAKT.md dagi
// HAQIQIY JSON misollari bilan), Excel (CSV) fayl nomi, davr shablonlari
// (hafta dushanbadan, «O'tgan oy» chegaralari), narx o'zgarishi rangi
// (±5 %) va `show_cost:false` da pul ustunlarining yashirilishi.
//
// Kod: `lib/core2/models/core_report2.dart`,
// `lib/core2/services/core_reports_service.dart`,
// `lib/core2/ui/reports/report_logic.dart`,
// `lib/core2/ui/reports/issues_report_ui.dart` (guruhlash),
// `lib/core2/ui/reports/inventory_diff_ui.dart` (saralash).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_reports_service.dart';
import 'package:uz_ai_dev/core2/ui/reports/inventory_diff_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/issues_report_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';

Map<String, dynamic> _json(String raw) =>
    Map<String, dynamic>.from(jsonDecode(raw) as Map);

void main() {
  // ───────────────────── Model parsing (haqiqiy javoblar) ─────────────────

  group('inventory-diff (kamomad / ortiqcha)', () {
    final j = _json('''
{"date_from":"2026-08-01","date_to":"2026-08-31","sklad_id":11,"group_id":null,"show_cost":true,
 "items":[{"sklad_id":11,"sklad_name":"Евроазия ЦЕХ ВЫПЕЧКА","good_id":12132,"good_name":"Подложка 26х26","base_unit":"mpcs","docs":1,
           "shortage_qty":3684000,"surplus_qty":0,"net_qty":-3684000,"shortage_sum":12894000,"surplus_sum":0,"net_sum":-12894000}],
 "by_sklad":[{"sklad_id":11,"sklad_name":"Евроазия ЦЕХ ВЫПЕЧКА","docs":5,"shortage_sum":43404463,"surplus_sum":0,"net_sum":-43404463,
              "docs_negative_sum":-43404463,"docs_positive_sum":0}],
 "by_month":[{"month":"2026-08","docs":5,"shortage_sum":43404463,"surplus_sum":0,"net_sum":-43404463,"docs_negative_sum":-43404463,
              "docs_positive_sum":0,"sklads":[{"sklad_id":11,"sklad_name":"Евроазия ЦЕХ ВЫПЕЧКА","docs":5,"net_sum":-43404463}]}],
 "total":{"docs":5,"shortage_sum":43404463,"surplus_sum":0,"net_sum":-43404463,"docs_negative_sum":-43404463,"docs_positive_sum":0}}''');

    test('qator, ombor, oy va jami o\'qiladi', () {
      final r = CoreInvDiffReport.fromJson(j);
      expect(r.dateFrom, '2026-08-01');
      expect(r.skladId, 11);
      expect(r.groupId, isNull);
      expect(r.showCost, isTrue);

      expect(r.items, hasLength(1));
      final it = r.items.first;
      expect(it.goodName, 'Подложка 26х26');
      expect(it.baseUnit, 'mpcs');
      expect(it.shortageQty, 3684000);
      expect(it.netQty, -3684000);
      expect(it.netSum, -12894000);

      expect(r.bySklad.single.docsNegativeSum, -43404463);
      expect(r.byMonth.single.month, '2026-08');
      expect(r.byMonth.single.sklads.single.skladId, 11);
      expect(r.total.docs, 5);
      expect(r.total.netSum, -43404463);
    });

    test('«2026-08» → «Avgust 2026»', () {
      expect(coreMonthUz('2026-08'), 'Avgust 2026');
      expect(coreMonthUz(''), '—');
    });

    test('tovarlar kamomad / sof farq / nom bo\'yicha saralanadi', () {
      const a = CoreInvDiffRow(
          goodName: 'Bravo', shortageSum: 100, netSum: -100, goodId: 1);
      const b = CoreInvDiffRow(
          goodName: 'Alfa', shortageSum: 900, netSum: -400, goodId: 2);
      const c = CoreInvDiffRow(
          goodName: 'Charli', shortageSum: 0, surplusSum: 50, netSum: 50, goodId: 3);
      final src = [a, b, c];
      expect(sortInvDiffItems(src, InvDiffSort.shortage).first.goodId, 2);
      // Sof farq: eng katta KAMOMAD (eng manfiy) birinchi.
      expect(sortInvDiffItems(src, InvDiffSort.net).first.goodId, 2);
      expect(sortInvDiffItems(src, InvDiffSort.net).last.goodId, 3);
      expect(sortInvDiffItems(src, InvDiffSort.name).first.goodName, 'Alfa');
      // Manba ro'yxat o'zgarmaydi.
      expect(src.first.goodId, 1);
    });
  });

  group('issues (spisaniye)', () {
    final j = _json('''
{"date_from":"2026-08-20","date_to":"2026-09-19","sklad_id":null,"corr_id":null,"show_cost":true,"total_cost":27902868,
 "items":[{"corr_id":16,"corr_name":"Списание Бухг.","corr_kind":"writeoff","sklad_id":29,"sklad_name":"Гелион МОРОЖЕНОЕ ФРЕЗЕР","good_id":10400,
           "good_name":"ММОРОЖЕНОЕ ФРЕЗЕРНОЕ масса","base_unit":"g","docs":23,"qty":209113,"cost":3664489},
          {"corr_id":16,"corr_name":"Списание Бухг.","corr_kind":"writeoff","sklad_id":38,"sklad_name":"ГЕЛИОН КУХНЯ","good_id":10401,
           "good_name":"Сахар","base_unit":"g","docs":4,"qty":5000,"cost":60000},
          {"corr_id":0,"corr_name":"","corr_kind":"","sklad_id":38,"sklad_name":"ГЕЛИОН КУХНЯ","good_id":10402,
           "good_name":"Масло","base_unit":"g","docs":1,"qty":1000,"cost":25000}],
 "totals":[{"corr_id":16,"corr_name":"Списание Бухг.","sklad_id":38,"sklad_name":"ГЕЛИОН КУХНЯ","positions":60,"cost":10311367}]}''');

    test('qatorlar va jamlar o\'qiladi', () {
      final r = CoreIssuesReport.fromJson(j);
      expect(r.totalCost, 27902868);
      expect(r.items, hasLength(3));
      expect(r.items.first.corrKind, 'writeoff');
      expect(r.items.first.qty, 209113);
      expect(r.items.last.noCorr, isTrue);
      expect(r.totals.single.positions, 60);
    });

    test('sabab → ombor → tovar guruhlanadi va summa bo\'yicha saralanadi', () {
      final r = CoreIssuesReport.fromJson(j);
      final groups = groupIssueRows(r.items);
      expect(groups, hasLength(2)); // «Списание Бухг.» va kontragentsiz
      final first = groups.first;
      expect(first.corrName, 'Списание Бухг.');
      expect(first.cost, 3664489 + 60000);
      expect(first.sklads, hasLength(2));
      // Eng katta summali ombor birinchi.
      expect(first.sklads.first.skladName, 'Гелион МОРОЖЕНОЕ ФРЕЗЕР');
      expect(first.positions, 2);
      expect(groups.last.corrName, 'Kontragentsiz');
      expect(groups.last.corrId, 0);
    });
  });

  group('purchases (xaridlar / narx)', () {
    final j = _json('''
{"date_from":"2026-09-05","date_to":"2026-09-19","prev_from":"2026-08-21","prev_to":"2026-09-04","show_cost":true,"total_sum":556014602,
 "items":[{"corr_id":27,"corr_name":"РЫНОК","good_id":9867,"good_name":"Яйца (белок/желток) Цех (3-4)","base_unit":"g","price_unit":"kg","docs":3,
           "qty":742500,"sum":18600001,"avg_price":25051,"min_price":24242,"max_price":25455,"last_price":25455,"last_date":"2026-09-16",
           "prev_avg_price":22424,"price_change_pct":11.7},
          {"corr_id":27,"corr_name":"РЫНОК","good_id":9999,"good_name":"Coca-cola 0.5 л","base_unit":"mpcs","price_unit":"pcs","docs":2,
           "qty":480,"sum":2812000,"avg_price":5858,"min_price":5858,"max_price":5858,"last_price":5858,"last_date":"2026-09-15",
           "prev_avg_price":0,"price_change_pct":null}]}''');

    test('narx maydonlari va oldingi davr o\'qiladi', () {
      final r = CorePurchasesReport.fromJson(j);
      expect(r.prevFrom, '2026-08-21');
      expect(r.totalSum, 556014602);
      final egg = r.items.first;
      expect(egg.priceUnit, 'kg');
      expect(egg.avgPrice, 25051);
      expect(egg.lastDate, '2026-09-16');
      expect(egg.priceChangePct, 11.7);
      // Oldingi davrda xarid yo'q — `null` (0 emas).
      expect(r.items.last.priceChangePct, isNull);
      expect(r.items.last.prevAvgPrice, 0);
    });
  });

  group('production (ishlab chiqarish)', () {
    final j = _json('''
{"date_from":"2026-08-20","date_to":"2026-09-19","sklad_id":null,"show_cost":true,"total_cost":705635161,
 "items":[{"good_id":10676,"good_name":"(заказной)   Ассорти Моне Мороженое","base_unit":"mpcs","to_sklad":24,"to_sklad_name":"Гелион ЗАКАЗ","docs":52,
           "qty":948000,"cost":40243094,"unit_cost":42451,"qty_from_other":948000,"price_unit":"dona"},
          {"good_id":10677,"good_name":"Кекс","base_unit":"g","to_sklad":24,"to_sklad_name":"Гелион ЗАКАЗ","docs":5,
           "qty":10000,"cost":100000,"unit_cost":10000,"qty_from_other":0,"price_unit":"kg"}],
 "totals":[{"to_sklad":24,"to_sklad_name":"Гелион ЗАКАЗ","positions":2,"cost":40343094}]}''');

    test('qator, boshqa ombor xomashyosi va jamlar', () {
      final r = CoreProductionReport.fromJson(j);
      expect(r.totalCost, 705635161);
      expect(r.items.first.unitCost, 42451);
      expect(r.items.first.qtyFromOther, 948000);
      expect(r.items.first.fromOtherSklad, isTrue);
      expect(r.items.last.fromOtherSklad, isFalse);
      expect(r.totals.single.toSkladName, 'Гелион ЗАКАЗ');
    });
  });

  group('recipe-cost (kalkulyatsiya kartasi)', () {
    final j = _json('''
{"good_id":10676,"good_name":"(заказной)   Ассорти Моне Мороженое","base_unit":"mpcs","price_unit":"dona","date":"2026-09-19","qty":1000,
 "rule":"expand_sub","show_cost":true,"total_cost":41287,"unit_cost":41287,
 "lines":[{"good_id":10624,"good_name":"Ассорти Ириска","base_unit":"mpcs","price_unit":"dona","qty":3000,"last_price":3840,"price_date":"2026-09-17","cost":11521,"share_pct":28},
          {"good_id":10479,"good_name":"Чизкейк Малина","base_unit":"mpcs","price_unit":"dona","qty":2250,"last_price":4151,"price_date":"2026-09-19","cost":9340,"share_pct":23},
          {"good_id":10480,"good_name":"Новый п/ф","base_unit":"g","price_unit":"kg","qty":500,"last_price":0,"price_date":"","cost":0,"share_pct":0}],
 "no_price":[10480],"cut":[10481]}''');

    test('qatorlar, narxsiz ingredient va `cut`', () {
      final r = CoreRecipeCost.fromJson(j);
      expect(r.rule, 'expand_sub');
      expect(r.unitCost, 41287);
      expect(r.qty, 1000);
      expect(r.lines, hasLength(3));
      expect(r.lines.first.sharePct, 28);
      expect(r.lines.first.noPrice, isFalse);
      expect(r.lines.last.noPrice, isTrue);
      expect(r.noPrice, [10480]);
      expect(r.cut, [10481]);
    });
  });

  group('cost (tannarx / food cost)', () {
    test('food cost % hisoblanadi', () {
      final r = CoreCostReport.fromJson(_json('''
{"total_cost":300,"total_sale":1000,"total_profit":700,
 "items":[{"good_id":1,"good_name":"Tort","base_unit":"g","qty":2000,"cost":300,"unit_cost":150,"sale":1000,"sold_qty":2000,"profit":700},
          {"good_id":2,"good_name":"Sotilmagan","base_unit":"g","qty":1000,"cost":100,"unit_cost":100,"sale":0,"sold_qty":0,"profit":0}]}'''));
      expect(r.totalProfit, 700);
      expect(r.items.first.foodCostPct, 30);
      expect(r.items.last.foodCostPct, isNull);
    });
  });

  test('show_cost yo\'q bo\'lsa `true` deb olinadi (eski javob)', () {
    final r = CoreIssuesReport.fromJson(_json('{"items":[],"totals":[]}'));
    expect(r.showCost, isTrue);
  });

  test('show_cost:false — summalar 0 keladi', () {
    final r = CoreInvDiffReport.fromJson(_json(
        '{"show_cost":false,"items":[{"good_id":1,"shortage_qty":500,"shortage_sum":0}],"total":{"docs":1}}'));
    expect(r.showCost, isFalse);
    expect(r.items.first.shortageQty, 500);
    expect(r.items.first.shortageSum, 0);
  });

  // ───────────────────────── Pul ustunlari ─────────────────────────

  group('show_cost:false — pul ustunlari yashiriladi', () {
    const all = [
      CoreReportColumn('Tovar'),
      CoreReportColumn('Miqdor', numeric: true),
      CoreReportColumn('Summa', money: true, numeric: true),
      CoreReportColumn('O\'rtacha narx', money: true, numeric: true),
    ];

    test('ruxsat bor — hamma ustun', () {
      expect(coreReportColumns(all, true), hasLength(4));
    });

    test('ruxsat yo\'q — faqat pul BO\'LMAGAN ustunlar', () {
      final cols = coreReportColumns(all, false);
      expect(cols.map((c) => c.title), ['Tovar', 'Miqdor']);
      expect(cols.every((c) => !c.money), isTrue);
    });
  });

  // ───────────────────────── Davr shablonlari ─────────────────────────

  group('Davr shablonlari', () {
    // 2026-09-21 — DUSHANBA; 2026-09-23 — chorshanba.
    final wed = DateTime(2026, 9, 23, 14, 30);

    test('Bugun / Kecha', () {
      expect(CorePeriod.of(CorePeriodPreset.today, now: wed).from, '2026-09-23');
      expect(CorePeriod.of(CorePeriodPreset.today, now: wed).to, '2026-09-23');
      final y = CorePeriod.of(CorePeriodPreset.yesterday, now: wed);
      expect([y.from, y.to], ['2026-09-22', '2026-09-22']);
    });

    test('Shu hafta DUSHANBAdan boshlanadi', () {
      final w = CorePeriod.of(CorePeriodPreset.thisWeek, now: wed);
      expect(w.from, '2026-09-21'); // dushanba
      expect(w.to, '2026-09-23');
      expect(DateTime.parse(w.from).weekday, DateTime.monday);
    });

    test('Dushanba kuni hafta o\'sha kundan boshlanadi', () {
      final mon = DateTime(2026, 9, 21);
      final w = CorePeriod.of(CorePeriodPreset.thisWeek, now: mon);
      expect([w.from, w.to], ['2026-09-21', '2026-09-21']);
    });

    test('Yakshanba hali shu haftaga kiradi', () {
      final sun = DateTime(2026, 9, 27); // yakshanba
      final w = CorePeriod.of(CorePeriodPreset.thisWeek, now: sun);
      expect([w.from, w.to], ['2026-09-21', '2026-09-27']);
    });

    test('Shu oy — oy boshidan bugungacha', () {
      final m = CorePeriod.of(CorePeriodPreset.thisMonth, now: wed);
      expect([m.from, m.to], ['2026-09-01', '2026-09-23']);
    });

    test('O\'tgan oy — to\'liq oldingi oy', () {
      final m = CorePeriod.of(CorePeriodPreset.lastMonth, now: wed);
      expect([m.from, m.to], ['2026-08-01', '2026-08-31']);
    });

    test('O\'tgan oy — yanvarda dekabrga o\'tadi', () {
      final m = CorePeriod.of(CorePeriodPreset.lastMonth,
          now: DateTime(2026, 1, 15));
      expect([m.from, m.to], ['2025-12-01', '2025-12-31']);
    });

    test('O\'tgan oy — martda 28 kunli fevral', () {
      final m = CorePeriod.of(CorePeriodPreset.lastMonth,
          now: DateTime(2026, 3, 10));
      expect([m.from, m.to], ['2026-02-01', '2026-02-28']);
    });

    test('Oraliq — tanlangan chegaralar', () {
      final p = CorePeriod.range(DateTime(2026, 8, 20), DateTime(2026, 9, 19));
      expect([p.from, p.to], ['2026-08-20', '2026-09-19']);
      expect(p.preset, CorePeriodPreset.custom);
      expect(p.label, '20.08.2026 – 19.09.2026');
    });

    test('Saqlash / o\'qish (SharedPreferences matni)', () {
      final custom =
          CorePeriod.range(DateTime(2026, 8, 20), DateTime(2026, 9, 19));
      expect(custom.encode(), 'custom|2026-08-20|2026-09-19');
      expect(CorePeriod.decode(custom.encode()), custom);

      expect(CorePeriod.of(CorePeriodPreset.lastMonth).encode(), 'lastMonth');
      final back = CorePeriod.decode('lastMonth', now: wed);
      expect(back, CorePeriod.of(CorePeriodPreset.lastMonth, now: wed));

      expect(CorePeriod.decode(null), isNull);
      expect(CorePeriod.decode(''), isNull);
      expect(CorePeriod.decode('allaqachon-yo\'q'), isNull);
      expect(CorePeriod.decode('custom|buzuq'), isNull);
    });

    test('Yorliqlar o\'zbekcha', () {
      expect(CorePeriod.of(CorePeriodPreset.today).label, 'Bugun');
      expect(CorePeriod.of(CorePeriodPreset.lastMonth).label, 'O\'tgan oy');
      expect(CorePeriod.of(CorePeriodPreset.thisMonth, now: wed).fullLabel,
          'Shu oy · 01.09.2026 – 23.09.2026');
    });
  });

  // ───────────────────────── CSV fayl nomi ─────────────────────────

  group('Excel (CSV) fayl nomi', () {
    test('davrli hisobot', () {
      expect(
        coreCsvFileName('kamomad', from: '2026-08-20', to: '2026-09-19'),
        'kamomad_2026-08-20_2026-09-19.csv',
      );
    });

    test('bir kunlik hisobot — sana bir marta', () {
      expect(coreCsvFileName('qoldiq-qiymati', from: '2026-09-19'),
          'qoldiq-qiymati_2026-09-19.csv');
      expect(
        coreCsvFileName('kamomad', from: '2026-09-19', to: '2026-09-19'),
        'kamomad_2026-09-19.csv',
      );
    });

    test('qo\'shimcha (ombor/tovar nomi) tozalanadi', () {
      final n = coreCsvFileName('kalkulyatsiya',
          from: '2026-09-19', suffix: 'Чизкейк / Малина*');
      expect(n, 'kalkulyatsiya_чизкейк-малина_2026-09-19.csv');
      expect(n.contains('/'), isFalse);
      expect(n.contains('*'), isFalse);
    });

    test('takrorlansa nom oxiriga raqam qo\'shiladi', () {
      expect(coreCsvNameWithIndex('kamomad_2026-09-19.csv', 1),
          'kamomad_2026-09-19.csv');
      expect(coreCsvNameWithIndex('kamomad_2026-09-19.csv', 3),
          'kamomad_2026-09-19_3.csv');
    });

    test('Content-Disposition dan nom', () {
      expect(
        coreCsvNameFromDisposition(
            'attachment; filename="kamomad-ortiqcha_2026-08-01_2026-08-31.csv"'),
        'kamomad-ortiqcha_2026-08-01_2026-08-31.csv',
      );
      expect(coreCsvNameFromDisposition(null), '');
      expect(coreCsvNameFromDisposition('inline'), '');
    });
  });

  // ───────────────────── Narx o'zgarishi (±5 %) ─────────────────────

  group('Narx o\'zgarishi chegarasi', () {
    test('≥ +5 % — qimmatlashgan', () {
      expect(corePriceTrend(11.7), CorePriceTrend.up);
      expect(corePriceTrend(5.0), CorePriceTrend.up);
    });

    test('≤ −5 % — arzonlashgan', () {
      expect(corePriceTrend(-6.2), CorePriceTrend.down);
      expect(corePriceTrend(-5.0), CorePriceTrend.down);
    });

    test('|Δ| < 5 % — rangsiz', () {
      expect(corePriceTrend(4.9), CorePriceTrend.flat);
      expect(corePriceTrend(-4.9), CorePriceTrend.flat);
      expect(corePriceTrend(0), CorePriceTrend.flat);
    });

    test('null — solishtirib bo\'lmaydi', () {
      expect(corePriceTrend(null), CorePriceTrend.unknown);
      expect(corePriceTrendText(null), '—');
    });

    test('matn: ▲ / ▼ va vergulli foiz', () {
      expect(corePriceTrendText(11.7), '▲ 11,7 %');
      expect(corePriceTrendText(-6.25), '▼ 6,3 %');
      expect(corePriceTrendText(1.5), '1,5 %');
    });
  });

  // ───────────────────────── Xato matni ─────────────────────────

  group('Server xatosi — o\'zbekcha matn', () {
    test('404/405 — eski binar', () {
      expect(coreReportErrorText(const CoreApiException('not found', status: 404)),
          'Server yangilanmagan — administratorga ayting');
      expect(coreReportErrorText(const CoreApiException('', status: 405)),
          'Server yangilanmagan — administratorga ayting');
    });

    test('403 — ruxsat', () {
      expect(
        coreReportErrorText(const CoreApiException('ruxsat yo\'q',
            status: 403, code: 'forbidden', perm: 'report.view')),
        'Ruxsat yo\'q (ruxsat: report.view)',
      );
      expect(coreReportErrorText(const CoreApiException('x', status: 403)),
          contains('report.view'));
    });

    test('boshqa xato — server matni', () {
      expect(
          coreReportErrorText(
              const CoreApiException('date_from > date_to', status: 422)),
          'date_from > date_to');
    });
  });
}
