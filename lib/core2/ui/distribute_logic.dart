// core2/ui/distribute_logic.dart — «Tarqatish» (matritsa) ekranining SOF
// mantig'i: Flutter'ga bog'liq emas, to'g'ridan-to'g'ri test bilan qoplanadi
// (`test/core2_distribute_logic_test.dart`).
//
// Vazifa (SH5_BIZNES_MANTIQ P14): «Оператор Цех» bir xil tovarlarni «Резка и
// Украшение» dan 4 do'konga kuniga ~24 marta ketma-ket ko'chiradi — SH5 da bu
// 4 ta alohida hujjat, aslida esa BITTA tarqatish vedomosti. Bu yerda
// matritsa (qatorlar = tovarlar, ustunlar = qabul qiluvchi omborlar)
// `POST /docs/quick-batch` tanasiga aylantiriladi (CORE_DEBT_KONTRAKT §3):
//  • 0 yoki bo'sh katak YUBORILMAYDI;
//  • ustunida birorta ham miqdor bo'lmagan ombor uchun hujjat yaratilmaydi;
//  • hujjatlar tartibi — tanlangan omborlar tartibi (xatodagi `details.index`
//    shu tartib bo'yicha ustunni topish uchun ishlatiladi).

/// Matritsa qatori: tovar + yuboriladigan birlik + manba ombordagi qoldiq.
class DistGoodRow {
  final int goodId;
  final String name;

  /// Serverga yuboriladigan birlik kodi (`kg`, `pcs`…) — miqdor esa doim
  /// BUTUN base birlikda ketadi (CORE_DEBT_KONTRAKT: `qty` base'da).
  final String unit;

  /// Manba ombordagi joriy qoldiq (base birlik) — qator jamini solishtirish
  /// uchun.
  final int stock;

  const DistGoodRow({
    required this.goodId,
    this.name = '',
    this.unit = '',
    this.stock = 0,
  });
}

/// Matritsadan qurilgan `quick-batch` so'rovi.
class DistBatch {
  /// Hujjat yaratiladigan omborlar — `docs` bilan BIR XIL tartibda.
  final List<int> dests;

  /// `{"docs": [...]}` ichidagi hujjatlar (`/docs/quick` tanasi bilan aynan).
  final List<Map<String, dynamic>> docs;

  const DistBatch({this.dests = const [], this.docs = const []});

  int get count => docs.length;
  bool get isEmpty => docs.isEmpty;

  /// Xato javobidagi `details.index` → qaysi ombor ustuni (topilmasa null).
  int? destOfIndex(Object? index) {
    final i = index is num ? index.toInt() : int.tryParse('${index ?? ''}');
    if (i == null || i < 0 || i >= dests.length) return null;
    return dests[i];
  }

  /// So'rov tanasi.
  Map<String, dynamic> toJson() => {'docs': docs};
}

/// Bitta ustun (ombor) bo'yicha jami — bo'sh ustunni aniqlash uchun.
int distColumnTotal(
  int skladId,
  Iterable<DistGoodRow> rows,
  int Function(int goodId, int skladId) qtyOf,
) {
  var sum = 0;
  for (final r in rows) {
    final q = qtyOf(r.goodId, skladId);
    if (q > 0) sum += q;
  }
  return sum;
}

/// Ustun (ombor) xulosasi: nechta tovar ketyapti va — BIRLIKLAR BIR XIL
/// bo'lsa — jami miqdor. Aralash birliklarni (kg + dona) qo'shib bo'lmaydi,
/// shuning uchun [qty] `null` bo'ladi va ekranda faqat «N ta tovar» chiqadi.
class DistColumnSummary {
  final int goods;
  final int? qty;
  final String unit;
  const DistColumnSummary({this.goods = 0, this.qty, this.unit = ''});

  bool get isEmpty => goods == 0;
}

DistColumnSummary distColumnSummary(
  int skladId,
  Iterable<DistGoodRow> rows,
  int Function(int goodId, int skladId) qtyOf,
) {
  var goods = 0;
  var sum = 0;
  String? unit;
  var mixed = false;
  for (final r in rows) {
    final q = qtyOf(r.goodId, skladId);
    if (q <= 0) continue;
    goods++;
    sum += q;
    if (unit == null) {
      unit = r.unit;
    } else if (unit != r.unit) {
      mixed = true;
    }
  }
  if (goods == 0) return const DistColumnSummary();
  return DistColumnSummary(
    goods: goods,
    qty: mixed ? null : sum,
    unit: mixed ? '' : (unit ?? ''),
  );
}

/// Bitta qator (tovar) bo'yicha jami — manba ombordan yechiladigan miqdor.
int distRowTotal(
  int goodId,
  Iterable<int> dests,
  int Function(int goodId, int skladId) qtyOf,
) {
  var sum = 0;
  for (final d in dests) {
    final q = qtyOf(goodId, d);
    if (q > 0) sum += q;
  }
  return sum;
}

/// Qator jami qoldiqdan oshib ketdimi (qizil eslatma).
bool distRowOverStock(int rowTotal, int stock) =>
    rowTotal > 0 && rowTotal > stock;

/// Matritsadagi jami nolmas kataklar soni.
int distFilledCells(
  Iterable<DistGoodRow> rows,
  Iterable<int> dests,
  int Function(int goodId, int skladId) qtyOf,
) {
  var n = 0;
  for (final r in rows) {
    for (final d in dests) {
      if (qtyOf(r.goodId, d) > 0) n++;
    }
  }
  return n;
}

/// Eng ko'pi bilan shuncha hujjat bitta so'rovda (§3: 1..20).
const int kDistMaxDocs = 20;

/// Bir vaqtda tanlanadigan omborlar chegarasi (ekran o'qiladigan qolsin).
const int kDistMaxDests = 8;
const int kDistMinDests = 2;

/// Matritsa → `POST /docs/quick-batch` tanasi.
///
/// Bo'sh (hamma katagi 0) ustun TUSHIB QOLADI, 0 kataklar qator bo'lib
/// yuborilmaydi. Takroriy va manbaga teng omborlar chiqarib tashlanadi.
DistBatch distBuildBatch({
  required int fromSklad,
  required List<int> dests,
  required List<DistGoodRow> rows,
  required int Function(int goodId, int skladId) qtyOf,
  String type = 'transfer',
  String docDate = '',
  String comment = '',
}) {
  final outDests = <int>[];
  final outDocs = <Map<String, dynamic>>[];
  final seen = <int>{};
  for (final dest in dests) {
    if (dest == fromSklad || !seen.add(dest)) continue;
    final lines = <Map<String, dynamic>>[];
    for (final r in rows) {
      final q = qtyOf(r.goodId, dest);
      if (q <= 0) continue;
      lines.add({
        'good_id': r.goodId,
        'qty': q,
        if (r.unit.isNotEmpty) 'unit': r.unit,
      });
    }
    if (lines.isEmpty) continue; // bo'sh ustun — hujjat yaratilmaydi
    outDests.add(dest);
    outDocs.add({
      'type': type,
      if (docDate.isNotEmpty) 'doc_date': docDate,
      'from_sklad': fromSklad,
      'to_sklad': dest,
      if (comment.trim().isNotEmpty) 'comment': comment.trim(),
      'lines': lines,
    });
  }
  return DistBatch(dests: outDests, docs: outDocs);
}

/// Yuborishdan oldingi tekshiruv — xato matni (o'zbekcha) yoki null.
String? distValidate({
  required int? fromSklad,
  required List<int> dests,
  required List<DistGoodRow> rows,
  required int Function(int goodId, int skladId) qtyOf,
}) {
  if (fromSklad == null) return 'Qaysi ombordan — tanlang';
  final clean = <int>{};
  for (final d in dests) {
    if (d != fromSklad) clean.add(d);
  }
  if (clean.length < kDistMinDests) {
    return 'Kamida $kDistMinDests ta qabul qiluvchi ombor tanlang';
  }
  if (clean.length > kDistMaxDests) {
    return 'Eng ko\'pi bilan $kDistMaxDests ta ombor tanlanadi';
  }
  if (rows.isEmpty) return 'Kamida bitta tovar qo\'shing';
  final filled = distFilledCells(rows, clean, qtyOf);
  if (filled == 0) return 'Miqdorlar kiritilmagan';
  final docs = clean.where((d) => distColumnTotal(d, rows, qtyOf) > 0).length;
  if (docs > kDistMaxDocs) {
    return 'Bitta yuborishda eng ko\'pi bilan $kDistMaxDocs ta hujjat';
  }
  return null;
}

/// Ogohlantirishlarni HUJJAT bo'yicha guruhlash (natija ekranida «M1: …»).
/// `doc_index` = −1 bo'lganlar `null` kalitiga tushadi.
Map<int?, List<T>> distGroupByDoc<T>(
    Iterable<T> warnings, int Function(T) indexOf) {
  final out = <int?, List<T>>{};
  for (final w in warnings) {
    final i = indexOf(w);
    out.putIfAbsent(i < 0 ? null : i, () => []).add(w);
  }
  return out;
}
