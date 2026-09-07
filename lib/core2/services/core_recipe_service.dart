// core2/services/core_recipe_service.dart — mone_core retseptlari:
// list (GET /recipes), get (GET /recipes/{id}), create (POST /recipes),
// addVersion (POST /recipes/{id}/versions — yangi versiya valid_from bilan),
// expand (GET /recipes/expand?good_id=&date=&qty=). Yozish — perm recipe.edit.
import 'package:uz_ai_dev/core2/models/core_recipe.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreRecipeService {
  Future<List<CoreRecipe>> list({String search = ''}) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/recipes'),
        queryParameters: {if (search.isNotEmpty) 'search': search},
      );
      return CoreClient.listOf(r.data).map(CoreRecipe.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreRecipe> get(int id) async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/recipes/$id'));
      return CoreRecipe.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// Yangi retsept (tovar uchun) — birinchi versiya bilan.
  Future<CoreRecipe> create({
    required int goodId,
    required String name,
    required CoreRecipeVersion version,
  }) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/recipes'),
        data: {
          'good_id': goodId,
          'name': name,
          'versions': [version.toJson()],
        },
        options: CoreClient.idem(),
      );
      return CoreRecipe.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreRecipeVersion> addVersion(int recipeId, CoreRecipeVersion v) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/recipes/$recipeId/versions'),
        data: v.toJson(),
        options: CoreClient.idem(),
      );
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? v : CoreRecipeVersion.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// Ingredientlarga yoyish: [{good_id, qty}].
  Future<List<Map<String, dynamic>>> expand({
    required int goodId,
    required String date,
    required int qty,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/recipes/expand'),
        queryParameters: {'good_id': goodId, 'date': date, 'qty': qty},
      );
      return CoreClient.listOf(r.data);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
