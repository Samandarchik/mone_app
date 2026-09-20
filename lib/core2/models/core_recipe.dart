// core2/models/core_recipe.dart — mone_core retseptlari: CoreRecipe (tovar
// bo'yicha), CoreRecipeVersion (valid_from, yield, qatorlar), CoreRecipeLine
// (good_id, qty_brutto/qty_netto — butun base birlik). API_V2.md `/recipes`.

class CoreRecipeLine {
  final int ord;
  final int goodId;
  final String goodName;
  final String baseUnit; // o'qishda server beradi (g/ml/mpcs/mm)
  final int qtyBrutto;
  final int qtyNetto;

  const CoreRecipeLine({
    this.ord = 0,
    required this.goodId,
    this.goodName = '',
    this.baseUnit = '',
    this.qtyBrutto = 0,
    this.qtyNetto = 0,
  });

  factory CoreRecipeLine.fromJson(Map<String, dynamic> j) => CoreRecipeLine(
        ord: (j['ord'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        baseUnit: (j['base_unit'] ?? '').toString(),
        qtyBrutto: (j['qty_brutto'] as num?)?.toInt() ?? 0,
        qtyNetto: (j['qty_netto'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'ord': ord,
        'good_id': goodId,
        'qty_brutto': qtyBrutto,
        'qty_netto': qtyNetto,
      };
}

class CoreRecipeVersion {
  final int id;
  final String validFrom; // YYYY-MM-DD
  final int yieldQty; // BUTUN base birlik (yield_unit — ko'rsatish birligi)
  final String yieldUnit; // kg|l|pcs|portion|…
  final String note;
  final List<CoreRecipeLine> lines;

  const CoreRecipeVersion({
    this.id = 0,
    required this.validFrom,
    this.yieldQty = 0,
    this.yieldUnit = '',
    this.note = '',
    this.lines = const [],
  });

  factory CoreRecipeVersion.fromJson(Map<String, dynamic> j) =>
      CoreRecipeVersion(
        id: (j['id'] as num?)?.toInt() ?? 0,
        validFrom: (j['valid_from'] ?? '').toString().split('T').first,
        yieldQty: (j['yield_qty'] as num?)?.toInt() ?? 0,
        yieldUnit: (j['yield_unit'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        lines: (j['lines'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreRecipeLine.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'valid_from': validFrom,
        'yield_qty': yieldQty,
        'yield_unit': yieldUnit,
        'note': note.isEmpty ? null : note,
        'lines': [
          for (var i = 0; i < lines.length; i++)
            (lines[i].toJson()..['ord'] = i + 1),
        ],
      };
}

class CoreRecipe {
  final int id;
  final int goodId;
  final String goodName; // o'qishda server beradi
  final String name;
  final List<CoreRecipeVersion> versions;

  const CoreRecipe({
    required this.id,
    required this.goodId,
    this.goodName = '',
    this.name = '',
    this.versions = const [],
  });

  /// Ro'yxatda ko'rsatiladigan nom: retsept nomi, bo'lmasa tovar nomi.
  String get title => name.isNotEmpty ? name : goodName;

  factory CoreRecipe.fromJson(Map<String, dynamic> j) => CoreRecipe(
        id: (j['id'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        versions: (j['versions'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreRecipeVersion.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  /// Eng yangi versiya (valid_from bo'yicha).
  CoreRecipeVersion? get latest {
    if (versions.isEmpty) return null;
    final sorted = [...versions]
      ..sort((a, b) => b.validFrom.compareTo(a.validFrom));
    return sorted.first;
  }
}

/// `GET /recipes/expand` javobi (ACT_KONTRAKT §7): mahsulotning shu
/// sanadagi retsepti SH5 `expand_sub` qoidasi bilan yoyilgan ingredientlar.
///
/// `rule` — yangi serverda doim `"expand_sub"` (maydon yo'q bo'lsa server
/// ESKI, javob baribir ingredientlar ro'yxati). `cut` — sikl yoki 12 dan
/// chuqur ichma-ichlik tufayli ICHKARIGA YOYILMAGAN yarim tayyorlar
/// (`good_id` lar): ular ro'yxatga o'zi bo'lib tushadi.
class CoreRecipeExpand {
  final int goodId;
  final String date; // YYYY-MM-DD
  final int qty; // BUTUN base birlik
  final String rule; // 'expand_sub' yoki bo'sh (eski server)
  final List<Map<String, dynamic>> ingredients;
  final List<int> cut;

  const CoreRecipeExpand({
    this.goodId = 0,
    this.date = '',
    this.qty = 0,
    this.rule = '',
    this.ingredients = const [],
    this.cut = const [],
  });

  /// Server yangilanganmi (`rule` maydoni bor).
  bool get newServer => rule.isNotEmpty;

  /// Sikl/chuqurlik tufayli yoyilmagan yarim tayyor bormi.
  bool get hasCut => cut.isNotEmpty;

  factory CoreRecipeExpand.fromJson(Map<String, dynamic> j) => CoreRecipeExpand(
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        date: (j['date'] ?? '').toString().split('T').first,
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        rule: (j['rule'] ?? '').toString(),
        ingredients: (j['ingredients'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            const [],
        cut: (j['cut'] as List?)
                ?.map((e) => (e as num?)?.toInt() ?? 0)
                .where((e) => e > 0)
                .toList() ??
            const [],
      );
}
