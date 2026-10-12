// Tex karta tannarx matematikasi — YAGONA manba (sof funksiyalar).
// TechCardEditorPage (jonli hisob kataklari) va «Foyda nazorati» ekrani
// (ProfitControlUi) ikkalasi ham shu helperlar bilan hisoblaydi.
//
// Belgilashlar:
//   C0 — 1 dona MASALLIQ tannarxi (bazalar + расходник, tozalash yo'qotishi
//        koeffitsiyentlari qo'llangan) — techIngredientPieceCost.
//   C  — 1 dona TO'LIQ tannarxi = C0 + dop. rasxod — techFullPieceCost.
//
// Narx manbai — GET /api/prices/latest (LatestPrice.unitPrice ENG KICHIK
// birlik narxi: кг/л uchun 1 gr/ml, шт uchun 1 dona, м uchun 1 metr).
//
// шт mahsulot (tuxum, полуфабрикат) tex kartada GRAMMDA ham kiritilishi
// mumkin (unit 'g'): konvert W = techEffectivePieceWeightG («1 шт = X gr»,
// pf uchun tex kartadan, xomga admin kiritadi) orqali — backend bilan mirror.

import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/catalog/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart'
    show normalizeProductType;
import 'package:uz_ai_dev/production/models/latest_price_model.dart';

// Mahsulotlar ro'yxatidan tozalash yo'qotishi koeffitsiyentlari xaritasi
// (faqat factor != 1 bo'lganlar — xarid narxi shu koeffitsiyentga
// ko'paytiriladi, backend /api/production/cost ham xuddi shunday qiladi).
Map<int, double> techWasteFactors(List<Product> products) => {
      for (final p in products)
        if (p.wasteFactor != 1) p.id: p.wasteFactor,
    };

// productId -> mahsulot xaritasi (полуфабрикат qatorlarini aniqlash uchun).
// Ikkala chaqiruvchi (tex karta muharriri va «Foyda nazorati») ham
// ProductProviderAdmin ro'yxatidan bir marta yig'adi.
Map<int, Product> techProductsById(
        List<Product> products) =>
    {for (final p in products) p.id: p};

// Полуфабрикат ichma-ich chuqurligi chegarasi (pf ichida pf ...).
const int kTechPfMaxDepth = 5;

// Partiya JAMI donasi = bitta list donasi (batchQty) × list soni (listQty).
// Retsept (bazalar/расходник miqdorlari) BUTUN partiyani qoplaydi, shuning
// uchun barcha «1 dona» hisoblari SHU songa bo'linadi (batchQty ga emas).
int techTotalPieces(TechCard card) => card.totalPieces;

// Полуфабрикат 1 DONA tannarxi — pf mahsulotning O'Z tex kartasi bo'yicha
// rekursiv hisob (xom qatorlar: oxirgi narx * wasteFactor; ichki pf qatorlar
// yana shu funksiya bilan). null — hisoblab bo'lmaydi: tex karta yo'q/bo'sh,
// batchQty<=0, sikl yoki chuqurlik chegarasi (bunday qator «narxsiz»
// hisoblanadi va mavjud «N ta masalliqda narx yo'q» ogohlantirishiga kiradi).
double? techPfPieceCost(
  Product pf,
  Map<int, LatestPrice> prices,
  Map<int, double> wasteFactors,
  Map<int, Product> products, {
  Set<int>? visited,
  int depth = 0,
}) {
  if (depth >= kTechPfMaxDepth) return null;
  final card = pf.techCard;
  if (card == null || card.batchQty <= 0 || !techCardHasContent(card)) {
    return null;
  }
  final seen = visited ?? <int>{};
  if (!seen.add(pf.id)) return null; // sikl (pf o'zini o'z ichiga oladi)
  try {
    double sum = 0;
    for (final it in card.consumables) {
      sum += techRowCost(it, prices, wasteFactors,
              products: products, visited: seen, depth: depth + 1) ??
          0;
    }
    for (final base in card.bases) {
      for (final it in base.ingredients) {
        sum += techRowCost(it, prices, wasteFactors,
                products: products, visited: seen, depth: depth + 1) ??
            0;
      }
    }
    return sum / techTotalPieces(card);
  } finally {
    seen.remove(pf.id);
  }
}

// Qator «gramm kiritilgan шт mahsulot»mi: шт-oiladagi mahsulot (tuxum, pf)
// tex kartada 'g' birligida yozilgan. Bunday qator gramm -> dona konvertini
// W = techEffectivePieceWeightG («1 шт = X gr») orqali oladi (backend mirror).
bool techIsShtGramRow(TechItem item, Product? p) =>
    p != null && item.unit == 'g' && normalizeProductType(p.unit) == 'шт';

// Qator tannarxi (PARTIYA uchun): amount * unit_price * wasteFactor.
// amount ham, unit_price ham ENG KICHIK birlikda — to'g'ridan-to'g'ri
// ko'paytma. Полуфабрикат qatori (products berilgan va mahsulot
// is_semi_finished): amount * pf 1 dona rekursiv tannarxi.
// Gramm kiritilgan шт qator (techIsShtGramRow): amount/W dona deb hisoblanadi
// (pf: * pf 1 dona tannarxi; xom: * 1 dona narxi * wasteFactor); W<=0 — null.
// null — narx yo'q (product_id=0, hech narxlanmagan yoki pf hisoblanmadi).
double? techRowCost(
  TechItem item,
  Map<int, LatestPrice> prices,
  Map<int, double> wasteFactors, {
  Map<int, Product>? products,
  Set<int>? visited,
  int depth = 0,
}) {
  if (item.productId == 0) return null;
  final pf = products?[item.productId];
  if (pf != null && techIsShtGramRow(item, pf)) {
    final w = techEffectivePieceWeightG(item.productId, products!);
    if (w <= 0) return null; // 1 dona og'irligi noma'lum — narxsiz qator
    if (pf.isPf) {
      final piece = techPfPieceCost(pf, prices, wasteFactors, products,
          visited: visited, depth: depth);
      if (piece == null) return null;
      return item.amount / w * piece;
    }
    final p = prices[item.productId];
    if (p == null) return null;
    return item.amount / w * p.unitPrice * (wasteFactors[item.productId] ?? 1);
  }
  if (pf != null && pf.isPf) {
    final piece = techPfPieceCost(pf, prices, wasteFactors, products!,
        visited: visited, depth: depth);
    if (piece == null) return null;
    return item.amount * piece;
  }
  final p = prices[item.productId];
  if (p == null) return null;
  return item.amount * p.unitPrice * (wasteFactors[item.productId] ?? 1);
}

// Qatorda ko'rsatiladigan «Цена»: g/ml uchun 1 kg/l narxi (x1000),
// pcs/m uchun o'z birligi narxi. Полуфабрикат qatori uchun — pf 1 dona
// rekursiv tannarxi. Gramm kiritilgan шт qator uchun ham 1 kg narxi:
// (1 dona narxi / W) * 1000. null — narx yo'q.
double? techRowUnitPrice(
  TechItem item,
  Map<int, LatestPrice> prices, {
  Map<int, Product>? products,
  Map<int, double> wasteFactors = const {},
}) {
  if (item.productId == 0) return null;
  final pf = products?[item.productId];
  if (pf != null && techIsShtGramRow(item, pf)) {
    final w = techEffectivePieceWeightG(item.productId, products!);
    if (w <= 0) return null;
    final perPiece = pf.isPf
        ? techPfPieceCost(pf, prices, wasteFactors, products)
        : prices[item.productId]?.unitPrice;
    if (perPiece == null) return null;
    return perPiece / w * 1000;
  }
  if (pf != null && pf.isPf) {
    return techPfPieceCost(pf, prices, wasteFactors, products!);
  }
  final p = prices[item.productId];
  if (p == null) return null;
  return (item.unit == 'g' || item.unit == 'ml')
      ? p.unitPrice * 1000
      : p.unitPrice;
}

// Narxi bor qatorlarning yig'indisi (narxsizlar hisobga olinmaydi).
double techItemsCost(
  List<TechItem> items,
  Map<int, LatestPrice> prices,
  Map<int, double> wasteFactors, {
  Map<int, Product>? products,
}) {
  double sum = 0;
  for (final it in items) {
    sum += techRowCost(it, prices, wasteFactors, products: products) ?? 0;
  }
  return sum;
}

// Partiya masalliq tannarxi = barcha bazalar + расходник.
double techBatchCost(
  TechCard card,
  Map<int, LatestPrice> prices,
  Map<int, double> wasteFactors, {
  Map<int, Product>? products,
}) {
  double sum =
      techItemsCost(card.consumables, prices, wasteFactors, products: products);
  for (final base in card.bases) {
    sum += techItemsCost(base.ingredients, prices, wasteFactors,
        products: products);
  }
  return sum;
}

// C0 — 1 dona masalliq tannarxi. batchQty<=0 bo'lsa 0 (hisoblab bo'lmaydi).
double techIngredientPieceCost(
  TechCard card,
  Map<int, LatestPrice> prices,
  Map<int, double> wasteFactors, {
  Map<int, Product>? products,
}) {
  if (card.batchQty <= 0) return 0;
  return techBatchCost(card, prices, wasteFactors, products: products) /
      techTotalPieces(card);
}

// ---- Og'irlik (полуфабрикат / dona qatorlar hissasi bilan) ----
// Backend qoidasi: pcs (dona) qatori baza og'irligiga amount * W qo'shadi,
// bunda W — mahsulotning EFFEKTIV 1 dona og'irligi (quyida). 'g' qatorlar
// TechBase.computedWeightG da allaqachon hisoblangan (ikki marta emas).

// Mahsulotning EFFEKTIV «1 dona og'irligi» (g) — backend bilan bir xil qoida:
// tex kartasi GRAMM rejimida bo'lsa (batch_unit 'g') — kelishuv bo'yicha
// 1 шт = 1 гр (og'irlik retseptdan HISOBLANMAYDI); aks holda tex kartadagi
// og'irlik (piece_weight_g, bo'lmasa mahalliy hisob) — o'sha (pf shu yerga
// kiradi); aks holda mahsulotdagi piece_weight_g («1 шт = X gr», tuxum kabi
// xom шт mahsulot uchun admin kiritadi); yo'q — 0.
int techEffectivePieceWeightG(
  int productId,
  Map<int, Product> products,
) {
  final p = products[productId];
  if (p == null) return 0;
  final card = p.techCard;
  if (card != null) {
    // Гр rejimi: 1 dona = 1 гр. Retsept og'irligi partiya soniga bo'linsa
    // (mas. 5707 гр / 20000 dona) butun songa yaxlitlanib 0 chiqardi —
    // shuning uchun grammda kiritish bloklanib qolgan edi.
    if (card.batchUnit == 'g') return 1;
    final w =
        card.pieceWeightG > 0 ? card.pieceWeightG : card.computedPieceWeightG;
    if (w > 0) return w;
  }
  return p.pieceWeightG;
}

// pf mahsulotning 1 dona og'irligi (g) — FAQAT полуфабрикат uchun (pf
// bo'lmasa 0). Umumiy qoida: techEffectivePieceWeightG.
int techPfPieceWeightG(int productId, Map<int, Product> products) {
  final p = products[productId];
  if (p == null || !p.isPf) return 0;
  return techEffectivePieceWeightG(productId, products);
}

// Bazaning pcs (dona) qatorlari qo'shadigan og'irligi (g): amount * W —
// pf qatori ham, «1 шт = X gr» belgilangan xom шт qatori (tuxum) ham.
int techBaseExtraWeightG(
  TechBase base,
  Map<int, Product> products,
) {
  int sum = 0;
  for (final it in base.ingredients) {
    if (it.unit == 'pcs') {
      sum += it.amount * techEffectivePieceWeightG(it.productId, products);
    }
  }
  return sum;
}

// Baza og'irligi = g/ml yig'indisi + pcs (pf/dona) qatorlar hissasi.
int techBaseWeightG(TechBase base, Map<int, Product> products) =>
    base.computedWeightG + techBaseExtraWeightG(base, products);

// Partiya og'irligi = barcha bazalar (pf hissasi bilan).
int techBatchWeightG(TechCard card, Map<int, Product> products) {
  int sum = 0;
  for (final base in card.bases) {
    sum += techBaseWeightG(base, products);
  }
  return sum;
}

// 1 dona og'irligi (pf hissasi bilan) — partiya JAMI donasiga bo'linadi.
int techPieceWeightG(TechCard card, Map<int, Product> products) =>
    card.batchQty > 0
        ? techBatchWeightG(card, products) ~/ techTotalPieces(card)
        : 0;

// Dop. rasxod 1 dona uchun (so'm). 'percent' — C0 dan foiz, 'sum' — so'm,
// belgilanmagan ('') — 0.
double techOverheadPerPiece(String mode, double value, double c0) {
  if (mode == 'percent') return c0 * value / 100;
  if (mode == 'sum') return value;
  return 0;
}

// C — 1 dona TO'LIQ tannarx = C0 + dop. rasxod.
double techFullPieceCost(String overheadMode, double overheadValue, double c0) =>
    c0 + techOverheadPerPiece(overheadMode, overheadValue, c0);

// 1 dona foyda (so'm) — TO'LIQ tannarx C ga nisbatan.
// null — foyda belgilanmagan yoki percent rejimida C noma'lum/0.
double? techProfitPerPiece(String mode, double value, double fullCost) {
  if (mode == 'sum') return value;
  if (mode == 'percent') {
    if (fullCost <= 0) return null;
    return fullCost * value / 100;
  }
  return null;
}

// Foyda foizda (C ga nisbatan). null — hisoblab bo'lmaydi.
double? techProfitPercent(String mode, double value, double fullCost) {
  if (mode == 'percent') return value;
  if (mode == 'sum') {
    if (fullCost <= 0) return null;
    return value * 100 / fullCost;
  }
  return null;
}

// Eng yaqin 1000 ga yaxlitlash: 287 634 -> 288 000, 287 400 -> 287 000.
int roundTo1000(double v) => (v / 1000).round() * 1000;

// Tavsiya etiladigan sotish narxi = roundTo1000(C + foyda).
// null — foyda belgilanmagan yoki C noma'lum/0.
int? techSuggestedSalePrice(
  String profitMode,
  double profitValue,
  double fullCost,
) {
  if (fullCost <= 0) return null;
  final profit = techProfitPerPiece(profitMode, profitValue, fullCost);
  if (profit == null) return null;
  return roundTo1000(fullCost + profit);
}

// Marja foizi: (narx − C) / C × 100. null — C noma'lum/0.
double? techMarginPercent(num salePrice, double fullCost) {
  if (fullCost <= 0) return null;
  return (salePrice - fullCost) / fullCost * 100;
}

// Tex kartada tarkib bormi (bo'sh kartalar «Foyda nazorati»ga kirmaydi).
bool techCardHasContent(TechCard? card) {
  if (card == null) return false;
  return card.bases.any((b) => b.ingredients.isNotEmpty) ||
      card.consumables.isNotEmpty;
}

// Sotish narxi ALMASHTIRILISHI kerak mahsulotlar soni: tavsiya hisoblanadi
// va saqlangan sale_price dan farq qiladi (hali belgilanmagani ham kiradi).
// Admin bosh sahifadagi badge va «Foyda nazorati» shu qoida bilan ishlaydi.
int techPriceReplaceCount(
  List<Product> products,
  Map<int, LatestPrice> prices,
) {
  if (prices.isEmpty) return 0;
  final wasteFactors = techWasteFactors(products);
  final byId = techProductsById(products);
  int n = 0;
  for (final p in products) {
    // Полуфабрикат sotilmaydi — sotish narxi nazoratiga kirmaydi.
    if (p.isPf) continue;
    final card = p.techCard;
    if (!techCardHasContent(card)) continue;
    final c0 =
        techIngredientPieceCost(card!, prices, wasteFactors, products: byId);
    final full = techFullPieceCost(card.overheadMode, card.overheadValue, c0);
    final suggested =
        techSuggestedSalePrice(card.profitMode, card.profitValue, full);
    if (suggested != null && suggested > 0 && suggested != card.salePrice) n++;
  }
  return n;
}
