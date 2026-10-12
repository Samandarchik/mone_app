// test/helpers/catalog_test_env.dart — vidjet testlari uchun GetIt muhiti:
// Dio (ixtiyoriy offline adapter) + HAR chaqiruvda YANGI CatalogRepository
// (ProductProviderAdmin konstruktori sl<CatalogRepository>() ni talab qiladi;
// testlar bir-biridan ajratilgan bo'lsin — `products.products.addAll(...)`
// oldingi testga sizib o'tmasin).
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:uz_ai_dev/core/catalog/catalog_repository.dart';

void registerTestCatalog({Dio? dio}) {
  final sl = GetIt.instance;
  if (!sl.isRegistered<Dio>()) sl.registerSingleton<Dio>(dio ?? Dio());
  if (sl.isRegistered<CatalogRepository>()) {
    sl.unregister<CatalogRepository>();
  }
  sl.registerSingleton<CatalogRepository>(CatalogRepository(sl<Dio>()));
}
