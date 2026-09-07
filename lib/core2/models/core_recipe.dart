// core2/models/core_recipe.dart — mone_core retseptlari: CoreRecipe (tovar
// bo'yicha), CoreRecipeVersion (valid_from, yield, qatorlar), CoreRecipeLine
// (good_id, qty_brutto/qty_netto — butun base birlik). API_V2.md `/recipes`.

class CoreRecipeLine {
  final int ord;
  final int goodId;
  final String goodName;
  final int qtyBrutto;
  final int qtyNetto;

  const CoreRecipeLine({
    this.ord = 0,
    required this.goodId,
    this.goodName = '',
    this.qtyBrutto = 0,
    this.qtyNetto = 0,
  });

  factory CoreRecipeLine.fromJson(Map<String, dynamic> j) => CoreRecipeLine(
        ord: (j['ord'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
        goodName: (j['good_name'] ?? '').toString(),
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
  final int yieldQty;
  final String yieldUnit;
  final List<CoreRecipeLine> lines;

  const CoreRecipeVersion({
    this.id = 0,
    required this.validFrom,
    this.yieldQty = 0,
    this.yieldUnit = '',
    this.lines = const [],
  });

  factory CoreRecipeVersion.fromJson(Map<String, dynamic> j) =>
      CoreRecipeVersion(
        id: (j['id'] as num?)?.toInt() ?? 0,
        validFrom: (j['valid_from'] ?? '').toString().split('T').first,
        yieldQty: (j['yield_qty'] as num?)?.toInt() ?? 0,
        yieldUnit: (j['yield_unit'] ?? '').toString(),
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
        'lines': [
          for (var i = 0; i < lines.length; i++)
            (lines[i].toJson()..['ord'] = i + 1),
        ],
      };
}

class CoreRecipe {
  final int id;
  final int goodId;
  final String name;
  final List<CoreRecipeVersion> versions;

  const CoreRecipe({
    required this.id,
    required this.goodId,
    this.name = '',
    this.versions = const [],
  });

  factory CoreRecipe.fromJson(Map<String, dynamic> j) => CoreRecipe(
        id: (j['id'] as num?)?.toInt() ?? 0,
        goodId: (j['good_id'] as num?)?.toInt() ?? 0,
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
