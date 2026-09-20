// core2/ui/widgets/count_keypad.dart — «Sanash» (inventarizatsiya) uchun
// MIQDOR KLAVIATURASI: katta raqamlar, birlik almashtirgich (kg ↔ g,
// l ↔ ml, dona), «hisobdagidek» tugmasi (bir bosishda fakt = hisob qoldig'i),
// tozalash va «Tayyor». Telefonda pastki varaq (`showCountKeypad`),
// kompyuterda o'ng panelga joylash mumkin (`CountKeypad` vidjeti).
//
// Kiritilgan qiymat DOIM butun BASE birlikka (g/ml/mpcs/mm) o'giriladi —
// konvert `core2/models/core_qty.dart` orqali, bu yerda `*1000` yozilmaydi.
// Ko'rsatish formati `core2/core_format.dart` (kasr vergul, 3 kasrgacha).
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

/// Klaviaturada tanlanadigan birlik: `label` — odam ko'radigan nom («kg»),
/// `toBase` — 1 `label` necha base birlik (kg → 1000 g).
class CountUnit {
  final String label;
  final int toBase;
  const CountUnit(this.label, this.toBase);

  CoreGoodUnit get asGoodUnit => CoreGoodUnit(unit: label, toBase: toBase);
}

/// Base birlik uchun almashtirgich variantlari: g → kg/g, ml → l/ml,
/// mpcs → dona, mm → m/mm. Bitta variant qolsa almashtirgich ko'rsatilmaydi.
List<CountUnit> countUnitsFor(String baseUnit) {
  switch (baseUnit) {
    case 'g':
      return const [CountUnit('kg', 1000), CountUnit('g', 1)];
    case 'ml':
      return const [CountUnit('l', 1000), CountUnit('ml', 1)];
    case 'mpcs':
      return const [CountUnit('dona', 1000)];
    case 'mm':
      return const [CountUnit('m', 1000), CountUnit('mm', 1)];
    default:
      return [CountUnit(coreUnitUz(baseUnit), 1)];
  }
}

/// Klaviatura natijasi: `cleared` — fakt o'chirildi (qator «sanalmagan»
/// holatiga qaytadi), aks holda `base` — butun base birlikdagi fakt.
class CountValue {
  final int base;
  final bool cleared;
  const CountValue(this.base, {this.cleared = false});
}

/// Telefon uchun pastki varaq klaviaturasi. `null` — bekor qilindi.
///
/// [expand] / [onExpandChanged] — taom/p-f (`is_complect`) qatori uchun
/// «o'zi / tarkibi» almashtirgichi (hujjat qatoridagi `flag`). `null` bo'lsa
/// almashtirgich KO'RSATILMAYDI (oddiy xom ashyo qatori).
Future<CountValue?> showCountKeypad(
  BuildContext context, {
  required String goodName,
  required String baseUnit,
  required int currentBase,
  int? initialBase,
  String? hint,
  bool? expand,
  ValueChanged<bool>? onExpandChanged,
}) {
  return showModalBottomSheet<CountValue>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: CountKeypad(
          goodName: goodName,
          baseUnit: baseUnit,
          currentBase: currentBase,
          initialBase: initialBase,
          hint: hint,
          expand: expand,
          onExpandChanged: onExpandChanged,
          onDone: (v) => Navigator.pop(ctx, v),
          onCancel: () => Navigator.pop(ctx),
        ),
      ),
    ),
  );
}

class CountKeypad extends StatefulWidget {
  final String goodName;
  final String baseUnit;

  /// Hisobdagi qoldiq (base birlik) — «hisobdagidek» tugmasi shuni qo'yadi.
  final int currentBase;

  /// Avval kiritilgan fakt (base birlik); null — hali sanalmagan.
  final int? initialBase;

  /// Qo'shimcha kulrang izoh (masalan guruh nomi).
  final String? hint;

  /// Taom/p-f qatori tanlovi: `false` — «o'zi» (flag 1), `true` — «tarkibi»
  /// (flag 0). `null` — komplekt tovar emas, almashtirgich ko'rsatilmaydi.
  final bool? expand;
  final ValueChanged<bool>? onExpandChanged;

  final ValueChanged<CountValue> onDone;
  final VoidCallback? onCancel;

  const CountKeypad({
    super.key,
    required this.goodName,
    required this.baseUnit,
    required this.currentBase,
    required this.onDone,
    this.initialBase,
    this.hint,
    this.expand,
    this.onExpandChanged,
    this.onCancel,
  });

  @override
  State<CountKeypad> createState() => _CountKeypadState();
}

class _CountKeypadState extends State<CountKeypad> {
  late final List<CountUnit> _units = countUnitsFor(widget.baseUnit);
  int _unitIdx = 0;
  String _text = '';

  /// Taom/p-f: «tarkibi» tanlanganmi (flag 0).
  late bool _expand = widget.expand ?? false;

  CountUnit get _unit => _units[_unitIdx];

  @override
  void initState() {
    super.initState();
    final init = widget.initialBase;
    if (init != null) _text = _textOf(init, _unit);
  }

  /// Base miqdorni tanlangan birlikdagi kiritish matniga («2,5»).
  String _textOf(int base, CountUnit u) =>
      coreQtyInUnitUz(base, u.asGoodUnit);

  double? get _value => parseUiQty(_text);
  int? get _base {
    final v = _value;
    if (v == null) return null;
    return coreQtyFromUi(v, _unit.asGoodUnit);
  }

  void _tap(String ch) {
    setState(() {
      if (ch == ',') {
        if (_text.contains(',')) return;
        _text = _text.isEmpty ? '0,' : '$_text,';
        return;
      }
      // Kasr qismi 3 xonadan oshmasin (base butun son).
      final dot = _text.indexOf(',');
      if (dot >= 0 && _text.length - dot > 3) return;
      if (_text == '0') {
        _text = ch;
        return;
      }
      if (_text.length >= 12) return;
      _text = '$_text$ch';
    });
  }

  void _backspace() {
    setState(() {
      if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
    });
  }

  void _switchUnit(int idx) {
    if (idx == _unitIdx) return;
    setState(() {
      final base = _base;
      _unitIdx = idx;
      _text = base == null ? '' : _textOf(base, _unit);
    });
  }

  void _sameAsStock() {
    setState(() => _text = _textOf(widget.currentBase, _unit));
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    final delta = base == null ? null : base - widget.currentBase;
    final diffColor = delta == null || delta == 0
        ? Colors.grey.shade600
        : (delta < 0 ? Colors.red.shade700 : Colors.green.shade700);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.goodName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  'hisobda: ${coreQtyUnitUz(widget.currentBase, widget.baseUnit)}',
                  if (widget.hint != null && widget.hint!.isNotEmpty) widget.hint!,
                ].join('  ·  '),
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (widget.onExpandChanged != null) _expandRow(),
        // Kiritilayotgan qiymat + birlik almashtirgich.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  _text.isEmpty ? '—' : _text,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: _text.isEmpty ? Colors.grey.shade400 : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (_units.length == 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_unit.label,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ToggleButtons(
                    borderRadius: BorderRadius.circular(10),
                    constraints: const BoxConstraints(minWidth: 52, minHeight: 36),
                    isSelected: [
                      for (var i = 0; i < _units.length; i++) i == _unitIdx
                    ],
                    selectedColor: Colors.white,
                    fillColor: kCoreAccentDark,
                    onPressed: _switchUnit,
                    children: [
                      for (final u in _units)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(u.label,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (delta != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              delta == 0
                  ? 'Farq yo\'q'
                  : (delta < 0
                      ? 'Kamomad: ${coreQtyUnitUz(-delta, widget.baseUnit)}'
                      : 'Ortiqcha: ${coreQtyUnitUz(delta, widget.baseUnit)}'),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: diffColor),
            ),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            children: [
              _row(['7', '8', '9'], _KeyAction.backspace),
              _row(['4', '5', '6'], _KeyAction.clear),
              _row(['1', '2', '3'], _KeyAction.sameAsStock),
              _row(['0', ','], _KeyAction.done),
            ],
          ),
        ),
        if (widget.onCancel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton(
              onPressed: widget.onCancel,
              child: const Text('Bekor qilish'),
            ),
          ),
      ],
    );
  }

  /// Taom/p-f qatori: farq taomning O'ZIGA yozilsinmi yoki retsept bo'yicha
  /// TARKIBIGA (ingredientlarga) yoyilsinmi.
  Widget _expandRow() {
    void set(bool v) {
      if (v == _expand) return;
      setState(() => _expand = v);
      widget.onExpandChanged?.call(v);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text('Taom/p-f:',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('o\'zi', style: TextStyle(fontSize: 12)),
                selected: !_expand,
                selectedColor: kCoreAccent.withValues(alpha: 0.3),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => set(false),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('tarkibi', style: TextStyle(fontSize: 12)),
                selected: _expand,
                selectedColor: kCoreAccent.withValues(alpha: 0.3),
                visualDensity: VisualDensity.compact,
                onSelected: (_) => set(true),
              ),
            ],
          ),
          Text(
            _expand
                ? 'Farq retsept bo\'yicha ingredientlarga yoyiladi.'
                : 'Farq taomning o\'ziga yoziladi (hozirgi tartib).',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _row(List<String> digits, _KeyAction action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (final d in digits)
            Expanded(
              flex: digits.length == 2 && d == '0' ? 2 : 1,
              child: _key(
                label: d,
                onTap: () => _tap(d),
                bold: true,
              ),
            ),
          Expanded(child: _actionKey(action)),
        ],
      ),
    );
  }

  Widget _actionKey(_KeyAction a) {
    switch (a) {
      case _KeyAction.backspace:
        return _key(
          icon: Icons.backspace_outlined,
          onTap: _text.isEmpty ? null : _backspace,
        );
      case _KeyAction.clear:
        return _key(
          label: 'O\'chir',
          small: true,
          onTap: _text.isEmpty
              ? (widget.initialBase == null
                  ? null
                  : () => widget.onDone(const CountValue(0, cleared: true)))
              : () => setState(() => _text = ''),
        );
      case _KeyAction.sameAsStock:
        return _key(
          label: 'Hisobdagidek',
          small: true,
          color: kCoreAccent.withValues(alpha: 0.22),
          onTap: _sameAsStock,
        );
      case _KeyAction.done:
        final base = _base;
        return _key(
          label: 'Tayyor',
          small: true,
          color: kCoreAccentDark,
          textColor: Colors.white,
          onTap: base == null ? null : () => widget.onDone(CountValue(base)),
        );
    }
  }

  Widget _key({
    String? label,
    IconData? icon,
    VoidCallback? onTap,
    bool bold = false,
    bool small = false,
    Color? color,
    Color? textColor,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: enabled
            ? (color ?? Colors.grey.shade100)
            : Colors.grey.shade200.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: icon != null
                  ? Icon(icon,
                      size: 24,
                      color: enabled ? Colors.black87 : Colors.grey.shade400)
                  : Text(
                      label ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: small ? 13 : 24,
                        fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                        color: textColor ??
                            (enabled ? Colors.black87 : Colors.grey.shade400),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _KeyAction { backspace, clear, sameAsStock, done }
