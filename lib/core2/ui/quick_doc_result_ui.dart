// core2/ui/quick_doc_result_ui.dart — «Tez kiritish» natija ekrani
// (PLAN_UI_OSON §2.2): yashil belgi, hujjat raqami va qisqa xulosa;
// post javobidagi `warnings` oddiy tilda GURUHLAB ko'rsatiladi
// (negative_stock | no_batch | no_recipe | rounding — `core_labels.dart`),
// tugmalar: «Yana bitta», «Bosh sahifa», «Hujjatni ko'rish».
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/quick_doc_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class QuickDocResultUi extends StatefulWidget {
  final CoreDocPostResult result;
  final String type;
  final int? skladId;

  const QuickDocResultUi({
    super.key,
    required this.result,
    required this.type,
    this.skladId,
  });

  @override
  State<QuickDocResultUi> createState() => _QuickDocResultUiState();
}

class _QuickDocResultUiState extends State<QuickDocResultUi> {
  @override
  void initState() {
    super.initState();
    // Ogohlantirishlardagi tovar nomi/birligi uchun keshga olib kelamiz.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ids = widget.result.warnings
          .map((w) => w.goodId ?? 0)
          .where((id) => id > 0);
      if (ids.isNotEmpty) context.read<CoreDictProvider>().ensureGoods(ids);
    });
  }

  CoreDoc get doc => widget.result.doc;

  @override
  Widget build(BuildContext context) {
    final dict = context.watch<CoreDictProvider>();
    final groups = coreGroupWarnings(widget.result.warnings);
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Bajarildi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _successCard(dict),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in groups.entries) _warnCard(e.key, e.value, dict),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    QuickDocUi(type: widget.type, skladId: widget.skladId),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Yana bitta',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Bosh sahifa'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DocDetailUi(docId: doc.id, initial: doc),
              ),
            ),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Hujjatni ko\'rish'),
          ),
        ],
      ),
    );
  }

  Widget _successCard(CoreDictProvider dict) {
    // Akt bitta omborda bo'lsa server `from_sklad` ni `to_sklad` ga
    // tenglashtirib qaytaradi — «X → X» ko'rinmasin.
    final same = doc.fromSklad != null && doc.fromSklad == doc.toSklad;
    final parts = <String>[
      if (doc.fromSklad != null && !same) dict.skladName(doc.fromSklad),
      if (doc.toSklad != null) dict.skladName(doc.toSklad),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle, size: 64, color: Colors.green.shade600),
          const SizedBox(height: 10),
          Text(
            '${coreTypeUz(doc.type)} o\'tkazildi',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('№ ${doc.number.isEmpty ? doc.id : doc.number} · ${coreDayUz(doc.docDate)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          if (parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(parts.join('  →  '),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('Qator', '${doc.lines.length}'),
              if (doc.total > 0) _stat('Summa', coreSumUz(doc.total)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _warnCard(
      String code, List<CoreDocWarning> list, CoreDictProvider dict) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(coreWarnIconUz(code), color: Colors.orange.shade900, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${coreWarnTitleUz(code)} · ${list.length} ta',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(coreWarnHintUz(code),
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          const SizedBox(height: 6),
          for (final w in list.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• ${_warnName(w, dict)} — ${_warnQty(w, dict)}'
                '${w.skladId == null ? '' : ' · ${dict.skladName(w.skladId)}'}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          if (list.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('… va yana ${list.length - 8} ta',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }

  String _warnName(CoreDocWarning w, CoreDictProvider dict) {
    if (w.goodName.isNotEmpty) return w.goodName;
    final g = dict.goodById(w.goodId);
    return g?.name ?? 'Tovar #${w.goodId ?? 0}';
  }

  String _warnQty(CoreDocWarning w, CoreDictProvider dict) {
    final g = dict.goodById(w.goodId);
    if (g == null) return '${w.qty}';
    return coreQtyUnitUz(w.qty, g.baseUnit);
  }
}
