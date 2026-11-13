import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/widgets/ingredient_picker.dart';
import '../admin_nav.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

class SupplyScreen extends StatefulWidget {
  const SupplyScreen({super.key});

  @override
  State<SupplyScreen> createState() => _SupplyScreenState();
}

enum _BatchFilter { active, empty, all }

class _SupplyScreenState extends State<SupplyScreen> {
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _ingredients = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;
  String _query = '';
  // Kunlik ko'rinishda odatiy filtr — HAMMASI: «shu kuni nima olindi»
  // savoliga tugagan partiyalar ham kiradi. Faol/Tugagan FIFO nazorati
  // uchun qoladi.
  _BatchFilter _filter = _BatchFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        ApiService().getIngredientBatches(),
        ApiService().getIngredients(),
      ]);
      final batchData = _map(results[0]);
      final ingredientData = _map(results[1]);
      if (!mounted) return;
      setState(() {
        _batches = _maps(batchData['items']);
        _summary = _map(batchData['summary']);
        _ingredients = _maps(ingredientData['ingredients']);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(error);
      });
    }
  }

  bool _isActive(Map<String, dynamic> b) =>
      b['status'] == 'active' && _int(b['remaining_qty']) > 0;

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _batches.where((b) {
      switch (_filter) {
        case _BatchFilter.active:
          if (!_isActive(b)) return false;
        case _BatchFilter.empty:
          if (_isActive(b)) return false;
        case _BatchFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      return (b['ingredient_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _editNote(Map<String, dynamic> batch) async {
    if (await _editBatchNoteForm(context, batch)) {
      if (mounted) showOk(context, 'Saqlandi');
      await _load(quiet: true);
    }
  }

  /// Yangi kirim — oraliq «partiya» ekrani YO'Q: bugungi kun sahifasi
  /// ochiladi va darhol picker chiqadi; har tanlov miqdor+narx bilan
  /// O'SHA ZAHOTI bugunga yozilaveradi.
  Future<void> _newIntake() async {
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DayScreen(
          dayKey: key,
          date: now,
          title: 'Bugun',
          initialItems:
              _batches.where((b) => _dayKeyOf(b) == key).toList(),
          ingredients: _ingredients,
          autoAdd: true,
        ),
      ),
    );
    await _load(quiet: true);
  }

  Future<void> _writeOff(Map<String, dynamic> batch) async {
    if (await _writeOffBatchForm(context, batch)) {
      if (mounted) showOk(context, 'Partiya hisobdan chiqarildi');
      await _load(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final activeCount = _batches.where(_isActive).length;

    return AdminPage(
      subtitle: 'FIFO hisob · $activeCount ta faol partiya',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: () => _load(quiet: true),
      onSearchChanged: (v) => setState(() => _query = v),
      searchHint: 'Ingredient nomi…',
      primaryAction: AdminAction(
        label: 'Kirim qo‘shish',
        icon: Icons.add_rounded,
        onPressed: _newIntake,
        color: const Color(0xFF0F766E),
      ),
      actions: [
        AdminIconAction(
          icon: Icons.inventory_2_outlined,
          tooltip: 'Ombor qoldig‘i',
          onPressed: () => AdminScope.maybeOf(context)?.go('ingredients'),
        ),
      ],
      toolbar: Column(
        children: [
          AdminStatsRow(
            items: [
              AdminStatData(
                label: 'FAOL PARTIYA',
                value: '${_int(_summary['active_count'])}',
                icon: Icons.layers_rounded,
                color: AppColors.primary,
              ),
              AdminStatData(
                label: 'QOLDIQ',
                value: _compactNumber(_summary['remaining_qty']),
                icon: Icons.scale_rounded,
                color: AppColors.success,
              ),
              AdminStatData(
                label: 'QIYMATI',
                value: formatMoney(_summary['remaining_value'], suffix: ' so‘m'),
                icon: Icons.payments_rounded,
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                KChip(
                  label: 'Faol',
                  selected: _filter == _BatchFilter.active,
                  accent: AppColors.success,
                  badge: activeCount,
                  onTap: () => setState(() => _filter = _BatchFilter.active),
                ),
                const SizedBox(width: 8),
                KChip(
                  label: 'Tugagan',
                  selected: _filter == _BatchFilter.empty,
                  accent: AppColors.textMuted,
                  badge: _batches.length - activeCount,
                  onTap: () => setState(() => _filter = _BatchFilter.empty),
                ),
                const SizedBox(width: 8),
                KChip(
                  label: 'Hammasi',
                  selected: _filter == _BatchFilter.all,
                  badge: _batches.length,
                  onTap: () => setState(() => _filter = _BatchFilter.all),
                ),
              ],
            ),
          ),
        ],
      ),
      child: list.isEmpty
          ? AdminEmpty(
              icon: Icons.inventory_2_outlined,
              title: _batches.isEmpty ? 'Partiyalar yo‘q' : 'Topilmadi',
              message: _batches.isEmpty
                  ? 'Omborga kelgan mahsulotni «Kirim qo‘shish» orqali '
                      'kiritsangiz, tannarx va qoldiq avtomatik hisoblanadi.'
                  : 'Filtr yoki qidiruvni o‘zgartiring.',
              actionLabel: _batches.isEmpty ? 'Kirim qo‘shish' : null,
              onAction: _batches.isEmpty ? _newIntake : null,
              color: const Color(0xFF0F766E),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 14, bottom: 96),
              children: _query.trim().isEmpty
                  ? [for (final g in _groupByDay(list)) _dayCard(g)]
                  // Qidiruvda kun kartalari emas — topilgan partiyalarning
                  // o'zi chiqadi (qaysi kunda olingani qator ostida).
                  : [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1,
                                    indent: 66,
                                    color: AppColors.borderSoft),
                              _batchRow(list[i], showDate: true),
                            ],
                          ],
                        ),
                      ),
                    ],
            ),
    );
  }

  /// Partiyalarni olingan kuni bo'yicha guruhlaydi. Ro'yxat serverdan
  /// received_at DESC keladi, shuning uchun guruhlar ham yangi→eski
  /// tartibda chiqadi (Map kiritish tartibini saqlaydi).
  List<_DayGroup> _groupByDay(List<Map<String, dynamic>> list) {
    final groups = <String, _DayGroup>{};
    for (final b in list) {
      final key = _dayKeyOf(b);
      (groups[key] ??= _DayGroup(
              key: key,
              date: DateTime.tryParse(b['received_at']?.toString() ?? '')
                  ?.toLocal()))
          .items.add(b);
    }
    return groups.values.toList();
  }

  /// Kun sahifasi — o'sha kunda olinganlar alohida ekranda: qo'shish va
  /// o'chirish bir tegishda. Qaytganda ro'yxat yangilanadi.
  Future<void> _openDay(_DayGroup g) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DayScreen(
          dayKey: g.key,
          date: g.date,
          title: _dayTitle(g.date),
          // Filtrdan qat'i nazar o'sha kunning HAMMA partiyalari.
          initialItems:
              _batches.where((b) => _dayKeyOf(b) == g.key).toList(),
          ingredients: _ingredients,
        ),
      ),
    );
    await _load(quiet: true);
  }

  static const _weekdays = [
    'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba',
    'Juma', 'Shanba', 'Yakshanba',
  ];
  static const _monthsShort = [
    'yan', 'fev', 'mar', 'apr', 'may', 'iyn',
    'iyl', 'avg', 'sen', 'okt', 'noy', 'dek',
  ];

  String _dayTitle(DateTime? d) {
    if (d == null) return 'Sana yo\'q';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Bugun';
    if (diff == 1) return 'Kecha';
    return _weekdays[d.weekday - 1];
  }

  Widget _dayCard(_DayGroup g) {
    final totalCost =
        g.items.fold<int>(0, (s, b) => s + _int(b['total_cost']));
    final d = g.date;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => _openDay(g),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
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
                            color: AppColors.primary,
                            height: 1.05,
                          ),
                        ),
                        if (d != null)
                          Text(
                            _monthsShort[d.month - 1],
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
                          d == null ? '' : _shortDate(g.items.first['received_at']),
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
                        '${g.items.length} ta mahsulot',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      if (totalCost > 0)
                        Text(
                          formatMoney(totalCost, suffix: ' so\'m'),
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
        ],
      ),
    );
  }

  /// Bitta partiya — ixcham qator: nimadan qancha olindi, necha pulga;
  /// o'ngda FIFO qoldiq holati. [showDate] — qidiruv natijasida qaysi
  /// kunda olingani ham chiqadi.
  Widget _batchRow(Map<String, dynamic> batch, {bool showDate = false}) {
    final received = _int(batch['received_qty']);
    final remaining = _int(batch['remaining_qty']);
    final ratio = received <= 0 ? 0.0 : (remaining / received).clamp(0.0, 1.0);
    final active = _isActive(batch);
    final note = batch['note']?.toString() ?? '';
    final name = batch['ingredient_name']?.toString() ?? '';
    final unit = batch['unit']?.toString() ?? '';
    final cost = _int(batch['total_cost']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          IngredientAvatar(name: name, size: 40),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  [
                    formatQty(received, unit),
                    if (cost > 0) formatMoney(cost, suffix: ' so\'m'),
                    if (showDate) _shortDate(batch['received_at']),
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                if (note.isNotEmpty)
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(ratio * 100).round()}% qoldi',
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: ratio,
                      backgroundColor: AppColors.surfaceAlt,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            )
          else
            const StatusBadge(label: 'tugagan', color: AppColors.textMuted),
          PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 20, color: AppColors.textFaint),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                onSelected: (value) {
                  if (value == 'edit') _editNote(batch);
                  if (value == 'write_off') _writeOff(batch);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    height: 44,
                    child: Row(
                      children: [
                        Icon(Icons.notes_rounded,
                            size: 18, color: AppColors.textMuted),
                        SizedBox(width: 10),
                        Text('Izohni tahrirlash'),
                      ],
                    ),
                  ),
                  if (active)
                    const PopupMenuItem(
                      value: 'write_off',
                      height: 44,
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_rounded,
                              size: 18, color: AppColors.danger),
                          SizedBox(width: 10),
                          Text('Hisobdan chiqarish',
                              style: TextStyle(color: AppColors.danger)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
  }
}

/// Bitta kunning kirim guruhi — kalit ('yyyy-mm-dd'), sana va o'sha kunda
/// olingan partiyalar.
class _DayGroup {
  final String key;
  final DateTime? date;
  final List<Map<String, dynamic>> items = [];
  _DayGroup({required this.key, required this.date});
}

/// Partiyaning olingan kuni — local vaqtda 'yyyy-mm-dd' kalit.
String _dayKeyOf(Map<String, dynamic> b) {
  final d = DateTime.tryParse(b['received_at']?.toString() ?? '')?.toLocal();
  if (d == null) return '-';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Partiya izohini tahrirlash formasi (partiya kodi va ta'minotchi UI'dan
/// olib tashlangan, lekin serverga o'zgarishsiz qaytariladi: backend PUT
/// hamma maydonni birdan yozadi). Saqlansa true.
Future<bool> _editBatchNoteForm(
    BuildContext context, Map<String, dynamic> batch) async {
  final noteC = TextEditingController(text: batch['note']?.toString() ?? '');
  final saved = await showAdminForm(
    context: context,
    title: batch['ingredient_name']?.toString() ?? 'Partiya',
    subtitle: 'Partiya #${batch['id']} · '
        '${formatQty(batch['remaining_qty'], batch['unit']?.toString() ?? '')} qoldi',
    icon: Icons.inventory_2_rounded,
    color: const Color(0xFF0F766E),
    fields: (ctx, refresh) => [
      AdminField(
        label: 'Izoh',
        controller: noteC,
        hint: 'Kim keltirdi, qanday holatda…',
        icon: Icons.notes_rounded,
        maxLines: 3,
        autofocus: true,
      ),
    ],
    onSubmit: () async {
      try {
        await ApiService().updateIngredientBatch(_int(batch['id']), {
          'ingredient_id': _int(batch['ingredient_id']),
          'supplier_id': batch['supplier_id'],
          'batch_code': batch['batch_code']?.toString() ?? '',
          'note': noteC.text.trim(),
        });
        return true;
      } catch (e) {
        if (context.mounted) showErr(context, apiErrorText(e));
        return false;
      }
    },
  );
  return saved == true;
}

/// Hisobdan chiqarish formasi (sabab bilan). Bajarilsa true.
Future<bool> _writeOffBatchForm(
    BuildContext context, Map<String, dynamic> batch) async {
  final noteC = TextEditingController();
  final saved = await showAdminForm(
    context: context,
    title: 'Hisobdan chiqarish',
    subtitle: '${batch['ingredient_name']} — '
        '${formatQty(batch['remaining_qty'], batch['unit']?.toString() ?? '')}',
    icon: Icons.delete_sweep_rounded,
    color: AppColors.danger,
    fields: (ctx, refresh) => [
      AdminField(
        label: 'Sabab',
        controller: noteC,
        hint: 'Buzildi, yo‘qotildi va h.k.',
        icon: Icons.notes_rounded,
        autofocus: true,
      ),
    ],
    submitLabel: 'Hisobdan chiqarish',
    onSubmit: () async {
      try {
        await ApiService()
            .writeOffIngredientBatch(_int(batch['id']), note: noteC.text.trim());
        return true;
      } catch (e) {
        if (context.mounted) showErr(context, apiErrorText(e));
        return false;
      }
    },
  );
  return saved == true;
}

/// Tanlangan ingredient uchun miqdor+narx formasi — saqlansa DARHOL
/// bugunga partiya bo'lib yoziladi (oraliq ekran yo'q). true = saqlandi.
Future<bool> _quickAddBatchForm(
    BuildContext context, Map<String, dynamic> ing) async {
  final qtyC = TextEditingController();
  final costC = TextEditingController();
  final unit = (ing['unit'] ?? '').toString();
  final saved = await showAdminForm(
    context: context,
    title: (ing['name'] ?? '').toString(),
    // Birlik doim ko'z oldida tursin — «25 kg»ni «25» deb yozib, omborga
    // 25 GRAMM kiritish xatosidan saqlaydi (1000 barobar farq).
    subtitle: unit == 'gr'
        ? 'Miqdor grammda — 1 kg = 1000 gr'
        : unit == 'ml'
            ? 'Miqdor millilitrda — 1 litr = 1000 ml'
            : 'Birlik: $unit',
    icon: Icons.add_shopping_cart_rounded,
    color: const Color(0xFF0F766E),
    fields: (ctx, refresh) => [
      AdminField(
        label: 'Miqdor',
        controller: qtyC,
        suffixText: unit,
        keyboardType: TextInputType.number,
        formatters: const [MoneyInputFormatter()],
        icon: Icons.scale_rounded,
        autofocus: true,
      ),
      AdminField(
        label: 'Jami narx',
        controller: costC,
        suffixText: 'so‘m',
        keyboardType: TextInputType.number,
        formatters: const [MoneyInputFormatter()],
        icon: Icons.payments_rounded,
      ),
    ],
    submitLabel: 'Bugunga qo‘shish',
    onSubmit: () async {
      final qty = parseIntField(qtyC.text) ?? 0;
      if (qty <= 0) {
        if (context.mounted) showErr(context, 'Miqdor kiritilmagan ($unit)');
        return false;
      }
      try {
        await ApiService().createIngredientBatch({
          'ingredient_id': _int(ing['id']),
          'supplier_id': null,
          'batch_code': '',
          'qty': qty,
          'total_cost': parseIntField(costC.text) ?? 0,
          'note': '',
        });
        return true;
      } catch (e) {
        if (context.mounted) showErr(context, apiErrorText(e));
        return false;
      }
    },
  );
  return saved == true;
}

// ============================================================
// Kun sahifasi — o'sha kunda olingan partiyalar alohida ekranda
// ============================================================

/// Qator bosilsa izoh tahrirlanadi; savatcha — olib tashlash (hisobdan
/// chiqarish yoki xato kiritilganni butunlay o'chirish). Bugungi kun
/// sahifasida pastda «Ingredient qo'shish» — picker'dan tanlangan zahoti
/// miqdor+narx so'raladi va DARHOL bugunga yozib boriladi (oraliq
/// «partiya» ekrani yo'q).
class _DayScreen extends StatefulWidget {
  const _DayScreen({
    required this.dayKey,
    required this.date,
    required this.title,
    required this.initialItems,
    required this.ingredients,
    this.autoAdd = false,
  });

  final String dayKey;
  final DateTime? date;
  final String title;
  final List<Map<String, dynamic>> initialItems;
  final List<Map<String, dynamic>> ingredients;

  /// true — sahifa ochilishi bilan picker o'zi chiqadi (asosiy sahifadagi
  /// «Kirim qo'shish» shu rejimda ochadi).
  final bool autoAdd;

  @override
  State<_DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<_DayScreen> {
  late List<Map<String, dynamic>> _items = [...widget.initialItems];
  // Nusxa: picker ichida yangi yaratilgan ingredient shu ro'yxatga tushadi.
  late final List<Map<String, dynamic>> _ingredients = [
    ...widget.ingredients,
  ];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _quickAdd();
      });
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return widget.dayKey ==
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
  }

  String get _dateLabel {
    final d = widget.date;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  bool _active(Map<String, dynamic> b) =>
      b['status'] == 'active' && _int(b['remaining_qty']) > 0;

  Future<void> _reload() async {
    try {
      final data = _map(await ApiService().getIngredientBatches());
      final all = _maps(data['items']);
      if (!mounted) return;
      setState(() =>
          _items = all.where((b) => _dayKeyOf(b) == widget.dayKey).toList());
    } catch (_) {
      // Tarmoq xatosida eski ro'yxat qolaveradi — sahifa yiqilmaydi.
    }
  }

  /// Tez qo'shish sikli: picker → miqdor+narx → DARHOL saqlanadi → yana
  /// picker (bozordan kelgan bir nechta mahsulot ketma-ket kiritiladi).
  /// Picker'da orqaga bosilsa sikl tugaydi.
  Future<void> _quickAdd() async {
    while (true) {
      if (!mounted) return;
      final picked = await showIngredientPicker(
        context,
        ingredients: _ingredients,
      );
      if (picked == null || !mounted) return;
      if (!_ingredients
          .any((i) => _int(i['id']) == _int(picked['id']))) {
        _ingredients.add(picked);
      }
      final saved = await _quickAddBatchForm(context, picked);
      if (!mounted) return;
      if (saved) {
        showOk(context, '${picked['name']} bugunga qo‘shildi');
        await _reload();
      }
      // Saqlanmagan (bekor) bo'lsa ham picker'ga qaytamiz — sikldan
      // chiqish nuqtasi bitta: picker'dagi orqaga tugmasi.
    }
  }

  Future<void> _editNote(Map<String, dynamic> batch) async {
    if (await _editBatchNoteForm(context, batch)) {
      if (mounted) showOk(context, 'Saqlandi');
      await _reload();
    }
  }

  /// Savatcha bosilganda tanlov: buzilgan mahsulot hisobdan chiqariladi
  /// (tarixda qoladi), xato kiritilgani esa butunlay o'chiriladi (ombor
  /// qoldig'i va tannarx qayta hisoblanadi).
  Future<void> _remove(Map<String, dynamic> batch) async {
    final name = batch['ingredient_name']?.toString() ?? '';
    final choice = await showDialog<String>(
      context: context,
      builder: (dctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        children: [
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded,
                color: AppColors.warning),
            title: const Text('Hisobdan chiqarish'),
            subtitle: const Text('Buzildi/yo‘qotildi — tarixda qoladi'),
            onTap: () => Navigator.pop(dctx, 'write_off'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_rounded,
                color: AppColors.danger),
            title: const Text('Butunlay o‘chirish',
                style: TextStyle(color: AppColors.danger)),
            subtitle:
                const Text('Xato kiritilgan — qoldiqdan olib tashlanadi'),
            onTap: () => Navigator.pop(dctx, 'delete'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Bekor'),
              ),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'write_off') {
      if (await _writeOffBatchForm(context, batch)) {
        if (mounted) showOk(context, 'Partiya hisobdan chiqarildi');
        await _reload();
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService().deleteIngredientBatch(_int(batch['id']));
      if (mounted) showOk(context, 'Partiya o‘chirildi');
      await _reload();
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCost =
        _items.fold<int>(0, (s, b) => s + _int(b['total_cost']));
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
                if (_dateLabel.isNotEmpty) _dateLabel,
                '${_items.length} ta mahsulot',
                if (totalCost > 0) formatMoney(totalCost, suffix: ' so‘m'),
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
                icon: Icons.inventory_2_outlined,
                title: 'Bu kunda kirim yo‘q',
                subtitle: 'Pastdagi tugma bilan yangi kirim qo‘shing',
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(
                    context.gutter, 14, context.gutter, 14),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _items.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1,
                                indent: 66,
                                color: AppColors.borderSoft),
                          _row(_items[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: !_isToday
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: KMaxWidth(
                  maxWidth: 720,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                      onPressed: _busy ? null : _quickAdd,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ingredient qo‘shish'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _row(Map<String, dynamic> b) {
    final received = _int(b['received_qty']);
    final remaining = _int(b['remaining_qty']);
    final ratio =
        received <= 0 ? 0.0 : (remaining / received).clamp(0.0, 1.0);
    final active = _active(b);
    final name = b['ingredient_name']?.toString() ?? '';
    final unit = b['unit']?.toString() ?? '';
    final cost = _int(b['total_cost']);
    final note = b['note']?.toString() ?? '';

    return InkWell(
      onTap: _busy ? null : () => _editNote(b),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            IngredientAvatar(name: name, size: 40),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      formatQty(received, unit),
                      if (cost > 0) formatMoney(cost, suffix: ' so‘m'),
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (note.isNotEmpty)
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textFaint),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (active)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(ratio * 100).round()}% qoldi',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: ratio,
                        backgroundColor: AppColors.surfaceAlt,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              )
            else
              const StatusBadge(label: 'tugagan', color: AppColors.textMuted),
            if (active)
              IconButton(
                tooltip: 'Olib tashlash',
                onPressed: _busy ? null : () => _remove(b),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppColors.danger),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return [];
  return value.map(_map).toList();
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _shortDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '—';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

String _compactNumber(dynamic value) {
  final number = _int(value);
  if (number >= 1_000_000) {
    return '${(number / 1_000_000).toStringAsFixed(1)} mln';
  }
  if (number >= 1_000) {
    return '${(number / 1_000).toStringAsFixed(1)} ming';
  }
  return '$number';
}

