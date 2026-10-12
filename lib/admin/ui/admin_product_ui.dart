// admin/ui/admin_product_ui.dart — kategoriya ichidagi mahsulotlar ro'yxati
// (AdminProductUi): ProductProviderAdmin.filteredProducts + ApiPdfService (PDF ulashish);
// single tap tahrir (EditProductPage), double tap tex karta editori, long press
// o'chirish, «i» ikona — tex karta. Reorder rejimi va ПФ belgisi bor.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/catalog/product.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/admin/services/get_pdf_service.dart';
import 'package:uz_ai_dev/admin/ui/admin_add_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/admin_edit_product_ui.dart';
import 'package:uz_ai_dev/admin/ui/tech_card_editor_page.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';

class AdminProductUi extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  

  const AdminProductUi({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<AdminProductUi> createState() => _AdminProductUiState();
}

class _AdminProductUiState extends State<AdminProductUi> {
  final ApiPdfService pdfService = ApiPdfService();
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0);
  bool _isDownloading = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _filterProducts();
      // Eski PDF fayllarni tozalash (optional)
      pdfService.cleanupOldPdfs();
    });
  }

  @override
  void dispose() {
    _progressNotifier.dispose();
    // Widget yopilganda PDF ni o'chirish (optional)
    pdfService.deleteCategoryPdf(widget.categoryId);
    super.dispose();
  }

  void _filterProducts() {
    final productProvider = context.read<ProductProviderAdmin>();
    productProvider.filterByCategory(widget.categoryId);
  }

  Future<void> _refreshProducts() async {
    final productProvider = context.read<ProductProviderAdmin>();
    await productProvider.initializeProducts(forceRefresh: true);
    _filterProducts();
  }

  Future<void> _downloadAndSharePdf() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);
    _progressNotifier.value = 0;

    debugPrint('\n🟢 ========== UI: YUKLASH BOSHLANDI ==========');
    final uiStopwatch = Stopwatch()..start();

    if (!mounted) return;

    // Progress dialog with ValueNotifier
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: ValueListenableBuilder<double>(
            valueListenable: _progressNotifier,
            builder: (context, progress, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    value: progress > 0 ? progress / 100 : null,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    progress > 0
                        ? 'Загрузка: ${progress.toStringAsFixed(0)}%'
                        : 'Подготовка...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (progress > 0) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: Colors.grey[200],
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      // Download va Share with progress callback
      await pdfService.downloadAndSharePdf(
        widget.categoryId,
        onProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100);
            _progressNotifier.value = progress;
            debugPrint('📊 UI Progress: ${progress.toStringAsFixed(1)}%');
          }
        },
        shareText: '${widget.categoryName} - Mahsulotlar katalogi',
      );

      // Close dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('✓ PDF tayyor!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      uiStopwatch.stop();
      debugPrint(
          '⏱ ========== UI: JAMI VAQT: ${uiStopwatch.elapsedMilliseconds}ms ==========\n');
    } catch (e) {
      // Close dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.toString().replaceAll('Exception:', '').trim(),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      uiStopwatch.stop();
      debugPrint(
          '⏱ ========== UI: XATOLIK VAQTI: ${uiStopwatch.elapsedMilliseconds}ms ==========\n');
    } finally {
      _progressNotifier.value = 0;
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        actions: [
          IconButton(
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
            icon: Icon(_isEditMode ? Icons.check : Icons.edit),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _progressNotifier,
            builder: (context, progress, child) {
              if (_isDownloading && progress > 0) {
                return Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: progress / 100,
                          strokeWidth: 2,
                          backgroundColor: Colors.grey[300],
                        ),
                      ),
                      Text(
                        '${progress.toInt()}',
                        style: const TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                );
              }
              return IconButton(
                onPressed: _isDownloading ? null : _downloadAndSharePdf,
                icon: _isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                tooltip: 'PDF ulashish',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              // createProduct provider ro'yxatini lokal yangilaydi — qayta GET shart emas.
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddProductPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ProductProviderAdmin>(
        builder: (context, productProvider, child) {
          // Loading holati
          if (productProvider.isLoading) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          // Bo'sh holat
          if (productProvider.filteredProducts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bu kategoriyada mahsulotlar yo\'q',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          }

          if (_isEditMode) {
            return ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: productProvider.filteredProducts.length,
              onReorderItem: (oldIndex, newIndex) {
                productProvider.reorderProducts(
                    widget.categoryId, oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final product = productProvider.filteredProducts[index];
                return ListTile(
                  key: ValueKey(product.id),
                  leading: ClipOval(
                    child: product.imageUrl.isNotEmpty
                        ? AppNetworkImage(
                            imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
                            width: 55,
                            height: 55,
                            fit: BoxFit.cover,
                            errorWidget: (context) =>
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
                    product.name,
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
            onRefresh: _refreshProducts,
            child: ListView.separated(
              separatorBuilder: (context, index) => const Divider(),
              padding: const EdgeInsets.all(8),
              itemCount: productProvider.filteredProducts.length,
              itemBuilder: (context, index) {
                final product = productProvider.filteredProducts[index];
                return _buildProductListTile(context, product);
              },
            ),
          );
        },
      ),
    );
  }

  // Mahsulot ichida tarkib (tex karta) bormi — «i» ikonani shartli ko'rsatish uchun.
  bool _hasTechCard(Product product) {
    final tc = product.techCard;
    if (tc == null) return false;
    return tc.bases.any((b) => b.ingredients.isNotEmpty) ||
        tc.consumables.isNotEmpty;
  }

  // Tahrirlash/qo'shish/tex-karta saqlangach provider o'zini lokal yangilaydi
  // (updateProduct/createProduct + notifyListeners). Shuning uchun bu yerda
  // butun bazani QAYTA GET qilmaymiz — Consumer o'zi qayta chizadi.
  Future<void> _openEditPage(Product product) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProductPage(product: product),
      ),
    );
  }

  Future<void> _openTechCard(Product product) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TechCardEditorPage(product: product),
      ),
    );
  }

  Widget _buildProductListTile(
      BuildContext context, Product product) {
    // Bitta bosish → mahsulotni tahrirlash (avalgi sahifa).
    // Ikki marta bosish (double-tap) → tex karta (состав) sahifasi.
    // Bosib turish → o'chirish. «i» ikona ham tex kartani ochadi (tarkibi bor bo'lsa).
    return GestureDetector(
      onTap: () => _openEditPage(product),
      onDoubleTap: () => _openTechCard(product),
      onLongPress: () => _showDeleteConfirmDialog(context, product),
      child: ListTile(
        trailing: _hasTechCard(product)
            ? IconButton(
                icon: const Icon(Icons.info_outline),
                color: Theme.of(context).colorScheme.primary,
                tooltip: 'Тех карта',
                onPressed: () => _openTechCard(product),
              )
            : null,
        leading: ClipOval(
        child: GestureDetector(
          onTap: () {
            if (product.imageUrl.isNotEmpty) {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: AppNetworkImage(
                    imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
                    fit: BoxFit.contain,
                    errorWidget: (context) =>
                        const Icon(Icons.error, size: 40, color: Colors.white),
                  ),
                ),
              );
            }
          },
          child: product.imageUrl.isNotEmpty
              ? AppNetworkImage(
                  imageUrl: "${AppUrls.baseUrl}${product.imageUrl}",
                  width: 55,
                  height: 55,
                  fit: BoxFit.cover,
                  errorWidget: (context) =>
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
        title: Row(
          children: [
            Flexible(
              child: Text(
                '${product.name} (${product.unit})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            // Полуфабрикат belgisi.
            if (product.isPf)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  border: Border.all(color: Colors.purple.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ПФ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(
      BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить'),
        content: Text('${product.name} Вы хотите удалить продукт?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final success = await context
                  .read<ProductProviderAdmin>()
                  .deleteProduct(product);

              if (success && context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Продукт удален')),
                );
              } else if (context.mounted) {
                // Server sababi bilan rad etdi (masalan: retseptlarda
                // ishlatilgan — avval o'sha tex kartalardan olib tashlash kerak).
                Navigator.pop(context);
                final err = context.read<ProductProviderAdmin>().error ??
                    'O\'chirib bo\'lmadi';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err.replaceFirst('Exception: ', '')),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 7),
                  ),
                );
              }
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
