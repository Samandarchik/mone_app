// Bozor (ombor) mahsuloti modeli.
// Backend javobi seller /products1 bilan bir xil guruhlangan shaklda keladi:
// { "success": true, "message": "...", "data": { "Kategoriya": [ {...}, ... ] } }
import 'package:uz_ai_dev/core/utils/product_sources.dart';

class OmborProduct {
  final int id;
  final String name;
  final String? type;
  final num? grams;
  // Bozor (yuk keltiruvchi) oqimi uchun: 1 pachkaga qancha gramm
  final num? bozorGrams;
  final String? ingredients;
  final String? companyName;
  final String? imageUrl;
  // Asosiy manba (= sources.first) — eski maydon.
  final String? source;
  // Yuk qayerdan keladi — bir nechta bo'lishi mumkin (Samarqand + Toshkent).
  // Kanonik tartib, hech qachon bo'sh emas. Omborchi har manba uchun ALOHIDA
  // miqdor kiritadi; backend har manbani o'z bozorchisiga alohida buyurtma
  // qilib yuboradi.
  final List<String> sources;

  OmborProduct({
    required this.id,
    required this.name,
    this.type,
    this.grams,
    this.bozorGrams,
    this.ingredients,
    this.companyName,
    this.imageUrl,
    this.source,
    List<String>? sources,
  }) : sources = parseProductSources(sources, source);

  factory OmborProduct.fromJson(Map<String, dynamic> json) {
    return OmborProduct(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      type: json['type'],
      grams: json['grams'],
      bozorGrams: json['bozor_grams'],
      ingredients: json['ingredients'],
      companyName: json['company_name'],
      imageUrl: json['image_url'],
      source: json['source']?.toString(),
      // sources yo'q/bo'sh (eski backend) -> [source] -> ['samarqand'].
      sources: parseProductSources(json['sources'], json['source']),
    );
  }

  // Asosiy manba — bitta manbali mahsulotda savat qatori shu manba bilan.
  String get primarySource => sources.first;

  // Bir nechta manbadan keladimi — kartochkada har manbaga alohida qator.
  bool get isMultiSource => sources.length > 1;

  // Manbalar foydalanuvchiga ko'rsatiladigan matnda: «Samarqand, Toshkent».
  // Bitta manba nomi uchun — productSourceLabel (core/utils/product_sources.dart).
  String get sourceLabel => sources.map(productSourceLabel).join(', ');
}

// Kategoriya (GET /api/categories) — admin paneldagi kabi ro'yxat uchun:
// dumaloq rasm + nom. Ombor ekranida kategoriya sahifasiga kirish uchun.
class OmborCategory {
  final int id;
  final String name;
  final String? imageUrl;

  OmborCategory({required this.id, required this.name, this.imageUrl});

  factory OmborCategory.fromJson(Map<String, dynamic> json) {
    return OmborCategory(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      imageUrl: json['image_url'],
    );
  }
}

// Guruhlangan javobni ( data: Map<String, List> ) parse qilish.
Map<String, List<OmborProduct>> parseOmborProducts(
    Map<String, dynamic> data) {
  final Map<String, List<OmborProduct>> result = {};
  data.forEach((category, products) {
    if (products is List) {
      result[category] = products
          .map((item) =>
              OmborProduct.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
  });
  return result;
}
