// core2/services/core_integration_service.dart — mone_core integratsiya
// (perm integration.manage): sotuv nuqtalari (GET/POST/PUT /sale-points),
// API kalitlar (GET/POST/DELETE /api-keys — kalit faqat POST javobida),
// webhooklar (GET/POST/PUT/DELETE /webhooks).
import 'package:uz_ai_dev/core2/models/core_integration.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

class CoreIntegrationService {
  Future<List<CoreSalePoint>> salePoints() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/sale-points'));
      return CoreClient.listOf(r.data).map(CoreSalePoint.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreSalePoint> saveSalePoint(CoreSalePoint p) async {
    try {
      final r = p.id > 0
          ? await CoreClient.dio
              .put(CoreClient.url('/sale-points/${p.id}'), data: p.toJson())
          : await CoreClient.dio.post(CoreClient.url('/sale-points'),
              data: p.toJson(), options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? p : CoreSalePoint.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreApiKey>> apiKeys() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/api-keys'));
      return CoreClient.listOf(r.data).map(CoreApiKey.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  /// Javobdagi `key` faqat shu yerda bir marta keladi.
  Future<CoreApiKey> createApiKey(String name, List<String> scopes) async {
    try {
      final r = await CoreClient.dio.post(
        CoreClient.url('/api-keys'),
        data: {'name': name, 'scopes': scopes},
        options: CoreClient.idem(),
      );
      final m = CoreClient.mapOf(r.data);
      return CoreApiKey.fromJson({'name': name, 'scopes': scopes, ...m});
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<void> deleteApiKey(int id) async {
    try {
      await CoreClient.dio.delete(CoreClient.url('/api-keys/$id'));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<List<CoreWebhook>> webhooks() async {
    try {
      final r = await CoreClient.dio.get(CoreClient.url('/webhooks'));
      return CoreClient.listOf(r.data).map(CoreWebhook.fromJson).toList();
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<CoreWebhook> saveWebhook(CoreWebhook w) async {
    try {
      final r = w.id > 0
          ? await CoreClient.dio
              .put(CoreClient.url('/webhooks/${w.id}'), data: w.toJson())
          : await CoreClient.dio.post(CoreClient.url('/webhooks'),
              data: w.toJson(), options: CoreClient.idem());
      final m = CoreClient.mapOf(r.data);
      return m.isEmpty ? w : CoreWebhook.fromJson(m);
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }

  Future<void> deleteWebhook(int id) async {
    try {
      await CoreClient.dio.delete(CoreClient.url('/webhooks/$id'));
    } catch (e) {
      throw CoreClient.wrap(e);
    }
  }
}
