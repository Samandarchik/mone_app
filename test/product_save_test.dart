import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'helpers/catalog_test_env.dart';

void main() {
  tearDown(() async => GetIt.instance.reset());

  test('create server ID sini qaytaradi, update shu ID bilan PUT qiladi',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      handler.resolve(Response(
        requestOptions: options,
        statusCode: options.method == 'POST' ? 201 : 200,
        data: {
          'data': {...Map<String, dynamic>.from(options.data as Map), 'id': 72}
        },
      ));
    }));
    registerTestCatalog(dio: dio);
    final provider = ProductProviderAdmin()..filterByCategory(2);
    final created = await provider.saveProduct(Product(
        id: 0, name: 'Krem', categoryId: 2, unit: 'шт', kind: ProductKind.pf));
    expect(created!.id, 72);
    expect(provider.productById(72), same(created));
    expect(provider.filteredProducts.single.id, 72);
    expect(requests.single.method, 'POST');
    expect(requests.single.path, AppUrls.product);
    final updated =
        await provider.saveProduct(created.copyWith(name: 'Yangi krem'));
    expect(updated!.name, 'Yangi krem');
    expect(requests.last.method, 'PUT');
    expect(requests.last.path, '${AppUrls.product}/72');
    expect(provider.products, hasLength(1));
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
    provider.dispose();
  });

  test('server rad etsa katalog va saqlangan mahsulot o‘zgarmaydi', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
        requestOptions: options,
        response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {'message': 'Saqlash mumkin emas'}),
        type: DioExceptionType.badResponse,
      ));
    }));
    registerTestCatalog(dio: dio);
    final provider = ProductProviderAdmin();
    final product = Product(id: 8, name: 'Un');
    provider.products.add(product);
    expect(
        await provider.saveProduct(product.copyWith(name: 'Boshqa')), isNull);
    expect(provider.products.single, same(product));
    expect(provider.error, contains('Saqlash mumkin emas'));
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });
}
