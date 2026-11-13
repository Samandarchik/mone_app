// admin/services/kassa_staff_service.dart — KASSA XODIMLARI servisi (admin):
// GET /api/kassa-staff?filial_id=, POST /api/kassa-staff (super admin, PIN qaytadi),
// PUT /api/kassa-staff/{id}, POST /api/kassa-staff/{id}/reset-pin, GET /api/hr/persons?q=.
// Backend: kassa_staff.go. PIN faqat yaratish/yangilash javobida bir marta keladi.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class KassaStaffMember {
  final int id;
  final int personId;
  final String name;
  final String phone;
  final String photoUrl;
  final String role;
  final String roleName;
  final int filialId;
  final String filialName;
  final bool active;
  final bool blocked;
  final String hrStatus;

  const KassaStaffMember({
    required this.id,
    required this.personId,
    required this.name,
    this.phone = '',
    this.photoUrl = '',
    this.role = '',
    this.roleName = '',
    this.filialId = 0,
    this.filialName = '',
    this.active = true,
    this.blocked = false,
    this.hrStatus = '',
  });

  bool get enabled => active && !blocked;

  factory KassaStaffMember.fromJson(Map<String, dynamic> j) => KassaStaffMember(
        id: _int(j['id']),
        personId: _int(j['person_id']),
        name: '${j['name'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        photoUrl: '${j['photo_url'] ?? ''}',
        role: '${j['role'] ?? ''}',
        roleName: '${j['role_name'] ?? ''}',
        filialId: _int(j['filial_id']),
        filialName: '${j['filial_name'] ?? ''}',
        active: j['active'] == true,
        blocked: j['blocked'] == true,
        hrStatus: '${j['hr_status'] ?? ''}',
      );
}

class HrPerson {
  final int personId;
  final String fio;
  final String phone;
  final String photoUrl;
  final String lavozim;
  final int staffId; // 0 — hali kassada emas

  const HrPerson(this.personId, this.fio, this.phone, this.photoUrl, this.lavozim, this.staffId);

  factory HrPerson.fromJson(Map<String, dynamic> j) => HrPerson(
        _int(j['person_id']),
        '${j['fio'] ?? ''}',
        '${j['telefon'] ?? ''}',
        '${j['rasm_url'] ?? ''}',
        '${j['lavozim'] ?? ''}',
        _int(j['staff_id']),
      );
}

class KassaStaffList {
  final List<KassaStaffMember> staff;
  final List<(String, String)> roles; // (id, nom)
  final bool hrEnabled;
  const KassaStaffList(this.staff, this.roles, this.hrEnabled);
}

class KassaStaffService {
  final Dio dio = sl<Dio>();

  Future<KassaStaffList> fetch(int filialId) async {
    final d = await _call(() => dio.get(AppUrls.kassaStaff, queryParameters: {'filial_id': filialId}));
    final m = d is Map ? d : const {};
    return KassaStaffList(
      [
        for (final s in (m['staff'] as List? ?? const []))
          if (s is Map) KassaStaffMember.fromJson(Map<String, dynamic>.from(s)),
      ],
      [
        for (final r in (m['roles'] as List? ?? const []))
          if (r is Map) ('${r['id']}', '${r['name']}'),
      ],
      m['hr_enabled'] == true,
    );
  }

  Future<List<HrPerson>> searchHr(String q) async {
    final d = await _call(() => dio.get(AppUrls.hrPersons, queryParameters: {'q': q}));
    final list = d is Map ? d['persons'] : null;
    return [
      for (final p in (list as List? ?? const []))
        if (p is Map) HrPerson.fromJson(Map<String, dynamic>.from(p)),
    ];
  }

  /// Qaytadi: (xodim, PIN) — PIN faqat shu javobda.
  Future<(KassaStaffMember, String)> create(int personId, String role, int filialId) async {
    final d = await _call(() => dio.post(AppUrls.kassaStaff,
        data: {'person_id': personId, 'role': role, 'filial_id': filialId}));
    return _withPin(d);
  }

  /// Filial almashsa yangi PIN keladi (aks holda bo'sh).
  Future<(KassaStaffMember, String)> update(int id, Map<String, dynamic> body) async =>
      _withPin(await _call(() => dio.put(AppUrls.kassaStaffOne(id), data: body)));

  Future<(KassaStaffMember, String)> resetPin(int id) async =>
      _withPin(await _call(() => dio.post(AppUrls.kassaStaffResetPin(id))));

  (KassaStaffMember, String) _withPin(dynamic d) {
    final m = d is Map ? d : const {};
    final s = m['staff'] is Map ? Map<String, dynamic>.from(m['staff'] as Map) : <String, dynamic>{};
    return (KassaStaffMember.fromJson(s), '${m['pin'] ?? ''}');
  }

  Future<dynamic> _call(Future<Response> Function() f) async {
    try {
      final r = await f();
      return r.data is Map ? r.data['data'] : null;
    } on DioException catch (e) {
      if (e.response != null) throw Exception(parseDioError(e));
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }
}
