// core2/provider/core_dict_provider.dart — mone_core lug'atlari keshi
// (CoreDictProvider): omborlar, kontragentlar, tovarlar, birliklar, guruhlar.
// Bir marta yuklanadi (`ensureLoaded`), keyin xotirada; `skladById` /
// `corrById` / `goodById` — O(1) indeks Map'lar (kartochka build'ida
// chiziqli qidiruv YO'Q). Tovar qidiruvi — lokal (`searchGoods`), ro'yxat
// katta bo'lsa serverga `search=` bilan ham murojaat qilinadi.
import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_dict_service.dart';

class CoreDictProvider extends ChangeNotifier with ClearableProvider {
  final CoreDictService _service = CoreDictService();

  List<CoreSklad> _sklads = [];
  List<CoreCorr> _corrs = [];
  List<CoreGood> _goods = [];
  List<CoreUnit> _units = [];
  List<CoreGoodGroup> _groups = [];

  Map<int, CoreSklad> _skladIdx = {};
  Map<int, CoreCorr> _corrIdx = {};
  Map<int, CoreGood> _goodIdx = {};
  Map<int, CoreGoodGroup> _groupIdx = {};

  bool _loaded = false;
  bool _loading = false;
  String? _error;
  Future<void>? _inflight;

  List<CoreSklad> get sklads => _sklads;
  List<CoreSklad> get activeSklads =>
      _sklads.where((s) => s.active).toList(growable: false);
  List<CoreCorr> get corrs => _corrs;
  List<CoreGood> get goods => _goods;
  List<CoreUnit> get units => _units;
  List<CoreGoodGroup> get groups => _groups;
  bool get loaded => _loaded;
  bool get loading => _loading;
  String? get error => _error;

  CoreSklad? skladById(int? id) => id == null ? null : _skladIdx[id];
  CoreCorr? corrById(int? id) => id == null ? null : _corrIdx[id];
  CoreGood? goodById(int? id) => id == null ? null : _goodIdx[id];
  CoreGoodGroup? groupById(int? id) => id == null ? null : _groupIdx[id];

  String skladName(int? id) =>
      id == null ? '—' : (_skladIdx[id]?.name ?? 'Ombor #$id');
  String corrName(int? id) =>
      id == null ? '—' : (_corrIdx[id]?.name ?? 'Kontragent #$id');
  String goodName(int id) => _goodIdx[id]?.name ?? 'Tovar #$id';

  List<CoreCorr> corrsOfKind(Iterable<String> kinds) {
    final set = kinds.toSet();
    return _corrs.where((c) => c.active && set.contains(c.kind)).toList();
  }

  /// Nomi shu matnni o'z ichiga olgan kontragent (bozorchi uchun «РЫНОК»).
  CoreCorr? findCorrByName(String needle) {
    final n = needle.toLowerCase();
    for (final c in _corrs) {
      if (c.name.toLowerCase().contains(n)) return c;
    }
    return null;
  }

  /// Lokal qidiruv (kesh ustida), max [limit] natija.
  List<CoreGood> searchGoods(String q, {int limit = 50, bool onlyActive = true}) {
    final s = q.trim().toLowerCase();
    final out = <CoreGood>[];
    for (final g in _goods) {
      if (onlyActive && !g.active) continue;
      if (s.isEmpty || g.name.toLowerCase().contains(s) || g.rkCode == s) {
        out.add(g);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Bir marta yuklash; parallel chaqiruvlar bitta so'rovni kutadi.
  Future<void> ensureLoaded({bool force = false}) {
    if (_loaded && !force) return Future.value();
    return _inflight ??= _load().whenComplete(() => _inflight = null);
  }

  Future<void> _load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.sklads(),
        _service.corrs(),
        _service.goods(limit: 5000),
        _service.units().catchError((_) => <CoreUnit>[]),
        _service.goodGroups().catchError((_) => <CoreGoodGroup>[]),
      ]);
      _sklads = results[0] as List<CoreSklad>;
      _corrs = results[1] as List<CoreCorr>;
      _goods = results[2] as List<CoreGood>;
      _units = results[3] as List<CoreUnit>;
      _groups = results[4] as List<CoreGoodGroup>;
      _reindex();
      _loaded = true;
    } catch (e) {
      _error = CoreClient.wrap(e).message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _reindex() {
    _skladIdx = {for (final s in _sklads) s.id: s};
    _corrIdx = {for (final c in _corrs) c.id: c};
    _goodIdx = {for (final g in _goods) g.id: g};
    _groupIdx = {for (final g in _groups) g.id: g};
  }

  Future<CoreSklad> saveSklad(CoreSklad s) async {
    final saved = await _service.saveSklad(s);
    final i = _sklads.indexWhere((e) => e.id == saved.id);
    if (i >= 0) {
      _sklads[i] = saved;
    } else {
      _sklads.add(saved);
    }
    _reindex();
    notifyListeners();
    return saved;
  }

  Future<CoreCorr> saveCorr(CoreCorr c) async {
    final saved = await _service.saveCorr(c);
    final i = _corrs.indexWhere((e) => e.id == saved.id);
    if (i >= 0) {
      _corrs[i] = saved;
    } else {
      _corrs.add(saved);
    }
    _reindex();
    notifyListeners();
    return saved;
  }

  Future<CoreGood> saveGood(CoreGood g) async {
    final saved = await _service.saveGood(g);
    final i = _goods.indexWhere((e) => e.id == saved.id);
    if (i >= 0) {
      _goods[i] = saved;
    } else {
      _goods.add(saved);
    }
    _reindex();
    notifyListeners();
    return saved;
  }

  @override
  void clear() {
    _sklads = [];
    _corrs = [];
    _goods = [];
    _units = [];
    _groups = [];
    _reindex();
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
