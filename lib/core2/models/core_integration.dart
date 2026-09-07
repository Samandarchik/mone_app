// core2/models/core_integration.dart — integratsiya modellari:
// CoreSalePoint (sotuv nuqtasi + qoidalar), CoreSalePointRule, CoreApiKey
// (kalit faqat yaratilganda bir marta keladi), CoreWebhook, CoreSyncStatus
// (/sync/status — rol, peer, pending). API_V2.md «Integratsiya».

class CoreSalePointRule {
  final String match; // category|group|good
  final String value;
  final int skladId;

  const CoreSalePointRule({
    required this.match,
    required this.value,
    required this.skladId,
  });

  factory CoreSalePointRule.fromJson(Map<String, dynamic> j) =>
      CoreSalePointRule(
        match: (j['match'] ?? 'category').toString(),
        value: (j['value'] ?? '').toString(),
        skladId: (j['sklad_id'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'match': match, 'value': value, 'sklad_id': skladId};
}

class CoreSalePoint {
  final int id;
  final String name;
  final String source; // konak|rk7
  final String externalId;
  final int? skladId;
  final List<CoreSalePointRule> rules;
  final bool active;

  const CoreSalePoint({
    this.id = 0,
    required this.name,
    this.source = 'konak',
    this.externalId = '',
    this.skladId,
    this.rules = const [],
    this.active = true,
  });

  factory CoreSalePoint.fromJson(Map<String, dynamic> j) => CoreSalePoint(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        source: (j['source'] ?? 'konak').toString(),
        externalId: (j['external_id'] ?? '').toString(),
        skladId: (j['sklad_id'] as num?)?.toInt(),
        rules: (j['rules'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    CoreSalePointRule.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        active: j['active'] is bool ? j['active'] as bool : true,
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'source': source,
        'external_id': externalId,
        'sklad_id': skladId,
        'rules': rules.map((r) => r.toJson()).toList(),
        'active': active,
      };
}

class CoreApiKey {
  final int id;
  final String name;
  final List<String> scopes;
  // Faqat POST javobida keladi (bir marta), ro'yxatda bo'sh.
  final String key;
  final String createdAt;

  const CoreApiKey({
    this.id = 0,
    required this.name,
    this.scopes = const [],
    this.key = '',
    this.createdAt = '',
  });

  factory CoreApiKey.fromJson(Map<String, dynamic> j) => CoreApiKey(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        scopes: (j['scopes'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        key: (j['key'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
      );

  static const List<String> allScopes = ['read', 'docs:write', 'pos:shift'];
}

class CoreWebhook {
  final int id;
  final String url;
  final List<String> events;
  final bool active;

  const CoreWebhook({
    this.id = 0,
    required this.url,
    this.events = const [],
    this.active = true,
  });

  factory CoreWebhook.fromJson(Map<String, dynamic> j) => CoreWebhook(
        id: (j['id'] as num?)?.toInt() ?? 0,
        url: (j['url'] ?? '').toString(),
        events: (j['events'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        active: j['active'] is bool ? j['active'] as bool : true,
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'url': url,
        'events': events,
        'active': active,
      };

  static const List<String> allEvents = ['doc.posted', 'stock.low'];
}

/// `GET /sync/status` — shartnomada hali rasmiy emas; kutilayotgan shakl:
/// {"role":"dialer|acceptor|off","peer":"…","pending":N,"last_sent_at","last_ack_at"}.
/// Noma'lum maydonlar `extra` da saqlanadi va kartada ko'rsatiladi.
class CoreSyncStatus {
  final String role;
  final String peer;
  final int pending;
  final Map<String, dynamic> extra;

  const CoreSyncStatus({
    this.role = '',
    this.peer = '',
    this.pending = 0,
    this.extra = const {},
  });

  factory CoreSyncStatus.fromJson(Map<String, dynamic> j) {
    final extra = Map<String, dynamic>.from(j)
      ..remove('role')
      ..remove('peer')
      ..remove('pending');
    return CoreSyncStatus(
      role: (j['role'] ?? '').toString(),
      peer: (j['peer'] ?? '').toString(),
      pending: (j['pending'] as num?)?.toInt() ?? 0,
      extra: extra,
    );
  }
}
