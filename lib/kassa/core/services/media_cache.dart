import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

/// Menyu rasmlarini diskda saqlaydigan kesh.
///
/// **Rasm doim asosiy (online) serverdan olinadi.** Fayllar local↔cloud
/// o'rtasida 60 soniyada bir replikatsiya qilinadi, shuning uchun faol
/// manzilga qarab yuklash "bazada rasm bor, lekin ochilmadi" xatosini berardi
/// (masalan rasm cloudda almashtirilgan, local hali olmagan). Asosiy server —
/// yagona doimiy manzil, qolgani keshdan chiqadi.
///
/// Yuklab olingan fayl `<app-support>/media_cache/` ichida saqlanadi va
/// qaytadan so'ralmaydi: rasm almashtirilganda backend yangi nom beradi
/// (`12_1755331200.jpg`), demak eski kesh hech qachon "eskirgan" bo'lmaydi.
class MediaCache {
  static final MediaCache _instance = MediaCache._();
  factory MediaCache() => _instance;
  MediaCache._();

  Directory? _dir;
  Future<Directory?>? _dirFuture;
  final Map<String, Future<File?>> _inflight = {};

  Future<Directory?> _cacheDir() {
    if (_dir != null) return Future.value(_dir);
    return _dirFuture ??= () async {
      try {
        final base = await getApplicationSupportDirectory();
        final dir = Directory('${base.path}${Platform.pathSeparator}media_cache');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _dir = dir;
        return dir;
      } catch (_) {
        return null;
      }
    }();
  }

  /// `/uploads/products/12_1755.jpg` → `uploads_products_12_1755.jpg`
  String _fileNameFor(String path) => path
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Rasmni keshdan (bo'lmasa serverdan) olish. Hech qayerdan topilmasa `null`.
  Future<File?> fetch(String path) {
    if (kIsWeb || path.trim().isEmpty) return Future.value(null);
    return _inflight[path] ??= _fetch(path).whenComplete(() {
      _inflight.remove(path);
    });
  }

  Future<File?> _fetch(String path) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final file = File('${dir.path}${Platform.pathSeparator}${_fileNameFor(path)}');
    if (file.existsSync() && file.lengthSync() > 0) return file;

    // 1) Asosiy server. 2) U yetib bo'lmasa (internet yo'q) — faol manzil:
    // Windows master'da rasm aynan shu yerda yuklangan bo'lishi mumkin.
    final sources = <String>{
      ApiService().mediaBaseUrl,
      ApiService().baseUrl,
    };
    for (final base in sources) {
      final bytes = await _download('$base$path');
      if (bytes == null) continue;
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (_) {
        return null;
      }
      return file;
    }
    return null;
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'ngrok-skip-browser-warning': 'true'},
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final data = res.data;
      if (res.statusCode != 200 || data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  /// Yangi yuklangan rasmni darhol keshga qo'yish — server tomonga
  /// replikatsiya tugashini (≤60s) kutmasdan ekranda ko'rinadi.
  Future<void> putFile(String path, String sourceFilePath) async {
    if (kIsWeb || path.trim().isEmpty) return;
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      await File(sourceFilePath).copy(
        '${dir.path}${Platform.pathSeparator}${_fileNameFor(path)}',
      );
    } catch (_) {}
  }

  /// Rasmni keshdan olib tashlash (masalan xato fayl saqlanib qolgan bo'lsa).
  Future<void> evict(String path) async {
    if (kIsWeb) return;
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      final file =
          File('${dir.path}${Platform.pathSeparator}${_fileNameFor(path)}');
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Menyudan chiqib ketgan rasmlar diskda to'planib qolmasin — 90 kundan beri
  /// tegilmagan fayllar o'chiriladi (ilova ochilishida bir marta).
  Future<void> prune({Duration maxAge = const Duration(days: 90)}) async {
    if (kIsWeb) return;
    try {
      final dir = await _cacheDir();
      if (dir == null) return;
      final deadline = DateTime.now().subtract(maxAge);
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (entity.statSync().modified.isBefore(deadline)) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
