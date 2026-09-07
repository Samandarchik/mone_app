// core2/provider/core_session_provider.dart — mone_core sessiyasi
// (CoreSession): `core_token` + foydalanuvchi + hisoblangan `perms` to'plami.
// Login ekranida v1 login muvaffaqiyatli bo'lgach o'sha kod bilan FONDA
// `loginWithCode` chaqiriladi; xato bo'lsa ilova to'xtamaydi — «Ombor 2.0»
// bo'limi «server ulanmagan» ko'rsatadi va «Qayta urinish» beradi.
// Ruxsat tekshiruvi: `has('doc.receipt.post')`, `canCreate(type)`,
// `canPost(type)`. superadmin (v1 roli) — hammasi ruxsat.
// Saqlanadi: core_token, core_user (JSON), core_perms (JSON ro'yxat),
// core_login_code (qayta ulanish uchun).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/constants/roles.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/services/core_auth_service.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

enum CoreConnState { idle, connecting, connected, error }

class CoreSession extends ChangeNotifier with ClearableProvider {
  static const String _kUser = 'core_user';
  static const String _kPerms = 'core_perms';
  static const String _kCode = 'core_login_code';

  final CoreAuthService _auth = CoreAuthService();

  CoreConnState _state = CoreConnState.idle;
  String? _error;
  CoreUser? _user;
  Set<String> _perms = {};
  String _token = '';
  String _loginCode = '';
  // v1 roli (superadmin bo'lsa hamma ruxsat).
  String _v1Role = '';

  CoreConnState get state => _state;
  String? get error => _error;
  CoreUser? get user => _user;
  Set<String> get perms => _perms;
  bool get connected => _state == CoreConnState.connected && _token.isNotEmpty;
  bool get hasToken => _token.isNotEmpty;
  bool get isSuper =>
      _v1Role == AppRoles.superAdmin || _user?.role == AppRoles.superAdmin;

  /// Ruxsat bormi. superadmin — har doim true.
  bool has(String perm) => isSuper || _perms.contains(perm);
  bool canCreate(String docType) =>
      has(CorePerms.docCreate(_permType(docType)));
  bool canPost(String docType) => has(CorePerms.docPost(_permType(docType)));
  bool get canCancel => has(CorePerms.docCancel);
  bool get canBackdate => has(CorePerms.docBackdate);

  static String _permType(String t) => t == 'reserve' ? 'transfer' : t;

  /// Hujjat turlaridan kamida bittasini yarata oladimi (bosh ekran tugmasi).
  bool get canAnyDoc =>
      isSuper || _perms.any((p) => p.startsWith('doc.') && p.endsWith('.create'));

  /// Ilova ochilganda (splash) saqlangan sessiyani tiklash; token bo'lsa
  /// fonda /auth/me bilan yangilanadi.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(CoreClient.tokenKey) ?? '';
    _loginCode = prefs.getString(_kCode) ?? '';
    _v1Role = prefs.getString('role') ?? '';
    final rawUser = prefs.getString(_kUser);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _user = CoreUser.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawUser) as Map));
      } catch (_) {}
    }
    final rawPerms = prefs.getString(_kPerms);
    if (rawPerms != null && rawPerms.isNotEmpty) {
      try {
        _perms = (jsonDecode(rawPerms) as List).map((e) => e.toString()).toSet();
      } catch (_) {}
    }
    if (_token.isNotEmpty) {
      _state = CoreConnState.connected; // keshdan — /auth/me tasdiqlaydi
      notifyListeners();
      await refreshMe();
    } else {
      notifyListeners();
    }
  }

  /// v1 login kodi (parol) bilan yadroga kirish. Xato tashlamaydi.
  Future<bool> loginWithCode(String code) async {
    _loginCode = code;
    _state = CoreConnState.connecting;
    _error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCode, code);
    _v1Role = prefs.getString('role') ?? '';
    try {
      final res = await _auth.loginWithCode(code);
      _token = res.token;
      _user = res.user;
      // Hisoblangan ruxsatlar login javobida keladi; bo'sh kelsa /auth/me.
      _perms = res.perms;
      if (_perms.isEmpty) {
        try {
          final me = await _auth.me();
          _user = me.user;
          _perms = me.perms;
        } catch (e) {
          debugPrint('CoreSession.me: $e');
        }
      }
      await prefs.setString(CoreClient.tokenKey, _token);
      await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
      await prefs.setString(_kPerms, jsonEncode(_perms.toList()));
      _state = CoreConnState.connected;
      notifyListeners();
      return true;
    } catch (e) {
      _state = CoreConnState.error;
      _error = CoreClient.wrap(e).message;
      notifyListeners();
      return false;
    }
  }

  /// Saqlangan kod bilan qayta urinish («Qayta urinish» tugmasi).
  Future<bool> retry() async {
    if (_loginCode.isEmpty) {
      _state = CoreConnState.error;
      _error = 'Kirish kodi saqlanmagan — ilovaga qayta kiring';
      notifyListeners();
      return false;
    }
    return loginWithCode(_loginCode);
  }

  /// `/auth/me` — perms yangilash. 401 bo'lsa saqlangan kod bilan qayta login.
  Future<void> refreshMe() async {
    if (_token.isEmpty) return;
    try {
      final me = await _auth.me();
      _user = me.user;
      _perms = me.perms;
      _state = CoreConnState.connected;
      _error = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
      await prefs.setString(_kPerms, jsonEncode(_perms.toList()));
      notifyListeners();
    } catch (e) {
      final err = CoreClient.wrap(e);
      if (err.unauthorized && _loginCode.isNotEmpty) {
        await loginWithCode(_loginCode);
        return;
      }
      _state = CoreConnState.error;
      _error = err.message;
      notifyListeners();
    }
  }

  @override
  void clear() {
    _state = CoreConnState.idle;
    _error = null;
    _user = null;
    _perms = {};
    _token = '';
    _loginCode = '';
    _v1Role = '';
    notifyListeners();
    SharedPreferences.getInstance().then((p) async {
      for (final k in [CoreClient.tokenKey, _kUser, _kPerms, _kCode]) {
        await p.remove(k);
      }
    });
  }
}
