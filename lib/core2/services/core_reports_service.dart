// core2/services/core_reports_service.dart — mone_core hisobotlari
// (perm `report.view`): YANGI 5 ta (`/reports/inventory-diff`, `/issues`,
// `/purchases`, `/production`, `/recipe-cost`) + mavjud `/reports/cost`.
// Hammasida `?format=csv` — server UTF-8 BOM li, `;` ajratgichli Excel CSV
// qaytaradi; u BAYT sifatida olinadi (`csv()`), chunki `Authorization`
// sarlavhasi kerak (brauzer havolasi ishlamaydi).
//
// Eski hisobotlar (turnover/stock-value/deficit/sh5-compare) —
// `core_stock_service.dart` da; CSV ularga ham shu servis orqali olinadi.
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/core2/models/core_report2.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

/// Serverdan olingan CSV: bayt tanasi + `Content-Disposition` dagi nom.
class CoreCsvData {
  final List<int> bytes;
  final String serverName;
  const CoreCsvData({required this.bytes, this.serverName = ''});
}

/// Hisobot yo'llari (CSV ham shu kalitlar bilan so'raladi).
abstract final class CoreReportPaths {
  static const String inventoryDiff = '/reports/inventory-diff';
  static const String issues = '/reports/issues';
  static const String purchases = '/reports/purchases';
  static const String production = '/reports/production';
  static const String recipeCost = '/reports/recipe-cost';
  static const String cost = '/reports/cost';
  static const String turnover = '/reports/turnover';
  static const String stockValue = '/reports/stock-value';
  static const String deficit = '/reports/deficit';
}

class CoreReportsService {
  /// 5a — kamomad / ortiqcha (Сличительная ведомость).
  Future<CoreInvDiffReport> inventoryDiff({
    required String dateFrom,
    required String dateTo,
    int? skladId,
    int? groupId,
  }) async {
    final j = await _get(CoreReportPaths.inventoryDiff, {
      'date_from': dateFrom,
      'date_to': dateTo,
      if (skladId != null) 'sklad_id': skladId,
      if (groupId != null) 'group_id': groupId,
    });
    return CoreInvDiffReport.fromJson(j);
  }

  /// 5b — hisobdan chiqarish sabab (kontragent) kesimida.
  Future<CoreIssuesReport> issues({
    required String dateFrom,
    required String dateTo,
    int? skladId,
    int? corrId,
  }) async {
    final j = await _get(CoreReportPaths.issues, {
      'date_from': dateFrom,
      'date_to': dateTo,
      if (skladId != null) 'sklad_id': skladId,
      if (corrId != null) 'corr_id': corrId,
    });
    return CoreIssuesReport.fromJson(j);
  }

  /// 5c — xaridlar va narx tarixi.
  Future<CorePurchasesReport> purchases({
    required String dateFrom,
    required String dateTo,
    int? corrId,
    int? goodId,
    int? skladId,
  }) async {
    final j = await _get(CoreReportPaths.purchases, {
      'date_from': dateFrom,
      'date_to': dateTo,
      if (corrId != null) 'corr_id': corrId,
      if (goodId != null) 'good_id': goodId,
      if (skladId != null) 'sklad_id': skladId,
    });
    return CorePurchasesReport.fromJson(j);
  }

  /// 5d — ishlab chiqarish (akt + переработка mahsuloti).
  Future<CoreProductionReport> production({
    required String dateFrom,
    required String dateTo,
    int? skladId,
    bool includeSales = false,
  }) async {
    final j = await _get(CoreReportPaths.production, {
      'date_from': dateFrom,
      'date_to': dateTo,
      if (skladId != null) 'sklad_id': skladId,
      if (includeSales) 'include_sales': 1,
    });
    return CoreProductionReport.fromJson(j);
  }

  /// 5e — kalkulyatsiya kartasi (retsept `expand_sub` bo'yicha yoyiladi).
  Future<CoreRecipeCost> recipeCost({
    required int goodId,
    String? date,
    int? qty,
  }) async {
    final j = await _get(CoreReportPaths.recipeCost, {
      'good_id': goodId,
      if (date != null && date.isNotEmpty) 'date': date,
      if (qty != null) 'qty': qty,
    });
    return CoreRecipeCost.fromJson(j);
  }

  /// Tannarx / food cost (`act` flag=0 qatorlari).
  Future<CoreCostReport> cost({
    required String dateFrom,
    required String dateTo,
    int? skladId,
    int? goodId,
  }) async {
    final j = await _get(CoreReportPaths.cost, {
      'date_from': dateFrom,
      'date_to': dateTo,
      if (skladId != null) 'sklad_id': skladId,
      if (goodId != null) 'good_id': goodId,
    });
    return CoreCostReport.fromJson(j);
  }

  /// Istalgan hisobotning `?format=csv` javobi — BAYT sifatida.
  Future<CoreCsvData> csv(String path, Map<String, dynamic> query) async {
    try {
      final r = await CoreClient.dio.get<List<int>>(
        CoreClient.url(path),
        queryParameters: {...query, 'format': 'csv'},
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'text/csv'},
        ),
      );
      return CoreCsvData(
        bytes: r.data ?? const [],
        serverName: coreCsvNameFromDisposition(
            r.headers.value('content-disposition')),
      );
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<Map<String, dynamic>> _get(
      String path, Map<String, dynamic> query) async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url(path),
          queryParameters: query);
      return CoreClient.mapOf(r.data);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}

/// `attachment; filename="kamomad_2026-08-01.csv"` → `kamomad_2026-08-01.csv`.
/// Topilmasa bo'sh satr (UI o'z nomini qo'yadi).
String coreCsvNameFromDisposition(String? header) {
  if (header == null || header.isEmpty) return '';
  final m = RegExp(r'''filename\*?=(?:UTF-8'')?"?([^";]+)"?''',
          caseSensitive: false)
      .firstMatch(header);
  final name = m?.group(1)?.trim() ?? '';
  return name.endsWith('.csv') ? name : '';
}
