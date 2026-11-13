import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_state.dart';

/// Video qo'llanmalar bulut serverda (nginx) turadi — local backend'da emas.
/// Shuning uchun manzil doim asosiy domen: restoran ichidagi Windows master
/// ham shu yerdan oladi (bir marta yuklanadi, keyin diskdan ochiladi).
const String kTutorialBaseUrl = '$kServerUrl/tutorials';

class TutorialVideo {
  final String id;
  final String title;
  final String file;
  final String? poster;
  final int durationSec;
  final int sizeBytes;
  final List<String> keys;
  final String groupId;
  final bool isFull;

  const TutorialVideo({
    required this.id,
    required this.title,
    required this.file,
    required this.poster,
    required this.durationSec,
    required this.sizeBytes,
    required this.keys,
    required this.groupId,
    this.isFull = false,
  });

  factory TutorialVideo.fromJson(
    Map<String, dynamic> j,
    String groupId, {
    bool isFull = false,
  }) =>
      TutorialVideo(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        file: (j['file'] ?? '').toString(),
        poster: j['poster']?.toString(),
        durationSec: (j['duration'] as num?)?.round() ?? 0,
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        keys: ((j['keys'] as List?) ?? const []).map((e) => '$e').toList(),
        groupId: groupId,
        isFull: isFull,
      );

  String get url => '$kTutorialBaseUrl/$file';
  String? get posterUrl => poster == null ? null : '$kTutorialBaseUrl/$poster';

  String get durationLabel {
    final m = durationSec ~/ 60, s = durationSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class TutorialGroup {
  final String id;
  final String title;

  /// Qaysi rollarga ko'rinadi. Bo'sh — hammaga.
  final List<String> roles;
  final TutorialVideo? full;
  final List<TutorialVideo> videos;

  const TutorialGroup({
    required this.id,
    required this.title,
    required this.roles,
    required this.full,
    required this.videos,
  });

  factory TutorialGroup.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString();
    final full = j['full'];
    return TutorialGroup(
      id: id,
      title: (j['title'] ?? '').toString(),
      roles: ((j['roles'] as List?) ?? const []).map((e) => '$e').toList(),
      full: full is Map<String, dynamic>
          ? TutorialVideo.fromJson(full, id, isFull: true)
          : null,
      videos: ((j['videos'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((v) => TutorialVideo.fromJson(v, id))
          .toList(),
    );
  }

  bool visibleFor(String? role) =>
      roles.isEmpty || (role != null && roles.contains(role));
}

/// Qo'llanmalar ro'yxati (server `manifest.json`) va yuklab olingan videolar.
///
/// Manifest serverda turadi — yangi video qo'shish uchun ilovani qayta
/// chiqarish shart emas. Oxirgi muvaffaqiyatli nusxa prefs'da saqlanadi,
/// internet bo'lmasa ham «i» tugmalari va ro'yxat ishlayveradi.
class TutorialService extends ChangeNotifier {
  static final TutorialService _instance = TutorialService._();
  factory TutorialService() => _instance;
  TutorialService._();

  static const _prefsKey = 'tutorials_manifest';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 10),
  ));

  List<TutorialGroup> _groups = const [];
  bool _loaded = false;
  Future<void>? _loading;

  /// id → yuklab olish jarayoni (0..1). Ro'yxat va pleyer shuni kuzatadi.
  final Map<String, double> progress = {};
  final Set<String> _downloaded = {};

  bool get loaded => _loaded;

  List<TutorialGroup> groupsFor(String? role) =>
      _groups.where((g) => g.visibleFor(role)).toList();

  /// Shu ekran (kalit) uchun videolar — rolga qarab. Admin uchun avval
  /// o'z guruhi (super admin), keyin kassirniki chiqadi.
  List<TutorialVideo> videosFor(String key, String? role) => [
        for (final g in groupsFor(role).reversed)
          for (final v in g.videos)
            if (v.keys.contains(key)) v,
      ];

  /// Ekranda ishlatiladigan rol (login'da AppState'ga yoziladi).
  String? get role => AppState().role;

  Future<void> ensureLoaded() => _loading ??= _load();

  /// Qayta yuklash (ro'yxat ekranida pastga tortilganda).
  Future<void> refresh() {
    _loading = _load(force: true);
    return _loading!;
  }

  Future<void> _load({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!_loaded) {
      final cached = prefs.getString(_prefsKey);
      if (cached != null) _apply(cached);
    }
    try {
      final r = await _dio.get<String>(
        '$kTutorialBaseUrl/manifest.json',
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch ~/ 60000},
        options: Options(responseType: ResponseType.plain),
      );
      final body = r.data;
      if (body != null && _apply(body)) {
        await prefs.setString(_prefsKey, body);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('TUTORIAL: manifest olinmadi: $e');
    }
    await _scanDownloaded();
    _loaded = true;
    notifyListeners();
  }

  bool _apply(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      _groups = ((j['groups'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TutorialGroup.fromJson)
          .toList();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('TUTORIAL: manifest buzuq: $e');
      return false;
    }
  }

  // ---------------- yuklab olish ----------------

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}tutorials');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  String _name(TutorialVideo v) => v.file.replaceAll('/', '__');

  Future<File> localFile(TutorialVideo v) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}${_name(v)}');

  bool isDownloaded(TutorialVideo v) => _downloaded.contains(v.file);
  bool isDownloading(TutorialVideo v) => progress.containsKey(v.file);

  Future<void> _scanDownloaded() async {
    if (kIsWeb) return;
    try {
      for (final g in _groups) {
        for (final v in [?g.full, ...g.videos]) {
          final f = await localFile(v);
          // Hajmi mos kelmasa — chala yoki eski nusxa, hisobga olinmaydi.
          if (f.existsSync() &&
              (v.sizeBytes == 0 || f.lengthSync() == v.sizeBytes)) {
            _downloaded.add(v.file);
          }
        }
      }
    } catch (_) {}
  }

  /// Videoni diskka yuklaydi (bor bo'lsa — darhol qaytaradi).
  /// Chala fayl `.part` nomi bilan yoziladi, tugagach o'zgartiriladi —
  /// uzilib qolsa keyingi safar buzuq video ochilmaydi.
  Future<File> download(TutorialVideo v) async {
    final f = await localFile(v);
    if (isDownloaded(v) && f.existsSync()) return f;
    final part = File('${f.path}.part');
    progress[v.file] = 0;
    notifyListeners();
    try {
      await _dio.download(
        v.url,
        part.path,
        onReceiveProgress: (got, total) {
          final t = total > 0 ? total : v.sizeBytes;
          if (t > 0) {
            progress[v.file] = (got / t).clamp(0, 1).toDouble();
            notifyListeners();
          }
        },
      );
      if (f.existsSync()) f.deleteSync();
      part.renameSync(f.path);
      _downloaded.add(v.file);
      return f;
    } finally {
      progress.remove(v.file);
      notifyListeners();
    }
  }

  Future<void> deleteDownload(TutorialVideo v) async {
    final f = await localFile(v);
    if (f.existsSync()) f.deleteSync();
    _downloaded.remove(v.file);
    notifyListeners();
  }
}
