// core2/models/core_stock.dart — mone_core qoldiq modellari: CoreStockRow
// (/stock: qty butun base, cost/last_price faqat stock.cost.view bo'lsa
// keladi — yo'q bo'lsa null), CoreStockSummary (/stock/summary),
// CoreBatch (/batches — FIFO partiyalar), CoreCardEntry (/stock/card —
// ledger yozuvlari balans bilan).

class CoreStockRow {
  final int skladId;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int qty;
  final int? cost; // qoldiq qiymati (butun so'm) — ruxsat bo'lsa
  final int? lastPrice; // oxirgi kirim narxi (1 base birlik) — ruxsat bo'lsa
  final int minQty;

  const CoreStockRow({
    required this.skladId,
    required this.goodId,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.qty = 0,
    this.cost,
    this.lastPrice,
    this.minQty = 0,
  });

  factory CoreStockRow.fromJson(Map<String, dynamic> j) => CoreStockRow(
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        baseUnit: (j['base_unit'] ?? 'pcs').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        cost: (j['cost'] as num?)?.toInt(),
        lastPrice: (j['last_price'] as num?)?.toInt(),
        minQty: (j['min_qty'] as num?)?.toInt() ?? 0,
      );

  bool get negative => qty < 0;
  bool get low => minQty > 0 && qty < minQty;
}

class CoreStockSummary {
  final int skladId;
  final String name;
  final int positions;
  final int qtyNegative;
  final int? cost;

  const CoreStockSummary({
    required this.skladId,
    this.name = '',
    this.positions = 0,
    this.qtyNegative = 0,
    this.cost,
  });

  factory CoreStockSummary.fromJson(Map<String, dynamic> j) =>
      CoreStockSummary(
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        positions: (j['positions'] as num?)?.toInt() ?? 0,
        qtyNegative: (j['qty_negative'] as num?)?.toInt() ?? 0,
        cost: (j['cost'] as num?)?.toInt(),
      );
}

class CoreBatch {
  final int id;
  final int docId;
  final int qtyIn;
  final int qtyLeft;
  final int unitCost; // 1 base birlik narxi (butun so'm)
  final String receivedAt;

  const CoreBatch({
    required this.id,
    this.docId = 0,
    this.qtyIn = 0,
    this.qtyLeft = 0,
    this.unitCost = 0,
    this.receivedAt = '',
  });

  factory CoreBatch.fromJson(Map<String, dynamic> j) => CoreBatch(
        id: (j['id'] as num?)?.toInt() ?? 0,
        docId: (j['doc_id'] as num?)?.toInt() ?? 0,
        qtyIn: (j['qty_in'] as num?)?.toInt() ?? 0,
        qtyLeft: (j['qty_left'] as num?)?.toInt() ?? 0,
        unitCost: (j['unit_cost'] as num?)?.toInt() ?? 0,
        receivedAt: (j['received_at'] ?? '').toString(),
      );
}

class CoreCardEntry {
  final int docId;
  final String docType;
  final String docDate;
  final int qtyDelta;
  final int costDelta;
  final int balance;

  const CoreCardEntry({
    this.docId = 0,
    this.docType = '',
    this.docDate = '',
    this.qtyDelta = 0,
    this.costDelta = 0,
    this.balance = 0,
  });

  factory CoreCardEntry.fromJson(Map<String, dynamic> j) => CoreCardEntry(
        docId: (j['doc_id'] as num?)?.toInt() ?? 0,
        docType: (j['doc_type'] ?? '').toString(),
        docDate: (j['doc_date'] ?? '').toString().split('T').first,
        qtyDelta: (j['qty_delta'] as num?)?.toInt() ?? 0,
        costDelta: (j['cost_delta'] as num?)?.toInt() ?? 0,
        balance: (j['balance'] as num?)?.toInt() ?? 0,
      );
}
