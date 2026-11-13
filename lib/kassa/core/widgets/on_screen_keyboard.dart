import 'package:flutter/material.dart';
import '../services/keyboard_service.dart';
import '../theme/app_theme.dart';

/// Ilova kontentini o'rab, klaviatura ochilganda uni pastdan chiqaradi.
///
/// Kontent Column ichida siqiladi — ya'ni markazlashgan dialog/maydonlar
/// klaviatura ustida ko'rinib turadi (haqiqiy klaviatura kabi), ustiga
/// chiqib ketmaydi.
class KeyboardHost extends StatelessWidget {
  final Widget child;
  const KeyboardHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: KeyboardController.instance.visible,
      builder: (context, visible, _) {
        return Column(
          children: [
            Expanded(child: child),
            AnimatedSize(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: visible
                  ? const OnScreenKeyboard()
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

/// Ilovaning o'z klaviaturasi (Windows tizim klaviaturasi o'rniga).
class OnScreenKeyboard extends StatefulWidget {
  const OnScreenKeyboard({super.key});

  @override
  State<OnScreenKeyboard> createState() => _OnScreenKeyboardState();
}

class _OnScreenKeyboardState extends State<OnScreenKeyboard> {
  final _kb = KeyboardController.instance;
  bool _shift = false;
  bool _symbols = false;
  // Oxirgi tanlangan alifboni eslab qolamiz (klaviatura yopilib ochilsa ham).
  late bool _cyrillic = _kb.cyrillic;

  // Lotin
  static const _lat1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _lat2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _lat3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];
  // Kirill
  static const _cyr1 =
      ['й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х', 'ъ'];
  static const _cyr2 =
      ['ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д', 'ж', 'э'];
  static const _cyr3 = ['я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю'];
  // Belgilar
  static const _sym1 = ['@', '#', '%', '&', '*', '-', '_', '+', '(', ')'];
  static const _sym2 = ['/', '\\', '=', ':', ';', '"', "'", ',', '?', '!'];

  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

  void _tapLetter(String ch) {
    _kb.insert(_shift ? ch.toUpperCase() : ch);
    if (_shift) setState(() => _shift = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = (size.height * 0.42).clamp(240.0, 380.0);

    // TextFieldTapRegion — tugma bosilganda maydon fokusini YO'QOTMASLIK
    // uchun shart: aks holda Flutter "maydondan tashqariga bosildi" deb
    // fokusni oladi va klaviatura darrov yopilib qolardi.
    // ExcludeFocus — tugmalarning o'zi fokus tortmasligi uchun.
    return TextFieldTapRegion(
      child: ExcludeFocus(
        child: Material(
          color: AppColors.surfaceAlt,
          elevation: 8,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: h,
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                      child: ValueListenableBuilder<KbLayout>(
                        valueListenable: _kb.layout,
                        builder: (context, layout, _) => layout ==
                                KbLayout.number
                            ? _numberPad()
                            : _textKeyboard(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: _kb.close,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Icon(Icons.keyboard_hide_rounded,
              size: 22, color: AppColors.textMuted),
        ),
      ),
    );
  }

  // ===== Raqamli panel =====
  Widget _numberPad() {
    Widget row(List<Widget> children) =>
        Expanded(child: Row(children: children));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            row([_key('1'), _key('2'), _key('3')]),
            row([_key('4'), _key('5'), _key('6')]),
            row([_key('7'), _key('8'), _key('9')]),
            row([
              _key('.', flex: 1),
              _key('0'),
              _action(Icons.backspace_outlined, _kb.backspace,
                  bg: AppColors.surfaceAlt),
            ]),
            row([
              _action(Icons.keyboard_return_rounded, _kb.action,
                  bg: AppColors.primary, fg: Colors.white, flex: 3),
            ]),
          ],
        ),
      ),
    );
  }

  // ===== To'liq QWERTY =====
  Widget _textKeyboard() {
    final rows = <Widget>[];
    rows.add(_row(_digits.map((d) => _key(d)).toList()));

    if (_symbols) {
      rows.add(_row(_sym1.map((s) => _key(s)).toList()));
      rows.add(_row([
        ..._sym2.map((s) => _key(s)),
        _action(Icons.backspace_outlined, _kb.backspace,
            bg: AppColors.surface, flex: 2),
      ]));
    } else {
      final r1 = _cyrillic ? _cyr1 : _lat1;
      final r2 = _cyrillic ? _cyr2 : _lat2;
      final r3 = _cyrillic ? _cyr3 : _lat3;
      rows.add(_row(r1.map((c) => _letter(c)).toList()));
      rows.add(_row(r2.map((c) => _letter(c)).toList()));
      rows.add(_row([
        _action(
          _shift ? Icons.arrow_upward_rounded : Icons.arrow_upward_outlined,
          () => setState(() => _shift = !_shift),
          bg: _shift ? AppColors.primary : AppColors.surface,
          fg: _shift ? Colors.white : AppColors.textMuted,
          flex: 2,
        ),
        ...r3.map((c) => _letter(c)),
        _action(Icons.backspace_outlined, _kb.backspace,
            bg: AppColors.surface, flex: 2),
      ]));
    }

    rows.add(_bottomRow());
    return Column(
      children: rows.map((r) => Expanded(child: r)).toList(),
    );
  }

  Widget _bottomRow() {
    return Row(
      children: [
        _action(
          null,
          () => setState(() => _symbols = !_symbols),
          label: _symbols ? 'АБВ' : '123',
          bg: AppColors.surface,
          flex: 3,
        ),
        if (!_symbols) _langKey(),
        _key(' ', label: 'bo\'sh joy', flex: 9),
        _key('.', flex: 2),
        _action(Icons.keyboard_return_rounded, _kb.action,
            bg: AppColors.primary, fg: Colors.white, flex: 4),
      ],
    );
  }

  /// Alifbo almashtirish tugmasi — nima bosilsa o'shani ko'rsatadi:
  /// lotinchada turганda «АБВ» (kirillchaga o'tish), kirillchada «ABC».
  /// Tanlov eslab qolinadi.
  Widget _langKey() {
    return Expanded(
      flex: 4,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => setState(() {
              _cyrillic = !_cyrillic;
              _kb.cyrillic = _cyrillic;
              _shift = false;
            }),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.language_rounded,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 5),
                Text(
                  _cyrillic ? 'ABC' : 'АБВ',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(children: children);

  Widget _letter(String ch) {
    final label = _shift ? ch.toUpperCase() : ch;
    return _key(ch, label: label, onTap: () => _tapLetter(ch));
  }

  /// Oddiy belgi tugmasi (matnni o'zi yozadi).
  Widget _key(String value, {String? label, int flex = 3, VoidCallback? onTap}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap ?? () => _kb.insert(value),
            child: Center(
              child: Text(
                label ?? value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Amal tugmasi (backspace, shift, enter, rejim...).
  Widget _action(IconData? icon, VoidCallback onTap,
      {String? label, Color bg = AppColors.surfaceAlt, Color? fg, int flex = 3}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            canRequestFocus: false,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Center(
              child: label != null
                  ? Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: fg ?? AppColors.textMuted,
                      ),
                    )
                  : Icon(icon, size: 22, color: fg ?? AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
