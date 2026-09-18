// admin/model/product_model.dart — admin mahsulot modeli (ProductModelAdmin):
// fromJson/toJson, techCard (iyerarxik тех карта), composition (eski tekis
// tarkib), type, is_semi_finished (полуфабрикат), piece_weight_g (1 шт = X gr),
// waste_base/waste_amount (tozalash yo'qotishi -> wasteFactor),
// manual_price/manual_price_at (hech sotib olinmagan masalliqning QO'LDA
// kiritilgan xarid narxi), mone_app/bozor/source/sources/sklads (ombor → yuk
// keltiruvchi oqimi).
import 'package:uz_ai_dev/admin/model/composition_item.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/core/utils/product_sources.dart';

class ProductModelAdmin {
  final int id;
  final String name;
  final int categoryId;
  final String type;
  final String? companyName;
  final num? grams;
  // Bozor (yuk keltiruvchi) oqimi uchun: 1 pachkaga qancha gramm
  final num? bozorGrams;
  final String categoryName;
  final String? imageUrl;
  final String? ingredients;

  final List<int> filials;
  final List<String> filialNames;

  // Ombor → yuk keltiruvchi oqimi uchun yangi maydonlar
  final bool moneApp;
  final bool bozor;
  // Yuk qayerdan keladi — bir nechta bo'lishi mumkin (Samarqand + Toshkent).
  // Kanonik tartib, dublikatsiz, hech qachon bo'sh emas
  // (core/utils/product_sources.dart).
  final List<String> sources;
  // Asosiy manba = sources.first — eski APK'lar uchun alohida yuboriladi.
  final String source;
  final List<int> sklads;

  // Mahsulot tarkibi (eski tekis ingredientlar ro'yxati — saqlanadi, lekin
  // endi tahrirlash IERARXIK tex karta orqali bo'ladi).
  final List<CompositionItem> composition;

  // Yangi iyerarxik tex karta (tortlar uchun). null bo'lishi mumkin.
  final TechCard? techCard;

  // «Состав» switch yoqilganda eski erkin matn shu yerda saqlanadi
  final String? comment;

  // «Состав» tarkibdagi mahsulot nomlaridan to'lsa true bo'ladi
  final bool compositionAsIngredients;

  // Tozalash yo'qotishi (faqat кг/л oilasi uchun, gr/ml da butun son):
  // har wasteBase grammdan wasteAmount gramm yo'qoladi. 0/0 = yo'q.
  final int wasteBase;
  final int wasteAmount;

  // Полуфабрикат (yarim tayyor mahsulot, masalan «Классик бисквит»):
  // o'z tex kartasi va o'z qoldig'i (dona) bor, sotilmaydi — boshqa
  // mahsulotlarning tex kartasida ingredient sifatida ishlatiladi.
  // Backend pf mahsulotlarni seller/filial kataloglaridan avtomatik chiqaradi.
  final bool isSemiFinished;

  // «1 шт = X gr» — шт birlikdagi XOM mahsulot (masalan tuxum) uchun bitta
  // dona og'irligi, BUTUN gramm. 0 — belgilanmagan. Pf uchun og'irlik o'z tex
  // kartasidan olinadi (tech_card_cost.dart -> techEffectivePieceWeightG).
  final int pieceWeightG;

  // QO'LDA kiritilgan xarid narxi — BUTUN so'm, mahsulotning TO'LIQ birligi
  // uchun (кг → 1 kg narxi, шт → 1 dona narxi). 0 — kiritilmagan.
  // Hech qachon sotib olinmagan masalliqning tannarxdagi bo'shlig'ini
  // to'ldiradi; XARID tarixi bo'lsa xarid narxi USTUN (backend qoidasi).
  // 1 гр/мл narxi bu qiymatdan HISOBLANADI (nisbat — saqlanmaydi).
  final int manualPrice;

  // Qo'lda narx oxirgi marta qachon kiritilgan (null — kiritilmagan).
  final DateTime? manualPriceAt;

  ProductModelAdmin({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.type,
    this.companyName,
    this.grams,
    this.bozorGrams,
    required this.categoryName,
    this.ingredients,
    this.imageUrl,
    required this.filials,
    required this.filialNames,
    this.moneApp = true,
    this.bozor = false,
    // source faqat sources berilmaganda (yoki bo'sh bo'lsa) ishlatiladi.
    String source = kDefaultProductSource,
    List<String>? sources,
    this.sklads = const [],
    this.composition = const [],
    this.techCard,
    this.comment,
    this.compositionAsIngredients = false,
    this.wasteBase = 0,
    this.wasteAmount = 0,
    this.isSemiFinished = false,
    this.pieceWeightG = 0,
    this.manualPrice = 0,
    this.manualPriceAt,
  })  : sources = parseProductSources(sources, source),
        // Kontrakt: source DOIM sources[0] ga teng.
        source = parseProductSources(sources, source).first;

  // Tozalash yo'qotishi koeffitsiyenti: xarid narxi shu koeffitsiyentga
  // ko'paytiriladi (masalan 8000 dan 100 yo'qolsa — 8000/7900).
  // Noto'g'ri qiymatlarda 1 (ta'sir yo'q).
  double get wasteFactor {
    if (wasteBase > 0 && wasteAmount > 0 && wasteAmount < wasteBase) {
      return wasteBase / (wasteBase - wasteAmount);
    }
    return 1;
  }

  factory ProductModelAdmin.fromJson(Map<String, dynamic> json) {
    return ProductModelAdmin(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      categoryId: json['category_id'] ?? 0,
      grams: json['grams'],
      bozorGrams: json['bozor_grams'],
      type: json['type'] ?? '',
      ingredients: json['ingredients'],
      companyName: json['company_name'],
      imageUrl: json['image_url'],
      categoryName: json['category_name'] ?? '',
      filials: List<int>.from(json['filials'] ?? []),
      filialNames: List<String>.from(json['filial_names'] ?? []),
      moneApp: json['mone_app'] ?? true,
      bozor: json['bozor'] ?? false,
      // sources yo'q/bo'sh (eski backend) -> [source] -> ['samarqand'].
      sources: parseProductSources(json['sources'], json['source']),
      sklads: (json['sklads'] as List?)?.map((e) => e as int).toList() ?? [],
      composition: CompositionItem.listFromJson(json['composition']),
      techCard: json['tech_card'] != null
          ? TechCard.fromJson(Map<String, dynamic>.from(json['tech_card']))
          : null,
      comment: json['comment']?.toString(),
      compositionAsIngredients: json['composition_as_ingredients'] ?? false,
      wasteBase: (json['waste_base'] as num?)?.toInt() ?? 0,
      wasteAmount: (json['waste_amount'] as num?)?.toInt() ?? 0,
      isSemiFinished: json['is_semi_finished'] ?? false,
      pieceWeightG: (json['piece_weight_g'] as num?)?.toInt() ?? 0,
      manualPrice: (json['manual_price'] as num?)?.toInt() ?? 0,
      manualPriceAt:
          DateTime.tryParse(json['manual_price_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'type': type,
      'company_name': companyName,
      'ingredients': ingredients,
      'image_url': imageUrl,
      'category_name': categoryName,
      'filials': filials,
      'filial_names': filialNames,
      'grams': grams,
      'bozor_grams': bozorGrams,
      'mone_app': moneApp,
      'bozor': bozor,
      'source': source,
      'sources': sources,
      'composition': composition.map((e) => e.toJson()).toList(),
      'tech_card': techCard?.toJson(),
      'comment': comment,
      'composition_as_ingredients': compositionAsIngredients,
      'waste_base': wasteBase,
      'waste_amount': wasteAmount,
      'is_semi_finished': isSemiFinished,
      'piece_weight_g': pieceWeightG,
      'manual_price': manualPrice,
    };
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'ingredients': ingredients,
      "company_name": companyName,
      'grams': grams,
      'bozor_grams': bozorGrams,
      'type': type,
      "image_url": imageUrl,
      'filials': filials,
      'mone_app': moneApp,
      'bozor': bozor,
      'source': source,
      'sources': sources,
      'sklads': sklads,
      'composition': composition.map((e) => e.toJson()).toList(),
      'tech_card': techCard?.toJson(),
      'comment': comment,
      'composition_as_ingredients': compositionAsIngredients,
      'waste_base': wasteBase,
      'waste_amount': wasteAmount,
      'is_semi_finished': isSemiFinished,
      'piece_weight_g': pieceWeightG,
      // Yangi mahsulotda qo'lda narx darhol belgilanishi mumkin (ixtiyoriy).
      'manual_price': manualPrice,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'id': id,
      'name': name,
      'grams': grams,
      'bozor_grams': bozorGrams,
      'category_id': categoryId,
      'type': type,
      "company_name": companyName,
      "ingredients": ingredients,
      "image_url": imageUrl,
      'filials': filials,
      'mone_app': moneApp,
      'bozor': bozor,
      'source': source,
      'sources': sources,
      'sklads': sklads,
      'composition': composition.map((e) => e.toJson()).toList(),
      'tech_card': techCard?.toJson(),
      'comment': comment,
      'composition_as_ingredients': compositionAsIngredients,
      'waste_base': wasteBase,
      'waste_amount': wasteAmount,
      'is_semi_finished': isSemiFinished,
      // Backend "maydon yo'q = tegilmasin" deb qaraydi — set/clear qilish
      // uchun DOIM yuboriladi (0 = o'chirish).
      'piece_weight_g': pieceWeightG,
      // manual_price ATAYLAB YUBORILMAYDI: uning o'z endpointi bor
      // (PUT /api/products/{id}/manual-price). Backend bu maydonni pointer
      // qilib o'qiydi — yo'q bo'lsa qiymat ham, manual_price_at sanasi ham
      // o'zgarmaydi. Yuborsak har tex karta saqlashda sana bugunga surilib,
      // «eski narx» (30 kun) ogohlantirishi hech qachon chiqmay qolardi.
    };
  }

  ProductModelAdmin copyWith({
    int? id,
    String? name,
    int? categoryId,
    String? type,
    num? grams,
    num? bozorGrams,
    String? companyName,
    String? categoryName,
    String? ingredients,
    List<int>? filials,
    String? imageUrl,
    List<String>? filialNames,
    bool? moneApp,
    bool? bozor,
    String? source,
    List<String>? sources,
    List<int>? sklads,
    List<CompositionItem>? composition,
    TechCard? techCard,
    String? comment,
    bool? compositionAsIngredients,
    int? wasteBase,
    int? wasteAmount,
    bool? isSemiFinished,
    int? pieceWeightG,
    int? manualPrice,
    DateTime? manualPriceAt,
  }) {
    return ProductModelAdmin(
      id: id ?? this.id,
      name: name ?? this.name,
      grams: grams ?? this.grams,
      bozorGrams: bozorGrams ?? this.bozorGrams,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      companyName: companyName ?? this.companyName,
      ingredients: ingredients ?? this.ingredients,
      categoryName: categoryName ?? this.categoryName,
      filials: filials ?? this.filials,
      imageUrl: imageUrl ?? this.imageUrl,
      filialNames: filialNames ?? this.filialNames,
      moneApp: moneApp ?? this.moneApp,
      bozor: bozor ?? this.bozor,
      // Faqat source berilsa (eski chaqiruv) — bitta manbaga aylanadi;
      // sources berilsa source undan (sources.first) hisoblanadi.
      source: source ?? this.source,
      sources: sources ?? (source != null ? null : this.sources),
      sklads: sklads ?? this.sklads,
      composition: composition ?? this.composition,
      techCard: techCard ?? this.techCard,
      comment: comment ?? this.comment,
      compositionAsIngredients:
          compositionAsIngredients ?? this.compositionAsIngredients,
      wasteBase: wasteBase ?? this.wasteBase,
      wasteAmount: wasteAmount ?? this.wasteAmount,
      isSemiFinished: isSemiFinished ?? this.isSemiFinished,
      pieceWeightG: pieceWeightG ?? this.pieceWeightG,
      manualPrice: manualPrice ?? this.manualPrice,
      // manualPrice 0 ga tushsa (o'chirish) sana ham ma'nosini yo'qotadi.
      manualPriceAt:
          (manualPrice == 0) ? null : (manualPriceAt ?? this.manualPriceAt),
    );
  }
}
