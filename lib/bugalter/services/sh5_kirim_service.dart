// bugalter/services/sh5_kirim_service.dart — «SH5 kirim» servisi
// (PLAN_KIRIM §4.3): kun ro'yxati, SH5 tovar qidiruvi, mapping (PUT/DELETE),
// SH5 ga yuborish, hujjat statuslari, SH5 login/paroli va sozlamalar.
//
// Bearer token va `X-Qty-Unit: milli` headerlari global Dio interceptor'da
// qo'shiladi (core/network/dio_settings.dart) — bu yerda qo'lda yozilmaydi.
// Javob envelope'i: {success, message, data}.
//
// Ruxsat backendda tekshiriladi (bugalter roli yoki admin) — ekran rolni
// O'ZI tekshirmaydi, 403 kelsa xato matni ko'rsatiladi.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/bugalter/model/sh5_kirim_model.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

/// `POST /send` natijasi. Uch holat bo'lishi mumkin:
///   • [needCredentials] — 428: SH5 login/parol so'raladi, keyin qayta send;
///   • [unmapped] bo'sh emas — 400: shu key'lar avval bog'lanishi kerak;
///   • [docs] — hujjatlar navbatga qo'yildi (`queued`).
class Sh5KirimSendResult {
  final List<Sh5KirimDoc> docs;
  final bool needCredentials;
  final List<String> unmapped;
  final String message;

  /// Hamma qatori «SH5'da yo'q» bo'lgan buyurtmalar (`skipped_orders`) —
  /// ular uchun hujjat YARATILMAYDI.
  final List<int> skippedOrders;

  const Sh5KirimSendResult({
    this.docs = const [],
    this.needCredentials = false,
    this.unmapped = const [],
    this.message = '',
    this.skippedOrders = const [],
  });

  bool get isOk => !needCredentials && unmapped.isEmpty;
}

class Sh5KirimService {
  final Dio dio = sl<Dio>();

  // ─────────────────────────── Kun ro'yxati ───────────────────────────

  /// Bir kunning narxlangan bozor buyurtmalari (mapping va SH5 hujjat
  /// statusi bilan). [date] — «YYYY-MM-DD».
  Future<Sh5KirimDay> getDay(String date) async {
    final data = await _get(AppUrls.sh5KirimDay, query: {'date': date});
    if (data is Map) {
      return Sh5KirimDay.fromJson(Map<String, dynamic>.from(data));
    }
    return Sh5KirimDay(date: date);
  }

  // ─────────────────────────── Tovar qidiruvi ───────────────────────────

  /// SH5 tovar lug'ati bo'yicha qidiruv (bog'lash dialogi).
  Future<List<Sh5KirimGood>> searchGoods(String q, {int limit = 30}) async {
    final data = await _get(AppUrls.sh5KirimGoods, query: {
      'q': q.trim(),
      'limit': limit,
    });
    final raw = data is Map ? data['items'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Sh5KirimGood.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  // ─────────────────────────── Mapping ───────────────────────────

  /// Mone mahsulotini SH5 tovariga bog'lash (`manual` — eng ustun manba).
  ///
  /// [skip] `true` bo'lsa — «SH5'da yo'q, o'tkazib yuborilsin»: server
  /// `source: "skip"`, `sh5_rid: 0` mapping yozadi, mahsulot bog'langan
  /// hisoblanadi, lekin hujjatga qo'shilmaydi ([sh5Rid] e'tiborga olinmaydi).
  Future<void> setMap({
    required String key,
    required int productId,
    required String productName,
    int sh5Rid = 0,
    bool skip = false,
  }) async {
    try {
      await dio.put(AppUrls.sh5KirimMap, data: {
        'key': key,
        'product_id': productId,
        'product_name': productName,
        if (skip) 'skip': true else 'sh5_rid': sh5Rid,
      });
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }

  /// Bog'lanishni o'chirish (keyin mahsulot yana «bog'lanmagan» bo'ladi).
  Future<void> deleteMap(String key) async {
    try {
      await dio.delete(AppUrls.sh5KirimMap, queryParameters: {'key': key});
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }

  // ─────────────────────────── Yuborish ───────────────────────────

  /// Tanlangan buyurtmalarni SH5 navbatiga qo'yish. Xato holatlari
  /// ([Sh5KirimSendResult]) EXCEPTION emas — UI ularni alohida ko'rsatadi.
  Future<Sh5KirimSendResult> send({
    required String date,
    required List<int> orderIds,
  }) async {
    try {
      final response = await dio.post(AppUrls.sh5KirimSend, data: {
        'date': date,
        'order_ids': orderIds,
      });
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      final raw = data is Map ? data['docs'] : null;
      final rawSkipped = data is Map ? data['skipped_orders'] : null;
      return Sh5KirimSendResult(
        docs: raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Sh5KirimDoc.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
            : const [],
        // Hamma qatori o'tkazilgan buyurtmalar — hujjat yaratilmadi.
        skippedOrders: rawSkipped is List
            ? rawSkipped
                .map((e) => e is num
                    ? e.toInt()
                    : (int.tryParse(e?.toString() ?? '') ?? 0))
                .where((e) => e > 0)
                .toList(growable: false)
            : const [],
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      // 428 va 400 javoblarida qo'shimcha maydonlar top-level'da ham,
      // `data` ichida ham kelishi mumkin — ikkalasi ham qaraladi.
      final Map? flat = body is Map ? body : null;
      final Map? inner = flat != null && flat['data'] is Map
          ? flat['data'] as Map
          : null;
      dynamic field(String name) => inner?[name] ?? flat?[name];

      if (status == 428 || field('need_credentials') == true) {
        return Sh5KirimSendResult(
          needCredentials: true,
          message: _error(e, fallback: 'SH5 login/paroli kerak'),
        );
      }
      final unmapped = field('unmapped');
      if (unmapped is List && unmapped.isNotEmpty) {
        return Sh5KirimSendResult(
          unmapped: unmapped.map((e) => e.toString()).toList(growable: false),
          message: _error(e, fallback: 'Bog\'lanmagan mahsulot bor'),
        );
      }
      throw Exception(_error(e));
    }
  }

  // ─────────────────────────── Hujjat statuslari ───────────────────────────

  /// Kun hujjatlari (ekran 3 s da so'raydi, hammasi `done/error` bo'lguncha).
  Future<List<Sh5KirimDoc>> getDocs(String date) async {
    final data = await _get(AppUrls.sh5KirimDocs, query: {'date': date});
    final raw = data is Map ? data['docs'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Sh5KirimDoc.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Xato bo'lgan hujjatni qayta navbatga qo'yish (`error` → `queued`).
  Future<void> retryDoc(int id) async {
    await _post(AppUrls.sh5KirimDocRetry(id), null);
  }

  // ─────────────────────────── SH5 login/paroli ───────────────────────────

  /// Saqlangan SH5 foydalanuvchisi (parol qaytmaydi).
  Future<Sh5KirimCredentials> getCredentials() async {
    final data = await _get(AppUrls.sh5KirimCredentials);
    if (data is Map) {
      return Sh5KirimCredentials.fromJson(Map<String, dynamic>.from(data));
    }
    return const Sh5KirimCredentials();
  }

  /// SH5 login/parolini saqlash — bir marta kiritiladi, keyin so'ralmaydi.
  Future<void> saveCredentials({
    required String user,
    required String pass,
  }) async {
    await _post(AppUrls.sh5KirimCredentials, {
      'sh5_user': user,
      'sh5_pass': pass,
    });
  }

  /// Saqlangan login/parolni o'chirish.
  Future<void> deleteCredentials() async {
    try {
      await dio.delete(AppUrls.sh5KirimCredentials);
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }

  // ─────────────────────────── Sozlamalar ───────────────────────────

  /// Sklad ↔ SH5 ombor, manba ↔ kontragent xaritalari + dropdown ro'yxatlari.
  Future<Sh5KirimSettings> getSettings() async {
    final data = await _get(AppUrls.sh5KirimSettings);
    if (data is Map) {
      return Sh5KirimSettings.fromJson(Map<String, dynamic>.from(data));
    }
    return const Sh5KirimSettings();
  }

  /// Sozlamalarni saqlash (faqat juftliklar yuboriladi, lug'atlar emas).
  Future<void> saveSettings({
    required List<Sh5KirimSkladMap> sklads,
    required List<Sh5KirimSourceMap> sources,
  }) async {
    try {
      await dio.put(AppUrls.sh5KirimSettings, data: {
        'sklads': [
          for (final s in sklads)
            {'sklad_id': s.skladId, 'dep_rid': s.depRid},
        ],
        'sources': [
          for (final s in sources) {'source': s.source, 'cntr_rid': s.cntrRid},
        ],
      });
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }

  // ─────────────────────────── Umumiy ───────────────────────────

  String _error(DioException e, {String fallback = 'Noma\'lum server xatosi'}) {
    if (e.response != null) {
      return 'Server xatosi: ${parseDioError(e, fallback: fallback)}';
    }
    return 'Tarmoq xatosi: ${e.message}';
  }

  Future<dynamic> _get(String url, {Map<String, dynamic>? query}) async {
    try {
      final response = await dio.get(url, queryParameters: query);
      return response.data is Map ? response.data['data'] : null;
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }

  Future<dynamic> _post(String url, Object? body) async {
    try {
      final response = await dio.post(url, data: body);
      return response.data is Map ? response.data['data'] : null;
    } on DioException catch (e) {
      throw Exception(_error(e));
    }
  }
}
