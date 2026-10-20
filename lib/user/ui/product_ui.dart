// user/ui/product_ui.dart — Seller: bitta kategoriya mahsulotlari grid ekrani: ProductsScreen
// (ProductProvider). Bosish -> savatga qo'shadi, uzun bosish -> UserProductDetailUi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';
import 'package:uz_ai_dev/user/ui/user_product_detail_ui.dart';

class ProductsScreen extends StatelessWidget {
  final String categoryName;

  const ProductsScreen({super.key, required this.categoryName});

  static const Color _buttonColor = Color(0xFFC5A97B);
  static const Color _bgColor = Color(0xFFFAF6F1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: Text(categoryName),
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          final products = provider.getProductsByCategory(categoryName);

          if (products.isEmpty) {
            return Center(child: Text('Mahsulotlar topilmadi'));
          }

          return GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final quantity = provider.getProductQuantity(product.id);
              final isSelected = quantity > 0;

              return GestureDetector(
                onTap: () => provider.incrementProduct(product.id),
                onLongPress: () => context.push(
                  UserProductDetailUi(productId: product.id),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rasm
                      Expanded(
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(12)),
                          // AppNetworkImage — kartochka kengligida dekod
                          // qiladi (asl fayl 1024px, RAM ~3 MB bo'lardi).
                          child: AppNetworkImage(
                            imageUrl:
                                "${AppUrls.baseUrl}${product.imageUrl}",
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context) => Container(
                              color: Colors.grey.shade200,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _buttonColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Nom
                      Padding(
                        padding: EdgeInsets.fromLTRB(6, 6, 6, 4),
                        child: Text(
                          product.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      // Tugma
                      Padding(
                        padding: EdgeInsets.fromLTRB(6, 0, 6, 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: isSelected
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: _buttonColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Stack(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.opaque,
                                              onTap: () => provider
                                                  .decrementProduct(
                                                      product.id),
                                              child: Container(
                                                alignment:
                                                    Alignment.centerLeft,
                                                padding: EdgeInsets.only(
                                                    left: 12),
                                                child: Icon(Icons.remove,
                                                    color: Colors.white,
                                                    size: 20),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.opaque,
                                              onTap: () => provider
                                                  .incrementProduct(
                                                      product.id),
                                              child: Container(
                                                alignment:
                                                    Alignment.centerRight,
                                                padding: EdgeInsets.only(
                                                    right: 12),
                                                child: Icon(Icons.add,
                                                    color: Colors.white,
                                                    size: 20),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      // "2шт = 1.8 кг" — tor katakda
                                      // ikonkalar ustiga chiqmasin.
                                      IgnorePointer(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 32),
                                          child: Center(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                formatQtyWithPacks(quantity,
                                                    product.unit,
                                                    product.sellStep),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: () =>
                                      provider.incrementProduct(product.id),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _buttonColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: EdgeInsets.zero,
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Qo\'shish',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
