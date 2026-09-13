// admin/model/user_model.dart — foydalanuvchi va bog'liq modellar:
// User (role, filial, categoryIds, sklads, sh5Sklads, sources,
// telegramChatId, passwordPlain), Filial, CreateUserRequest/
// UpdateUserRequest (user_management servisi so'rov tanalari),
// SendAllCredentialsResult/SendCredentialsFailure.
class User {
  final int id;
  final String name;
  final String phone;
  final bool isAdmin;
  final String role; // superadmin, admin, seller, ombor, yuk_keltiruvchi
  final int? filialId;
  final Filial? filial;
  final String? password;
  final List<int>? categoryIds;
  final List<int> sklads;
  // Ostatka (SH5) omborlari — ko'rish ruxsati berilganlari (Sh5RemainSklad.id).
  // Bo'sh — ruxsat yo'q (admin baribir hammasini ko'radi).
  final List<int> sh5Sklads;
  // yuk_keltiruvchi uchun mahsulot manbalari ("samarqand"/"toshkent"/"zagranitsa").
  // Bo'sh — cheklov yo'q (hammasini ko'radi).
  final List<String> sources;
  final String? telegramGroupId;
  // Telegram bot orqali bog'langan shaxsiy chat ID (0 — bog'lanmagan).
  final int telegramChatId;
  // Adminga ko'rsatish uchun ochiq parol (bo'sh bo'lishi mumkin).
  final String passwordPlain;

  User({
    required this.id,
    required this.name,
    required this.phone,
    required this.isAdmin,
    this.role = 'seller',
    this.filialId,
    this.filial,
    this.password,
    this.categoryIds,
    this.sklads = const [],
    this.sh5Sklads = const [],
    this.sources = const [],
    this.telegramGroupId,
    this.telegramChatId = 0,
    this.passwordPlain = '',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      isAdmin: json['is_admin'] ?? false,
      role: json['role'] ?? 'seller',
      filialId: json['filial_id'],
      filial: json['filial'] != null ? Filial.fromJson(json['filial']) : null,
      categoryIds: (json['category_list'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      sklads: (json['sklads'] as List?)?.map((e) => e as int).toList() ?? [],
      sh5Sklads: (json['sh5_sklads'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      sources:
          (json['sources'] as List?)?.map((e) => e.toString()).toList() ?? [],
      telegramGroupId: json['telegram_group_id'],
      telegramChatId: (json['telegram_chat_id'] as num?)?.toInt() ?? 0,
      passwordPlain: json['password_plain'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'is_admin': isAdmin,
      'role': role,
      'filial_id': filialId,
      'sklads': sklads,
      'sh5_sklads': sh5Sklads,
      'sources': sources,
      if (password != null) 'password': password,
      if (telegramGroupId != null) 'telegram_group_id': telegramGroupId,
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? phone,
    bool? isAdmin,
    String? role,
    int? filialId,
    Filial? filial,
    String? password,
    List<int>? sklads,
    List<int>? sh5Sklads,
    List<String>? sources,
    String? telegramGroupId,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isAdmin: isAdmin ?? this.isAdmin,
      role: role ?? this.role,
      filialId: filialId ?? this.filialId,
      filial: filial ?? this.filial,
      password: password ?? this.password,
      sklads: sklads ?? this.sklads,
      sh5Sklads: sh5Sklads ?? this.sh5Sklads,
      sources: sources ?? this.sources,
      telegramGroupId: telegramGroupId ?? this.telegramGroupId,
    );
  }
}
// ================ MODELS ================
// models/user_models.dart

class Filial {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final String? location;

  Filial({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.location,
  });

  factory Filial.fromJson(Map<String, dynamic> json) {
    return Filial(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      address: json['address'],
      phone: json['phone'],
      location: json['location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'location': location,
    };
  }
}

class UpdateUserRequest {
  final String? name;
  final String? phone;
  final bool? isAdmin;
  final String? role;
  final int? filialId;
  final String? password;
  final List<int>? categoryIds;
  final List<int>? sklads;
  // Ostatka (SH5) ruxsati; null — yuborilmaydi (backenddagi qiymat qoladi).
  final List<int>? sh5Sklads;
  // null — yuborilmaydi (backenddagi qiymat o'zgarmaydi).
  final List<String>? sources;
  final String? telegramGroupId;

  UpdateUserRequest({
    this.name,
    this.phone,
    this.isAdmin,
    this.role,
    this.filialId,
    this.password,
    this.categoryIds,
    this.sklads,
    this.sh5Sklads,
    this.sources,
    this.telegramGroupId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (name != null) data['name'] = name;
    if (phone != null) data['phone'] = phone;
    if (isAdmin != null) data['is_admin'] = isAdmin;
    if (role != null) data['role'] = role;
    if (filialId != null) data['filial_id'] = filialId;
    if (password != null && password!.isNotEmpty) data['password'] = password;
    if (categoryIds != null) data['category_list'] = categoryIds;
    if (sklads != null) data['sklads'] = sklads;
    if (sh5Sklads != null) data['sh5_sklads'] = sh5Sklads;
    if (sources != null) data['sources'] = sources;
    // Bo'sh string ham yuboriladi — backend bo'sh qiymatda tozalaydi.
    if (telegramGroupId != null) data['telegram_group_id'] = telegramGroupId;
    return data;
  }
}

/// POST /api/users/send-all-credentials javobidagi `data` bo'limi.
/// Maydonlar defensiv parse qilinadi — backend biror ro'yxatni yubormasa
/// bo'sh ro'yxat sifatida qabul qilinadi.
class SendAllCredentialsResult {
  final int sent;
  // Telegrami bog'lanmagani uchun o'tkazib yuborilgan foydalanuvchi ismlari.
  final List<String> skipped;
  final List<SendCredentialsFailure> failed;

  SendAllCredentialsResult({
    this.sent = 0,
    this.skipped = const [],
    this.failed = const [],
  });

  factory SendAllCredentialsResult.fromJson(Map<String, dynamic> json) {
    return SendAllCredentialsResult(
      sent: (json['sent'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      failed: (json['failed'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(SendCredentialsFailure.fromJson)
              .toList() ??
          const [],
    );
  }
}

class SendCredentialsFailure {
  final String name;
  final String error;

  SendCredentialsFailure({this.name = '', this.error = ''});

  factory SendCredentialsFailure.fromJson(Map<String, dynamic> json) {
    return SendCredentialsFailure(
      name: json['name']?.toString() ?? '',
      error: json['error']?.toString() ?? '',
    );
  }
}

class CreateUserRequest {
  final String name;
  final String phone;
  final String password;
  final bool isAdmin;
  final String role;
  final int? filialId;
  final List<int>? categoryIds;
  final List<int> sklads;
  // Ostatka (SH5) omborlari — ko'rish ruxsati.
  final List<int> sh5Sklads;
  final List<String>? sources;
  final String? telegramGroupId;

  CreateUserRequest({
    required this.name,
    required this.phone,
    required this.password,
    this.isAdmin = false,
    this.role = 'seller',
    this.filialId,
    this.categoryIds,
    this.sklads = const [],
    this.sh5Sklads = const [],
    this.sources,
    this.telegramGroupId,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'password': password,
      'is_admin': isAdmin,
      'role': role,
      if (filialId != null) 'filial_id': filialId,
      'category_list': categoryIds,
      'sklads': sklads,
      'sh5_sklads': sh5Sklads,
      if (sources != null) 'sources': sources,
      if (telegramGroupId != null) 'telegram_group_id': telegramGroupId,
    };
  }
}
