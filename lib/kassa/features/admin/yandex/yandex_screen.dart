import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/utils/search_fold.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// Yandex Eda stop-listi: qaysi taom sotuvda, qaysi biri stopda.
///
/// Stop — taom Yandex menyusida QOLADI, faqat qoldig'i 0 deb ko'rsatiladi
/// (Yandex ilovasida «нет в наличии»). Stopdan olinganda darhol qaytadi.
/// Yandex qoldiqni o'zi tortadi, shuning uchun o'zgarish ilovada bir necha
/// daqiqadan keyin ko'rinadi.
class YandexScreen extends StatefulWidget {
  const YandexScreen({super.key});

  @override
  State<YandexScreen> createState() => _YandexScreenState();
}

class _YandexScreenState extends State<YandexScreen> {
  static const _yandexRed = Color(0xFFFC3F1D);

  List<Map<String, dynamic>> _items = [];
  bool _stopAll = false;
  bool _shiftOpen = true;
  bool _loading = true;
  String? _error;
  int _segment = 0;
  String _query = '';

  /// Hozir o'zgartirilayotgan mahsulotlar (switch ikki marta bosilmasin).
  final Set<int> _busy = {};
  bool _stopAllBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiService().getYandexMenuPreview();
      if (!mounted) return;
      setState(() {
        _items = (d['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _stopAll = d['stop_all'] == true;
        _shiftOpen = d['shift_open'] != false;
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

  Future<void> _setStopped(Map<String, dynamic> it, bool stopped) async {
    final id = it['id'] as int;
    setState(() {
      _busy.add(id);
      it['stopped'] = stopped;
    });
    try {
      await ApiService().setProductYandex(id, {'stopped': stopped});
      if (mounted) {
        showOk(
          context,
          stopped
              ? '${it['name']} — stopga qo‘yildi'
              : '${it['name']} — sotuvga qaytdi',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => it['stopped'] = !stopped);
      showErr(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _setStopAll(bool stop) async {
    final ok = await confirmAction(
      context: context,
      title: stop ? 'Hammasini stopga qo‘yish' : 'Stopni olib tashlash',
      message: stop
          ? 'Yandex Eda’dagi ${_items.length} ta taomning hammasi stopga '
                'tushadi, yangi zakaz qabul qilinmaydi.'
          : 'Yandex Eda’da sotuv qayta ochiladi. Alohida stopga qo‘yilgan '
                'taomlar stopda qoladi.',
      confirmLabel: stop ? 'Ha, stop' : 'Ha, ochilsin',
      danger: stop,
    );
    if (ok != true) return;
    setState(() => _stopAllBusy = true);
    try {
      await ApiService().setYandexStopAll(stop);
      if (!mounted) return;
      setState(() => _stopAll = stop);
      showOk(
        context,
        stop ? 'Yandex’da hammasi stopda' : 'Yandex’da sotuv ochildi',
      );
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _stopAllBusy = false);
    }
  }

  bool _matches(Map<String, dynamic> it) {
    if (_query.isEmpty) return true;
    final q = searchFold(_query);
    return searchFold('${it['name'] ?? ''}').contains(q) ||
        searchFold('${it['category'] ?? ''}').contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final stopped = _items.where((e) => e['stopped'] == true).toList();
    final selling = _items.where((e) => e['stopped'] != true).toList();
    final shown = (_segment == 0 ? selling : stopped).where(_matches).toList();
    final empty = selling
        .where((e) => ((e['stock'] as num?)?.toInt() ?? 0) <= 0)
        .length;

    return AdminPage(
      subtitle: '${_items.length} ta taom · ${stopped.length} tasi stopda',
      accent: _yandexRed,
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: _load,
      onSearchChanged: (v) => setState(() => _query = v.trim()),
      searchHint: 'Taom yoki kategoriya…',
      segments: ['Sotuvda (${selling.length})', 'Stopda (${stopped.length})'],
      segmentIndex: _segment,
      onSegmentChanged: (i) => setState(() => _segment = i),
      actions: [
        AdminIconAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Yangilash',
          onPressed: _load,
        ),
      ],
      toolbar: _loading || _error != null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StopAllCard(
                  stopAll: _stopAll,
                  shiftOpen: _shiftOpen,
                  busy: _stopAllBusy,
                  onChanged: _setStopAll,
                ),
                if (empty > 0) ...[
                  const SizedBox(height: 8),
                  _EmptyStockBanner(count: empty),
                ],
              ],
            ),
      child: _items.isEmpty
          ? const AdminEmpty(
              icon: Icons.delivery_dining_outlined,
              title: 'Yandex’ga hali taom chiqarilmagan',
              message:
                  'Menyu → mahsulot kartochkasida «Yandex Eda» ni '
                  'yoqing — taom shu yerda paydo bo‘ladi.',
            )
          : shown.isEmpty
          ? AdminEmpty(
              icon: _segment == 0
                  ? Icons.block_rounded
                  : Icons.check_circle_outline_rounded,
              title: _query.isNotEmpty
                  ? 'Hech narsa topilmadi'
                  : (_segment == 0 ? 'Hamma taom stopda' : 'Stopda taom yo‘q'),
              message: _query.isNotEmpty
                  ? 'Boshqa so‘z bilan qidirib ko‘ring'
                  : (_segment == 0
                        ? 'Taomni sotuvga qaytarish uchun «Stopda» '
                              'bo‘limida switch’ni yoqing'
                        : 'Hamma taom Yandex’da sotilmoqda'),
            )
          : AdminList(
              children: [
                for (final it in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _YandexItemTile(
                      item: it,
                      stopAll: _stopAll,
                      busy: _busy.contains(it['id']),
                      onChanged: (selling) => _setStopped(it, !selling),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Tepadagi katta kalit: butun Yandex savdosini to'xtatish.
class _StopAllCard extends StatelessWidget {
  final bool stopAll;
  final bool shiftOpen;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _StopAllCard({
    required this.stopAll,
    required this.shiftOpen,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = stopAll ? AppColors.danger : AppColors.success;
    final title = stopAll
        ? 'Yandex’da HAMMASI stopda'
        : 'Yandex’da sotuv ochiq';
    final hint = stopAll
        ? 'Hech bir taom sotilmaydi, zakaz qabul qilinmaydi'
        : (shiftOpen
              ? 'Stopdagilardan tashqari hamma taom sotilmoqda'
              : 'Smena yopiq — smena ochilguncha Yandex’da hammasi 0');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            stopAll
                ? Icons.pause_circle_filled_rounded
                : Icons.storefront_rounded,
            color: c,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: stopAll ? AppColors.success : AppColors.danger,
              ),
              onPressed: () => onChanged(!stopAll),
              icon: Icon(
                stopAll ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              label: Text(
                stopAll ? 'Stopni olish' : 'Hammasini stop',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _YandexItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool stopAll;
  final bool busy;

  /// `true` — sotuvda, `false` — stopda.
  final ValueChanged<bool> onChanged;

  const _YandexItemTile({
    required this.item,
    required this.stopAll,
    required this.busy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stopped = item['stopped'] == true;
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final name = '${item['name'] ?? ''}';
    final category = '${item['category'] ?? ''}';
    final price = formatMoney(item['yandex_price']);

    // Qo'lda stop qilinmagan bo'lsa ham Yandex'da ko'rinmasligi mumkin —
    // ogohlantiramiz (qoldiq 0 bo'lsa ham Yandex'da sotilaveradi).
    String? note;
    if (!stopped) {
      if (stopAll) {
        note = 'Umumiy stop yoqilgan';
      } else if (stock <= 0) {
        // Qoldiq 0 taomni AVTO stop qilmaydi — faqat ogohlantirish.
        note = '⚠ Qoldiq 0 — Yandex’da sotilaveradi';
      }
    }

    return AdminTile(
      title: name,
      subtitle: [
        if (category.isNotEmpty) category,
        '$price so‘m',
        ?note,
      ].join(' · '),
      initials: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      color: stopped ? AppColors.danger : AppColors.success,
      highlight: note != null ? AppColors.warning : null,
      trailing: busy
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stopped ? 'Stop' : 'Sotuvda',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: stopped ? AppColors.danger : AppColors.success,
                  ),
                ),
                Switch(
                  value: !stopped,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.success,
                  onChanged: onChanged,
                ),
              ],
            ),
      onTap: () => onChanged(stopped),
    );
  }
}

/// Qoldig'i 0 bo'lgan taomlar haqida ogohlantirish. Ular Yandex'da
/// SOTILAVERADI — stop faqat qo'lda qo'yiladi va qo'lda olinadi.
class _EmptyStockBanner extends StatelessWidget {
  final int count;
  const _EmptyStockBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count ta taomning qoldig‘i 0, lekin Yandex’da '
              'sotilmoqda. Kerak bo‘lsa qo‘lda stopga qo‘ying.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
