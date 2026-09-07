// core2/provider/core_stock_provider.dart — mone_core qoldiq keshi
// (CoreStockProvider): ombor bo'yicha qatorlar (`rowsFor(skladId)`),
// `rowFor(skladId, goodId)` — O(1) indeks (inventar formasida har qator
// build'ida chaqiriladi; indeks notifyListeners'da bekor qilinadi).
import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';

class CoreStockProvider extends ChangeNotifier with ClearableProvider {
  final CoreStockService _service = CoreStockService();

  final Map<int, List<CoreStockRow>> _bySklad = {};
  final Set<int> _loading = {};
  final Map<int, String> _errors = {};
  Map<int, Map<int, CoreStockRow>>? _idx;

  List<CoreStockRow>? rowsFor(int skladId) => _bySklad[skladId];
  bool isLoading(int skladId) => _loading.contains(skladId);
  String? errorFor(int skladId) => _errors[skladId];

  /// Bitta tovar qoldig'i — O(1) (indeks kesh).
  CoreStockRow? rowFor(int skladId, int goodId) {
    _idx ??= {
      for (final e in _bySklad.entries)
        e.key: {for (final r in e.value) r.goodId: r}
    };
    return _idx![skladId]?[goodId];
  }

  int qtyFor(int skladId, int goodId) => rowFor(skladId, goodId)?.qty ?? 0;

  @override
  void notifyListeners() {
    _idx = null;
    super.notifyListeners();
  }

  /// Qoldiq qatorlaridan tovar nomi/base birligi — CoreDictProvider keshiga
  /// (`onRows` orqali; tovarlar to'liq yuklanmaydi).
  void Function(List<CoreStockRow>)? onRows;

  Future<void> load(int skladId, {String? date, bool nonzero = false}) async {
    _loading.add(skladId);
    _errors.remove(skladId);
    notifyListeners();
    try {
      final rows =
          await _service.stock(skladId: skladId, date: date, nonzero: nonzero);
      _bySklad[skladId] = rows;
      onRows?.call(rows);
    } catch (e) {
      _errors[skladId] = CoreClient.wrap(e).message;
    } finally {
      _loading.remove(skladId);
      notifyListeners();
    }
  }

  Future<void> ensure(int skladId) {
    if (_bySklad.containsKey(skladId) || _loading.contains(skladId)) {
      return Future.value();
    }
    return load(skladId);
  }

  /// Hujjat o'tkazilgach tegishli omborlar keshini yangilash.
  Future<void> refreshSklads(Iterable<int?> ids) async {
    for (final id in ids) {
      if (id != null && _bySklad.containsKey(id)) await load(id);
    }
  }

  @override
  void clear() {
    _bySklad.clear();
    _loading.clear();
    _errors.clear();
    notifyListeners();
  }
}
