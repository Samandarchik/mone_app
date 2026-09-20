// core2/ui/reports/report_widgets.dart — hisobot ekranlari uchun umumiy
// vidjetlar: davr tanlagich (Bugun / Kecha / Shu hafta / Shu oy / O'tgan oy /
// Oraliq…, har hisobot uchun SharedPreferences'da eslab qolinadi),
// «Excel (CSV)» AppBar amali, yuklanish/bo'sh/xato holatlari, telefon uchun
// gorizontal suriladigan jadval konteyneri (≥900 px da kengaygan),
// xulosa plitkalari va kamomad (qizil) / ortiqcha (yashil) ranglari.
//
// Format QOIDASI: son/pul/miqdor FAQAT `core2/core_format.dart` orqali.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/ui/reports/report_logic.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Ekran keng (kompyuter/planshet) — jadval qisilmaydi, ikki panel mumkin.
bool coreWideScreen(BuildContext context) =>
    MediaQuery.of(context).size.width >= 900;

/// Kamomad / manfiy qiymat — mavzuning semantik «error» rangi.
Color coreShortageColor(BuildContext context) =>
    Theme.of(context).colorScheme.error;

/// Ortiqcha / musbat qiymat (Material 3 da semantik «success» yo'q).
const Color kCoreSurplus = Color(0xFF2E7D32);

Color coreSurplusColor(BuildContext context) => kCoreSurplus;

/// Manfiy — qizil, musbat — yashil, 0 — oddiy rang.
Color coreSignColor(BuildContext context, num v) => v < 0
    ? coreShortageColor(context)
    : (v > 0 ? coreSurplusColor(context) : Colors.black87);

// ───────────────────────── Davr (eslab qolinadi) ─────────────────────────

const String _kPeriodPrefix = 'core_report_period_';

/// Hisobot uchun saqlangan davr (topilmasa [fallback]).
Future<CorePeriod> coreLoadPeriod(String reportKey,
    {CorePeriodPreset fallback = CorePeriodPreset.thisMonth}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = CorePeriod.decode(prefs.getString('$_kPeriodPrefix$reportKey'));
    if (saved != null) return saved;
  } catch (_) {
    // SharedPreferences yo'q/xato — standart davr bilan davom etamiz.
  }
  return CorePeriod.of(fallback);
}

/// Tanlangan davrni shu hisobot uchun eslab qolish (xatolar yutiladi).
Future<void> coreSavePeriod(String reportKey, CorePeriod period) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kPeriodPrefix$reportKey', period.encode());
  } catch (_) {
    // eslab qolinmasa ham ekran ishlayveradi
  }
}

/// Davr tugmasi: bosilsa shablonlar ro'yxati + «Oraliq…» ochiladi.
class CorePeriodBar extends StatelessWidget {
  final CorePeriod period;
  final ValueChanged<CorePeriod> onChanged;
  const CorePeriodBar({super.key, required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final p = await showCorePeriodSheet(context, period);
        if (p != null) onChanged(p);
      },
      icon: const Icon(Icons.date_range, size: 18),
      label: Text(period.fullLabel, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Davr tanlash varag'i (pastdan chiqadi).
Future<CorePeriod?> showCorePeriodSheet(
    BuildContext context, CorePeriod current) async {
  final picked = await showModalBottomSheet<CorePeriod>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      final presets = [
        CorePeriodPreset.today,
        CorePeriodPreset.yesterday,
        CorePeriodPreset.thisWeek,
        CorePeriodPreset.thisMonth,
        CorePeriodPreset.lastMonth,
      ];
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Davr', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final p in presets)
              ListTile(
                dense: true,
                leading: Icon(
                  current.preset == p
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: kCoreAccentDark,
                  size: 20,
                ),
                title: Text(CorePeriod.of(p).label),
                subtitle: Text(
                  '${coreDateUz(CorePeriod.of(p).from)} – ${coreDateUz(CorePeriod.of(p).to)}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                onTap: () => Navigator.pop(ctx, CorePeriod.of(p)),
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_calendar_outlined,
                  color: kCoreAccentDark, size: 20),
              title: const Text('Oraliq…'),
              onTap: () => Navigator.pop(ctx, const _CustomMarker()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (picked == null) return null;
  if (picked is! _CustomMarker) return picked;
  if (!context.mounted) return null;
  final now = DateTime.now();
  final r = await showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 3),
    lastDate: DateTime(now.year + 1),
    initialDateRange: DateTimeRange(
      start: DateTime.tryParse(current.from) ?? now,
      end: DateTime.tryParse(current.to) ?? now,
    ),
  );
  return r == null ? null : CorePeriod.range(r.start, r.end);
}

/// «Oraliq…» tanlanganini bildiruvchi ichki belgi.
class _CustomMarker extends CorePeriod {
  const _CustomMarker()
      : super(preset: CorePeriodPreset.custom, from: '', to: '');
}

// ───────────────────────── AppBar: Excel (CSV) ─────────────────────────

/// AppBar amali «Excel (CSV)» — tor ekranda faqat ikonka.
class CoreExcelAction extends StatelessWidget {
  final VoidCallback? onPressed;
  const CoreExcelAction({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 480) {
      return IconButton(
        onPressed: onPressed,
        tooltip: 'Excel (CSV)',
        icon: const Icon(Icons.table_view_outlined),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.table_view_outlined, size: 18),
        label: const Text('Excel (CSV)'),
        style: TextButton.styleFrom(foregroundColor: kCoreAccentDark),
      ),
    );
  }
}

// ───────────────────────── Holatlar ─────────────────────────

/// Yuklanish / xato / bo'sh / ma'lumot — hamma hisobotda bir xil.
class CoreReportBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final bool empty;
  final String emptyText;
  final VoidCallback? onRetry;
  final Widget child;

  const CoreReportBody({
    super.key,
    required this.loading,
    required this.child,
    this.error,
    this.empty = false,
    this.emptyText = 'Ma\'lumot yo\'q',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) return CoreErrorView(message: error!, onRetry: onRetry);
    if (loading) return const Center(child: CircularProgressIndicator.adaptive());
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 44, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }
    return child;
  }
}

// ───────────────────────── Jadval va kartalar ─────────────────────────

/// Jadval konteyneri: telefonda O'Z ichida gorizontal suriladi, ≥900 px da
/// butun kenglikni egallaydi.
class CoreReportTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double minWidth;

  const CoreReportTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 0,
  });

  @override
  Widget build(BuildContext context) {
    final table = DataTable(
      headingRowHeight: 38,
      dataRowMinHeight: 34,
      dataRowMaxHeight: 46,
      columnSpacing: 14,
      headingTextStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
      dataTextStyle: const TextStyle(fontSize: 12.5, color: Colors.black87),
      columns: columns,
      rows: rows,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: minWidth > 0 ? minWidth : c.maxWidth),
            child: table,
          ),
        ),
      ),
    );
  }
}

/// Xulosa plitkasi (hujjatlar soni, kamomad, ortiqcha…).
class CoreSummaryTile {
  final String label;
  final String value;
  final Color? color;
  const CoreSummaryTile(this.label, this.value, {this.color});
}

/// Xulosa sarlavhasi — telefonda ikki ustun, kengda bir qator.
class CoreSummaryHeader extends StatelessWidget {
  final List<CoreSummaryTile> tiles;
  const CoreSummaryHeader({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final wide = coreWideScreen(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          for (final t in tiles)
            SizedBox(
              width: wide ? 200 : (MediaQuery.of(context).size.width - 90) / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t.label,
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(t.value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: t.color ?? Colors.black87)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Filtrlar qatori (davr + dropdownlar) — oq kartada.
class CoreFilterBar extends StatelessWidget {
  final List<Widget> children;
  const CoreFilterBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// Pul ustunlari yashirilgani haqida kichik kulrang eslatma.
class CoreNoCostNote extends StatelessWidget {
  const CoreNoCostNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Text(
          'Summalar yashirilgan — «stock.cost.view» ruxsati yo\'q',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      );
}

/// Ro'yxat/karta ichidagi kichik kulrang SH5 atamasi.
Widget coreSh5Subtitle(String text) => Text(
      text,
      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
    );

/// Narx o'zgarishi matni + rangi (|Δ| ≥ 5 % bo'lsa rangli).
Widget corePriceChangeText(BuildContext context, double? pct) {
  final trend = corePriceTrend(pct);
  final color = switch (trend) {
    CorePriceTrend.up => coreShortageColor(context), // qimmatlashdi — yomon
    CorePriceTrend.down => coreSurplusColor(context), // arzonlashdi — yaxshi
    _ => Colors.black54,
  };
  return Text(
    corePriceTrendText(pct),
    style: TextStyle(
      fontSize: 12.5,
      color: color,
      fontWeight: trend == CorePriceTrend.up || trend == CorePriceTrend.down
          ? FontWeight.bold
          : FontWeight.normal,
    ),
  );
}
