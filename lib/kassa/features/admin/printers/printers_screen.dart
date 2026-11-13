import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

class PrintersScreen extends StatefulWidget {
  const PrintersScreen({super.key});
  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  List<dynamic> _printers = [];
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  Map<String, dynamic> _receiptPrinter = {};
  // Mone bo'limlari (Bar, Oshxona…): printer bo'limga biriktiriladi — bo'lim
  // mahsulotlari shu printerga chiqadi va o'sha bo'lim omboridan yechiladi.
  List<dynamic> _departments = [];
  bool _loading = true;
  String? _error;

  /// 0 — printerlar, 1 — kategoriya biriktiruvi, 2 — mahsulot biriktiruvi.
  ///
  /// Ilgari uchalasi bitta uzun ro'yxatda edi: 130 ta mahsulotni aylantirib
  /// o'tmasdan printer sozlamasiga yetib bo'lmasdi.
  int _tab = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final printers = await ApiService().getPrinters();
      final menu = await ApiService().getMenu(force: true);
      Map<String, dynamic> receipt = {};
      List<dynamic> deps = [];
      try {
        deps = await ApiService().getMoneDepartments();
      } catch (_) {
        // Mone ulanmagan kassa — bo'limlar yo'q.
      }
      try {
        receipt = await ApiService().getReceiptPrinter();
      } catch (_) {
        // Chek printeri sozlanmagan bo'lishi mumkin — bu xato emas.
      }
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _categories = menu['categories'] ?? [];
        _products = menu['products'] ?? [];
        _receiptPrinter = receipt;
        _departments = deps;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(e);
      });
    }
  }

  String _printerName(Object? id) {
    if (id == null) return '';
    final p = _printers.where((p) => p['id'] == id);
    if (p.isEmpty) return '';
    return (p.first['name'] ?? '').toString();
  }

  String _name(Object? raw) {
    if (raw is Map) return (raw['uz'] ?? raw['ru'] ?? '').toString();
    return '${raw ?? ''}';
  }

  // ===================== Printer tanlash =====================

  /// Printerni ro'yxatdan tanlash. Dropdown o'rniga — barmoq bilan
  /// bosiladigan katta qatorlar, har birida IP manzili ko'rinib turadi.
  Future<({bool ok, int? id})> _pickPrinter({
    required String title,
    required String nullLabel,
    required String nullHint,
    int? current,
  }) async {
    final result = await showModalBottomSheet<({bool ok, int? id})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.only(
          top: MediaQuery.of(ctx).size.height * 0.12,
        ),
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
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
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                children: [
                  AdminTile(
                    title: nullLabel,
                    subtitle: nullHint,
                    icon: Icons.block_rounded,
                    color: AppColors.textMuted,
                    trailing: current == null
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, (ok: true, id: null)),
                  ),
                  for (final p in _printers)
                    AdminTile(
                      title: (p['name'] ?? '').toString(),
                      subtitle: (p['address'] ?? '').toString(),
                      icon: Icons.print_rounded,
                      color: AppColors.success,
                      trailing: current == p['id']
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary)
                          : null,
                      onTap: () =>
                          Navigator.pop(ctx, (ok: true, id: p['id'] as int)),
                    ),
                ],
              ),
            ),
            SafeArea(top: false, child: const SizedBox(height: 6)),
          ],
        ),
      ),
    );
    return result ?? (ok: false, id: null);
  }

  Future<void> _changeReceiptPrinter() async {
    if (_printers.isEmpty) {
      showErr(context, 'Avval printer qo‘shing');
      return;
    }
    final r = await _pickPrinter(
      title: 'Chek printeri',
      nullLabel: 'Avtomatik',
      nullHint: '«chek» nomli printer o‘zi topiladi',
      current: _receiptPrinter['printer_id'] as int?,
    );
    if (!r.ok) return;
    try {
      await ApiService().setReceiptPrinter(r.id);
      if (mounted) showOk(context, 'Chek printeri o‘zgartirildi');
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    }
    _load();
  }

  Future<void> _assignCategory(Map<String, dynamic> category) async {
    final r = await _pickPrinter(
      title: _name(category['name']),
      nullLabel: 'Printerga chiqmasin',
      nullHint: 'Bu kategoriya uchun oshxona cheki chiqmaydi',
      current: category['printer_station_id'] as int?,
    );
    if (!r.ok) return;
    try {
      await ApiService()
          .updateCategory(category['id'] as int, {'printer_station_id': r.id ?? 0});
      if (mounted) showOk(context, 'Saqlandi');
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    }
    _load();
  }

  Future<void> _assignProduct(Map<String, dynamic> product) async {
    final r = await _pickPrinter(
      title: _name(product['name']),
      nullLabel: 'Kategoriya bo‘yicha',
      nullHint: 'Kategoriyasiga biriktirilgan printerga chiqadi',
      current: product['printer_station_id'] as int?,
    );
    if (!r.ok) return;
    try {
      await ApiService()
          .updateProduct(product['id'] as int, {'printer_station_id': r.id ?? 0});
      if (mounted) showOk(context, 'Saqlandi');
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    }
    _load();
  }

  Future<void> _openPrinterForm({Map<String, dynamic>? printer}) async {
    final editing = printer != null;
    final nameC = TextEditingController(text: printer?['name']?.toString() ?? '');
    final addrC =
        TextEditingController(text: printer?['address']?.toString() ?? '');

    final saved = await showAdminForm(
      context: context,
      title: editing ? (printer['name']?.toString() ?? 'Printer') : 'Yangi printer',
      subtitle: 'Tarmoqdagi chek printeri (ESC/POS)',
      icon: Icons.print_rounded,
      color: AppColors.success,
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Nomi',
          controller: nameC,
          hint: 'Bar, Oshxona, Chek…',
          icon: Icons.label_outline_rounded,
          autofocus: !editing,
        ),
        AdminField(
          label: 'Tarmoq manzili',
          controller: addrC,
          hint: '192.168.0.51:9100',
          helper: 'Printerning IP manzili va porti',
          icon: Icons.lan_outlined,
        ),
      ],
      submitLabel: editing ? 'Saqlash' : 'Qo‘shish',
      onSubmit: () async {
        if (nameC.text.trim().isEmpty || addrC.text.trim().isEmpty) {
          showErr(context, 'Nomi va manzilini to‘ldiring');
          return false;
        }
        try {
          if (editing) {
            await ApiService().updatePrinter(printer['id'] as int, {
              'name': nameC.text.trim(),
              'address': addrC.text.trim(),
            });
          } else {
            await ApiService()
                .createPrinter(nameC.text.trim(), addrC.text.trim());
          }
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
      onDelete: editing
          ? () async {
              try {
                await ApiService().deletePrinter(printer['id'] as int);
                return true;
              } catch (e) {
                if (mounted) showErr(context, apiErrorText(e));
                return false;
              }
            }
          : null,
      deleteLabel: 'Printerni o‘chirish',
    );

    if (saved == true) {
      if (mounted) showOk(context, 'Saqlandi');
      _load();
    }
  }

  // ===================== Ko'rinish =====================

  @override
  Widget build(BuildContext context) {
    final assigned =
        _categories.where((c) => c['printer_station_id'] != null).length;

    return AdminPage(
      subtitle: '${_printers.length} printer · $assigned/${_categories.length} '
          'kategoriya biriktirilgan',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: _load,
      segments: const ['Printerlar', 'Kategoriyalar', 'Mahsulotlar'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() {
        _tab = i;
        _query = '';
      }),
      onSearchChanged:
          _tab == 0 ? null : (v) => setState(() => _query = v),
      searchHint: _tab == 1 ? 'Kategoriya nomi…' : 'Mahsulot nomi…',
      primaryAction: _tab == 0
          ? AdminAction(
              label: 'Printer qo‘shish',
              icon: Icons.add_rounded,
              onPressed: () => _openPrinterForm(),
            )
          : null,
      child: switch (_tab) {
        0 => _printersTab(),
        1 => _categoriesTab(),
        _ => _productsTab(),
      },
    );
  }

  /// Bo'limga printer tanlash: tanlangan printer shu bo'limga o'tadi, avval
  /// shu bo'limdagi boshqa printerlar bo'shatiladi (bitta bo'lim — bitta printer).
  Future<void> _pickDepartmentPrinter(Map<String, dynamic> dept) async {
    final deptId = dept['id'] as int;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('${dept['name']} — printer')),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Printer yo‘q'),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            for (final p in _printers.whereType<Map>())
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text('${p['name']}'),
                subtitle: Text('${p['address']}'),
                trailing: p['mone_department_id'] == deptId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, p['id'] as int),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      for (final p in _printers.whereType<Map>()) {
        if (p['mone_department_id'] == deptId && p['id'] != picked) {
          await ApiService().updatePrinter(p['id'] as int, {'mone_department_id': 0});
        }
      }
      if (picked > 0) {
        await ApiService().updatePrinter(picked, {'mone_department_id': deptId});
      }
      if (!mounted) return;
      showOk(context, 'Saqlandi');
    } catch (e) {
      if (!mounted) return;
      showErr(context, apiErrorText(e));
    }
    _load();
  }

  Widget _printersTab() {
    final name = (_receiptPrinter['name'] ?? '').toString();
    final address = (_receiptPrinter['address'] ?? '').toString();
    final auto = _receiptPrinter['auto'] == true;
    final none = name.isEmpty;

    return AdminList(
      children: [
        const AdminGroupLabel(text: 'Mijoz cheki'),
        AdminTile(
          title: none ? 'Tanlanmagan' : name,
          subtitle: none
              ? 'Avval printer qo‘shing, so‘ng shu yerdan tanlang'
              : (auto ? '$address · avtomatik tanlandi' : address),
          icon: Icons.receipt_long_rounded,
          color: none ? AppColors.textMuted : AppColors.info,
          badge: none
              ? null
              : const StatusBadge(label: 'CHEK', color: AppColors.info),
          onTap: _changeReceiptPrinter,
        ),
        if (_departments.isNotEmpty) ...[
          const AdminGroupLabel(text: 'Bo‘limlar (Mone)'),
          for (final d in _departments.whereType<Map>())
            AdminTile(
              title: '${d['name'] ?? ''}${d['is_default'] == true ? ' · asosiy' : ''}',
              subtitle: (d['printers'] ?? '').toString().isEmpty
                  ? 'Printer tanlanmagan — kategoriya printeriga chiqadi'
                  : 'Printer: ${d['printers']}',
              icon: Icons.account_tree_rounded,
              color: (d['printers'] ?? '').toString().isEmpty
                  ? AppColors.textMuted
                  : AppColors.success,
              onTap: () => _pickDepartmentPrinter(Map<String, dynamic>.from(d)),
            ),
        ],
        const AdminGroupLabel(text: 'Tarmoqdagi printerlar'),
        if (_printers.isEmpty)
          AdminEmpty(
            icon: Icons.print_disabled_rounded,
            title: 'Printer qo‘shilmagan',
            message: 'Oshxona va chek printerlarini IP manzili bilan '
                'qo‘shing (masalan 192.168.0.51:9100).',
            actionLabel: 'Printer qo‘shish',
            onAction: () => _openPrinterForm(),
            color: AppColors.success,
          )
        else
          for (final p in _printers)
            AdminTile(
              title: (p['name'] ?? '').toString(),
              subtitle: (p['address'] ?? '').toString(),
              icon: Icons.print_rounded,
              color: AppColors.success,
              onTap: () => _openPrinterForm(printer: Map<String, dynamic>.from(p)),
              menu: const [
                AdminMenuItem(
                  value: 'edit',
                  label: 'Tahrirlash',
                  icon: Icons.edit_outlined,
                ),
                AdminMenuItem(
                  value: 'delete',
                  label: 'O‘chirish',
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
              ],
              onMenuSelected: (v) async {
                if (v == 'edit') {
                  _openPrinterForm(printer: Map<String, dynamic>.from(p));
                  return;
                }
                final ok = await confirmAction(
                  context: context,
                  title: 'Printerni o‘chirish',
                  message: '${p['name']} o‘chirilsinmi?',
                  confirmLabel: 'O‘chirish',
                  danger: true,
                );
                if (ok != true) return;
                try {
                  await ApiService().deletePrinter(p['id'] as int);
                  if (!mounted) return;
                  showOk(context, 'O‘chirildi');
                } catch (e) {
                  if (!mounted) return;
                  showErr(context, apiErrorText(e));
                }
                _load();
              },
            ),
      ],
    );
  }

  Widget _categoriesTab() {
    final q = _query.trim().toLowerCase();
    final list = _categories
        .whereType<Map>()
        .where((c) => q.isEmpty || _name(c['name']).toLowerCase().contains(q))
        .toList();

    if (list.isEmpty) {
      return const AdminEmpty(
        icon: Icons.category_outlined,
        title: 'Kategoriya topilmadi',
      );
    }

    return AdminList(
      header: const _Hint(
        'Kategoriyadagi mahsulotlar buyurtma qilinganda qaysi printerdan '
        'chiqishini belgilaydi.',
      ),
      children: [
        for (final c in list)
          Builder(
            builder: (_) {
              final id = c['printer_station_id'];
              final pname = _printerName(id);
              return AdminTile(
                title: _name(c['name']),
                subtitle: id == null
                    ? 'Printerga chiqmaydi'
                    : 'Printer: $pname',
                icon: id == null ? Icons.print_disabled_rounded : Icons.print_rounded,
                color: id == null ? AppColors.textMuted : AppColors.success,
                badge: id == null
                    ? const StatusBadge(
                        label: 'YO‘Q', color: AppColors.textMuted)
                    : StatusBadge(label: pname, color: AppColors.success),
                onTap: () => _assignCategory(Map<String, dynamic>.from(c)),
              );
            },
          ),
      ],
    );
  }

  Widget _productsTab() {
    final q = _query.trim().toLowerCase();
    final widgets = <Widget>[];

    for (final cat in _categories.whereType<Map>()) {
      final catProducts = _products
          .whereType<Map>()
          .where((p) => p['category_id'] == cat['id'])
          .where((p) => q.isEmpty || _name(p['name']).toLowerCase().contains(q))
          .toList();
      if (catProducts.isEmpty) continue;

      final catPrinter = _printerName(cat['printer_station_id']);
      widgets.add(
        AdminGroupLabel(
          text: _name(cat['name']),
          trailing: catPrinter.isEmpty
              ? null
              : StatusBadge(label: catPrinter, color: AppColors.textFaint),
        ),
      );
      for (final p in catProducts) {
        final override = p['printer_station_id'];
        widgets.add(
          AdminTile(
            title: _name(p['name']),
            subtitle: override == null
                ? (catPrinter.isEmpty
                    ? 'Kategoriya bo‘yicha — printer yo‘q'
                    : 'Kategoriya bo‘yicha — $catPrinter')
                : 'Alohida: ${_printerName(override)}',
            icon: Icons.fastfood_rounded,
            color: override == null ? AppColors.textFaint : AppColors.warning,
            badge: override == null
                ? null
                : StatusBadge(
                    label: _printerName(override),
                    color: AppColors.warning,
                  ),
            onTap: () => _assignProduct(Map<String, dynamic>.from(p)),
          ),
        );
      }
    }

    if (widgets.isEmpty) {
      return const AdminEmpty(
        icon: Icons.fastfood_outlined,
        title: 'Mahsulot topilmadi',
      );
    }

    return AdminList(
      header: const _Hint(
        'Faqat kategoriyasidan BOSHQA printerga chiqishi kerak bo‘lgan '
        'mahsulotga alohida printer tanlang.',
      ),
      children: widgets,
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.infoSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
