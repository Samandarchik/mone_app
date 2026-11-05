import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';

/// Formani tez to'ldirish uchun andozalar. API'da yangi mahsulot turi emas.
enum ProductTemplate {
  ingredient(
      'Xomashyo', 'Un, shakar, tuxum, qadoq', ProductKind.raw, false, true),
  resale('Tayyor olib sotamiz', 'Ichimlik, shokolad, sotib olingan tovar',
      ProductKind.raw, true, true),
  preparation(
      'Yarim tayyor mahsulot',
      'Krem, biskvit, sirop — boshqa retsept uchun',
      ProductKind.pf,
      false,
      false),
  finished('O‘zimiz tayyorlaymiz', 'Tort, pirojnoe, non — retsept bo‘yicha',
      ProductKind.product, true, false);

  const ProductTemplate(
      this.label, this.hint, this.kind, this.sellable, this.purchasable);
  final String label;
  final String hint;
  final ProductKind kind;
  final bool sellable;
  final bool purchasable;
}

/// Faqat forma holati. Product — katalogdagi yagona saqlanadigan model.
/// Retsept va narxlar bu forma tomonidan qayta qurilmaydi.
class ProductFormDraft {
  ProductFormDraft(this.original)
      : name = original.name,
        categoryId = original.categoryId,
        unit = original.unit,
        kind = original.kind,
        sellable = original.sellable,
        purchasable = original.purchasable,
        filials = List.of(original.filials),
        sklads = List.of(original.sklads),
        sources = Set.of(original.sources),
        sellStep = _quantity(original.sellStep, original.unit),
        buyStep = _quantity(original.buyStep, original.unit),
        wasteBase = _number(original.wasteBase),
        wasteAmount = _number(original.wasteAmount),
        pieceWeight = _number(original.pieceWeightG),
        sostav = original.sostav,
        companyName = original.companyName,
        imageUrl = original.imageUrl;

  final Product original;
  String name, unit, sellStep, buyStep, wasteBase, wasteAmount, pieceWeight;
  String sostav, companyName, imageUrl;
  int categoryId;
  ProductKind kind;
  bool sellable, purchasable;
  final List<int> filials, sklads;
  final Set<String> sources;
  (bool, bool)? _channelsBeforePreparation;

  static String _number(int value) => value == 0 ? '' : '$value';
  static String _quantity(int value, String unit) =>
      value == 0 ? '' : formatQty(value, unit);

  bool get hasSales => kind != ProductKind.pf && sellable;
  bool get hasPurchases => kind != ProductKind.pf && purchasable;
  bool get usesWaste => qtyUnitFactor(unit) == 1000;
  bool get usesPieceWeight => unit == 'шт' && kind != ProductKind.pf;
  String get wasteUnit => unit == 'л' ? 'ml' : 'g';

  void applyTemplate(ProductTemplate template) {
    kind = template.kind;
    sellable = template.sellable;
    purchasable = template.purchasable;
    _channelsBeforePreparation = null;
    // Andoza kiritilgan birlik/miqdorlarni o'zgartirmaydi.
  }

  void changeKind(ProductKind value) {
    if (kind == value) return;
    if (value == ProductKind.pf) {
      _channelsBeforePreparation = (sellable, purchasable);
      sellable = purchasable = false;
    } else if (kind == ProductKind.pf && _channelsBeforePreparation != null) {
      sellable = _channelsBeforePreparation!.$1;
      purchasable = _channelsBeforePreparation!.$2;
      _channelsBeforePreparation = null;
    }
    kind = value;
  }

  /// Faqat aniq saqlanadigan musbat miqdorlar; bo'sh = mavjud default qoida.
  static int? parseStep(String text, String unit) {
    final value = text.trim().replaceAll(',', '.');
    if (value.isEmpty) return 0;
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    final scaled = parsed * qtyUnitFactor(unit);
    if (!scaled.isFinite || scaled > 9007199254740991) return null;
    final rounded = scaled.round();
    if (rounded <= 0 || (scaled - rounded).abs() > 0.000001) return null;
    return rounded;
  }

  static int? _whole(String text) {
    if (text.trim().isEmpty) return 0;
    if (!RegExp(r'^\d+$').hasMatch(text.trim())) return null;
    final value = int.tryParse(text.trim());
    return value != null && value <= 9007199254740991 ? value : null;
  }

  Map<String, String> validate() {
    final errors = <String, String>{};
    if (name.trim().isEmpty) errors['name'] = 'Mahsulot nomini kiriting';
    if (categoryId <= 0) errors['category'] = 'Kategoriyani tanlang';
    if (unit.isEmpty) errors['unit'] = 'O‘lchov birligini tanlang';
    final stepError = qtyUnitFactor(unit) == 1000
        ? 'Musbat miqdor kiriting (eng kam 0.001 $unit)'
        : 'Musbat butun miqdor kiriting';
    if (hasSales) {
      if (filials.isEmpty) errors['filials'] = 'Sotuv uchun filial tanlang';
      if (parseStep(sellStep, unit) == null) errors['sellStep'] = stepError;
    }
    if (hasPurchases) {
      if (sklads.isEmpty) errors['sklads'] = 'Xarid uchun ombor tanlang';
      if (sources.isEmpty) errors['sources'] = 'Xarid uchun manba tanlang';
      if (parseStep(buyStep, unit) == null) errors['buyStep'] = stepError;
    }
    if (usesWaste) {
      final base = _whole(wasteBase);
      final loss = _whole(wasteAmount);
      if (base == null ||
          loss == null ||
          !((base == 0 && loss == 0) || (base > 0 && loss < base))) {
        errors['waste'] =
            'Yo‘qotish boshlang‘ich miqdordan kichik bo‘lsin; butun $wasteUnit kiriting';
      }
    }
    if (usesPieceWeight && _whole(pieceWeight) == null) {
      errors['pieceWeight'] = 'Dona og‘irligini butun grammda kiriting';
    }
    return errors;
  }

  Product build() {
    final errors = validate();
    if (errors.isNotEmpty) throw StateError(errors.values.join('\n'));
    return original.copyWith(
      name: name.trim(), categoryId: categoryId, unit: unit, kind: kind,
      sellable: hasSales, purchasable: hasPurchases,
      filials: List.of(filials), sklads: List.of(sklads),
      sources: sources.toList(),
      sellStep: hasSales ? parseStep(sellStep, unit)! : original.sellStep,
      buyStep: hasPurchases ? parseStep(buyStep, unit)! : original.buyStep,
      // Yashirilgan maydonlar o'chirilmaydi: kanal/tur qayta yoqilishi mumkin.
      wasteBase: usesWaste ? _whole(wasteBase)! : original.wasteBase,
      wasteAmount: usesWaste ? _whole(wasteAmount)! : original.wasteAmount,
      pieceWeightG:
          usesPieceWeight ? _whole(pieceWeight)! : original.pieceWeightG,
      sostav: sostav.trim(), companyName: companyName.trim(),
      imageUrl: imageUrl,
    );
  }
}
