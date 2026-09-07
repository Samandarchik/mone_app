// user/ui/user_home_ui.dart — Seller roli bosh ekrani: UserHomeUi (ProductProvider). Qidiruv,
// kategoriyalar va kartochkalar; savat (CartPage) hamda buyurtmalar (OrdersPage) ga o'tish.
// «Ostatka» tugmasi FAQAT ruxsat berilganda chiqadi: ekran ochilganda
// /api/sh5/remains so'raladi (backend userga biriktirilganini qaytaradi) —
// ro'yxat bo'sh bo'lsa tugma umuman ko'rinmaydi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uz_ai_dev/admin/services/sh5_service.dart';
import 'package:uz_ai_dev/admin/ui/sh5_ostatka_ui.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_entry_menu.dart';
import 'package:uz_ai_dev/user/provider/provider.dart';
import 'package:uz_ai_dev/user/ui/order_ui.dart';
import 'package:uz_ai_dev/user/ui/orders_page.dart';
import 'package:uz_ai_dev/user/ui/product_ui.dart';
import 'package:uz_ai_dev/user/ui/user_product_detail_ui.dart';

class UserHomeUi extends StatefulWidget {
  const UserHomeUi({super.key});

  @override
  State<UserHomeUi> createState() => _UserHomeUiState();
}

class _UserHomeUiState extends State<UserHomeUi> {
  String name = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  // Ostatka (SH5) ruxsati bormi — tugmani ko'rsatish uchun.
  bool _hasOstatka = false;

  static const Color _buttonColor = Color(0xFFC5A97B);
  static const Color _bgColor = Color(0xFFFAF6F1);

  Future<void> getMe() async {
    final prefs = await SharedPreferences.getInstance();
    var savedName = prefs.getString('name') ?? '';
    // Eski o'rnatishlar nomni jsonEncode bilan ("Ism") saqlagan —
    // atrofidagi qo'shtirnoqlarni olib tashlaymiz (backward-compat).
    if (savedName.length >= 2 &&
        savedName.startsWith('"') &&
        savedName.endsWith('"')) {
      savedName = savedName.substring(1, savedName.length - 1);
    }
    if (!mounted) return;
    setState(() {
      name = savedName;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductProvider>().fetchCategories();
      context.read<ProductProvider>().fetchProducts();
    });
    getMe();
    _checkOstatka();
  }

  // Ruxsat tekshiruvi: bo'sh ro'yxat yoki xato — tugma chiqmaydi (jim).
  Future<void> _checkOstatka() async {
    try {
      final sklads = await Sh5Service().fetchSklads();
      if (!mounted) return;
      if (sklads.isNotEmpty) setState(() => _hasOstatka = true);
    } catch (_) {
      // Ruxsat yo'q yoki tarmoq xatosi — bosh ekran o'z ishida davom etadi.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: IconButton(
            onPressed: () => _showContactDialog(context),
            icon: Icon(Icons.info_outline)),
        title: Text(name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              onPressed: () => logoutAndClear(context),
              icon: Icon(Icons.logout)),
          // Ombor 2.0 (mone_core): Hujjatlar / Qoldiq / Bozor приход —
          // perms bo'yicha; yadro sessiyasi bo'lmasa ko'rinmaydi.
          const CoreEntryMenu(),
          if (_hasOstatka)
            IconButton(
                tooltip: 'Ostatka',
                onPressed: () => context.push(const Sh5OstatkaUi()),
                icon: Icon(Icons.inventory_2_outlined)),
          IconButton(
              onPressed: () => context.push(OrdersPage()),
              icon: Icon(Icons.receipt_long)),
        ],
      ),
      body: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.errorMessage != null) {
            return Center(child: Text('Xatolik: ${provider.errorMessage}'));
          }

          final query = _searchQuery.toLowerCase();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Mahsulot qidirish...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            icon: Icon(Icons.clear, color: Colors.grey),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(bottom: 80),
                  itemCount: provider.categories.length,
                  itemBuilder: (context, index) {
                    final category = provider.categories[index];
                    final allProducts =
                        provider.getProductsByCategory(category.name);

                    final products = query.isEmpty
                        ? allProducts
                        : allProducts.where((p) {
                            return p.name.toLowerCase().contains(query) ||
                                (p.category?.toLowerCase().contains(query) ?? false);
                          }).toList();

                    if (products.isEmpty) {
                      return SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    category.name,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    context.push(ProductsScreen(
                                      categoryName: category.name,
                                    ));
                                  },
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                          color: Colors.grey.shade400, width: 1),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'barchasi',
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.chevron_right,
                                          color: Colors.black54, size: 18),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 280,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              itemCount: products.length,
                              itemBuilder: (context, pIndex) {
                                final product = products[pIndex];
                                final quantity =
                                    provider.getProductQuantity(product.id);
                                return _ProductCard(
                                  imageUrl:
                                      "${AppUrls.baseUrl}${product.imageUrl}",
                                  name: product.name,
                                  quantity: quantity,
                                  quantityText:
                                      formatQty(quantity, product.type),
                                  type: product.type,
                                  buttonColor: _buttonColor,
                                  onTap: () =>
                                      provider.incrementProduct(product.id),
                                  onLongPress: () => context.push(
                                    UserProductDetailUi(productId: product.id),
                                  ),
                                  onAdd: () =>
                                      provider.incrementProduct(product.id),
                                  onRemove: () =>
                                      provider.decrementProduct(product.id),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<ProductProvider>(
        builder: (context, provider, child) {
          if (provider.totalSelectedProducts > 0) {
            return FloatingActionButton.extended(
              backgroundColor: _buttonColor,
              onPressed: () async {
                context.push(CartPage());
              },
              icon: Icon(Icons.shopping_basket_outlined, color: Colors.white),
              label: Text(
                provider.totalSelectedProducts % 1 == 0
                    ? provider.totalSelectedProducts.toInt().toString()
                    : provider.totalSelectedProducts.toStringAsFixed(3),
                style: TextStyle(color: Colors.white),
              ),
            );
          }
          return SizedBox.shrink();
        },
      ),
    );
  }

  void _showContactDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Savol yoki muammo'),
          content: Text(
              'Savolingiz bo\'lsa yoki tushunarsiz narsa bo\'lsa, dastur yaratuvchisiga murojaat qiling.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Bekor'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launchContactLink();
              },
              child: Text('Aloqa'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchContactLink() async {
    const urlString = 'https://t.me/uzaidev';
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }
}

class _ProductCard extends StatelessWidget {
  final String imageUrl;
  final String name;
  final double quantity;
  final String quantityText;
  final String? type;
  final Color buttonColor;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ProductCard({
    required this.imageUrl,
    required this.name,
    required this.quantity,
    required this.quantityText,
    this.type,
    required this.buttonColor,
    required this.onTap,
    required this.onLongPress,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = quantity > 0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
      width: 180,
      margin: EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            child: AppNetworkImage(
              imageUrl: imageUrl,
              width: 180,
              height: 160,
              fit: BoxFit.cover,
              placeholder: (context) => Container(
                height: 160,
                color: Colors.grey.shade200,
                child: Center(
                    child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: buttonColor,
                )),
              ),
              errorWidget: (context) => Container(
                height: 160,
                color: Colors.grey.shade200,
                child: Icon(Icons.image_not_supported,
                    color: Colors.grey, size: 40),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Text(
              type != null && type!.isNotEmpty ? '$name ($type)' : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: isSelected
                  ? Container(
                      decoration: BoxDecoration(
                        color: buttonColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onRemove,
                                  child: Container(
                                    alignment: Alignment.centerLeft,
                                    padding: EdgeInsets.only(left: 14),
                                    child: Icon(Icons.remove,
                                        color: Colors.white, size: 22),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onAdd,
                                  child: Container(
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 14),
                                    child: Icon(Icons.add,
                                        color: Colors.white, size: 22),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          IgnorePointer(
                            child: Center(
                              child: Text(
                                type != null ? '$quantityText $type' : quantityText,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton(
                      onPressed: onAdd,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                      child: Text(
                        'Qo\'shish',
                        style: TextStyle(
                          fontSize: 15,
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
  }
}

