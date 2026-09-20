// core2/ui/reports/report_logic.dart — hisobot ekranlarining SOF mantig'i
// (Flutter vidjetlarisiz, shuning uchun test bilan qoplanadi):
//   • davr shablonlari (Bugun / Kecha / Shu hafta / Shu oy / O'tgan oy /
//     Oraliq…) — hafta DUSHANBAdan boshlanadi;
//   • davrni SharedPreferences uchun matnga o'rash/ochish;
//   • Excel (CSV) fayl nomi: `kamomad_2026-08-20_2026-09-19.csv`;
//   • narx o'zgarishi (±5 %) chegarasi va yo'nalishi;
//   • `show_cost:false` da pul ustunlarini olib tashlash;
//   • server xatosi → o'zbekcha matn (404 = eski binar, 403 = ruxsat).
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

// ───────────────────────── Davr ─────────────────────────

enum CorePeriodPreset { today, yesterday, thisWeek, thisMonth, lastMonth, custom }

/// Hisobot davri: shablon + `YYYY-MM-DD` chegaralar (ikkalasi ham kiradi).
class CorePeriod {
  final CorePeriodPreset preset;
  final String from;
  final String to;

  const CorePeriod({required this.preset, required this.from, required this.to});

  /// Shablondan davr yasash (test uchun [now] beriladi).
  factory CorePeriod.of(CorePeriodPreset preset, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (preset) {
      case CorePeriodPreset.today:
        return CorePeriod(preset: preset, from: _iso(today), to: _iso(today));
      case CorePeriodPreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        return CorePeriod(preset: preset, from: _iso(y), to: _iso(y));
      case CorePeriodPreset.thisWeek:
        // Hafta DUSHANBAdan (DateTime.weekday: dushanba = 1).
        final start = today.subtract(Duration(days: today.weekday - 1));
        return CorePeriod(preset: preset, from: _iso(start), to: _iso(today));
      case CorePeriodPreset.thisMonth:
        return CorePeriod(
            preset: preset,
            from: _iso(DateTime(today.year, today.month, 1)),
            to: _iso(today));
      case CorePeriodPreset.lastMonth:
        final firstThis = DateTime(today.year, today.month, 1);
        final lastPrev = firstThis.subtract(const Duration(days: 1));
        return CorePeriod(
            preset: preset,
            from: _iso(DateTime(lastPrev.year, lastPrev.month, 1)),
            to: _iso(lastPrev));
      case CorePeriodPreset.custom:
        // Standart oraliq — oxirgi 30 kun.
        final start = today.subtract(const Duration(days: 30));
        return CorePeriod(preset: preset, from: _iso(start), to: _iso(today));
    }
  }

  /// Qo'lda tanlangan oraliq.
  factory CorePeriod.range(DateTime start, DateTime end) => CorePeriod(
        preset: CorePeriodPreset.custom,
        from: _iso(start),
        to: _iso(end),
      );

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Tugmada ko'rinadigan nom.
  String get label {
    switch (preset) {
      case CorePeriodPreset.today:
        return 'Bugun';
      case CorePeriodPreset.yesterday:
        return 'Kecha';
      case CorePeriodPreset.thisWeek:
        return 'Shu hafta';
      case CorePeriodPreset.thisMonth:
        return 'Shu oy';
      case CorePeriodPreset.lastMonth:
        return 'O\'tgan oy';
      case CorePeriodPreset.custom:
        return from == to
            ? coreDateUz(from)
            : '${coreDateUz(from)} – ${coreDateUz(to)}';
    }
  }

  /// To'liq matn: «Shu oy · 01.09.2026 – 21.09.2026».
  String get fullLabel => preset == CorePeriodPreset.custom
      ? label
      : '$label · ${coreDateUz(from)} – ${coreDateUz(to)}';

  /// SharedPreferences uchun: «thisMonth» / «custom|2026-08-01|2026-08-31».
  String encode() => preset == CorePeriodPreset.custom
      ? 'custom|$from|$to'
      : preset.name;

  /// [encode] ning teskarisi; noto'g'ri matn → null.
  static CorePeriod? decode(String? raw, {DateTime? now}) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.first == 'custom') {
      if (parts.length != 3) return null;
      final a = DateTime.tryParse(parts[1]);
      final b = DateTime.tryParse(parts[2]);
      if (a == null || b == null) return null;
      return CorePeriod.range(a, b);
    }
    for (final p in CorePeriodPreset.values) {
      if (p.name == parts.first) return CorePeriod.of(p, now: now);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CorePeriod &&
      other.preset == preset &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);

  @override
  String toString() => encode();
}

// ───────────────────────── Excel (CSV) fayl nomi ─────────────────────────

/// Hisobot kaliti + davr → fayl nomi: `kamomad_2026-08-20_2026-09-19.csv`.
/// Bir kunlik hisobot (qoldiq qiymati, kalkulyatsiya) — `..._2026-09-19.csv`.
/// [suffix] — qo'shimcha belgi (masalan tovar nomi) kerak bo'lganda.
String coreCsvFileName(String key, {String? from, String? to, String? suffix}) {
  final parts = <String>[_slug(key)];
  if (suffix != null && suffix.trim().isNotEmpty) parts.add(_slug(suffix));
  final a = (from ?? '').trim();
  final b = (to ?? '').trim();
  if (a.isNotEmpty) parts.add(a);
  if (b.isNotEmpty && b != a) parts.add(b);
  return '${parts.join('_')}.csv';
}

/// Fayl nomiga yaramaydigan belgilarni olib tashlash (kirillcha nom ham).
String _slug(String raw) {
  final s = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'''[\\/:*?"<>|]'''), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll('\'', '');
  final cut = s.length > 40 ? s.substring(0, 40) : s;
  return cut.isEmpty ? 'hisobot' : cut;
}

/// Fayl allaqachon bo'lsa nom oxiriga `_2`, `_3`… qo'shadi.
String coreCsvNameWithIndex(String name, int index) {
  if (index <= 1) return name;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '${name}_$index';
  return '${name.substring(0, dot)}_$index${name.substring(dot)}';
}

// ───────────────────────── Narx o'zgarishi ─────────────────────────

/// Narx o'zgarishi yo'nalishi: qimmatlashgan / arzonlashgan / sezilarsiz /
/// solishtirib bo'lmaydi (oldingi davrda xarid yo'q — server `null` beradi).
enum CorePriceTrend { up, down, flat, unknown }

/// Chegara: |o'zgarish| ≥ 5 % bo'lsa rang va ▲/▼ ko'rsatiladi.
const double kCorePriceTrendPct = 5.0;

CorePriceTrend corePriceTrend(double? pct,
    {double threshold = kCorePriceTrendPct}) {
  if (pct == null) return CorePriceTrend.unknown;
  if (pct >= threshold) return CorePriceTrend.up;
  if (pct <= -threshold) return CorePriceTrend.down;
  return CorePriceTrend.flat;
}

/// «▲ 11,7 %» / «▼ 6,2 %» / «0,4 %» / «—».
String corePriceTrendText(double? pct) {
  if (pct == null) return '—';
  final arrow = switch (corePriceTrend(pct)) {
    CorePriceTrend.up => '▲ ',
    CorePriceTrend.down => '▼ ',
    _ => '',
  };
  return '$arrow${coreNumUz(pct.abs(), maxFrac: 1)} %';
}

// ───────────────────────── Ustunlar (show_cost) ─────────────────────────

/// Jadval ustuni: sarlavha, pul ustunimi (`show_cost:false` da yashiriladi),
/// o'ngga tekislanadimi.
class CoreReportColumn {
  final String title;
  final bool money;
  final bool numeric;
  const CoreReportColumn(this.title, {this.money = false, this.numeric = false});
}

/// `show_cost:false` (ruxsat `stock.cost.view` yo'q) — pul ustunlari tushadi.
List<CoreReportColumn> coreReportColumns(
        List<CoreReportColumn> all, bool showCost) =>
    showCost ? all : all.where((c) => !c.money).toList(growable: false);

// ───────────────────────── Xato matni ─────────────────────────

/// Server xatosi → foydalanuvchi tiliga: 404/405 — eski binar (yangi
/// hisobotlar hali qo'yilmagan), 403 — ruxsat, qolgani `display`.
String coreReportErrorText(Object e) {
  final err = e is CoreApiException ? e : CoreClient.wrap(e);
  if (err.status == 404 || err.status == 405) {
    return 'Server yangilanmagan — administratorga ayting';
  }
  if (err.status == 403) {
    final perm = err.perm.isNotEmpty ? err.perm : 'report.view';
    return 'Ruxsat yo\'q (ruxsat: $perm)';
  }
  return err.display;
}
