// bugalter/model/sh5_kirim_model.dart — «SH5 kirim» (bozor → SH5 «Приходная
// накладная») modellari, PLAN_KIRIM §4.3 kontrakti bo'yicha.
//
// Kontrakt (qisqacha):
//   GET  /api/sh5/kirim/day?date=      → Sh5KirimDay
//   GET  /api/sh5/kirim/goods?q=       → {items:[Sh5KirimGood]}
//   GET  /api/sh5/kirim/docs?date=     → {docs:[Sh5KirimDoc]}
//   GET  /api/sh5/kirim/credentials    → Sh5KirimCredentials (parolsiz!)
//   GET  /api/sh5/kirim/settings       → Sh5KirimSettings
//
// MUHIM (son kontrakti): `qty_milli` — кг/л mahsulot uchun гр/мл BUTUN son,
// boshqalari o'z birligida. Ko'rsatish uchun server tayyor `qty_display`
// matnini beradi — ilova o'zi BO'LMAYDI (bo'linish serverda).
// Pul (`subtotal`, `total`) — BUTUN so'm.

// ─────────────────────────── JSON yordamchilari ───────────────────────────

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  final s = v?.toString() ?? '';
  return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String _asStr(dynamic v) => v?.toString() ?? '';

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase();
  return s == 'true' || s == '1';
}

DateTime? _asDate(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

List<Map<String, dynamic>> _asMaps(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

// ─────────────────────────── Doimiy qiymatlar ───────────────────────────

/// SH5 hujjatining holati (`doc.status`).
abstract final class Sh5KirimStatus {
  static const String queued = 'queued'; // navbatda
  static const String sending = 'sending'; // bridge yuboryapti
  static const String done = 'done'; // SH5 da yaratildi
  static const String error = 'error'; // xato (qayta yuborsa bo'ladi)
}

/// Mapping manbai (`map.source`) — ustuvorlik: manual > learned.
abstract final class Sh5KirimMapSource {
  static const String manual = 'manual'; // bugalter qo'lda bog'lagan
  static const String learned = 'learned'; // tarixdan o'rganilgan
}

/// Buyurtma manbalari (settings: manba ↔ kontragent). `''` — «boshqa»
/// (default kontragent ishlatiladi).
const List<String> kSh5KirimSources = ['samarqand', 'toshkent', 'zagranitsa', ''];

/// Manba kodining o'zbekcha nomi (dropdown/sarlavha uchun).
String sh5KirimSourceName(String source) {
  switch (source) {
    case 'samarqand':
      return 'Samarqand';
    case 'toshkent':
      return 'Toshkent';
    case 'zagranitsa':
      return 'Zagranitsa';
    default:
      return 'Boshqa';
  }
}

// ─────────────────────────── Kun javobi ───────────────────────────

/// Bitta Mone mahsuloti ↔ SH5 tovari bog'lanishi (`item.map`).
class Sh5KirimMap {
  final int sh5Rid;
  final String sh5Name;
  final String sh5UnitName;

  /// `manual` yoki `learned` ([Sh5KirimMapSource]).
  final String source;

  /// `learned` uchun — necha marta tarixda uchragani.
  final int confidence;

  const Sh5KirimMap({
    required this.sh5Rid,
    this.sh5Name = '',
    this.sh5UnitName = '',
    this.source = '',
    this.confidence = 0,
  });

  bool get isManual => source == Sh5KirimMapSource.manual;
  bool get isLearned => source == Sh5KirimMapSource.learned;

  factory Sh5KirimMap.fromJson(Map<String, dynamic> json) => Sh5KirimMap(
        sh5Rid: _asInt(json['sh5_rid']),
        sh5Name: _asStr(json['sh5_name']),
        sh5UnitName: _asStr(json['sh5_unit_name']),
        source: _asStr(json['source']),
        confidence: _asInt(json['confidence']),
      );
}

/// Nom o'xshashligi bo'yicha taklif (`item.suggestions`) — avto bog'lanmaydi,
/// bugalter bosib tasdiqlaydi.
class Sh5KirimSuggestion {
  final int sh5Rid;
  final String sh5Name;
  final String sh5UnitName;

  /// 0..1 — nom o'xshashligi bahosi (server ≥ 0.5 larni beradi).
  final double score;

  const Sh5KirimSuggestion({
    required this.sh5Rid,
    this.sh5Name = '',
    this.sh5UnitName = '',
    this.score = 0,
  });

  /// «72 %» ko'rinishida.
  String get scoreLabel => '${(score * 100).round()} %';

  factory Sh5KirimSuggestion.fromJson(Map<String, dynamic> json) =>
      Sh5KirimSuggestion(
        sh5Rid: _asInt(json['sh5_rid']),
        sh5Name: _asStr(json['sh5_name']),
        sh5UnitName: _asStr(json['sh5_unit_name']),
        score: _asDouble(json['score']),
      );
}

/// Buyurtma ichidagi bitta mahsulot qatori.
class Sh5KirimItem {
  /// Mapping kaliti: katalog uchun `p:<product_id>`, proche uchun `n:<nom>`.
  final String key;
  final int productId;
  final String name;

  /// Mone birligi (кг/л/шт...) — SH5 birligi bilan solishtiriladi.
  final String type;

  /// Miqdor milli BUTUN (кг/л → гр/мл), boshqalari o'z birligida.
  final int qtyMilli;

  /// Server tayyorlagan ko'rsatish matni («2,5 кг», «3 dona»).
  final String qtyDisplay;

  /// Qator summasi — BUTUN so'm.
  final int subtotal;

  /// Ombor qabul qilganmi (qabul qilinmasa — sariq ogohlantirish).
  final bool accepted;

  /// Mone birligi SH5 birligiga mos kelmadi (кг ↔ шт) — qizil belgi.
  final bool unitWarning;

  /// Bog'lanish (yo'q bo'lsa null → [suggestions] ko'rsatiladi).
  final Sh5KirimMap? map;

  /// [map] null bo'lganda — top 5 taklif.
  final List<Sh5KirimSuggestion> suggestions;

  const Sh5KirimItem({
    required this.key,
    this.productId = 0,
    this.name = '',
    this.type = '',
    this.qtyMilli = 0,
    this.qtyDisplay = '',
    this.subtotal = 0,
    this.accepted = false,
    this.unitWarning = false,
    this.map,
    this.suggestions = const [],
  });

  /// Bog'lanmagan (yuborishga to'siq).
  bool get isUnmapped => map == null;

  /// Bog'lanish yo'q, lekin tasdiqlash mumkin bo'lgan taklif bor.
  bool get hasSuggestion => map == null && suggestions.isNotEmpty;

  factory Sh5KirimItem.fromJson(Map<String, dynamic> json) {
    final rawMap = json['map'];
    return Sh5KirimItem(
      key: _asStr(json['key']),
      productId: _asInt(json['product_id']),
      name: _asStr(json['name']),
      type: _asStr(json['type']),
      qtyMilli: _asInt(json['qty_milli']),
      qtyDisplay: _asStr(json['qty_display']),
      subtotal: _asInt(json['subtotal']),
      accepted: _asBool(json['accepted']),
      unitWarning: _asBool(json['unit_warning']),
      map: rawMap is Map
          ? Sh5KirimMap.fromJson(Map<String, dynamic>.from(rawMap))
          : null,
      suggestions: _asMaps(json['suggestions'])
          .map(Sh5KirimSuggestion.fromJson)
          .toList(growable: false),
    );
  }
}

/// SH5 hujjati (navbat yozuvi): kun javobidagi `order.doc` va
/// `GET /docs?date=` ro'yxati bitta model bilan o'qiladi.
class Sh5KirimDoc {
  final int id;

  /// Qaysi Mone buyurtmasi uchun (docs ro'yxatida keladi).
  final int orderId;
  final String orderNo;
  final String date;

  /// queued | sending | done | error ([Sh5KirimStatus]).
  final String status;

  /// SH5 dagi hujjat rid'i va nomeri (`done` bo'lganda).
  final int sh5Rid;
  final String sh5Num;

  /// Xato matni (`error` bo'lganda).
  final String error;
  final DateTime? sentAt;
  final int attempts;

  const Sh5KirimDoc({
    required this.id,
    this.orderId = 0,
    this.orderNo = '',
    this.date = '',
    this.status = '',
    this.sh5Rid = 0,
    this.sh5Num = '',
    this.error = '',
    this.sentAt,
    this.attempts = 0,
  });

  bool get isDone => status == Sh5KirimStatus.done;
  bool get isError => status == Sh5KirimStatus.error;
  bool get isSending => status == Sh5KirimStatus.sending;
  bool get isQueued => status == Sh5KirimStatus.queued;

  /// Hali natija kutilyapti (3 s poll shu holatda davom etadi).
  bool get isPending => isQueued || isSending;

  /// Xato SH5 login/paroliga tegishlimi — shunda cred dialogi qayta chiqadi.
  bool get isAuthError {
    final text = error.toLowerCase();
    return text.contains('login') ||
        text.contains('parol') ||
        text.contains('auth_failed');
  }

  /// «SH5 № 338022» (nomer bo'lmasa rid bilan).
  String get numLabel {
    if (sh5Num.isNotEmpty) return 'SH5 № $sh5Num';
    if (sh5Rid > 0) return 'SH5 № $sh5Rid';
    return 'SH5 ga yozildi';
  }

  factory Sh5KirimDoc.fromJson(Map<String, dynamic> json) => Sh5KirimDoc(
        id: _asInt(json['id']),
        orderId: _asInt(json['order_id']),
        orderNo: _asStr(json['order_no']),
        date: _asStr(json['date']),
        status: _asStr(json['status']),
        sh5Rid: _asInt(json['sh5_rid']),
        sh5Num: _asStr(json['sh5_num']),
        error: _asStr(json['error']),
        sentAt: _asDate(json['sent_at']),
        attempts: _asInt(json['attempts']),
      );
}

/// Kun ro'yxatidagi bitta buyurtma.
class Sh5KirimOrder {
  /// Mone buyurtma id'si (`send` ga shu yuboriladi).
  final int id;

  /// Buyurtma nomeri (kontraktda `order_id`).
  final String orderNo;
  final int skladId;
  final String skladName;

  /// Sozlamadan kelgan SH5 ombori (0 — sklad bog'lanmagan).
  final int depRid;
  final String depName;

  /// Kontragent (РЫНОК / Ташкент).
  final int cntrRid;
  final String cntrName;
  final String source;
  final String pricedByName;

  /// Ombor qabul qilganmi.
  final bool accepted;

  /// Jami summa — BUTUN so'm.
  final int total;

  /// SH5 hujjati (hali yuborilmagan bo'lsa null).
  final Sh5KirimDoc? doc;
  final List<Sh5KirimItem> items;

  const Sh5KirimOrder({
    required this.id,
    this.orderNo = '',
    this.skladId = 0,
    this.skladName = '',
    this.depRid = 0,
    this.depName = '',
    this.cntrRid = 0,
    this.cntrName = '',
    this.source = '',
    this.pricedByName = '',
    this.accepted = false,
    this.total = 0,
    this.doc,
    this.items = const [],
  });

  /// Shu buyurtmadagi bog'lanmagan mahsulotlar soni.
  int get unmappedCount => items.where((e) => e.isUnmapped).length;

  /// SH5 ga yozilgan — qayta yuborilmaydi.
  bool get isDone => doc?.isDone ?? false;

  /// Ko'rsatish uchun nomer («#123»).
  String get numLabel => orderNo.isEmpty ? '#$id' : '#$orderNo';

  /// Doc almashganda (3 s poll) yangi nusxa — qolgan maydonlar o'zgarmaydi.
  Sh5KirimOrder copyWithDoc(Sh5KirimDoc? newDoc) => Sh5KirimOrder(
        id: id,
        orderNo: orderNo,
        skladId: skladId,
        skladName: skladName,
        depRid: depRid,
        depName: depName,
        cntrRid: cntrRid,
        cntrName: cntrName,
        source: source,
        pricedByName: pricedByName,
        accepted: accepted,
        total: total,
        doc: newDoc,
        items: items,
      );

  factory Sh5KirimOrder.fromJson(Map<String, dynamic> json) {
    final rawDoc = json['doc'];
    // Kontraktda `id` va `order_id` ikkalasi ham bor — `id` bo'sh kelsa
    // `order_id` dan olinadi (send uchun aynan shu son kerak).
    final id = _asInt(json['id']);
    final orderId = _asInt(json['order_id']);
    return Sh5KirimOrder(
      id: id > 0 ? id : orderId,
      orderNo: _asStr(json['order_no']).isNotEmpty
          ? _asStr(json['order_no'])
          : (orderId > 0 && orderId != id ? orderId.toString() : ''),
      skladId: _asInt(json['sklad_id']),
      skladName: _asStr(json['sklad_name']),
      depRid: _asInt(json['dep_rid']),
      depName: _asStr(json['dep_name']),
      cntrRid: _asInt(json['cntr_rid']),
      cntrName: _asStr(json['cntr_name']),
      source: _asStr(json['source']),
      pricedByName: _asStr(json['priced_by_name']),
      accepted: _asBool(json['accepted']),
      total: _asInt(json['total']),
      doc: rawDoc is Map
          ? Sh5KirimDoc.fromJson(Map<String, dynamic>.from(rawDoc))
          : null,
      items: _asMaps(json['items'])
          .map(Sh5KirimItem.fromJson)
          .toList(growable: false),
    );
  }
}

/// Sozlamada SH5 ombori biriktirilmagan sklad (ekranda ogohlantirish).
class Sh5KirimMissingSklad {
  final int skladId;
  final String skladName;

  const Sh5KirimMissingSklad({required this.skladId, this.skladName = ''});

  factory Sh5KirimMissingSklad.fromJson(Map<String, dynamic> json) =>
      Sh5KirimMissingSklad(
        skladId: _asInt(json['sklad_id']),
        skladName: _asStr(json['sklad_name']),
      );
}

/// `GET /api/sh5/kirim/day?date=` javobi.
class Sh5KirimDay {
  final String date;

  /// Sklad ↔ SH5 ombor xaritasi to'lami (false — yuborib bo'lmaydi).
  final bool settingsOk;
  final List<Sh5KirimMissingSklad> missingSklads;
  final List<Sh5KirimOrder> orders;
  final int unmappedCount;
  final int mappedCount;

  const Sh5KirimDay({
    this.date = '',
    this.settingsOk = false,
    this.missingSklads = const [],
    this.orders = const [],
    this.unmappedCount = 0,
    this.mappedCount = 0,
  });

  /// Kundagi jami mahsulot qatorlari.
  int get itemCount => orders.fold(0, (sum, o) => sum + o.items.length);

  /// Hali SH5 ga yozilmagan buyurtmalar (yuboriladiganlar).
  List<Sh5KirimOrder> get pendingOrders =>
      orders.where((o) => !o.isDone).toList(growable: false);

  /// Natija kutilayotgan hujjat bormi (3 s poll shunga qarab davom etadi).
  bool get hasPendingDocs => orders.any((o) => o.doc?.isPending ?? false);

  factory Sh5KirimDay.fromJson(Map<String, dynamic> json) => Sh5KirimDay(
        date: _asStr(json['date']),
        settingsOk: _asBool(json['settings_ok']),
        missingSklads: _asMaps(json['missing_sklads'])
            .map(Sh5KirimMissingSklad.fromJson)
            .toList(growable: false),
        orders: _asMaps(json['orders'])
            .map(Sh5KirimOrder.fromJson)
            .toList(growable: false),
        unmappedCount: _asInt(json['unmapped_count']),
        mappedCount: _asInt(json['mapped_count']),
      );

  /// Doc'lar ro'yxatidan (3 s poll) buyurtmalar statusini yangilaydi.
  Sh5KirimDay withDocs(List<Sh5KirimDoc> docs) {
    if (docs.isEmpty) return this;
    final byOrder = <int, Sh5KirimDoc>{};
    final byId = <int, Sh5KirimDoc>{};
    for (final d in docs) {
      if (d.orderId > 0) byOrder[d.orderId] = d;
      if (d.id > 0) byId[d.id] = d;
    }
    return Sh5KirimDay(
      date: date,
      settingsOk: settingsOk,
      missingSklads: missingSklads,
      orders: orders
          .map((o) {
            final fresh = byOrder[o.id] ??
                (o.doc != null ? byId[o.doc!.id] : null);
            return fresh == null ? o : o.copyWithDoc(fresh);
          })
          .toList(growable: false),
      unmappedCount: unmappedCount,
      mappedCount: mappedCount,
    );
  }
}

// ─────────────────────────── Tovar qidiruvi ───────────────────────────

/// SH5 tovar lug'atining bitta yozuvi (`goods?q=`).
class Sh5KirimGood {
  final int rid;
  final String name;
  final String unitName;

  /// RK7 kodi (bo'lsa) — qidiruvda farqlash uchun.
  final String rkCode;
  final String groupName;

  const Sh5KirimGood({
    required this.rid,
    this.name = '',
    this.unitName = '',
    this.rkCode = '',
    this.groupName = '',
  });

  /// «Кг · Бакалея» ko'rinishidagi ostki matn.
  String get subtitle => [
        if (unitName.isNotEmpty) unitName,
        if (groupName.isNotEmpty) groupName,
        if (rkCode.isNotEmpty) 'kod: $rkCode',
      ].join(' · ');

  factory Sh5KirimGood.fromJson(Map<String, dynamic> json) => Sh5KirimGood(
        rid: _asInt(json['rid']),
        name: _asStr(json['name']),
        unitName: _asStr(json['unit_name']),
        rkCode: _asStr(json['rk_code']),
        groupName: _asStr(json['group_name']),
      );
}

// ─────────────────────────── SH5 login/paroli ───────────────────────────

/// `GET /api/sh5/kirim/credentials` — parol HECH QACHON qaytmaydi.
class Sh5KirimCredentials {
  /// Saqlangan login/parol bormi.
  final bool has;
  final String sh5User;

  /// Bridge birinchi hujjatda tekshirgan va to'g'ri chiqqanmi.
  final bool verified;
  final String lastError;

  const Sh5KirimCredentials({
    this.has = false,
    this.sh5User = '',
    this.verified = false,
    this.lastError = '',
  });

  factory Sh5KirimCredentials.fromJson(Map<String, dynamic> json) =>
      Sh5KirimCredentials(
        has: _asBool(json['has']),
        sh5User: _asStr(json['sh5_user']),
        verified: _asBool(json['verified']),
        lastError: _asStr(json['last_error']),
      );
}

// ─────────────────────────── Sozlamalar ───────────────────────────

/// Sklad ↔ SH5 ombor juftligi.
class Sh5KirimSkladMap {
  final int skladId;
  final String skladName;
  final int depRid;
  final String depName;

  const Sh5KirimSkladMap({
    required this.skladId,
    this.skladName = '',
    this.depRid = 0,
    this.depName = '',
  });

  factory Sh5KirimSkladMap.fromJson(Map<String, dynamic> json) =>
      Sh5KirimSkladMap(
        skladId: _asInt(json['sklad_id']),
        skladName: _asStr(json['sklad_name']),
        depRid: _asInt(json['dep_rid']),
        depName: _asStr(json['dep_name']),
      );
}

/// Manba (samarqand/toshkent/zagranitsa/«») ↔ kontragent juftligi.
class Sh5KirimSourceMap {
  final String source;
  final int cntrRid;
  final String cntrName;

  const Sh5KirimSourceMap({
    this.source = '',
    this.cntrRid = 0,
    this.cntrName = '',
  });

  factory Sh5KirimSourceMap.fromJson(Map<String, dynamic> json) =>
      Sh5KirimSourceMap(
        source: _asStr(json['source']),
        cntrRid: _asInt(json['cntr_rid']),
        cntrName: _asStr(json['cntr_name']),
      );
}

/// SH5 ombori (dropdown uchun).
class Sh5KirimDepart {
  final int rid;
  final String name;

  const Sh5KirimDepart({required this.rid, this.name = ''});

  factory Sh5KirimDepart.fromJson(Map<String, dynamic> json) =>
      Sh5KirimDepart(rid: _asInt(json['rid']), name: _asStr(json['name']));
}

/// SH5 kontragenti (dropdown uchun).
class Sh5KirimCorr {
  final int rid;
  final String name;

  /// SH5 kontragent turi (bozor yo'nalishlari — 3).
  final int type;

  const Sh5KirimCorr({required this.rid, this.name = '', this.type = 0});

  factory Sh5KirimCorr.fromJson(Map<String, dynamic> json) => Sh5KirimCorr(
        rid: _asInt(json['rid']),
        name: _asStr(json['name']),
        type: _asInt(json['type']),
      );
}

/// `GET /api/sh5/kirim/settings` javobi.
class Sh5KirimSettings {
  final List<Sh5KirimSkladMap> sklads;
  final List<Sh5KirimSourceMap> sources;
  final List<Sh5KirimDepart> departs;
  final List<Sh5KirimCorr> corrs;

  const Sh5KirimSettings({
    this.sklads = const [],
    this.sources = const [],
    this.departs = const [],
    this.corrs = const [],
  });

  factory Sh5KirimSettings.fromJson(Map<String, dynamic> json) =>
      Sh5KirimSettings(
        sklads: _asMaps(json['sklads'])
            .map(Sh5KirimSkladMap.fromJson)
            .toList(growable: false),
        sources: _asMaps(json['sources'])
            .map(Sh5KirimSourceMap.fromJson)
            .toList(growable: false),
        departs: _asMaps(json['departs'])
            .map(Sh5KirimDepart.fromJson)
            .toList(growable: false),
        corrs: _asMaps(json['corrs'])
            .map(Sh5KirimCorr.fromJson)
            .toList(growable: false),
      );
}
