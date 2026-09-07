// admin/ui/admin_home_ui.dart — admin bosh ekrani: kategoriyalar ro'yxati
// (AdminHomeUi): CategoryProviderAdmin + ProductProviderAdmin; AppBar'da qidiruv
// (_AdminProductSearchDelegate), narx badge (→ProfitControlUi), reorder rejimi va
// menyu (kategoriya/analitika/sklad qoldiqlari/audit/POS/filial/skladlar/pf), logout.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/model/product_model.dart';
import 'package:uz_ai_dev/admin/model/tech_card_cost.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/ui/admin_add_categoriy.dart';
import 'package:uz_ai_dev/admin/ui/admin_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/analytics_hub_ui.dart';
import 'package:uz_ai_dev/admin/ui/audit_log_ui.dart';
import 'package:uz_ai_dev/admin/ui/convert_pf_ui.dart';
import 'package:uz_ai_dev/admin/ui/filials_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_hub_ui.dart';
import 'package:uz_ai_dev/admin/ui/profit_control_ui.dart';
import 'package:uz_ai_dev/admin/ui/rk7_hub_ui.dart';
import 'package:uz_ai_dev/admin/ui/sh5_ostatka_ui.dart';
import 'package:uz_ai_dev/admin/ui/sklads_ui.dart';
import 'package:uz_ai_dev/admin/ui/admin_stock_ui.dart';
import 'package:uz_ai_dev/admin/ui/widgets/dashboard_card.dart';
import 'package:uz_ai_dev/admin/ui/user_management_screen.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/core_hub_ui.dart';
import 'package:uz_ai_dev/production/models/latest_price_model.dart';
import 'package:uz_ai_dev/production/services/production_service.dart';
import 'package:uz_ai_dev/production/ui/production_plan_page.dart';

class AdminHomeUi extends StatefulWidget {
  const AdminHomeUi({super.key});

  @override
  State<AdminHomeUi> createState() => _AdminHomeUiState();
}

class _AdminHomeUiState extends State<AdminHomeUi> {
  bool _isEditMode = false;

  // Oxirgi xarid narxlari — AppBar'dagi «narx almashtirish» badge hisobi
  // uchun. Xatoda JIM (badge shunchaki ko'rinmaydi).
  Map<int, LatestPrice> _prices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadInitialData();
    });
  }

  // Kategoriyalar va barcha mahsulotlarni bir marta yuklash
  Future<void> _loadInitialData({bool forceRefresh = false}) async {
    final categoryProvider = context.read<CategoryProviderAdmin>();
    final productProvider = context.read<ProductProviderAdmin>();

    // Parallel ravishda yuklash
    await Future.wait([
      categoryProvider.getCategories(),
      productProvider.initializeProducts(forceRefresh: forceRefresh),
      _loadPrices(),
    ]);
  }

  Future<void> _loadPrices() async {
    try {
      final prices = await ProductionService().fetchLatestPrices();
      if (!mounted) return;
      setState(() => _prices = prices);
    } catch (_) {
      // jim — badge ko'rinmaydi, sahifa ishlayveradi
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.push(UserManagementScreen()),
          icon: const Icon(Icons.people),
        ),
        title: const Text('Admin Panel'),
        actions: [
          // Narxi almashtirilishi kerak mahsulotlar soni (qizil badge).
          // Bosilsa «Foyda nazorati» ochiladi — u yerda [Almashtirish] bor.
          Consumer<ProductProviderAdmin>(
            builder: (context, productProvider, _) {
              final count =
                  techPriceReplaceCount(productProvider.products, _prices);
              return IconButton(
                tooltip: 'Narxni almashtirish kerak',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfitControlUi()),
                  );
                  // Qaytganda narxlarni yangilaymiz (sale_price'lar
                  // provider orqali o'zi yangilanadi).
                  _loadPrices();
                },
                icon: Badge.count(
                  count: count,
                  isLabelVisible: count > 0,
                  child: const Icon(Icons.price_change_outlined),
                ),
              );
            },
          ),
          IconButton(
            onPressed: () {
              final productProvider = context.read<ProductProviderAdmin>();
              showSearch(
                context: context,
                delegate: _AdminProductSearchDelegate(productProvider),
              );
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
            icon: Icon(_isEditMode ? Icons.check : Icons.edit),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.menu),
            itemBuilder: (_) => [
              // Ombor 2.0 — mone_core (/api/v2) hujjat oqimlari hub'i.
              const PopupMenuItem(
                value: 'core_hub',
                child: ListTile(
                  leading: Icon(Icons.warehouse),
                  title: Text('Ombor 2.0'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'categories',
                child: ListTile(
                  leading: Icon(Icons.category),
                  title: Text('Kategoriyalar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'analytics_hub',
                child: ListTile(
                  leading: Icon(Icons.insights),
                  title: Text('Analitika'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'stock',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Sklad qoldiqlari'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'production_plan',
                child: ListTile(
                  leading: Icon(Icons.event_note),
                  title: Text('Ishlab chiqarish rejasi'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'audit_log',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Audit jurnali'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'pos_hub',
                child: ListTile(
                  leading: Icon(Icons.point_of_sale),
                  title: Text('POS (Konak)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'rk7_hub',
                child: ListTile(
                  leading: Icon(Icons.sync_alt),
                  title: Text('RK7'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'sh5_ostatka',
                child: ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Ostatka (SH5)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'filials',
                child: ListTile(
                  leading: Icon(Icons.store_outlined),
                  title: Text('Filiallar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'sklads',
                child: ListTile(
                  leading: Icon(Icons.warehouse_outlined),
                  title: Text('Skladlar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'convert_pf',
                child: ListTile(
                  leading: Icon(Icons.published_with_changes),
                  title: Text('Полуфабрикатga o\'tkazish'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'server_settings',
                child: ListTile(
                  leading: Icon(Icons.dns_outlined),
                  title: Text('Server sozlamalari'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'core_hub':
                  context.push(const CoreHubUi());
                  break;
                case 'server_settings':
                  final saved = await showServerSettingsDialog(context);
                  if (saved && context.mounted) {
                    // Yangi yadro manziliga qayta ulanamiz.
                    context.read<CoreSession>().retry();
                  }
                  break;
                case 'categories':
                  context.push(const CategoryManagementScreen());
                  break;
                case 'analytics_hub':
                  context.push(const AnalyticsHubUi());
                  break;
                case 'stock':
                  context.push(const AdminStockUi());
                  break;
                case 'production_plan':
                  context.push(const ProductionPlanPage());
                  break;
                case 'audit_log':
                  context.push(const AuditLogUi());
                  break;
                case 'pos_hub':
                  context.push(const PosHubUi());
                  break;
                case 'rk7_hub':
                  context.push(const Rk7HubUi());
                  break;
                case 'sh5_ostatka':
                  context.push(const Sh5OstatkaUi());
                  break;
                case 'filials':
                  context.push(const FilialsUi());
                  break;
                case 'sklads':
                  context.push(const SkladsUi());
                  break;
                case 'convert_pf':
                  context.push(const ConvertPfUi());
                  break;
              }
            },
          ),
          IconButton(
            onPressed: () => logoutAndClear(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
        builder: (context, categoryProvider, productProvider, child) {
          // Loading holati
          if ((categoryProvider.isLoading &&
                  categoryProvider.categories.isEmpty) ||
              (productProvider.isLoading && !productProvider.isInitialized)) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          // Xatolik holati
          if (categoryProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Ошибка: ${categoryProvider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _loadInitialData(forceRefresh: true),
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            );
          }

          // Bo'sh holat
          if (categoryProvider.categories.isEmpty) {
            return const Center(child: Text('Kategoriyalar topilmadi'));
          }

          if (_isEditMode) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: categoryProvider.categories.length,
              onReorderItem: (oldIndex, newIndex) {
                categoryProvider.reorderCategories(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final category = categoryProvider.categories[index];
                return ListTile(
                  key: ValueKey(category.id),
                  contentPadding: EdgeInsets.zero,
                  leading: ClipOval(
                    child: category.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl:
                                "${AppUrls.baseUrl}${category.imageUrl}",
                            width: 55,
                            height: 55,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.image_not_supported),
                          )
                        : Container(
                            width: 55,
                            height: 55,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.image_not_supported),
                          ),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.drag_handle,
                    size: 24,
                    color: Colors.grey,
                  ),
                );
              },
            );
          }

          return RefreshIndicator(
            onRefresh: () => _loadInitialData(forceRefresh: true),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              // index 0 — boshqaruv paneli (DashboardCard), qolgani kategoriyalar.
              itemCount: categoryProvider.categories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const DashboardCard();
                final category = categoryProvider.categories[index - 1];

                final productCount =
                    productProvider.getProductCountByCategory(category.id);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipOval(
                    child: GestureDetector(
                      onTap: () {
                        if (category.imageUrl != null) {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: CachedNetworkImage(
                                imageUrl:
                                    "${AppUrls.baseUrl}${category.imageUrl}",
                                fit: BoxFit.contain,
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                  Icons.error,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      child: category.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl:
                                  "${AppUrls.baseUrl}${category.imageUrl}",
                              width: 55,
                              height: 55,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.image_not_supported),
                            )
                          : Container(
                              width: 55,
                              height: 55,
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image_not_supported),
                            ),
                    ),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    'ID: ${category.id} • $productCount продукт',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onTap: () {
                    context.push(AdminProductUi(
                      categoryId: category.id,
                      categoryName: category.name,
                    ));
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AdminProductSearchDelegate extends SearchDelegate<String> {
  final ProductProviderAdmin productProvider;

  _AdminProductSearchDelegate(this.productProvider)
      : super(searchFieldLabel: 'Mahsulot qidirish...');

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () => query = '',
          icon: const Icon(Icons.clear),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, ''),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchList(context);

  Widget _buildSearchList(BuildContext context) {
    final results = query.isEmpty
        ? <ProductModelAdmin>[]
        : productProvider.products.where((p) {
            final q = query.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.categoryName.toLowerCase().contains(q) ||
                (p.companyName?.toLowerCase().contains(q) ?? false);
          }).toList();

    if (query.isEmpty) {
      return const Center(
        child: Text(
          'Mahsulot nomini kiriting',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'Hech narsa topilmadi',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final product = results[index];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.image_not_supported),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image_not_supported),
                  ),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${product.categoryName} • ${product.type}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            close(context, '');
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminProductUi(
                  categoryId: product.categoryId,
                  categoryName: product.categoryName,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
