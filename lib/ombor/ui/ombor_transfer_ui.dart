// ombor/ui/ombor_transfer_ui.dart — ICHKI KO'CHIRISH (markaz → filial bo'limi
// va h.k.): manba sklad (omborchining o'zi), manzil sklad, mahsulotlar va miqdor.
// POST /api/stock/transfer — tannarx FIFO bo'yicha manbadan manzilga to'liq
// o'tadi (sexda pishgan tort filial Vitrinasiga xuddi o'sha tannarxda kiradi).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/network/error_handler.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/production/models/stock_model.dart';

class OmborTransferUi extends StatefulWidget {
  final List<int> fromSklads; // omborchining skladlari (admin — hammasi)
  const OmborTransferUi({super.key, required this.fromSklads});

  @override
  State<OmborTransferUi> createState() => _OmborTransferUiState();
}

class _OmborTransferUiState extends State<OmborTransferUi> {
  final Dio _dio = sl<Dio>();
  late int _from = widget.fromSklads.first;
  int? _to;
  List<StockRow> _rows = const [];
  final Map<int, TextEditingController> _qty = {};
  String _q = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SkladRegistry.load().then((_) => mounted ? setState(() {}) : null);
    _load();
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _dio.get(AppUrls.stock, queryParameters: {'sklad_id': _from});
      final rows = StockRow.listFromJson(r.data is Map ? r.data['data'] : null)
          .where((s) => s.qty > 0)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = parseDioError(e);
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final to = _to;
    if (to == null) {
      setState(() => _error = 'Qaysi omborga ko‘chirilishini tanlang');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final s in _rows) {
      final t = _qty[s.productId]?.text.trim().replaceAll(',', '.') ?? '';
      final v = double.tryParse(t);
      if (v == null || v <= 0) continue;
      final api = qtyFromUi(v, s.type);
      if (api > s.qty + 1e-9) {
        setState(() => _error = '«${s.name}»: omborda ${formatQtyUnit(s.qty, s.type)} bor');
        return;
      }
      items.add({'product_id': s.productId, 'qty': api});
    }
    if (items.isEmpty) {
      setState(() => _error = 'Kamida bitta mahsulot miqdorini kiriting');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await _dio.post(AppUrls.stockTransfer,
          data: {'from_sklad_id': _from, 'to_sklad_id': to, 'items': items});
      if (!mounted) return;
      final total = (r.data is Map && r.data['data'] is Map) ? r.data['data']['total_cost'] : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ko‘chirildi: ${items.length} ta mahsulot'
              '${total is num ? ' · tannarx ${formatMoneyInput(total)} so‘m' : ''}')));
      for (final c in _qty.values) {
        c.clear();
      }
      setState(() => _sending = false);
      _load();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = parseDioError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [
      for (final s in _rows)
        if (q.isEmpty || s.name.toLowerCase().contains(q)) s,
    ];
    final targets = [
      for (final id in SkladRegistry.ids)
        if (id != _from) id,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Ichki ko‘chirish')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text(_sending ? 'Yuborilmoqda…' : 'Ko‘chirish'),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _from,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Qayerdan', border: OutlineInputBorder()),
                  items: [
                    for (final id in widget.fromSklads)
                      DropdownMenuItem(value: id, child: Text(SkladRegistry.nameOf(id), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v == null || v == _from) return;
                    setState(() {
                      _from = v;
                      if (_to == v) _to = null;
                    });
                    _load();
                  },
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: targets.contains(_to) ? _to : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Qayerga', border: OutlineInputBorder()),
                  items: [
                    for (final id in targets)
                      DropdownMenuItem(value: id, child: Text(SkladRegistry.nameOf(id), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Mahsulot qidirish', isDense: true),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? const Center(child: Text('Bu omborda qoldiq yo‘q'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final s = list[i];
                          final c = _qty.putIfAbsent(s.productId, () => TextEditingController());
                          return ListTile(
                            title: Text(s.name),
                            subtitle: Text('Omborda: ${formatQtyUnit(s.qty, s.type)}'),
                            trailing: SizedBox(
                              width: 96,
                              child: TextField(
                                controller: c,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.end,
                                decoration: InputDecoration(isDense: true, hintText: '0'),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
