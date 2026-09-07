// core2/services/core_auth_service.dart — mone_core auth: loginWithCode
// (POST /auth/login {"code"}), me (GET /auth/me → CoreMe: user + perms
// ro'yxati). Token saqlash CoreSession (provider) ishi.
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreLoginResult {
  final String token;
  final CoreUser user;
  const CoreLoginResult({required this.token, required this.user});
}

class CoreAuthService {
  /// `POST /auth/login {"code": …}` → token + user.
  Future<CoreLoginResult> loginWithCode(String code) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/auth/login'),
        data: {'code': code},
      );
      final m = CoreClient.mapOf(r.data);
      final token = (m['token'] ?? '').toString();
      if (token.isEmpty) {
        throw const CoreApiException('Javobda token yo\'q');
      }
      final userJson = m['user'] is Map
          ? Map<String, dynamic>.from(m['user'] as Map)
          : <String, dynamic>{};
      return CoreLoginResult(token: token, user: CoreUser.fromJson(userJson));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `POST /auth/login {"phone","password"}`.
  Future<CoreLoginResult> loginWithPhone(String phone, String password) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/auth/login'),
        data: {'phone': phone, 'password': password},
      );
      final m = CoreClient.mapOf(r.data);
      final token = (m['token'] ?? '').toString();
      if (token.isEmpty) {
        throw const CoreApiException('Javobda token yo\'q');
      }
      final userJson = m['user'] is Map
          ? Map<String, dynamic>.from(m['user'] as Map)
          : <String, dynamic>{};
      return CoreLoginResult(token: token, user: CoreUser.fromJson(userJson));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `GET /auth/me` → user + hisoblangan perms.
  Future<CoreMe> me() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/auth/me'));
      return CoreMe.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
