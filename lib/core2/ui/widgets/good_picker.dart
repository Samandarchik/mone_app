// core2/ui/widgets/good_picker.dart — tovar tanlash bottom-sheet'i
// (pickCoreGood): qidiruv maydoni (debounce 300 ms), qidiruv SERVER tomonda
// (`CoreDictProvider.searchGoods` → /goods?search=&limit=50), natija
// keshlanadi; qator bosilsa tanlangan CoreGood qaytadi. Ixtiyoriy [skladId]
// berilsa har qatorda joriy qoldiq ko'rsatiladi (CoreStockProvider).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

Future<CoreGood?> pickCoreGood(BuildContext context, {int? skladId}) {
  return showModalBottomSheet<CoreGood>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _GoodPickerSheet(skladId: skladId),
  );
}

class _GoodPickerSheet extends StatefulWidget {
  final int? skladId;
  const _GoodPickerSheet({this.skladId});

  @override
  State<_GoodPickerSheet> createState() => _GoodPickerSheetState();
}

class _GoodPickerSheetState extends State<_GoodPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<CoreGood> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.skladId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CoreStockProvider>().ensure(widget.skladId!);
      });
    }
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<CoreDictProvider>().searchGoods(q, limit: 50);
      if (!mounted || my != _seq) return; // eskirgan javob
      setState(() => _results = r);
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() => _error = CoreClient.wrap(e).display);
    } finally {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dict = context.read<CoreDictProvider>();
    final stock = widget.skladId == null ? null : context.watch<CoreStockProvider>();
    final height = MediaQuery.of(context).size.height * 0.8;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Tovar qidirish (server)…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : (_ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _ctrl.clear();
                              _search('');
                            })),
                filled: true,
                fillColor: kCoreBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? CoreErrorView(message: _error!, onRetry: () => _search(_ctrl.text))
                : _results.isEmpty
                    ? Center(child: Text(_loading ? 'Qidirilmoqda…' : 'Topilmadi'))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final g = _results[i];
                          final row = stock?.rowFor(widget.skladId!, g.id);
                          final group = dict.groupById(g.groupId)?.name;
                          return ListTile(
                            dense: true,
                            title: Text(g.name),
                            subtitle: Text(
                              [
                                coreDisplayUnit(g.baseUnit),
                                if (group != null && group.isNotEmpty) group,
                                if (g.isSemi) 'п/ф',
                                if (g.isComplect) 'taom',
                              ].join(' · '),
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: row == null
                                ? null
                                : Text(
                                    coreFormatQtyUnit(row.qty, row.baseUnit),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: row.qty < 0 ? Colors.red.shade700 : Colors.black87,
                                    ),
                                  ),
                            onTap: () => Navigator.pop(context, g),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
