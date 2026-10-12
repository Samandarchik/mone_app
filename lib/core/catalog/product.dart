// core/catalog/product.dart — mahsulot (nomenklatura) modeli, HAMMA rol uchun
// YAGONA: seller, ombor, yuk, shef, admin shu `Product`ni ishlatadi (ilgari
// 6 xil klass bor edi). Kontrakt: mone_app/REJA_NOMENKLATURA.md §4–5.
//
// JSON KALIT ↔ MAYDON jadvali (sim kalitlar tarixiy, kod nomlari tushunarli):
//   id, name, category_id, category_name, image_url, company_name
//   type            → unit        — o'lchov birligi (кг|л|шт|м|гр|мл|пачка|порция|упаковка)
//   kind            → kind        — raw (xomashyo/tovar) | pf (полуфабрикат) | product (tayyor mahsulot)
//   mone_app        → sellable    — filial/seller katalogida sotiladi
//   bozor           → purchasable — ombor/bozor katalogida sotib olinadi
//   filials, sklads, sources      — qayerda sotiladi / saqlanadi / qayerdan keladi
//   sell_step       → sellStep    — seller «+» qadami, ENG KICHIK birlikda BUTUN (0.5 кг → 500); 0 = 1 to'liq birlik
//   buy_step        → buyStep     — bozor pachkasi, eng kichik birlikda butun (25 кг → 25000); 0 = sellStep
//   ingredients     → sostav      — «Состав» matni (seller «Tarkibi»)
//   waste_base/waste_amount, piece_weight_g, manual_price, manual_price_at — o'zgarmagan
//   tech_card       → techCard    — retsept (core/catalog/tech_card.dart), faqat ?include=recipe da keladi
//
// ESKI KALITLAR (faqat o'qishda, eski backend javobi uchun): is_semi_finished
// → kind, grams/bozor_grams (float, display birlik) → sell_step/buy_step.
// toJson() BITTA — create ham, update ham shu; manual_price YUBORILMAYDI
// (uning o'z endpointi bor: PUT /api/products/{id}/manual-price).
import 'package:uz_ai_dev/core/catalog/tech_card.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';

// Mahsulot TURI — katta tizimlardagi (iiko «Номенклатура») aniq tur.
enum ProductKind {
  // Xomashyo / tovar: un, shakar, tuxum, qadoq, Coca-Cola. Sotib olinadi;
  // sotilishi ham mumkin (resale). Ishlab chiqarilmaydi.
  raw('raw', 'Xomashyo'),
  // Полуфабрикат: biskvit, krem, сироп. Ishlab chiqariladi va boshqa
  // retseptlarda sarflanadi. Kataloglarda ko'rinmaydi.
  pf('pf', 'Полуфабрикат'),
  // Tayyor mahsulot: tort, pirojnoe. Retsepti bor, ishlab chiqariladi,
  // filiallarga sotiladi.
  product('product', 'Tayyor mahsulot');

  const ProductKind(this.wire, this.label);

  // JSON qiymati.
  final String wire;
  // Foydalanuvchiga ko'rsatiladigan nom (admin formasi radio).
  final String label;

  static ProductKind? parse(Object? v) {
    final s = v?.toString().trim().toLowerCase() ?? '';
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ??
      (double.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
}

num? _asNumOrNull(dynamic v) {
  if (v is num) return v;
  return num.tryParse(v?.toString() ?? '');
}

List<int> _asIntList(dynamic v) {
  if (v is! List) return const [];
  return [for (final e in v) _asInt(e)];
}

List<String> _asStringList(dynamic v) {
  if (v is! List) return const [];
  return [for (final e in v) e?.toString() ?? ''];
}

class Product {
  final int id;
  final String name;
  final int categoryId;
  // Server qo'shib beradi (GET /api/products); bo'lmasa ''.
  final String categoryName;
  // O'lchov birligi (JSON: type). Kanonik kichik harf: кг, шт, л ...
  final String unit;
  final ProductKind kind;
  // Kanallar (turdan ALOHIDA): sotiladimi / sotib olinadimi.
  final bool sellable;
  final bool purchasable;
  // Qaysi filiallarda sotiladi (sellable bo'lsa).
  final List<int> filials;
  final List<String> filialNames;
  // Qaysi skladlarda saqlanadi (purchasable bo'lsa).
  final List<int> sklads;
  // Yuk qayerdan keladi — kanonik tartib, dublikatsiz, hech qachon bo'sh emas
  // (core/utils/product_sources.dart).
  final List<String> sources;
  // Seller «+» qadami va bozor pachkasi — ENG KICHIK birlikda BUTUN son.
  // 0 = belgilanmagan (sellStepOrDefault / buyStepOrDefault ishlating).
  final int sellStep;
  final int buyStep;
  // «Состав» matni (seller «Tarkibi»). '' — yo'q.
  final String sostav;
  final String companyName; // '' — yo'q
  final String imageUrl; // '/static/...' yoki '' — rasm yo'q

  // Tozalash yo'qotishi (faqat кг/л oilasi uchun, gr/ml da butun son):
  // har wasteBase grammdan wasteAmount gramm yo'qoladi. 0/0 = yo'q.
  final int wasteBase;
  final int wasteAmount;

  // «1 шт = X gr» — шт birlikdagi XOM mahsulot (masalan tuxum) uchun bitta
  // dona og'irligi, BUTUN gramm. 0 — belgilanmagan. Pf uchun og'irlik o'z tex
  // kartasidan olinadi (tech_card_cost.dart -> techEffectivePieceWeightG).
  final int pieceWeightG;

  // QO'LDA kiritilgan xarid narxi — BUTUN so'm, mahsulotning TO'LIQ birligi
  // uchun (кг → 1 kg narxi, шт → 1 dona narxi). 0 — kiritilmagan.
  final int manualPrice;
  // Qo'lda narx oxirgi marta qachon kiritilgan (null — kiritilmagan).
  final DateTime? manualPriceAt;

  // Retsept. null — yo'q yoki so'ralmagan (?include=recipe siz ro'yxat).
  final TechCard? techCard;

  Product({
    required this.id,
    required this.name,
    this.categoryId = 0,
    this.categoryName = '',
    this.unit = '',
    this.kind = ProductKind.raw,
    this.sellable = false,
    this.purchasable = false,
    this.filials = const [],
    this.filialNames = const [],
    this.sklads = const [],
    List<String>? sources,
    this.sellStep = 0,
    this.buyStep = 0,
    this.sostav = '',
    this.companyName = '',
    this.imageUrl = '',
    this.wasteBase = 0,
    this.wasteAmount = 0,
    this.pieceWeightG = 0,
    this.manualPrice = 0,
    this.manualPriceAt,
    this.techCard,
  }) : sources = parseProductSources(sources, null);

  // ---- hisoblanadigan ----

  bool get isPf => kind == ProductKind.pf;

  // Retseptda tarkib bormi («i» belgisi, foyda nazorati, shef ro'yxati).
  bool get hasRecipe => techCard?.hasContent ?? false;

  // Tozalash yo'qotishi koeffitsiyenti: xarid narxi shu koeffitsiyentga
  // ko'paytiriladi (masalan 8000 dan 100 yo'qolsa — 8000/7900).
  // Noto'g'ri qiymatlarda 1 (ta'sir yo'q).
  double get wasteFactor {
    if (wasteBase > 0 && wasteAmount > 0 && wasteAmount < wasteBase) {
      return wasteBase / (wasteBase - wasteAmount);
    }
    return 1;
  }

  // Seller qadami (eng kichik birlikda): belgilanmagan bo'lsa 1 to'liq birlik
  // (кг → 1000 gr, шт → 1 dona).
  int get sellStepOrDefault => sellStep > 0 ? sellStep : qtyUnitFactor(unit);

  // Bozor pachkasi (eng kichik birlikda): belgilanmagan bo'lsa seller qadami.
  int get buyStepOrDefault => buyStep > 0 ? buyStep : sellStepOrDefault;

  // Asosiy manba — bitta manbali mahsulotda savat qatori shu manba bilan.
  String get primarySource => sources.first;

  // Bir nechta manbadan keladimi — kartochkada har manbaga alohida qator.
  bool get isMultiSource => sources.length > 1;

  // Manbalar foydalanuvchiga ko'rsatiladigan matnda: «Samarqand, Toshkent».
  String get sourceLabel => sources.map(productSourceLabel).join(', ');

  // Retsept partiyasi: bitta list donasi, list soni, jami dona (ishlab
  // chiqarish buyurtmasi ekranlari). Retsept yo'q — 1.
  int get batchQty => techCard?.batchQty ?? 1;
  int get listQty => techCard?.listQty ?? 1;
  int get totalPieces => techCard?.totalPieces ?? 1;

  // Partiya soni: yuqoriga yaxlitlash — ceil(qty / totalPieces).
  int batchesFor(int qty) =>
      qty <= 0 ? 0 : (qty + totalPieces - 1) ~/ totalPieces;

  // ---- JSON ----

  factory Product.fromJson(Map<String, dynamic> json) {
    final unit = json['type']?.toString() ?? '';
    final techCard = json['tech_card'] is Map
        ? TechCard.fromJson(Map<String, dynamic>.from(json['tech_card']))
        : null;

    // kind yo'q (eski backend) → is_semi_finished / retsept / xomashyo.
    final kind = ProductKind.parse(json['kind']) ??
        (json['is_semi_finished'] == true
            ? ProductKind.pf
            : ((techCard?.bases.isNotEmpty ?? false)
                ? ProductKind.product
                : ProductKind.raw));

    // sell_step/buy_step yo'q (eski backend) → grams/bozor_grams (display
    // birlik, float) eng kichik birlikka o'giriladi.
    int step(String canonical, String legacy) {
      if (json[canonical] != null) return _asInt(json[canonical]);
      final g = _asNumOrNull(json[legacy]);
      if (g == null || g <= 0) return 0;
      return qtyFromUi(g, unit).round();
    }

    return Product(
      id: _asInt(json['id']),
      name: json['name']?.toString() ?? '',
      categoryId: _asInt(json['category_id']),
      categoryName: json['category_name']?.toString() ?? '',
      unit: unit,
      kind: kind,
      sellable: json['mone_app'] == true,
      purchasable: json['bozor'] == true,
      filials: _asIntList(json['filials']),
      filialNames: _asStringList(json['filial_names']),
      sklads: _asIntList(json['sklads']),
      // sources yo'q/bo'sh (eski backend) -> [source] -> ['samarqand'].
      sources: parseProductSources(json['sources'], json['source']),
      sellStep: step('sell_step', 'grams'),
      buyStep: step('buy_step', 'bozor_grams'),
      sostav: json['ingredients']?.toString() ?? '',
      companyName: json['company_name']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      wasteBase: _asInt(json['waste_base']),
      wasteAmount: _asInt(json['waste_amount']),
      pieceWeightG: _asInt(json['piece_weight_g']),
      manualPrice: _asInt(json['manual_price']),
      manualPriceAt:
          DateTime.tryParse(json['manual_price_at']?.toString() ?? ''),
      techCard: techCard,
    );
  }

  // Tolerant ro'yxat parse: {data:[...]} ham, to'g'ridan-to'g'ri massiv ham.
  static List<Product> listFromJson(dynamic data) {
    final list = data is Map ? data['data'] : data;
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // POST /api/products va PUT /api/products/{id} uchun BITTA shakl.
  // manual_price ATAYLAB yo'q — uning o'z endpointi bor (yuborilsa har
  // saqlashda manual_price_at bugunga surilib «eski narx» ogohi yo'qolardi).
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category_id': categoryId,
        'type': unit,
        'kind': kind.wire,
        'mone_app': sellable,
        'bozor': purchasable,
        'filials': filials,
        'sklads': sklads,
        'sources': sources,
        'sell_step': sellStep,
        'buy_step': buyStep,
        'ingredients': sostav,
        'company_name': companyName,
        'image_url': imageUrl,
        'waste_base': wasteBase,
        'waste_amount': wasteAmount,
        // Backend "maydon yo'q = tegilmasin" deb qaraydi — set/clear qilish
        // uchun DOIM yuboriladi (0 = o'chirish).
        'piece_weight_g': pieceWeightG,
        'tech_card': techCard?.toJson(),
      };

  Product copyWith({
    int? id,
    String? name,
    int? categoryId,
    String? categoryName,
    String? unit,
    ProductKind? kind,
    bool? sellable,
    bool? purchasable,
    List<int>? filials,
    List<String>? filialNames,
    List<int>? sklads,
    List<String>? sources,
    int? sellStep,
    int? buyStep,
    String? sostav,
    String? companyName,
    String? imageUrl,
    int? wasteBase,
    int? wasteAmount,
    int? pieceWeightG,
    int? manualPrice,
    DateTime? manualPriceAt,
    TechCard? techCard,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      unit: unit ?? this.unit,
      kind: kind ?? this.kind,
      sellable: sellable ?? this.sellable,
      purchasable: purchasable ?? this.purchasable,
      filials: filials ?? this.filials,
      filialNames: filialNames ?? this.filialNames,
      sklads: sklads ?? this.sklads,
      sources: sources ?? this.sources,
      sellStep: sellStep ?? this.sellStep,
      buyStep: buyStep ?? this.buyStep,
      sostav: sostav ?? this.sostav,
      companyName: companyName ?? this.companyName,
      imageUrl: imageUrl ?? this.imageUrl,
      wasteBase: wasteBase ?? this.wasteBase,
      wasteAmount: wasteAmount ?? this.wasteAmount,
      pieceWeightG: pieceWeightG ?? this.pieceWeightG,
      manualPrice: manualPrice ?? this.manualPrice,
      // manualPrice 0 ga tushsa (o'chirish) sana ham ma'nosini yo'qotadi.
      manualPriceAt:
          (manualPrice == 0) ? null : (manualPriceAt ?? this.manualPriceAt),
      techCard: techCard ?? this.techCard,
    );
  }
}
