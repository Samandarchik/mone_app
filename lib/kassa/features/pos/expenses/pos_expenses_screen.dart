import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/business_day.dart';
import '../../../core/widgets/tutorial_widgets.dart';

class PosExpensesScreen extends StatefulWidget {
  const PosExpensesScreen({super.key});
  @override
  State<PosExpensesScreen> createState() => _PosExpensesScreenState();
}

class _PosExpensesScreenState extends State<PosExpensesScreen> {
  List<dynamic> _expenses = [];
  List<dynamic> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Server xatosini KO'RSATADI. Ilgari `catch (_) {}` edi: 2 000 000 so'mlik
  /// xarajat yozilmay qolsa ham hech narsa ko'rinmasdi va kunlik foyda
  /// o'sha summaga oshib ketardi.
  void _showApiError(Object error) {
    if (!mounted) return;
    var msg = 'Saqlanmadi';
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        msg = data['message'].toString();
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _load() async {
    // Ish kuni (02:00 chegarasi): kechasi kiritilgan xarajat o'sha
    // kechning ro'yxatida qoladi.
    final today = businessTodayStr();
    // Ikkala so'rov MUSTAQIL yuklanadi. Ilgari bitta Future.wait ichida edi:
    // kassir tokenida finance ruxsati bo'lmagani uchun ro'yxat 403 qaytarsa,
    // kategoriya so'rovi natijasi ham bekor bo'lib, "Qo'shish" tugmasi
    // "kategoriya yo'q" deb o'lik qolardi.
    final results = await Future.wait<List<dynamic>?>([
      ApiService()
          .getFinanceExpenses(today)
          .then<List<dynamic>?>((v) => v)
          .catchError((_) => null),
      ApiService()
          .getExpenseCategories()
          .then<List<dynamic>?>((v) => v)
          .catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _expenses = results[0] ?? _expenses;
      _categories = results[1] ?? _categories;
      _loading = false;
    });
  }

  int get _total {
    int sum = 0;
    for (final e in _expenses) {
      sum += (e['amount'] as int? ?? 0);
    }
    return sum;
  }

  Future<void> _add() async {
    if (_categories.isEmpty) {
      // Ilgari bu yerda JIMGINA `return` edi: kategoriya bo'lmasa tugma
      // "ishlamayotgandek" ko'rinardi. POS foydalanuvchisida kategoriya
      // yaratish huquqi yo'q, shuning uchun avval qayta yuklab ko'riladi,
      // baribir bo'sh bo'lsa — sababi aniq aytiladi.
      await _load();
      if (!mounted) return;
      if (_categories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Xarajat kategoriyasi yo\'q — admin Xarajatlar bo\'limidan kategoriya qo\'shishi kerak'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }
    final amtC = TextEditingController();
    final descC = TextEditingController();
    int selectedCatId = _categories.first['id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Xarajat qo\'shish'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedCatId,
                  decoration: const InputDecoration(labelText: 'Kategoriya'),
                  items: _categories
                      .map<DropdownMenuItem<int>>(
                        (c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['name_uz'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setS(() => selectedCatId = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtC,
                  decoration: const InputDecoration(
                    labelText: 'Summa',
                    suffixText: 'so\'m',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descC,
                  decoration: const InputDecoration(labelText: 'Izoh'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () async {
                final amount = parseIntField(amtC.text) ?? 0;
                // Ilgari `if (amount <= 0) return;` bilan JIMGINA chiqib
                // ketilardi: dialog ochiq qolar, tugma ishlamagandek
                // ko'rinardi va nima noto'g'ri ekani aytilmasdi. Ko'p
                // hollarda sabab "200 000" kabi bo'sh joyli yozuv edi.
                if (amount <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Summa faqat butun son boʻlishi kerak'),
                    backgroundColor: Colors.red,
                  ));
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await ApiService()
                      .createExpense(selectedCatId, amount, descC.text);
                } catch (e) { _showApiError(e); }
                _load();
              },
              child: const Text('Qo\'shish'),
            ),
          ],
        ),
      ),
    );
  }

  /// Xarajatni o'chirish — server faqat joriy OCHIQ smena ichidagi yozuvni
  /// o'chiradi (smena yopilgach hisobot muzlaydi), rad etsa sababi snackbar'da.
  Future<void> _delete(Map e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xarajatni o\'chirish'),
        content: Text(
            '${e['description'] ?? 'Xarajat'} — ${formatMoney(e['amount'] ?? 0, suffix: ' so\'m')}\nO\'chirilsinmi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteExpense(e['id'] as int);
    } catch (e) {
      _showApiError(e);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Header + total
          Padding(
            padding: EdgeInsets.fromLTRB(context.gutter,
                context.isTabletUi ? 16 : 12, context.gutter, 8),
            child: Row(
              children: [
                Text(
                  'Xarajatlar',
                  style: TextStyle(
                      fontSize: context.isTabletUi ? 26 : 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      letterSpacing: -0.4),
                ),
                const SizedBox(width: 8),
                const TutorialHelpButton('pos.expenses', size: 26),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.trending_down_rounded,
                          size: 13, color: AppColors.danger),
                      const SizedBox(width: 4),
                      Text(
                        formatMoney(_total, suffix: ' so\'m'),
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _expenses.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Bugun xarajat yo\'q',
                    subtitle: 'Pastdagi tugma orqali xarajat qo\'shing',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: KMaxWidth(
                      maxWidth:
                          context.isTabletUi ? 760 : double.infinity,
                      child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          context.gutter, 0, context.gutter, 90),
                      itemCount: _expenses.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = _expenses[i];
                        final catName = e['category_name'] is Map
                            ? (e['category_name']['uz'] ?? '')
                            : '';
                        return KCard(
                          padding: const EdgeInsets.all(12),
                          shadow: AppShadows.xs,
                          child: Row(
                            children: [
                              const IconAvatar(
                                icon: Icons.receipt_long_rounded,
                                color: AppColors.warning,
                                size: 40,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e['description'] ?? 'Xarajat',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      catName,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '- ${formatMoney(e['amount'] ?? 0, suffix: ' so\'m')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppColors.danger),
                                tooltip: 'O\'chirish',
                                onPressed: () => _delete(e),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-pos-expenses',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Qo\'shish'),
      ),
    );
  }
}
