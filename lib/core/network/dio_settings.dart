// core/network/dio_settings.dart — Dio klientini quradi (AppDioClient.createDio):
// baseUrl, Bearer token interceptor, X-Qty-Unit: milli header (гр/мл kontrakti)
// va faqat-debug TalkerDioLogger.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talker_dio_logger/talker_dio_logger_interceptor.dart';
import 'package:talker_dio_logger/talker_dio_logger_settings.dart';
import 'package:uz_ai_dev/core/config/server_config.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';

// Debug logga yoziladigan javob tanasining eng katta uzunligi (belgi).
const int _kMaxLoggedBodyChars = 4000;

// Javob tanasini logga chiqarishdan oldin qisqartiradi (yuqoridagi sabab).
String _shortLogBody(Response response) {
  final data = response.data;
  String text;
  try {
    text = data is String ? data : jsonEncode(data);
  } catch (_) {
    text = data.toString();
  }
  if (text.length <= _kMaxLoggedBodyChars) return text;
  return '${text.substring(0, _kMaxLoggedBodyChars)}\n'
      '… (jami ${text.length} belgi — log uchun qisqartirildi)';
}

class AppDioClient {
  Dio createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppUrls.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    // Sozlamada server manzili almashtirilsa Dio baseUrl ham yangilanadi
    // (AppUrls manzillari absolyut, lekin nisbiy yo'l ishlatilgan joy uchun).
    ServerConfig.revision.addListener(() {
      dio.options.baseUrl = AppUrls.baseUrl;
    });

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString("token");

          options.headers['Content-Type'] = 'application/json';
          options.headers['Accept'] = 'application/json';
          // Yangi klient belgisi: кг/л miqdorlar гр/мл BUTUN son tilida
          // yuriladi. Belgisiz so'rovni server eski (kg/l tilli) APK deb
          // bilib, qiymatlarni o'zi konvert qiladi — bu headerni OLIB
          // TASHLAMANG (backend legacy_qty.go bilan juft ishlaydi).
          options.headers['X-Qty-Unit'] = 'milli';

          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          return handler.next(options);
        },
      ),
    );

    dio.interceptors.add(
      TalkerDioLogger(
        settings: TalkerDioLoggerSettings(
          // Faqat debug rejimda: release'da Bearer token va barcha so'rov/javob
          // tanalari qurilma loglariga yozilib qolmasin (xavfsizlik).
          enabled: kDebugMode,
          printRequestHeaders: true,
          printRequestData: true,
          printResponseData: true,
          printErrorData: true,
          printErrorMessage: true,
          // Katta javob tanasi logga TO'LIQ yozilmaydi. `/api/products/all`
          // ~1.6 MB — uni logcat'ga yozish MAIN THREAD ni `writev` da ushlab
          // turadi va Android ANR («isn't responding») beradi (ANR trace'da
          // main thread `__android_log_print` ichida edi). Debug loglar
          // qoladi, faqat tanasi qisqartiriladi.
          responseDataConverter: _shortLogBody,
        ),
      ),
    );

    return dio;
  }
}
