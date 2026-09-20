// core2/ui/quick_doc_ui.dart — «Tez kiritish»: Kirim / Ko'chirish / Hisobdan
// chiqarish / Ishlab chiqarish uchun YAGONA forma (PLAN_UI_OSON §2.2).
// Bitta ekran, bitta yashil tugma («Saqlash va o'tkazish» → POST /docs/quick).
//
// Tamoyillar: kam yozish (standart ombor/sana/kontragent oldindan, «Tez-tez»
// chiplari, «Kechagidan nusxa»), inson birligi (kg/l/dona — base birlik hech
// qachon ko'rinmaydi, konvert `core_qty.dart` orqali), oddiy til
// (`core_labels.dart` xato tarjimoni).
//
// Tartib: < 900 px — telefon (qidiruv + pastki varaq klaviatura); ≥ 900 px —
// ikki panel (chap: qatorlar, o'ng: qidiruv + klaviatura) va yorliqlar:
// Enter — qo'shish, F2 — saqlash, Esc — orqaga, ↑↓ — ro'yxatda yurish.
//
// Maxsus oqimlar: kirimda «Jami summa» (narx avtomatik), ko'chirishda
// «Qabul qiluvchi tasdiqlasin» (qoralama + izoh boshida `[yo'lda]`) va
// «Qabul qildim» (draft → post), ishlab chiqarishda «Retsept bo'yicha
// to'ldirish» (`GET /recipes/expand`), takror tovarda birlashtirish taklifi.
//
// AKT (`act`, «Ishlab chiqarish»): ikkita ombor — «Xomashyo qayerdan?»
// (`from_sklad`, IXTIYORIY: sex ombori) va «Mahsulot qayerga?» (`to_sklad`).
// Ikkalasi ham standart holda foydalanuvchining «Bugun» dagi ombori, ya'ni
// oddiy holatda hech narsa bosilmaydi va bugungi kabi yuboriladi. Farq
// qilsa — sarlavhada bir qatorli eslatma; oxirgi juftlik foydalanuvchi +
// tur bo'yicha SharedPreferences'da eslab qolinadi (ACT_KONTRAKT §1, §11).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';
import 'package:uz_ai_dev/core2/services/core_recipe_service.dart';
import 'package:uz_ai_dev/core2/ui/quick_doc_result_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';
import 'package:uz_ai_dev/core2/ui/widgets/good_search.dart';
import 'package:uz_ai_dev/core2/ui/widgets/qty_keypad.dart';

/// Ikki panel chegarasi (kompyuter tartibi).
const double kWideBreakpoint = 900;

class QuickDocUi extends StatefulWidget {
  final String type;

  /// Foydalanuvchining «o'z» ombori (bosh sahifadan keladi).
  final int? skladId;

  /// Davom ettiriladigan qoralama (qatorlari bilan; bo'sh bo'lsa yuklanadi).
  final CoreDoc? draft;

  /// «Kutilmoqda» dan kelgan ko'chirishni qabul qilish oqimi.
  final bool receiveMode;

  const QuickDocUi({
    super.key,
    required this.type,
    this.skladId,
    this.draft,
    this.receiveMode = false,
  });

  @override
  State<QuickDocUi> createState() => _QuickDocUiState();
}

/// Tahrirlanayotgan qator (miqdor BUTUN base birlikda saqlanadi).
class _QLine {
  final CoreGood good;
  CoreGoodUnit unit;
  int baseQty;
  int price; // 1 `unit` narxi, butun so'm (faqat kirimda)
  int amount; // qator summasi, butun so'm
  final int flag; // production: 1 — sarf, 0 — mahsulot

  _QLine({
    required this.good,
    required this.unit,
    this.baseQty = 0,
    this.price = 0,
    this.amount = 0,
    this.flag = 0,
  });

  CoreDocLine toLine() => CoreDocLine(
        goodId: good.id,
        goodName: good.name,
        unit: unit.unit,
        qty: baseQty,
        price: price,
        amount: amount,
        flag: flag,
      );
}

class _QuickDocUiState extends State<QuickDocUi> {
  static const String _inTransitTag = '[yo\'lda]';

  final CoreDocService _docService = CoreDocService();
  final CoreRecipeService _recipes = CoreRecipeService();

  late String _date;
  int? _from;
  int? _to;
  int? _corr;
  final _comment = TextEditingController();
  bool _showComment = false;

  final List<_QLine> _lines = [];
  int _draftId = 0;

  /// Oxirgi SAQLANGAN holat «barmoq izi». Joriy holat bundan farq qilsa —
  /// saqlanmagan o'zgarish bor (chiqishda tasdiq so'raladi).
  String _savedSig = '';

  // Qidiruv (server tomonda, 250 ms debounce).
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  int _seq = 0;
  List<CoreGood> _results = const [];
  bool _searching = false;
  String? _searchError;
  int _hi = 0;

  // «Tez-tez» chiplari (widgets/good_search.dart — tarqatish ekrani bilan
  // umumiy).
  List<CoreFreqGood> _freq = const [];

  // Ishlab chiqarish: qaysi bo'limga qo'shilyapti (1 — sarf, 0 — mahsulot).
  int _activeFlag = 1;

  // Ko'chirish: qabul qiluvchi tasdiqlasin (qoralama + `[yo'lda]`).
  bool _confirmReceiver = false;

  bool _busy = false;
  bool _initDone = false;

  // Kompyuter tartibida o'ng paneldagi klaviatura.
  CoreGood? _padGood;
  int? _padEditIndex;
  QtyKeypadResult? _padInitial;
  // Klaviaturadagi «joriy qoldiq» qaysi ombordan (sarf qatori — xomashyo
  // ombori, mahsulot qatori — mahsulot ombori).
  int? _padSklad;

  String get type => widget.type;
  bool get hasFrom => CoreDocType.hasFrom(type);
  bool get hasTo => CoreDocType.hasTo(type);
  bool get hasCorr => CoreDocType.hasCorr(type);
  bool get hasPrice => CoreDocType.hasPrice(type);
  bool get isProduction => type == CoreDocType.production;
  bool get isAct => type == CoreDocType.act;
  bool get isTransfer => type == CoreDocType.transfer;

  /// Ikki bo'limli forma (sarf flag=1 + mahsulot flag=0): qayta ishlash va
  /// akt. Aktda sarf qatorlari IXTIYORIY — bo'sh qoldirilsa server retsept
  /// bo'yicha o'zi yozadi (ACT_KONTRAKT §4).
  bool get isMake => isProduction || isAct;

  /// Aktda «qayerdan» ixtiyoriy: tanlanmasa mahsulot ombori olinadi.
  bool get hasOptionalFrom => CoreDocType.hasOptionalFrom(type);

  /// Shu bo'lim qatorlari qaysi ombor qoldig'ini ko'rsatadi/yechadi:
  /// sarf (flag=1) — XOMASHYO ombori (`from`, aktda tanlanmasa `to`),
  /// mahsulot (flag=0) — MAHSULOT ombori (`to`).
  int? _skladForFlag(int flag) {
    if (isMake) return flag == 1 ? (_from ?? _to) : _to;
    return hasFrom ? _from : _to;
  }

  /// Qidiruv/qoldiq qaysi omborga tegishli (sarf «dan», kirim «ga»).
  int? get _activeSklad => _skladForFlag(isMake ? _activeFlag : 0);

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _date = d?.docDate ?? coreToday();
    _from = d?.fromSklad;
    _to = d?.toSklad;
    _corr = d?.corrId;
    _draftId = d?.id ?? 0;
    var comment = d?.comment ?? '';
    if (comment.startsWith(_inTransitTag)) {
      _confirmReceiver = !widget.receiveMode;
      comment = comment.substring(_inTransitTag.length).trim();
    }
    _comment.text = comment;
    _showComment = comment.isNotEmpty;
    // Qayta ishlashda avval sarf yoziladi; aktda esa avval TAOM (server
    // sarfni retsept bo'yicha o'zi yozishi mumkin).
    if (!isProduction) _activeFlag = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    final dict = context.read<CoreDictProvider>();
    final session = context.read<CoreSession>();
    final mine = widget.skladId ??
        (session.user?.sklads.isNotEmpty == true
            ? session.user!.sklads.first
            : (dict.activeSklads.length == 1 ? dict.activeSklads.first.id : null));

    if (hasFrom) _from ??= mine;
    if (hasTo) _to ??= isTransfer ? null : mine;
    if (isProduction) _to ??= mine;
    // Akt: IKKALA ombor ham standart holda «Bugun» dagi ombor — oddiy
    // (bitta omborli) holat uchun qo'shimcha bosish kerak emas.
    if (hasOptionalFrom) _from ??= mine;

    final draft = widget.draft;
    if (draft != null) {
      if (draft.lines.isNotEmpty) {
        _loadLines(draft.lines, dict);
      } else if (draft.id > 0) {
        _fetchDraft(draft.id);
      }
    }
    _restorePrefs();
    _afterSkladChanged();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _comment.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────── Yuklashlar ───────────────────────────

  Future<void> _fetchDraft(int id) async {
    try {
      final doc = await _docService.get(id);
      if (!mounted) return;
      setState(() {
        _loadLines(doc.lines, context.read<CoreDictProvider>());
        _savedSig = _sig();
      });
    } catch (e) {
      if (mounted) showErrorUz(context, e);
    }
  }

  /// Hujjat qatorlaridan tahrir qatorlari (tovar keshda bo'lmasa qator
  /// ma'lumotidan quriladi — `doc_form_ui.dart` dagi qoida).
  void _loadLines(List<CoreDocLine> lines, CoreDictProvider dict) {
    dict.ensureGoods(lines.map((l) => l.goodId));
    for (final l in lines) {
      final good = dict.goodById(l.goodId) ??
          CoreGood(
              id: l.goodId,
              name: l.goodName,
              baseUnit: coreBaseUnitOf(l.unit),
              partial: true);
      final unit = good.selectableUnits
          .firstWhere((u) => u.unit == l.unit, orElse: () => good.preferredUnit);
      _lines.add(_QLine(
        good: good,
        unit: unit,
        baseQty: l.qty,
        price: l.price,
        amount: l.amount,
        flag: l.flag,
      ));
    }
  }

  /// Eslab qolinadigan sozlama kaliti: foydalanuvchi + hujjat turi bo'yicha
  /// (bir qurilmada bir necha xodim ishlashi mumkin).
  String _prefKey(String name) {
    final uid = context.read<CoreSession>().user?.id ?? 0;
    return 'core_quick_${name}_${type}_u$uid';
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final dict = context.read<CoreDictProvider>();
    final fromKey = _prefKey('from');
    final toKey = _prefKey('to');
    setState(() {
      if (hasCorr && _corr == null) {
        final saved = prefs.getInt('core_quick_corr_$type');
        _corr = saved ??
            (type == CoreDocType.receipt
                ? (dict.findCorrByName('рынок')?.id ??
                    dict.findCorrByName('bozor')?.id)
                : null);
      }
      if (isTransfer && _to == null) {
        _to = prefs.getInt('core_quick_to_$type');
      }
      // Akt: oxirgi ishlatilgan «xomashyo → mahsulot» JUFTLIGI (masalan
      // «Sex» → «Magazin»). Qoralama ochilganda hujjatdagi qiymat ustun.
      // Eslangan ombor JIMGINA qo'llanmaydi — ikkala chip ham nomni
      // ko'rsatadi, farq bo'lsa sarlavhada eslatma chiqadi.
      if (hasOptionalFrom && widget.draft == null) {
        final savedFrom = prefs.getInt(fromKey);
        final savedTo = prefs.getInt(toKey);
        if (savedFrom != null && savedTo != null) {
          final ids = dict.activeSklads.map((s) => s.id).toSet();
          // O'chirilgan/ruxsat olib qo'yilgan ombor tiklanmaydi.
          if (ids.isEmpty || (ids.contains(savedFrom) && ids.contains(savedTo))) {
            _from = savedFrom;
            _to = savedTo;
          }
        }
      }
      // Boshlang'ich holat «saqlangan» deb belgilanadi (qoralamani ochib,
      // hech narsa o'zgartirmay chiqishda ortiqcha savol bo'lmasin).
      _savedSig = _sig();
    });
    _afterSkladChanged();
  }

  Future<void> _savePrefs() async {
    final fromKey = hasOptionalFrom ? _prefKey('from') : '';
    final toKey = hasOptionalFrom ? _prefKey('to') : '';
    final prefs = await SharedPreferences.getInstance();
    if (hasCorr && _corr != null) await prefs.setInt('core_quick_corr_$type', _corr!);
    if (isTransfer && _to != null) await prefs.setInt('core_quick_to_$type', _to!);
    if (hasOptionalFrom && _from != null && _to != null) {
      await prefs.setInt(fromKey, _from!);
      await prefs.setInt(toKey, _to!);
    }
  }

  /// Ombor almashgach: qoldiq keshi + «Tez-tez» chiplari yangilanadi.
  /// Ikki omborli formada (akt/qayta ishlash) IKKALA ombor qoldig'i ham
  /// keshga olinadi — sarf qatori xomashyo omborining qoldig'ini,
  /// mahsulot qatori esa mahsulot omborinikini ko'rsatishi kerak.
  void _afterSkladChanged() {
    final sklad = _activeSklad;
    final stock = context.read<CoreStockProvider>();
    final ids = <int>{
      if (sklad != null) sklad,
      if (isMake) ...[
        if (_from != null) _from!,
        if (_to != null) _to!,
      ],
    };
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final id in ids) {
        stock.ensure(id);
      }
    });
    if (sklad != null) _loadFreq(sklad);
  }

  Future<void> _loadFreq(int sklad) async {
    final list = await CoreFreqGood.load(
      service: _docService,
      skladId: sklad,
      type: type,
    );
    if (!mounted) return;
    setState(() => _freq = list);
  }

  // ─────────────────────────── Qidiruv ───────────────────────────

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(v));
  }

  Future<void> _runSearch(String q) async {
    final my = ++_seq;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await context.read<CoreDictProvider>().searchGoods(q, limit: 30);
      if (!mounted || my != _seq) return;
      setState(() {
        _results = r;
        _hi = 0;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() => _searchError = coreErrorUz(e).title);
    } finally {
      if (mounted && my == _seq) setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _debounce?.cancel();
    _seq++; // yo'ldagi javob eskiradi
    _search.clear();
    setState(() {
      _results = const [];
      _searchError = null;
    });
    _searchFocus.requestFocus();
  }

  // ─────────────────────────── Qatorlar ───────────────────────────

  Future<void> _openKeypad(CoreGood good, {int? editIndex}) async {
    final wide = MediaQuery.of(context).size.width >= kWideBreakpoint;
    final init = editIndex == null
        ? null
        : QtyKeypadResult(
            baseQty: _lines[editIndex].baseQty,
            unit: _lines[editIndex].unit,
            price: _lines[editIndex].price,
            amount: _lines[editIndex].amount,
          );
    // Klaviaturadagi «Qoldiq» — shu QATOR ombori: tahrirda qatorning o'z
    // bayrog'i, yangi qatorda esa faol bo'lim bayrog'i bo'yicha.
    final sklad = _skladForFlag(editIndex != null
        ? _lines[editIndex].flag
        : (isMake ? _activeFlag : 0));
    if (wide) {
      setState(() {
        _padGood = good;
        _padEditIndex = editIndex;
        _padInitial = init;
        _padSklad = sklad;
      });
      return;
    }
    final res = await showQtyKeypad(
      context,
      good: good,
      skladId: sklad,
      withSum: hasPrice,
      initial: init,
      okText: editIndex == null ? 'Qo\'shish' : 'Saqlash',
    );
    if (res == null || !mounted) return;
    await _applyQty(good, res, editIndex: editIndex);
  }

  Future<void> _applyQty(CoreGood good, QtyKeypadResult res,
      {int? editIndex}) async {
    if (editIndex != null) {
      setState(() {
        final l = _lines[editIndex];
        l.unit = res.unit;
        l.baseQty = res.baseQty;
        l.price = res.price;
        l.amount = res.amount;
      });
      _clearSearch();
      return;
    }
    final flag = isMake ? _activeFlag : 0;
    final dup = _lines.indexWhere((l) => l.good.id == good.id && l.flag == flag);
    if (dup >= 0) {
      final merge = await _askMerge(good, _lines[dup]);
      if (!mounted) return;
      if (merge == null) return; // bekor
      if (merge) {
        setState(() {
          final l = _lines[dup];
          // Birlik farq qilishi mumkin — qo'shish BASE birlikda.
          l.baseQty += res.baseQty;
          l.amount += res.amount;
          l.price = l.baseQty > 0 && l.amount > 0
              ? (l.amount * l.unit.toBase / l.baseQty).round()
              : l.price;
        });
        _clearSearch();
        return;
      }
    }
    setState(() {
      _lines.add(_QLine(
        good: good,
        unit: res.unit,
        baseQty: res.baseQty,
        price: res.price,
        amount: res.amount,
        flag: flag,
      ));
    });
    _clearSearch();
  }

  /// Takror tovar: qo'shib yuborilsinmi (true) / alohida qator (false) /
  /// bekor (null).
  Future<bool?> _askMerge(CoreGood good, _QLine existing) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bu tovar allaqachon bor'),
        content: Text(
          '«${good.name}» ro\'yxatda: '
          '${coreQtyUnitInUz(existing.baseQty, existing.unit)}.\n'
          'Yangi miqdorni ustiga qo\'shib yuboraymi?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Alohida qator'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Qo\'shib yuborish'),
          ),
        ],
      ),
    );
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  int get _total => _lines.fold(0, (s, l) => s + l.amount);

  // ─────────────────── «Kechagidan nusxa» va retsept ───────────────────

  Future<void> _copyLast() async {
    setState(() => _busy = true);
    try {
      final page = await _docService.list(
        type: type,
        status: CoreDocStatus.posted,
        sklad: hasFrom ? _from : _to,
        limit: 20,
      );
      CoreDoc? match;
      for (final d in page.items) {
        if (hasFrom && _from != null && d.fromSklad != _from) continue;
        if (hasTo && _to != null && d.toSklad != _to) continue;
        match = d;
        break;
      }
      if (match == null) {
        if (mounted) showInfoUz(context, 'Bu yo\'nalishda oldingi hujjat topilmadi');
        return;
      }
      final full = await _docService.get(match.id);
      if (!mounted) return;
      if (_lines.isNotEmpty) {
        final ok = await confirmDialog(
          context,
          'Nusxa olish',
          'Hozirgi ${_lines.length} qator o\'chib, '
              '${coreDayUz(full.docDate)} hujjatidagi ${full.lines.length} qator yuklansinmi?',
          okText: 'Ha, yuklansin',
        );
        if (!ok || !mounted) return;
      }
      setState(() {
        _lines.clear();
        _loadLines(full.lines, context.read<CoreDictProvider>());
      });
      if (mounted) {
        showInfoUz(context,
            '${coreDayUz(full.docDate)} hujjatidan ${full.lines.length} qator yuklandi');
      }
    } catch (e) {
      if (mounted) showErrorUz(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Ishlab chiqarish/akt: mahsulot (flag 0) qatorlari bo'yicha sarfni
  /// (flag 1) retsept asosida to'ldirish — `GET /recipes/expand`
  /// (ACT_KONTRAKT §7: `good_id` + `qty` + hujjat `date`; `sklad_id`
  /// yuborilmaydi — u natijaga ta'sir qilmaydi).
  ///
  /// Retsepti yo'q taom: yangi serverda `422`, eskisida `500` — ikkalasi
  /// ham «retsept yo'q» deb sanaladi, qolgan xatolar (tarmoq, ruxsat)
  /// yuqoriga chiqadi. Javobdagi `cut` — sikl tufayli ichkariga yoyilmagan
  /// yarim tayyorlar; ular haqida alohida aytiladi.
  Future<void> _expandRecipe() async {
    final products = _lines.where((l) => l.flag == 0).toList();
    if (products.isEmpty) {
      showInfoUz(context,
          'Avval «${isAct ? 'Mahsulot (taomlar)' : 'Mahsulot'}» bo\'limiga taom qo\'shing');
      return;
    }
    if (_lines.any((l) => l.flag == 1)) {
      final ok = await confirmDialog(context, 'Retsept bo\'yicha to\'ldirish',
          'Mavjud sarf qatorlari o\'chib, retsept bo\'yicha qaytadan yoziladimi?',
          okText: 'Ha');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final dict = context.read<CoreDictProvider>();
      // good_id → base miqdor (yig'indi).
      final need = <int, int>{};
      final names = <int, String>{};
      final units = <int, String>{};
      final cut = <int>{}; // ichkariga yoyilmagan yarim tayyorlar
      var missing = 0;
      for (final p in products) {
        try {
          final res = await _recipes.expand(
            goodId: p.good.id,
            date: _date,
            qty: p.baseQty,
          );
          if (res.ingredients.isEmpty) missing++;
          cut.addAll(res.cut);
          for (final m in res.ingredients) {
            final id = (m['good_id'] as num?)?.toInt() ?? 0;
            if (id <= 0) continue;
            need[id] = (need[id] ?? 0) + ((m['qty'] as num?)?.toInt() ?? 0);
            names[id] = (m['good_name'] ?? '').toString();
            units[id] = (m['base_unit'] ?? '').toString();
          }
        } catch (e) {
          // Faqat «retsept yo'q» jimgina sanaladi; boshqasi — haqiqiy xato.
          if (!coreIsNoRecipeError(e)) rethrow;
          missing++;
        }
      }
      if (!mounted) return;
      if (need.isEmpty) {
        showInfoUz(
            context,
            isAct
                ? 'Retsept topilmadi — sarfni qo\'lda kiriting '
                    '(yoki bo\'sh qoldiring: server o\'zi yozishga urinadi)'
                : 'Retsept topilmadi — sarfni qo\'lda kiriting');
        return;
      }
      await dict.ensureGoods(need.keys);
      if (!mounted) return;
      setState(() {
        _lines.removeWhere((l) => l.flag == 1);
        need.forEach((id, qty) {
          final good = dict.goodById(id) ??
              CoreGood(
                  id: id,
                  name: names[id] ?? 'Tovar #$id',
                  baseUnit: units[id]?.isNotEmpty == true ? units[id]! : 'mpcs',
                  partial: true);
          _lines.add(_QLine(
            good: good,
            unit: good.preferredUnit,
            baseQty: qty,
            flag: 1,
          ));
        });
      });
      showInfoUz(
          context,
          'Retsept bo\'yicha ${need.length} ta sarf qatori yozildi'
          '${missing > 0 ? ' ($missing ta taomda retsept yo\'q)' : ''}'
          '${cut.isEmpty ? '' : '. ${cut.length} ta yarim tayyorning ichi '
              'yoyilmadi (retseptda sikl yoki juda chuqur) — ular sarf '
              'qatori bo\'lib qoldi'}');
    } catch (e) {
      if (mounted) showErrorUz(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── Saqlash ───────────────────────────

  String? _validate() {
    if (hasFrom && _from == null) return 'Qaysi ombordan — tanlang';
    if (hasTo && _to == null) {
      return isAct ? 'Mahsulot qaysi omborga — tanlang' : 'Qaysi omborga — tanlang';
    }
    if (hasCorr && _corr == null) {
      return type == CoreDocType.receipt ? 'Kimdan olindi — tanlang' : 'Kontragentni tanlang';
    }
    if (isTransfer && _from == _to) return 'Ombor «dan» va «ga» bir xil';
    if (_lines.isEmpty) return 'Kamida bitta tovar qo\'shing';
    for (final l in _lines) {
      if (l.baseQty <= 0) return '«${l.good.name}» miqdori 0';
      if (hasPrice && l.amount <= 0) return '«${l.good.name}» summasi kiritilmadi';
    }
    if (isProduction) {
      if (!_lines.any((l) => l.flag == 1)) return 'Sarf qatorlari yo\'q';
      if (!_lines.any((l) => l.flag == 0)) return 'Mahsulot qatorlari yo\'q';
    }
    // Aktda sarf qatorlari IXTIYORIY (server retsept bo'yicha o'zi yozadi),
    // mahsulot (taom) esa bo'lishi shart.
    if (isAct && !_lines.any((l) => l.flag == 0)) {
      return 'Mahsulot (taom) qatorlari yo\'q';
    }
    return null;
  }

  CoreDoc _build({bool inTransit = false}) {
    var comment = _comment.text.trim();
    if (inTransit) {
      comment = comment.isEmpty ? _inTransitTag : '$_inTransitTag $comment';
    }
    return CoreDoc(
      id: _draftId,
      type: type,
      docDate: _date,
      // Akt: `from_sklad` — XOMASHYO ombori. PUT to'liq almashtirish
      // bo'lgani uchun tanlangan qiymat har safar yuboriladi; bir xil
      // bo'lsa `to_sklad` bilan teng ketadi (ACT_KONTRAKT §3, §9).
      fromSklad: (hasFrom || hasOptionalFrom) ? _from : null,
      toSklad: hasTo ? _to : null,
      corrId: hasCorr ? _corr : null,
      comment: comment,
      lines: _lines.map((l) => l.toLine()).toList(),
    );
  }

  /// Asosiy amal: qoralama bo'lsa `POST /docs` + `POST /docs/{id}/post`,
  /// aks holda bitta so'rovda `POST /docs/quick`.
  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      showInfoUz(context, err);
      return;
    }
    // Ko'chirish: qabul qiluvchi tasdiqlasin — faqat qoralama saqlanadi.
    if (_confirmReceiver && isTransfer && !widget.receiveMode) {
      await _saveDraft(inTransit: true, closeAfter: true);
      return;
    }
    final docs = context.read<CoreDocsProvider>();
    final stock = context.read<CoreStockProvider>();
    setState(() => _busy = true);
    try {
      final doc = _build();
      CoreDocPostResult res;
      if (_draftId > 0) {
        await docs.update(_draftId, doc);
        res = await docs.post(_draftId);
      } else {
        res = await docs.quick(doc);
      }
      if (!mounted) return;
      _savedSig = _sig(); // o'tkazildi — chiqish qo'riqchisi kerak emas
      await _savePrefs();
      stock.refreshSklads([res.doc.fromSklad, res.doc.toSklad]);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuickDocResultUi(
            result: res,
            type: type,
            skladId: widget.skladId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showErrorUz(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────── Saqlanmagan qatorlar (chiqish qo'riqchisi) ─────────────────

  /// Joriy hujjat mazmuni — saqlangan holat bilan taqqoslash uchun.
  String _sig() => [
        _date,
        _from,
        _to,
        _corr,
        _comment.text.trim(),
        for (final l in _lines)
          '${l.good.id}:${l.flag}:${l.baseQty}:${l.unit.unit}:${l.amount}',
      ].join('|');

  /// Saqlanmagan qator bormi (bo'sh hujjatdan chiqish erkin).
  bool get _unsaved => _lines.isNotEmpty && _sig() != _savedSig;

  /// «Orqaga»/Esc: saqlanmagan qatorlar jimgina yo'qolmasin.
  /// 0 — qolish, 1 — qoralama saqlab chiqish, 2 — saqlamay chiqish.
  Future<int> _askExit() async {
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saqlanmagan qatorlar bor'),
        content: Text(
          'Saqlanmagan ${_lines.length} qator bor.\n'
          'Chiqsangiz ular yo\'qoladi.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('Qolish')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: Text('Chiqish',
                style: TextStyle(color: Colors.red.shade700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('Qoralama saqlash'),
          ),
        ],
      ),
    );
    return r ?? 0;
  }

  Future<void> _onPopBlocked() async {
    final choice = await _askExit();
    if (!mounted) return;
    switch (choice) {
      case 1:
        await _saveDraft(closeAfter: true);
        break;
      case 2:
        // Qatorlar ataylab tashlab ketiladi — qo'riqchi o'chiriladi.
        setState(() => _savedSig = _sig());
        if (mounted) Navigator.pop(context);
        break;
      default:
        break;
    }
  }

  Future<void> _saveDraft({bool inTransit = false, bool closeAfter = false}) async {
    final err = _validate();
    if (err != null) {
      showInfoUz(context, err);
      return;
    }
    final docs = context.read<CoreDocsProvider>();
    setState(() => _busy = true);
    try {
      final doc = _build(inTransit: inTransit);
      final saved = _draftId > 0
          ? await docs.update(_draftId, doc)
          : await docs.create(doc);
      if (!mounted) return;
      _draftId = saved.id;
      _savedSig = _sig();
      await _savePrefs();
      if (!mounted) return;
      showInfoUz(
          context,
          inTransit
              ? 'Saqlandi. Qabul qiluvchi «Kutilmoqda» dan tasdiqlaydi'
              : 'Qoralama saqlandi: ${saved.number}');
      if (closeAfter) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorUz(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────── Yorliqlar ───────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f2) {
      if (!_busy) _submit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_padGood != null) {
        setState(() => _padGood = null);
      } else if (_search.text.isNotEmpty) {
        _clearSearch();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }
    if (_results.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _hi = (_hi + 1) % _results.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _hi = (_hi - 1 + _results.length) % _results.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _openKeypad(_results[_hi]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─────────────────────────── Ko'rinish ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final task = coreTaskOf(type);
    final wide = MediaQuery.of(context).size.width >= kWideBreakpoint;
    return PopScope(
      // Saqlanmagan qatorlar bo'lsa «orqaga» (tizim tugmasi, Esc, AppBar)
      // jimgina chiqib ketmaydi — tasdiq so'raladi.
      canPop: !_unsaved,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        _onPopBlocked();
      },
      child: _scaffold(task, wide),
    );
  }

  Widget _scaffold(CoreTask? task, bool wide) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.receiveMode ? 'Qabul qilish' : (task?.title ?? coreTypeUz(type)),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(coreTypeSh5(type),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          if (!widget.receiveMode)
            TextButton.icon(
              onPressed: _busy ? null : _copyLast,
              icon: const Icon(Icons.content_copy, size: 18),
              label: const Text('Kechagidan'),
            ),
        ],
      ),
      // Yorliqlar: tugma fokusni O'ZI olmaydi (qidiruv maydoni autofocus
      // bo'ladi) — hodisalar fokusdagi maydondan yuqoriga «pufakchalanadi».
      body: Focus(
        canRequestFocus: false,
        onKeyEvent: _onKey,
        child: CoreConnectGate(
          child: Column(
            children: [
              Expanded(child: wide ? _wideBody() : _narrowBody()),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _narrowBody() {
    final searching = _search.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        _headerCard(),
        const SizedBox(height: 8),
        _searchField(),
        if (searching) ...[
          if (isMake) _flagSwitch(),
          const SizedBox(height: 6),
          _resultsCard(maxHeight: 320),
        ] else ...[
          if (_freq.isNotEmpty) ...[
            const SizedBox(height: 8),
            _freqChips(),
          ],
          const SizedBox(height: 8),
          ..._sections(),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Tovar qidiring yoki «Tez-tez» dan tanlang',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _wideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            children: [
              _headerCard(),
              const SizedBox(height: 8),
              ..._sections(),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('Qatorlar bu yerda ko\'rinadi',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 380,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            ),
            child: _padGood != null
                ? SingleChildScrollView(
                    child: QtyKeypad(
                      key: ValueKey('pad-${_padGood!.id}-$_padEditIndex'),
                      good: _padGood!,
                      skladId: _padSklad ?? _activeSklad,
                      withSum: hasPrice,
                      initial: _padInitial,
                      okText:
                          _padEditIndex == null ? 'Qo\'shish (Enter)' : 'Saqlash',
                      onCancel: () => setState(() => _padGood = null),
                      onSubmit: (r) {
                        final good = _padGood!;
                        final idx = _padEditIndex;
                        setState(() => _padGood = null);
                        _applyQty(good, r, editIndex: idx);
                        _searchFocus.requestFocus();
                      },
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                        child: Column(
                          children: [
                            _searchField(),
                            if (isMake) _flagSwitch(),
                          ],
                        ),
                      ),
                      if (_freq.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                          child: _freqChips(),
                        ),
                      Expanded(child: _resultsCard()),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'Enter — qo\'shish · F2 — saqlash · Esc — orqaga · ↑↓ — ro\'yxat',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Sarlavha (qayerdan → qayerga, sana, kontragent) ──

  Widget _headerCard() {
    final dict = context.watch<CoreDictProvider>();
    final session = context.watch<CoreSession>();
    final backdated = _date != coreToday();
    final onePlace = _onePlaceOf(dict);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasCorr)
                _chip(
                  icon: Icons.storefront_outlined,
                  label: _corr == null
                      ? (type == CoreDocType.receipt ? 'Kimdan?' : 'Kontragent?')
                      : dict.corrName(_corr),
                  warn: _corr == null,
                  onTap: widget.receiveMode ? null : _pickCorr,
                ),
              if (hasFrom)
                _chip(
                  icon: Icons.warehouse_outlined,
                  label: _from == null ? 'Qaysi ombordan?' : dict.skladName(_from),
                  warn: _from == null,
                  onTap: widget.receiveMode ? null : () => _pickSklad(isFrom: true),
                ),
              // Akt: «Xomashyo qayerdan?» — ixtiyoriy, lekin standart holda
              // to'ldirilgan (mahsulot ombori bilan bir xil).
              if (hasOptionalFrom)
                _chip(
                  icon: Icons.warehouse_outlined,
                  label: _from == null
                      ? 'Xomashyo qayerdan?'
                      : dict.skladName(_from),
                  sub: 'xomashyo · sex ombori',
                  onTap: (widget.receiveMode || onePlace)
                      ? null
                      : () => _pickSklad(isFrom: true),
                ),
              if ((hasFrom || hasOptionalFrom) && hasTo)
                const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              if (hasTo)
                _chip(
                  icon: Icons.inventory_2_outlined,
                  label: _to == null
                      ? (isAct ? 'Mahsulot qayerga?' : 'Qaysi omborga?')
                      : dict.skladName(_to),
                  sub: isAct ? 'mahsulot' : null,
                  warn: _to == null,
                  onTap: (widget.receiveMode || (isAct && onePlace))
                      ? null
                      : () => _pickSklad(isFrom: false),
                ),
              _chip(
                icon: Icons.event,
                label: coreDayUz(_date),
                warn: backdated,
                onTap: () async {
                  final d = await pickDate(context, _date,
                      allowPast: session.canBackdate);
                  if (d != null && mounted) setState(() => _date = d);
                },
              ),
              _chip(
                icon: Icons.chat_bubble_outline,
                label: _showComment ? 'Izoh' : 'Izoh qo\'shish',
                onTap: () => setState(() => _showComment = !_showComment),
              ),
            ],
          ),
          // Ikki xil ombor: bitta neytral qatorda tushuntiriladi (xato emas).
          if (_splitSklads)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: Colors.grey.shade700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Xomashyo: ${dict.skladName(_from)} → '
                      'mahsulot: ${dict.skladName(_to)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ),
          if (backdated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.history, size: 15, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Orqa sana: hujjat ${coreDateUz(_date)} kuniga yoziladi',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade900),
                    ),
                  ),
                ],
              ),
            ),
          if (_showComment)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _comment,
                decoration: coreInput('Izoh (ixtiyoriy)'),
              ),
            ),
          if (isTransfer && !widget.receiveMode)
            SwitchListTile(
              value: _confirmReceiver,
              onChanged: (v) => setState(() => _confirmReceiver = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Qabul qiluvchi tasdiqlasin',
                  style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _confirmReceiver
                    ? 'Qoralama saqlanadi, qabul qiluvchi «Kutilmoqda» dan tasdiqlaydi'
                    : 'Darhol o\'tkaziladi (SH5 dagidek)',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

  /// Chip: [sub] — kichik kulrang ostyozuv (qaysi chip nimaga tegishli:
  /// «xomashyo · sex ombori» / «mahsulot»).
  Widget _chip({
    required IconData icon,
    required String label,
    String? sub,
    VoidCallback? onTap,
    bool warn = false,
  }) {
    final color = warn ? Colors.orange.shade800 : kCoreAccentDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  if (sub != null)
                    Text(sub,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.expand_more, size: 15, color: color),
          ],
        ),
      ),
    );
  }

  /// Foydalanuvchiga bitta ombor ochiq (yoki lug'at hali bo'sh) — tanlagich
  /// ma'nosiz, chip oddiy yozuv bo'lib qoladi. Server `GET /sklads` ni
  /// o'zi cheklaydi, mijoz tomonda qo'shimcha filtr YO'Q.
  bool _onePlaceOf(CoreDictProvider dict) => dict.activeSklads.length <= 1;

  /// Aktda xomashyo va mahsulot omborlari boshqa-boshqa.
  bool get _splitSklads =>
      hasOptionalFrom && _from != null && _to != null && _from != _to;

  Future<void> _pickSklad({required bool isFrom}) async {
    // `GET /sklads` allaqachon foydalanuvchi omborlari bilan cheklangan
    // (API_V2: users.sklads) — qo'shimcha mijoz tomon filtri kerak emas.
    final list = context.read<CoreDictProvider>().activeSklads;
    final id = await _pickFromList<CoreSklad>(
      title: isAct
          ? (isFrom ? 'Xomashyo qaysi ombordan' : 'Mahsulot qaysi omborga')
          : (isFrom ? 'Qaysi ombordan' : 'Qaysi omborga'),
      items: list,
      label: (s) => s.name,
      idOf: (s) => s.id,
      current: isFrom ? _from : _to,
    );
    if (id == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = id;
      } else {
        _to = id;
      }
    });
    _afterSkladChanged();
  }

  Future<void> _pickCorr() async {
    final dict = context.read<CoreDictProvider>();
    final kinds = type == CoreDocType.receipt
        ? const ['supplier', 'other']
        : const ['payment', 'writeoff', 'debtor', 'other'];
    final list = dict.corrsOfKind(kinds);
    final id = await _pickFromList<CoreCorr>(
      title: type == CoreDocType.receipt ? 'Kimdan olindi' : 'Kontragent',
      items: list,
      label: (c) => c.name,
      idOf: (c) => c.id,
      current: _corr,
    );
    if (id == null || !mounted) return;
    setState(() => _corr = id);
    _savePrefs();
  }

  Future<int?> _pickFromList<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    required int Function(T) idOf,
    int? current,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PickSheet<T>(
        title: title,
        items: items,
        label: label,
        idOf: idOf,
        current: current,
      ),
    );
  }

  // ── Qidiruv va natijalar ──

  Widget _searchField() {
    return TextField(
      controller: _search,
      focusNode: _searchFocus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        setState(() {});
        _onSearchChanged(v);
      },
      onSubmitted: (_) {
        if (_results.isNotEmpty) _openKeypad(_results[_hi]);
      },
      decoration: InputDecoration(
        hintText: 'Tovar qidirish…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : (_search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear), onPressed: _clearSearch)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }

  Widget _resultsCard({double? maxHeight}) {
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_searchError!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
      );
    }
    if (_search.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Tovar nomini yozing',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_searching ? 'Qidirilmoqda…' : 'Topilmadi',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      );
    }
    final list = ListView.separated(
      shrinkWrap: maxHeight != null,
      physics: maxHeight != null ? const ClampingScrollPhysics() : null,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _goodTile(_results[i], highlighted: i == _hi),
    );
    if (maxHeight == null) return list;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: list,
    );
  }

  Widget _goodTile(CoreGood g, {bool highlighted = false}) {
    final sklad = _activeSklad;
    final row = sklad == null
        ? null
        : context.select<CoreStockProvider, CoreStockRow?>(
            (s) => s.rowFor(sklad, g.id));
    return Container(
      color: highlighted ? kCoreAccent.withValues(alpha: 0.15) : null,
      child: ListTile(
        dense: true,
        title: Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            coreUnitUz(g.baseUnit),
            if (g.isComplect) 'taom',
            if (g.isSemi) 'yarim tayyor',
          ].join(' · '),
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: row == null
            ? null
            : Text(
                coreQtyUnitUz(row.qty, row.baseUnit),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: row.qty < 0 ? Colors.red.shade700 : Colors.black87,
                ),
              ),
        onTap: () => _openKeypad(g),
      ),
    );
  }

  Widget _freqChips() => CoreFreqChips(items: _freq, onPick: _openFreq);

  Future<void> _openFreq(CoreFreqGood f) async {
    final good =
        await CoreFreqGood.resolve(context.read<CoreDictProvider>(), f);
    if (!mounted) return;
    await _openKeypad(good);
  }

  // ── Qatorlar ro'yxati ──

  /// Bo'limlar: qayta ishlashda «Sarf → Mahsulot», aktda esa avval TAOM
  /// (asosiy ish), keyin ixtiyoriy «Sarf (ingredientlar)». Oddiy turlarda —
  /// bitta ro'yxat.
  List<Widget> _sections() {
    if (isProduction) {
      return [
        _sectionTitle('Sarf (xomashyo)', flag: 1),
        ..._linesOf(1),
        const SizedBox(height: 8),
        _sectionTitle('Mahsulot (chiqish)', flag: 0),
        ..._linesOf(0),
      ];
    }
    if (isAct) {
      final dict = context.watch<CoreDictProvider>();
      return [
        _sectionTitle('Mahsulot (taomlar)', flag: 0),
        ..._linesOf(0),
        const SizedBox(height: 8),
        _sectionTitle('Sarf (ingredientlar)', flag: 1),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            _lines.any((l) => l.flag == 1)
                ? 'Sarf ${dict.skladName(_from ?? _to)} omboridan yechiladi'
                : 'Ixtiyoriy: bo\'sh qoldirsangiz retsept bo\'yicha server '
                    'o\'zi yozadi (${dict.skladName(_from ?? _to)} ombori)',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ),
        ..._linesOf(1),
      ];
    }
    return _linesOf(0);
  }

  Widget _sectionTitle(String title, {required int flag}) {
    final active = _activeFlag == flag;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          if (flag == 1)
            TextButton.icon(
              onPressed: _busy ? null : _expandRecipe,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Retsept bo\'yicha'),
            ),
          ChoiceChip(
            label: Text(active ? 'Shu yerga qo\'shiladi' : 'Bu yerga qo\'shish',
                style: const TextStyle(fontSize: 11.5)),
            selected: active,
            selectedColor: kCoreAccent.withValues(alpha: 0.3),
            onSelected: (_) => setState(() {
              _activeFlag = flag;
              _afterSkladChanged();
            }),
          ),
        ],
      ),
    );
  }

  /// Ishlab chiqarish/aktda tanlangan tovar qaysi bo'limga tushishi (qidiruv
  /// paytida bo'lim sarlavhalari ko'rinmaydi).
  Widget _flagSwitch() {
    final names = isAct
        ? const {0: 'Taom', 1: 'Sarf'}
        : const {1: 'Sarf', 0: 'Mahsulot'};
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('Qo\'shiladi:',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(width: 6),
          for (final e in names.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                selected: _activeFlag == e.key,
                selectedColor: kCoreAccent.withValues(alpha: 0.3),
                onSelected: (_) => setState(() {
                  _activeFlag = e.key;
                  _afterSkladChanged();
                }),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _linesOf(int flag) {
    final out = <Widget>[];
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].flag != flag) continue;
      out.add(_lineTile(i));
    }
    return out;
  }

  Widget _lineTile(int index) {
    final l = _lines[index];
    return Dismissible(
      key: ValueKey('line-${l.good.id}-$index-${l.flag}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: Colors.red.shade700),
      ),
      onDismissed: (_) => _removeLine(index),
      child: InkWell(
        onTap: () => _openKeypad(l.good, editIndex: index),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.good.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5)),
                    if (l.amount > 0)
                      Text(coreSumUz(l.amount),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                coreQtyUnitInUz(l.baseQty, l.unit),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'O\'chirish',
                onPressed: () => _removeLine(index),
                icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pastki panel ──

  Widget _bottomBar() {
    final session = context.watch<CoreSession>();
    final canPost = session.canPost(type);
    final canCreate = session.canCreate(type);
    final draftOnly = _confirmReceiver && isTransfer && !widget.receiveMode;
    final label = widget.receiveMode
        ? 'Qabul qildim'
        : draftOnly
            ? 'Yuborish (tasdiq kutiladi)'
            : 'Saqlash va o\'tkazish';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('${_lines.length} qator',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                      const Spacer(),
                      if (hasPrice)
                        Text('Jami: ${coreSumUz(_total)}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (!widget.receiveMode && !draftOnly)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            onPressed: canCreate ? () => _saveDraft() : null,
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size(110, 50)),
                            child: const Text('Qoralama'),
                          ),
                        ),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              (draftOnly ? canCreate : (canPost && canCreate))
                                  ? _submit
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(label,
                              style: const TextStyle(
                                  fontSize: 15.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  if (!canPost && !draftOnly && !widget.receiveMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'O\'tkazish ruxsati yo\'q («${corePermUz(CorePerms.docPost(CoreDocType.permType(type)))}») — qoralama saqlang',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.orange.shade900),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ───────────────────────── Ro'yxatdan tanlash ─────────────────────────

class _PickSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) label;
  final int Function(T) idOf;
  final int? current;
  const _PickSheet({
    required this.title,
    required this.items,
    required this.label,
    required this.idOf,
    this.current,
  });

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = widget.items
        .where((e) => q.isEmpty || widget.label(e).toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (widget.items.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: coreInput('Qidirish',
                    suffix: const Icon(Icons.search, size: 18)),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = items[i];
                final id = widget.idOf(e);
                return ListTile(
                  dense: true,
                  title: Text(widget.label(e)),
                  trailing: id == widget.current
                      ? Icon(Icons.check, color: Colors.green.shade700)
                      : null,
                  onTap: () => Navigator.pop(context, id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
