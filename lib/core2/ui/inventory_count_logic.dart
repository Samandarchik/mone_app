// core2/ui/inventory_count_logic.dart — «Sanash» (inventarizatsiya) oson
// rejimining SOF mantig'i: Flutter'ga bog'liq emas, shuning uchun to'g'ridan-
// to'g'ri test bilan qoplanadi (`test/core2_inventory_count_logic_test.dart`).
//
// Bu yerda:
//  • ommaviy to'ldirish rejasi — «Hammasini 0» (xarajat yopish, SH5 dagi
//    «Хозы обнулить») va «Hammasini hisobdagidek»; QOIDA: fakt KIRITILGAN
//    qator hech qachon ustidan yozilmaydi;
//  • bekor qilish (undo) holati — oldingi faktlar va izoh;
//  • guruh (toifa) rejimi — SH5 da sanoq shablon bo'yicha ketadi
//    («выпечка», «напитки», «хозтовары»), tanlangan toifalar qamrovi;
//  • taom/p-f qatorining `flag` qoidasi (LEDGER.md) — TEGILMAGAN holat
//    bugungi xatti-harakatni AYNAN saqlaydi;
//  • hujjat izohi: prefikslar («[nolga tushirish] », «[topshirildi] ») va
//    toifa nomlari — takror qo'shilmaydi (avto-saqlash qayta-qayta chaqiradi).

/// Izoh prefiksi: butun ombor nolga tushirildi (oy yopish xarajati).
const String kInvZeroTag = '[nolga tushirish]';

/// Izoh prefiksi: sanoqchi (post ruxsatisiz xodim) sanoqni topshirdi.
const String kInvHandoverTag = '[topshirildi]';

/// Ommaviy to'ldirishning bitta nishoni: `goodId` qatoriga `value` matni
/// (tovarning ko'rsatish birligida, masalan «0» yoki «2,5») yoziladi.
class InvFillTarget {
  final int goodId;
  final String value;

  /// Hisob qoldig'i (base birlik) — dialogda summa hisoblash uchun.
  final int current;

  /// 1 base birlik narxi (`stock.cost.view` bo'lsa) — dialogdagi summa.
  final int? price;

  const InvFillTarget({
    required this.goodId,
    required this.value,
    this.current = 0,
    this.price,
  });

  /// Shu qatorda hisobdan chiqadigan summa (butun so'm).
  int get amount => (price ?? 0) * current;
}

/// «Hammasini 0» / «Hammasini hisobdagidek» rejasi.
///
/// [scope] — joriy filtr (hammasi / tanlangan toifalar / qidiruv) qatorlari,
/// [factOf] — shu tovarga hozir kiritilgan fakt matni (`null` yoki bo'sh —
/// sanalmagan). Kiritilgan qator natijaga TUSHMAYDI: xodim qo'l bilan yozgan
/// son hech qachon yo'qolmaydi.
List<InvFillTarget> invPlanBulkFill(
  Iterable<InvFillTarget> scope,
  String? Function(int goodId) factOf,
) {
  final out = <InvFillTarget>[];
  final seen = <int>{};
  for (final t in scope) {
    if (!seen.add(t.goodId)) continue; // takror qator
    final cur = factOf(t.goodId);
    if (cur != null && cur.trim().isNotEmpty) continue; // sanalgan — tegilmaydi
    out.add(t);
  }
  return out;
}

/// Ommaviy to'ldirishdan oldingi holat (xotirada) — «Bekor qilish» uchun.
class InvBulkUndo {
  /// good_id → oldingi fakt matni (`''` — sanalmagan edi).
  final Map<int, String> previous;

  /// Oldingi «nolga tushirish» belgisi.
  final bool wasZeroed;

  const InvBulkUndo({required this.previous, this.wasZeroed = false});

  bool get isEmpty => previous.isEmpty;
  int get count => previous.length;
}

/// Rejadan undo holatini qurish (yozishdan OLDIN chaqiriladi).
InvBulkUndo invUndoOf(
  Iterable<InvFillTarget> plan,
  String? Function(int goodId) factOf, {
  bool wasZeroed = false,
}) =>
    InvBulkUndo(
      previous: {
        for (final t in plan) t.goodId: factOf(t.goodId) ?? '',
      },
      wasZeroed: wasZeroed,
    );

/// Taraqqiyot: qamrovdagi qatorlar soni va sanalganlari.
class InvProgress {
  final int total;
  final int counted;
  const InvProgress(this.total, this.counted);

  int get uncounted => total - counted;
  double get ratio => total == 0 ? 0 : counted / total;
}

/// Qamrovdagi (guruh rejimi hisobga olingan) qatorlar bo'yicha taraqqiyot.
InvProgress invProgress(
  Iterable<int> goodIds,
  bool Function(int goodId) isCounted,
) {
  var total = 0;
  var counted = 0;
  for (final id in goodIds) {
    total++;
    if (isCounted(id)) counted++;
  }
  return InvProgress(total, counted);
}

/// Toifa qamrovi: tanlangan toifalar BO'SH bo'lsa — hamma qator kiradi.
bool invInGroupScope(Set<String> selected, String group) =>
    selected.isEmpty || selected.contains(group);

/// Qatorlarni tanlangan toifalar bo'yicha filtrlash (bo'sh tanlov — hammasi).
List<T> invScopeRows<T>(
  Iterable<T> rows,
  Set<String> selected,
  String Function(T row) groupOf,
) =>
    [
      for (final r in rows)
        if (invInGroupScope(selected, groupOf(r))) r,
    ];

/// Inventar qatoridagi `flag` (LEDGER.md / API_V2.md):
/// **1 = tayyor fakt** — taom/p-f O'ZI hisobga olinadi, retsept bo'yicha
/// yoyilmaydi; **0 = xom qator** — retseptli taom omborda o'zi bo'lmasa
/// ingredientlarga yoyiladi.
///
/// [expand] — foydalanuvchi tanlovi:
///  • `null` — almashtirgichga TEGILMAGAN: bugungi xatti-harakat (komplekt
///    tovar → 1, qolganlari → 0) AYNAN saqlanadi;
///  • `false` — «o'zi» (1);
///  • `true` — «tarkibi» (0).
/// Komplekt bo'lmagan tovarda tanlov ahamiyatsiz — doim 0.
int invLineFlag({required bool isComplect, bool? expand}) {
  if (!isComplect) return 0;
  if (expand == null) return 1;
  return expand ? 0 : 1;
}

/// Izohdagi prefikslar ajratilgan holati.
class InvComment {
  /// Prefikssiz (sof) izoh — foydalanuvchi/SH5 matni, toifa nomlari ham shunda.
  final String base;
  final bool zeroed;
  final bool handover;

  const InvComment({this.base = '', this.zeroed = false, this.handover = false});

  /// Qoralamadan qaytganda izohni qismlarga ajratish (prefikslar takror
  /// qo'shilmasin).
  factory InvComment.parse(String raw) {
    var s = raw.trim();
    var zeroed = false;
    var handover = false;
    var changed = true;
    while (changed) {
      changed = false;
      if (s.startsWith(kInvZeroTag)) {
        zeroed = true;
        s = s.substring(kInvZeroTag.length).trimLeft();
        changed = true;
      }
      if (s.startsWith(kInvHandoverTag)) {
        handover = true;
        s = s.substring(kInvHandoverTag.length).trimLeft();
        changed = true;
      }
    }
    return InvComment(base: s, zeroed: zeroed, handover: handover);
  }
}

/// Hujjat izohini qurish: prefikslar + sof izoh + toifa nomlari + eslatma.
/// Avto-saqlash bir necha marta chaqiradi — natija DOIM bir xil bo'ladi
/// (prefiks yoki toifa nomi takror qo'shilmaydi).
String invBuildComment({
  String base = '',
  bool zeroed = false,
  bool handover = false,
  Iterable<String> groups = const [],
  String note = '',
}) {
  final b = base.trim();
  final lower = b.toLowerCase();
  final tail = <String>[];
  for (final g in groups) {
    final n = g.trim();
    if (n.isEmpty) continue;
    if (lower.contains(n.toLowerCase())) continue;
    if (tail.any((t) => t.toLowerCase() == n.toLowerCase())) continue;
    tail.add(n);
  }
  final noteText = note.trim();
  final body = [
    if (b.isNotEmpty) b,
    if (tail.isNotEmpty) tail.join(', '),
    if (noteText.isNotEmpty && !lower.contains(noteText.toLowerCase())) noteText,
  ].join(' · ');
  final tags = [
    if (zeroed) kInvZeroTag,
    if (handover) kInvHandoverTag,
  ].join(' ');
  return [
    if (tags.isNotEmpty) tags,
    if (body.isNotEmpty) body,
  ].join(' ');
}

/// Sanoqchi topshirgan qoralamami (tekshiruvchining «Kutilmoqda» ro'yxati).
bool invIsHandover(String comment) => comment.contains(kInvHandoverTag);

/// Butun ombor nolga tushirilgan hujjatmi.
bool invIsZeroed(String comment) => comment.contains(kInvZeroTag);
