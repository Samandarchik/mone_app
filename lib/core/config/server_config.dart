// core/config/server_config.dart — server manzillari RUNTIME'da sozlanadi
// (ServerConfig): `base_url` (v1 Mone backend, default prod domen) va
// `core_url` (v2 mone_core yadro, default http://localhost:1020).
// SharedPreferences'da saqlanadi; `setupInit()` da yuklanadi; `AppUrls`
// getterlari shu qiymatlarni o'qiydi, shuning uchun manzil almashtirilsa
// ilova qayta ishga tushirilmasdan yangi serverga yuboradi.
// Sozlash dialogi: lib/core/widgets/server_settings_dialog.dart.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ServerConfig {
  static const String defaultBaseUrl = 'https://moneapp.monebakeryuz.uz';
  static const String defaultCoreUrl = 'http://localhost:1020';

  static const String _kBase = 'base_url';
  static const String _kCore = 'core_url';

  static String _baseUrl = defaultBaseUrl;
  static String _coreUrl = defaultCoreUrl;

  /// v1 Mone backend manzili (sxema + host[:port], oxirida `/` yo'q).
  static String get baseUrl => _baseUrl;

  /// v2 mone_core yadro manzili (sxema + host[:port], oxirida `/` yo'q).
  static String get coreUrl => _coreUrl;

  /// Manzil o'zgarganda xabar beradi (Dio baseUrl, sozlama ekranlari).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Saqlangan qiymatlarni yuklash — main() → setupInit() da chaqiriladi.
  static void load(SharedPreferences prefs) {
    _baseUrl = normalize(prefs.getString(_kBase)) ?? defaultBaseUrl;
    _coreUrl = normalize(prefs.getString(_kCore)) ?? defaultCoreUrl;
  }

  /// Ikkala manzilni saqlash. Bo'sh qiymat — default'ga qaytadi.
  static Future<void> save({String? baseUrl, String? coreUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = normalize(baseUrl) ?? defaultBaseUrl;
    _coreUrl = normalize(coreUrl) ?? defaultCoreUrl;
    await prefs.setString(_kBase, _baseUrl);
    await prefs.setString(_kCore, _coreUrl);
    revision.value++;
  }

  /// Foydalanuvchi kiritgan matnni to'liq manzilga keltiradi:
  /// «localhost:1020» → «http://localhost:1020», «192.168.1.5» →
  /// «http://192.168.1.5», «moneapp.uz» → «https://moneapp.uz» (domen bo'lsa
  /// https, IP/localhost bo'lsa http). Oxiridagi `/` olib tashlanadi.
  /// Bo'sh matn → null.
  static String? normalize(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      final host = s.split(':').first.split('/').first;
      final isLocal = host == 'localhost' ||
          host == '127.0.0.1' ||
          RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
          host.endsWith('.local');
      s = (isLocal ? 'http://' : 'https://') + s;
    }
    return s;
  }

  /// `GET <coreUrl>/api/v2/health` — yadro ishlayaptimi. Javob `{"ok":true,
  /// "node":"…"}`; xatoda matnli sabab. Manzil berilmasa joriy coreUrl.
  static Future<HealthResult> checkCore([String? url]) async {
    final base = normalize(url) ?? _coreUrl;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final r = await dio.get('$base/api/v2/health');
      final data = r.data;
      if (data is Map && data['ok'] == true) {
        return HealthResult(ok: true, node: (data['node'] ?? '').toString());
      }
      return HealthResult(ok: false, error: 'Kutilmagan javob: $data');
    } on DioException catch (e) {
      return HealthResult(
          ok: false, error: e.message ?? e.type.name);
    } catch (e) {
      return HealthResult(ok: false, error: e.toString());
    }
  }

  /// `GET <baseUrl>/api/sklads` — v1 backend javob beryaptimi (401 ham
  /// «server bor» degani; faqat tarmoq xatosi «yo'q»).
  static Future<HealthResult> checkBase([String? url]) async {
    final base = normalize(url) ?? _baseUrl;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true,
      ));
      final r = await dio.get('$base/api/sklads');
      return HealthResult(ok: true, node: 'HTTP ${r.statusCode}');
    } on DioException catch (e) {
      return HealthResult(ok: false, error: e.message ?? e.type.name);
    } catch (e) {
      return HealthResult(ok: false, error: e.toString());
    }
  }
}

class HealthResult {
  final bool ok;
  final String node;
  final String error;
  const HealthResult({required this.ok, this.node = '', this.error = ''});
}
