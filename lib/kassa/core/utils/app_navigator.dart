import 'package:flutter/material.dart';

/// Global navigator kaliti — kontekstsiz (masalan avto-yangilash xizmatidan)
/// dialog ochish / navigatsiya qilish uchun. `MaterialApp.navigatorKey`'ga
/// ulanadi (`lib/main.dart`).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Global SnackBar kaliti — ekran kontekstisiz xabar ko'rsatish uchun
/// (masalan token yaroqsiz bo'lib ilova login ekraniga qaytarilganda).
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
