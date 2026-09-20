// core2/models/core_report2.dart — mone_core `/api/v2` YANGI hisobotlari
// (CORE_DEBT_KONTRAKT.md §5): kamomad/ortiqcha (`/reports/inventory-diff`),
// spisaniye sabab kesimida (`/reports/issues`), xaridlar va narx tarixi
// (`/reports/purchases`), ishlab chiqarish (`/reports/production`),
// kalkulyatsiya kartasi (`/reports/recipe-cost`) hamda mavjud tannarx
// hisoboti (`/reports/cost`).
//
// Qoidalar (kontrakt): miqdor — BUTUN base birlik (g/ml/mpcs/mm, ko'rsatish
// = /1000), pul — butun so'm; narxlar (`*_price`, `unit_cost`) 1 KO'RSATISH
// birligi uchun (`price_unit`); `show_cost:false` bo'lsa summalar 0 keladi va
// UI pul ustunlarini yashiradi.
//
// Eski hisobot qatorlari (turnover/deficit/sh5-compare) — `core_report.dart`.

/// `show_cost` maydonini o'qish: yo'q bo'lsa `true` (eski javoblar).
bool _showCost(Map<String, dynamic> j) =>
    j['show_cost'] is bool ? j['show_cost'] as bool : true;

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
String _s(dynamic v) => (v ?? '').toString();
String _day(dynamic v) => _s(v).split('T').first;

List<Map<String, dynamic>> _list(dynamic raw) => raw is List
    ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

List<int> _ids(dynamic raw) =>
    raw is List ? raw.whereType<num>().map((e) => e.toInt()).toList() : const [];

// ───────── 5a. Kamomad / ortiqcha — `/reports/inventory-diff` ─────────

/// Ombor × tovar qatori: kamomad (shortage) va ortiqcha (surplus) miqdori va
/// summasi; `net = surplus − shortage` (manfiy = kamomad).
class CoreInvDiffRow {
  final int skladId;
  final String skladName;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int docs;
  final int shortageQty;
  final int surplusQty;
  final int netQty;
  final int shortageSum;
  final int surplusSum;
  final int netSum;

  const CoreInvDiffRow({
    this.skladId = 0,
    this.skladName = '',
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.docs = 0,
    this.shortageQty = 0,
    this.surplusQty = 0,
    this.netQty = 0,
    this.shortageSum = 0,
    this.surplusSum = 0,
    this.netSum = 0,
  });

  factory CoreInvDiffRow.fromJson(Map<String, dynamic> j) => CoreInvDiffRow(
        skladId: _i(j['sklad_id']),
        skladName: _s(j['sklad_name']),
        goodId: _i(j['good_id']),
        goodName: _s(j['good_name']),
        baseUnit: j['base_unit'] == null ? 'pcs' : _s(j['base_unit']),
        docs: _i(j['docs']),
        shortageQty: _i(j['shortage_qty']),
        surplusQty: _i(j['surplus_qty']),
        netQty: _i(j['net_qty']),
        shortageSum: _i(j['shortage_sum']),
        surplusSum: _i(j['surplus_sum']),
        netSum: _i(j['net_sum']),
      );
}

/// Jamlangan qator: ombor bo'yicha (`by_sklad`), oy bo'yicha (`by_month`,
/// ichida `sklads`) yoki umumiy (`total`).
class CoreInvDiffGroup {
  final String month; // faqat `by_month` da: «2026-08»
  final int skladId;
  final String skladName;
  final int docs;
  final int shortageSum;
  final int surplusSum;
  final int netSum;
  final int docsNegativeSum;
  final int docsPositiveSum;
  final List<CoreInvDiffGroup> sklads;

  const CoreInvDiffGroup({
    this.month = '',
    this.skladId = 0,
    this.skladName = '',
    this.docs = 0,
    this.shortageSum = 0,
    this.surplusSum = 0,
    this.netSum = 0,
    this.docsNegativeSum = 0,
    this.docsPositiveSum = 0,
    this.sklads = const [],
  });

  factory CoreInvDiffGroup.fromJson(Map<String, dynamic> j) => CoreInvDiffGroup(
        month: _s(j['month']),
        skladId: _i(j['sklad_id']),
        skladName: _s(j['sklad_name']),
        docs: _i(j['docs']),
        shortageSum: _i(j['shortage_sum']),
        surplusSum: _i(j['surplus_sum']),
        netSum: _i(j['net_sum']),
        docsNegativeSum: _i(j['docs_negative_sum']),
        docsPositiveSum: _i(j['docs_positive_sum']),
        sklads: _list(j['sklads']).map(CoreInvDiffGroup.fromJson).toList(),
      );
}

class CoreInvDiffReport {
  final String dateFrom;
  final String dateTo;
  final int? skladId;
  final int? groupId;
  final bool showCost;
  final List<CoreInvDiffRow> items;
  final List<CoreInvDiffGroup> bySklad;
  final List<CoreInvDiffGroup> byMonth;
  final CoreInvDiffGroup total;

  const CoreInvDiffReport({
    this.dateFrom = '',
    this.dateTo = '',
    this.skladId,
    this.groupId,
    this.showCost = true,
    this.items = const [],
    this.bySklad = const [],
    this.byMonth = const [],
    this.total = const CoreInvDiffGroup(),
  });

  factory CoreInvDiffReport.fromJson(Map<String, dynamic> j) =>
      CoreInvDiffReport(
        dateFrom: _day(j['date_from']),
        dateTo: _day(j['date_to']),
        skladId: (j['sklad_id'] as num?)?.toInt(),
        groupId: (j['group_id'] as num?)?.toInt(),
        showCost: _showCost(j),
        items: _list(j['items']).map(CoreInvDiffRow.fromJson).toList(),
        bySklad: _list(j['by_sklad']).map(CoreInvDiffGroup.fromJson).toList(),
        byMonth: _list(j['by_month']).map(CoreInvDiffGroup.fromJson).toList(),
        total: j['total'] is Map
            ? CoreInvDiffGroup.fromJson(
                Map<String, dynamic>.from(j['total'] as Map))
            : const CoreInvDiffGroup(),
      );
}

// ───────── 5b. Hisobdan chiqarish (spisaniye) — `/reports/issues` ─────────

/// Sabab (kontragent) × ombor × tovar qatori.
class CoreIssueRow {
  final int corrId;
  final String corrName;
  final String corrKind;
  final int skladId;
  final String skladName;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int docs;
  final int qty;
  final int cost;

  const CoreIssueRow({
    this.corrId = 0,
    this.corrName = '',
    this.corrKind = '',
    this.skladId = 0,
    this.skladName = '',
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.docs = 0,
    this.qty = 0,
    this.cost = 0,
  });

  factory CoreIssueRow.fromJson(Map<String, dynamic> j) => CoreIssueRow(
        corrId: _i(j['corr_id']),
        corrName: _s(j['corr_name']),
        corrKind: _s(j['corr_kind']),
        skladId: _i(j['sklad_id']),
        skladName: _s(j['sklad_name']),
        goodId: _i(j['good_id']),
        goodName: _s(j['good_name']),
        baseUnit: j['base_unit'] == null ? 'pcs' : _s(j['base_unit']),
        docs: _i(j['docs']),
        qty: _i(j['qty']),
        cost: _i(j['cost']),
      );

  /// Kontragentsiz hujjatlar (`corr_id: 0`).
  bool get noCorr => corrId == 0;
}

/// Sabab × ombor yig'masi (`totals`).
class CoreIssueTotal {
  final int corrId;
  final String corrName;
  final int skladId;
  final String skladName;
  final int positions;
  final int cost;

  const CoreIssueTotal({
    this.corrId = 0,
    this.corrName = '',
    this.skladId = 0,
    this.skladName = '',
    this.positions = 0,
    this.cost = 0,
  });

  factory CoreIssueTotal.fromJson(Map<String, dynamic> j) => CoreIssueTotal(
        corrId: _i(j['corr_id']),
        corrName: _s(j['corr_name']),
        skladId: _i(j['sklad_id']),
        skladName: _s(j['sklad_name']),
        positions: _i(j['positions']),
        cost: _i(j['cost']),
      );
}

class CoreIssuesReport {
  final String dateFrom;
  final String dateTo;
  final int? skladId;
  final int? corrId;
  final bool showCost;
  final int totalCost;
  final List<CoreIssueRow> items;
  final List<CoreIssueTotal> totals;

  const CoreIssuesReport({
    this.dateFrom = '',
    this.dateTo = '',
    this.skladId,
    this.corrId,
    this.showCost = true,
    this.totalCost = 0,
    this.items = const [],
    this.totals = const [],
  });

  factory CoreIssuesReport.fromJson(Map<String, dynamic> j) => CoreIssuesReport(
        dateFrom: _day(j['date_from']),
        dateTo: _day(j['date_to']),
        skladId: (j['sklad_id'] as num?)?.toInt(),
        corrId: (j['corr_id'] as num?)?.toInt(),
        showCost: _showCost(j),
        totalCost: _i(j['total_cost']),
        items: _list(j['items']).map(CoreIssueRow.fromJson).toList(),
        totals: _list(j['totals']).map(CoreIssueTotal.fromJson).toList(),
      );
}

// ───────── 5c. Xaridlar / narx tarixi — `/reports/purchases` ─────────

/// Yetkazuvchi × tovar: miqdor, summa, o'rtacha/eng past/eng yuqori/oxirgi
/// narx (1 `price_unit` uchun) va oldingi davrga nisbatan o'zgarish %.
class CorePurchaseRow {
  final int corrId;
  final String corrName;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final String priceUnit;
  final int docs;
  final int qty;
  final int sum;
  final int avgPrice;
  final int minPrice;
  final int maxPrice;
  final int lastPrice;
  final String lastDate;
  final int prevAvgPrice;

  /// `null` — oldingi davrda xarid bo'lmagan (solishtirish yo'q).
  final double? priceChangePct;

  const CorePurchaseRow({
    this.corrId = 0,
    this.corrName = '',
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.priceUnit = '',
    this.docs = 0,
    this.qty = 0,
    this.sum = 0,
    this.avgPrice = 0,
    this.minPrice = 0,
    this.maxPrice = 0,
    this.lastPrice = 0,
    this.lastDate = '',
    this.prevAvgPrice = 0,
    this.priceChangePct,
  });

  factory CorePurchaseRow.fromJson(Map<String, dynamic> j) {
    final base = j['base_unit'] == null ? 'pcs' : _s(j['base_unit']);
    return CorePurchaseRow(
      corrId: _i(j['corr_id']),
      corrName: _s(j['corr_name']),
      goodId: _i(j['good_id']),
      goodName: _s(j['good_name']),
      baseUnit: base,
      priceUnit: j['price_unit'] == null ? base : _s(j['price_unit']),
      docs: _i(j['docs']),
      qty: _i(j['qty']),
      sum: _i(j['sum']),
      avgPrice: _i(j['avg_price']),
      minPrice: _i(j['min_price']),
      maxPrice: _i(j['max_price']),
      lastPrice: _i(j['last_price']),
      lastDate: _day(j['last_date']),
      prevAvgPrice: _i(j['prev_avg_price']),
      priceChangePct: (j['price_change_pct'] as num?)?.toDouble(),
    );
  }
}

class CorePurchasesReport {
  final String dateFrom;
  final String dateTo;
  final String prevFrom;
  final String prevTo;
  final bool showCost;
  final int totalSum;
  final List<CorePurchaseRow> items;

  const CorePurchasesReport({
    this.dateFrom = '',
    this.dateTo = '',
    this.prevFrom = '',
    this.prevTo = '',
    this.showCost = true,
    this.totalSum = 0,
    this.items = const [],
  });

  factory CorePurchasesReport.fromJson(Map<String, dynamic> j) =>
      CorePurchasesReport(
        dateFrom: _day(j['date_from']),
        dateTo: _day(j['date_to']),
        prevFrom: _day(j['prev_from']),
        prevTo: _day(j['prev_to']),
        showCost: _showCost(j),
        totalSum: _i(j['total_sum']),
        items: _list(j['items']).map(CorePurchaseRow.fromJson).toList(),
      );
}

// ───────── 5d. Ishlab chiqarish — `/reports/production` ─────────

/// Mahsulot × qabul qiluvchi ombor: miqdor, ingredient tannarxi, 1 birlik
/// tannarxi; `qtyFromOther` — xomashyosi BOSHQA ombordan yechilgan miqdor.
class CoreProductionRow {
  final int goodId;
  final String goodName;
  final String baseUnit;
  final String priceUnit;
  final int toSklad;
  final String toSkladName;
  final int docs;
  final int qty;
  final int cost;
  final int unitCost;
  final int qtyFromOther;

  const CoreProductionRow({
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.priceUnit = '',
    this.toSklad = 0,
    this.toSkladName = '',
    this.docs = 0,
    this.qty = 0,
    this.cost = 0,
    this.unitCost = 0,
    this.qtyFromOther = 0,
  });

  factory CoreProductionRow.fromJson(Map<String, dynamic> j) {
    final base = j['base_unit'] == null ? 'pcs' : _s(j['base_unit']);
    return CoreProductionRow(
      goodId: _i(j['good_id']),
      goodName: _s(j['good_name']),
      baseUnit: base,
      priceUnit: j['price_unit'] == null ? base : _s(j['price_unit']),
      toSklad: _i(j['to_sklad']),
      toSkladName: _s(j['to_sklad_name']),
      docs: _i(j['docs']),
      qty: _i(j['qty']),
      cost: _i(j['cost']),
      unitCost: _i(j['unit_cost']),
      qtyFromOther: _i(j['qty_from_other']),
    );
  }

  /// Xomashyo boshqa ombordan kelganmi (ЦЕХ → МАГАЗИН oqimi).
  bool get fromOtherSklad => qtyFromOther > 0;
}

class CoreProductionTotal {
  final int toSklad;
  final String toSkladName;
  final int positions;
  final int cost;

  const CoreProductionTotal({
    this.toSklad = 0,
    this.toSkladName = '',
    this.positions = 0,
    this.cost = 0,
  });

  factory CoreProductionTotal.fromJson(Map<String, dynamic> j) =>
      CoreProductionTotal(
        toSklad: _i(j['to_sklad']),
        toSkladName: _s(j['to_sklad_name']),
        positions: _i(j['positions']),
        cost: _i(j['cost']),
      );
}

class CoreProductionReport {
  final String dateFrom;
  final String dateTo;
  final int? skladId;
  final bool showCost;
  final int totalCost;
  final List<CoreProductionRow> items;
  final List<CoreProductionTotal> totals;

  const CoreProductionReport({
    this.dateFrom = '',
    this.dateTo = '',
    this.skladId,
    this.showCost = true,
    this.totalCost = 0,
    this.items = const [],
    this.totals = const [],
  });

  factory CoreProductionReport.fromJson(Map<String, dynamic> j) =>
      CoreProductionReport(
        dateFrom: _day(j['date_from']),
        dateTo: _day(j['date_to']),
        skladId: (j['sklad_id'] as num?)?.toInt(),
        showCost: _showCost(j),
        totalCost: _i(j['total_cost']),
        items: _list(j['items']).map(CoreProductionRow.fromJson).toList(),
        totals: _list(j['totals']).map(CoreProductionTotal.fromJson).toList(),
      );
}

// ───────── 5e. Kalkulyatsiya kartasi — `/reports/recipe-cost` ─────────

/// Retsept qatori: ingredient miqdori (base), oxirgi narx (1 `price_unit`),
/// qator summasi va ulushi. `priceDate` bo'sh — narx topilmadi (`cost: 0`).
class CoreRecipeCostLine {
  final int goodId;
  final String goodName;
  final String baseUnit;
  final String priceUnit;
  final int qty;
  final int lastPrice;
  final String priceDate;
  final int cost;
  final double sharePct;

  const CoreRecipeCostLine({
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.priceUnit = '',
    this.qty = 0,
    this.lastPrice = 0,
    this.priceDate = '',
    this.cost = 0,
    this.sharePct = 0,
  });

  factory CoreRecipeCostLine.fromJson(Map<String, dynamic> j) {
    final base = j['base_unit'] == null ? 'pcs' : _s(j['base_unit']);
    return CoreRecipeCostLine(
      goodId: _i(j['good_id']),
      goodName: _s(j['good_name']),
      baseUnit: base,
      priceUnit: j['price_unit'] == null ? base : _s(j['price_unit']),
      qty: _i(j['qty']),
      lastPrice: _i(j['last_price']),
      priceDate: _day(j['price_date']),
      cost: _i(j['cost']),
      sharePct: (j['share_pct'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Narx topilmagan ingredient (UI sariq belgi qo'yadi).
  bool get noPrice => priceDate.isEmpty || lastPrice == 0;
}

class CoreRecipeCost {
  final int goodId;
  final String goodName;
  final String baseUnit;
  final String priceUnit;
  final String date;
  final int qty; // base birlikda (default 1000 = 1 dona/kg)
  final String rule;
  final bool showCost;
  final int totalCost;
  final int unitCost;
  final List<CoreRecipeCostLine> lines;
  final List<int> noPrice;
  final List<int> cut; // sikl tufayli yoyilmagan p/f lar

  const CoreRecipeCost({
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.priceUnit = '',
    this.date = '',
    this.qty = 1000,
    this.rule = '',
    this.showCost = true,
    this.totalCost = 0,
    this.unitCost = 0,
    this.lines = const [],
    this.noPrice = const [],
    this.cut = const [],
  });

  factory CoreRecipeCost.fromJson(Map<String, dynamic> j) {
    final base = j['base_unit'] == null ? 'pcs' : _s(j['base_unit']);
    return CoreRecipeCost(
      goodId: _i(j['good_id']),
      goodName: _s(j['good_name']),
      baseUnit: base,
      priceUnit: j['price_unit'] == null ? base : _s(j['price_unit']),
      date: _day(j['date']),
      qty: j['qty'] == null ? 1000 : _i(j['qty']),
      rule: _s(j['rule']),
      showCost: _showCost(j),
      totalCost: _i(j['total_cost']),
      unitCost: _i(j['unit_cost']),
      lines: _list(j['lines']).map(CoreRecipeCostLine.fromJson).toList(),
      noPrice: _ids(j['no_price']),
      cut: _ids(j['cut']),
    );
  }
}

// ───────── Tannarx / food cost — `/reports/cost` (mavjud hisobot) ─────────

/// Taom qatori: `act` flag=0 miqdori va ingredient tannarxi, sotuv summasi.
class CoreCostRow {
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int qty;
  final int cost;
  final int unitCost;
  final int sale;
  final int soldQty;
  final int profit;

  const CoreCostRow({
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.qty = 0,
    this.cost = 0,
    this.unitCost = 0,
    this.sale = 0,
    this.soldQty = 0,
    this.profit = 0,
  });

  factory CoreCostRow.fromJson(Map<String, dynamic> j) => CoreCostRow(
        goodId: _i(j['good_id']),
        goodName: _s(j['good_name']),
        baseUnit: j['base_unit'] == null ? 'pcs' : _s(j['base_unit']),
        qty: _i(j['qty']),
        cost: _i(j['cost']),
        unitCost: _i(j['unit_cost']),
        sale: _i(j['sale']),
        soldQty: _i(j['sold_qty']),
        profit: _i(j['profit']),
      );

  /// Food cost % = tannarx / sotuv × 100 (sotuv 0 bo'lsa null).
  double? get foodCostPct => sale <= 0 ? null : cost / sale * 100;
}

class CoreCostReport {
  final String dateFrom;
  final String dateTo;
  final bool showCost;
  final int totalCost;
  final int totalSale;
  final int totalProfit;
  final List<CoreCostRow> items;

  const CoreCostReport({
    this.dateFrom = '',
    this.dateTo = '',
    this.showCost = true,
    this.totalCost = 0,
    this.totalSale = 0,
    this.totalProfit = 0,
    this.items = const [],
  });

  factory CoreCostReport.fromJson(Map<String, dynamic> j) => CoreCostReport(
        dateFrom: _day(j['date_from']),
        dateTo: _day(j['date_to']),
        showCost: _showCost(j),
        totalCost: _i(j['total_cost']),
        totalSale: _i(j['total_sale']),
        totalProfit: _i(j['total_profit']),
        items: _list(j['items']).map(CoreCostRow.fromJson).toList(),
      );
}
