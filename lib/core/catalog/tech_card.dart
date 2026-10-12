// core/catalog/tech_card.dart — retsept (тех карта) modeli, HAMMA rol uchun
// yagona. TechCard uchta bo'lakdan yig'iladi:
//   RecipeSpec    — retseptning o'zi: partiya, listlar, bo'limlar, bazalar,
//                   расходник, avto og'irliklar;
//   RecipePricing — narx: foyda (profit), dop. rasxod (overhead), sotish narxi;
//   RecipeVisual  — ko'rinish: shakl/o'lchamlar, pishirish, foto, ranglar.
// SIM SHAKLI (JSON) TEKIS va o'zgarmagan — `tech_card` kalitlari backend bilan
// bir xil (models.go TechCard: Go'da ham 3 ta embedded struct, JSON tekis).
// Barcha OG'IRLIK/HAJM butun son (int) — eng kichik birlikda: g yoki ml.
// Dona (pcs) va metr (m) o'z birligida butun son. float ISHLATILMAYDI.
// amount — BUTUN PARTIYA uchun (jami batch_qty × list_qty dona).
// Retsept qatori (TechItem) FAQAT mahsulot ID'si bilan bog'lanadi —
// product_id = 0 bo'lgan qator «bog'lanmagan» (server saqlashda 400 beradi).

// Ruxsat etilgan birliklar (faqat shular).
const List<String> kTechUnits = ['g', 'ml', 'pcs', 'm'];

// Birlikni ko'rsatish uchun ruscha yorliq (qiymat o'zgarmaydi).
String techUnitLabel(String unit) {
  switch (unit) {
    case 'g':
      return 'г';
    case 'ml':
      return 'мл';
    case 'pcs':
      return 'дона';
    case 'm':
      return 'м';
    default:
      return unit;
  }
}

// Noma'lum/eski birlikni ruxsat etilgan birlikka moslaydi.
String normalizeTechUnit(String? unit) {
  final u = (unit ?? '').toLowerCase().trim();
  if (kTechUnits.contains(u)) return u;
  switch (u) {
    case 'г':
    case 'гр':
    case 'грамм':
    case 'кг':
      return 'g';
    case 'мл':
    case 'л':
      return 'ml';
    case 'шт':
    case 'шт.':
    case 'дона':
    case 'pc':
      return 'pcs';
    case 'м':
    case 'см':
    case 'метр':
      return 'm';
    default:
      return 'g';
  }
}

// Shakl qiymatini normallashtiradi: faqat '' | 'round' | 'rect' qabul qilinadi.
String normalizeTechShape(String? shape) {
  final s = (shape ?? '').trim().toLowerCase();
  return (s == 'round' || s == 'rect') ? s : '';
}

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ??
      (double.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

int? _asIntOrNull(dynamic v) => v == null ? null : _asInt(v);

// Bitta ingredient/расходник qatori: {product_id, name, unit, amount}.
// productId — bog'langan mahsulot (0 = bog'lanmagan, faqat eski/import
// qatorlarida uchraydi; muharrir yangi qatorni faqat mahsulot tanlab qo'shadi).
class TechItem {
  final int productId;
  final String name;
  final String unit; // g | ml | pcs | m
  final int amount; // partiya uchun miqdor

  const TechItem({
    this.productId = 0,
    required this.name,
    required this.unit,
    required this.amount,
  });

  // Bog'lanmagan qator (mahsulot tanlanmagan) — muharrirda qizil belgilanadi.
  bool get isUnlinked => productId == 0;

  factory TechItem.fromJson(Map<String, dynamic> json) {
    return TechItem(
      productId: _asInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      unit: normalizeTechUnit(json['unit']?.toString()),
      amount: _asInt(json['amount']),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'unit': unit,
        'amount': amount,
      };

  TechItem copyWith({
    int? productId,
    String? name,
    String? unit,
    int? amount,
  }) {
    return TechItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      amount: amount ?? this.amount,
    );
  }

  static List<TechItem> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => TechItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}

// Ishlab chiqarish bo'limi (bosqichi): Бисквит, Крем, Безаш...
// Tartibi = ishlab chiqarish tartibi. Har baza bitta bo'limga biriktiriladi.
class TechStage {
  final String name;

  const TechStage({required this.name});

  factory TechStage.fromJson(Map<String, dynamic> json) {
    return TechStage(name: json['name']?.toString() ?? '');
  }

  Map<String, dynamic> toJson() => {'name': name};

  static List<TechStage> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => TechStage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}

// Yarim tayyor blok (biskvit, krem, сироп, ...).
class TechBase {
  final String name;
  final int weightG; // server avto hisoblaydi
  final List<TechItem> ingredients;

  // Excel'dagi blok sarlavhasi rangi: "#RRGGBB" yoki '' (standart kulrang).
  final String color;

  // Blok rasmi: "/static/<fayl>" yoki '' (rasm yo'q). JSON kaliti: image_url.
  final String imageUrl;

  // Nechanchi bo'limga (TechCard.stages, 1-based) tegishli.
  // 0 yoki noto'g'ri qiymat = 1-bo'lim deb olinadi.
  final int stage;

  const TechBase({
    required this.name,
    this.weightG = 0,
    this.ingredients = const [],
    this.color = '',
    this.imageUrl = '',
    this.stage = 1,
  });

  factory TechBase.fromJson(Map<String, dynamic> json) {
    final rawStage = _asInt(json['stage']);
    return TechBase(
      name: json['name']?.toString() ?? '',
      weightG: _asInt(json['weight_g']),
      ingredients: TechItem.listFromJson(json['ingredients']),
      color: json['color']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      stage: rawStage < 1 ? 1 : rawStage,
    );
  }

  // Mahalliy hisoblangan og'irlik: faqat g/ml ingredientlar yig'indisi.
  int get computedWeightG => ingredients
      .where((i) => i.unit == 'g' || i.unit == 'ml')
      .fold(0, (sum, i) => sum + i.amount);

  Map<String, dynamic> toJson() => {
        'name': name,
        // Saqlashda mahalliy hisoblangan qiymatni yuboramiz (server qayta hisoblaydi).
        'weight_g': computedWeightG,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'color': color,
        'image_url': imageUrl,
        'stage': stage < 1 ? 1 : stage,
      };

  TechBase copyWith({
    String? name,
    int? weightG,
    List<TechItem>? ingredients,
    String? color,
    String? imageUrl,
    int? stage,
  }) {
    return TechBase(
      name: name ?? this.name,
      weightG: weightG ?? this.weightG,
      ingredients: ingredients ?? this.ingredients,
      color: color ?? this.color,
      imageUrl: imageUrl ?? this.imageUrl,
      stage: stage ?? this.stage,
    );
  }

  static List<TechBase> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => TechBase.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}

// ---------------------------------------------------------------------------
// RecipeSpec — retseptning o'zi (partiya, bo'limlar, bazalar, расходник).
// ---------------------------------------------------------------------------
class RecipeSpec {
  // BITTA LISTdan (противень) chiqadigan dona. Partiya JAMI donasi =
  // batchQty × listQty (totalPieces) — 1 dona hisoblari shunga bo'linadi.
  final int batchQty;
  // batchQty ning KO'RSATISH birligi: '' (шт, default) | 'g' (полуфабрикат
  // uchun; kelishuv: 1 шт = 1 гр — soni o'zgarmaydi, faqat birlik yozuvi).
  final String batchUnit;
  // Partiya nechta LISTda (противень/forma) pishiriladi. Bitta list
  // batchQty (Штук) bo'lakka kesiladi — kesish sxemasi shunga qarab chiziladi.
  final int listQty;
  // Bo'limlar (bosqichlar) ro'yxati; bo'sh bo'lsa hammasi 1 ta bo'lim deb olinadi.
  final List<TechStage> stages;
  final List<TechBase> bases;
  final List<TechItem> consumables; // qadoqlash materiallari
  final int batchWeightG; // server avto hisoblaydi
  final int pieceWeightG; // server avto hisoblaydi

  const RecipeSpec({
    this.batchQty = 1,
    this.batchUnit = '',
    this.listQty = 1,
    this.stages = const [],
    this.bases = const [],
    this.consumables = const [],
    this.batchWeightG = 0,
    this.pieceWeightG = 0,
  });

  factory RecipeSpec.fromJson(Map<String, dynamic> json) {
    final lq = _asInt(json['list_qty']);
    return RecipeSpec(
      batchQty: json['batch_qty'] == null ? 1 : _asInt(json['batch_qty']),
      batchUnit: json['batch_unit']?.toString() == 'g' ? 'g' : '',
      listQty: lq < 1 ? 1 : lq,
      stages: TechStage.listFromJson(json['stages']),
      bases: TechBase.listFromJson(json['bases']),
      consumables: TechItem.listFromJson(json['consumables']),
      batchWeightG: _asInt(json['batch_weight_g']),
      pieceWeightG: _asInt(json['piece_weight_g']),
    );
  }

  // Mahalliy hisoblangan partiya og'irligi (bazalar yig'indisi).
  int get computedBatchWeightG =>
      bases.fold(0, (sum, b) => sum + b.computedWeightG);

  // Partiya JAMI donasi = bitta list donasi (batchQty) × list soni (listQty).
  int get totalPieces =>
      (batchQty < 1 ? 1 : batchQty) * (listQty < 1 ? 1 : listQty);

  // Mahalliy hisoblangan 1 dona og'irligi (partiya JAMI donasiga bo'linadi).
  // Гр rejimida (batchUnit 'g') kelishuv bo'yicha 1 dona = 1 гр — hisoblanmaydi
  // (server ham shunday: recomputeTechCardWeights).
  int get computedPieceWeightG => batchUnit == 'g'
      ? 1
      : (batchQty > 0 ? computedBatchWeightG ~/ totalPieces : 0);

  // Retseptda tarkib bormi (bo'sh karta = tarkibsiz).
  bool get hasContent =>
      bases.any((b) => b.ingredients.isNotEmpty) || consumables.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'batch_qty': batchQty,
        'batch_unit': batchUnit,
        'list_qty': listQty < 1 ? 1 : listQty,
        'stages': stages.map((e) => e.toJson()).toList(),
        'bases': bases.map((e) => e.toJson()).toList(),
        'consumables': consumables.map((e) => e.toJson()).toList(),
        // Mahalliy hisoblangan qiymatlar (server qayta hisoblaydi).
        'batch_weight_g': computedBatchWeightG,
        'piece_weight_g': computedPieceWeightG,
      };

  RecipeSpec copyWith({
    int? batchQty,
    String? batchUnit,
    int? listQty,
    List<TechStage>? stages,
    List<TechBase>? bases,
    List<TechItem>? consumables,
    int? batchWeightG,
    int? pieceWeightG,
  }) {
    return RecipeSpec(
      batchQty: batchQty ?? this.batchQty,
      batchUnit: batchUnit ?? this.batchUnit,
      listQty: listQty ?? this.listQty,
      stages: stages ?? this.stages,
      bases: bases ?? this.bases,
      consumables: consumables ?? this.consumables,
      batchWeightG: batchWeightG ?? this.batchWeightG,
      pieceWeightG: pieceWeightG ?? this.pieceWeightG,
    );
  }
}

// ---------------------------------------------------------------------------
// RecipePricing — foyda, dop. rasxod, tasdiqlangan sotish narxi.
// ---------------------------------------------------------------------------
class RecipePricing {
  // Foyda (ustama): '' — belgilanmagan, 'percent' — foizda, 'sum' — so'mda.
  final String profitMode;
  // percent rejimida foiz qiymati (50 = +50%),
  // sum rejimida 1 DONA uchun so'mdagi foyda.
  final double profitValue;

  // Dop. rasxod (qadoq/kommunal kabi ustama xarajat):
  // '' — yo'q, 'percent' — masalliq tannarxidan (C0) foiz,
  // 'sum' — 1 DONA uchun so'm.
  final String overheadMode;
  final double overheadValue;

  // Tasdiqlangan sotish narxi (so'm/dona). 0 — belgilanmagan.
  // FAQAT admin «Almashtirish» bosganda o'zgaradi — avto yangilanmaydi.
  final int salePrice;

  const RecipePricing({
    this.profitMode = '',
    this.profitValue = 0,
    this.overheadMode = '',
    this.overheadValue = 0,
    this.salePrice = 0,
  });

  static String _mode(dynamic v) {
    final s = v?.toString() ?? '';
    return (s == 'percent' || s == 'sum') ? s : '';
  }

  factory RecipePricing.fromJson(Map<String, dynamic> json) {
    return RecipePricing(
      profitMode: _mode(json['profit_mode']),
      profitValue: _asDouble(json['profit_value']),
      overheadMode: _mode(json['overhead_mode']),
      overheadValue: _asDouble(json['overhead_value']),
      salePrice: _asInt(json['sale_price']),
    );
  }

  Map<String, dynamic> toJson() => {
        'profit_mode': profitMode,
        'profit_value': profitValue,
        'overhead_mode': overheadMode,
        'overhead_value': overheadValue,
        'sale_price': salePrice,
      };

  RecipePricing copyWith({
    String? profitMode,
    double? profitValue,
    String? overheadMode,
    double? overheadValue,
    int? salePrice,
  }) {
    return RecipePricing(
      profitMode: profitMode ?? this.profitMode,
      profitValue: profitValue ?? this.profitValue,
      overheadMode: overheadMode ?? this.overheadMode,
      overheadValue: overheadValue ?? this.overheadValue,
      salePrice: salePrice ?? this.salePrice,
    );
  }
}

// ---------------------------------------------------------------------------
// RecipeVisual — shakl/o'lchamlar, pishirish, foto va ranglar (3D rasm uchun).
// ---------------------------------------------------------------------------
class RecipeVisual {
  // Shakl: '' — belgilanmagan, 'round' — dumaloq (diameterCm),
  // 'rect' — to'rtburchak (widthCm × lengthCm). Backend sanitizatsiya qiladi:
  // rect'da diametr, round'da eni/uzunlik tozalanadi.
  final String shape;
  final int? diameterCm; // tort uchun ixtiyoriy (round shakl)
  final int? widthCm; // to'rtburchak eni, sm (rect shakl)
  final int? lengthCm; // to'rtburchak uzunligi, sm (rect shakl)
  final int? heightCm; // tort balandligi, sm (round va rect uchun)

  // Pishirish vaqti (daqiqa) va harorati (°C); 0 — kiritilmagan. Faqat
  // Biskvit bo'limidagi «Бисквит» kategoriyasi retseptlarida ko'rsatiladi.
  final int bakeTimeMin;
  final int bakeTempC;
  // Tayyor biskvit fotosi — "/static/..." yoki '' (yo'q). JSON: biscuit_photo_url.
  final String biscuitPhotoUrl;
  // Palitradan tanlangan nachinka rangi: "#RRGGBB" yoki '' (tanlanmagan).
  // Shef «П/Ф Начинка» 3D rasmida nachinka shu rangda chiziladi.
  // (Backend'dagi `filling_color2` ATAYLAB o'qilmaydi va yuborilmaydi —
  // test/filling_look_test.dart qo'riqlaydi.)
  final String fillingColor;
  // «Покрытие» bo'limi uchun palitradan tanlangan rang: "#RRGGBB" yoki ''.
  final String coatingColor;
  // BISKVITNING o'z rangi, palitradan: "#RRGGBB" yoki ''.
  final String biscuitColor;

  const RecipeVisual({
    this.shape = '',
    this.diameterCm,
    this.widthCm,
    this.lengthCm,
    this.heightCm,
    this.bakeTimeMin = 0,
    this.bakeTempC = 0,
    this.biscuitPhotoUrl = '',
    this.fillingColor = '',
    this.coatingColor = '',
    this.biscuitColor = '',
  });

  factory RecipeVisual.fromJson(Map<String, dynamic> json) {
    final diameter = _asIntOrNull(json['diameter_cm']);
    final rawShape = normalizeTechShape(json['shape']?.toString());
    return RecipeVisual(
      // Eski karta: shape yo'q, lekin diametr bor — round deb olinadi.
      shape: (rawShape.isEmpty && diameter != null) ? 'round' : rawShape,
      diameterCm: diameter,
      widthCm: _asIntOrNull(json['width_cm']),
      lengthCm: _asIntOrNull(json['length_cm']),
      heightCm: _asIntOrNull(json['height_cm']),
      bakeTimeMin: _asInt(json['bake_time_min']),
      bakeTempC: _asInt(json['bake_temp_c']),
      biscuitPhotoUrl: json['biscuit_photo_url']?.toString() ?? '',
      fillingColor: json['filling_color']?.toString() ?? '',
      coatingColor: json['coating_color']?.toString() ?? '',
      biscuitColor: json['biscuit_color']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'shape': shape,
        'diameter_cm': diameterCm,
        'width_cm': widthCm,
        'length_cm': lengthCm,
        'height_cm': heightCm,
        'bake_time_min': bakeTimeMin,
        'bake_temp_c': bakeTempC,
        'biscuit_photo_url': biscuitPhotoUrl,
        'filling_color': fillingColor,
        'coating_color': coatingColor,
        'biscuit_color': biscuitColor,
      };

  RecipeVisual copyWith({
    String? shape,
    int? diameterCm,
    bool clearDiameter = false,
    int? widthCm,
    bool clearWidth = false,
    int? lengthCm,
    bool clearLength = false,
    int? heightCm,
    bool clearHeight = false,
    int? bakeTimeMin,
    int? bakeTempC,
    String? biscuitPhotoUrl,
    String? fillingColor,
    String? coatingColor,
    String? biscuitColor,
  }) {
    return RecipeVisual(
      shape: normalizeTechShape(shape ?? this.shape),
      diameterCm: clearDiameter ? null : (diameterCm ?? this.diameterCm),
      widthCm: clearWidth ? null : (widthCm ?? this.widthCm),
      lengthCm: clearLength ? null : (lengthCm ?? this.lengthCm),
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      bakeTimeMin: bakeTimeMin ?? this.bakeTimeMin,
      bakeTempC: bakeTempC ?? this.bakeTempC,
      biscuitPhotoUrl: biscuitPhotoUrl ?? this.biscuitPhotoUrl,
      fillingColor: fillingColor ?? this.fillingColor,
      coatingColor: coatingColor ?? this.coatingColor,
      biscuitColor: biscuitColor ?? this.biscuitColor,
    );
  }
}

// ---------------------------------------------------------------------------
// TechCard — to'liq tex karta. Maydonlar TEKIS saqlanadi (const
// konstruktor uchun — Dart const initializer'da ichki obyekt yasab bo'lmaydi),
// `spec` / `pricing` / `visual` esa GURUHLANGAN ko'rinishlar (getter):
// retsept mantiqi `card.spec`, narx `card.pricing`, dizayn `card.visual`.
// JSON tekis (fromJson/toJson uchala bo'lakni bitta map'ga yig'adi).
// ---------------------------------------------------------------------------
class TechCard {
  // ---- RecipeSpec ----
  final int batchQty;
  final String batchUnit;
  final int listQty;
  final List<TechStage> stages;
  final List<TechBase> bases;
  final List<TechItem> consumables;
  final int batchWeightG; // server avto hisoblaydi
  final int pieceWeightG; // server avto hisoblaydi

  // ---- RecipePricing ----
  final String profitMode;
  final double profitValue;
  final String overheadMode;
  final double overheadValue;
  final int salePrice;

  // ---- RecipeVisual ----
  final String shape;
  final int? diameterCm;
  final int? widthCm;
  final int? lengthCm;
  final int? heightCm;
  final int bakeTimeMin;
  final int bakeTempC;
  final String biscuitPhotoUrl;
  final String fillingColor;
  final String coatingColor;
  final String biscuitColor;

  const TechCard({
    this.batchQty = 1,
    this.batchUnit = '',
    this.batchWeightG = 0,
    this.pieceWeightG = 0,
    this.shape = '',
    this.diameterCm,
    this.widthCm,
    this.lengthCm,
    this.heightCm,
    this.listQty = 1,
    this.stages = const [],
    this.bases = const [],
    this.consumables = const [],
    this.profitMode = '',
    this.profitValue = 0,
    this.overheadMode = '',
    this.overheadValue = 0,
    this.salePrice = 0,
    this.bakeTimeMin = 0,
    this.bakeTempC = 0,
    this.biscuitPhotoUrl = '',
    this.fillingColor = '',
    this.coatingColor = '',
    this.biscuitColor = '',
  });

  // Uch bo'lakdan yig'ish.
  factory TechCard.parts({
    required RecipeSpec spec,
    required RecipePricing pricing,
    required RecipeVisual visual,
  }) =>
      TechCard(
        batchQty: spec.batchQty,
        batchUnit: spec.batchUnit,
        listQty: spec.listQty,
        stages: spec.stages,
        bases: spec.bases,
        consumables: spec.consumables,
        batchWeightG: spec.batchWeightG,
        pieceWeightG: spec.pieceWeightG,
        profitMode: pricing.profitMode,
        profitValue: pricing.profitValue,
        overheadMode: pricing.overheadMode,
        overheadValue: pricing.overheadValue,
        salePrice: pricing.salePrice,
        shape: visual.shape,
        diameterCm: visual.diameterCm,
        widthCm: visual.widthCm,
        lengthCm: visual.lengthCm,
        heightCm: visual.heightCm,
        bakeTimeMin: visual.bakeTimeMin,
        bakeTempC: visual.bakeTempC,
        biscuitPhotoUrl: visual.biscuitPhotoUrl,
        fillingColor: visual.fillingColor,
        coatingColor: visual.coatingColor,
        biscuitColor: visual.biscuitColor,
      );

  factory TechCard.fromJson(Map<String, dynamic> json) => TechCard.parts(
        spec: RecipeSpec.fromJson(json),
        pricing: RecipePricing.fromJson(json),
        visual: RecipeVisual.fromJson(json),
      );

  // Guruhlangan ko'rinishlar.
  RecipeSpec get spec => RecipeSpec(
        batchQty: batchQty,
        batchUnit: batchUnit,
        listQty: listQty,
        stages: stages,
        bases: bases,
        consumables: consumables,
        batchWeightG: batchWeightG,
        pieceWeightG: pieceWeightG,
      );

  RecipePricing get pricing => RecipePricing(
        profitMode: profitMode,
        profitValue: profitValue,
        overheadMode: overheadMode,
        overheadValue: overheadValue,
        salePrice: salePrice,
      );

  RecipeVisual get visual => RecipeVisual(
        shape: shape,
        diameterCm: diameterCm,
        widthCm: widthCm,
        lengthCm: lengthCm,
        heightCm: heightCm,
        bakeTimeMin: bakeTimeMin,
        bakeTempC: bakeTempC,
        biscuitPhotoUrl: biscuitPhotoUrl,
        fillingColor: fillingColor,
        coatingColor: coatingColor,
        biscuitColor: biscuitColor,
      );

  // Mahalliy hisoblangan partiya og'irligi (bazalar yig'indisi).
  int get computedBatchWeightG =>
      bases.fold(0, (sum, b) => sum + b.computedWeightG);

  // Partiya JAMI donasi = bitta list donasi (batchQty) × list soni (listQty).
  int get totalPieces =>
      (batchQty < 1 ? 1 : batchQty) * (listQty < 1 ? 1 : listQty);

  // Mahalliy hisoblangan 1 dona og'irligi (partiya JAMI donasiga bo'linadi).
  // Гр rejimida (batchUnit 'g') kelishuv bo'yicha 1 dona = 1 гр.
  int get computedPieceWeightG => batchUnit == 'g'
      ? 1
      : (batchQty > 0 ? computedBatchWeightG ~/ totalPieces : 0);

  // Retseptda tarkib bormi (bo'sh karta = tarkibsiz).
  bool get hasContent =>
      bases.any((b) => b.ingredients.isNotEmpty) || consumables.isNotEmpty;

  // Barcha bog'lanmagan (product_id = 0) qatorlar nomi — bazalar + расходник.
  List<String> get unlinkedNames => [
        for (final b in bases)
          for (final i in b.ingredients)
            if (i.isUnlinked) i.name,
        for (final c in consumables)
          if (c.isUnlinked) c.name,
      ];

  // JSON TEKIS — uchala bo'lak bitta map'ga.
  Map<String, dynamic> toJson() => {
        ...spec.toJson(),
        ...pricing.toJson(),
        ...visual.toJson(),
      };

  TechCard copyWith({
    int? batchQty,
    String? batchUnit,
    int? batchWeightG,
    int? pieceWeightG,
    String? shape,
    int? diameterCm,
    bool clearDiameter = false,
    int? widthCm,
    bool clearWidth = false,
    int? lengthCm,
    bool clearLength = false,
    int? heightCm,
    bool clearHeight = false,
    int? listQty,
    List<TechStage>? stages,
    List<TechBase>? bases,
    List<TechItem>? consumables,
    String? profitMode,
    double? profitValue,
    String? overheadMode,
    double? overheadValue,
    int? salePrice,
    int? bakeTimeMin,
    int? bakeTempC,
    String? biscuitPhotoUrl,
    String? fillingColor,
    String? coatingColor,
    String? biscuitColor,
  }) {
    return TechCard(
      batchQty: batchQty ?? this.batchQty,
      batchUnit: batchUnit ?? this.batchUnit,
      batchWeightG: batchWeightG ?? this.batchWeightG,
      pieceWeightG: pieceWeightG ?? this.pieceWeightG,
      shape: normalizeTechShape(shape ?? this.shape),
      diameterCm: clearDiameter ? null : (diameterCm ?? this.diameterCm),
      widthCm: clearWidth ? null : (widthCm ?? this.widthCm),
      lengthCm: clearLength ? null : (lengthCm ?? this.lengthCm),
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      listQty: listQty ?? this.listQty,
      stages: stages ?? this.stages,
      bases: bases ?? this.bases,
      consumables: consumables ?? this.consumables,
      profitMode: profitMode ?? this.profitMode,
      profitValue: profitValue ?? this.profitValue,
      overheadMode: overheadMode ?? this.overheadMode,
      overheadValue: overheadValue ?? this.overheadValue,
      salePrice: salePrice ?? this.salePrice,
      bakeTimeMin: bakeTimeMin ?? this.bakeTimeMin,
      bakeTempC: bakeTempC ?? this.bakeTempC,
      biscuitPhotoUrl: biscuitPhotoUrl ?? this.biscuitPhotoUrl,
      fillingColor: fillingColor ?? this.fillingColor,
      coatingColor: coatingColor ?? this.coatingColor,
      biscuitColor: biscuitColor ?? this.biscuitColor,
    );
  }

  // «Состав» matni uchun: BAZALARDAGI barcha masalliq nomlari (расходник
  // emas — qadoq iste'molchi tarkibiga kirmaydi). pfCard berilsa, полуфабрикат
  // qatori (tex kartasi topilgan product_id) o'z nomi o'rniga ICHIDAGI
  // masalliqlarga yoyiladi; aylanma havola visited bilan to'xtatiladi.
  // Natija takrorsiz. Admin formasidagi «Retseptdan to'ldirish» tugmasi
  // shu ro'yxatni vergul bilan matn maydoniga yozadi (saqlanadigan holat yo'q).
  List<String> ingredientNames({
    TechCard? Function(int productId)? pfCard,
    Set<int>? visited,
  }) {
    final names = <String>[];
    for (final base in bases) {
      for (final item in base.ingredients) {
        final card = (pfCard != null &&
                item.productId != 0 &&
                !(visited?.contains(item.productId) ?? false))
            ? pfCard(item.productId)
            : null;
        if (card != null && card.hasContent) {
          names.addAll(card.ingredientNames(
              pfCard: pfCard, visited: {...?visited, item.productId}));
        } else {
          names.add(item.name);
        }
      }
    }
    final seen = <String>{};
    return [
      for (final n in names)
        if (n.trim().isNotEmpty && seen.add(n.trim().toLowerCase())) n.trim()
    ];
  }
}
