import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/widgets/ingredient_picker.dart';
import '../widgets/admin_page.dart';

/// Bozor — "olish kerak" ro'yxati, xarid kiritish va kunlik tarix
class BozorScreen extends StatefulWidget {
  const BozorScreen({super.key});
  @override
  State<BozorScreen> createState() => _BozorScreenState();
}

class _DraftLine {
  final int ingredientId;
  final String name;
  final String unit;
  final TextEditingController qtyC;
  final TextEditingController sumC;

  _DraftLine({
    required this.ingredientId,
    required this.name,
    required this.unit,
    int? initialQty,
  }) : qtyC = TextEditingController(
         text: initialQty != null && initialQty > 0 ? '$initialQty' : '',
       ),
       sumC = TextEditingController();

  void dispose() {
    qtyC.dispose();
    sumC.dispose();
  }
}

class _BozorScreenState extends State<BozorScreen> {
  /// 0 — bozorlik ro'yxati, 1 — xaridlar tarixi.
  int _tab = 0;
  List<dynamic> _needed = [];
  List<dynamic> _ingredients = [];
  List<dynamic> _purchases = [];
  final List<_DraftLine> _draft = [];
  final TextEditingController _noteC = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  StreamSubscription? _wssSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Real time: ombor o'zgarsa (pishirish, korreksiya, boshqa qurilmadagi
    // xarid) ro'yxat va tarix yangilanadi. Draft (yozilayotgan xarid) tegilmaydi.
    _wssSub = WssService().eventStream.listen((e) {
      if (e['event'] == 'ingredient:updated') {
        _loadNeeded();
        _loadPurchases();
      }
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    _noteC.dispose();
    for (final l in _draft) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        ApiService().getBozorList(),
        ApiService().getIngredients(),
        ApiService().getPurchases(limit: _kPurchaseLimit),
      ]);
      if (mounted) {
        setState(() {
          _needed = (results[0])['items'] as List<dynamic>? ?? [];
          _ingredients = (results[1])['ingredients'] as List<dynamic>? ?? [];
          _purchases = (results[2])['purchases'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      // Xato jimgina "bo'sh ro'yxat" bo'lib ko'rinmasin: xodim hammasi
      // joyida deb o'ylab qolardi. Endi aniq xabar chiqadi.
      if (mounted) {
        setState(() => _loading = false);
        _toast('Bozor malumotlari yuklanmadi - qayta urining', color: AppColors.danger);
      }
    }
  }

  Future<void> _loadNeeded() async {
    try {
      final res = await ApiService().getBozorList();
      if (mounted) {
        setState(() => _needed = res['items'] as List<dynamic>? ?? []);
      }
    } catch (_) {}
  }

  Future<void> _loadPurchases() async {
    try {
      final res = await ApiService().getPurchases(limit: _kPurchaseLimit);
      if (mounted) {
        setState(() => _purchases = res['purchases'] as List<dynamic>? ?? []);
      }
    } catch (_) {}
  }

  void _toast(String msg, {Color color = AppColors.success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  bool _inDraft(int ingredientId) =>
      _draft.any((l) => l.ingredientId == ingredientId);

  void _addToDraft(int id, String name, String unit, {int? qty}) {
    if (_inDraft(id)) return;
    setState(() {
      _draft.add(
        _DraftLine(ingredientId: id, name: name, unit: unit, initialQty: qty),
      );
    });
  }

  void _removeFromDraft(_DraftLine line) {
    setState(() => _draft.remove(line));
    line.dispose();
  }

  // Boshqa ingredient tanlash (qidiruvli)
  Future<void> _pickIngredient() async {
    final picked = await showIngredientPicker(
      context,
      ingredients:
          _ingredients.where((i) => !_inDraft(i['id'] as int)).toList(),
      showStock: true,
    );
    if (picked != null) {
      _addToDraft(
        picked['id'] as int,
        (picked['name'] ?? '').toString(),
        (picked['unit'] ?? '').toString(),
      );
    }
  }

  /// Miqdorni o'qish — FAQAT butun son.
  ///
  /// Ilgari raqam bo'lmagan hamma belgi tashlab yuborilardi va "1.5" → 15,
  /// "-500" → 500 bo'lib ketardi: operator 1,5 kg deb yozgan narsa omborga
  /// 15 birlik bo'lib kirardi va buni hech narsa bildirmasdi.
  static int? _parseQty(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\u00A0]'), '');
    if (cleaned.isEmpty) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(cleaned)) return null;
    return int.tryParse(cleaned);
  }

  Future<void> _submit() async {
    // Ikki marta bosishdan himoya SINXRON bo'lishi kerak: `_sending` faqat
    // tekshiruvlardan keyin qo'yilardi, tugma esa keyingi kadrda bloklanardi
    // — bitta bozor xaridi ikki marta yozilib, ombor ham, xarajat ham
    // ikki barobar bo'lib ketardi.
    if (_sending) return;
    _sending = true;

    final items = <Map<String, dynamic>>[];
    for (final l in _draft) {
      // MIQDOR va NARX turlicha o'qiladi.
      //
      // Narxda ajratgichlarni tashlash to'g'ri ("150 000" → 150000), lekin
      // MIQDORDA bu falokat edi: "1.5" → "15", "12.5" → "125", "-500" →
      // "500". Ya'ni 1.5 kg o'rniga 15 birlik omborga kirardi va buni hech
      // narsa bildirmasdi. Endi miqdor faqat butun son sifatida qabul
      // qilinadi, nuqta/vergul bo'lsa aniq xato beriladi.
      final qty = _parseQty(l.qtyC.text);
      final sum = int.tryParse(l.sumC.text.replaceAll(RegExp(r'[^0-9]'), ''));
      if (qty == null || qty <= 0) {
        _sending = false;
        _toast(
            '${l.name}: miqdor butun son bo\'lishi kerak (${l.unit})',
            color: AppColors.danger);
        return;
      }
      if (sum == null || sum <= 0) {
        _sending = false;
        _toast('${l.name}: narx kiritilmagan', color: AppColors.danger);
        return;
      }
      // Partiya kodi so'ralmaydi — kirim partiyalari kabi xarid o'z KUNI
      // bilan tanaladi (kod qo'lda yozilardi va deyarli doim bo'sh edi).
      items.add({
        'ingredient_id': l.ingredientId,
        'qty': qty,
        'subtotal': sum,
      });
    }
    if (items.isEmpty) {
      _sending = false;
      _toast('Xarid ro\'yxati bo\'sh', color: AppColors.danger);
      return;
    }
    if (mounted) setState(() {});
    try {
      final res = await ApiService().createPurchase(
        _noteC.text.trim(),
        items,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        for (final l in _draft) {
          l.dispose();
        }
        _draft.clear();
        _noteC.clear();
      });
      _toast(
        'Xarid saqlandi — jami ${formatMoney(res['total'], suffix: ' so\'m')}',
      );
      _loadNeeded();
      _loadPurchases();
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _toast(_errMsg(e, 'Saqlab bo\'lmadi'), color: AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _tab == 1 ? _groupByDay(_purchases) : const <_PurchaseDay>[];
    return AdminPage(
      subtitle: _tab == 0
          ? (_needed.isEmpty
              ? 'Kamomad yo‘q — hammasi yetarli'
              : '${_needed.length} ta mahsulot tugab qolgan')
          : (_purchases.isEmpty
              ? 'Xaridlar yo‘q'
              : '${days.length} kun · ${_purchases.length} ta xarid'),
      loading: _loading,
      onRefresh: _load,
      segments: const ['Bozorlik', 'Tarix'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() => _tab = i),
      primaryAction: _tab == 0
          ? AdminAction(
              label: 'Mahsulot qo‘shish',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: _pickIngredient,
              color: AppColors.success,
            )
          : null,
      padded: true,
      child: _tab == 0 ? _buildShoppingTab() : _buildHistoryTab(days),
    );
  }

  // ===== Bozorlik tab =====

  Widget _buildShoppingTab() {
    return ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 96),
        children: [
          // Xarid ro'yxati (draft)
          KSection(
            title: 'Xarid ro\'yxati',
            icon: Icons.shopping_basket_rounded,
            iconColor: AppColors.success,
            trailing: TextButton.icon(
              onPressed: _pickIngredient,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Qo\'shish',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            children: [
              if (_draft.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Quyidagi ro\'yxatdan tanlang yoki "Qo\'shish" bosing',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                )
              else ...[
                ..._draft.map(_draftTile),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteC,
                  decoration: const InputDecoration(
                    labelText: 'Izoh (ixtiyoriy)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      'Oldim',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Olish kerak
          KSection(
            title: 'Olish kerak',
            icon: Icons.notification_important_rounded,
            iconColor: AppColors.danger,
            children: [
              if (_needed.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Hammasi yetarli — kamomad yo\'q',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                )
              else
                ..._needed.map(_neededTile),
            ],
          ),
        ],
    );
  }

  Widget _neededTile(dynamic item) {
    final id = item['ingredient_id'] as int;
    final name = (item['name'] ?? '').toString();
    final unit = (item['unit'] ?? '').toString();
    final deficit = item['deficit'] is int ? item['deficit'] as int : 0;
    final added = _inDraft(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: added ? AppColors.successTint : AppColors.dangerTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: added ? null : () => _addToDraft(id, name, unit, qty: deficit),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  added
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 20,
                  color: added ? AppColors.success : AppColors.danger,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        'qoldiq: ${formatQty(item['count'], unit)} • '
                        'min: ${formatQty(item['min_qty'], unit)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '-${formatQty(deficit, unit)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _draftTile(_DraftLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _removeFromDraft(line),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: line.qtyC,
                  decoration: InputDecoration(
                    labelText: 'Miqdor',
                    suffixText: line.unit,
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: line.sumC,
                  decoration: const InputDecoration(
                    labelText: 'Narxi (jami)',
                    suffixText: 'so\'m',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                ),
              ),
            ],
          ),
          if ((line.unit == 'gr' || line.unit == 'ml') &&
              (int.tryParse(line.qtyC.text) ?? 0) >= 1000)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '= ${formatQty(int.tryParse(line.qtyC.text) ?? 0, line.unit)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textFaint,
                ),
              ),
            ),
          const Divider(height: 16, color: AppColors.borderSoft),
        ],
      ),
    );
  }

  // ===== Tarix tab — KUNLIK (kirim partiyalari kabi) =====
  //
  // Ilgari hamma xarid bitta uzun ro'yxatda akkordeon bo'lib turardi va
  // «shu kuni bozorga qancha ketdi» degan savolga javob yo'q edi. Endi
  // har kun yopiq karta: N ta mahsulot va kunlik jami; bosilsa o'sha
  // kunning xaridlari alohida sahifada ochiladi.

  Widget _buildHistoryTab(List<_PurchaseDay> days) {
    if (days.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'Xaridlar yo\'q',
        subtitle: 'Bozorlik qilinganda shu yerda ko\'rinadi',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 14, bottom: 96),
      itemCount: days.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _dayCard(days[i]),
    );
  }

  /// Kun sahifasi — o'sha kuni qilingan xaridlar alohida ekranda.
  /// Qaytganda ro'yxat yangilanadi (u yerda xarid o'chirilgan bo'lishi
  /// mumkin — ombor va kamomad ham o'zgaradi).
  Future<void> _openDay(_PurchaseDay day) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PurchaseDayScreen(
          dayKey: day.key,
          date: day.date,
          title: _dayTitle(day.date),
          initialItems: day.items,
        ),
      ),
    );
    if (!mounted) return;
    _loadNeeded();
    _loadPurchases();
  }

  Widget _dayCard(_PurchaseDay day) {
    final d = day.date;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => _openDay(day),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.successTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      d == null ? '—' : '${d.day}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.success,
                        height: 1.05,
                      ),
                    ),
                    if (d != null)
                      Text(
                        _kMonthsShort[d.month - 1],
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayTitle(d),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      [
                        if (d != null) _fmtDay(d),
                        '${day.items.length} ta xarid',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${day.productCount} ta mahsulot',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  if (day.total > 0)
                    Text(
                      formatMoney(day.total, suffix: ' so\'m'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Kunlik guruh va umumiy yordamchilar
// ============================================================

/// Bitta kunning xaridlari — kalit ('yyyy-mm-dd'), sana va o'sha kuni
/// qilingan xaridlar ro'yxati.
class _PurchaseDay {
  final String key;
  final DateTime? date;
  final List<Map<String, dynamic>> items = [];
  _PurchaseDay({required this.key, required this.date});

  int get total => items.fold<int>(0, (s, p) => s + _int(p['total']));

  /// Kun davomida olingan mahsulot qatorlari soni (bir xil mahsulot ikki
  /// xaridda bo'lsa ikki marta sanaladi — «necha qator kiritildi»).
  int get productCount => items.fold<int>(
      0, (s, p) => s + (p['items'] as List<dynamic>? ?? []).length);
}

/// Tarixda nechta xarid yozuvi olinadi. Kunlik ko'rinishda bitta kunda
/// bir nechta xarid bo'lishi mumkin, shuning uchun 50 ta kam edi.
const int _kPurchaseLimit = 300;

const _kWeekdays = [
  'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba',
  'Juma', 'Shanba', 'Yakshanba',
];
const _kMonthsShort = [
  'yan', 'fev', 'mar', 'apr', 'may', 'iyn',
  'iyl', 'avg', 'sen', 'okt', 'noy', 'dek',
];

int _int(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

String _two(int n) => n.toString().padLeft(2, '0');

/// Xaridning kuni — local vaqtda 'yyyy-mm-dd' kalit.
String _dayKeyOf(dynamic createdAt) {
  final d = DateTime.tryParse(createdAt?.toString() ?? '')?.toLocal();
  if (d == null) return '-';
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

String _dayTitle(DateTime? d) {
  if (d == null) return 'Sana yo\'q';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Bugun';
  if (diff == 1) return 'Kecha';
  return _kWeekdays[d.weekday - 1];
}

String _fmtDay(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String _fmtTime(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  return '${_two(d.hour)}:${_two(d.minute)}';
}

String _errMsg(Object e, String fallback) {
  if (e is DioException && e.response?.data is Map) {
    final m = (e.response!.data as Map);
    final msg = m['message'] ?? m['error'];
    if (msg != null) return msg.toString();
  }
  return fallback;
}

/// Xaridlarni sotib olingan kuni bo'yicha guruhlaydi. Server yangi→eski
/// tartibda qaytaradi, shuning uchun kunlar ham shu tartibda chiqadi
/// (Map kiritish tartibini saqlaydi).
List<_PurchaseDay> _groupByDay(List<dynamic> purchases) {
  final groups = <String, _PurchaseDay>{};
  for (final p in purchases) {
    final m = Map<String, dynamic>.from(p as Map);
    final key = _dayKeyOf(m['created_at']);
    (groups[key] ??= _PurchaseDay(
      key: key,
      date: DateTime.tryParse('${m['created_at']}')?.toLocal(),
    )).items.add(m);
  }
  return groups.values.toList();
}

// ============================================================
// Kun sahifasi — o'sha kuni qilingan xaridlar
// ============================================================

/// Har bir xarid alohida karta: vaqti, kim oldi, izohi va olingan
/// mahsulotlar. O'ng yuqorida savatcha — xaridni bekor qilish (ombor va
/// xarajat qaytariladi).
class _PurchaseDayScreen extends StatefulWidget {
  const _PurchaseDayScreen({
    required this.dayKey,
    required this.date,
    required this.title,
    required this.initialItems,
  });

  final String dayKey;
  final DateTime? date;
  final String title;
  final List<Map<String, dynamic>> initialItems;

  @override
  State<_PurchaseDayScreen> createState() => _PurchaseDayScreenState();
}

class _PurchaseDayScreenState extends State<_PurchaseDayScreen> {
  late List<Map<String, dynamic>> _items = [...widget.initialItems];
  bool _busy = false;

  Future<void> _reload() async {
    try {
      final res = await ApiService().getPurchases(limit: _kPurchaseLimit);
      final all = (res['purchases'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) => _dayKeyOf(p['created_at']) == widget.dayKey)
          .toList();
      if (!mounted) return;
      setState(() => _items = all);
    } catch (_) {
      // Tarmoq xatosida eski ro'yxat qolaveradi — sahifa yiqilmaydi.
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Xaridni o\'chirish'),
        content: Text(
          '${_fmtTime(p['created_at'])} — '
          '${formatMoney(p['total'], suffix: ' so\'m')} xaridi bekor '
          'qilinsinmi? Ombor va xarajat qaytariladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ApiService().deletePurchase(_int(p['id']));
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Xarid bekor qilindi'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errMsg(e, 'O\'chirib bo\'lmadi')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (s, p) => s + _int(p['total']));
    final d = widget.date;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            Text(
              [
                if (d != null) _fmtDay(d),
                '${_items.length} ta xarid',
                if (total > 0) formatMoney(total, suffix: ' so\'m'),
              ].join(' · '),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: KMaxWidth(
        maxWidth: 720,
        child: _items.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'Bu kunda xarid yo‘q',
                subtitle: 'Xaridlar bekor qilingan bo‘lishi mumkin',
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    context.gutter, 14, context.gutter, 24),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _purchaseCard(_items[i]),
              ),
      ),
    );
  }

  Widget _purchaseCard(Map<String, dynamic> p) {
    final items = p['items'] as List<dynamic>? ?? [];
    final note = (p['note'] ?? '').toString();
    final who = (p['created_by'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatMoney(p['total'], suffix: ' so\'m'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        [
                          _fmtTime(p['created_at']),
                          if (who.isNotEmpty) who,
                          if (note.isNotEmpty) note,
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Xaridni bekor qilish',
                  onPressed: _busy ? null : () => _delete(p),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            const Divider(
                height: 1, indent: 63, color: AppColors.borderSoft),
            _itemRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _itemRow(dynamic it) {
    final name = (it['name'] ?? '').toString();
    final unit = (it['unit'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IngredientAvatar(name: name, size: 38),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  formatQty(it['qty'], unit),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(it['subtotal'], suffix: ' so\'m'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
