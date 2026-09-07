// core2/services/core_client.dart — mone_core (/api/v2) uchun ALOHIDA Dio
// klienti (CoreClient): manzil `AppUrls.coreApi` (runtime), token —
// SharedPreferences `core_token` (v1 `token` dan ALOHIDA), `Authorization:
// Bearer`. Xato javobi `{"error","code","details"}` → CoreApiException.
// Barcha core2 servislar `CoreClient.dio` orqali yuradi; yo'llar
// `CoreClient.url('/docs')` bilan quriladi (coreUrl almashsa darhol yangi
// manzil). Idempotency-Key — yozuvchi so'rovlarda ixtiyoriy (`idem()`).
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_dio_logger/talker_dio_logger_interceptor.dart';
import 'package:talker_dio_logger/talker_dio_logger_settings.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';

class CoreApiException implements Exception {
  final String message;
  final String code; // validation|not_found|forbidden|conflict|insufficient|…
  final int? status;
  final String perm; // 403 bo'lsa qaysi ruxsat yetmadi
  final Map<String, dynamic> details;

  const CoreApiException(
    this.message, {
    this.code = '',
    this.status,
    this.perm = '',
    this.details = const {},
  });

  bool get unauthorized => status == 401;
  bool get forbidden => status == 403;
  bool get insufficient => code == 'insufficient' || status == 422;
  bool get network => status == null;

  @override
  String toString() => message;
}

abstract final class CoreClient {
  static const String tokenKey = 'core_token';

  static Dio? _dio;

  static Dio get dio => _dio ??= _create();

  /// `/api/v2` + yo'l. Har chaqiruvda hisoblanadi — manzil sozlamadan
  /// o'zgarsa qayta ishga tushirish shart emas.
  static String url(String path) => '${AppUrls.coreApi}$path';

  static Dio _create() {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(tokenKey);
        options.headers['Content-Type'] = 'application/json';
        options.headers['Accept'] = 'application/json';
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
    d.interceptors.add(TalkerDioLogger(
      settings: const TalkerDioLoggerSettings(
        enabled: kDebugMode,
        printRequestData: true,
        printResponseData: true,
        printErrorData: true,
      ),
    ));
    return d;
  }

  /// Yozuvchi so'rov uchun Idempotency-Key sarlavhasi.
  static Options idem() => Options(headers: {
        'Idempotency-Key':
            '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}',
      });

  /// DioException → CoreApiException (server xabari, code, perm).
  static CoreApiException wrap(Object e) {
    if (e is CoreApiException) return e;
    if (e is DioException) {
      final r = e.response;
      if (r != null) {
        final data = r.data;
        if (data is Map) {
          return CoreApiException(
            (data['error'] ?? data['message'] ?? 'Server xatosi ${r.statusCode}')
                .toString(),
            code: (data['code'] ?? '').toString(),
            status: r.statusCode,
            perm: (data['perm'] ?? '').toString(),
            details: data['details'] is Map
                ? Map<String, dynamic>.from(data['details'] as Map)
                : const {},
          );
        }
        return CoreApiException('Server xatosi ${r.statusCode}',
            status: r.statusCode);
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return const CoreApiException('Yadro serveri javob bermadi (timeout)');
        case DioExceptionType.connectionError:
          return CoreApiException(
              'Yadro serveriga ulanib bo\'lmadi (${AppUrls.coreUrl})');
        default:
          return CoreApiException('Tarmoq xatosi: ${e.message}');
      }
    }
    return CoreApiException(e.toString());
  }

  /// Javobdagi ro'yxat: `[…]` yoki `{"items":[…]}` yoki `{"data":[…]}`.
  static List<Map<String, dynamic>> listOf(dynamic data) {
    dynamic raw = data;
    if (raw is Map) raw = raw['items'] ?? raw['data'] ?? raw['list'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  /// `{"items":[…],"total":N}` dagi total (yo'q bo'lsa items uzunligi).
  static int totalOf(dynamic data, int fallback) {
    if (data is Map && data['total'] is num) return (data['total'] as num).toInt();
    return fallback;
  }

  static Map<String, dynamic> mapOf(dynamic data) {
    if (data is Map) {
      final inner = data['data'];
      if (inner is Map && data.length == 1) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(data);
    }
    return const {};
  }
}
