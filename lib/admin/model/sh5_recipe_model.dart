// admin/model/sh5_recipe_model.dart — SH5 (StoreHouse) kalkulyatsiyasi =
// «retsept» modellari: taomga mos retsept, uning ingredientlari + har
// ingredientning Mone mahsulotiga moslash natijasi va retseptni tex karta
// qilib qo'llash (apply) xatosi.
//
// Kontrakt (PLAN_RETSEPT §3):
//   GET /api/sh5/recipes/by-dish/{dish_guid} — {cmp_rid, cmp_guid, name, unit,
//   group, ingredients:[{rid, name, unit, qty_micro, matched_product_id,
//   matched_product_name}]}; retsept yo'q bo'lsa 404 (UI bo'limni ko'rsatmaydi).
//   POST /api/sh5/recipes/apply {dish_guid, overwrite} — 409: mavjud tex karta
//   yoki mos kelmagan ingredientlar ro'yxati.
//
// MIQDOR KONTRAKTI: `qty_micro` = qty × 1 000 000, BUTUN son (float
// saqlanmaydi/yuborilmaydi). Ko'rsatish — [sh5FormatQtyMicro]: Кг/Литр → /1000
// va butun «g»/«ml», boshqa birlik → /1e6 (keraksiz kasrsiz).

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ??
      (double.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
}

String _asString(dynamic v) => v?.toString() ?? '';

/// qty_micro → o'qiladigan miqdor matni (birligi bilan).
///
/// Кг/Литр — 1/1000 (ya'ni gramm/millilitr) BUTUN son; qolgan birliklar
/// (шт, Порция...) — 1/1 000 000, keraksiz kasr nollarisiz.
String sh5FormatQtyMicro(int qtyMicro, String unit) {
  final u = unit.trim().toLowerCase();
  final isKg = u.startsWith('кг') || u == 'kg';
  final isLitre =
      u.startsWith('литр') || u == 'л' || u == 'l' || u.startsWith('lit');
  if (isKg) return '${(qtyMicro / 1000).round()} g';
  if (isLitre) return '${(qtyMicro / 1000).round()} ml';

  var text = (qtyMicro / 1000000).toStringAsFixed(3);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  final suffix = unit.trim();
  return suffix.isEmpty ? text : '$text $suffix';
}

/// Retseptning bitta ingredienti + Mone mahsulotiga moslash natijasi.
class Sh5RecipeIngredient {
  final int rid;
  final String name;
  final String unit;
  final int qtyMicro; // qty × 1 000 000, BUTUN
  final int matchedProductId; // 0 = mos mahsulot topilmadi
  final String matchedProductName;

  const Sh5RecipeIngredient({
    required this.rid,
    required this.name,
    this.unit = '',
    this.qtyMicro = 0,
    this.matchedProductId = 0,
    this.matchedProductName = '',
  });

  /// Mone mahsuloti topilganmi (topilmasa apply 409 beradi).
  bool get matched => matchedProductId > 0;

  /// Ro'yxatda ko'rsatiladigan miqdor (masalan «210 g», «1 Порция»).
  String get qtyLabel => sh5FormatQtyMicro(qtyMicro, unit);

  factory Sh5RecipeIngredient.fromJson(Map<String, dynamic> json) {
    // Backend moslashni yassi (matched_product_id/name) yoki ichma-ich
    // (matched_product:{id,name}) berishi mumkin — ikkalasi ham o'qiladi.
    final nested = json['matched_product'];
    final nestedMap = nested is Map ? Map<String, dynamic>.from(nested) : null;
    return Sh5RecipeIngredient(
      rid: _asInt(json['rid']),
      name: _asString(json['name'] ?? json['ingredient']),
      unit: _asString(json['unit']),
      qtyMicro: _asInt(json['qty_micro'] ?? json['qty']),
      matchedProductId:
          _asInt(json['matched_product_id'] ?? nestedMap?['id'] ?? 0),
      matchedProductName:
          _asString(json['matched_product_name'] ?? nestedMap?['name']),
    );
  }
}

/// Taomga mos SH5 retsepti (komplekt) — ingredientlari bilan.
class Sh5DishRecipe {
  final int cmpRid;
  final String cmpGuid;
  final String name;
  final String unit;
  final String group;
  final List<Sh5RecipeIngredient> ingredients;

  const Sh5DishRecipe({
    this.cmpRid = 0,
    this.cmpGuid = '',
    this.name = '',
    this.unit = '',
    this.group = '',
    this.ingredients = const [],
  });

  /// Mos mahsulot topilmagan ingredient nomlari (bo'sh — hammasi mos).
  List<String> get unmatchedNames => ingredients
      .where((e) => !e.matched)
      .map((e) => e.name)
      .toList(growable: false);

  factory Sh5DishRecipe.fromJson(Map<String, dynamic> json) {
    // Javob {recipe:{...}} yoki to'g'ridan-to'g'ri retsept obyekti bo'lishi
    // mumkin; ingredientlar ikkala darajada ham qidiriladi.
    final inner = json['recipe'];
    final map = inner is Map ? Map<String, dynamic>.from(inner) : json;
    final rawIngredients = map['ingredients'] ?? json['ingredients'];
    return Sh5DishRecipe(
      cmpRid: _asInt(map['cmp_rid']),
      cmpGuid: _asString(map['cmp_guid']),
      name: _asString(map['name']),
      unit: _asString(map['unit']),
      group: _asString(map['group']),
      ingredients: rawIngredients is List
          ? rawIngredients
              .whereType<Map>()
              .map((e) =>
                  Sh5RecipeIngredient.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

/// `POST /api/sh5/recipes/apply` ning 409 javobi: yo mahsulotda tex karta bor
/// (overwrite:true bilan qayta yuboriladi), yo ingredientlar mos kelmadi.
class Sh5RecipeApplyException implements Exception {
  final String message;
  final List<String> unmatched;

  const Sh5RecipeApplyException(this.message, {this.unmatched = const []});

  /// Mavjud tex karta sababli rad etilgan (mos kelmagan ingredient yo'q).
  bool get techCardExists => unmatched.isEmpty;

  @override
  String toString() => message;

  /// 409 javob tanasidan yig'ish: `unmatched` yassi (`{unmatched:[...]}`) yoki
  /// envelope ichida (`{data:{unmatched:[...]}}`), element satr yoki
  /// `{name:...}` bo'lishi mumkin.
  factory Sh5RecipeApplyException.fromResponse(dynamic body, String message) {
    final names = <String>[];
    if (body is Map) {
      final data = body['data'];
      final raw = body['unmatched'] ??
          (data is Map ? data['unmatched'] : null) ??
          body['unmatched_ingredients'];
      if (raw is List) {
        for (final item in raw) {
          final name = item is Map
              ? _asString(item['name'] ?? item['ingredient'])
              : _asString(item);
          if (name.isNotEmpty) names.add(name);
        }
      }
    }
    return Sh5RecipeApplyException(message, unmatched: names);
  }
}
