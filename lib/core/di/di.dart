// core/di/di.dart — GetIt DI konteyneri (sl): setupInit() SharedPreferences,
// BaseStorage/TokenStorage va Dio (AppDioClient) singletonlarini ro'yxatlaydi.
// main() dan eng birinchi chaqiriladi.
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core/config/server_config.dart';
import 'package:uz_ai_dev/core/data/local/base_storage.dart';
import 'package:uz_ai_dev/core/data/local/shared_preferences_impl.dart';
import 'package:uz_ai_dev/core/data/local/token_storage.dart';
import 'package:uz_ai_dev/core/network/dio_settings.dart';

final GetIt sl = GetIt.instance;

Future<void> setupInit() async {
  /// Register Dio client
  final SharedPreferences pref = await SharedPreferences.getInstance();

  /// Server manzillari (base_url / core_url) — AppUrls shundan o'qiydi.
  ServerConfig.load(pref);

  /// register local storage
  sl.registerLazySingleton<BaseStorage>(() => SharedPreferencesImpl(pref));
  sl.registerLazySingleton<TokenStorage>(() => TokenStorage(sl<BaseStorage>()));

  final dioClient = AppDioClient();
  final dio = dioClient.createDio();
  sl.registerLazySingleton<Dio>(() => dio);
}
