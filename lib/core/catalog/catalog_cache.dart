// core/catalog/catalog_cache.dart — katalog (GET /api/products) javobining
// LOKAL keshi (CatalogCache), HAMMA rol uchun. Javob admin/shef uchun
// (?include=recipe) ~1.6 MB bo'lishi mumkin: XOM MATN holida app papkasidagi
// faylga yoziladi, o'qishda `compute()` — FON isolate'ida parse qilinadi
// (UI oqimida 1000+ marta fromJson chaqirilsa Android ANR berardi).
//
// Oqim (CatalogRepository.load): kesh o'qiladi -> ro'yxat DARHOL ko'rinadi ->
// fonda tarmoqdan yangilanadi. Logout'da (`clear`) fayl O'CHIRILADI — boshqa
// foydalanuvchiga (boshqa rol/filial — server filtri!) o'tmaydi.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';

// FON isolate'ida bajariladi (compute uchun TOP-LEVEL bo'lishi shart):
// xom JSON -> modellar. `{"data": [...]}` ham, to'g'ridan-to'g'ri massiv ham.
List<Product> parseCatalogJson(String raw) {
  if (raw.trim().isEmpty) return [];
  return Product.listFromJson(jsonDecode(raw));
}

class CatalogCache {
  static const String _fileName = 'catalog.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Keshdagi ro'yxat. Kesh yo'q / bo'sh / buzuq bo'lsa `null` — chaqiruvchi
  /// tarmoqdan oladi. Parse fon isolate'ida, UI bloklanmaydi.
  Future<List<Product>?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      final list = await compute(parseCatalogJson, raw);
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
