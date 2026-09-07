// core/auth/session.dart — markaziy logout yordamchisi (logoutAndClear): barcha
// global providerlarni ClearableProvider.clear() bilan tozalaydi (socketli
// providerlar ulanishni ham uzadi), login ekraniga qaytaradi va saqlangan
// sessiyani (SharedPreferences) o'chiradi. Har rol home ekranidagi logout tugmasi
// SHUNI chaqiradi — ma'lumot keyingi foydalanuvchiga sizib chiqmasin.
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_filial_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/provider/upload_image_provider.dart';
import 'package:uz_ai_dev/bugalter/provider/bugalter_provider.dart';
import 'package:uz_ai_dev/core/clearable_provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_stock_provider.dart';
import 'package:uz_ai_dev/login_page.dart';
import 'package:uz_ai_dev/ombor/provider/ombor_provider.dart';
import 'package:uz_ai_dev/production/provider/production_orders_provider.dart';
import 'package:uz_ai_dev/production/provider/stock_provider.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';
import 'package:uz_ai_dev/yuk/provider/yuk_provider.dart';

// Logout: barcha provider ma'lumotini va saqlangan sessiyani tozalaydi.
// TARTIB muhim — context navigatsiyadan keyin yaroqsiz bo'ladi, shuning uchun
// provider referenslar OLDIN olinadi va navigatsiya birinchi `await` dan OLDIN
// (sinxron) bajariladi.
Future<void> logoutAndClear(BuildContext context) async {
  // 1. Provider referenslarini oldindan olamiz (13 + 4 ta global provider).
  final providers = <ClearableProvider>[
    context.read<ProductProvider>(),
    context.read<OmborProvider>(),
    context.read<YukProvider>(),
    context.read<BugalterProvider>(),
    context.read<ShefProvider>(),
    context.read<OmborProductionProvider>(),
    context.read<AdminProductionProvider>(),
    context.read<BugalterProductionProvider>(),
    context.read<StockProvider>(),
    context.read<ProductProviderAdmin>(),
    context.read<CategoryProviderAdmin>(),
    context.read<FilialProviderAdmin>(),
    context.read<CategoryProviderAdminUpload>(),
    // Ombor 2.0 (mone_core) — core_token/perms/keshlar ham tozalanadi.
    context.read<CoreSession>(),
    context.read<CoreDictProvider>(),
    context.read<CoreDocsProvider>(),
    context.read<CoreStockProvider>(),
  ];
  // 2. Login ekraniga (butun stack tozalab).
  context.pushAndRemove(const LoginPage());
  // 3. Barcha provider ma'lumotini tozalaymiz (socket uzish clear() ichida).
  for (final p in providers) {
    p.clear();
  }
  // 4. Saqlangan sessiyani o'chiramiz.
  final prefs = await SharedPreferences.getInstance();
  for (final k in ['token', 'refresh_token', 'role', 'user', 'name', 'is_admin']) {
    await prefs.remove(k);
  }
}
