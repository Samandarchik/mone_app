// core2/provider/core_dict_provider.dart — mone_core lug'atlari keshi
// (CoreDictProvider): omborlar, kontragentlar, birliklar, guruhlar — bir
// marta to'liq yuklanadi (`ensureLoaded`). TOVARLAR (12 000+) to'liq
// yuklanmaydi: qidiruv SERVER tomonda (`searchGoods` → `/goods?search=&limit=50`),
// natijalar va tanlangan/ko'rilgan tovarlar `_goodIdx` keshiga tushadi;
// `goodById` — O(1) kesh, `ensureGoods(ids)` — yetishmaganlarni to'ldiradi
// (50+ tovar kerak bo'lsa `loadActiveGoods()` — faol tovarlar ro'yxati
// sahifalab, aks holda `/goods/{id}` bittalab). `skladById`/`corrById` —
// O(1) indeks Map'lar.
import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_dict_service.dart';

class CoreDictProvider extends ChangeNotifier with ClearableProvider {
  final CoreDictService _service = CoreDictService();

  List<CoreSklad> _sklads = [];
  List<CoreCorr> _corrs = [];
  List<CoreUnit> _units = [];
  List<CoreGoodGroup> _groups = [];

  Map<int, CoreSklad> _skladIdx = {};
  Map<int, CoreCorr> _corrIdx = {};
  final Map<int, CoreGood> _goodIdx = {};
  Map<int, CoreGoodGroup> _groupIdx = {};
  // Serverda topilmagan id'lar — qayta-qayta so'ramaslik uchun.
  final Set<int> _missingGoods = {};

  bool _loaded = false;
  bool _loading = false;
  String? _error;
  Future<void>? _inflight;

  // Faol tovarlar to'liq ro'yxati (guruh/`is_complect` KO'P tovar uchun
  // kerak bo'lganda — sanash/qoldiq ekranlari) bir marta sahifalab olinadi.
  bool _allActiveLoaded = false;
  Future<void>? _allActiveInflight;

  /// Fonda tovar kartalari yuklanyaptimi (bo'lim sarlavhasidagi spinner).
  int _ensuring = 0;
  bool get goodsLoading => _ensuring > 0;

  List<CoreSklad> get sklads => _sklads;
  List<CoreSklad> get activeSklads =>
      _sklads.where((s) => s.active).toList(growable: false);
  List<CoreCorr> get corrs => _corrs;
  List<CoreUnit> get units => _units;
  List<CoreGoodGroup> get groups => _groups;
  /// Keshdagi tovarlar (faqat ko'rilgan/tanlanganlar — to'liq ro'yxat EMAS).
  Iterable<CoreGood> get cachedGoods => _goodIdx.values;
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

  /// Server qidiruvi (`?search=&limit=`); natijalar keshlanadi.
  /// Xato tashlaydi (UI ko'rsatadi).
  Future<List<CoreGood>> searchGoods(String q,
      {int limit = 50, bool onlyActive = true}) async {
    final list = await _service.goods(
        search: q.trim(), active: onlyActive ? true : null, limit: limit);
    cacheGoods(list);
    return list;
  }

  /// Tovarlarni keshga qo'yish (hujjat/qoldiq javoblaridan ham). TO'LIQ EMAS
  /// (`partial`) kartochka to'liqning ustiga YOZILMAYDI — aks holda
  /// `is_complect`/`units` yo'qolardi (inventar flag'i buzilardi).
  void cacheGoods(Iterable<CoreGood> goods, {bool notify = false}) {
    for (final g in goods) {
      final old = _goodIdx[g.id];
      if (g.partial && old != null && !old.partial) continue;
      _goodIdx[g.id] = g;
      if (!g.partial) _missingGoods.remove(g.id);
    }
    if (notify) notifyListeners();
  }

  /// Keshda yo'q — yoki faqat `partial` (qoldiq/hujjat qatoridan qurilgan)
  /// bo'lgan tovar id'lari.
  Set<int> _needGoods(Iterable<int> ids) => ids
      .where((id) =>
          id > 0 &&
          (_goodIdx[id]?.partial ?? true) &&
          !_missingGoods.contains(id))
      .toSet();

  /// Keshda yo'q — yoki faqat `partial` (qoldiq/hujjat qatoridan qurilgan) —
  /// tovarlarni to'ldiradi. KO'P tovar kerak bo'lsa (sanash: 250+ qator)
  /// bittalab `/goods/{id}` juda sekin — faol tovarlar ro'yxati sahifalab
  /// (1000 tadan, 4 ta parallel) olinadi, qolgani bittalab.
  /// Har bo'lakdan keyin `notifyListeners()` — ekran bosqichma-bosqich
  /// qayta guruhlanadi. Xatolar yutiladi (nom/birlik qator ma'lumotidan).
  Future<void> ensureGoods(Iterable<int> ids) async {
    var need = _needGoods(ids);
    if (need.isEmpty) return;
    _ensuring++;
    notifyListeners();
    try {
      if (need.length >= 50 && !_allActiveLoaded) {
        await loadActiveGoods();
        need = _needGoods(ids);
      }
      // Qolganlari (faol bo'lmagan yoki o'chirilgan tovarlar) bittalab.
      const chunk = 24;
      final list = need.toList();
      for (var i = 0; i < list.length; i += chunk) {
        final part = list.sublist(i, (i + chunk).clamp(0, list.length));
        await Future.wait(part.map((id) async {
          try {
            _goodIdx[id] = await _service.good(id);
          } catch (e) {
            _missingGoods.add(id);
            debugPrint('ensureGoods($id): $e');
          }
        }));
        notifyListeners();
      }
    } finally {
      _ensuring--;
      notifyListeners();
    }
  }

  /// Faol tovarlar to'liq ro'yxati (guruh nomi va `is_complect` bilan) —
  /// bir marta, sahifalab. Parallel chaqiruvlar bitta yuklashni kutadi.
  Future<void> loadActiveGoods() {
    if (_allActiveLoaded) return Future.value();
    return _allActiveInflight ??=
        _loadActiveGoods().whenComplete(() => _allActiveInflight = null);
  }

  Future<void> _loadActiveGoods() async {
    const page = 1000; // serverdagi eng katta limit
    const par = 4; // brauzerda bir vaqtda ochiladigan ulanishlar chegarasi
    _ensuring++;
    var offset = 0;
    try {
      while (offset < 60000) {
        final parts = await Future.wait([
          for (var i = 0; i < par; i++)
            _service
                .goods(active: true, limit: page, offset: offset + i * page)
                .catchError((Object e) {
              debugPrint('loadActiveGoods(offset ${offset + i * page}): $e');
              return <CoreGood>[];
            }),
        ]);
        var got = 0;
        for (final p in parts) {
          cacheGoods(p);
          got += p.length;
        }
        notifyListeners();
        if (got < page * par) break;
        offset += page * par;
      }
      _allActiveLoaded = true;
    } finally {
      _ensuring--;
      notifyListeners();
    }
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
        _service.units().catchError((_) => <CoreUnit>[]),
        _service.goodGroups().catchError((_) => <CoreGoodGroup>[]),
      ]);
      _sklads = results[0] as List<CoreSklad>;
      _corrs = results[1] as List<CoreCorr>;
      _units = results[2] as List<CoreUnit>;
      _groups = results[3] as List<CoreGoodGroup>;
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
    _goodIdx[saved.id] = saved;
    notifyListeners();
    return saved;
  }

  @override
  void clear() {
    _sklads = [];
    _corrs = [];
    _units = [];
    _groups = [];
    _goodIdx.clear();
    _missingGoods.clear();
    _reindex();
    _allActiveLoaded = false;
    _loaded = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }
}
