// core2/provider/core_docs_provider.dart — mone_core hujjatlar ro'yxati
// holati (CoreDocsProvider): filtrlar (tur, holat, sana oralig'i, ombor,
// qidiruv), sahifalash (limit/offset, `loadMore`), yuklash/xato. Hujjat
// yaratish/post/cancel/delete ham shu yerdan — natija ro'yxatda darhol
// almashtiriladi (re-fetch YO'Q, `upsert`).
import 'package:flutter/foundation.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';

class CoreDocsProvider extends ChangeNotifier with ClearableProvider {
  final CoreDocService _service = CoreDocService();
  static const int pageSize = 50;

  List<CoreDoc> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  String? typeFilter;
  String? statusFilter;
  String? dateFrom;
  String? dateTo;
  int? skladFilter;
  // «Kim kiritgan» (`?created_by=`) va «Manba» (`?source=`) — §4.
  int? createdByFilter;
  String? sourceFilter;
  String search = '';

  List<CoreDoc> get items => _items;
  int get total => _total;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get hasMore => _items.length < _total;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.list(
        type: typeFilter,
        status: statusFilter,
        dateFrom: dateFrom,
        dateTo: dateTo,
        sklad: skladFilter,
        source: sourceFilter,
        createdBy: createdByFilter,
        search: search,
        limit: pageSize,
        offset: 0,
      );
      _items = page.items;
      _total = page.total;
    } catch (e) {
      _error = CoreClient.wrap(e).message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _service.list(
        type: typeFilter,
        status: statusFilter,
        dateFrom: dateFrom,
        dateTo: dateTo,
        sklad: skladFilter,
        source: sourceFilter,
        createdBy: createdByFilter,
        search: search,
        limit: pageSize,
        offset: _items.length,
      );
      _items = [..._items, ...page.items];
      _total = page.total;
    } catch (e) {
      _error = CoreClient.wrap(e).message;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void setFilters({
    String? type,
    String? status,
    String? from,
    String? to,
    int? sklad,
    int? createdBy,
    String? source,
    String? searchText,
    bool clearType = false,
    bool clearStatus = false,
    bool clearDates = false,
    bool clearSklad = false,
    bool clearCreatedBy = false,
    bool clearSource = false,
  }) {
    if (clearType) typeFilter = null;
    if (type != null) typeFilter = type;
    if (clearStatus) statusFilter = null;
    if (status != null) statusFilter = status;
    if (clearDates) {
      dateFrom = null;
      dateTo = null;
    }
    if (from != null) dateFrom = from;
    if (to != null) dateTo = to;
    if (clearSklad) skladFilter = null;
    if (sklad != null) skladFilter = sklad;
    if (clearCreatedBy) createdByFilter = null;
    if (createdBy != null) createdByFilter = createdBy;
    if (clearSource) sourceFilter = null;
    if (source != null) sourceFilter = source;
    if (searchText != null) search = searchText;
    load();
  }

  /// Ro'yxatdagi hujjatni almashtirish/qo'shish (tafsilot/forma natijasi).
  void upsert(CoreDoc doc) {
    final i = _items.indexWhere((d) => d.id == doc.id);
    if (i >= 0) {
      _items[i] = doc;
    } else {
      _items = [doc, ..._items];
      _total++;
    }
    notifyListeners();
  }

  void removeLocal(int id) {
    final before = _items.length;
    _items = _items.where((d) => d.id != id).toList();
    if (_items.length != before) _total--;
    notifyListeners();
  }

  // ── Amallar (xato tashlaydi — UI ko'rsatadi) ──

  Future<CoreDoc> create(CoreDoc doc) async {
    final saved = await _service.create(doc);
    upsert(saved);
    return saved;
  }

  Future<CoreDoc> update(int id, CoreDoc doc) async {
    final saved = await _service.update(id, doc);
    upsert(saved);
    return saved;
  }

  Future<CoreDocPostResult> post(int id) async {
    final res = await _service.post(id);
    upsert(res.doc);
    return res;
  }

  Future<CoreDocPostResult> quick(CoreDoc doc) async {
    final res = await _service.quick(doc);
    upsert(res.doc);
    return res;
  }

  Future<CoreDoc> cancel(int id) async {
    final doc = await _service.cancel(id);
    upsert(doc);
    return doc;
  }

  /// «Tuzatish»: asl hujjat bekor bo'ladi, qaytgan QORALAMA ro'yxatga
  /// qo'shiladi. Asl hujjatning yangi holati javobda kelmaydi — uni
  /// ro'yxatdan olib tashlaymiz (ekran yangilanganda bekor bo'lib qaytadi).
  Future<CoreDoc> rework(int id, {bool dropInputs = false}) async {
    final draft = await _service.rework(id, dropInputs: dropInputs);
    removeLocal(id);
    upsert(draft);
    return draft;
  }

  /// «Nusxa olish»: asl hujjat tegilmaydi, yangi qoralama qo'shiladi.
  Future<CoreDoc> copy(int id, {String? docDate}) async {
    final draft = await _service.copy(id, docDate: docDate);
    upsert(draft);
    return draft;
  }

  /// Tarqatish matritsasi — bitta so'rovda bir nechta hujjat.
  Future<CoreDocBatchResult> quickBatch(List<Map<String, dynamic>> docs) async {
    final res = await _service.quickBatch(docs);
    for (final d in res.docs) {
      upsert(d);
    }
    return res;
  }

  Future<void> delete(int id) async {
    await _service.delete(id);
    removeLocal(id);
  }

  Future<CoreDoc> fetch(int id) => _service.get(id);

  @override
  void clear() {
    _items = [];
    _total = 0;
    _loading = false;
    _loadingMore = false;
    _error = null;
    typeFilter = null;
    statusFilter = null;
    dateFrom = null;
    dateTo = null;
    skladFilter = null;
    createdByFilter = null;
    sourceFilter = null;
    search = '';
    notifyListeners();
  }
}
