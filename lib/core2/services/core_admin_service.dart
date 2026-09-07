// core2/services/core_admin_service.dart — mone_core admin: ruxsat
// katalogi (GET /perms), rol ruxsatlari (GET/PUT /roles/{role}/perms —
// {"perms":{"doc.receipt.post":true,…}}), foydalanuvchilar (GET/POST/PUT
// /users), sinxron holati (GET /sync/status). Perm: users.manage.
import 'package:uz_ai_dev/core2/models/core_integration.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreAdminService {
  Future<List<CorePermDef>> perms() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/perms'));
      return CoreClient.listOf(r.data).map(CorePermDef.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<Map<String, bool>> rolePerms(String role) async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/roles/$role/perms'));
      final m = CoreClient.mapOf(r.data);
      final raw = m['perms'] is Map ? m['perms'] as Map : m;
      final out = <String, bool>{};
      raw.forEach((k, v) {
        if (v is bool) out[k.toString()] = v;
      });
      return out;
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<void> saveRolePerms(String role, Map<String, bool> perms) async {
    try {
      await CoreClient.dio.put(
        CoreClient.url('/roles/$role/perms'),
        data: {'perms': perms},
      );
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreUser>> users() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/users'));
      return CoreClient.listOf(r.data).map(CoreUser.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreUser> saveUser(CoreUser u, {String? password}) async {
    try {
      final body = u.toJson(password: password);
      final r = u.id > 0
          ? await CoreClient.dio.put(CoreClient.url('/users/${u.id}'), data: body)
          : await CoreClient.dio.post(CoreClient.url('/users'),
              data: body, options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? u : CoreUser.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `GET /sync/status` (shartnomada hali yo'q — kutilgan shakl modelda).
  Future<CoreSyncStatus> syncStatus() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/sync/status'));
      return CoreSyncStatus.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
