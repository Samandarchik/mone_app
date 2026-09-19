// main.dart — ilova kirish nuqtasi: main() DI'ni (setupInit) ishga tushiradi,
// MultiProvider'da barcha global ChangeNotifier providerlarni ro'yxatlaydi va
// MyApp (MaterialApp) home = SplashScreen bilan ishga tushadi.
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/bugalter/provider/bugalter_provider.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/core/di/di.dart';
import 'package:uz_ai_dev/core/services/windows_update_service.dart';
import 'package:uz_ai_dev/core/utils/app_navigator.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/ombor/provider/ombor_provider.dart';
import 'package:uz_ai_dev/production/provider/production_orders_provider.dart';
import 'package:uz_ai_dev/production/provider/stock_provider.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/yuk/provider/yuk_provider.dart';
import 'package:uz_ai_dev/splash_screen.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupInit();

  // Sklad nomlari (tab/dropdown/kartalar) — avval keshdan, keyin splash'da
  // serverdan yangilanadi (core/data/sklad_registry.dart).
  await SkladRegistry.load();

  // Windows'da ochiq turgan ilova yangi release'ni o'tkazib yubormasligi
  // uchun davriy (30 daqiqada) avto-yangilanish tekshiruvi.
  WindowsUpdateService.startPeriodicChecks();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => OmborProvider()),
        ChangeNotifierProvider(create: (_) => YukProvider()),
        ChangeNotifierProvider(create: (_) => BugalterProvider()),
        ChangeNotifierProvider(create: (_) => ShefProvider()),
        // Ishlab chiqarish (ombor/admin/bugalter) + sklad qoldig'i.
        ChangeNotifierProvider(create: (_) => OmborProductionProvider()),
        ChangeNotifierProvider(create: (_) => AdminProductionProvider()),
        ChangeNotifierProvider(create: (_) => BugalterProductionProvider()),
        ChangeNotifierProvider(create: (_) => StockProvider()),
        ChangeNotifierProvider(create: (_) => ProductProviderAdmin()),
        ChangeNotifierProvider(create: (_) => CategoryProviderAdmin()),
        ChangeNotifierProvider(create: (_) => FilialProviderAdmin()),
        ChangeNotifierProvider(create: (_) => CategoryProviderAdminUpload()),
        // Ombor 2.0 (mone_core /api/v2): sessiya (core_token + perms),
        // lug'atlar keshi, hujjatlar ro'yxati, qoldiq keshi.
        ChangeNotifierProvider(create: (_) => CoreSession()),
        ChangeNotifierProvider(create: (_) => CoreDictProvider()),
        ChangeNotifierProvider(create: (_) => CoreDocsProvider()),
        ChangeNotifierProvider(create: (_) => CoreStockProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'User Panel',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          surfaceTintColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
        ),
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
