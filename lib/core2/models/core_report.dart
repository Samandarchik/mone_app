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
