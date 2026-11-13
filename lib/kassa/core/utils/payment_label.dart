import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// To'lov usullari — YAGONA ro'yxat (kalit, nom, ikonka, rang).
/// To'lov oynasi, aralash to'lov, smena/moliya hisobotlari shundan oladi.
/// Kalitlar backend'dagi `validPaymentMethods` bilan bir xil bo'lishi shart.
const kPaymentMethods = <(String, String, IconData, Color)>[
  ('cash', 'Naqd', Icons.payments_rounded, AppColors.success),
  ('card', 'Karta', Icons.credit_card_rounded, AppColors.info),
  ('payme', 'Payme', Icons.qr_code_2_rounded, Color(0xFF00C9A7)),
  ('click', 'Click', Icons.qr_code_2_rounded, Color(0xFF1A65EB)),
  // Ichki hisob — egalari olgan narsalar
  ('nilufar', 'Nilyufar opa', Icons.person_rounded, Color(0xFFD6336C)),
  ('bobur', 'Bobur aka', Icons.person_rounded, Color(0xFF7048E8)),
  ('other', 'Boshqa', Icons.more_horiz_rounded, AppColors.textFaint),
];

/// Server to'lov usuli kaliti (cash/card/…) → ekrandagi o'zbekcha nom.
String paymentLabel(String? value) => switch (value ?? '') {
  'cash' => 'Naqd',
  'card' => 'Karta',
  'payme' => 'Payme',
  'click' => 'Click',
  'nilufar' => 'Nilyufar opa',
  'bobur' => 'Bobur aka',
  'split' => 'Aralash',
  'other' => 'Boshqa',
  '' => 'Boshqa',
  final v => v,
};
