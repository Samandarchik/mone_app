// Sklad qoldig'i (inventar) modellari — ombor/admin qoldiq sahifalari.
// Backend JSON snake_case; kontrakt: mone_app/reja.md §5 (Stock/StockMove).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ??
      (double.tryParse(v?.toString() ?? '')?.toInt() ?? 0);
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

// Sklad nomlari — YAGONA manba SkladRegistry (superadmin serverda tahrirlaydi).
// Bu yerdagilar faqat eski chaqiruv nomlarini saqlab turadi.
Map<int, String> get kProductionSkladNames => SkladRegistry.names;

String productionSkladName(int id) => SkladRegistry.nameOf(id);

// SharedPreferences'dagi 'user' JSON ichidan foydalanuvchiga biriktirilgan
// skladlar ro'yxatini o'qish (yuk_home_ui dagi naqsh bilan bir xil).
Future<List<int>> loadUserSklads() async {
  final prefs = await SharedPreferences.getInstance();
  final userStr = prefs.getString('user');
  final sklads = <int>[];
  if (userStr != null && userStr.isNotEmpty) {
    try {
      final user = jsonDecode(userStr);
      if (user is Map && user['sklads'] is List) {
        for (final s in user['sklads']) {
          if (s is int) {
            sklads.add(s);
          } else if (s is num) {
            sklads.add(s.toInt());
          } else {
            final parsed = int.tryParse(s.toString());
            if (parsed != null) sklads.add(parsed);
          }
        }
      }
    } catch (_) {
      // Buzilgan JSON — bo'sh ro'yxat qaytadi.
    }
  }
  return sklads;
}

// GET /api/stock javobidagi bitta qator — (sklad, mahsulot) joriy qoldig'i.
class StockRow {
  final int skladId;
  final int productId;
  final String name;
  final String type; // mahsulotning o'z birligi: кг | литр | шт | м ...
  // Mahsulot rasmi — relativ yo'l ('/static/...'); bo'sh bo'lishi mumkin.
  // To'liq manzil: '${AppUrls.baseUrl}$imageUrl'. Inventarizatsiya jadvalidagi
  // «Rasm» ustuni uchun.
  final String imageUrl;
  final double qty; // manfiy bo'lishi mumkin (qizil ko'rsatiladi)
  final double minQty; // minimal chegara (0 — o'rnatilmagan)
  final bool low; // backend: qty <= min_qty (kam qolgan)

  const StockRow({
    required this.skladId,
    required this.productId,
    this.name = '',
    this.type = '',
    this.imageUrl = '',
    this.qty = 0,
    this.minQty = 0,
    this.low = false,
  });

  factory StockRow.fromJson(Map<String, dynamic> json) {
    return StockRow(
      skladId: _asInt(json['sklad_id']),
      productId: _asInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      qty: _asDouble(json['qty']),
      minQty: _asDouble(json['min_qty']),
      low: json['low'] == true,
    );
  }

  static List<StockRow> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => StockRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}

// Harakat sabablari (StockMove.reason qiymatlari).
abstract final class StockReason {
  static const String omborQabul = 'ombor_qabul';
  static const String ishlabChiqarish = 'ishlab_chiqarish';
  static const String korreksiya = 'korreksiya';
  static const String tayyorMahsulot = 'tayyor_mahsulot';
}

// Sabab kodini foydalanuvchiga ko'rsatiladigan matnga aylantirish.
String stockReasonLabel(String reason) {
  switch (reason) {
    case StockReason.omborQabul:
      return 'Kirim (qabul)';
    case StockReason.ishlabChiqarish:
      return 'Ishlab chiqarish';
    case StockReason.korreksiya:
      return 'Korreksiya';
    case StockReason.tayyorMahsulot:
      return 'Tayyor mahsulot';
    default:
      return reason;
  }
}

// GET /api/stock/moves javobidagi bitta harakat (mahsulot nomi bilan).
class StockMove {
  final int id;
  final int skladId;
  final int productId;
  final String name;
  final double qty; // + kirim, − chiqim
  final String reason; // ombor_qabul | ishlab_chiqarish | korreksiya
  final int refOrderId;
  final int userId;
  final String comment;
  final String created;

  const StockMove({
    required this.id,
    required this.skladId,
    required this.productId,
    this.name = '',
    this.qty = 0,
    this.reason = '',
    this.refOrderId = 0,
    this.userId = 0,
    this.comment = '',
    this.created = '',
  });

  factory StockMove.fromJson(Map<String, dynamic> json) {
    return StockMove(
      id: _asInt(json['id']),
      skladId: _asInt(json['sklad_id']),
      productId: _asInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      qty: _asDouble(json['qty']),
      reason: json['reason']?.toString() ?? '',
      refOrderId: _asInt(json['ref_order_id']),
      userId: _asInt(json['user_id']),
      comment: json['comment']?.toString() ?? '',
      created: json['created']?.toString() ?? '',
    );
  }

  static List<StockMove> listFromJson(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => StockMove.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }
}

// Miqdorni chiroyli ko'rsatish: 7.0 -> "7", 7.25 -> "7.25".
String fmtStockQty(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}
