import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';

/// Inventarizatsiya — omborni sanab, haqiqiy qoldiqlarni to'g'irlash ekrani.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<dynamic> _products = [];
  Map<int, int> _stocks = {}; // product_id -> count
  bool _loading = true;
  bool _submitting = false;
  final TextEditingController _searchC = TextEditingController();
  String _query = '';
  final Map<int, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchC.addListener(() {
      final q = _searchC.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchC.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService().getStocks(force: true),
        ApiService().getMenu(),
      ]);
      final stocks = results[0] as List<dynamic>;
      final menu = results[1] as Map<String, dynamic>;
      final products = menu['products'] as List<dynamic>? ?? [];
      final stockMap = <int, int>{};
      for (final s in stocks) {
        stockMap[s['product_id'] as int] = s['count'] as int;
      }
      if (!mounted) return;
      // Eski kiritishlarni tozalab, yangi qoldiqlar bilan prefill qilamiz.
      // Controller'lar hali TextField'larga ulangan bo'lishi mumkin —
      // dispose keyingi frame'da qilinadi.
      final old = List<TextEditingController>.of(_ctrls.values);
      setState(() {
        _products =
            products.where((p) => p['status'] != 'inactive').toList();
        _stocks = stockMap;
        _loading = false;
        _ctrls.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in old) {
          c.dispose();
        }
      });
    } catch (_) {
      if (!mounted) return;
      // Xato jimgina BO'SH sanoq ro'yxati bo'lib ko'rinmasin — ilgari
      // ekran "Mahsulot yo'q" deb turardi va sabab ko'rinmasdi.
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sanoq maʼlumoti yuklanmadi — qayta urinib koʻring'),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  String _productName(dynamic p) {
    final name = p?['name'];
    if (name is Map) return (name['uz'] ?? '').toString();
    return (name ?? '').toString();
  }

  TextEditingController _ctrlFor(int id) {
    return _ctrls.putIfAbsent(
      id,
      () => TextEditingController(
        text: _stocks.containsKey(id) ? '${_stocks[id]}' : '',
      ),
    );
  }

  List<dynamic> get _filtered {
    if (_query.isEmpty) return _products;
    return _products
        .where((p) => _productName(p).toLowerCase().contains(_query))
        .toList();
  }

  /// O'zgargan qatorlar: {product_id, name, old (int|null), new, diff}
  List<Map<String, dynamic>> _changedRows() {
    final changed = <Map<String, dynamic>>[];
    for (final p in _products) {
      final id = p['id'] as int;
      final ctrl = _ctrls[id];
      if (ctrl == null) continue; // qator ochilmagan — o'zgarmagan
      final text = ctrl.text.trim();
      if (text.isEmpty) continue; // bo'sh — tegilmagan deb hisoblanadi
      final value = int.tryParse(text);
      if (value == null || value < 0) continue;
      final hasStock = _stocks.containsKey(id);
      final old = hasStock ? _stocks[id]! : null;
      if (hasStock && value == old) continue;
      if (!hasStock) {
        // Cheksiz mahsulotga son kiritilgan — yangi qoldiq o'rnatiladi
        changed.add({
          'product_id': id,
          'name': _productName(p),
          'old': null,
          'new': value,
          'diff': value,
        });
      } else {
        changed.add({
          'product_id': id,
          'name': _productName(p),
          'old': old,
          'new': value,
          'diff': value - old!,
        });
      }
    }
    return changed;
  }

  String _errMsg(Object e) {
    if (e is DioException && e.response?.data is Map) {
      final msg = (e.response!.data as Map)['message'];
      if (msg != null) return msg.toString();
    }
    return 'Xatolik yuz berdi';
  }

  Future<void> _check() async {
    // SINXRON qo'riqchi: `_submitting` faqat dialog TASDIQLANGANDAN keyin
    // qo'yilardi, ya'ni ikki marta bosilsa ikkita dialog ochilib, ikkalasi
    // ham yuborilardi — sanoq ikki marta qo'llanib, sotilgan porsiyalar
    // qoldiqqa qaytib kelardi.
    if (_submitting) return;
    _submitting = true;
    try {
      await _runCheck();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      } else {
        _submitting = false;
      }
    }
  }

  Future<void> _runCheck() async {
    FocusScope.of(context).unfocus();
    final changed = _changedRows();
    if (changed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O\'zgarish yo\'q')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('O\'zgargan qatorlar (${changed.length})'),
        content: SizedBox(
          width: 400,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: changed.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.borderSoft),
              itemBuilder: (_, i) {
                final r = changed[i];
                final old = r['old'] as int?;
                final newV = r['new'] as int;
                final diff = r['diff'] as int;
                final diffColor =
                    diff < 0 ? AppColors.danger : AppColors.success;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r['name'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        old == null ? 'cheksiz' : '$old',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.arrow_forward_rounded,
                            size: 14, color: AppColors.textFaint),
                      ),
                      Text(
                        '$newV',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          old == null
                              ? 'yangi'
                              : (diff > 0 ? '+$diff' : '$diff'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: diffColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tasdiqlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // `_submitting` allaqachon `_check()` da qo'yilgan; bu yerda faqat
    // UI ni yangilaymiz.
    if (mounted) setState(() {});
    try {
      final res = await ApiService().submitInventory([
        for (final r in changed)
          {
            'product_id': r['product_id'],
            'actual_count': r['new'],
          },
      ]);
      if (!mounted) return;
      final n = (res['changed'] as num?)?.toInt() ?? changed.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$n ta to\'g\'irlandi'),
          backgroundColor: AppColors.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errMsg(e)), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchC,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Mahsulot izlash...',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: AppColors.textMuted),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _searchC.clear(),
                    ),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: _query.isEmpty
                      ? Icons.checklist_rounded
                      : Icons.search_off_rounded,
                  title: _query.isEmpty
                      ? 'Mahsulot yo\'q'
                      : 'Hech narsa topilmadi',
                  subtitle:
                      _query.isEmpty ? null : '"${_searchC.text}" bo\'yicha',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildRow(list[i]),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _check,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.checklist_rounded, size: 18),
              label: const Text(
                'Tekshirish',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(dynamic p) {
    final id = p['id'] as int;
    final hasStock = _stocks.containsKey(id);
    final count = _stocks[id];

    return KCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _productName(p),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      hasStock
                          ? Icons.inventory_2_rounded
                          : Icons.all_inclusive_rounded,
                      size: 12,
                      color:
                          hasStock ? AppColors.textMuted : AppColors.info,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasStock ? 'Hozirgi: $count ta' : 'Hozirgi: cheksiz',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            hasStock ? AppColors.textMuted : AppColors.info,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _ctrlFor(id),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                hintText: hasStock ? null : '—',
                suffixText: 'ta',
                suffixStyle: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
