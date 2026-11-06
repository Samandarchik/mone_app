// admin/model/pos_mone_station_model.dart — POS Mone kassasi (mone_pos):
// PosMoneStation (filial, asosiy sklad, bo'lim yo'naltirishlari) va
// PosMoneSkladRoute (kategoriya YOKI mahsulot → sklad).

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

DateTime? _date(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  final d = DateTime.tryParse(v);
  // Go nol vaqti (0001-01-01) — «hali yo'q».
  if (d == null || d.year < 2000) return null;
  return d.toLocal();
}

/// Bo'lim yo'naltirishi: [categoryId] YOKI [productId] (bittasi) → [skladId].
/// Ustuvorlik serverda: mahsulot > kategoriya > kassaning asosiy skladi.
class PosMoneSkladRoute {
  final int categoryId;
  final int productId;
  final int skladId;

  /// true — mahsulotning O'ZI yechiladi (tayyor tort skladda turadi);
  /// false — tex karta bo'lsa masalliqlari (restoran: fresh, salat).
  final bool self;

  const PosMoneSkladRoute({
    this.categoryId = 0,
    this.productId = 0,
    required this.skladId,
    this.self = false,
  });

  bool get isProduct => productId > 0;

  factory PosMoneSkladRoute.fromJson(Map<String, dynamic> j) =>
      PosMoneSkladRoute(
        categoryId: _int(j['category_id']),
        productId: _int(j['product_id']),
        skladId: _int(j['sklad_id']),
        self: j['deduct_mode'] == 'self',
      );

  Map<String, dynamic> toJson() => {
        if (productId > 0) 'product_id': productId,
        if (productId <= 0) 'category_id': categoryId,
        'sklad_id': skladId,
        if (self) 'deduct_mode': 'self',
      };
}

class PosMoneStation {
  final String stationId;
  final String name;
  final int filialId;
  final String filialName;
  final int skladId;
  final int effectiveSkladId;
  final String hostname;
  final String appVersion;
  final DateTime? lastSeenAt;
  final List<PosMoneSkladRoute> routes;

  const PosMoneStation({
    required this.stationId,
    this.name = '',
    this.filialId = 0,
    this.filialName = '',
    this.skladId = 0,
    this.effectiveSkladId = 0,
    this.hostname = '',
    this.appVersion = '',
    this.lastSeenAt,
    this.routes = const [],
  });

  String get title => name.isNotEmpty ? name : stationId;

  /// Oxirgi 2 daqiqada aloqa bo'lgan (kassa har 20 s da so'raydi).
  bool get online =>
      lastSeenAt != null &&
      DateTime.now().difference(lastSeenAt!) < const Duration(minutes: 2);

  factory PosMoneStation.fromJson(Map<String, dynamic> j) => PosMoneStation(
        stationId: '${j['station_id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        filialId: _int(j['filial_id']),
        filialName: '${j['filial_name'] ?? ''}',
        skladId: _int(j['sklad_id']),
        effectiveSkladId: _int(j['effective_sklad_id']),
        hostname: '${j['hostname'] ?? ''}',
        appVersion: '${j['app_version'] ?? ''}',
        lastSeenAt: _date(j['last_seen_at']),
        routes: [
          if (j['sklad_routes'] is List)
            for (final r in j['sklad_routes'] as List)
              if (r is Map)
                PosMoneSkladRoute.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
}

/// POS menyudagi (kassa katalogi) kategoriya/mahsulot — yo'naltirish tanlovi uchun.
class PosMoneCatalogItem {
  final int id;
  final String name;
  final int categoryId;
  const PosMoneCatalogItem(this.id, this.name, {this.categoryId = 0});
}
