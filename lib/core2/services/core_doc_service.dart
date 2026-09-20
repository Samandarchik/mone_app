// core2/services/core_doc_service.dart — mone_core hujjatlari:
// list (GET /docs filtrlar bilan, qatorlarsiz), get (GET /docs/{id} to'liq),
// create (POST /docs — draft), update (PUT /docs/{id}), delete, post
// (POST /docs/{id}/post → doc + warnings), cancel, quick (POST /docs/quick —
// yaratish + post bitta so'rovda; bozorchi приход, inventar).
//
// CORE_DEBT_KONTRAKT: rework (POST /docs/{id}/rework — bekor + qoralama
// nusxa bitta tranzaksiyada), copy (POST /docs/{id}/copy — bekor qilmasdan),
// quickBatch (POST /docs/quick-batch — tarqatish matritsasi), ro'yxatda
// `created_by` filtri.
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
    int? createdBy,
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
          if (createdBy != null) 'created_by': createdBy,
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

  /// «Tuzatish» — `POST /docs/{id}/rework` (CORE_DEBT_KONTRAKT §1):
  /// o'tkazilgan hujjat BEKOR qilinadi va to'liq nusxasi QORALAMA bo'lib
  /// yaratiladi — ikkalasi bitta tranzaksiyada. Javob: yangi draft
  /// (`reworked_from`, `from_number` bilan).
  ///
  /// [dropInputs] — faqat `act`: flag=1 (ingredient) qatorlari ko'chirilmaydi,
  /// qayta post retsept bo'yicha o'zi yoyadi.
  Future<CoreDoc> rework(int id, {bool dropInputs = false}) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/docs/$id/rework'),
        data: dropInputs ? {'drop_inputs': true} : const <String, dynamic>{},
        options: CoreClient.idem(),
      );
      return CoreDoc.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// «Nusxa olish» — `POST /docs/{id}/copy` (§2): asl hujjat TEGILMAYDI,
  /// qoralama nusxa yaratiladi. Sana default BUGUN (orqa sana `doc.backdate`
  /// talab qiladi). Har qanday holat va manbadagi hujjatdan (sh5/rk7 ham).
  Future<CoreDoc> copy(int id, {String? docDate, bool dropInputs = false}) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/docs/$id/copy'),
        data: {
          if (docDate != null && docDate.isNotEmpty) 'doc_date': docDate,
          if (dropInputs) 'drop_inputs': true,
        },
        options: CoreClient.idem(),
      );
      return CoreDoc.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// Tarqatish matritsasi — `POST /docs/quick-batch` (§3): 1..20 ta hujjat
  /// BITTA tranzaksiyada yaratiladi va o'tkaziladi (birortasi xato bersa
  /// hech biri yaratilmaydi). [docs] — `/docs/quick` tanasi bilan AYNAN bir
  /// xil obyektlar (`distribute_logic.dart` quradi).
  Future<CoreDocBatchResult> quickBatch(List<Map<String, dynamic>> docs) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/docs/quick-batch'),
        data: {'docs': docs},
        options: CoreClient.idem(),
      );
      return CoreDocBatchResult.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
