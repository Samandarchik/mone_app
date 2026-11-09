// admin/services/department_service.dart — filial BO'LIMLARI (Bar, Oshxona,
// Vitrina…) servisi (faqat admin): GET/POST /api/filials/{id}/departments,
// PUT/DELETE /api/departments/{id}. Har javob — filialning yangilangan ro'yxati.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

List<int> _ints(dynamic v) =>
    v is List ? [for (final x in v) _int(x)].where((x) => x > 0).toList() : <int>[];

class Department {
  final int id;
  final int filialId;
  final String name;
  final int skladId;
  final String skladName;
  final bool isDefault;
  final List<int> categoryIds;
  final List<int> productIds;

  const Department({
    required this.id,
    required this.filialId,
    required this.name,
    this.skladId = 0,
    this.skladName = '',
    this.isDefault = false,
    this.categoryIds = const [],
    this.productIds = const [],
  });

  factory Department.fromJson(Map<String, dynamic> j) => Department(
        id: _int(j['id']),
        filialId: _int(j['filial_id']),
        name: '${j['name'] ?? ''}',
        skladId: _int(j['sklad_id']),
        skladName: '${j['sklad_name'] ?? ''}',
        isDefault: j['is_default'] == true,
        categoryIds: _ints(j['category_ids']),
        productIds: _ints(j['product_ids']),
      );
}

/// Bo'lim sozlashda tanlanadigan element (kategoriya yoki mahsulot).
class DeptPickItem {
  final int id;
  final String name;
  final int categoryId;
  const DeptPickItem(this.id, this.name, {this.categoryId = 0});
}

class DepartmentService {
  final Dio dio = sl<Dio>();

  Future<List<Department>> fetch(int filialId) async =>
      _parse(await _call(() => dio.get(AppUrls.filialDepartments(filialId))));

  Future<List<Department>> create(int filialId, Map<String, dynamic> body) async =>
      _parse(await _call(() => dio.post(AppUrls.filialDepartments(filialId), data: body)));

  Future<List<Department>> update(int id, Map<String, dynamic> body) async =>
      _parse(await _call(() => dio.put(AppUrls.department(id), data: body)));

  Future<List<Department>> delete(int id) async =>
      _parse(await _call(() => dio.delete(AppUrls.department(id))));

  /// Kassada sotiladigan narsalar (kassa menyusi + qo'shish mumkinlari):
  /// (kategoriyalar, mahsulotlar) — bo'limga biriktirish uchun.
  Future<(List<DeptPickItem>, List<DeptPickItem>)> fetchSellables(int filialId) async {
    final data = await _call(() => dio.get(AppUrls.kassaMenu, queryParameters: {'filial_id': filialId}));
    final cats = <int, DeptPickItem>{};
    final prods = <DeptPickItem>[];
    if (data is Map) {
      for (final key in ['products', 'available_products']) {
        for (final p in (data[key] as List? ?? const [])) {
          if (p is! Map) continue;
          final cid = _int(p['category_id']);
          prods.add(DeptPickItem(_int(p['id']), '${p['name'] ?? ''}', categoryId: cid));
          if (cid > 0) {
            cats.putIfAbsent(cid, () => DeptPickItem(cid, '${p['category_name'] ?? 'Kategoriya $cid'}'));
          }
        }
      }
    }
    final catList = cats.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    prods.sort((a, b) => a.name.compareTo(b.name));
    return (catList, prods);
  }

  List<Department> _parse(dynamic data) {
    final list = data is Map ? data['departments'] : null;
    if (list is! List) return const [];
    return [
      for (final d in list)
        if (d is Map) Department.fromJson(Map<String, dynamic>.from(d)),
    ];
  }

  Future<dynamic> _call(Future<Response> Function() f) async {
    try {
      final r = await f();
      return r.data is Map ? r.data['data'] : null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(parseDioError(e));
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }
}
