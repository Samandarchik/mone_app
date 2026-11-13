import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_navigator.dart';

/// Windows uchun to'liq avtomatik yangilanish xizmati.
///
/// Manba — GitHub Releases (public repo, autentifikatsiya kerak emas):
///   `https://github.com/{repo}/releases/latest`
/// `build_windows.bat` har build oxirida `publish_release.ps1` orqali zip'ni
/// shu repoga release qilib qo'yadi (tag = pubspec versiyasi, masalan v0.0.2).
///
/// Oqim: yangi versiya topilsa yopib bo'lmaydigan dialog chiqadi va DARHOL
/// o'zi yuklab boshlaydi -> zip %TEMP% ga tushadi -> ilova O'ZI (Dart'da)
/// zip'ni o'z papkasi ustiga ochadi. Windows'da ishlab turgan exe/dll'ni
/// o'chirib bo'lmaydi, lekin RENAME qilish mumkin — qulflangan fayllar
/// `.old_upd` nomiga ko'chirilib o'rniga yangisi yoziladi. So'ng yangi exe
/// ishga tushiriladi va eski jarayon yopiladi; `.old_upd` fayllar keyingi
/// ochilishda tozalanadi.
class WindowsUpdateService {
  /// Faqat zip'lar turadigan public releases repo.
  static const String _repo = 'Samandarchik/konak_pos_releases';

  /// Zip fayl nomi negizi (build_windows.bat bilan bir xil bo'lishi SHART).
  static const String _appSlug = 'konak_pos';

  static bool _dialogShowing = false;
  static bool _installing = false;

  // Bir vaqtda faqat BITTA tekshiruv yurishi uchun.
  static Future<bool>? _inflight;

  /// Mone ilovasi ichida Konak relizlari bilan avto-yangilanish O'CHIQ.
  static const bool _disabledInMone = true;

  static Timer? _periodicTimer;

  /// Ochiq turgan ilova yangi versiyani o'tkazib yubormasligi uchun davriy
  /// tekshiruv. Kassa kompyuterlarida dastur kun bo'yi yopilmaydi — faqat
  /// ochilishdagi tekshiruv bilan yangilanish keyingi restart'gacha yetib
  /// bormasdi. GitHub'ga so'rov redirect orqali (limitsiz), shuning uchun
  /// har 30 daqiqada tekshirish bemalol.
  static void startPeriodicChecks() {
    // Mone ilovasi ichida O'CHIQ: bu Konak kassa ilovasining relizlari
    // (konak_pos_releases) — Mone ilovasini almashtirib yubormasin.
    // Mone o'z yangilanish yo'lidan (do'kon / Mone relizlari) foydalanadi.
    if (_disabledInMone) return;
    if (!Platform.isWindows || !kReleaseMode) return;
    _periodicTimer ??= Timer.periodic(
      const Duration(minutes: 30),
      (_) => checkForUpdate(),
    );
  }

  static DateTime? _lastCheckAt;

  /// Yangi versiya bormi tekshiradi; bo'lsa avto-yangilash dialogini ochib
  /// `true` qaytaradi (chaqiruvchi navigatsiyani to'xtatishi kerak).
  /// Xatolik yoki yangilanish yo'q bo'lsa `false` — ilova odatdagidek ochiladi.
  /// Parallel chaqiruvlar bitta umumiy tekshiruvni kutadi.
  ///
  /// WSS har (qayta) ulanishda ham chaqiradi — tarmoq uzilib-ulanishida
  /// GitHub'ga so'rov yog'ilmasligi uchun oddiy chaqiruvlar 60 soniyadan
  /// siyraklashtiriladi. `force` — backend'dan "app:update_available"
  /// kelganda: bu aniq signal, throttle'siz darhol tekshiriladi.
  static Future<bool> checkForUpdate({bool force = false}) {
    if (_disabledInMone) return Future.value(false); // yuqoriga qarang
    final inflight = _inflight;
    if (inflight != null) return inflight;
    if (!force &&
        _lastCheckAt != null &&
        DateTime.now().difference(_lastCheckAt!) <
            const Duration(seconds: 60)) {
      return Future.value(false);
    }
    _lastCheckAt = DateTime.now();
    return _inflight =
        _checkForUpdate().whenComplete(() => _inflight = null);
  }

  static Future<bool> _checkForUpdate() async {
    if (!Platform.isWindows) return false;
    // flutter run / debug'da o'zini yangilashga urinmasin.
    if (!kReleaseMode) return false;
    cleanupLeftovers();
    try {
      final release = await _fetchLatestRelease();
      if (release == null) return false;

      final packageInfo = await PackageInfo.fromPlatform();
      // MUHIM: Windows'da PackageInfo.version "0.0.2+2" ko'rinishida
      // (build raqami bilan) keladi. '+build' qismini olib tashlamasak
      // "2+2" soni 0 deb o'qilib, ilova HAR ochilishda o'zini qayta
      // yuklab o'rnatadigan cheksiz sikl bo'ladi.
      final current = packageInfo.version.trim().split('+').first;

      if (!isNewerVersion(release.version, current)) return false;
      if (_dialogShowing) return true;

      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return true;

      _dialogShowing = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AutoUpdateDialog(
          release: release,
          currentVersion: current,
        ),
      ).whenComplete(() => _dialogShowing = false);
      return true;
    } catch (e) {
      debugPrint('❌ Windows yangilanish tekshiruvida xato: $e');
      return false;
    }
  }

  /// GitHub'dan eng so'nggi release versiyasini oladi.
  ///
  /// ATAYIN api.github.com ishlatilmaydi: API autentifikatsiyasiz soatiga
  /// 60 so'rov / IP bilan cheklangan — bitta ofisdagi barcha kassalar bir IP
  /// orqali chiqqanda limit tez tugab, yangilanish tekshiruvi ishlamay
  /// qolardi. O'rniga `github.com/<repo>/releases/latest` ning 302 redirect
  /// manzilidan (…/releases/tag/v0.0.2) versiya o'qiladi — bunda limit yo'q.
  /// Zip manzili esa deterministik: build_windows.bat doim
  /// `konak_pos_v<versiya>_windows.zip` nomi bilan chiqaradi.
  static Future<_ReleaseInfo?> _fetchLatestRelease() async {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    ).get(
      'https://github.com/$_repo/releases/latest',
      options: Options(
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );

    final location = response.headers.value('location') ?? '';
    final match = RegExp(r'/releases/tag/v?([0-9][0-9.]*)').firstMatch(location);
    if (match == null) {
      debugPrint(
          '⚠️ GitHub latest redirect topilmadi (status ${response.statusCode})');
      return null;
    }
    final version = match.group(1)!.split('+').first;

    return _ReleaseInfo(
      version: version,
      zipUrl: 'https://github.com/$_repo/releases/download/'
          'v$version/${_appSlug}_v${version}_windows.zip',
      sizeBytes: 0,
    );
  }

  /// `latest > current` bo'lsa true. Nuqta bilan ajratilgan sonlar sifatida.
  static bool isNewerVersion(String latest, String current) {
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final max = l.length > c.length ? l.length : c.length;
    for (int i = 0; i < max; i++) {
      final lp = i < l.length ? l[i] : 0;
      final cp = i < c.length ? c[i] : 0;
      if (lp > cp) return true;
      if (lp < cp) return false;
    }
    return false;
  }

  /// Yuklab olingan zip'ni ilova papkasi ustiga ochadi va ilovani qayta
  /// ishga tushiradi — hammasi shu jarayonning o'zida, tashqi skriptsiz.
  ///
  /// Windows'da ishlab turgan exe/dll fayllarning USTIGA yozib bo'lmaydi,
  /// lekin ularni RENAME qilish mumkin. Shundan foydalanamiz: qulflangan
  /// fayl `.old_upd` qo'shimchasi bilan qayta nomlanadi, o'rniga yangisi
  /// yoziladi. Keyin yangi exe ishga tushirilib bu jarayon yopiladi.
  /// `.old_upd` qoldiqlarini keyingi ochilishda [cleanupLeftovers] o'chiradi.
  static Future<void> installAndRestart(String zipPath) async {
    // Qo'shimcha himoya: qanday bo'lmasin ikki marta chaqirilsa ham
    // o'rnatish faqat bir marta yuradi.
    if (_installing) return;
    _installing = true;
    try {
      await _doInstallAndRestart(zipPath);
    } catch (_) {
      // Xato — dialog "Qayta urinish" ko'rsatadi, keyingi urinish yursin.
      _installing = false;
      rethrow;
    }
  }

  static Future<void> _doInstallAndRestart(String zipPath) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final sep = Platform.pathSeparator;

    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final entry in archive) {
      // Compress-Archive zip'larida yo'llar '\' bilan bo'lishi mumkin.
      final rel = entry.name.replaceAll('\\', '/');
      if (rel.isEmpty || rel.contains('..')) continue;

      final targetPath = '$appDir$sep${rel.replaceAll('/', sep)}';
      if (!entry.isFile) {
        Directory(targetPath).createSync(recursive: true);
        continue;
      }

      final target = File(targetPath);
      target.parent.createSync(recursive: true);
      final data = entry.readBytes();
      if (data == null) continue;

      try {
        target.writeAsBytesSync(data, flush: true);
      } on FileSystemException {
        // Fayl qulflangan (ishlab turgan exe/dll) — eskisini chetga
        // rename qilib o'rniga yangisini yozamiz. Rename ham xato bersa
        // (masalan Program Files'ga ruxsat yo'q) — tashqaridagi catch
        // dialogda xabar ko'rsatadi.
        final old = File('$targetPath.old_upd');
        try {
          if (old.existsSync()) old.deleteSync();
        } catch (_) {}
        target.renameSync(old.path);
        target.writeAsBytesSync(data, flush: true);
      }
    }

    // Zip endi kerak emas.
    try {
      await File(zipPath).delete();
    } catch (_) {}

    // Yangi exe'ni ishga tushirib, eski jarayonni yopamiz.
    await Process.start(exePath, const [],
        workingDirectory: appDir, mode: ProcessStartMode.detached);
    exit(0);
  }

  /// Oldingi yangilanishdan qolgan `.old_upd` fayllarni o'chiradi.
  /// Ochilishda chaqiriladi; hali qulflangan bo'lsa — jim o'tkazib
  /// yuboriladi, keyingi safar o'chadi.
  static void cleanupLeftovers() {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      for (final entity in appDir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.old_upd')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      final temp = Directory.systemTemp;
      for (final entity in temp.listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('${_appSlug}_update')) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

class _ReleaseInfo {
  const _ReleaseInfo({
    required this.version,
    required this.zipUrl,
    required this.sizeBytes,
  });

  final String version;
  final String zipUrl;
  final int sizeBytes;
}

/// Yopib bo'lmaydigan avto-yangilash dialogi: ochilishi bilan o'zi yuklab
/// boshlaydi, progress ko'rsatadi, tugagach o'zi o'rnatib qayta ishga
/// tushiradi. Xato bo'lsa "Qayta urinish" tugmasi chiqadi.
class _AutoUpdateDialog extends StatefulWidget {
  const _AutoUpdateDialog({
    required this.release,
    required this.currentVersion,
  });

  final _ReleaseInfo release;
  final String currentVersion;

  @override
  State<_AutoUpdateDialog> createState() => _AutoUpdateDialogState();
}

class _AutoUpdateDialogState extends State<_AutoUpdateDialog> {
  double _progress = 0; // 0..1
  bool _installing = false;
  String? _error;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _installing = false;
      _error = null;
      _progress = 0;
    });

    final zipPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}konak_pos_update_v${widget.release.version}.zip';

    try {
      _cancelToken = CancelToken();
      await Dio().download(
        widget.release.zipUrl,
        zipPath,
        cancelToken: _cancelToken,
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          headers: {'Accept': 'application/octet-stream'},
        ),
        onReceiveProgress: (received, total) {
          final t = total > 0 ? total : widget.release.sizeBytes;
          if (t > 0 && mounted) {
            setState(() => _progress = received / t);
          }
        },
      );

      if (!mounted) return;
      setState(() => _installing = true);
      // Progress UI ko'rinishi uchun kichik pauza, so'ng o'rnatish + restart.
      await Future.delayed(const Duration(milliseconds: 600));
      await WindowsUpdateService.installAndRestart(zipPath);
    } catch (e) {
      debugPrint('❌ Yangilanishni yuklab olishda xato: $e');
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error =
            'Yuklab olishda xatolik yuz berdi.\nInternetni tekshirib qayta urining.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    // `canPop` — xato bo'lganda YOKI hali yuklab olinayotganda dialogni
    // yopish mumkin. Ilgari u har doim `false` edi va yagona tugma
    // "Qayta urinish" bo'lgani uchun, GitHub ochilmasa yoki fayl nomi
    // mos kelmasa (404), kassir dialogdan CHIQA OLMASDI: butun terminal
    // Task Manager orqali o'ldirilmaguncha ishlamay turardi — smena
    // o'rtasida, yarim kiritilgan buyurtma ustida.
    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        title: const Text(
          'Yangilanish o\'rnatilmoqda',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hozirgi versiya: ${widget.currentVersion}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Text(
              'Yangi versiya: ${widget.release.version}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ] else if (_installing) ...[
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('O\'rnatilmoqda... dastur qayta ochiladi'),
                ],
              ),
            ] else ...[
              Text('Yuklab olinmoqda... $percent%'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
              ),
            ],
          ],
        ),
        actions: [
          // "Keyinroq" — o'rnatish BOSHLANMAGUNCHA doim mavjud.
          // O'rnatish boshlangach fayllar almashtirilayotgani uchun
          // to'xtatib bo'lmaydi.
          if (!_installing)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Keyinroq'),
            ),
          if (_error != null)
            TextButton(
              onPressed: _startDownload,
              child: const Text('Qayta urinish'),
            ),
        ],
      ),
    );
  }
}
