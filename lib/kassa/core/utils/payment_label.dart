import 'package:flutter/material.dart';

import '../services/kassa_owners.dart';
import '../theme/app_theme.dart';

/// Asoschilar tugmalari ranglari (tartib bo'yicha aylanadi).
const _ownerColors = <Color>[
  Color(0xFFD6336C),
  Color(0xFF7048E8),
  Color(0xFFE8590C),
  Color(0xFF0CA678),
  Color(0xFF1C7ED6),
  Color(0xFFAE3EC9),
];

/// To'lov usullari — YAGONA ro'yxat (kalit, nom, ikonka, rang).
/// To'lov oynasi, aralash to'lov, smena/moliya hisobotlari shundan oladi.
/// Kalitlar backend'dagi `validPaymentMethods` bilan bir xil bo'lishi shart.
///
/// «Ichki hisob» (egalar olgan narsalar) — qotirilgan emas: qilinadigan_ishlar
/// «Получатель расхода (владелец)» userlari (`KassaOwners`, kalit `owner:<id>`).
List<(String, String, IconData, Color)> get kPaymentMethods {
  final owners = KassaOwners.instance.active;
  return [
    ('cash', 'Naqd', Icons.payments_rounded, AppColors.success),
    ('card', 'Karta', Icons.credit_card_rounded, AppColors.info),
    ('payme', 'Payme', Icons.qr_code_2_rounded, const Color(0xFF00C9A7)),
    ('click', 'Click', Icons.qr_code_2_rounded, const Color(0xFF1A65EB)),
    for (var i = 0; i < owners.length; i++)
      (
        owners[i].$1,
        owners[i].$2,
        Icons.person_rounded,
        _ownerColors[i % _ownerColors.length],
      ),
    ('other', 'Boshqa', Icons.more_horiz_rounded, AppColors.textFaint),
  ];
}

/// Asoschi kaliti uchun rang (hisobot qatorlari).
Color ownerColor(String method) {
  final i = KassaOwners.instance.active.indexWhere((o) => o.$1 == method);
  return i >= 0 ? _ownerColors[i % _ownerColors.length] : const Color(0xFF7048E8);
}

/// Server to'lov usuli kaliti (cash/card/…) → ekrandagi o'zbekcha nom.
String paymentLabel(String? value) => switch (value ?? '') {
  'cash' => 'Naqd',
  'card' => 'Karta',
  'payme' => 'Payme',
  'click' => 'Click',
  'split' => 'Aralash',
  'other' => 'Boshqa',
  '' => 'Boshqa',
  final v => KassaOwners.instance.labels[v] ??
      (v.startsWith('owner:') ? 'Asoschi #${v.substring(6)}' : v),
};

/// Hisobot qatorlari: `kPaymentMethods` + hisobotda summasi bor, lekin hozir
/// faol bo'lmagan asoschi kalitlari (eski nilufar/bobur, ro'yxatdan chiqqan
/// `owner:<id>`) — jami bilan qatorlar yig'indisi mos tushsin.
List<(String, String, IconData, Color)> reportPaymentMethods(
    Map<String, dynamic> byPayment) {
  final base = kPaymentMethods;
  final known = {for (final m in base) m.$1};
  final extra = <(String, String, IconData, Color)>[
    for (final e in byPayment.entries)
      if (!known.contains(e.key) &&
          KassaOwners.isOwnerMethod(e.key) &&
          e.value is num &&
          (e.value as num) != 0)
        (e.key, paymentLabel(e.key), Icons.person_rounded, ownerColor(e.key)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final i = base.indexWhere((m) => m.$1 == 'other');
  return [...base.sublist(0, i), ...extra, ...base.sublist(i)];
}
