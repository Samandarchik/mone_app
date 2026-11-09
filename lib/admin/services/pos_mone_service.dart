// admin/services/pos_mone_service.dart — POS Mone kassalari servisi (faqat
// admin): GET/POST /api/pos-mone/stations, kassa katalogi GET /api/pos-menu.
// Javob envelope: {success, message, data}.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/admin/model/pos_mone_station_model.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

class PosMoneService {
  final Dio dio = sl<Dio>();

  Future<List<PosMoneStation>> fetchStations() async {
    final data = await _get(AppUrls.posMoneStations);
    final list = data is Map ? data['stations'] : data;
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map) PosMoneStation.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  /// Kassani saqlash. [routes] null bo'lsa yo'naltirishlar o'zgarmaydi.
  Future<PosMoneStation?> saveStation({
    required String stationId,
    required String name,
    required int filialId,
    required int skladId,
    List<PosMoneSkladRoute>? routes,
  }) async {
    final data = await _post(AppUrls.posMoneStations, {
      'station_id': stationId,
      'name': name,
      'filial_id': filialId,
      'sklad_id': skladId,
      if (routes != null) 'sklad_routes': [for (final r in routes) r.toJson()],
    });
    if (data is Map) {
      return PosMoneStation.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Filial POS katalogi: (kategoriyalar, mahsulotlar) — kassa aynan shuni sotadi.
  Future<(List<PosMoneCatalogItem>, List<PosMoneCatalogItem>)> fetchCatalog(
      int filialId) async {
    final data = await _get(AppUrls.kassaMenu, query: {'filial_id': filialId});
    final cats = <PosMoneCatalogItem>[];
    final prods = <PosMoneCatalogItem>[];
    if (data is Map) {
      for (final c in (data['categories'] as List? ?? const [])) {
        if (c is Map) {
          cats.add(PosMoneCatalogItem(_int(c['id']), '${c['name'] ?? ''}'));
        }
      }
      for (final p in (data['products'] as List? ?? const [])) {
        if (p is Map) {
          prods.add(PosMoneCatalogItem(_int(p['id']), '${p['name'] ?? ''}',
              categoryId: _int(p['category_id'])));
        }
      }
    }
    return (cats, prods);
  }

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  Future<dynamic> _get(String url, {Map<String, dynamic>? query}) async {
    try {
      final r = await dio.get(url, queryParameters: query);
      return r.data is Map ? r.data['data'] : null;
    } on DioException catch (e) {
      throw _asException(e);
    }
  }

  Future<dynamic> _post(String url, Map<String, dynamic> body) async {
    try {
      final r = await dio.post(url, data: body);
      return r.data is Map ? r.data['data'] : null;
    } on DioException catch (e) {
      throw _asException(e);
    }
  }

  Exception _asException(DioException e) {
    if (e.response != null) {
      return Exception('Server xatosi: ${parseDioError(e)}');
    }
    return Exception('Tarmoq xatosi: ${e.message}');
  }
}
