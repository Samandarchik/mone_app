// admin/services/sh5_service.dart — SH5 (StoreHouse) qoldiq + smena
// topshirish/qabul servisi: omborlar ro'yxati, ombor tovarlari, bridge'dan
// yangilash so'rovi, topshiriq qoralamasi/saqlash/qabul/tarix.
// Endpointlar: /api/sh5/remains[/{id}], /api/sh5/refresh, /api/sh5/handover*,
// /api/sh5/recipes/by-dish/{dish_guid}, /api/sh5/recipes/apply.
// Javob envelope: {success, message, data}.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/admin/model/sh5_handover_model.dart';
import 'package:uz_ai_dev/admin/model/sh5_recipe_model.dart';
import 'package:uz_ai_dev/admin/model/sh5_remain_model.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

// SH5 qoldiq servisi (rk7_service naqshida, token global Dio interceptor
// orqali qo'shiladi). Ruxsat backendda tekshiriladi: admin hamma omborni,
// sotuvchi faqat o'ziga biriktirilganini oladi.
class Sh5Service {
  final Dio dio = sl<Dio>();

  /// SH5 omborlari ro'yxati (nom bo'yicha tartiblangan, taken_at bilan).
  Future<List<Sh5RemainSklad>> fetchSklads() async {
    final data = await _get(AppUrls.sh5Remains);
    final raw = data is Map ? data['sklads'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Sh5RemainSklad.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Bitta ombor tovarlari; [q] — nom bo'yicha qidiruv (bo'sh = hammasi).
  Future<Sh5RemainDetail?> fetchDetail(int id, {String q = ''}) async {
    final query = q.trim();
    final data = await _get(
      AppUrls.sh5Remain(id),
      query: query.isEmpty ? null : {'q': query},
    );
    if (data is Map) {
      return Sh5RemainDetail.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Bridge'ga «qoldiqni qayta o'qi» so'rovi (kassir «yangilash» bosganda).
  /// Javob darhol qaytadi — bridge push qilgach `taken_at` yangilanadi.
  Future<void> requestRefresh() async {
    await _post(AppUrls.sh5Refresh, null);
  }

  /// Topshirish qoralamasi: StoreHouse sonlari + oldingi smena sonlari.
  Future<Sh5HandoverDraft?> fetchDraft(int skladId) async {
    final data = await _get(AppUrls.sh5HandoverDraft,
        query: {'sklad_id': skladId});
    if (data is Map) {
      return Sh5HandoverDraft.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Qabul kutayotgan topshiriq (yo'q bo'lsa null).
  Future<Sh5Handover?> fetchOpen(int skladId) async {
    final data =
        await _get(AppUrls.sh5HandoverOpen, query: {'sklad_id': skladId});
    if (data is Map) {
      return Sh5Handover.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Smenani topshirish. [qtyByRid] — FAQAT StoreHouse sonidan farq qilgan
  /// qatorlar (qolganlari serverda StoreHouse soni bilan yoziladi).
  Future<Sh5Handover?> submitHandover({
    required int skladId,
    required Map<int, int> qtyByRid,
    String note = '',
  }) async {
    final data = await _post(AppUrls.sh5Handover, {
      'sklad_id': skladId,
      'note': note,
      'items': _items(qtyByRid),
    });
    if (data is Map) {
      return Sh5Handover.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Topshiriqni qabul qilish. [qtyByRid] — FAQAT topshirilgan sondan farq
  /// qilgan qatorlar.
  Future<Sh5Handover?> acceptHandover({
    required int handoverId,
    required Map<int, int> qtyByRid,
    String note = '',
  }) async {
    final data = await _post(AppUrls.sh5HandoverAccept(handoverId), {
      'note': note,
      'items': _items(qtyByRid),
    });
    if (data is Map) {
      return Sh5Handover.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Topshiriqlar tarixi (yangisi birinchi). [skladId] null — ruxsat berilgan
  /// hamma ombor bo'yicha.
  Future<List<Sh5Handover>> fetchHandovers({int? skladId, int days = 30}) async {
    final data = await _get(AppUrls.sh5Handovers, query: {
      if (skladId != null) 'sklad_id': skladId,
      'days': days,
    });
    final raw = data is Map ? data['handovers'] : data;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Sh5Handover.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Bitta topshiriq. [onlyDiff] — faqat farq chiqqan qatorlar.
  Future<Sh5Handover?> fetchHandover(int id, {bool onlyDiff = false}) async {
    final data = await _get(AppUrls.sh5HandoverDetail(id),
        query: onlyDiff ? {'diff': 1} : null);
    if (data is Map) {
      return Sh5Handover.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  // ──────────────────── Retsept (kalkulyatsiya) — PLAN_RETSEPT ────────────────────

  /// RK7 taomiga mos SH5 retsepti + har ingredientning Mone mahsulotiga
  /// moslash natijasi. Retsept topilmasa (404 yoki bo'sh) — null qaytadi va
  /// UI «SH5 retsepti» bo'limini umuman ko'rsatmaydi.
  Future<Sh5DishRecipe?> fetchRecipeByDish(String dishGuid) async {
    try {
      final response = await dio.get(AppUrls.sh5RecipeByDish(dishGuid));
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! Map) return null;
      final recipe = Sh5DishRecipe.fromJson(Map<String, dynamic>.from(data));
      return recipe.ingredients.isEmpty ? null : recipe;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      if (e.response != null) {
        throw Exception('Server xatosi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  /// Retseptni mahsulotga tex karta qilib qo'llash. [overwrite] — mavjud tex
  /// kartani almashtirishga admin rozi bo'lgandagina true.
  ///
  /// 409 (mavjud tex karta yoki mos kelmagan ingredientlar) —
  /// [Sh5RecipeApplyException] ko'tariladi, UI shunga qarab tasdiq so'raydi
  /// yoki qizil ro'yxatni ko'rsatadi.
  Future<void> applyRecipe({
    required String dishGuid,
    bool overwrite = false,
  }) async {
    try {
      await dio.post(AppUrls.sh5RecipeApply, data: {
        'dish_guid': dishGuid,
        'overwrite': overwrite,
      });
    } on DioException catch (e) {
      final response = e.response;
      if (response?.statusCode == 409) {
        throw Sh5RecipeApplyException.fromResponse(
          response?.data,
          parseDioError(e, fallback: 'Retsept qo\'llanmadi'),
        );
      }
      if (response != null) {
        throw Exception('Server xatosi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  // rid → milli BUTUN son ro'yxati (serverga float yuborilmaydi).
  List<Map<String, int>> _items(Map<int, int> qtyByRid) {
    return qtyByRid.entries
        .map((e) => {'rid': e.key, 'qty_milli': e.value})
        .toList();
  }

  Future<dynamic> _post(String url, Object? body) async {
    try {
      final response = await dio.post(url, data: body);
      return response.data is Map ? response.data['data'] : null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(parseDioError(e));
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  Future<dynamic> _get(String url, {Map<String, dynamic>? query}) async {
    try {
      final response = await dio.get(url, queryParameters: query);
      return response.data is Map ? response.data['data'] : null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Server xatosi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }
}
