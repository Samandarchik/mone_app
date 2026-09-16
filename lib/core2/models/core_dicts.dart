// core2/models/core_dicts.dart — mone_core lug'atlari: CoreSklad (ombor,
// allow_negative: strict|warn|soft), CoreCorr (kontragent: supplier|payment|
// debtor|writeoff|other), CoreUnit (birlik katalogi), CoreGoodGroup,
// CoreGood (tovar: base_unit + qo'shimcha birliklar `units:[{unit,to_base}]`).
// Miqdorlar butun base birlikda (g/ml/pcs/m).

class CoreSklad {
  final int id;
  final String name;
  final String kind; // shop|bar|kitchen|production|central|…
  final int? filialId;
  final bool active;
  final String allowNegative; // strict|warn|soft

  const CoreSklad({
    required this.id,
    required this.name,
    this.kind = '',
    this.filialId,
    this.active = true,
    this.allowNegative = 'warn',
  });

  factory CoreSklad.fromJson(Map<String, dynamic> j) => CoreSklad(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        filialId: (j['filial_id'] as num?)?.toInt(),
        active: j['active'] is bool ? j['active'] as bool : true,
        allowNegative: (j['allow_negative'] ?? 'warn').toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'kind': kind,
        'filial_id': filialId,
        'active': active,
        'allow_negative': allowNegative,
      };

  // Server: sklad|shop|bar|kitchen|production|central.
  static const List<String> kinds = [
    'sklad',
    'central',
    'shop',
    'bar',
    'kitchen',
    'production',
  ];
  static const List<String> negativeModes = ['strict', 'warn', 'soft'];
}

class CoreCorr {
  final int id;
  final String name;
  final String kind; // supplier|payment|debtor|writeoff|other
  final bool active;

  const CoreCorr({
    required this.id,
    required this.name,
    this.kind = 'other',
    this.active = true,
  });

  factory CoreCorr.fromJson(Map<String, dynamic> j) => CoreCorr(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        kind: (j['kind'] ?? 'other').toString(),
        active: j['active'] is bool ? j['active'] as bool : true,
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'kind': kind,
        'active': active,
      };

  static const List<String> kinds = [
    'supplier',
    'payment',
    'debtor',
    'writeoff',
    'other',
  ];
}

class CoreUnit {
  final String code;
  final String name;
  final String baseCode;
  final int factor;

  const CoreUnit({
    required this.code,
    this.name = '',
    this.baseCode = '',
    this.factor = 1,
  });

  factory CoreUnit.fromJson(Map<String, dynamic> j) => CoreUnit(
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        baseCode: (j['base_code'] ?? '').toString(),
        factor: (j['factor'] as num?)?.toInt() ?? 1,
      );
}

class CoreGoodGroup {
  final int id;
  final String name;
  final int? parentId;

  const CoreGoodGroup({required this.id, required this.name, this.parentId});

  factory CoreGoodGroup.fromJson(Map<String, dynamic> j) => CoreGoodGroup(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        parentId: (j['parent_id'] as num?)?.toInt(),
      );
}

/// Tovarning qo'shimcha birligi: 1 `unit` = `toBase` × base birlik
/// (kg → 1000 g). Butun son.
class CoreGoodUnit {
  final String unit;
  final int toBase;
  const CoreGoodUnit({required this.unit, required this.toBase});

  factory CoreGoodUnit.fromJson(Map<String, dynamic> j) => CoreGoodUnit(
        unit: (j['unit'] ?? '').toString(),
        toBase: (j['to_base'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {'unit': unit, 'to_base': toBase};
}

class CoreGood {
  final int id;
  final String name;
  final int? groupId;
  final String baseUnit; // g|ml|pcs|m
  final bool isComplect;
  final bool isSemi;
  final String rkCode;
  final bool active;
  final List<CoreGoodUnit> units;
  // TO'LIQ kartochka emas (qoldiq/hujjat qatoridan qurilgan: faqat nom va
  // base birlik ma'lum; `is_complect`, `units` ishonchsiz). Keshda shundaylar
  // `/goods/{id}` bilan to'ldiriladi (CoreDictProvider.ensureGoods).
  final bool partial;

  const CoreGood({
    required this.id,
    required this.name,
    this.groupId,
    this.baseUnit = 'pcs',
    this.isComplect = false,
    this.isSemi = false,
    this.rkCode = '',
    this.active = true,
    this.units = const [],
    this.partial = false,
  });

  factory CoreGood.fromJson(Map<String, dynamic> j) => CoreGood(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        groupId: (j['group_id'] as num?)?.toInt(),
        baseUnit: (j['base_unit'] ?? 'pcs').toString(),
        isComplect: j['is_complect'] == true,
        isSemi: j['is_semi'] == true,
        rkCode: (j['rk_code'] ?? '').toString(),
        active: j['active'] is bool ? j['active'] as bool : true,
        units: (j['units'] as List?)
                ?.whereType<Map>()
                .map((e) => CoreGoodUnit.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'group_id': groupId,
        'base_unit': baseUnit,
        'is_complect': isComplect,
        'is_semi': isSemi,
        'rk_code': rkCode,
        'active': active,
        'units': units.map((u) => u.toJson()).toList(),
      };

  /// Hujjat qatorida tanlanadigan birliklar: default ko'rsatish birligi
  /// (g→kg, ml→l, mpcs→pcs, mm→m) birinchi, keyin qo'shimchalar
  /// (`units`), oxirida base o'zi (takrorsiz).
  List<CoreGoodUnit> get selectableUnits {
    final out = <CoreGoodUnit>[];
    final seen = <String>{};
    void add(CoreGoodUnit u) {
      if (seen.add(u.unit)) out.add(u);
    }

    final def = defaultDisplayUnit(baseUnit);
    if (def != null) add(def);
    for (final u in units) {
      add(u);
    }
    add(CoreGoodUnit(unit: baseUnit, toBase: 1));
    return out;
  }

  /// Tovarning eng qulay kiritish birligi (kg / l / dona / m — ×1000).
  CoreGoodUnit get preferredUnit => selectableUnits.first;

  /// Server qabul qiladigan base birliklar (`/units` da factor=1 bo'lganlar):
  /// g, ml, mpcs (0.001 dona), mm.
  static const List<String> baseUnits = ['g', 'ml', 'mpcs', 'mm'];
}

/// Base birlikka mos «katta» ko'rsatish birligi (×1000): g→kg, ml→l,
/// mpcs→pcs, mm→m. Boshqa (noma'lum) base uchun null.
CoreGoodUnit? defaultDisplayUnit(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return const CoreGoodUnit(unit: 'kg', toBase: 1000);
    case 'ml':
      return const CoreGoodUnit(unit: 'l', toBase: 1000);
    case 'mpcs':
      return const CoreGoodUnit(unit: 'pcs', toBase: 1000);
    case 'mm':
      return const CoreGoodUnit(unit: 'm', toBase: 1000);
    default:
      return null;
  }
}
