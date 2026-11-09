// admin/services/pos_menu_service.dart — Konak POS menyu katalogi servisi
// (faqat admin): PosMenuService.fetchPosMenu/savePosMenu →
// GET/PUT /api/pos-menu (tartibli product_ids ro'yxati).
import 'package:dio/dio.dart';
import 'package:uz_ai_dev/admin/model/pos_menu_model.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';

// POS (Konak) menyu servisi (faqat admin, token global Dio interceptor
// orqali qo'shiladi). Javob envelope: {success, message, data}.
class PosMenuService {
  PosMenuService({this.kassa = false});

  // kassa=true → Mone kassasi menyusi (/api/kassa-menu), aks holda Konak POS menyusi.
  final bool kassa;
  final Dio dio = sl<Dio>();
  String get _url => kassa ? AppUrls.kassaMenu : AppUrls.posMenu;

  // POS ko'radigan katalog: kategoriyalar + mahsulotlar. filialId
  // berilmasa server birinchi filialni oladi.
  Future<PosMenuResult> fetchPosMenu({int? filialId}) async {
    try {
      final response = await dio.get(
        _url,
        queryParameters: {
          if (filialId != null) 'filial_id': filialId,
        },
      );
      return _parseResult(response);
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Server xatosi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  // Kuratsiyani saqlash: PUT to'liq TARTIBLI id ro'yxati bilan (tartib =
  // POS'dagi tartib). Bo'sh ro'yxat → config o'chiriladi (configured=false).
  // Javob — yangilangan to'liq holat (GET bilan bir xil shakl).
  Future<PosMenuResult> savePosMenu(int? filialId, List<int> productIds) async {
    try {
      final response = await dio.put(
        _url,
        queryParameters: {
          if (filialId != null) 'filial_id': filialId,
        },
        data: {'product_ids': productIds},
      );
      return _parseResult(response);
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Server xatosi: ${parseDioError(e)}');
      }
      throw Exception('Tarmoq xatosi: ${e.message}');
    }
  }

  PosMenuResult _parseResult(Response response) {
    final data = response.data is Map ? response.data['data'] : null;
    if (data is Map) {
      return PosMenuResult.fromJson(Map<String, dynamic>.from(data));
    }
    return const PosMenuResult();
  }
}
