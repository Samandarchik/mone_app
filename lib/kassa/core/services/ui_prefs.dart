import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kassir o'zi sozlaydigan UI o'lchamlari. Qiymatlar SHU QURILMANING
/// o'zida saqlanadi (SharedPreferences) — serverga yuborilmaydi va boshqa
/// kassalarga ta'sir qilmaydi: har bir ekran o'ziga qulay o'lchamni tanlaydi.
///
/// 1.0 — standart, 0.7 — eng kichik, 1.6 — eng katta.
class UiPrefs {
  static final UiPrefs _i = UiPrefs._();
  factory UiPrefs() => _i;
  UiPrefs._();

  static const double minScale = 0.7;
  static const double maxScale = 1.6;

  /// Stollar ekranidagi stol kartalari masshtabi.
  final ValueNotifier<double> tableScale = ValueNotifier(1.0);

  /// Buyurtma ekranidagi menyu (mahsulot) kartalari masshtabi.
  final ValueNotifier<double> menuScale = ValueNotifier(1.0);

  static const _kTable = 'ui_table_scale';
  static const _kMenu = 'ui_menu_scale';

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    tableScale.value = _clamp(p.getDouble(_kTable));
    menuScale.value = _clamp(p.getDouble(_kMenu));
  }

  double _clamp(double? v) => (v ?? 1.0).clamp(minScale, maxScale);

  Future<void> setTableScale(double v) async {
    tableScale.value = _clamp(v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTable, tableScale.value);
  }

  Future<void> setMenuScale(double v) async {
    menuScale.value = _clamp(v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kMenu, menuScale.value);
  }
}
