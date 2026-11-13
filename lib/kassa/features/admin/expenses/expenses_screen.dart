import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';
import '../../../core/utils/business_day.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<dynamic> _expenses = [];
  List<dynamic> _categories = [];
  bool _loading = true;

  /// 0 — xarajatlar, 1 — kategoriyalar.
  int _tab = 0;
  /// Ish kuni (02:00 chegarasi) — kechasi 00:30 da ochilsa kechagi kun.
  DateTime _date = businessToday();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateKey => _date.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    // Ikkala so'rov MUSTAQIL yuklanadi. Ilgari bitta Future.wait ichida edi:
    // biri (masalan, ruxsat yo'qligidan 403) yiqilsa, ikkinchisining natijasi
    // ham bekor bo'lib, "Qo'shish" tugmasi "kategoriya yo'q" deb o'lik qolardi.
    final results = await Future.wait<List<dynamic>?>([
      ApiService()
          .getFinanceExpenses(_dateKey)
          .then<List<dynamic>?>((v) => v)
          .catchError((_) => null),
      ApiService()
          .getExpenseCategories()
          .then<List<dynamic>?>((v) => v)
          .catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _expenses = results[0] ?? [];
      _categories = results[1] ?? _categories;
      _loading = false;
    });
  }

  int get _total {
    var sum = 0;
    for (final e in _expenses.whereType<Map>()) {
      final a = e['amount'];
      if (a is num) sum += a.toInt();
    }
    return sum;
  }

  String _catName(Map c) =>
      (c['name_uz'] ?? c['name'] ?? '').toString();

  // ===================== Xarajat =====================

  Future<void> _addExpense() async {
    if (_categories.isEmpty) {
      // Kategoriya bo'lmasa (baza tozalangandan keyin) tugma umuman
      // "ishlamayotgandek" ko'rinmasin — sababi aytiladi va darhol
      // kategoriya yaratish taklif qilinadi.
      await _load();
      if (!mounted) return;
      if (_categories.isEmpty) {
        showErr(context, 'Avval xarajat kategoriyasini qo‘shing');
        await _addCategory();
        if (!mounted || _categories.isEmpty) return;
      }
    }

    final amountC = TextEditingController();
    final descC = TextEditingController();
    var catId = _categories.first['id'] as int;

    final saved = await showAdminForm(
      context: context,
      title: 'Yangi xarajat',
      subtitle: AdminDateBar.label(_date),
      icon: Icons.payments_rounded,
      color: AppColors.danger,
      fields: (ctx, refresh) => [
        AdminChoice<int>(
          label: 'Kategoriya',
          value: catId,
          items: {
            for (final c in _categories.whereType<Map>())
              c['id'] as int: _catName(c),
          },
          onChanged: (v) => refresh(() => catId = v),
        ),
        AdminField(
          label: 'Summa',
          controller: amountC,
          hint: '0',
          suffixText: 'so‘m',
          icon: Icons.attach_money_rounded,
          keyboardType: TextInputType.number,
          formatters: const [MoneyInputFormatter()],
          autofocus: true,
        ),
        AdminField(
          label: 'Izoh',
          controller: descC,
          hint: 'Nima uchun sarflandi?',
          icon: Icons.notes_rounded,
        ),
      ],
      submitLabel: 'Qo‘shish',
      onSubmit: () async {
        final amount = parseIntField(amountC.text) ?? 0;
        if (amount <= 0) {
          showErr(context, 'Summani kiriting');
          return false;
        }
        try {
          await ApiService().createExpense(catId, amount, descC.text.trim());
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
    );

    if (saved == true) {
      if (mounted) showOk(context, 'Xarajat yozildi');
      _load();
    }
  }

  Future<void> _deleteExpense(Map e) async {
    final ok = await confirmAction(
      context: context,
      title: 'Xarajatni o‘chirish',
      message: '${e['description'] ?? 'Xarajat'} — '
          '${formatMoney(e['amount'], suffix: ' so‘m')}',
      confirmLabel: 'O‘chirish',
      danger: true,
    );
    if (ok != true) return;
    try {
      // Server faqat joriy OCHIQ smena ichidagi xarajatni o'chiradi —
      // smena yopilgach rad etadi va sababi ko'rinadi.
      await ApiService().deleteExpense(e['id'] as int);
      if (mounted) showOk(context, 'O‘chirildi');
    } catch (err) {
      if (mounted) showErr(context, apiErrorText(err));
    }
    _load();
  }

  // ===================== Kategoriya =====================

  Future<void> _addCategory() async {
    final nameC = TextEditingController();
    final saved = await showAdminForm(
      context: context,
      title: 'Yangi kategoriya',
      subtitle: 'Xarajatlar shu bo‘yicha guruhlanadi',
      icon: Icons.sell_rounded,
      color: AppColors.warning,
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Kategoriya nomi',
          controller: nameC,
          hint: 'Ijara, kommunal, ish haqi…',
          icon: Icons.label_outline_rounded,
          autofocus: true,
        ),
      ],
      submitLabel: 'Qo‘shish',
      onSubmit: () async {
        if (nameC.text.trim().isEmpty) {
          showErr(context, 'Nomini kiriting');
          return false;
        }
        try {
          await ApiService().createExpenseCategory(nameC.text.trim());
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
    );
    if (saved == true) {
      if (mounted) showOk(context, 'Kategoriya qo‘shildi');
      await _load();
    }
  }

  Future<void> _deleteCategory(Map c) async {
    final ok = await confirmAction(
      context: context,
      title: 'Kategoriyani o‘chirish',
      message: '«${_catName(c)}» o‘chirilsinmi?',
      confirmLabel: 'O‘chirish',
      danger: true,
    );
    if (ok != true) return;
    try {
      await ApiService().deleteExpenseCategory(c['id'] as int);
      if (mounted) showOk(context, 'O‘chirildi');
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    }
    _load();
  }

  // ===================== Ko'rinish =====================

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      subtitle: _tab == 0
          ? '${_expenses.length} ta yozuv · ${formatMoney(_total, suffix: ' so‘m')}'
          : '${_categories.length} ta kategoriya',
      loading: _loading,
      onRefresh: _load,
      segments: const ['Xarajatlar', 'Kategoriyalar'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() => _tab = i),
      primaryAction: _tab == 0
          ? AdminAction(
              label: 'Xarajat qo‘shish',
              icon: Icons.add_rounded,
              onPressed: _addExpense,
              color: AppColors.danger,
            )
          : AdminAction(
              label: 'Kategoriya',
              icon: Icons.add_rounded,
              onPressed: _addCategory,
              color: AppColors.warning,
            ),
      toolbar: _tab == 0
          ? AdminDateBar(
              date: _date,
              onChanged: (d) {
                setState(() {
                  _date = d;
                  _loading = true;
                });
                _load();
              },
            )
          : null,
      child: _tab == 0 ? _expensesTab() : _categoriesTab(),
    );
  }

  Widget _expensesTab() {
    if (_expenses.isEmpty) {
      return AdminEmpty(
        icon: Icons.receipt_long_outlined,
        title: 'Bu kunda xarajat yo‘q',
        message: 'Ijara, mahsulot xaridi, ish haqi — barcha chiqimlarni '
            'shu yerga yozsangiz, kunlik foyda to‘g‘ri hisoblanadi.',
        actionLabel: 'Xarajat qo‘shish',
        onAction: _addExpense,
        color: AppColors.danger,
      );
    }

    // Kategoriya bo'yicha jami — qayerga ko'p ketayotgani darrov ko'rinadi.
    final byCat = <String, int>{};
    for (final e in _expenses.whereType<Map>()) {
      final n = e['category_name'] is Map
          ? (e['category_name']['uz'] ?? '').toString()
          : (e['category_name'] ?? '').toString();
      final a = e['amount'];
      byCat[n] = (byCat[n] ?? 0) + (a is num ? a.toInt() : 0);
    }
    final top = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AdminList(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.dangerTint,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.dangerSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(Icons.trending_down_rounded,
                      color: AppColors.danger, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JAMI XARAJAT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textFaint,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney(_total, suffix: ' so‘m'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.danger,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (top.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: top.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        top[i].key,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        formatMoney(top[i].value),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const AdminGroupLabel(text: 'Yozuvlar'),
        ],
      ),
      children: [
        for (final e in _expenses.whereType<Map>())
          AdminTile(
            title: (e['description'] ?? '').toString().trim().isEmpty
                ? 'Izohsiz xarajat'
                : e['description'].toString(),
            subtitle: e['category_name'] is Map
                ? (e['category_name']['uz'] ?? '').toString()
                : (e['category_name'] ?? '').toString(),
            icon: Icons.receipt_long_rounded,
            color: AppColors.danger,
            value: '−${formatMoney(e['amount'])}',
            valueHint: 'so‘m',
            valueColor: AppColors.danger,
            menu: const [
              AdminMenuItem(
                value: 'delete',
                label: 'O‘chirish',
                icon: Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
            ],
            onMenuSelected: (_) => _deleteExpense(e),
          ),
      ],
    );
  }

  Widget _categoriesTab() {
    if (_categories.isEmpty) {
      return AdminEmpty(
        icon: Icons.sell_outlined,
        title: 'Kategoriya yo‘q',
        message: 'Xarajatlarni guruhlash uchun kamida bitta kategoriya kerak.',
        actionLabel: 'Kategoriya qo‘shish',
        onAction: _addCategory,
        color: AppColors.warning,
      );
    }
    return AdminList(
      children: [
        for (final c in _categories.whereType<Map>())
          AdminTile(
            title: _catName(c),
            icon: Icons.sell_rounded,
            color: AppColors.warning,
            menu: const [
              AdminMenuItem(
                value: 'delete',
                label: 'O‘chirish',
                icon: Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
            ],
            onMenuSelected: (_) => _deleteCategory(c),
          ),
      ],
    );
  }
}
