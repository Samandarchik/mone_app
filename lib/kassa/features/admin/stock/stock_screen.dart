import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import 'inventory_screen.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<dynamic> _products = [];
  Map<int, int> _stocks = {}; // product_id → count
  bool _loading = true;
  final TextEditingController _searchC = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all | limited | unlimited | low | empty

  @override
  void initState() {
    super.initState();
    _load();
    AppState().addListener(_onChanged);
    _searchC.addListener(() {
      final q = _searchC.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchC.dispose();
    AppState().removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
      if (mounted) {
        setState(() {
          _products = products;
          _stocks = stockMap;
          _loading = false;
        });
      }
    } catch (_) {
      // Xato jimgina BO'SH ombor bo'lib ko'rinmasin — ilgari ekran
      // "Mahsulot yo'q" deb turardi va sabab hech qayerda ko'rinmasdi.
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ombor maʼlumoti yuklanmadi — qayta urinib koʻring'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  List<dynamic> get _filtered {
    Iterable<dynamic> list = _products;

    // Filter
    if (_filter != 'all') {
      list = list.where((p) {
        final id = p['id'] as int;
        final hasStock = _stocks.containsKey(id);
        final realCount = AppState().getStockCount(id) ?? _stocks[id];
        switch (_filter) {
          case 'limited':
            return hasStock;
          case 'unlimited':
            return !hasStock;
          case 'low':
            return hasStock && realCount != null && realCount > 0 && realCount < 10;
          case 'empty':
            return hasStock && (realCount ?? 0) <= 0;
          default:
            return true;
        }
      });
    }

    // Search
    if (_query.isNotEmpty) {
      list = list.where((p) {
        final name = p['name'];
        if (name is Map) {
          for (final v in name.values) {
            if (v is String && v.toLowerCase().contains(_query)) return true;
          }
        } else if (name is String &&
            name.toLowerCase().contains(_query)) {
          return true;
        }
        return false;
      });
    }
    return list.toList();
  }

  void _openSubScreen(String title, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(title: Text(title)),
          body: screen,
        ),
      ),
    );
  }

  // Qoldiq nazorati rejimi — tizim sinovda ekan, qoldiqsiz ham sotishga
  // ruxsat (qoldiq minusga tushadi). Qiymat AppState'dan (server eventi).
  Widget _stockModeCard() {
    final soft = AppState().stockSoft;
    final color = soft ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: soft ? AppColors.warning.withValues(alpha: 0.10) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: soft ? AppColors.warning : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(soft ? Icons.warning_amber_rounded : Icons.verified_rounded,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  soft ? 'Yumshoq qoldiq (test rejimi)' : 'Qat\'iy qoldiq nazorati',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  soft
                      ? 'Qoldiq yetmasa ham chek uriladi, qoldiq minusga tushadi'
                      : 'Qoldiq yetmasa sotilmaydi va POS\'da ko\'rinmaydi',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Switch(value: soft, onChanged: _setStockMode),
        ],
      ),
    );
  }

  Future<void> _setStockMode(bool soft) async {
    try {
      await ApiService().setStockMode(soft ? 'soft' : 'strict');
      AppState().stockSoft = soft; // event ham keladi, lekin darhol ko'rsatamiz
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rejim o\'zgarmadi: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: AppColors.primary),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        side: const BorderSide(color: AppColors.border),
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.success,
    ));
  }

  /// Server xatosini ko'rsatadi — ilgari bu chaqiruvlar umuman
  /// `try/catch` siz edi va xato jimgina yo'qolardi.
  void _showApiError(Object error) {
    var msg = 'Amal bajarilmadi';
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        msg = data['message'].toString();
      }
    }
    _toast(msg, error: true);
  }

  void _showEditDialog(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final name = product['name']?['uz'] ?? '';
    final hasStock = _stocks.containsKey(id);
    // JONLI qoldiq — `AppState` WebSocket orqali yangilanib turadi.
    //
    // Ilgari `_load()` paytida olingan SURAT ishlatilardi. Ekran ochiq
    // turganda oshxona 9 ta sotsa, dialog hali ham eski 12 ni ko'rsatardi
    // va admin boshqa sabab bilan "Saqlash"ni bossa, sotilgan 9 ta porsiya
    // qoldiqqa QAYTIB kelardi (setStock absolyut yozadi).
    final currentCount = AppState().getStockCount(id) ?? _stocks[id] ?? 0;
    final controller = TextEditingController(
        text: hasStock ? '$currentCount' : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Qoldiq soni',
                  hintText: 'Bo\'sh = cheksiz',
                  suffixText: 'ta',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasStock
                          ? Icons.numbers_rounded
                          : Icons.all_inclusive_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasStock
                          ? 'Hozir: $currentCount ta'
                          : 'Hozir: cheksiz',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (hasStock)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                // `try/catch` SHART: ilgari xato ushlanmasdi va tarmoq
                // uzilsa hech narsa ko'rinmasdi — admin mahsulot cheksiz
                // bo'ldi deb o'ylab ketardi, POS esa uni sotmayverardi.
                try {
                  await ApiService().removeStock(id);
                  _toast('Qoldiq kuzatuvi olib tashlandi');
                } catch (e) {
                  _showApiError(e);
                }
                _load();
              },
              icon: const Icon(Icons.all_inclusive_rounded,
                  size: 16, color: AppColors.warning),
              label: const Text('Cheksiz qilish',
                  style: TextStyle(color: AppColors.warning)),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor')),
          FilledButton(
            onPressed: () async {
              final raw = controller.text.trim();
              // Ilgari "1 500" yoki "1.5" kiritilsa IKKALA shart ham
              // bajarilmasdi: dialog yopilar, hech narsa yozilmas, xabar
              // ham chiqmasdi. Admin qoldiq saqlandi deb o'ylardi.
              final count = raw.isEmpty
                  ? null
                  : int.tryParse(raw.replaceAll(RegExp(r'[\s\u00A0]'), ''));
              if (raw.isNotEmpty && (count == null || count < 0)) {
                _toast('Qoldiq faqat musbat butun son bo‘lishi kerak',
                    error: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                if (count != null) {
                  await ApiService().setStock(id, count);
                  _toast('Qoldiq saqlandi: $count ta');
                } else {
                  await ApiService().removeStock(id);
                  _toast('Qoldiq kuzatuvi olib tashlandi');
                }
              } catch (e) {
                _showApiError(e);
              }
              _load();
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = _filtered;

    return Column(
      children: [
        // Quick actions: inventory
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.checklist_rounded,
                  label: 'Inventarizatsiya',
                  onTap: () => _openSubScreen(
                      'Inventarizatsiya', const InventoryScreen()),
                ),
              ),
            ],
          ),
        ),

        // Qoldiq nazorati rejimi (test davrida minusga ruxsat)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _stockModeCard(),
        ),

        // Search box
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
                      onPressed: () {
                        _searchC.clear();
                      },
                    ),
            ),
          ),
        ),

        // Filter chips
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip('Hammasi', 'all', _products.length),
              _filterChip(
                  'Limitli',
                  'limited',
                  _products
                      .where((p) =>
                          _stocks.containsKey(p['id'] as int))
                      .length),
              _filterChip(
                  'Cheksiz',
                  'unlimited',
                  _products
                      .where((p) =>
                          !_stocks.containsKey(p['id'] as int))
                      .length),
              _filterChip(
                'Kam qoldi',
                'low',
                _products.where((p) {
                  final id = p['id'] as int;
                  final c = AppState().getStockCount(id) ?? _stocks[id];
                  return _stocks.containsKey(id) &&
                      c != null &&
                      c > 0 &&
                      c < 10;
                }).length,
                accent: AppColors.warning,
              ),
              _filterChip(
                'Tugagan',
                'empty',
                _products.where((p) {
                  final id = p['id'] as int;
                  final c = AppState().getStockCount(id) ?? _stocks[id];
                  return _stocks.containsKey(id) && (c ?? 0) <= 0;
                }).length,
                accent: AppColors.danger,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // List
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: _query.isEmpty
                      ? Icons.inventory_2_rounded
                      : Icons.search_off_rounded,
                  title: _query.isEmpty
                      ? 'Mahsulot yo\'q'
                      : 'Hech narsa topilmadi',
                  subtitle: _query.isEmpty
                      ? null
                      : '"${_searchC.text}" bo\'yicha',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _buildTile(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTile(dynamic p) {
    final id = p['id'] as int;
    final name = p['name']?['uz'] ?? '';
    final price = p['price'] as int? ?? 0;
    final hasStock = _stocks.containsKey(id);
    final count = _stocks[id] ?? 0;
    final realCount = AppState().getStockCount(id);
    final displayCount = realCount ?? count;

    String subtitle;
    Color countColor;
    IconData statusIcon;
    if (!hasStock) {
      subtitle = 'Cheksiz';
      countColor = AppColors.info;
      statusIcon = Icons.all_inclusive_rounded;
    } else if (displayCount <= 0) {
      subtitle = 'TUGAGAN';
      countColor = AppColors.danger;
      statusIcon = Icons.warning_amber_rounded;
    } else if (displayCount < 10) {
      subtitle = '$displayCount ta — kam qoldi';
      countColor = AppColors.warning;
      statusIcon = Icons.inventory_2_rounded;
    } else {
      subtitle = '$displayCount ta qoldi';
      countColor = AppColors.success;
      statusIcon = Icons.inventory_2_rounded;
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => _showEditDialog(p),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // Stock indicator avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: countColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: hasStock
                    ? Text(
                        '$displayCount',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: countColor,
                          fontSize: 15,
                        ),
                      )
                    : Icon(statusIcon, color: countColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(statusIcon, size: 12, color: countColor),
                        const SizedBox(width: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                              color: countColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${formatMoney(price)} so\'m',
                          style: const TextStyle(
                              color: AppColors.textFaint, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded,
                  size: 18, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value, int count,
      {Color? accent}) {
    final selected = _filter == value;
    final c = accent ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: selected ? c : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : AppColors.surfaceAlt,
                  borderRadius:
                      BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? Colors.white : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
