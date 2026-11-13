import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Asoschilar — to'lov oynasidagi «ichki hisob» usullari (egalar olgan
/// narsalar). Manba: qilinadigan_ishlar «Получатель расхода (владелец)»
/// switch'i yoqilgan userlar → Mone → kassa serveri (`GET /api/kassa/owners`).
///
/// To'lov kaliti: `owner:<id>`. Eski cheklardagi `nilufar` / `bobur`
/// kalitlari faqat nom uchun (`labels`) qoladi — yangi to'lovda taklif
/// qilinmaydi.
class KassaOwners extends ChangeNotifier {
  KassaOwners._();
  static final KassaOwners instance = KassaOwners._();

  /// (kalit, nom) — kassada ko'rsatiladigan faol asoschilar.
  List<(String, String)> active = const [];

  /// Barcha ma'lum asoschi kalitlari → nom (ro'yxatdan chiqqanlar ham).
  Map<String, String> labels = const {
    'nilufar': 'Nilyufar opa',
    'bobur': 'Bobur aka',
  };

  Future<void>? _loading;

  Future<void> load() => _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    try {
      final data = await ApiService().getKassaOwners();
      final list = <(String, String)>[];
      for (final o in (data['owners'] as List? ?? const [])) {
        if (o is! Map) continue;
        final method = o['method']?.toString() ?? '';
        final name = o['name']?.toString() ?? '';
        if (method.startsWith('owner:') && name.isNotEmpty) {
          list.add((method, name));
        }
      }
      final lbl = <String, String>{...labels};
      final raw = data['labels'];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v != null && v.toString().isNotEmpty) lbl['$k'] = v.toString();
        });
      }
      active = list;
      labels = lbl;
      notifyListeners();
    } catch (e) {
      // Server eski versiya yoki tarmoq yo'q — oldingi ro'yxat qoladi.
      debugPrint('KassaOwners: yuklanmadi: $e');
    }
  }

  static bool isOwnerMethod(String m) =>
      m.startsWith('owner:') || m == 'nilufar' || m == 'bobur';
}
