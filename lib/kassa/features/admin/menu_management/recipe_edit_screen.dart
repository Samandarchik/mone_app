import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/widgets/ingredient_picker.dart';

/// Mahsulot retsepti — partiya (batch) bo'yicha ingredientlar va tannarx.
/// `embedded: true` bo'lsa Scaffold'siz, mahsulot tahrirlash oynasining
/// ichiga bo'lim sifatida joylanadi (o'z "Retseptni saqlash" tugmasi bilan).
class RecipeEditScreen extends StatefulWidget {
  final int productId;
  final String productName;
  final bool embedded;

  const RecipeEditScreen({
    super.key,
    required this.productId,
    required this.productName,
    this.embedded = false,
  });

  @override
  State<RecipeEditScreen> createState() => RecipeEditScreenState();
}

/// Raqamli maydonlarga HARF YOZIB BO'LMAYDI.
///
/// NEGA: `keyboardType: TextInputType.number` iOS'da faqat raqamli
/// klaviaturani KO'RSATADI, kiritishni cheklamaydi — tashqi klaviatura yoki
/// nusxa-joylashtirish orqali maydonga "jkl" tushardi. Bunday matndan
/// `parseIntField` null qaytaradi va masalliq JIMGINA saqlanmay qolardi:
/// admin miqdorni yozdim deb o'ylab chiqib ketardi.
///
/// Bo'shliq va apostrof ATAYLAB ruxsat etilgan — summalar "150 000"
/// ko'rinishida yoziladi va `parseIntField` ularni tozalab o'qiydi.
final _kNumberOnly =
    FilteringTextInputFormatter.allow(RegExp(r"[0-9\s\u00A0']"));

class _RecipeItemRow {
  final int ingredientId;
  final String name;
  final String unit;

  /// Retsept QISMI ("Biskvit", "Krem"). Bo'sh — qismsiz retsept.
  /// Bitta masalliq bir necha qismda turishi mumkin (tuxum ikkalasiga ham
  /// kiradi), shuning uchun qatorlar `ingredientId` bo'yicha yagona EMAS —
  /// yagonaligi `part + ingredientId` juftligi bilan belgilanadi.
  String part;

  final TextEditingController amountC;
  final FocusNode focus = FocusNode();

  _RecipeItemRow({
    required this.ingredientId,
    required this.name,
    required this.unit,
    this.part = '',
    int? amount,
  }) : amountC = TextEditingController(
            text: amount != null && amount > 0 ? '$amount' : '');

  void dispose() {
    amountC.dispose();
    focus.dispose();
  }
}

/// Yangi qism uchun tez tanlash — desertlarda eng ko'p uchraydiganlari.
const _kPartSuggestions = <String>[
  'Biskvit',
  'Krem',
  'Sirop',
  'Glazur',
  'Bezak',
  'To\'ldirma',
];

class RecipeEditScreenState extends State<RecipeEditScreen> {
  final TextEditingController _batchC = TextEditingController();
  final TextEditingController _limitC = TextEditingController();
  final List<_RecipeItemRow> _items = [];

  /// Qism nomlari — ko'rsatish TARTIBI shu ro'yxatda saqlanadi (item'lardan
  /// tiklab bo'lmaydi: hozircha bo'sh, ingredientsiz qism ham turishi mumkin).
  /// Ro'yxat bo'sh = qismsiz retsept, ekran ilgarigidek bitta ro'yxat.
  final List<String> _parts = [];

  List<dynamic> _ingredients = [];
  Map<String, dynamic>? _cost;
  bool _exists = false;
  bool _loading = true;
  bool _saving = false;
  /// Yuklash yiqildi — saqlashga ruxsat berilmaydi (retseptni yo'q qilib
  /// qo'ymaslik uchun).
  bool _loadFailed = false;

  // ===== AVTOMATIK SAQLASH =====
  //
  // "Saqlash" tugmasini bosish ESDAN CHIQARDI: admin masalliqlarni kiritib,
  // ortga bosib chiqib ketardi va hammasi yo'qolardi. Endi har o'zgarish
  // (ingredient qo'shildi/o'chirildi, miqdor yozildi, partiya/limit
  // o'zgardi) qisqa kutishdan keyin o'zi serverga yuboriladi.
  Timer? _autoTimer;
  bool _autoSaving = false;
  /// Saqlash ketayotganda yana o'zgarish bo'ldi — tugagach qayta yuboriladi.
  bool _autoQueued = false;
  /// Oxirgi MUVAFFAQIYATLI saqlangan holat — bir xil ma'lumot qayta-qayta
  /// yuborilmasligi uchun.
  String? _savedSig;
  int? _savedLimit;
  String? _autoNote;
  bool _autoNoteIsError = false;
  /// Oxirgi saqlashda server javobi mos kelmasa — SABABI (eski server?).
  String? _mismatchNote;
  bool _disposed = false;
  /// Mahsulotning o'zi o'chirilyapti — avtomatik saqlash butunlay to'xtaydi
  /// (o'chirilgan mahsulotga retsept qaytib yozilmasin).
  bool _abandoned = false;

  static const _autoDelay = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    // OYNADAN CHIQAYOTGANDA OXIRGI HOLAT YUBORILADI.
    //
    // Kutish taymeri hali ishlamagan bo'lishi mumkin (admin yozib bo'lib
    // darrov ortga bosdi) — shuning uchun qiymatlar shu yerda o'qib olinadi
    // va so'rov widget'dan mustaqil ravishda ketadi (ApiService — singleton,
    // ekran yopilsa ham so'rov tugaydi).
    _fireAndForgetSave();
    _disposed = true;
    _batchC.dispose();
    _limitC.dispose();
    for (final r in _items) {
      r.dispose();
    }
    super.dispose();
  }

  /// Ekrandagi holatni serverga yuboriladigan ko'rinishga o'giradi.
  /// Miqdori kiritilmagan qatorlar TASHLAB KETILADI (server amount > 0
  /// talab qiladi) — ular `missing` da qaytadi va ekranda ogohlantiriladi.
  ({int batch, List<Map<String, dynamic>> items, List<String> missing})
      _collect() {
    final batchQty = parseIntField(_batchC.text) ?? 0;
    final items = <Map<String, dynamic>>[];
    final missing = <String>[];
    for (final r in _items) {
      final amount = parseIntField(r.amountC.text) ?? 0;
      if (amount > 0) {
        items.add({
          'ingredient_id': r.ingredientId,
          'amount': amount,
          'part': r.part,
        });
      } else {
        missing.add(r.part.isEmpty ? r.name : '${r.part} — ${r.name}');
      }
    }
    return (
      batch: batchQty > 0 ? batchQty : 1,
      items: items,
      missing: missing
    );
  }

  /// Miqdor maydonidan chiqilganda (boshqa qatorga o'tdi, "Qo'shish" bosdi,
  /// klaviaturani yopdi) darhol saqlaymiz — kutib o'tirmaymiz.
  void _attachAutoSave(_RecipeItemRow r) {
    r.focus.addListener(() {
      if (!r.focus.hasFocus && !_disposed) flushPendingSave();
    });
  }

  /// Saqlangan holat imzosi. QISM ham kiradi: masalliqni bir qismdan
  /// boshqasiga ko'chirish miqdorlarni o'zgartirmaydi, imzo qismsiz bo'lsa
  /// avtosaqlash bu o'zgarishni "hech narsa o'zgarmadi" deb o'tkazib
  /// yuborardi.
  String _sigOf(int batch, List<Map<String, dynamic>> items) =>
      '$batch|${items.map((e) => '${e['part'] ?? ''}/${e['ingredient_id']}:${e['amount']}').join(',')}';

  /// Serverdan qaytgan retseptni SHU imzoga keltiradi — saqlangani
  /// haqiqatan mos kelganini tekshirish uchun.
  ///
  /// NEGA KERAK: ilgari faqat item SONI solishtirilardi. Eski server yangi
  /// ilovadan kelgan `part` maydonini tashlab yuboradi — soni o'sha-o'sha
  /// bo'lgani uchun ekran "saqlandi" derdi, qismlar esa yo'qolgan bo'lardi.
  String _sigOfServer(Map<String, dynamic> res) {
    final items = (res['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => {
              'part': (e['part'] ?? '').toString(),
              'ingredient_id': e['ingredient_id'],
              'amount': e['amount'],
            })
        .toList();
    return _sigOf(res['batch_qty'] as int? ?? 1, items);
  }

  /// Saqlash tasdiqlanmadi — SABABINI aytamiz.
  ///
  /// Eng ko'p uchraydigani: server ESKI va `part` maydonini bilmaydi.
  /// U retseptni saqlaydi, lekin qismlarsiz — 200 qaytaradi, qayta o'qiganda
  /// esa qismlar yo'q. "Topilmadi" deyish bunda chalg'itadi: aslida
  /// masalliqlar saqlangan, faqat qismlar tushib qolgan va qayta "Saqlash"
  /// bosish ham hech narsani o'zgartirmaydi — backend yangilanishi kerak.
  String _mismatchReason(
      Map<String, dynamic> check, int batch, List<Map<String, dynamic>> items) {
    if (check['exists'] != true) {
      return 'Server saqladi dedi, lekin qayta o\'qiganda topilmadi — '
          '"Saqlash"ni bosing';
    }
    final wantParts =
        items.any((e) => (e['part'] ?? '').toString().isNotEmpty);
    final gotParts = (check['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .any((e) => (e['part'] ?? '').toString().isNotEmpty);
    if (wantParts && !gotParts) {
      final flat = items
          .map((e) => {...e, 'part': ''})
          .toList();
      if (_sigOfServer(check) == _sigOf(batch, flat)) {
        return 'Server ESKI versiyada — retsept qismlarini (Biskvit, Krem) '
            'saqlay olmaydi. Masalliqlar saqlandi, QISMLAR yo\'qoldi. '
            'Backend yangilanmaguncha qismlarga bo\'lish ishlamaydi.';
      }
    }
    return 'Server saqladi dedi, lekin qayta o\'qiganda mos kelmadi — '
        '"Saqlash"ni bosing';
  }

  /// Har o'zgarishda chaqiriladi — taymerni qaytadan boshlaydi.
  void _scheduleAutoSave() {
    if (_loadFailed) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(_autoDelay, () => _autoSave());
  }

  /// Kutmasdan darhol saqlash (ingredient qo'shish/o'chirish, maydondan
  /// chiqish, oynani yopish).
  Future<void> flushPendingSave() async {
    _autoTimer?.cancel();
    await _autoSave();
  }

  /// Mahsulot o'chirilayotganda chaqiriladi — kutayotgan saqlash bekor
  /// bo'ladi va oyna yopilganda ham hech narsa yuborilmaydi.
  void cancelPendingSave() {
    _autoTimer?.cancel();
    _abandoned = true;
  }

  Future<void> _autoSave() async {
    if (_loadFailed || _disposed || _abandoned || !mounted) return;
    if (_saving) return; // qo'lda "Saqlash" ketyapti — aralashmaymiz
    if (_autoSaving) {
      _autoQueued = true;
      return;
    }
    final data = _collect();
    final sig = _sigOf(data.batch, data.items);
    final limit = parseIntField(_limitC.text);
    final limitChanged = limit != null && limit >= 0 && limit != _savedLimit;
    final recipeChanged = data.items.isNotEmpty && sig != _savedSig;
    if (!recipeChanged && !limitChanged) {
      // O'zgarish yo'q — faqat to'ldirilmagan qator haqida eslatib qo'yamiz.
      String? note;
      if (data.items.isEmpty && _savedSig != null) {
        // Hamma qator o'chirildi. Server bo'sh retseptni qabul qilmaydi va
        // biz uni o'zboshimchalik bilan O'CHIRMAYMIZ — noto'g'ri bosilgan
        // "x" butun retseptni yo'q qilib yuborishi mumkin edi.
        note = 'Ingredient qolmadi — serverdagi retsept o\'zgarmadi. '
            'O\'chirish uchun "Retseptni o\'chirish"ni bosing.';
      } else if (data.missing.isNotEmpty) {
        note = '${data.missing.first}: miqdor kiritilmagan — '
            'bu masalliq saqlanmadi';
      }
      if (mounted && note != null) {
        setState(() {
          _autoNote = note;
          _autoNoteIsError = true;
        });
      }
      return;
    }

    setState(() {
      _autoSaving = true;
      _autoNote = null;
      _autoNoteIsError = false;
    });
    try {
      bool verified = true;
      if (recipeChanged) {
        await ApiService().saveRecipe(widget.productId, data.batch, data.items);
        // Qo'lda saqlashdagidek TEKSHIRAMIZ: ilova local va online server
        // orasida almashadi, yozuv bir joyga tushib o'qish ikkinchisidan
        // bo'lishi mumkin. "Saqlandi" deb aldamaymiz.
        final check = await ApiService().getRecipe(widget.productId);
        verified = check['exists'] == true && _sigOfServer(check) == sig;
        _mismatchNote =
            verified ? null : _mismatchReason(check, data.batch, data.items);
        if (verified) _savedSig = sig;
      }
      if (limitChanged) {
        await ApiService().setStockLimit(widget.productId, limit);
        _savedLimit = limit;
      }
      if (!mounted) return;
      setState(() {
        _autoSaving = false;
        if (recipeChanged && verified) _exists = true;
        if (!verified) {
          _autoNote = _mismatchNote ??
              'Server saqladi dedi, lekin qayta o\'qiganda topilmadi '
                  '— "Saqlash"ni bosing';
          _autoNoteIsError = true;
        } else {
          _autoNote = data.missing.isEmpty
              ? 'Avtomatik saqlandi'
              : '${data.missing.first}: miqdor kiritilmagan — '
                  'qolganlari saqlandi';
          _autoNoteIsError = data.missing.isNotEmpty;
        }
      });
      if (recipeChanged && verified) _loadCost();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autoSaving = false;
        _autoNote = _errMsg(e, 'Avtomatik saqlanmadi — "Saqlash"ni bosing');
        _autoNoteIsError = true;
      });
    }
    if (_autoQueued) {
      _autoQueued = false;
      if (mounted) _autoSave();
    }
  }

  /// Ekran yopilayotganda — javobini kutmasdan yuborish.
  void _fireAndForgetSave() {
    if (_loadFailed || _saving || _abandoned) return;
    final data = _collect();
    if (data.items.isEmpty) return;
    final sig = _sigOf(data.batch, data.items);
    final limit = parseIntField(_limitC.text);
    final productId = widget.productId;
    if (sig != _savedSig) {
      ApiService()
          .saveRecipe(productId, data.batch, data.items)
          .catchError((_) => <String, dynamic>{});
    }
    if (limit != null && limit >= 0 && limit != _savedLimit) {
      ApiService().setStockLimit(productId, limit).catchError((_) {});
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService().getRecipe(widget.productId),
        ApiService().getIngredients(),
        ApiService().getStocks(force: true),
      ]);
      final recipe = results[0] as Map<String, dynamic>;
      final ingredients =
          (results[1] as Map<String, dynamic>)['ingredients']
                  as List<dynamic>? ??
              [];
      final stocks = results[2] as List<dynamic>;

      final exists = recipe['exists'] == true;
      final items = recipe['items'] as List<dynamic>? ?? [];

      int? limitQty;
      for (final s in stocks) {
        if (s is Map && s['product_id'] == widget.productId) {
          limitQty = s['limit_qty'] as int?;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _ingredients = ingredients;
          _exists = exists;
          // 1 — standart qiymat (bittalab tayyorlanadi), maydon bo'sh
          // qoladi: admin uni majburiy to'ldiriladigan narsa deb o'ylamasin.
          final savedBatch = exists ? (recipe['batch_qty'] as int? ?? 1) : 0;
          _batchC.text = savedBatch > 1 ? '$savedBatch' : '';
          if (limitQty != null && limitQty > 0) {
            _limitC.text = '$limitQty';
          }
          for (final it in items) {
            final part = (it['part'] ?? '').toString().trim();
            final row = _RecipeItemRow(
              ingredientId: it['ingredient_id'] as int,
              name: (it['name'] ?? '').toString(),
              unit: (it['unit'] ?? '').toString(),
              part: part,
              amount: it['amount'] as int?,
            );
            _attachAutoSave(row);
            _items.add(row);
            // Qism tartibi — retseptda birinchi uchragan tartibda
            if (part.isNotEmpty && !_parts.contains(part)) _parts.add(part);
          }
          _loading = false;
          // Yuklangan holat "saqlangan" deb belgilanadi: hech narsa
          // o'zgarmasa serverga bekorga so'rov ketmaydi.
          _savedLimit = limitQty;
          final loaded = _collect();
          if (exists && loaded.items.isNotEmpty) {
            _savedSig = _sigOf(loaded.batch, loaded.items);
          }
        });
      }
      if (exists) _loadCost();
    } catch (_) {
      // XATO JIMGINA YUTILMAYDI.
      //
      // Ilgari yuklash yiqilsa ekran BO'SH retsept formasi bo'lib ochilardi
      // (`_exists = false`, `_items = []`) va hech qanday xabar yo'q edi.
      // Admin "retsept kiritilmagan ekan" deb o'ylab, bitta masalliq yozib
      // saqlasa — server PUT ni TO'LIQ ALMASHTIRISH sifatida bajaradi va
      // 12 ta masalliqli retsept 1 tagacha qisqarardi. Keyin har "Tayyor"
      // da faqat o'sha bitta masalliq omborlardan chiqardi, tannarx esa
      // sun'iy ravishda pasayib, marja soxta ko'rinardi.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _loadCost() async {
    try {
      final res = await ApiService().getRecipeCostPinned(widget.productId);
      if (mounted) setState(() => _cost = res);
    } catch (_) {}
  }

  void _toast(String msg, {Color color = AppColors.success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  String _errMsg(Object e, String fallback) {
    if (e is DioException && e.response?.data is Map) {
      final m = (e.response!.data as Map);
      final msg = m['message'] ?? m['error'];
      if (msg != null) return msg.toString();
    }
    return fallback;
  }

  /// Retseptda qism bormi — ekran guruhlangan ko'rinishga o'tadimi.
  bool get _grouped => _parts.isNotEmpty;

  /// Shu qismdagi qatorlar (retseptdagi tartibda).
  List<_RecipeItemRow> _rowsOf(String part) =>
      _items.where((r) => r.part == part).toList();

  /// Qism nomini so'rash — tayyor takliflar + qo'lda yozish.
  Future<String?> _askPartName({String initial = '', required String title}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Qism nomi',
                  hintText: 'Masalan: Biskvit',
                  counterText: '',
                ),
                onChanged: (_) => setD(() {}),
                onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final sug in _kPartSuggestions)
                    if (!_parts.contains(sug))
                      ActionChip(
                        label: Text(sug, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          c.text = sug;
                          setD(() {});
                        },
                      ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Bekor')),
            FilledButton(
              onPressed: c.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dctx, c.text.trim()),
              child: const Text('Saqlash'),
            ),
          ],
        ),
      ),
    );
  }

  /// Yangi qism — nomi so'raladi, so'ng darhol ingredient tanlash ochiladi
  /// (bo'sh qism serverga saqlanmaydi, faqat ekranda turadi).
  Future<void> _addPart() async {
    unawaited(flushPendingSave());
    final name = await _askPartName(title: 'Yangi qism');
    if (name == null || name.isEmpty || !mounted) return;
    if (_parts.any((p) => p.toLowerCase() == name.toLowerCase())) {
      _toast('"$name" qismi allaqachon bor', color: AppColors.danger);
      return;
    }
    setState(() => _parts.add(name));
    await _addIngredient(part: name);
  }

  Future<void> _renamePart(String part) async {
    unawaited(flushPendingSave());
    final name = await _askPartName(initial: part, title: 'Qism nomi');
    if (name == null || name.isEmpty || name == part || !mounted) return;
    if (_parts.any((p) => p != part && p.toLowerCase() == name.toLowerCase())) {
      _toast('"$name" qismi allaqachon bor', color: AppColors.danger);
      return;
    }
    setState(() {
      final i = _parts.indexOf(part);
      if (i >= 0) _parts[i] = name;
      for (final r in _items) {
        if (r.part == part) r.part = name;
      }
    });
    _scheduleAutoSave();
  }

  /// Qismni o'chirish — ICHIDAGI MASALLIQLAR BILAN. Tasodifan bosilsa butun
  /// blok yo'qolgani uchun tasdiq so'raladi.
  Future<void> _deletePart(String part) async {
    final rows = _rowsOf(part);
    if (rows.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('"$part" qismi o\'chirilsinmi?'),
          content: Text('${rows.length} ta masalliq ham o\'chadi: '
              '${rows.map((r) => r.name).join(', ')}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Yo\'q')),
            FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('O\'chirish'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _parts.remove(part);
      for (final r in rows) {
        _items.remove(r);
        r.dispose();
      }
    });
    _scheduleAutoSave();
  }

  /// Masalliqni boshqa qismga ko'chirish (tuxumni "Biskvit"dan "Krem"ga).
  Future<void> _moveToPart(_RecipeItemRow row) async {
    final targets = [..._parts.where((p) => p != row.part)];
    if (row.part.isNotEmpty && _items.any((r) => r.part.isEmpty)) {
      targets.add(''); // qismsiz qatorlar bo'lsa — ularning oldiga qaytarish
    }
    if (targets.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (bctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('"${row.name}" ni qaysi qismga?',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            for (final t in targets)
              ListTile(
                onTap: () => Navigator.pop(bctx, t),
                leading: const Icon(Icons.subdirectory_arrow_right_rounded,
                    color: AppColors.textMuted),
                title: Text(t.isEmpty ? 'Qismsiz' : t,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // Bir qism ichida bitta masalliq IKKI MARTA turolmaydi — server ham shuni
    // rad etadi. Ko'chirishdan oldin aytamiz.
    if (_items.any((r) =>
        r != row && r.part == picked && r.ingredientId == row.ingredientId)) {
      _toast(
          '${row.name} "${picked.isEmpty ? 'Qismsiz' : picked}" da allaqachon bor',
          color: AppColors.danger);
      return;
    }
    setState(() => row.part = picked);
    _scheduleAutoSave();
  }

  Future<void> _addIngredient({String part = ''}) async {
    // "QO'SHISH" BOSILISHI = OLDINGILARINI SAQLASH.
    //
    // Admin miqdorni yozib, darrov yana "Qo'shish" bosadi — o'sha payt
    // yozilgani serverga ketadi, "Saqlash"ni kutmaydi.
    unawaited(flushPendingSave());
    // Band deb hisoblanadigan masalliqlar — FAQAT SHU QISMDAGILAR. Tuxum
    // "Biskvit"da bo'lsa ham "Krem" ro'yxatida ko'rinaverishi kerak.
    final used =
        _items.where((r) => r.part == part).map((r) => r.ingredientId).toSet();
    final available =
        _ingredients.where((i) => !used.contains(i['id'] as int)).toList();
    final picked =
        await showIngredientPicker(context, ingredients: available);
    if (picked != null) {
      final row = _RecipeItemRow(
        ingredientId: picked['id'] as int,
        name: (picked['name'] ?? '').toString(),
        unit: (picked['unit'] ?? '').toString(),
        part: part,
      );
      _attachAutoSave(row);
      setState(() {
        // Picker ichida yangi yaratilgan bo'lsa umumiy ro'yxatga ham qo'shamiz
        if (!_ingredients.any((i) => i['id'] == picked['id'])) {
          _ingredients.add(picked);
        }
        _items.add(row);
      });
      // Miqdor maydoni darhol ochiladi — tanlab bo'lib raqamni yozaveradi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) row.focus.requestFocus();
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    // Qo'lda saqlash — kutib turgan avtomatik saqlash bekor qilinadi
    // (ikkalasi bir vaqtda ketmasin).
    _autoTimer?.cancel();
    // Yuklash yiqilgan bo'lsa saqlashga RUXSAT YO'Q: ekrandagi bo'sh forma
    // haqiqiy retsept emas, uni saqlash mavjud retseptni butunlay
    // almashtirib yuborardi.
    if (_loadFailed) {
      _toast('Retsept yuklanmagan — avval qayta yuklang',
          color: AppColors.danger);
      return;
    }
    // PARTIYA MAJBURIY EMAS.
    //
    // Kofe/choy kabi mahsulot buyurtma kelganda bittalab tayyorlanadi —
    // "bir pishirishda nechta chiqadi" savoli ularga tegishli emas.
    // Bo'sh qoldirilsa 1 deb olamiz: ingredient miqdorlari 1 dona uchun.
    final batchQty = parseIntField(_batchC.text) ?? 0;
    final effectiveBatch = batchQty > 0 ? batchQty : 1;
    if (_items.isEmpty) {
      _toast('Kamida bitta ingredient qo\'shing', color: AppColors.danger);
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final r in _items) {
      final amount = parseIntField(r.amountC.text) ?? 0;
      if (amount <= 0) {
        _toast(
            r.part.isEmpty
                ? '${r.name}: miqdor kiritilmagan'
                : '${r.part} — ${r.name}: miqdor kiritilmagan',
            color: AppColors.danger);
        return;
      }
      items.add({
        'ingredient_id': r.ingredientId,
        'amount': amount,
        'part': r.part,
      });
    }

    setState(() => _saving = true);
    try {
      await ApiService().saveRecipe(widget.productId, effectiveBatch, items);

      // SAQLANGANINI TEKSHIRAMIZ.
      //
      // Ilgari "Retsept saqlandi" xabari faqat HTTP javobiga qarab
      // chiqarilardi. Ilova esa local va online serverlar orasida
      // avtomatik almashardi: yozuv bir serverga tushib, ekran ikkinchisidan
      // o'qishi mumkin edi — foydalanuvchi "saqlandi dedi, lekin
      // saqlanmagan" holatini ko'rardi. Endi darhol qayta o'qib
      // solishtiramiz va mos kelmasa ROSTINI aytamiz.
      final check = await ApiService().getRecipe(widget.productId);
      final wantSig = _sigOf(effectiveBatch, items);
      final verified =
          check['exists'] == true && _sigOfServer(check) == wantSig;
      _mismatchNote = verified
          ? null
          : _mismatchReason(check, effectiveBatch, items);

      final limit = parseIntField(_limitC.text);
      if (limit != null && limit >= 0) {
        await ApiService().setStockLimit(widget.productId, limit);
        _savedLimit = limit;
      }
      if (verified) _savedSig = wantSig;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _exists = verified;
        _autoNote = null;
      });
      if (!verified) {
        setState(() {
          _autoNote = _mismatchNote;
          _autoNoteIsError = true;
        });
        _toast(_mismatchNote ?? 'Saqlash tasdiqlanmadi',
            color: AppColors.danger);
        return;
      }
      // Bulutga yozildi va restoran ichida local server ham bor —
      // bu ma'lumot POS'ga faqat sync ishlaganda yetib boradi.
      _toast(ApiService().recipesGoOnline
          ? 'Retsept ONLINE serverga saqlandi'
          : 'Retsept saqlandi');
      _loadCost();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _toast(_errMsg(e, 'Saqlab bo\'lmadi'), color: AppColors.danger);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retseptni o\'chirish'),
        content: Text(
            '"${widget.productName}" retsepti o\'chirilsinmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Yo\'q')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService().deleteRecipe(widget.productId);
      // O'CHIRGANDAN KEYIN AVTOMATIK SAQLASH UNI TIKLAMASLIGI KERAK:
      // ekrandagi qatorlar ham tozalanadi, shunda yopilishda yuboradigan
      // narsa qolmaydi.
      _autoTimer?.cancel();
      if (!mounted) return;
      setState(() {
        for (final r in _items) {
          r.dispose();
        }
        _items.clear();
        _savedSig = null;
        _exists = false;
        _cost = null;
        _autoNote = 'Retsept o\'chirildi';
        _autoNoteIsError = false;
      });
      if (!widget.embedded) Navigator.pop(context);
    } catch (e) {
      _toast(_errMsg(e, 'O\'chirib bo\'lmadi'), color: AppColors.danger);
    }
  }

  // Ichki (embedded) rejim — mahsulot oynasi ichidagi bo'lim
  Widget _buildEmbedded() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Yuklash yiqilgan bo'lsa BO'SH forma ko'rsatilmaydi — admin uni
    // "retsept yo'q" deb tushunib, saqlash bilan mavjudini o'chirib
    // yuborishi mumkin edi.
    if (_loadFailed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.danger, size: 32),
            const SizedBox(height: 8),
            const Text(
              'Retsept yuklanmadi.\nSaqlash bloklandi — mavjud retsept '
              'tasodifan o\'chib ketmasligi uchun.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loadFailed = false;
                  _loading = true;
                });
                _load();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Qayta yuklash'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._formCards(),
        const SizedBox(height: 8),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.restaurant_menu_rounded, size: 18),
            label: Text(_saving ? 'Saqlanmoqda...' : 'Retseptni saqlash'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
        if (_exists)
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 16, color: AppColors.danger),
            label: const Text('Retseptni o\'chirish',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbedded();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        toolbarHeight: 64,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_rounded, size: 22),
            ),
          ),
        ),
        title: Text(
          'Retsept — ${widget.productName}',
          style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.text),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_exists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Material(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: _delete,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger, size: 22),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      // SAQLASH TUGMASI BODY ICHIDA (bottomNavigationBar'da EMAS).
      //
      // NEGA: raqamli klaviatura ochilganda tugma uning ostida qolib ketardi
      // va admin retseptni saqlay olmasdi — "kiritdim, lekin saqlanmagan"
      // holati aynan shundan chiqqan. Body esa klaviatura balandligicha
      // qisqaradi, ya'ni ustundagi tugma DOIM klaviatura ustida turadi.
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    // Bo'sh joyga bosish klaviaturani yopadi.
                    behavior: HitTestBehavior.translucent,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: ListView(
                      // Ro'yxatni surish ham yopadi (iOS'da odatiy xatti-harakat).
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      children: _formCards(),
                    ),
                  ),
                ),
                _buildSaveBar(),
              ],
            ),
    );
  }

  // Retsept formasining kartalari — to'liq sahifa va embedded rejim uchun umumiy
  //
  // Telefonda bu kartalar mahsulot oynasining kartasi ICHIDA turadi —
  // shuning uchun chekkalar ixcham, aks holda ikki qavat chekka qo'shilib
  // ekranning yarmi bo'sh joyga ketardi.
  static const _cardPad = EdgeInsets.fromLTRB(12, 10, 12, 10);
  static const _densePad = EdgeInsets.symmetric(horizontal: 12, vertical: 11);

  List<Widget> _formCards() {
    return [
                // Partiya
                KSection(
                  title: 'Partiya (ixtiyoriy)',
                  icon: Icons.bakery_dining_rounded,
                  iconColor: AppColors.warning,
                  padding: _cardPad,
                  children: [
                    const SizedBox(height: 6),
                    TextField(
                      controller: _batchC,
                      // Embedded rejimda bu forma mahsulot oynasining ichida —
                      // u yerda fokusni tortib olmasligi kerak.
                      decoration: const InputDecoration(
                        labelText: 'Bir pishirishda nechta chiqadi?',
                        hintText: 'Bo\'sh qoldiring — 1 ta',
                        suffixText: 'ta',
                        contentPadding: _densePad,
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [_kNumberOnly],
                      onChanged: (_) {
                        setState(() {});
                        _scheduleAutoSave();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        (parseIntField(_batchC.text) ?? 0) > 1
                            ? 'Quyidagi ingredient miqdorlari BUTUN partiya uchun'
                            : 'Bo\'sh qoldirilsa 1 ta deb olinadi (kofe, choy — '
                                'buyurtma kelganda bittalab tayyorlanadi). '
                                'Quyidagi miqdorlar 1 dona uchun.',
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Ingredientlar (qismsiz) yoki qismlarga bo'lingan retsept
                KSection(
                  title: _grouped ? 'Retsept qismlari' : 'Ingredientlar',
                  icon: Icons.egg_alt_outlined,
                  iconColor: AppColors.success,
                  padding: _cardPad,
                  trailing: _grouped
                      ? null
                      : TextButton.icon(
                          onPressed: () => _addIngredient(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Qo\'shish',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                  children: [
                    ..._ingredientsBody(),
                    _autoStatusRow(),
                  ],
                ),
                const SizedBox(height: 8),

                // Limit
                KSection(
                  title: 'Limit (ixtiyoriy)',
                  icon: Icons.inventory_2_rounded,
                  iconColor: AppColors.info,
                  padding: _cardPad,
                  children: [
                    const SizedBox(height: 6),
                    TextField(
                      controller: _limitC,
                      decoration: const InputDecoration(
                        labelText: 'Qancha tayyor turishi kerak?',
                        hintText: 'Bo\'sh — oldindan tayyorlanmaydi',
                        suffixText: 'ta',
                        contentPadding: _densePad,
                        prefixIcon: Icon(Icons.flag_rounded),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [_kNumberOnly],
                      onChanged: (_) => _scheduleAutoSave(),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Qoldiq shu miqdordan kam bo\'lsa "Pishirish kerak" '
                        'ro\'yxatida chiqadi. Buyurtma kelganda o\'sha zahoti '
                        'tayyorlanadigan mahsulotga (kofe) limit shart emas — '
                        'bo\'sh qoldiring, ro\'yxatda chiqmaydi.',
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),

                // Tannarx
                if (_cost != null) ...[
                  const SizedBox(height: 8),
                  _buildCostSection(),
                ],
                const SizedBox(height: 4),
    ];
  }

  /// Avtomatik saqlash holati — admin "saqlandimi?" deb o'ylab qolmasligi
  /// uchun ingredientlar ostida ko'rinib turadi.
  Widget _autoStatusRow() {
    if (!_autoSaving && _autoNote == null) return const SizedBox.shrink();
    final color = _autoSaving
        ? AppColors.textMuted
        : (_autoNoteIsError ? AppColors.warning : AppColors.success);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_autoSaving)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textMuted),
            )
          else
            Icon(
              _autoNoteIsError
                  ? Icons.warning_amber_rounded
                  : Icons.cloud_done_rounded,
              size: 14,
              color: color,
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _autoSaving ? 'Saqlanmoqda...' : (_autoNote ?? ''),
              style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    // Raqamli klaviaturada iOS "Return"/"Tayyor" tugmasini KO'RSATMAYDI —
    // klaviatura ochiq qolib, uni yopishning yo'li yo'q edi. Ochiq bo'lsa
    // yonida yopish tugmasi chiqadi (bo'sh joyga bosish va ro'yxatni surish
    // ham yopadi).
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (keyboardOpen) ...[
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => FocusScope.of(context).unfocus(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                child: const Icon(Icons.keyboard_hide_rounded, size: 22),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 20),
                label: Text(
                  _saving ? 'Saqlanmoqda...' : 'Saqlash',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ingredientlar bo'limining ichi.
  ///
  /// Qism yo'q bo'lsa — ILGARIGIDEK bitta tekis ro'yxat (eski retseptlar
  /// ko'rinishi o'zgarmaydi), pastida "Qismga bo'lish" tugmasi. Qism paydo
  /// bo'lsa har biri alohida blok bo'lib chiqadi va bitta masalliq
  /// (tuxum) bir necha blokda turaveradi.
  List<Widget> _ingredientsBody() {
    if (!_grouped) {
      return [
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Ingredient qo\'shilmagan',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          )
        else
          ..._items.map(_itemRow),
        _addPartButton(
          label: 'Qismga bo\'lish (Biskvit, Krem...)',
          hint: 'Desert bir necha qismdan yig\'ilsa — har qismning masalliqlari '
              'alohida yoziladi. Bitta masalliq (tuxum) bir necha qismga '
              'kirishi mumkin.',
        ),
      ];
    }

    // Qismga tegishli bo'lmagan qatorlar (retsept qismlarga keyin bo'lingan)
    final loose = _rowsOf('');
    return [
      if (loose.isNotEmpty) _partBlock('', loose),
      for (final part in _parts) _partBlock(part, _rowsOf(part)),
      _addPartButton(label: 'Yana qism qo\'shish'),
    ];
  }

  Widget _addPartButton({required String label, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(hint,
                  style: const TextStyle(
                      fontSize: 11, height: 1.35, color: AppColors.textMuted)),
            ),
          OutlinedButton.icon(
            onPressed: _addPart,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bitta qism bloki: sarlavha + masalliqlar + "Ingredient qo'shish".
  /// `part` bo'sh bo'lsa — qismga taqsimlanmagan qatorlar ("Qismsiz").
  Widget _partBlock(String part, List<_RecipeItemRow> rows) {
    final isLoose = part.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: isLoose ? AppColors.surfaceAlt : AppColors.successTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: isLoose ? AppColors.border : AppColors.successSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isLoose
                    ? Icons.horizontal_rule_rounded
                    : Icons.layers_rounded,
                size: 16,
                color: isLoose ? AppColors.textFaint : AppColors.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isLoose ? 'Qismsiz' : part,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isLoose ? AppColors.textMuted : AppColors.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isLoose)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 18, color: AppColors.textMuted),
                  onSelected: (v) {
                    if (v == 'rename') _renamePart(part);
                    if (v == 'delete') _deletePart(part);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'rename', child: Text('Nomini o\'zgartirish')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Qismni o\'chirish',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
            ],
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Masalliq qo\'shilmagan',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            )
          else
            ...rows.map(_itemRow),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addIngredient(part: part),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ingredient',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(_RecipeItemRow r) {
    final amount = parseIntField(r.amountC.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              r.name,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextField(
              controller: r.amountC,
              focusNode: r.focus,
              decoration: InputDecoration(
                labelText: 'Miqdor',
                suffixText: r.unit,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                helperText: (r.unit == 'gr' || r.unit == 'ml') &&
                        amount >= 1000
                    ? formatQty(amount, r.unit)
                    : null,
                helperStyle: const TextStyle(
                    fontSize: 10, color: AppColors.textFaint),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [_kNumberOnly],
              onChanged: (_) {
                setState(() {});
                _scheduleAutoSave();
              },
            ),
          ),
          // Qismlar bo'lsa — masalliqni boshqa qismga ko'chirish
          // (tuxumni "Biskvit"dan "Krem"ga olib o'tish).
          if (_grouped && _parts.length + (r.part.isEmpty ? 0 : 1) > 1)
            InkWell(
              onTap: () => _moveToPart(r),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.swap_vert_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ),
          InkWell(
            onTap: () {
              setState(() => _items.remove(r));
              r.dispose();
              _scheduleAutoSave();
            },
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostSection() {
    final c = _cost!;
    final incomplete = c['incomplete'] == true;
    final items = c['items'] as List<dynamic>? ?? [];
    final parts = c['parts'] as List<dynamic>? ?? [];
    return KSection(
      title: 'Tannarx',
      icon: Icons.calculate_rounded,
      iconColor: AppColors.primary,
      padding: _cardPad,
      children: [
        if (incomplete)
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ba\'zi ingredient narxi yo\'q (xarid kiritilmagan) — tannarx to\'liq emas',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        // Partiya 1 ta bo'lsa bu qator "1 dona tannarxi" bilan bir xil —
        // takror ko'rsatilmaydi.
        if ((c['batch_qty'] as int? ?? 0) > 1)
          KKeyValueRow(
            label: 'Partiya (${c['batch_qty']} ta)',
            value: formatMoney(c['batch_cost'], suffix: ' so\'m'),
          ),
        KKeyValueRow(
          label: '1 dona tannarxi',
          value: formatMoney(c['piece_cost'], suffix: ' so\'m'),
          bold: true,
          valueColor: AppColors.primary,
        ),
        const SizedBox(height: 4),
        // Retsept qismlarga bo'lingan bo'lsa har qismning jami alohida
        // ko'rsatiladi — "krem qimmatga tushyapti"ni shundan ko'rish mumkin.
        if (parts.isEmpty)
          for (final it in items) _costItemRow(it)
        else
          for (final p in parts) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (p['part'] ?? '').toString().isEmpty
                          ? 'Qismsiz'
                          : '${p['part']}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success),
                    ),
                  ),
                  Text(
                    formatMoney(p['cost'], suffix: ' so\'m'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success),
                  ),
                ],
              ),
            ),
            for (final it in items
                .where((e) => (e['part'] ?? '') == (p['part'] ?? '')))
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _costItemRow(it),
              ),
          ],
      ],
    );
  }

  Widget _costItemRow(dynamic it) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (it['has_price'] == false)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.warning_amber_rounded,
                  size: 14, color: AppColors.warning),
            ),
          Expanded(
            child: Text(
              '${it['name']} — ${formatQty(it['gross_amount'], (it['unit'] ?? '').toString())} (chiqit bilan)',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Text(
            formatMoney(it['cost'], suffix: ' so\'m'),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
