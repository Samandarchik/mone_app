// admin/ui/widgets/tech_card_section.dart — тех карта editori sub-fayli:
// TechCardController — muharrir holatini (batchQty, bases, consumables,
// profit/overhead, salePrice) boshqaradi va build() bilan TechCard yig'adi.
import 'package:uz_ai_dev/admin/model/tech_card.dart';

// Tex karta (тех карта) holatini boshqaradigan controller.
// Parent ekran shuni yaratadi, save paytida build() chaqiradi va dispose qiladi.
// Tex karta TAHRIRI endi faqat TechCardEditorPage (Excel-uslub sahifa) da —
// eski inline TechCardSection vidjeti va unga qarashli base/consumables
// sahifalari o'lik kod sifatida o'chirilgan.
class TechCardController {
  int batchQty;
  // batchQty birligi: '' (шт) | 'g' (полуфабрикат; 1 шт = 1 гр kelishuvi).
  String batchUnit;
  // Shakl: '' | 'round' (diameterCm) | 'rect' (widthCm × lengthCm).
  String shape;
  int? diameterCm;
  int? widthCm;
  int? lengthCm;
  int? heightCm; // balandlik, sm (round va rect uchun)
  int listQty; // partiyada nechta list (противень); kamida 1
  // Bo'limlar (bosqichlar) — tex karta muharriridagi «Bo'limlar» qatori.
  final List<TechStage> stages;
  final List<TechBase> bases;
  final List<TechItem> consumables;

  // Foyda (ustama): '' | 'percent' | 'sum' va qiymati (foiz yoki so'm/dona).
  String profitMode;
  double profitValue;

  // Dop. rasxod: '' | 'percent' (C0 dan foiz) | 'sum' (so'm/dona) va qiymati.
  String overheadMode;
  double overheadValue;

  // Tasdiqlangan sotish narxi (so'm/dona, 0 — belgilanmagan). Faqat admin
  // «Almashtirish» bosganda o'zgaradi.
  int salePrice;

  // Pishirish vaqti/harorati — muharrirda tahrirlanmaydi, faqat karta
  // qayta yig'ilganda yo'qolmasligi uchun o'tkaziladi.
  int bakeTimeMin;
  int bakeTempC;

  // Tayyor biskvit fotosi ("/static/..." yoki '') — tex kartada saqlanadi.
  String biscuitPhotoUrl;

  // Palitradan tanlangan nachinka rangi ("#RRGGBB" yoki '').
  String fillingColor;

  // Pastki (2-) nachinka qatlami rangi ("#RRGGBB" yoki '').
  String fillingColor2;

  // «Покрытие» uchun palitradan tanlangan rang ("#RRGGBB" yoki '').
  String coatingColor;

  TechCardController([TechCard? initial])
      : batchQty = (initial?.batchQty ?? 1) < 1 ? 1 : (initial?.batchQty ?? 1),
        batchUnit = initial?.batchUnit == 'g' ? 'g' : '',
        shape = normalizeTechShape(initial?.shape),
        diameterCm = initial?.diameterCm,
        widthCm = initial?.widthCm,
        lengthCm = initial?.lengthCm,
        heightCm = initial?.heightCm,
        listQty = (initial?.listQty ?? 1) < 1 ? 1 : (initial?.listQty ?? 1),
        stages = List<TechStage>.from(initial?.stages ?? const []),
        bases = List<TechBase>.from(initial?.bases ?? const []),
        consumables = List<TechItem>.from(initial?.consumables ?? const []),
        profitMode = initial?.profitMode ?? '',
        profitValue = initial?.profitValue ?? 0,
        overheadMode = initial?.overheadMode ?? '',
        overheadValue = initial?.overheadValue ?? 0,
        salePrice = initial?.salePrice ?? 0,
        bakeTimeMin = initial?.bakeTimeMin ?? 0,
        bakeTempC = initial?.bakeTempC ?? 0,
        biscuitPhotoUrl = initial?.biscuitPhotoUrl ?? '',
        fillingColor = initial?.fillingColor ?? '',
        fillingColor2 = initial?.fillingColor2 ?? '',
        coatingColor = initial?.coatingColor ?? '';

  // Partiya JAMI donasi = bitta list donasi (batchQty) × list soni (listQty).
  // Barcha «1 dona» / «за N штук» hisob-ko'rsatishlar shu songa tayanadi.
  int get totalPieces =>
      (batchQty < 1 ? 1 : batchQty) * (listQty < 1 ? 1 : listQty);

  // To'liq TechCard ni yig'ib qaytaradi (weight maydonlari mahalliy hisoblanadi).
  TechCard build() => TechCard(
        batchQty: batchQty < 1 ? 1 : batchQty,
        batchUnit: batchUnit == 'g' ? 'g' : '',
        shape: normalizeTechShape(shape),
        diameterCm: diameterCm,
        widthCm: widthCm,
        lengthCm: lengthCm,
        heightCm: heightCm,
        listQty: listQty < 1 ? 1 : listQty,
        stages: List<TechStage>.from(stages),
        bases: List<TechBase>.from(bases),
        consumables: List<TechItem>.from(consumables),
        profitMode: profitMode,
        profitValue: profitValue,
        overheadMode: overheadMode,
        overheadValue: overheadValue,
        salePrice: salePrice,
        bakeTimeMin: bakeTimeMin,
        bakeTempC: bakeTempC,
        biscuitPhotoUrl: biscuitPhotoUrl,
        fillingColor: fillingColor,
        fillingColor2: fillingColor2,
        coatingColor: coatingColor,
      );

  // «Состав» uchun showInSostav=true bo'lgan nomlar.
  List<String> sostavNames({TechCard? Function(int productId)? pfCard}) =>
      build().sostavNames(pfCard: pfCard);

  void dispose() {}
}
