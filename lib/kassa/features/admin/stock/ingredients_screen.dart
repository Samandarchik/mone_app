import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../admin_nav.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// Ingredientlar ombori — qoldiq, min miqdor, narx, korreksiya, tarix
class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});
  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

enum _Filter { all, low, inactive }

class _IngredientsScreenState extends State<IngredientsScreen> {
  List<dynamic> _ingredients = [];
  bool _loading = true;
  String? _error;
  StreamSubscription? _wssSub;
  String _query = '';
  _Filter _filter = _Filter.all;

  static const _units = {
    'gr': 'Gramm (gr)',
    'ml': 'Millilitr (ml)',
    'dona': 'Dona',
    'm': 'Metr (m)',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen((e) {
      if (e['event'] == 'ingredient:updated') _load();
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getIngredients();
      if (!mounted) return;
      setState(() {
        _ingredients = res['ingredients'] as List<dynamic>? ?? [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      // Xato jimgina "bo'sh ro'yxat" bo'lib ko'rinmasin: xodim hammasi
      // joyida deb o'ylab qolardi.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _ingredients
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((i) {
          switch (_filter) {
            case _Filter.low:
              if (i['low'] != true) return false;
            case _Filter.inactive:
              if (i['status'] != 'inactive') return false;
            case _Filter.all:
              break;
          }
          if (q.isEmpty) return true;
          return (i['name'] ?? '').toString().toLowerCase().contains(q);
        })
        .toList();
  }

  // ===================== Qo'shish / tahrirlash =====================

  Future<void> _openForm({Map<String, dynamic>? initial}) async {
    final isNew = initial == null;
    final nameC = TextEditingController(text: initial?['name']?.toString() ?? '');
    final minC = TextEditingController(
        text: isNew ? '' : '${initial['min_qty'] ?? 0}');
    final wasteC = TextEditingController(
        text: isNew ? '' : '${initial['waste_percent'] ?? 0}');
    var unit = (initial?['unit'] ?? 'gr').toString();
    var active = (initial?['status'] ?? 'active') == 'active';

    final saved = await showAdminForm(
      context: context,
      title: isNew ? 'Yangi ingredient' : initial['name'].toString(),
      subtitle: isNew
          ? 'Retseptlarda ishlatiladigan masalliq'
          : 'Qoldiq: ${formatQty(initial['count'], unit)}',
      icon: Icons.egg_alt_rounded,
      color: const Color(0xFF06B6D4),
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Nomi',
          controller: nameC,
          hint: 'Masalan: Un',
          icon: Icons.egg_alt_outlined,
          autofocus: isNew,
        ),
        if (isNew)
          AdminChoice<String>(
            label: 'O‘lchov birligi',
            value: unit,
            items: _units,
            onChanged: (v) => refresh(() => unit = v),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'O‘lchov birligi: $unit (o‘zgartirib bo‘lmaydi)',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint),
            ),
          ),
        AdminField(
          label: 'Minimal qoldiq',
          controller: minC,
          hint: '0',
          suffixText: unit,
          helper: 'Shu miqdordan kamaysa «kam qoldi» ogohlantirishi chiqadi',
          icon: Icons.warning_amber_rounded,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        AdminField(
          label: 'Chiqindi (waste)',
          controller: wasteC,
          hint: '0',
          suffixText: '%',
          helper: 'Tozalashda yo‘qoladigan qism (0–90%)',
          icon: Icons.percent_rounded,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        if (!isNew)
          AdminSwitchRow(
            label: active ? 'Faol' : 'Nofaol',
            hint: 'Nofaol ingredient yangi retseptlarda tanlanmaydi',
            value: active,
            icon: Icons.toggle_on_rounded,
            onChanged: (v) => refresh(() => active = v),
          ),
      ],
      submitLabel: isNew ? 'Qo‘shish' : 'Saqlash',
      onSubmit: () async {
        final name = nameC.text.trim();
        if (name.isEmpty) {
          showErr(context, 'Nomini kiriting');
          return false;
        }
        // Bo'sh bo'lmagan, lekin o'qib bo'lmaydigan qiymat ilgari JIMGINA
        // 0 ga aylanardi. `min_qty` 0 bo'lsa "kam qoldi" ogohlantirishi
        // butunlay o'chib ketardi.
        final minQty = minC.text.trim().isEmpty ? 0 : parseIntField(minC.text);
        final waste = wasteC.text.trim().isEmpty ? 0 : parseIntField(wasteC.text);
        if (minQty == null) {
          showErr(context, 'Minimal qoldiq faqat butun son bo‘lsin');
          return false;
        }
        if (waste == null || waste < 0 || waste > 90) {
          showErr(context, 'Chiqindi foizi 0 dan 90 gacha bo‘lsin');
          return false;
        }
        try {
          if (isNew) {
            await ApiService().createIngredient({
              'name': name,
              'unit': unit,
              'min_qty': minQty,
              'waste_percent': waste,
            });
          } else {
            await ApiService().updateIngredient(initial['id'] as int, {
              'name': name,
              'min_qty': minQty,
              'waste_percent': waste,
              'status': active ? 'active' : 'inactive',
            });
          }
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
      onDelete: isNew ? null : () => _delete(initial, silent: true),
      deleteLabel: 'Ingredientni o‘chirish',
    );

    if (saved == true) {
      if (mounted) showOk(context, isNew ? 'Qo‘shildi' : 'Saqlandi');
      _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> ing, {bool silent = false}) async {
    if (!silent) {
      final ok = await confirmAction(
        context: context,
        title: 'O‘chirish',
        message: '«${ing['name']}» o‘chirilsinmi?',
        confirmLabel: 'O‘chirish',
        danger: true,
      );
      if (ok != true) return false;
    }
    try {
      await ApiService().deleteIngredient(ing['id'] as int);
      if (!silent) {
        if (mounted) showOk(context, 'O‘chirildi');
        _load();
      }
      return true;
    } catch (e) {
      var msg = apiErrorText(e);
      if (e is DioException && e.response?.statusCode == 409) {
        msg = 'O‘chirib bo‘lmadi — retseptda ishlatilgan';
      }
      if (mounted) showErr(context, msg);
      return false;
    }
  }

  // ===================== Korreksiya =====================

  Future<void> _adjust(Map<String, dynamic> ing) async {
    final unit = (ing['unit'] ?? '').toString();
    final countC = TextEditingController();
    final commentC = TextEditingController();

    final saved = await showAdminForm(
      context: context,
      title: 'Korreksiya',
      subtitle: '${ing['name']} · hozir ${formatQty(ing['count'], unit)}',
      icon: Icons.scale_rounded,
      color: AppColors.warning,
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Haqiqiy qoldiq',
          controller: countC,
          hint: '0',
          suffixText: unit,
          helper: 'Tarozida o‘lchangan haqiqiy miqdorni yozing',
          icon: Icons.scale_rounded,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
        ),
        AdminField(
          label: 'Sabab',
          controller: commentC,
          hint: 'Nega farq chiqdi?',
          icon: Icons.notes_rounded,
        ),
      ],
      submitLabel: 'Tasdiqlash',
      onSubmit: () async {
        final newCount = parseIntField(countC.text);
        if (newCount == null || newCount < 0) {
          showErr(context, 'Miqdor noto‘g‘ri');
          return false;
        }
        try {
          await ApiService().adjustIngredient(
              ing['id'] as int, newCount, commentC.text.trim());
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
    );
    if (saved == true) {
      if (mounted) showOk(context, 'Korreksiya saqlandi');
      _load();
    }
  }

  // ===================== Tarix =====================

  static const _reasonColors = <String, Color>{
    'kirim': AppColors.success,
    'pishirish': AppColors.info,
    'korreksiya': AppColors.warning,
    'spisaniye': AppColors.danger,
    'qaytarildi': AppColors.primary,
  };

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return v.toString();
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _showHistory(Map<String, dynamic> ing) async {
    List<dynamic>? moves;
    try {
      final res = await ApiService()
          .getIngredientMoves(ingredientId: ing['id'] as int, limit: 100);
      moves = res['moves'] as List<dynamic>? ?? [];
    } catch (_) {
      moves = null;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${ing['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Ombor harakatlari tarixi',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceAlt,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: moves == null
                  ? const AdminEmpty(
                      icon: Icons.cloud_off_rounded,
                      title: 'Tarixni yuklab bo‘lmadi',
                      color: AppColors.danger,
                    )
                  : moves.isEmpty
                      ? const AdminEmpty(
                          icon: Icons.history_rounded,
                          title: 'Harakatlar yo‘q',
                          message: 'Bu ingredient bo‘yicha kirim/chiqim '
                              'hali qayd etilmagan.',
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: moves.length,
                          separatorBuilder: (_, _) => const Divider(height: 14),
                          itemBuilder: (_, i) => _moveRow(moves![i]),
                        ),
            ),
            SafeArea(top: false, child: const SizedBox(height: 6)),
          ],
        ),
      ),
    );
  }

  Widget _moveRow(dynamic m) {
    final reason = (m['reason'] ?? '').toString();
    final color = _reasonColors[reason] ?? AppColors.textMuted;
    final qty = m['qty'] is int ? m['qty'] as int : 0;
    final unit = (m['unit'] ?? '').toString();
    final comment = (m['comment'] ?? '').toString();
    return Row(
      children: [
        StatusBadge(label: reason, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${qty > 0 ? '+' : ''}${formatQty(qty, unit)}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: qty >= 0 ? AppColors.success : AppColors.danger,
                ),
              ),
              if (comment.isNotEmpty)
                Text(
                  comment,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmtDate(m['created_at']),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
            ),
            if ((m['created_by'] ?? '').toString().isNotEmpty)
              Text(
                '${m['created_by']}',
                style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
          ],
        ),
      ],
    );
  }

  // ===================== Ko'rinish =====================

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final lowCount = _ingredients.where((i) => i['low'] == true).length;
    final inactiveCount =
        _ingredients.where((i) => i['status'] == 'inactive').length;

    return AdminPage(
      subtitle: '${_ingredients.length} ta ingredient'
          '${lowCount > 0 ? ' · $lowCount tasi kam qoldi' : ''}',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: _load,
      onSearchChanged: (v) => setState(() => _query = v),
      searchHint: 'Ingredient nomi…',
      primaryAction: AdminAction(
        label: 'Ingredient',
        icon: Icons.add_rounded,
        onPressed: () => _openForm(),
        color: const Color(0xFF06B6D4),
      ),
      actions: [
        AdminIconAction(
          icon: Icons.local_shipping_outlined,
          tooltip: 'Kirim partiyalari',
          onPressed: () => AdminScope.maybeOf(context)?.go('supply'),
        ),
      ],
      toolbar: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            KChip(
              label: 'Hammasi',
              selected: _filter == _Filter.all,
              badge: _ingredients.length,
              onTap: () => setState(() => _filter = _Filter.all),
            ),
            const SizedBox(width: 8),
            KChip(
              label: 'Kam qoldi',
              icon: Icons.warning_amber_rounded,
              accent: AppColors.danger,
              selected: _filter == _Filter.low,
              badge: lowCount,
              onTap: () => setState(() => _filter = _Filter.low),
            ),
            if (inactiveCount > 0) ...[
              const SizedBox(width: 8),
              KChip(
                label: 'Nofaol',
                accent: AppColors.textMuted,
                selected: _filter == _Filter.inactive,
                badge: inactiveCount,
                onTap: () => setState(() => _filter = _Filter.inactive),
              ),
            ],
          ],
        ),
      ),
      child: list.isEmpty
          ? AdminEmpty(
              icon: _query.isEmpty
                  ? Icons.egg_alt_outlined
                  : Icons.search_off_rounded,
              title: _query.isEmpty ? 'Ingredient yo‘q' : 'Topilmadi',
              message: _query.isEmpty
                  ? 'Retsept tuzish uchun avval masalliqlarni qo‘shing.'
                  : 'Boshqa nom bilan qidirib ko‘ring.',
              actionLabel: _query.isEmpty ? 'Ingredient qo‘shish' : null,
              onAction: _query.isEmpty ? () => _openForm() : null,
              color: const Color(0xFF06B6D4),
            )
          : AdminList(
              children: [
                for (final ing in list) _tile(ing),
              ],
            ),
    );
  }

  Widget _tile(Map<String, dynamic> ing) {
    final unit = (ing['unit'] ?? '').toString();
    final low = ing['low'] == true;
    final inactive = ing['status'] == 'inactive';
    final unitPrice = ing['unit_price'] is int ? ing['unit_price'] as int : 0;
    final color = low ? AppColors.danger : AppColors.success;

    final tile = AdminTile(
      title: '${ing['name']}',
      subtitle: [
        'min: ${formatQty(ing['min_qty'], unit)}',
        if (unitPrice > 0) '${formatMoney(unitPrice)} ${unitPriceLabel(unit)}',
      ].join(' · '),
      icon: low ? Icons.warning_amber_rounded : Icons.egg_alt_outlined,
      color: color,
      value: formatQty(ing['count'], unit),
      valueColor: color,
      badge: inactive
          ? const StatusBadge(label: 'nofaol', color: AppColors.textMuted)
          : null,
      highlight: low ? AppColors.danger.withValues(alpha: 0.45) : null,
      onTap: () => _openForm(initial: ing),
      menu: const [
        AdminMenuItem(
          value: 'edit',
          label: 'Tahrirlash',
          icon: Icons.edit_outlined,
        ),
        AdminMenuItem(
          value: 'adjust',
          label: 'Korreksiya',
          icon: Icons.scale_rounded,
          color: AppColors.warning,
        ),
        AdminMenuItem(
          value: 'history',
          label: 'Tarix',
          icon: Icons.history_rounded,
          color: AppColors.info,
        ),
        AdminMenuItem(
          value: 'delete',
          label: 'O‘chirish',
          icon: Icons.delete_outline_rounded,
          color: AppColors.danger,
        ),
      ],
      onMenuSelected: (v) {
        switch (v) {
          case 'edit':
            _openForm(initial: ing);
          case 'adjust':
            _adjust(ing);
          case 'history':
            _showHistory(ing);
          case 'delete':
            _delete(ing);
        }
      },
    );

    return inactive ? Opacity(opacity: 0.55, child: tile) : tile;
  }
}
