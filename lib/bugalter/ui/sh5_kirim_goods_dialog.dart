// bugalter/ui/sh5_kirim_goods_dialog.dart — Mone mahsulotini SH5 tovariga
// bog'lash dialogi (PLAN_KIRIM §6): tepada nom o'xshashligi bo'yicha takliflar
// (score bilan), pastda SH5 lug'ati bo'yicha qidiruv (`goods?q=`, 300 ms
// debounce). Mavjud bog'lanish bo'lsa «Bog'lanishni o'chirish» ham bor.
//
// Dialog SERVERGA YOZMAYDI — faqat tanlovni qaytaradi; PUT/DELETE ni chaqirgan
// ekran (sh5_kirim_ui.dart) bajaradi, shunda ro'yxat bir joyda yangilanadi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/bugalter/model/sh5_kirim_model.dart';
import 'package:uz_ai_dev/bugalter/services/sh5_kirim_service.dart';

/// Dialog natijasi: tovar tanlandi yoki bog'lanish o'chirilsin.
enum Sh5KirimPickAction { select, delete }

/// Dialog qaytaradigan natija (bekor qilinsa null).
class Sh5KirimPick {
  final Sh5KirimPickAction action;

  /// [Sh5KirimPickAction.select] uchun — tanlangan SH5 tovari.
  final int sh5Rid;
  final String sh5Name;

  const Sh5KirimPick.select(this.sh5Rid, this.sh5Name)
      : action = Sh5KirimPickAction.select;

  const Sh5KirimPick.delete()
      : action = Sh5KirimPickAction.delete,
        sh5Rid = 0,
        sh5Name = '';
}

/// Bog'lash dialogini ochadi. [item] — bog'lanayotgan Mone mahsuloti.
Future<Sh5KirimPick?> showSh5KirimGoodsDialog(
  BuildContext context, {
  required Sh5KirimItem item,
  required Sh5KirimService service,
}) {
  return showDialog<Sh5KirimPick>(
    context: context,
    builder: (_) => _Sh5KirimGoodsDialog(item: item, service: service),
  );
}

class _Sh5KirimGoodsDialog extends StatefulWidget {
  final Sh5KirimItem item;
  final Sh5KirimService service;

  const _Sh5KirimGoodsDialog({required this.item, required this.service});

  @override
  State<_Sh5KirimGoodsDialog> createState() => _Sh5KirimGoodsDialogState();
}

class _Sh5KirimGoodsDialogState extends State<_Sh5KirimGoodsDialog> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<Sh5KirimGood> _goods = const [];
  bool _loading = false;
  String? _error;

  // So'nggi yuborilgan so'rov matni — kech kelgan javob yangisini bosmasin.
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Mahsulot nomi bilan darhol bir qidiruv — ko'p holda javob shu yerda.
    _search.text = widget.item.name;
    _query = widget.item.name;
    _load(widget.item.name);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(value));
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.service.searchGoods(q);
      if (!mounted || q != _query) return;
      setState(() {
        _goods = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _pick(int rid, String name) {
    Navigator.pop(context, Sh5KirimPick.select(rid, name));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final map = item.map;
    final suggestions = item.suggestions;
    return AlertDialog(
      backgroundColor: Colors.white,
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (item.qtyDisplay.isNotEmpty) item.qtyDisplay,
              if (map != null && map.sh5Name.isNotEmpty)
                'hozir: ${map.sh5Name}',
            ].join(' · '),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.normal,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 440,
        child: Column(
          children: [
            // Takliflar — faqat bog'lanish yo'q bo'lganda (tasdiqlash uchun).
            if (map == null && suggestions.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Takliflar (nom o\'xshashligi)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              for (final s in suggestions)
                _row(
                  title: s.sh5Name,
                  subtitle: s.sh5UnitName,
                  trailing: rk7Badge(s.scoreLabel, color: Colors.orange.shade800),
                  onTap: () => _pick(s.sh5Rid, s.sh5Name),
                ),
              const Divider(height: 18),
            ],
            TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'SH5 tovarini qidirish...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                          setState(() {});
                        },
                      ),
                isDense: true,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: kRk7Accent, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _results()),
          ],
        ),
      ),
      actions: [
        // Mavjud bog'lanishni uzish — mahsulot yana «bog'lanmagan» bo'ladi.
        if (map != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const Sh5KirimPick.delete()),
            child: Text(
              'Bog\'lanishni o\'chirish',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Yopish',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _results() {
    if (_loading && _goods.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null && _goods.isEmpty) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
        ),
      );
    }
    if (_goods.isEmpty) {
      return const Center(
        child: Text(
          'Hech narsa topilmadi',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
      );
    }
    return ListView.builder(
      itemCount: _goods.length,
      itemBuilder: (context, index) {
        final g = _goods[index];
        return _row(
          title: g.name,
          subtitle: g.subtitle,
          onTap: () => _pick(g.rid, g.name),
        );
      },
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
