// core/data/local/products_cache.dart — mahsulotlar ro'yxatining LOKAL keshi
// (ProductsCache). `/api/products/all` javobi ~1.6 MB (1342 mahsulot, har
// birida тех карта): u XOM MATN holida app papkasidagi faylga yoziladi, o'qishda
// esa `compute()` — FON isolate'ida parse qilinadi. Ilgari bu JSON UI oqimida
// dekod qilinib 1342 marta `fromJson` chaqirilardi va Android «Mone App isn't
// responding» (ANR) berardi.
//
// Oqim (ProductProviderAdmin.initializeProducts):
//   kesh o'qiladi -> ro'yxat DARHOL ko'rinadi -> fonda tarmoqdan yangilanadi.
// Logout'da (`clear`) kesh fayli O'CHIRILADI — boshqa foydalanuvchiga o'tmaydi.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';

// FON isolate'ida bajariladi (compute uchun TOP-LEVEL bo'lishi shart):
// xom JSON -> modellar. `{"data": [...]}` ham, to'g'ridan-to'g'ri massiv ham
// qabul qilinadi (endpoint ikkala shaklni ham qaytargan).
List<ProductModelAdmin> parseProductsJson(String raw) {
  final decoded = jsonDecode(raw);
  final list = decoded is Map
      ? (decoded['data'] as List? ?? const [])
      : (decoded as List? ?? const []);
  return list
      .whereType<Map<String, dynamic>>()
      .map(ProductModelAdmin.fromJson)
      .toList();
}

class ProductsCache {
  static const String _fileName = 'products_all.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Keshdagi ro'yxat. Kesh yo'q / bo'sh / buzuq bo'lsa `null` — chaqiruvchi
  /// tarmoqdan oladi. Parse fon isolate'ida, UI bloklanmaydi.
  Future<List<ProductModelAdmin>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final list = await compute(parseProductsJson, raw);
      return list.isEmpty ? null : list;
    } catch (_) {
      // Buzuq kesh — jim o'tamiz, tarmoqdan yangisi keladi.
      return null;
    }
  }

  /// Serverdan kelgan XOM javobni keshga yozadi (parse qilinmaydi).
  Future<void> write(String raw) async {
    if (raw.trim().isEmpty) return;
    try {
      final f = await _file();
      await f.writeAsString(raw, flush: true);
    } catch (_) {
      // Disk to'la / ruxsat yo'q — kesh ixtiyoriy, jim o'tamiz.
    }
  }

  /// Logout: kesh faylini o'chiradi.
  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
