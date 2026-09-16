// core2/services/core_stock_service.dart — mone_core qoldiq/partiya/kartochka:
// stock (GET /stock?sklad_id=&good_id=&date=&search=&nonzero=1), summary
// (GET /stock/summary?date=), batches (GET /batches), card (GET /stock/card
// → CoreStockCard obyekti). Hisobotlar (perm report.view, javob
// `{"items":[…],…}`): turnover, stockValue, deficit. /stock, /batches —
// ledger ulanmaguncha 501.
import 'package:uz_ai_dev/core2/models/core_report.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreStockService {
  Future<List<CoreStockRow>> stock({
    int? skladId,
    int? goodId,
    String? date,
    String search = '',
    bool nonzero = false,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/stock'),
        queryParameters: {
          if (skladId != null) 'sklad_id': skladId,
          if (goodId != null) 'good_id': goodId,
          if (date != null && date.isNotEmpty) 'date': date,
          if (search.isNotEmpty) 'search': search,
          if (nonzero) 'nonzero': 1,
        },
      );
      return CoreClient.listOf(r.data).map(CoreStockRow.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreStockSummary>> summary({String? date}) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/stock/summary'),
        queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
      );
      return CoreClient.listOf(r.data).map(CoreStockSummary.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreBatch>> batches({required int skladId, required int goodId}) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/batches'),
        queryParameters: {'sklad_id': skladId, 'good_id': goodId},
      );
      return CoreClient.listOf(r.data).map(CoreBatch.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `{sklad_id, good_id, open_qty, open_cost, close_qty, rows[]}`.
  Future<CoreStockCard> card({
    required int skladId,
    required int goodId,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/stock/card'),
        queryParameters: {
          'sklad_id': skladId,
          'good_id': goodId,
          if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
        },
      );
      return CoreStockCard.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  // ── Hisobotlar ──

  Future<List<CoreTurnoverRow>> turnover({
    int? skladId,
    required String dateFrom,
    required String dateTo,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/reports/turnover'),
        queryParameters: {
          if (skladId != null) 'sklad_id': skladId,
          'date_from': dateFrom,
          'date_to': dateTo,
        },
      );
      return CoreClient.listOf(r.data).map(CoreTurnoverRow.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `GET /reports/stock-value?date=` — ombor × qiymat (summary shakli).
  Future<List<CoreStockSummary>> stockValue({String? date}) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/reports/stock-value'),
        queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
      );
      return CoreClient.listOf(r.data).map(CoreStockSummary.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// `GET /reports/sh5-compare?date=` — SH5 ↔ yadro kunlik solishtiruv
  /// natijasi (sh5compare demoni yozadi). Hali hisoblanmagan kun uchun
  /// server 404 qaytaradi — UI shuni alohida ko'rsatadi.
  Future<CoreSh5Compare> sh5Compare({String? date}) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/reports/sh5-compare'),
        queryParameters: {if (date != null && date.isNotEmpty) 'date': date},
      );
      return CoreSh5Compare.fromJson(CoreClient.mapOf(r.data));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreDeficitRow>> deficit({
    required String dateFrom,
    required String dateTo,
    int? skladId,
  }) async {
    try {
      final r = await CoreClient.dio.get(
        CoreClient.url('/reports/deficit'),
        queryParameters: {
          'date_from': dateFrom,
          'date_to': dateTo,
          if (skladId != null) 'sklad_id': skladId,
        },
      );
      return CoreClient.listOf(r.data).map(CoreDeficitRow.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
