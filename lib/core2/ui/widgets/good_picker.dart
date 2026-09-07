// core2/ui/widgets/good_picker.dart — tovar tanlash bottom-sheet'i
// (pickCoreGood): qidiruv maydoni, CoreDictProvider keshida lokal qidiruv
// (natija 60 tagacha), qator bosilsa tanlangan CoreGood qaytadi. Ixtiyoriy
// [skladId] berilsa har qatorda joriy qoldiq ko'rsatiladi (CoreStockProvider).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
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
  String _q = '';

  @override
  void initState() {
    super.initState();
    if (widget.skladId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CoreStockProvider>().ensure(widget.skladId!);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dict = context.watch<CoreDictProvider>();
    final stock = widget.skladId == null ? null : context.watch<CoreStockProvider>();
    final results = dict.searchGoods(_q, limit: 60);
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
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Tovar qidirish...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _q = '');
                        }),
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
            child: results.isEmpty
                ? const Center(child: Text('Topilmadi'))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final g = results[i];
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
                                  color: row.qty < 0
                                      ? Colors.red.shade700
                                      : Colors.black87,
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
