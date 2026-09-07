// core2/models/core_user.dart — mone_core (/api/v2) foydalanuvchisi
// (CoreUser): id, name, phone, login_code, role, perms override (map),
// sklads (cheklov), active; hamda /auth/me dan keladigan hisoblangan `perms`
// ro'yxati (CoreMe). Ruxsat katalogi elementi — CorePermDef (/perms).
class CoreUser {
  final int id;
  final String name;
  final String phone;
  final String loginCode;
  final String role;
  // Shaxsiy override: {"doc.receipt.post": true/false}.
  final Map<String, bool> permsOverride;
  // Bo'sh — cheklov yo'q (hamma ombor).
  final List<int> sklads;
  final bool active;

  const CoreUser({
    required this.id,
    required this.name,
    this.phone = '',
    this.loginCode = '',
    this.role = 'seller',
    this.permsOverride = const {},
    this.sklads = const [],
    this.active = true,
  });

  factory CoreUser.fromJson(Map<String, dynamic> j) {
    final rawPerms = j['perms'];
    final Map<String, bool> override = {};
    if (rawPerms is Map) {
      rawPerms.forEach((k, v) {
        if (v is bool) override[k.toString()] = v;
      });
    }
    return CoreUser(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      loginCode: (j['login_code'] ?? '').toString(),
      role: (j['role'] ?? 'seller').toString(),
      permsOverride: override,
      sklads: (j['sklads'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      active: j['active'] is bool ? j['active'] as bool : true,
    );
  }

  Map<String, dynamic> toJson({String? password}) => {
        'id': id,
        'name': name,
        'phone': phone,
        'login_code': loginCode,
        'role': role,
        'perms': permsOverride,
        'sklads': sklads,
        'active': active,
        if (password != null && password.isNotEmpty) 'password': password,
      };

  CoreUser copyWith({
    String? name,
    String? phone,
    String? loginCode,
    String? role,
    Map<String, bool>? permsOverride,
    List<int>? sklads,
    bool? active,
  }) =>
      CoreUser(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        loginCode: loginCode ?? this.loginCode,
        role: role ?? this.role,
        permsOverride: permsOverride ?? this.permsOverride,
        sklads: sklads ?? this.sklads,
        active: active ?? this.active,
      );
}

/// `GET /auth/me` javobi: foydalanuvchi + hisoblangan ruxsatlar ro'yxati.
class CoreMe {
  final CoreUser user;
  final Set<String> perms;
  const CoreMe({required this.user, required this.perms});

  factory CoreMe.fromJson(Map<String, dynamic> j) {
    // /auth/me: {…User, "perms":[…hisoblangan], "perms_override":{…}};
    // /auth/login: {"token","user":{User},"perms":[…]} — ikkalasi qabul.
    final userJson = j['user'] is Map
        ? Map<String, dynamic>.from(j['user'] as Map)
        : Map<String, dynamic>.from(j);
    final perms = parsePermsList(j['perms']);
    if (j['perms'] is List) userJson.remove('perms');
    if (j['perms_override'] is Map) userJson['perms'] = j['perms_override'];
    return CoreMe(user: CoreUser.fromJson(userJson), perms: perms);
  }

  /// `"perms":["doc.receipt.create",…]` → to'plam (List bo'lmasa bo'sh).
  static Set<String> parsePermsList(dynamic raw) {
    final out = <String>{};
    if (raw is List) {
      for (final p in raw) {
        out.add(p.toString());
      }
    }
    return out;
  }
}

/// `GET /perms` katalogi: {"perm","title","grp"}.
class CorePermDef {
  final String perm;
  final String title;
  final String grp;
  const CorePermDef({required this.perm, required this.title, required this.grp});

  factory CorePermDef.fromJson(Map<String, dynamic> j) => CorePermDef(
        perm: (j['perm'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        grp: (j['grp'] ?? '').toString(),
      );
}

/// Ruxsat kalitlari — UI shu konstantalar bilan tekshiradi (typo'dan himoya).
abstract final class CorePerms {
  static String docCreate(String type) => 'doc.$type.create';
  static String docPost(String type) => 'doc.$type.post';
  static const String docBackdate = 'doc.backdate';
  static const String docCancel = 'doc.cancel';
  static const String recipeEdit = 'recipe.edit';
  static const String dictEdit = 'dict.edit';
  static const String stockView = 'stock.view';
  static const String stockCostView = 'stock.cost.view';
  static const String reportView = 'report.view';
  static const String usersManage = 'users.manage';
  static const String integrationManage = 'integration.manage';
}
