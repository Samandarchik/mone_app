// Tortlar «tex karta» (тех карта) modeli.
// Barcha OG'IRLIK/HAJM butun son (int) — eng kichik birlikda: g yoki ml.
// Dona (pcs) va metr (m) o'z birligida butun son. float ISHLATILMAYDI.
// amount — BUTUN PARTIYA uchun (jami batch_qty × list_qty dona).
// 1 dona uchun = amount / (batch_qty × list_qty).
// Backend JSON snake_case.

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

// Bitta ingredient/расходник (item).
class TechItem {
  final int productId;
  final String name;
  final String unit; // g | ml | pcs | m
  final int amount; // partiya uchun miqdor
  // Switch YONIQ bo'lsa shu nom «Состав»ga chiqadi.
  final bool showInSostav;

  const TechItem({
    this.productId = 0,
    required this.name,
    required this.unit,
    required this.amount,
    this.showInSostav = false,
  });

  factory TechItem.fromJson(Map<String, dynamic> json) {
    final rawShow = json['show_in_sostav'];
    return TechItem(
      productId: _asInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      unit: normalizeTechUnit(json['unit']?.toString()),
      amount: _asInt(json['amount']),
      showInSostav: rawShow == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'unit': unit,
        'amount': amount,
        'show_in_sostav': showInSostav,
      };

  TechItem copyWith({
    int? productId,
    String? name,
    String? unit,
    int? amount,
    bool? showInSostav,
  }) {
    return TechItem(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      amount: amount ?? this.amount,
      showInSostav: showInSostav ?? this.showInSostav,
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

// Yarim tayyor blok (biskvit, krem, sироп, ...).
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

// To'liq tex karta.
class TechCard {
  // BITTA LISTdan (противень) chiqadigan dona. Partiya JAMI donasi =
  // batchQty × listQty (totalPieces) — 1 dona hisoblari shunga bo'linadi.
  final int batchQty;
  // batchQty ning KO'RSATISH birligi: '' (шт, default) | 'g' (полуфабрикат
  // uchun; kelishuv: 1 шт = 1 гр — soni o'zgarmaydi, faqat birlik yozuvi).
  final String batchUnit;
  final int batchWeightG; // server avto hisoblaydi
  final int pieceWeightG; // server avto hisoblaydi
  // Shakl: '' — belgilanmagan, 'round' — dumaloq (diameterCm),
  // 'rect' — to'rtburchak (widthCm × lengthCm). Backend sanitizatsiya qiladi:
  // rect'da diametr, round'da eni/uzunlik tozalanadi.
  final String shape;
  final int? diameterCm; // tort uchun ixtiyoriy (round shakl)
  final int? widthCm; // to'rtburchak eni, sm (rect shakl)
  final int? lengthCm; // to'rtburchak uzunligi, sm (rect shakl)
  final int? heightCm; // tort balandligi, sm (round va rect uchun)
  // Partiya nechta LISTda (противень/forma) pishiriladi. Bitta list
  // batchQty (Штук) bo'lakka kesiladi — kesish sxemasi shunga qarab chiziladi.
  final int listQty;
  // Bo'limlar (bosqichlar) ro'yxati; bo'sh bo'lsa hammasi 1 ta bo'lim deb olinadi.
  final List<TechStage> stages;
  final List<TechBase> bases;
  final List<TechItem> consumables; // qadoqlash materiallari

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

  // Pishirish vaqti (daqiqa) va harorati (°C); 0 — kiritilmagan. Faqat
  // Biskvit bo'limidagi «Бисквит» kategoriyasi retseptlarida ko'rsatiladi
  // (shef_tech_card_page.dart → isBiskvitCategory).
  final int bakeTimeMin;
  final int bakeTempC;
  // Tayyor biskvit fotosi — tex kartada saqlanadi va ko'rsatiladi (shef
  // «П/Ф Бисквит»). "/static/..." yoki '' (yo'q). JSON: biscuit_photo_url.
  // 3D rasmga foto QO'YILMAYDI — u тех карта tarkibidan chiziladi.
  final String biscuitPhotoUrl;

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
  });

  factory TechCard.fromJson(Map<String, dynamic> json) {
    final rawMode = json['profit_mode']?.toString() ?? '';
    final rawOverhead = json['overhead_mode']?.toString() ?? '';
    final diameter =
        json['diameter_cm'] == null ? null : _asInt(json['diameter_cm']);
    final rawShape = normalizeTechShape(json['shape']?.toString());
    return TechCard(
      batchQty: json['batch_qty'] == null ? 1 : _asInt(json['batch_qty']),
      batchUnit: json['batch_unit']?.toString() == 'g' ? 'g' : '',
      batchWeightG: _asInt(json['batch_weight_g']),
      pieceWeightG: _asInt(json['piece_weight_g']),
      // Eski karta: shape yo'q, lekin diametr bor — round deb olinadi.
      shape: (rawShape.isEmpty && diameter != null) ? 'round' : rawShape,
      diameterCm: diameter,
      widthCm: json['width_cm'] == null ? null : _asInt(json['width_cm']),
      lengthCm: json['length_cm'] == null ? null : _asInt(json['length_cm']),
      heightCm: json['height_cm'] == null ? null : _asInt(json['height_cm']),
      listQty: _asInt(json['list_qty']) < 1 ? 1 : _asInt(json['list_qty']),
      stages: TechStage.listFromJson(json['stages']),
      bases: TechBase.listFromJson(json['bases']),
      consumables: TechItem.listFromJson(json['consumables']),
      profitMode: (rawMode == 'percent' || rawMode == 'sum') ? rawMode : '',
      profitValue: _asDouble(json['profit_value']),
      overheadMode: (rawOverhead == 'percent' || rawOverhead == 'sum')
          ? rawOverhead
          : '',
      overheadValue: _asDouble(json['overhead_value']),
      salePrice: _asInt(json['sale_price']),
      bakeTimeMin: _asInt(json['bake_time_min']),
      bakeTempC: _asInt(json['bake_temp_c']),
      biscuitPhotoUrl: json['biscuit_photo_url']?.toString() ?? '',
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

  Map<String, dynamic> toJson() => {
        'batch_qty': batchQty,
        'batch_unit': batchUnit,
        // Mahalliy hisoblangan qiymatlar (server qayta hisoblaydi).
        'batch_weight_g': computedBatchWeightG,
        'piece_weight_g': computedPieceWeightG,
        'shape': shape,
        'diameter_cm': diameterCm,
        'width_cm': widthCm,
        'length_cm': lengthCm,
        'height_cm': heightCm,
        'list_qty': listQty < 1 ? 1 : listQty,
        'stages': stages.map((e) => e.toJson()).toList(),
        'bases': bases.map((e) => e.toJson()).toList(),
        'consumables': consumables.map((e) => e.toJson()).toList(),
        'profit_mode': profitMode,
        'profit_value': profitValue,
        'overhead_mode': overheadMode,
        'overhead_value': overheadValue,
        'sale_price': salePrice,
        'bake_time_min': bakeTimeMin,
        'bake_temp_c': bakeTempC,
        'biscuit_photo_url': biscuitPhotoUrl,
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
    );
  }

  // «Состав» uchun showInSostav=true bo'lgan barcha nomlar (bazalar + расходник).
  // pfCard berilsa, полуфабрикат qatori (tex kartasi topilgan product_id) o'z nomi
  // o'rniga ICHIDAGI masalliq nomlariga yoyiladi; aylanma havola visited bilan
  // to'xtatiladi (bunda pf nomining o'zi yoziladi). Natija takrorsiz.
  List<String> sostavNames({
    TechCard? Function(int productId)? pfCard,
    Set<int>? visited,
  }) {
    final names = <String>[];
    void addItem(TechItem item) {
      if (!item.showInSostav) return;
      final card = (pfCard != null &&
              item.productId != 0 &&
              !(visited?.contains(item.productId) ?? false))
          ? pfCard(item.productId)
          : null;
      if (card != null) {
        names.addAll(card.sostavNames(
            pfCard: pfCard, visited: {...?visited, item.productId}));
      } else {
        names.add(item.name);
      }
    }

    for (final base in bases) {
      base.ingredients.forEach(addItem);
    }
    consumables.forEach(addItem);
    final seen = <String>{};
    return [
      for (final n in names)
        if (seen.add(n.trim().toLowerCase())) n
    ];
  }
}
