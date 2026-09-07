// core2/services/core_dict_service.dart — mone_core lug'atlari:
// /sklads, /corrs, /units, /good-groups, /goods (GET hamma; POST/PUT perm
// `dict.edit`). Ro'yxat javobi `[…]` yoki `{"items":[…],"total"}`.
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreDictService {
  Future<List<CoreSklad>> sklads() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/sklads'));
      return CoreClient.listOf(r.data).map(CoreSklad.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreSklad> saveSklad(CoreSklad s) async {
    try {
      final r = s.id > 0
          ? await CoreClient.dio
              .put(CoreClient.url('/sklads/${s.id}'), data: s.toJson())
          : await CoreClient.dio.post(CoreClient.url('/sklads'),
              data: s.toJson(), options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? s : CoreSklad.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreCorr>> corrs() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/corrs'));
      return CoreClient.listOf(r.data).map(CoreCorr.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreCorr> saveCorr(CoreCorr c) async {
    try {
      final r = c.id > 0
          ? await CoreClient.dio
              .put(CoreClient.url('/corrs/${c.id}'), data: c.toJson())
          : await CoreClient.dio.post(CoreClient.url('/corrs'),
              data: c.toJson(), options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? c : CoreCorr.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreUnit>> units() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/units'));
      return CoreClient.listOf(r.data).map(CoreUnit.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreGoodGroup>> goodGroups() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/good-groups'));
      return CoreClient.listOf(r.data).map(CoreGoodGroup.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `GET /goods?search=&group_id=&active=&limit=&offset=`.
  Future<List<CoreGood>> goods({
    String search = '',
    int? groupId,
    bool? active,
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/goods'),
        queryParameters: {
          if (search.isNotEmpty) 'search': search,
          if (groupId != null) 'group_id': groupId,
          if (active != null) 'active': active ? 1 : 0,
          'limit': limit,
          'offset': offset,
        },
      );
      return CoreClient.listOf(r.data).map(CoreGood.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreGood> good(int id) async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/goods/$id'));
      return CoreGood.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreGood> saveGood(CoreGood g) async {
    try {
      final r = g.id > 0
          ? await CoreClient.dio
              .put(CoreClient.url('/goods/${g.id}'), data: g.toJson())
          : await CoreClient.dio.post(CoreClient.url('/goods'),
              data: g.toJson(), options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? g : CoreGood.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
