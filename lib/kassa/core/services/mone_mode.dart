import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Mone rejimi — kassa katalogi Mone'dan keladi (backend: internal/monesync).
/// Yoqilgan bo'lsa mahsulot/kategoriya YARATISH yashiriladi va nom, narx,
/// kategoriya tahrirlanmaydi (server ham 409 qaytaradi). Printer, tartib,
/// faol/nofaol, rasm — kassa sozlamasi, ochiq qoladi.
class MoneMode {
  MoneMode._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Holatni serverdan yangilaydi (xatoda oldingi qiymat qoladi).
  static Future<bool> refresh() async {
    try {
      final st = await ApiService().getMoneStatus();
      enabled.value = st['enabled'] == true;
    } catch (_) {}
    return enabled.value;
  }

  static const String lockedHint = 'Mone\'dan keladi — Mone\'da o\'zgartiriladi';
}
