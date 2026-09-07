// core2/models/core_integration.dart — integratsiya modellari:
// CoreSalePoint (sotuv nuqtasi + qoidalar), CoreSalePointRule, CoreApiKey
// (kalit faqat yaratilganda bir marta keladi), CoreWebhook (secret faqat
// yaratilganda), CoreSyncStatus/CoreSyncPeer (/sync/status — rol, peers,
// queue). API_V2.md «Integratsiya» + internal/sync/admin.go.

class CoreSalePointRule {
  final String match; // category|code|good
  static const List<String> matches = ['category', 'code', 'good'];
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
  static const List<String> sources = ['konak', 'rk7', 'mone_v1', 'other'];
  final int id;
  final String name;
  final String source; // konak|rk7|mone_v1|other
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
  final bool active;
  // Faqat POST javobida keladi (bir marta), ro'yxatda bo'sh.
  final String key;
  final String createdAt;
  final String lastUsed;

  const CoreApiKey({
    this.id = 0,
    required this.name,
    this.scopes = const [],
    this.active = true,
    this.key = '',
    this.createdAt = '',
    this.lastUsed = '',
  });

  factory CoreApiKey.fromJson(Map<String, dynamic> j) => CoreApiKey(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        scopes: (j['scopes'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        active: j['active'] is bool ? j['active'] as bool : true,
        key: (j['key'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        lastUsed: (j['last_used'] ?? '').toString(),
      );

  // `admin` — faqat superadmin beradi.
  static const List<String> allScopes = ['read', 'docs:write', 'pos:shift', 'admin'];
}

class CoreWebhook {
  final int id;
  final String name;
  final String url;
  final List<String> events;
  final bool active;
  // Faqat POST javobida (bir marta) — HMAC imzo kaliti.
  final String secret;

  const CoreWebhook({
    this.id = 0,
    this.name = '',
    required this.url,
    this.events = const [],
    this.active = true,
    this.secret = '',
  });

  factory CoreWebhook.fromJson(Map<String, dynamic> j) => CoreWebhook(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        events: (j['events'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        active: j['active'] is bool ? j['active'] as bool : true,
        secret: (j['secret'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id > 0) 'id': id,
        'name': name,
        'url': url,
        'events': events,
        'active': active,
      };

  static const List<String> allEvents = [
    'doc.posted',
    'doc.cancelled',
    'stock.changed',
    'stock.low',
    'shift.imported',
  ];
}

/// `GET /sync/status` (internal/sync/admin.go): `{node_id, role
/// (dialer|acceptor|off), cloud_url, configured, connected, epoch,
/// id_offset, last_ack_at, peers[{node_id,remote,since,last_ack_at}],
/// queue{pending,sent,acked,failed}, failed[{event_id,table,op,error,
/// retry_count}]}`.
class CoreSyncPeer {
  final String nodeId;
  final String remote;
  final String since;
  final String lastAckAt;
  const CoreSyncPeer({
    this.nodeId = '',
    this.remote = '',
    this.since = '',
    this.lastAckAt = '',
  });

  factory CoreSyncPeer.fromJson(Map<String, dynamic> j) => CoreSyncPeer(
        nodeId: (j['node_id'] ?? '').toString(),
        remote: (j['remote'] ?? '').toString(),
        since: (j['since'] ?? '').toString(),
        lastAckAt: (j['last_ack_at'] ?? '').toString(),
      );
}

class CoreSyncStatus {
  final String nodeId;
  final String role;
  final String cloudUrl;
  final bool configured;
  final bool connected;
  final String epoch;
  final int idOffset;
  final String lastAckAt;
  final List<CoreSyncPeer> peers;
  final int pending;
  final int sent;
  final int acked;
  final int failedCount;
  final List<Map<String, dynamic>> failed;

  const CoreSyncStatus({
    this.nodeId = '',
    this.role = '',
    this.cloudUrl = '',
    this.configured = false,
    this.connected = false,
    this.epoch = '',
    this.idOffset = 0,
    this.lastAckAt = '',
    this.peers = const [],
    this.pending = 0,
    this.sent = 0,
    this.acked = 0,
    this.failedCount = 0,
    this.failed = const [],
  });

  factory CoreSyncStatus.fromJson(Map<String, dynamic> j) {
    final q = j['queue'] is Map ? j['queue'] as Map : const {};
    return CoreSyncStatus(
      nodeId: (j['node_id'] ?? '').toString(),
      role: (j['role'] ?? '').toString(),
      cloudUrl: (j['cloud_url'] ?? '').toString(),
      configured: j['configured'] == true,
      connected: j['connected'] == true,
      epoch: (j['epoch'] ?? '').toString(),
      idOffset: (j['id_offset'] as num?)?.toInt() ?? 0,
      lastAckAt: (j['last_ack_at'] ?? '').toString(),
      peers: (j['peers'] as List?)
              ?.whereType<Map>()
              .map((e) => CoreSyncPeer.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      pending: (q['pending'] as num?)?.toInt() ?? 0,
      sent: (q['sent'] as num?)?.toInt() ?? 0,
      acked: (q['acked'] as num?)?.toInt() ?? 0,
      failedCount: (q['failed'] as num?)?.toInt() ?? 0,
      failed: (j['failed'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
    );
  }
}
