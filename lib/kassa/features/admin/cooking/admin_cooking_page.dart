import 'package:flutter/material.dart';

import '../../pos/cooking/cooking_screen.dart';
import '../widgets/admin_page.dart';

/// «Pishirish» bo'limi — POS'dagi ekranning o'zi, lekin admin panelida
/// sarlavha bilan.
///
/// Ekran POS qobig'ida ham ishlatiladi (u yerda o'z sarlavhasi bor), shuning
/// uchun ekranning ichiga tegilmaydi: bu yerda faqat admin karkasi kiyiladi.
class AdminCookingPage extends StatelessWidget {
  const AdminCookingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPage(
      subtitle: 'Yarim tayyor mahsulotlarni tayyorlash va omborga yozish',
      padded: false,
      constrained: false,
      child: CookingScreen(),
    );
  }
}
