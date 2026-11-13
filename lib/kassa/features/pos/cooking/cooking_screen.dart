import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';

/// Pishirish — nima pishirish kerak, jarayonda va tarix
class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});
  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen> {
  List<dynamic> _needed = [];
  List<dynamic> _inProgress = [];
  List<dynamic> _history = [];
  bool _loading = true;
  bool _loadError = false;
  bool _busy = false; // ikki marta bosishdan himoya (qo'sh sarf/qo'sh baza)
  StreamSubscription? _wssSub;

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen((e) {
      final ev = e['event'];
      if (ev == 'cooking:updated' ||
          ev == 'ingredient:updated' ||
          ev == 'stock:updated') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService().getCookingNeeded(),
        ApiService().getCookings(status: 'cooking', limit: 50),
        ApiService().getCookings(limit: 30),
      ]);
      if (mounted) {
        setState(() {
          _needed = (results[0])['items'] as List<dynamic>? ?? [];
          _inProgress =
              (results[1])['cookings'] as List<dynamic>? ?? [];
          _history = ((results[2])['cookings'] as List<dynamic>? ?? [])
              .where((c) => c['status'] != 'cooking')
              .take(20)
              .toList();
          _loading = false;
          _loadError = false;
        });
      }
    } catch (e) {
      // Xato JIMGINA "bo'sh ro'yxat" bo'lib ko'rinmasin: oshxona "hammasi
      // yetarli" deb o'ylab qolardi, pishayotgan taom esa "Tayyor" tugmasisiz
      // qolib, masalliqlari omborda kamaygancha turaverardi.
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
        _toast('Ma\'lumot yuklanmadi — internet yoki server bilan aloqa yo\'q',
            color: AppColors.danger);
      }
    }
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

  String _fmtTime(dynamic v) {
    if (v == null) return '';
    final d = DateTime.tryParse(v.toString());
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }

  // ===== Pishirishni boshlash =====

  Future<void> _startDialog(Map<String, dynamic> item) async {
    if (item['has_recipe'] != true) {
      _toast('Avval retsept kiritilishi kerak', color: AppColors.warning);
      return;
    }
    final deficit = item['deficit'] is int ? item['deficit'] as int : 0;
    final batchQty =
        item['batch_qty'] is int ? item['batch_qty'] as int : 1;
    final qtyC =
        TextEditingController(text: deficit > 0 ? '$deficit' : '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item['name']}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: qtyC,
                decoration: const InputDecoration(
                  labelText: 'Nechta pishirilsin?',
                  suffixText: 'ta',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(
                '1 partiya = $batchQty ta',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.local_fire_department_rounded,
                size: 18),
            label: const Text('Boshlash'),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(qtyC.text) ?? 0;
    if (qty <= 0) {
      _toast('Miqdor noto\'g\'ri', color: AppColors.danger);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService()
          .startCooking(item['product_id'] as int, qty);
      _toast('Pishirish boshlandi — $qty ta');
      _load();
    } catch (e) {
      _toast(_errMsg(e, 'Boshlab bo\'lmadi — ingredientlar yetarli emas?'),
          color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done(Map<String, dynamic> c) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await ApiService().finishCooking(c['id'] as int);
      final qty = res['qty'] ?? c['qty'] ?? 0;
      final newCount = res['new_count'];
      _toast(newCount != null
          ? 'Bazaga +$qty ta (jami: $newCount)'
          : 'Bazaga +$qty ta');
      _load();
    } catch (e) {
      _toast(_errMsg(e, 'Xatolik yuz berdi'), color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekor qilish'),
        content: Text(
            '${c['product_name']} (${c['qty']} ta) pishirish bekor qilinsinmi? '
            'Ingredientlar omborga qaytariladi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Yo\'q')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Bekor qilish'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ApiService().cancelCooking(c['id'] as int);
      _toast('Bekor qilindi — ingredientlar qaytarildi',
          color: AppColors.warning);
      _load();
    } catch (e) {
      _toast(_errMsg(e, 'Xatolik yuz berdi'), color: AppColors.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(context.gutter, context.isTabletUi ? 18 : 12, context.gutter, 24),
        children: [
          // Ma'lumot yuklanmagan bo'lsa buni AYTAMIZ. Busiz ro'yxat bo'sh
          // ko'rinib, oshxona "hammasi yetarli" deb o'ylab qolardi.
          if (_loadError) ...[
            KCard(
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ma\'lumot yuklanmadi — ro\'yxat to\'liq bo\'lmasligi mumkin',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Qayta')),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 1. Pishirish kerak
          _sectionHeader(Icons.notification_important_rounded,
              'Pishirish kerak', AppColors.danger, _needed.length),
          const SizedBox(height: 8),
          if (_needed.isEmpty)
            const KCard(
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 20),
                  SizedBox(width: 10),
                  Text('Hammasi yetarli',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            )
          else
            ..._needed.map(_neededCard),
          const SizedBox(height: 18),

          // 2. Jarayonda
          _sectionHeader(Icons.local_fire_department_rounded, 'Jarayonda',
              AppColors.warning, _inProgress.length),
          const SizedBox(height: 8),
          if (_inProgress.isEmpty)
            const KCard(
              child: Text('Hozir hech narsa pishirilmayapti',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
            )
          else
            ..._inProgress.map((c) => _cookingCard(
                c is Map<String, dynamic>
                    ? c
                    : Map<String, dynamic>.from(c as Map))),
          const SizedBox(height: 18),

          // 3. Tarix (yig'ilgan)
          if (_history.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 2),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  leading: const IconAvatar(
                      icon: Icons.history_rounded,
                      color: AppColors.textMuted,
                      size: 38),
                  title: const Text(
                    'Tarix',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text),
                  ),
                  subtitle: Text(
                    'oxirgi ${_history.length} ta',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                  children: _history.map(_historyRow).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(
      IconData icon, String title, Color color, int count) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.text),
        ),
        const SizedBox(width: 8),
        if (count > 0)
          StatusBadge(label: '$count', color: color, fontSize: 11),
      ],
    );
  }

  Widget _neededCard(dynamic item) {
    final count = item['count'] is int ? item['count'] as int : 0;
    final limit =
        item['limit_qty'] is int ? item['limit_qty'] as int : 0;
    final deficit = item['deficit'] is int ? item['deficit'] as int : 0;
    final batchQty =
        item['batch_qty'] is int ? item['batch_qty'] as int : 0;
    final hasRecipe = item['has_recipe'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KCard(
        onTap: _busy
            ? null
            : () => _startDialog(item is Map<String, dynamic>
                ? item
                : Map<String, dynamic>.from(item as Map)),
        padding: const EdgeInsets.all(12),
        borderColor: AppColors.danger.withValues(alpha: 0.35),
        child: Row(
          children: [
            const IconAvatar(
                icon: Icons.bakery_dining_rounded,
                color: AppColors.danger,
                size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count/$limit — $deficit ta kam',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger),
                  ),
                  Text(
                    hasRecipe
                        ? '1 partiya = $batchQty ta'
                        : 'Retsept yo\'q — kiriting',
                    style: TextStyle(
                        fontSize: 11,
                        color: hasRecipe
                            ? AppColors.textFaint
                            : AppColors.warning),
                  ),
                ],
              ),
            ),
            Icon(
              hasRecipe
                  ? Icons.play_circle_fill_rounded
                  : Icons.warning_amber_rounded,
              size: 28,
              color: hasRecipe ? AppColors.warning : AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cookingCard(Map<String, dynamic> c) {
    final ingredients = c['ingredients'] as List<dynamic>? ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KCard(
        padding: const EdgeInsets.all(12),
        borderColor: AppColors.warning.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconAvatar(
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.warning,
                    size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c['product_name']} — ${c['qty']} ta',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text),
                      ),
                      Text(
                        'boshlandi: ${_fmtTime(c['created_at'])}'
                        '${(c['created_by'] ?? '').toString().isNotEmpty ? ' • ${c['created_by']}' : ''}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (ingredients.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ishlatilgan ingredientlar:',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted)),
                    const SizedBox(height: 4),
                    for (final ing in ingredients)
                      Text(
                        '• ${ing['name']} — ${formatQty(ing['qty'] ?? ing['amount'], (ing['unit'] ?? '').toString())}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.text),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _done(c),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Tayyor',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _cancel(c),
                      icon:
                          const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Bekor',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side:
                            const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(dynamic c) {
    final done = c['status'] == 'done';
    final color = done ? AppColors.success : AppColors.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${c['product_name']} — ${c['qty']} ta',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StatusBadge(
            label: done ? 'tayyor' : 'bekor',
            color: color,
            fontSize: 10,
          ),
          const SizedBox(width: 8),
          Text(
            _fmtTime(c['created_at']),
            style: const TextStyle(
                fontSize: 11, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
