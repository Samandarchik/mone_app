// core2/models/core_report.dart — mone_core hisobot qatorlari:
// CoreTurnoverRow (/reports/turnover — ochilish/kirim/chiqim/yopilish,
// miqdor butun base + qiymat butun so'm), CoreDeficitRow (/reports/deficit —
// partiyasiz chiqimlar, ombor×tovar jamlangan). Hisobot javoblari obyekt:
// `{"items":[…], "date_from", "date_to", "total_cost"…}` — servis `items`
// ni oladi. Stock-value uchun CoreStockSummary (core_stock.dart).

class CoreTurnoverRow {
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int openQty;
  final int inQty;
  final int outQty;
  final int closeQty;
  final int openCost;
  final int inCost;
  final int outCost;
  final int closeCost;

  const CoreTurnoverRow({
    required this.goodId,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.openQty = 0,
    this.inQty = 0,
    this.outQty = 0,
    this.closeQty = 0,
    this.openCost = 0,
    this.inCost = 0,
    this.outCost = 0,
    this.closeCost = 0,
  });

  factory CoreTurnoverRow.fromJson(Map<String, dynamic> j) => CoreTurnoverRow(
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        baseUnit: (j['base_unit'] ?? 'pcs').toString(),
        openQty: (j['open_qty'] as num?)?.toInt() ?? 0,
        inQty: (j['in_qty'] as num?)?.toInt() ?? 0,
        outQty: (j['out_qty'] as num?)?.toInt() ?? 0,
        closeQty: (j['close_qty'] as num?)?.toInt() ?? 0,
        openCost: (j['open_cost'] as num?)?.toInt() ?? 0,
        inCost: (j['in_cost'] as num?)?.toInt() ?? 0,
        outCost: (j['out_cost'] as num?)?.toInt() ?? 0,
        closeCost: (j['close_cost'] as num?)?.toInt() ?? 0,
      );
}

/// `/reports/deficit` qatori — ombor×tovar bo'yicha jamlangan partiyasiz
/// (batch_id IS NULL) chiqimlar: qty (manfiy), cost, hujjatlar soni, davr.
class CoreDeficitRow {
  final int skladId;
  final String skladName;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int qty;
  final int cost;
  final int docs;
  final String firstDate;
  final String lastDate;

  const CoreDeficitRow({
    this.skladId = 0,
    this.skladName = '',
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.qty = 0,
    this.cost = 0,
    this.docs = 0,
    this.firstDate = '',
    this.lastDate = '',
  });

  factory CoreDeficitRow.fromJson(Map<String, dynamic> j) => CoreDeficitRow(
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
        skladName: (j['sklad_name'] ?? '').toString(),
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        baseUnit: (j['base_unit'] ?? 'pcs').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        cost: (j['cost'] as num?)?.toInt() ?? 0,
        docs: (j['docs'] as num?)?.toInt() ?? 0,
        firstDate: (j['first_date'] ?? '').toString().split('T').first,
        lastDate: (j['last_date'] ?? '').toString().split('T').first,
      );
}

// ───────── SH5 ↔ yadro solishtiruv (`GET /reports/sh5-compare?date=`) ─────────
// Javob: {date, rows, diff_rows, diff_pct, top:[{sklad, good, sh5, core,
// diff, sum}], docs:[{type, sh5, core}]}. `sklad`/`good` nom (matn) yoki id
// (son) bo'lishi mumkin — ikkalasi ham qabul qilinadi. Miqdorlar BUTUN base
// birlikda (g/ml/mpcs), pul — butun so'm.

/// Eng katta farq qatori: ombor × tovar, SH5 va yadro miqdori.
class CoreSh5DiffRow {
  final int skladId;
  final String skladName;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int sh5;
  final int core;
  final int diff;
  final int sum; // farqning so'mdagi qiymati

  const CoreSh5DiffRow({
    this.skladId = 0,
    this.skladName = '',
    this.goodId = 0,
    this.goodName = '',
    this.baseUnit = '',
    this.sh5 = 0,
    this.core = 0,
    this.diff = 0,
    this.sum = 0,
  });

  factory CoreSh5DiffRow.fromJson(Map<String, dynamic> j) {
    final sklad = j['sklad'];
    final good = j['good'];
    final sh5 = (j['sh5'] as num?)?.toInt() ?? 0;
    final core = (j['core'] as num?)?.toInt() ?? 0;
    return CoreSh5DiffRow(
      skladId: (j['sklad_id'] as num?)?.toInt() ??
          (sklad is num ? sklad.toInt() : 0),
      skladName: (j['sklad_name'] ?? (sklad is String ? sklad : '')).toString(),
      goodId:
          (j['good_id'] as num?)?.toInt() ?? (good is num ? good.toInt() : 0),
      goodName: (j['good_name'] ?? (good is String ? good : '')).toString(),
      baseUnit: (j['base_unit'] ?? '').toString(),
      sh5: sh5,
      core: core,
      diff: (j['diff'] as num?)?.toInt() ?? (core - sh5),
      sum: (j['sum'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Hujjat sonlari tur bo'yicha: SH5 da nechta, yadroda nechta.
class CoreSh5DocCount {
  final String type;
  final int sh5;
  final int core;

  const CoreSh5DocCount({this.type = '', this.sh5 = 0, this.core = 0});

  factory CoreSh5DocCount.fromJson(Map<String, dynamic> j) => CoreSh5DocCount(
        type: (j['type'] ?? '').toString(),
        sh5: (j['sh5'] as num?)?.toInt() ?? 0,
        core: (j['core'] as num?)?.toInt() ?? 0,
      );

  int get diff => core - sh5;
}

/// Bir kunlik solishtiruv natijasi.
class CoreSh5Compare {
  final String date;
  final int rows; // solishtirilgan ombor×tovar qatorlari
  final int diffRows; // farq chiqqanlari
  final double diffPct;
  final String computedAt; // hisoblangan vaqt (bo'lsa)
  final List<CoreSh5DiffRow> top;
  final List<CoreSh5DocCount> docs;

  const CoreSh5Compare({
    this.date = '',
    this.rows = 0,
    this.diffRows = 0,
    this.diffPct = 0,
    this.computedAt = '',
    this.top = const [],
    this.docs = const [],
  });

  factory CoreSh5Compare.fromJson(Map<String, dynamic> j) => CoreSh5Compare(
        date: (j['date'] ?? '').toString().split('T').first,
        rows: (j['rows'] as num?)?.toInt() ?? 0,
        diffRows: (j['diff_rows'] as num?)?.toInt() ?? 0,
        diffPct: (j['diff_pct'] as num?)?.toDouble() ?? 0,
        computedAt: (j['computed_at'] ?? j['at'] ?? '').toString(),
        top: (j['top'] as List?)
                ?.whereType<Map>()
                .map((e) => CoreSh5DiffRow.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        docs: (j['docs'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreSh5DocCount.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  /// Farq summasi (eng katta farqlar bo'yicha) — xulosa qatorida.
  int get topSum => top.fold(0, (s, r) => s + r.sum.abs());
}
