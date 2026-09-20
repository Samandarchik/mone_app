// core2/ui/reports_ui.dart — «Hisobotlar» bo'limi bosh ekrani (ReportsUi,
// perm `report.view`): hisobot TANLASH ro'yxati, 4 guruhga bo'lingan —
// «Qoldiq va aylanma», «Kamomad va hisobdan chiqarish», «Xaridlar»,
// «Ishlab chiqarish va tannarx». Har bir hisobot o'z ekranida
// (`core2/ui/reports/*.dart`), SH5 atamasi kichik kulrang ostyozuv bilan.
//
// Ekranlar: Aylanma (`/reports/turnover`), Qoldiq qiymati
// (`/reports/stock-value`), Kamomad va ortiqcha (`/reports/inventory-diff`),
// Hisobdan chiqarish (`/reports/issues`), Defitsit (`/reports/deficit`),
// Xaridlar va narx tarixi (`/reports/purchases`), Ishlab chiqarish
// (`/reports/production`), Tannarx va food cost (`/reports/cost`),
// Kalkulyatsiya kartasi (`/reports/recipe-cost`). Hammasida «Excel (CSV)».
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/reports/cost_report_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/deficit_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/inventory_diff_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/issues_report_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/production_report_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/purchases_report_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/recipe_cost_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/stock_value_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports/turnover_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Ro'yxatdagi bitta hisobot.
class _ReportEntry {
  final String title;
  final String sh5; // SH5 dagi nomi (kichik kulrang ostyozuv)
  final String hint;
  final IconData icon;
  final Widget Function() open;
  const _ReportEntry({
    required this.title,
    required this.sh5,
    required this.hint,
    required this.icon,
    required this.open,
  });
}

class _ReportGroup {
  final String title;
  final List<_ReportEntry> items;
  const _ReportGroup(this.title, this.items);
}

const List<_ReportGroup> _groups = [
  _ReportGroup('Qoldiq va aylanma', [
    _ReportEntry(
      title: 'Aylanma',
      sh5: 'Оборотная ведомость',
      hint: 'Boshi + kirim − chiqim = oxiri (tovar bo\'yicha)',
      icon: Icons.swap_vert,
      open: TurnoverUi.new,
    ),
    _ReportEntry(
      title: 'Qoldiq qiymati',
      sh5: 'Ведомость остатков',
      hint: 'Sana bo\'yicha ombor qoldig\'ining qiymati',
      icon: Icons.inventory_outlined,
      open: StockValueUi.new,
    ),
  ]),
  _ReportGroup('Kamomad va hisobdan chiqarish', [
    _ReportEntry(
      title: 'Kamomad va ortiqcha',
      sh5: 'Сличительная ведомость',
      hint: 'Sanoq farqlari: ombor, tovar va oy kesimida',
      icon: Icons.balance,
      open: InventoryDiffUi.new,
    ),
    _ReportEntry(
      title: 'Hisobdan chiqarish',
      sh5: 'Списание — sabablar bo\'yicha',
      hint: 'Sabab (kontragent) → ombor → tovar, summalar bilan',
      icon: Icons.delete_sweep_outlined,
      open: IssuesReportUi.new,
    ),
    _ReportEntry(
      title: 'Defitsit',
      sh5: 'Partiyasiz chiqim',
      hint: 'Qoldiqsiz yechilgan tovarlar (manfiy qoldiq sababi)',
      icon: Icons.remove_circle_outline,
      open: DeficitUi.new,
    ),
  ]),
  _ReportGroup('Xaridlar', [
    _ReportEntry(
      title: 'Xaridlar va narx tarixi',
      sh5: 'Приход · narxlar',
      hint: 'Yetkazuvchi × tovar: summa, o\'rtacha narx, o\'zgarish %',
      icon: Icons.local_shipping_outlined,
      open: PurchasesReportUi.new,
    ),
  ]),
  _ReportGroup('Ishlab chiqarish va tannarx', [
    _ReportEntry(
      title: 'Ishlab chiqarish',
      sh5: 'Акт выпуска · Переработка',
      hint: 'Mahsulot × ombor: miqdor, ingredient tannarxi, 1 birlik',
      icon: Icons.factory_outlined,
      open: ProductionReportUi.new,
    ),
    _ReportEntry(
      title: 'Tannarx va food cost',
      sh5: 'Себестоимость',
      hint: 'Taom: tannarx, sotuv, foyda va food cost %',
      icon: Icons.restaurant_menu,
      open: CostReportUi.new,
    ),
    _ReportEntry(
      title: 'Kalkulyatsiya kartasi',
      sh5: 'Калькуляционная карта',
      hint: 'Retsept bo\'yicha 1 birlik tannarxi (sana tanlab)',
      icon: Icons.calculate_outlined,
      open: RecipeCostUi.new,
    ),
  ]),
];

class ReportsUi extends StatelessWidget {
  const ReportsUi({super.key});

  @override
  Widget build(BuildContext context) {
    final canView =
        context.select<CoreSession, bool>((s) => s.has(CorePerms.reportView));
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Hisobotlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: CoreConnectGate(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (!canView)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  'Hisobotlarni ko\'rish uchun ruxsat yo\'q (report.view) —'
                  ' administratorga ayting',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            for (final g in _groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Text(g.title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: kCoreAccentDark)),
              ),
              if (wide)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in g.items)
                      SizedBox(width: 420, child: _card(context, e)),
                  ],
                )
              else
                for (final e in g.items) _card(context, e),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, _ReportEntry e) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ListTile(
          onTap: () => context.push(e.open()),
          leading: CircleAvatar(
            backgroundColor: kCoreAccent.withValues(alpha: 0.2),
            child: Icon(e.icon, color: kCoreAccentDark, size: 20),
          ),
          title: Text(e.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.sh5,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(e.hint, style: const TextStyle(fontSize: 12)),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
