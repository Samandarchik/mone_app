// ombor/models/ombor_product_model.dart — ombor ekrani kategoriya modeli
// (OmborCategory). Mahsulot modeli endi YAGONA: core/catalog/product.dart
// (Product) — ombor ro'yxati CatalogRepository dan keladi.

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
