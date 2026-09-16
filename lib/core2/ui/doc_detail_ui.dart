// core2/ui/doc_detail_ui.dart — hujjat tafsiloti (DocDetailUi): sarlavha
// (tur, raqam, holat chip), sana/omborlar/kontragent/izoh/manba, qatorlar
// (miqdor birlikda, narx, summa, sotuv summasi, `stock_after` — qator
// darajasida, hujjatdan keyingi qoldiq; production'da sarf/mahsulot
// bo'limlari), warnings (post javobidan saqlanadi), tarix (created_by,
// posted_by/at). Tugmalar perms bo'yicha: Tahrirlash (draft), Tasdiqlash
// (draft → post, warnings dialog), Bekor qilish (posted → cancel,
// doc.cancel), O'chirish (draft).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/ui/doc_form_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DocDetailUi extends StatefulWidget {
  final int docId;
  // Ro'yxatdan kelgan (qatorsiz) nusxa — to'liq yuklangunча ko'rsatiladi.
  final CoreDoc? initial;
  const DocDetailUi({super.key, required this.docId, this.initial});

  @override
  State<DocDetailUi> createState() => _DocDetailUiState();
}

class _DocDetailUiState extends State<DocDetailUi> {
  CoreDoc? _doc;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<CoreDocsProvider>().fetch(widget.docId);
      if (!mounted) return;
      // Tovar nomlari qatorda bor; keshga fonda (warnings/birlik uchun).
      context.read<CoreDictProvider>().ensureGoods(d.lines.map((l) => l.goodId));
      setState(() {
        // Post javobidagi warnings tafsilotda yo'q — mavjudini saqlaymiz.
        _doc = d.warnings.isEmpty && (_doc?.warnings.isNotEmpty ?? false)
            ? d.copyWith(warnings: _doc!.warnings)
            : d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _post() async {
    final doc = _doc;
    if (doc == null) return;
    final ok = await confirmDialog(context, 'Tasdiqlash',
        '${CoreDocType.title(doc.type)} ${doc.number} o\'tkazilsinmi?',
        okText: 'Tasdiqlash');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await context.read<CoreDocsProvider>().post(doc.id);
      if (!mounted) return;
      setState(() => _doc = res.doc.copyWith(warnings: res.warnings));
      context.read<CoreStockProvider>().refreshSklads([doc.fromSklad, doc.toSklad]);
      await showWarningsDialog(context, res.warnings);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final doc = _doc;
    if (doc == null) return;
    final ok = await confirmDialog(context, 'Bekor qilish',
        '${doc.number} bekor qilinsinmi? Qoldiq teskari yoziladi.',
        okText: 'Bekor qilish', danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final d = await context.read<CoreDocsProvider>().cancel(doc.id);
      if (!mounted) return;
      setState(() => _doc = d);
      context.read<CoreStockProvider>().refreshSklads([doc.fromSklad, doc.toSklad]);
      _load();
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final doc = _doc;
    if (doc == null) return;
    final ok = await confirmDialog(
        context, 'O\'chirish', 'Qoralama ${doc.number} o\'chirilsinmi?',
        okText: 'O\'chirish', danger: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<CoreDocsProvider>().delete(doc.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showCoreError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: Text(
          doc == null
              ? 'Hujjat'
              : '${CoreDocType.title(doc.type)} ${doc.number.isEmpty ? '#${doc.id}' : doc.number}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (doc != null && doc.isDraft)
            IconButton(
              tooltip: 'Tahrirlash',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DocFormUi(type: doc.type, existing: doc)),
                );
                _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: CoreConnectGate(
        child: doc == null
            ? (_error != null
                ? CoreErrorView(message: _error!, onRetry: _load)
                : const Center(child: CircularProgressIndicator.adaptive()))
            : _body(doc),
      ),
    );
  }

  Widget _body(CoreDoc doc) {
    final dict = context.watch<CoreDictProvider>();
    final session = context.watch<CoreSession>();
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                _card(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(docTypeIcon(doc.type), color: kCoreAccentDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(CoreDocType.title(doc.type),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        coreStatusChip(doc.status),
                      ],
                    ),
                    const Divider(),
                    kv('Sana', coreDate(doc.docDate)),
                    if (doc.fromSklad != null)
                      kv('Dan', dict.skladName(doc.fromSklad)),
                    if (doc.toSklad != null) kv('Ga', dict.skladName(doc.toSklad)),
                    if (doc.corrId != null) kv('Kontragent', dict.corrName(doc.corrId)),
                    if (doc.comment.isNotEmpty) kv('Izoh', doc.comment),
                    if (doc.source.isNotEmpty) kv('Manba', doc.source),
                    if (doc.externalId != null && doc.externalId!.isNotEmpty)
                      kv('Tashqi ID', doc.externalId!),
                    kv('Jami', '${coreMoney(doc.total)} so\'m', bold: true),
                    if (doc.saleAmount > 0)
                      kv('Sotuv summasi', '${coreMoney(doc.saleAmount)} so\'m'),
                  ],
                )),
                const SizedBox(height: 10),
                if (doc.warnings.isNotEmpty) ...[
                  _warnings(doc, dict),
                  const SizedBox(height: 10),
                ],
                if (doc.type == CoreDocType.production) ...[
                  _lines('Sarf (xomashyo)',
                      doc.lines.where((l) => l.flag == 1).toList(), doc, dict),
                  const SizedBox(height: 10),
                  _lines('Mahsulot (chiqish)',
                      doc.lines.where((l) => l.flag == 0).toList(), doc, dict),
                ] else if (doc.type == CoreDocType.act &&
                    doc.lines.any((l) => l.flag == 1)) ...[
                  // Post paytida retsept yoyilgan bo'lsa hujjatda ikki xil
                  // qator bo'ladi: taom (flag=0) va ingredient sarfi (flag=1).
                  _lines('Taomlar',
                      doc.lines.where((l) => l.flag == 0).toList(), doc, dict),
                  const SizedBox(height: 10),
                  _lines('Sarf (ingredientlar)',
                      doc.lines.where((l) => l.flag == 1).toList(), doc, dict),
                ] else
                  _lines(
                      doc.type == CoreDocType.act
                          ? 'Taomlar'
                          : doc.type == CoreDocType.inventory
                              ? 'Fakt qatorlari'
                              : 'Qatorlar',
                      doc.lines,
                      doc,
                      dict),
                const SizedBox(height: 10),
                _history(doc),
              ],
            ),
          ),
        ),
        _actions(doc, session),
      ],
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: child,
      );

  Widget _lines(String title, List<CoreDocLine> lines, CoreDoc doc,
      CoreDictProvider dict) {
    final showPrice = CoreDocType.hasPrice(doc.type) ||
        lines.any((l) => l.price > 0 || l.amount > 0);
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title (${lines.length})',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (lines.isEmpty)
          Text('Qator yo\'q', style: TextStyle(color: Colors.grey.shade600)),
        for (final l in lines) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    l.goodName.isNotEmpty ? l.goodName : dict.goodName(l.goodId),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_qtyText(l, dict),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (showPrice)
                      Text(
                        '${coreMoney(l.price)} × → ${coreMoney(l.amount)}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    if ((l.saleAmount ?? 0) > 0)
                      Text(
                        'sotuv: ${coreMoney(l.saleAmount!)}',
                        style: TextStyle(fontSize: 11.5, color: Colors.green.shade700),
                      ),
                    // Post'dan keyingi qoldiq (ledger beradi, qator darajasida).
                    if (l.stockAfter != null)
                      Text(
                        'qoldiq: ${coreFormatQtyUnit(l.stockAfter!, _baseOf(l, dict))}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: l.stockAfter! < 0 ? Colors.red.shade700 : Colors.grey.shade700),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (l != lines.last) const Divider(height: 1),
        ],
      ],
    ));
  }

  /// Qator miqdori — hujjatdagi birlikda (kg/pcs…); tovar keshda bo'lsa
  /// uning `units` faktori, bo'lmasa `/units` standart faktori.
  String _qtyText(CoreDocLine l, CoreDictProvider dict) {
    final good = dict.goodById(l.goodId);
    if (good != null) {
      final u = good.selectableUnits
          .where((u) => u.unit == l.unit)
          .cast<CoreGoodUnit?>()
          .firstWhere((_) => true, orElse: () => null);
      if (u != null) return '${coreFormatInUnit(l.qty, u)} ${u.unit}';
      return coreFormatQtyUnit(l.qty, good.baseUnit);
    }
    if (l.unit.isNotEmpty) return coreFormatQtyAs(l.qty, l.unit);
    return '${l.qty}';
  }

  // Qator base birligi: kesh, bo'lmasa `unit` dan (kg → g).
  String _baseOf(CoreDocLine l, CoreDictProvider dict) =>
      dict.goodById(l.goodId)?.baseUnit ?? coreBaseUnitOf(l.unit);

  Widget _warnings(CoreDoc doc, CoreDictProvider dict) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            SizedBox(width: 6),
            Text('Ogohlantirishlar', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          for (final w in doc.warnings)
            Text(
              '• ${w.goodName.isNotEmpty ? w.goodName : dict.goodName(w.goodId ?? 0)} — ${dict.skladName(w.skladId)}: ${w.qty}${w.msg.isNotEmpty ? ' (${w.msg})' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
        ],
      ),
    );
  }

  Widget _history(CoreDoc doc) {
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tarix', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        kv('Yaratdi',
            '${doc.createdBy == null ? '—' : 'user #${doc.createdBy}'}${doc.createdAt != null ? ' · ${coreDate(doc.createdAt, withTime: true)}' : ''}'),
        if (doc.postedAt != null || doc.postedBy != null)
          kv('O\'tkazdi',
              '${doc.postedBy == null ? '—' : 'user #${doc.postedBy}'} · ${coreDate(doc.postedAt, withTime: true)}'),
        kv('Holat', CoreDocStatus.title(doc.status)),
      ],
    ));
  }

  Widget _actions(CoreDoc doc, CoreSession session) {
    final buttons = <Widget>[];
    if (doc.isDraft) {
      buttons.add(IconButton(
        tooltip: 'O\'chirish',
        onPressed: _delete,
        icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
      ));
      if (session.canPost(doc.type)) {
        buttons.add(Expanded(
          child: ElevatedButton.icon(
            onPressed: _post,
            style: ElevatedButton.styleFrom(
                backgroundColor: kCoreAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.check),
            label: const Text('Tasdiqlash'),
          ),
        ));
      }
    } else if (doc.isPosted && session.canCancel) {
      buttons.add(Expanded(
        child: OutlinedButton.icon(
          onPressed: _cancel,
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size.fromHeight(46)),
          icon: const Icon(Icons.undo),
          label: const Text('Bekor qilish'),
        ),
      ));
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: _busy
            ? const Center(child: CircularProgressIndicator.adaptive())
            : Row(children: buttons),
      ),
    );
  }
}
