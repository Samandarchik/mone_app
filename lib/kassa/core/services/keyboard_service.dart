import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Klaviatura turi — sonli maydonlarga raqamli panel, qolganlariga to'liq
/// QWERTY chiqadi.
enum KbLayout { number, text }

/// Ilovaning O'ZIDA chiziladigan klaviatura boshqaruvchisi.
///
/// NEGA KERAK: Windows sensorli ekrandagi tizim klaviaturasi (TabTip)
/// o'z-o'zidan ochilib/yopilib bezovta qilardi va uni Windows tomonidan
/// bosib bo'lmadi. `TextInput.setInputControl` orqali Flutter'ning matn
/// kiritish oqimini butunlay o'zimiz ushlaymiz: endi tizim klaviaturasi
/// UMUMAN chaqirilmaydi, uning o'rniga [OnScreenKeyboard] chiziladi va
/// tugmalar shu yerdan fokusdagi maydonga yoziladi.
///
/// Faqat Windows'da o'rnatiladi (main.dart) — telefon/planshetda tizim
/// klaviaturasi qulay, o'zgartirilmaydi.
class KeyboardController with TextInputControl {
  KeyboardController._();
  static final KeyboardController instance = KeyboardController._();

  /// Klaviatura ko'rinib turibdimi (overlay shu asosida chiziladi).
  final ValueNotifier<bool> visible = ValueNotifier(false);

  /// Joriy maydon turiga mos panel.
  final ValueNotifier<KbLayout> layout = ValueNotifier(KbLayout.text);

  /// Tanlangan alifbo — kirillcha (ЙЦУКЕН) yoki lotincha. Klaviatura qayta
  /// ochilganda ham saqlanib qoladi: rus tilida yozadigan joyda har safar
  /// qaytadan almashtirmaslik uchun.
  bool cyrillic = false;

  TextInputClient? _client;
  TextInputConfiguration? _config;
  TextEditingValue _value = TextEditingValue.empty;

  bool _installed = false;

  /// Flutter matn kiritishini shu boshqaruvchiga ulaydi. Bir marta chaqiriladi.
  void install() {
    if (_installed) return;
    TextInput.setInputControl(this);
    _installed = true;
  }

  bool get _isMultiline =>
      _config?.inputType.index == TextInputType.multiline.index;

  void _refreshLayout() {
    final t = _config?.inputType;
    final numeric = t != null &&
        (t.index == TextInputType.number.index ||
            t.index == TextInputType.phone.index);
    layout.value = numeric ? KbLayout.number : KbLayout.text;
  }

  // ===== TextInputControl — Flutter chaqiradigan metodlar =====

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _client = client;
    _config = configuration;
    _refreshLayout();
  }

  @override
  void detach(TextInputClient client) {
    if (identical(client, _client)) {
      _client = null;
      _config = null;
      visible.value = false;
    }
  }

  @override
  void show() {
    _refreshLayout();
    visible.value = true;
  }

  @override
  void hide() {
    visible.value = false;
  }

  @override
  void setEditingState(TextEditingValue value) {
    _value = value;
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    _config = configuration;
    _refreshLayout();
  }

  // ===== Klaviatura tugmalari shu metodlarni chaqiradi =====

  /// Kursor turgan joyga matn qo'yadi (belgilangan matn bo'lsa almashtiradi).
  void insert(String s) {
    final client = _client;
    if (client == null) return;
    final text = _value.text;
    final sel = _value.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, s);
    _value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    // `updateEditingValue` maydonning inputFormatters'idan o'tadi — ya'ni
    // digitsOnly / maxLength kabi cheklovlar avvalgidek ishlaydi.
    client.updateEditingValue(_value);
  }

  /// Bir belgi (yoki belgilangan matn) o'chiradi.
  void backspace() {
    final client = _client;
    if (client == null) return;
    final text = _value.text;
    if (text.isEmpty) return;
    final sel = _value.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    if (start == end) {
      if (start == 0) return;
      final newText = text.replaceRange(start - 1, start, '');
      _value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      final newText = text.replaceRange(start, end, '');
      _value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    }
    client.updateEditingValue(_value);
  }

  /// Enter — ko'p qatorli maydonda yangi qator, aks holda "tayyor"/"qidirish"
  /// amali (maydon `onSubmitted`ini ishga soladi).
  void action() {
    final client = _client;
    if (client == null) return;
    if (_isMultiline) {
      insert('\n');
      return;
    }
    client.performAction(_config?.inputAction ?? TextInputAction.done);
  }

  /// Klaviaturani yopadi (fokusni olib tashlab).
  void close() {
    FocusManager.instance.primaryFocus?.unfocus();
    visible.value = false;
  }
}
