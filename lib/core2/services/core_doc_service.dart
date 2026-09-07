// core2/services/core_doc_service.dart — mone_core hujjatlari:
// list (GET /docs filtrlar bilan, qatorlarsiz), get (GET /docs/{id} to'liq),
// create (POST /docs — draft), update (PUT /docs/{id}), delete, post
// (POST /docs/{id}/post → doc + warnings), cancel, quick (POST /docs/quick —
// yaratish + post bitta so'rovda; bozorchi приход, inventar).
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreDocService {
  Future<CoreDocPage> list({
    String? type,
    String? status,
    String? dateFrom,
    String? dateTo,
    int? sklad,
    String? source,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/docs'),
        queryParameters: {
          if (type != null && type.isNotEmpty) 'type': type,
          if (status != null && status.isNotEmpty) 'status': status,
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
          if (sklad != null) 'sklad': sklad,
          if (source != null && source.isNotEmpty) 'source': source,
          if (search.isNotEmpty) 'search': search,
          'limit': limit,
          'offset': offset,
        },
      );
      final items = CoreClient.listOf(r.data).map(CoreDoc.fromJson).toList();
      return CoreDocPage(
          items: items, total: CoreClient.totalOf(r.data, items.length));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreDoc> get(int id) async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/docs/$id'));
      return CoreDoc.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreDoc> create(CoreDoc doc) async {
    try {
      final r = await CoreClient.dio.post(CoreClient.url('/docs'),
          data: doc.toJson(), options: CoreClient.idem());
      return CoreDoc.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreDoc> update(int id, CoreDoc doc) async {
    try {
      final r = await CoreClient.dio
          .put(CoreClient.url('/docs/$id'), data: doc.toJson());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? doc : CoreDoc.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<void> delete(int id) async {
    try {
      await CoreClient.dio.delete(CoreClient.url('/docs/$id'));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreDocPostResult> post(int id) async {
    try {
      final r = await CoreClient.dio.post(CoreClient.url('/docs/$id/post'),
          options: CoreClient.idem());
      return CoreDocPostResult.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreDoc> cancel(int id) async {
    try {
      final r = await CoreClient.dio.post(CoreClient.url('/docs/$id/cancel'),
          options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      final docJson = m['doc'] is Map ? Map<String, dynamic>.from(m['doc'] as Map) : m;
      return CoreDoc.fromJson(docJson);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// Yaratish + post bitta so'rovda.
  Future<CoreDocPostResult> quick(CoreDoc doc) async {
    try {
      final r = await CoreClient.dio.post(CoreClient.url('/docs/quick'),
          data: doc.toJson(), options: CoreClient.idem());
      return CoreDocPostResult.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
