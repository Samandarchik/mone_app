// core2/models/core_doc.dart — mone_core hujjati (CoreDoc) va qatori
// (CoreDocLine), tur/holat konstantalari (CoreDocType/CoreDocStatus),
// post javobidagi ogohlantirish (CoreDocWarning), qoldiq-keyin (stock_after)
// va ro'yxat javobi (CoreDocPage). qty — butun base birlik, price/amount —
// butun so'm. JSON snake_case, API_V2.md «Hujjatlar» bo'limi bilan 1:1.

abstract final class CoreDocType {
  static const String receipt = 'receipt';
  static const String issue = 'issue';
  static const String transfer = 'transfer';
  static const String production = 'production';
  static const String act = 'act';
  static const String inventory = 'inventory';
  static const String reserve = 'reserve';

  static const List<String> all = [
    receipt,
    issue,
    transfer,
    production,
    act,
    inventory,
    reserve,
  ];

  static String title(String t) {
    switch (t) {
      case receipt:
        return 'Приход';
      case issue:
        return 'Расход';
      case transfer:
        return 'Ko\'chirish';
      case production:
        return 'Ishlab chiqarish';
      case act:
        return 'Akt (sotuv)';
      case inventory:
        return 'Inventarizatsiya';
      case reserve:
        return 'Rezerv';
      default:
        return t;
    }
  }

  /// Ruxsat kaliti uchun tur: `reserve` uchun alohida perm yo'q (katalogda),
  /// shartnoma «transfer kabi» deydi — transfer ruxsati bilan tekshiriladi.
  static String permType(String t) => t == reserve ? transfer : t;

  static bool hasFrom(String t) =>
      t == issue || t == transfer || t == production || t == reserve;
  static bool hasTo(String t) =>
      t == receipt || t == transfer || t == production || t == act ||
      t == inventory || t == reserve;
  static bool hasCorr(String t) => t == receipt || t == issue;
  static bool hasPrice(String t) => t == receipt;
  static bool hasSaleAmount(String t) => t == issue || t == reserve;
}

abstract final class CoreDocStatus {
  static const String draft = 'draft';
  static const String posted = 'posted';
  static const String cancelled = 'cancelled';

  static String title(String s) {
    switch (s) {
      case draft:
        return 'Qoralama';
      case posted:
        return 'O\'tkazilgan';
      case cancelled:
        return 'Bekor';
      default:
        return s;
    }
  }
}

class CoreDocLine {
  final int id;
  final int ord;
  final int goodId;
  final String goodName;
  final String unit; // ko'rsatish birligi (kg/g/pcs…)
  final int qty; // BUTUN base birlik
  final int price; // 1 `unit` narxi, butun so'm
  final int amount; // butun so'm
  final int flag; // production: 1 — sarf, 0 — mahsulot

  const CoreDocLine({
    this.id = 0,
    this.ord = 0,
    required this.goodId,
    this.goodName = '',
    this.unit = '',
    this.qty = 0,
    this.price = 0,
    this.amount = 0,
    this.flag = 0,
  });

  factory CoreDocLine.fromJson(Map<String, dynamic> j) => CoreDocLine(
        id: (j['id'] as num?)?.toInt() ?? 0,
        ord: (j['ord'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        unit: (j['unit'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        flag: (j['flag'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'ord': ord,
        'good_id': goodId,
        'unit': unit,
        'qty': qty,
        'price': price,
        'amount': amount,
        'flag': flag,
      };
}

/// `POST /docs/{id}/post` → `warnings[]` (masalan manfiy qoldiq).
class CoreDocWarning {
  final String code;
  final int? skladId;
  final int? goodId;
  final String goodName;
  final int qty;
  final String msg;

  const CoreDocWarning({
    this.code = '',
    this.skladId,
    this.goodId,
    this.goodName = '',
    this.qty = 0,
    this.msg = '',
  });

  factory CoreDocWarning.fromJson(Map<String, dynamic> j) => CoreDocWarning(
        code: (j['code'] ?? '').toString(),
        skladId: (j['sklad_id'] as num?)?.toInt(),
        goodId: (j['good_id'] as num?)?.toInt(),
        goodName: (j['good_name'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        msg: (j['msg'] ?? '').toString(),
      );
}

/// Tafsilotdagi `stock_after`: hujjatdan keyingi qoldiq (ombor, tovar).
class CoreStockAfter {
  final int skladId;
  final int goodId;
  final String goodName;
  final int qty;

  const CoreStockAfter({
    required this.skladId,
    required this.goodId,
    this.goodName = '',
    this.qty = 0,
  });

  factory CoreStockAfter.fromJson(Map<String, dynamic> j) => CoreStockAfter(
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toInt() ?? 0,
      );
}

class CoreDoc {
  final int id;
  final String type;
  final String number;
  final String docDate; // "YYYY-MM-DD"
  final int? fromSklad;
  final int? toSklad;
  final int? corrId;
  final String status;
  final String comment;
  final String source;
  final String? externalId;
  final int? createdBy;
  final int? postedBy;
  final String? postedAt;
  final String? createdAt;
  final int total;
  final int saleAmount;
  final List<CoreDocLine> lines;
  final List<CoreStockAfter> stockAfter;
  final List<CoreDocWarning> warnings;

  const CoreDoc({
    this.id = 0,
    required this.type,
    this.number = '',
    required this.docDate,
    this.fromSklad,
    this.toSklad,
    this.corrId,
    this.status = CoreDocStatus.draft,
    this.comment = '',
    this.source = 'app',
    this.externalId,
    this.createdBy,
    this.postedBy,
    this.postedAt,
    this.createdAt,
    this.total = 0,
    this.saleAmount = 0,
    this.lines = const [],
    this.stockAfter = const [],
    this.warnings = const [],
  });

  factory CoreDoc.fromJson(Map<String, dynamic> j) => CoreDoc(
        id: (j['id'] as num?)?.toInt() ?? 0,
        type: (j['type'] ?? '').toString(),
        number: (j['number'] ?? '').toString(),
        docDate: (j['doc_date'] ?? '').toString().split('T').first,
        fromSklad: (j['from_sklad'] as num?)?.toInt(),
        toSklad: (j['to_sklad'] as num?)?.toInt(),
        corrId: (j['corr_id'] as num?)?.toInt(),
        status: (j['status'] ?? CoreDocStatus.draft).toString(),
        comment: (j['comment'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        externalId: j['external_id']?.toString(),
        createdBy: (j['created_by'] as num?)?.toInt(),
        postedBy: (j['posted_by'] as num?)?.toInt(),
        postedAt: j['posted_at']?.toString(),
        createdAt: j['created_at']?.toString(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        saleAmount: (j['sale_amount'] as num?)?.toInt() ?? 0,
        lines: (j['lines'] as List?)
                ?.whereType<Map>()
                .map((e) => CoreDocLine.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        stockAfter: (j['stock_after'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreStockAfter.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        warnings: (j['warnings'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreDocWarning.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  /// POST/PUT tanasi (server hisoblaydigan maydonlar yuborilmaydi).
  Map<String, dynamic> toJson() => {
        'type': type,
        'doc_date': docDate,
        'from_sklad': fromSklad,
        'to_sklad': toSklad,
        'corr_id': corrId,
        'comment': comment,
        if (CoreDocType.hasSaleAmount(type)) 'sale_amount': saleAmount,
        'lines': [
          for (var i = 0; i < lines.length; i++)
            (lines[i].toJson()..['ord'] = i + 1),
        ],
      };

  bool get isDraft => status == CoreDocStatus.draft;
  bool get isPosted => status == CoreDocStatus.posted;

  CoreDoc copyWith({
    List<CoreDocWarning>? warnings,
  }) =>
      CoreDoc(
        id: id,
        type: type,
        number: number,
        docDate: docDate,
        fromSklad: fromSklad,
        toSklad: toSklad,
        corrId: corrId,
        status: status,
        comment: comment,
        source: source,
        externalId: externalId,
        createdBy: createdBy,
        postedBy: postedBy,
        postedAt: postedAt,
        createdAt: createdAt,
        total: total,
        saleAmount: saleAmount,
        lines: lines,
        stockAfter: stockAfter,
        warnings: warnings ?? this.warnings,
      );
}

/// `GET /docs` → {"items":[…],"total":N}.
class CoreDocPage {
  final List<CoreDoc> items;
  final int total;
  const CoreDocPage({required this.items, required this.total});
}

/// `POST /docs/{id}/post` va `/docs/quick` javobi.
class CoreDocPostResult {
  final CoreDoc doc;
  final List<CoreDocWarning> warnings;
  const CoreDocPostResult({required this.doc, required this.warnings});

  factory CoreDocPostResult.fromJson(Map<String, dynamic> j) {
    final docJson =
        j['doc'] is Map ? Map<String, dynamic>.from(j['doc'] as Map) : j;
    final w = (j['warnings'] as List?)
            ?.whereType<Map>()
            .map((e) => CoreDocWarning.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <CoreDocWarning>[];
    return CoreDocPostResult(doc: CoreDoc.fromJson(docJson), warnings: w);
  }
}
