// core2/models/core_stock.dart — mone_core qoldiq modellari: CoreStockRow
// (/stock: qty butun base, qty_lots/deficit (partiyasiz yechim), cost/
// last_price faqat stock.cost.view bo'lsa keladi — yo'q bo'lsa null),
// CoreStockSummary (/stock/summary),
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
//
// CoreBatch (/batches — FIFO partiyalar), CoreStockCard + CoreCardEntry
// (/stock/card — {open_qty, close_qty, rows[]} ledger yozuvlari balans bilan).

class CoreStockRow {
  final int skladId;
  final int goodId;
  final String goodName;
  final String baseUnit;
  final int qty;
  // Partiyalardagi miqdor (soft rejimda SH5 ko'rsatadigan qoldiq = qty + deficit).
  final int qtyLots;
  // Partiyasiz yechilgan (qoplanmagan) miqdor — ledger.StockRow `deficit`.
  // Hozir api/stock.go DTO'si bu ikki maydonni tashlab yuboradi → 0.
  final int deficit;
  final int? cost; // qoldiq qiymati (butun so'm) — ruxsat bo'lsa
  final int? lastPrice; // oxirgi kirim narxi (1 base birlik) — ruxsat bo'lsa
  final int minQty;

  const CoreStockRow({
    required this.skladId,
    required this.goodId,
    this.goodName = '',
    this.baseUnit = 'pcs',
    this.qty = 0,
    this.qtyLots = 0,
    this.deficit = 0,
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
        qtyLots: (j['qty_lots'] as num?)?.toInt() ?? 0,
        deficit: (j['deficit'] as num?)?.toInt() ?? 0,
        cost: (j['cost'] as num?)?.toInt(),
        lastPrice: (j['last_price'] as num?)?.toInt(),
        minQty: (j['min_qty'] as num?)?.toInt() ?? 0,
      );

  /// Qoldiq keshidagi qatordan tovar kartochkasi (kesh uchun) — TO'LIQ EMAS
  /// (`partial: true`): bu javobda `is_complect`/`units` yo'q, kerak bo'lganda
  /// `/goods/{id}` bilan to'ldiriladi (CoreDictProvider.ensureGoods).
  CoreGood toGood() => CoreGood(
      id: goodId, name: goodName, baseUnit: baseUnit, partial: true);

  bool get negative => qty < 0;
  bool get hasDeficit => deficit != 0;
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
        // Server float64 beradi (faqat shu maydon) — ko'rsatish uchun yaxlitlab.
        unitCost: (j['unit_cost'] as num?)?.round() ?? 0,
        receivedAt: (j['received_at'] ?? '').toString(),
      );
}

/// `/stock/card` qatori (ledger yozuvi, yig'ma balans bilan).
class CoreCardEntry {
  final int id;
  final int docId;
  final String docType;
  final String docNumber;
  final String docDate;
  final String corr;
  final String fromSklad;
  final String toSklad;
  final int qtyDelta;
  final int? costDelta; // faqat stock.cost.view
  final int? batchId; // null — partiyasiz (defitsit) chiqim
  final int balance;
  final String postedAt;

  const CoreCardEntry({
    this.id = 0,
    this.docId = 0,
    this.docType = '',
    this.docNumber = '',
    this.docDate = '',
    this.corr = '',
    this.fromSklad = '',
    this.toSklad = '',
    this.qtyDelta = 0,
    this.costDelta,
    this.batchId,
    this.balance = 0,
    this.postedAt = '',
  });

  factory CoreCardEntry.fromJson(Map<String, dynamic> j) => CoreCardEntry(
        id: (j['id'] as num?)?.toInt() ?? 0,
        docId: (j['doc_id'] as num?)?.toInt() ?? 0,
        docType: (j['doc_type'] ?? '').toString(),
        docNumber: (j['doc_number'] ?? '').toString(),
        docDate: (j['doc_date'] ?? '').toString().split('T').first,
        corr: (j['corr'] ?? '').toString(),
        fromSklad: (j['from_sklad'] ?? '').toString(),
        toSklad: (j['to_sklad'] ?? '').toString(),
        qtyDelta: (j['qty_delta'] as num?)?.toInt() ?? 0,
        costDelta: (j['cost_delta'] as num?)?.toInt(),
        batchId: (j['batch_id'] as num?)?.toInt(),
        balance: (j['balance'] as num?)?.toInt() ?? 0,
        postedAt: (j['posted_at'] ?? '').toString(),
      );
}

/// `GET /stock/card` javobi: `{sklad_id, good_id, open_qty, open_cost,
/// close_qty, rows[]}`.
class CoreStockCard {
  final int skladId;
  final int goodId;
  final int openQty;
  final int openCost;
  final int closeQty;
  final List<CoreCardEntry> rows;

  const CoreStockCard({
    required this.skladId,
    required this.goodId,
    this.openQty = 0,
    this.openCost = 0,
    this.closeQty = 0,
    this.rows = const [],
  });

  factory CoreStockCard.fromJson(Map<String, dynamic> j) => CoreStockCard(
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        openQty: (j['open_qty'] as num?)?.toInt() ?? 0,
        openCost: (j['open_cost'] as num?)?.toInt() ?? 0,
        closeQty: (j['close_qty'] as num?)?.toInt() ?? 0,
        rows: (j['rows'] as List?)
                ?.whereType<Map>()
                .map((e) => CoreCardEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );
}
