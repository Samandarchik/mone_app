// core2/ui/widgets/good_search.dart — «Oson rejim» formalarining UMUMIY tovar
// tanlash qismlari (quick_doc_ui.dart dan ajratildi, distribute_ui.dart ham
// shulardan foydalanadi):
//  • CoreFreqGood — shu ombor + shu amal uchun eng ko'p ishlatilgan tovarlar
//    («Tez-tez» chiplari), kunlik SharedPreferences keshi bilan;
//  • CoreFreqChips — o'sha chiplar qatori;
//  • CoreGoodSearchPanel — server qidiruvi (250 ms debounce) + natijalar
//    ro'yxati (qatorda shu ombordagi qoldiq).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';

/// Shu ombor + shu amal uchun eng ko'p ishlatilgan tovar.
///
/// Server `GET /docs` qatorlarni QAYTARMAYDI (ro'yxat yengil bo'lishi uchun),
/// shuning uchun oxirgi 30 kunning eng so'nggi [_maxDetail] hujjati
/// `GET /docs/{id}` bilan olinadi va tovarlar MIJOZ tomonda sanaladi.
/// Server yukini cheklash: ro'yxat bir sahifa ([_maxDocs] dan oshmaydi),
/// natija SharedPreferences'da KUNLIK keshlanadi (kalit: ombor + tur).
class CoreFreqGood {
  final int goodId;
  final String name;
  final String baseUnit;
  final int count;

  const CoreFreqGood({
    required this.goodId,
    required this.name,
    required this.baseUnit,
    this.count = 0,
  });

  /// Chipda uzun nom kesiladi.
  String get shortName =>
      name.length <= 22 ? name : '${name.substring(0, 21)}…';

  Map<String, dynamic> toJson() =>
      {'id': goodId, 'n': name, 'u': baseUnit, 'c': count};

  factory CoreFreqGood.fromJson(Map<String, dynamic> j) => CoreFreqGood(
        goodId: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['n'] ?? '').toString(),
        baseUnit: (j['u'] ?? 'mpcs').toString(),
        count: (j['c'] as num?)?.toInt() ?? 0,
      );

  static const int _maxDocs = 200; // serverdan so'raladigan eng ko'p hujjat
  static const int _maxDetail = 30; // qatorlari o'qiladigan hujjat soni
  static const int _chipCount = 12;

  static Future<List<CoreFreqGood>> load({
    required CoreDocService service,
    required int skladId,
    required String type,
  }) async {
    final key = 'core_freq_${type}_$skladId';
    final prefs = await SharedPreferences.getInstance();
    final today = coreToday();
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['day'] == today) {
          return (m['items'] as List)
              .whereType<Map>()
              .map((e) => CoreFreqGood.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {/* kesh buzilgan — qayta hisoblanadi */}
    }
    try {
      final page = await service.list(
        type: type,
        status: CoreDocStatus.posted,
        sklad: skladId,
        dateFrom: coreDaysAgo(30),
        limit: 100,
      );
      final docs = page.items.take(_maxDocs).take(_maxDetail).toList();
      final count = <int, int>{};
      final names = <int, String>{};
      final units = <int, String>{};
      const chunk = 6;
      for (var i = 0; i < docs.length; i += chunk) {
        final part = docs.sublist(i, (i + chunk).clamp(0, docs.length));
        final full = await Future.wait(part.map((d) async {
          try {
            return await service.get(d.id);
          } catch (_) {
            return null;
          }
        }));
        for (final doc in full) {
          if (doc == null) continue;
          for (final l in doc.lines) {
            if (l.goodId <= 0) continue;
            count[l.goodId] = (count[l.goodId] ?? 0) + 1;
            names[l.goodId] = l.goodName;
            units[l.goodId] = coreBaseUnitOf(l.unit);
          }
        }
      }
      final top = count.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final out = [
        for (final e in top.take(_chipCount))
          CoreFreqGood(
            goodId: e.key,
            name: names[e.key] ?? 'Tovar #${e.key}',
            baseUnit: units[e.key] ?? 'mpcs',
            count: e.value,
          ),
      ];
      await prefs.setString(
          key,
          jsonEncode({
            'day': today,
            'items': [for (final f in out) f.toJson()],
          }));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Chip bosilganda to'liq tovar kartochkasi (keshdan yoki serverdan).
  static Future<CoreGood> resolve(
      CoreDictProvider dict, CoreFreqGood f) async {
    var good = dict.goodById(f.goodId);
    if (good == null || good.partial) {
      await dict.ensureGoods([f.goodId]);
      good = dict.goodById(f.goodId);
    }
    return good ??
        CoreGood(
            id: f.goodId, name: f.name, baseUnit: f.baseUnit, partial: true);
  }
}

/// «Tez-tez:» chiplari qatori.
class CoreFreqChips extends StatelessWidget {
  final List<CoreFreqGood> items;
  final ValueChanged<CoreFreqGood> onPick;
  const CoreFreqChips({super.key, required this.items, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Tez-tez:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          for (final f in items)
            ActionChip(
              label: Text(f.shortName, style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.white,
              onPressed: () => onPick(f),
            ),
        ],
      ),
    );
  }
}

/// Tovar qidiruvi: maydon + natijalar (qatorda [skladId] qoldig'i).
/// Tanlangach maydon o'zi tozalanadi va fokusda qoladi.
class CoreGoodSearchPanel extends StatefulWidget {
  final int? skladId;
  final ValueChanged<CoreGood> onPicked;
  final String hint;
  final bool autofocus;

  /// Natijalar ro'yxatining eng katta balandligi (telefon tartibi).
  final double? maxHeight;

  const CoreGoodSearchPanel({
    super.key,
    required this.onPicked,
    this.skladId,
    this.hint = 'Tovar qidirish…',
    this.autofocus = false,
    this.maxHeight = 300,
  });

  @override
  State<CoreGoodSearchPanel> createState() => _CoreGoodSearchPanelState();
}

class _CoreGoodSearchPanelState extends State<CoreGoodSearchPanel> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _seq = 0;
  List<CoreGood> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      _seq++;
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(v));
  }

  Future<void> _run(String q) async {
    final my = ++_seq;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await context.read<CoreDictProvider>().searchGoods(q, limit: 30);
      if (!mounted || my != _seq) return;
      setState(() => _results = r);
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() => _error = coreErrorUz(e).title);
    } finally {
      if (mounted && my == _seq) setState(() => _searching = false);
    }
  }

  void _clear() {
    _debounce?.cancel();
    _seq++;
    _ctrl.clear();
    setState(() {
      _results = const [];
      _error = null;
    });
    _focus.requestFocus();
  }

  void _pick(CoreGood g) {
    widget.onPicked(g);
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (_) {
            if (_results.isNotEmpty) _pick(_results.first);
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : (_ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear), onPressed: _clear)),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        if (_ctrl.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _resultsBox(),
        ],
      ],
    );
  }

  Widget _resultsBox() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_error!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_searching ? 'Qidirilmoqda…' : 'Topilmadi',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      );
    }
    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _tile(_results[i]),
      ),
    );
  }

  Widget _tile(CoreGood g) {
    final sklad = widget.skladId;
    final row = sklad == null
        ? null
        : context.select<CoreStockProvider, CoreStockRow?>(
            (s) => s.rowFor(sklad, g.id));
    return ListTile(
      dense: true,
      title: Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          coreUnitUz(g.baseUnit),
          if (g.isComplect) 'taom',
          if (g.isSemi) 'yarim tayyor',
        ].join(' · '),
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: row == null
          ? null
          : Text(
              coreQtyUnitUz(row.qty, row.baseUnit),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: row.qty < 0 ? Colors.red.shade700 : Colors.black87,
              ),
            ),
      onTap: () => _pick(g),
    );
  }
}
