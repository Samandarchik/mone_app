// core2/ui/widgets/qty_keypad.dart — «Tez kiritish» uchun katta raqamli
// miqdor klaviaturasi (QtyKeypad): tovar nomi, joriy qoldiq va oxirgi narx,
// birlik almashtirgich (kg ↔ g, l ↔ ml, dona), katta raqamlar.
//
// KIRIMDA narx emas, **Jami summa** kiritiladi (SH5 va bozor odati):
// `price = summa × to_base / base_qty` (1 birlik narxi, butun so'm) avtomatik
// hisoblanib ko'rsatiladi. Konvert faqat `core_qty.dart` orqali (qo'lda ×1000
// yozilmaydi).
//
// Telefonda `showQtyKeypad()` — pastki varaq; kompyuterda (≥900 px) o'ng
// panelda shu `QtyKeypad` vidjeti ishlatiladi (Enter — qo'shish, Esc — bekor).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/models/core_stock.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Klaviatura natijasi: miqdor BUTUN base birlikda + tanlangan birlik,
/// hamda (kirimda) 1 birlik narxi va qator summasi — butun so'm.
class QtyKeypadResult {
  final int baseQty;
  final CoreGoodUnit unit;
  final int price;
  final int amount;
  const QtyKeypadResult({
    required this.baseQty,
    required this.unit,
    this.price = 0,
    this.amount = 0,
  });
}

/// Pastki varaqda ochish (telefon tartibi). Bekor qilinsa null.
Future<QtyKeypadResult?> showQtyKeypad(
  BuildContext context, {
  required CoreGood good,
  int? skladId,
  bool withSum = false,
  QtyKeypadResult? initial,
  String okText = 'Qo\'shish',
}) {
  return showModalBottomSheet<QtyKeypadResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      // Past ekran (landshaft) — sig'masa aylantiriladi.
      child: SingleChildScrollView(
        child: QtyKeypad(
          good: good,
          skladId: skladId,
          withSum: withSum,
          initial: initial,
          okText: okText,
          onSubmit: (r) => Navigator.pop(ctx, r),
          onCancel: () => Navigator.pop(ctx),
        ),
      ),
    ),
  );
}

class QtyKeypad extends StatefulWidget {
  final CoreGood good;
  final int? skladId;

  /// Kirim: «Jami summa» maydoni ko'rsatiladi (narx avtomatik).
  final bool withSum;
  final QtyKeypadResult? initial;
  final String okText;
  final ValueChanged<QtyKeypadResult> onSubmit;
  final VoidCallback? onCancel;

  const QtyKeypad({
    super.key,
    required this.good,
    this.skladId,
    this.withSum = false,
    this.initial,
    this.okText = 'Qo\'shish',
    required this.onSubmit,
    this.onCancel,
  });

  @override
  State<QtyKeypad> createState() => _QtyKeypadState();
}

class _QtyKeypadState extends State<QtyKeypad> {
  late CoreGoodUnit _unit;
  String _qty = '';
  String _sum = '';
  bool _sumActive = false;
  final FocusNode _keys = FocusNode(debugLabel: 'qty_keypad');

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _unit = init?.unit ?? widget.good.preferredUnit;
    if (init != null && init.baseQty > 0) {
      _qty = coreFormatInUnit(init.baseQty, _unit).replaceAll('.', ',');
      if (init.amount > 0) _sum = formatMoneyInput(init.amount);
    }
    if (widget.skladId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CoreStockProvider>().ensure(widget.skladId!);
      });
    }
  }

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  // ── Hisoblar ──

  double get _qtyUi => parseUiQty(_qty) ?? 0;
  int get _baseQty => coreQtyFromUi(_qtyUi, _unit);
  int get _sumInt => parseMoney(_sum);

  /// 1 birlik narxi (butun so'm) — summa / miqdor.
  int get _price {
    if (_baseQty <= 0 || _sumInt <= 0) return 0;
    return (_sumInt * _unit.toBase / _baseQty).round();
  }

  /// Serverga ketadigan qator summasi — narx bo'yicha qayta hisoblangan
  /// (server ham shunday hisoblaydi, yaxlitlash farqi chiqmasin).
  int get _amount =>
      _price <= 0 ? 0 : coreLineAmount(_baseQty, _price, _unit);

  bool get _ready => _baseQty > 0;

  void _tap(String key) {
    setState(() {
      final target = _sumActive ? _sum : _qty;
      String next;
      switch (key) {
        case '<':
          next = target.isEmpty
              ? ''
              : target.substring(0, target.length - 1);
          break;
        case ',':
          if (_sumActive) {
            next = '${target}000'; // summada «000»
          } else {
            next = target.contains(',') ? target : (target.isEmpty ? '0,' : '$target,');
          }
          break;
        default:
          next = target + key;
      }
      if (_sumActive) {
        _sum = next.isEmpty ? '' : formatMoneyInput(parseMoney(next));
      } else {
        // Ortiqcha uzun kiritishdan himoya.
        if (next.replaceAll(RegExp(r'[^0-9]'), '').length > 9) return;
        _qty = next;
      }
    });
  }

  void _submit() {
    if (!_ready) return;
    widget.onSubmit(QtyKeypadResult(
      baseQty: _baseQty,
      unit: _unit,
      price: _price,
      amount: _amount,
    ));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      widget.onCancel?.call();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _tap('<');
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab && widget.withSum) {
      setState(() => _sumActive = !_sumActive);
      return KeyEventResult.handled;
    }
    final ch = e.character ?? '';
    if (ch.isNotEmpty && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _tap(ch);
      return KeyEventResult.handled;
    }
    if (ch == ',' || ch == '.') {
      _tap(',');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Ko'rinish ──

  @override
  Widget build(BuildContext context) {
    final row = widget.skladId == null
        ? null
        : context.select<CoreStockProvider, CoreStockRow?>(
            (s) => s.rowFor(widget.skladId!, widget.good.id));

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(row),
            _units(),
            _display(),
            const SizedBox(height: 4),
            _pad(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  if (widget.onCancel != null) ...[
                    OutlinedButton(
                      onPressed: widget.onCancel,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(96, 50)),
                      child: const Text('Bekor'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _ready ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.check),
                      label: Text(widget.okText,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(CoreStockRow? row) {
    final lastPriceInUnit =
        row?.lastPrice == null ? null : row!.lastPrice! * _unit.toBase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.good.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Row(
            children: [
              if (row != null)
                Text(
                  'Qoldiq: ${coreQtyUnitUz(row.qty, row.baseUnit)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: row.qty < 0 ? Colors.red.shade700 : Colors.grey.shade700,
                  ),
                ),
              if (lastPriceInUnit != null && lastPriceInUnit > 0) ...[
                const SizedBox(width: 10),
                Text(
                  'Oxirgi narx: ${coreMoneyUz(lastPriceInUnit)}/${_unitLabel(_unit.unit)}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _units() {
    final units = widget.good.selectableUnits;
    if (units.length < 2) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        children: [
          for (final u in units)
            ChoiceChip(
              label: Text(_unitLabel(u.unit)),
              selected: u.unit == _unit.unit,
              selectedColor: kCoreAccent.withValues(alpha: 0.3),
              onSelected: (_) => setState(() => _unit = u),
            ),
        ],
      ),
    );
  }

  Widget _display() {
    final qtyBox = _field(
      label: 'Miqdor',
      value: _qty.isEmpty ? '0' : _qty,
      suffix: _unitLabel(_unit.unit),
      active: !_sumActive,
      onTap: () => setState(() => _sumActive = false),
    );
    if (!widget.withSum) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: qtyBox,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: qtyBox),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  label: 'Jami summa',
                  value: _sum.isEmpty ? '0' : _sum,
                  suffix: 'so\'m',
                  active: _sumActive,
                  onTap: () => setState(() => _sumActive = true),
                ),
              ),
            ],
          ),
          if (_price > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Narx: ${coreMoneyUz(_price)} so\'m / ${_unitLabel(_unit.unit)}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required String suffix,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kCoreAccent.withValues(alpha: 0.12) : kCoreBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? kCoreAccentDark : Colors.grey.shade300,
              width: active ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                Text(suffix,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pad() {
    const keys = ['7', '8', '9', '4', '5', '6', '1', '2', '3'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var r = 0; r < 3; r++)
            Row(
              children: [
                for (var c = 0; c < 3; c++) _key(keys[r * 3 + c]),
              ],
            ),
          Row(
            children: [
              _key(',', label: _sumActive ? '000' : ','),
              _key('0'),
              _key('<', label: '⌫'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(String value, {String? label}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: kCoreBg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _tap(value),
            onLongPress: value == '<'
                ? () => setState(() {
                      if (_sumActive) {
                        _sum = '';
                      } else {
                        _qty = '';
                      }
                    })
                : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text(label ?? value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Birlik kodining chipdagi nomi. `coreUnitUz` bu yerda YARAMAYDI — u
/// g→kg, ml→l qiladi (chipda ikkita «kg» ko'rinib qolardi).
String _unitLabel(String code) {
  switch (code) {
    case 'pcs':
      return 'dona';
    case 'mpcs':
      return 'dona/1000';
    case 'portion':
      return 'porsiya';
    default:
      return code;
  }
}
