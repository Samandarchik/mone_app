// shef/ui/shef_home_ui.dart — shef bosh ekrani: ShefHomeUi — menyu kartalari.
// Menyuda to'rt bo'lim: «Biskvit» (rasmli), «Полуфабрикат» (qoldiq),
// «Готовый» va «Тех карта». Buyurtmalar / yangi buyurtma / ishlab chiqarish rejasi kartalari
// olib tashlandi (ShefOrdersPage klassi shu faylda qoldi — boshqa joydan
// ochilishi mumkin). productionStatusChip shu yerdan eksport qilinadi (boshqa
// rollar ham ishlatadi).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/admin/model/category_model.dart';
import 'package:uz_ai_dev/admin/provider/admin_categoriy_provider.dart';
import 'package:uz_ai_dev/admin/provider/admin_product_provider.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_entry_menu.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/biskvit_page.dart';
import 'package:uz_ai_dev/shef/ui/pf_stock_page.dart';
import 'package:uz_ai_dev/shef/ui/shef_constructor_page.dart';
// ShefOrdersPage ichidagi «Yangi buyurtma» tugmasi uchun kerak (bosh menyudan
// olib tashlangan bo'lsa ham).
import 'package:uz_ai_dev/shef/ui/shef_create_order_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_order_detail_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

// Shef roli uchun bosh ekran: bo'limlar menyusi. Buyurtmalar ro'yxati bu yerda
// chizilmaydi — «Buyurtmalar» kartasi orqali ShefOrdersPage ochiladi.
// AppBar'dagi «+» — Biskvit bo'limidagi kabi «Тех карта»dagi kategoriyani
// tanlab, shu menyuga karta qilib qo'shish (ShefHomeLinks, qurilmada
// saqlanadi); kartani bosib turish — menyudan olib tashlash.
class ShefHomeUi extends StatefulWidget {
  const ShefHomeUi({super.key});

  @override
  State<ShefHomeUi> createState() => _ShefHomeUiState();
}

class _ShefHomeUiState extends State<ShefHomeUi> {
  bool _linksLoaded = false;

  @override
  void initState() {
    super.initState();
    ShefHomeLinks.load().then((_) {
      if (mounted) setState(() => _linksLoaded = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CategoryProviderAdmin>().getCategories();
      // Kartalardagi «N ta» soni uchun (allaqachon yuklangan bo'lsa — jim).
      context.read<ProductProviderAdmin>().initializeProducts();
      // Qo'shilgan пф kategoriyalari nomi shu ro'yxatdan topiladi.
      final shef = context.read<ShefProvider>();
      if (shef.pfStock.isEmpty) shef.fetchPfStock();
    });
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openCategory(CategoryProductAdmin category) {
    _open(
      context,
      ShefTechCardProductsPage(
        categoryId: category.id,
        categoryName: category.name,
        canAddProducts: true,
        // «П/Ф Бисквит» — tepada 3D tort va tort konstruktori.
        showCakeConstructor: isBiskvitCategory(category.name),
        // «П/Ф Начинка» — kesilgan tort, kesimda nachinka (тех картадан).
        showFillingCake: isNachinkaCategory(category.name),
      ),
    );
  }

  // «+» — Biskvit bo'limidagi oynaning o'zi; Biskvit'ga yoki bu menyuga
  // allaqachon qo'shilganlar ro'yxatda chiqmaydi.
  Future<void> _addCategory() async {
    await Future.wait([ShefHomeLinks.load(), BiskvitLinks.load()]);
    if (!mounted) return;
    final picked = await pickTechCardCategory(
      context,
      exclude: {...ShefHomeLinks.linkedIds, ...BiskvitLinks.linkedIds},
      hint: '«Тех карта»dagi kategoriya hamma mahsulotlari bilan '
          'bosh menyuga o\'tadi',
    );
    if (picked == null || !mounted) return;
    await ShefHomeLinks.add(picked.id);
    if (!mounted) return;
    setState(() {});
  }

  // Kartani bosib turish — menyudan olib tashlash (tasdiq bilan).
  Future<void> _removeCategory(CategoryProductAdmin category) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Menyudan olib tashlash'),
        content: Text(
          '«${category.name}» bosh menyudan olinib, yana «Тех карта»da '
          'ko\'rinadi. Kategoriya va mahsulotlar o\'chmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Olib tashlash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ShefHomeLinks.remove(category.id);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      // O'ng pastki burchak: KONSTRUKTOR — biskvit + ichki nachinka + tashqi
      // qoplamani haqiqiy mahsulotlardan yig'ib, 3D'da ko'rish
      // (shef_constructor_page.dart).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, const ShefConstructorPage()),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.layers_outlined),
        label: const Text('Konstruktor'),
      ),
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Shef — Ishlab chiqarish',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _addCategory,
            tooltip: 'Kategoriya qo\'shish',
            icon: const Icon(Icons.add_circle_outline),
            color: Colors.brown.shade700,
            iconSize: 28,
          ),
          // Ombor 2.0 (mone_core): retseptlar/hujjatlar — perms bo'yicha.
          const CoreEntryMenu(),
          IconButton(
            onPressed: () => logoutAndClear(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      // Qo'shilgan kategoriyalar soni kichik — ikkala provider'ni kuzatish
      // arzon.
      body: Consumer2<CategoryProviderAdmin, ProductProviderAdmin>(
        builder: (context, cats, products, _) {
          // Пф kategoriyalari «Тех карта» ro'yxatida bo'lmasligi mumkin.
          final pf = context.select<ShefProvider, List<PfStockRow>>(
            (p) => p.pfStock,
          );
          final byId = shefCategoriesById(cats.categories, pf);
          final counts = <int, int>{};
          for (final p in products.products) {
            counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
          }
          // Backend'da o'chirilgan (ro'yxatda yo'q) id'lar ko'rsatilmaydi.
          final linked = [
            if (_linksLoaded)
              for (final id in ShefHomeLinks.ids)
                if (byId[id] != null) byId[id]!,
          ];
          return _buildGrid(context, linked, counts);
        },
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<CategoryProductAdmin> linked,
    Map<int, int> counts,
  ) {
    return GridView.count(
      // Pastki joy — «Konstruktor» tugmasi oxirgi qatorni yopmasin.
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        // Biskvit — rasmli karta; ichida shakllar / nachinka / krem /
        // bezaklar bo'limlari (biskvit_page.dart → BiskvitPage).
        _MenuCard(
          icon: Icons.cake_outlined,
          image: 'assets/biskvit.png',
          title: 'Biskvit',
          subtitle: 'Biskvit · Nachinka · Krem · Bezaklar',
          onTap: () => _open(context, const BiskvitPage()),
        ),
        // Полуфабрикат qoldig'i — qaysi pf bor, nechtasi band/mumkin.
        _MenuCard(
          icon: Icons.inventory_2_outlined,
          title: 'Полуфабрикат',
          subtitle: 'Qoldiq: bor / band / mumkin',
          onTap: () => _open(context, const PfStockPage()),
        ),
        // Готовый — «Полуфабрикат» bilan AYNAN bir xil ekran, faqat пф
        // BO'LMAGAN (tayyor) mahsulotlar ro'yxati (GET pf-stock?kind=ready).
        _MenuCard(
          icon: Icons.cake_outlined,
          title: 'Готовый',
          subtitle: 'Tayyor mahsulot qoldig\'i',
          onTap: () => _open(context, const PfStockPage(ready: true)),
        ),
        // Тех карта — shefga belgilangan kategoriyalar retsepti
        // (narxlarsiz: faqat tarkib tahrirlanadi).
        _MenuCard(
          icon: Icons.menu_book_outlined,
          title: 'Тех карта',
          subtitle: 'Retsept tarkibini tahrirlash',
          onTap: () => _open(context, const ShefTechCardCategoriesPage()),
        ),
        // «+» bilan qo'shilgan kategoriyalar — rasmi, nomi va soni bilan.
        for (final c in linked) ...[
          _MenuCard(
            icon: Icons.category_outlined,
            thumb: LayoutBuilder(
              builder: (context, box) => CategoryThumb(
                category: c,
                size: box.maxHeight,
                width: box.maxWidth,
              ),
            ),
            title: c.name,
            subtitle: '${counts[c.id] ?? 0} ta mahsulot',
            onTap: () => _openCategory(c),
            onLongPress: () => _removeCategory(c),
          ),
          // «Покрытие» — «Начинка» kategoriyasining O'SHA mahsulotlari, lekin
          // tortni tashqaridan qoplagan krem sifatida. Alohida kategoriya
          // emas: nachinka kartasi yonida o'zi chiqadi (u olib tashlansa —
          // bu ham yo'qoladi).
          if (isNachinkaCategory(c.name))
            _MenuCard(
              icon: Icons.cake_outlined,
              thumb: const ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                child: CoatingSectionThumb(),
              ),
              title: 'Покрытие',
              subtitle: '${counts[c.id] ?? 0} ta mahsulot',
              onTap: () => _open(
                context,
                ShefTechCardProductsPage(
                  categoryId: c.id,
                  categoryName: 'Покрытие',
                  showCoating: true,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// Bosh menyudagi bitta bo'lim kartasi.
class _MenuCard extends StatelessWidget {
  final IconData icon;
  // Berilsa ikonka o'rnida shu asset rasmi (kattaroq) ko'rsatiladi.
  final String? image;
  // Berilsa rasm o'rnida shu vidjet (masalan kategoriyaning tarmoq rasmi).
  final Widget? thumb;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MenuCard({
    required this.icon,
    this.image,
    this.thumb,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasPicture = image != null || thumb != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumb != null)
                Expanded(flex: 3, child: thumb!)
              else if (image != null)
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Image.asset(
                      image!,
                      cacheWidth: 360,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon, color: _accentColor, size: 40),
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _accentColor, size: 26),
                ),
                const Spacer(),
              ],
              if (hasPicture) const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Shef buyurtmalari ro'yxati (ilgari bosh ekranda edi).
// Har karta: order_id, sana, mahsulotlar qisqacha, status chip va umumiy
// progress (jami oxirgi-bo'lim done / jami qty).
class ShefOrdersPage extends StatefulWidget {
  const ShefOrdersPage({super.key});

  @override
  State<ShefOrdersPage> createState() => _ShefOrdersPageState();
}

class _ShefOrdersPageState extends State<ShefOrdersPage> {
  // dispose() ichida context.read() xavfsiz emas — referensni saqlaymiz.
  ShefProvider? _shefProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ShefProvider>();
      provider.fetchOrders();
      // Real-time: ombor «Berdim» bosganda ro'yxat refresh'siz yangilanadi.
      provider.connectSocket();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shefProvider = context.read<ShefProvider>();
  }

  @override
  void dispose() {
    _shefProvider?.disconnectSocket();
    super.dispose();
  }

  Future<void> _openCreateOrder() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ShefCreateOrderUi()),
    );
    if (created == true && mounted) {
      context.read<ShefProvider>().fetchOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Buyurtmalar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<ShefProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.orders.isEmpty) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (provider.errorMessage != null && provider.orders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => provider.fetchOrders(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Qayta urinish'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.fetchOrders(),
            child: provider.orders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 160),
                      Center(
                        child: Text(
                          'Hozircha buyurtma yo\'q.\n«+ Buyurtma» bilan yangi '
                          'ishlab chiqarish buyurtmasi bering.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    itemCount: provider.orders.length,
                    itemBuilder: (context, index) =>
                        _OrderCard(order: provider.orders[index]),
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateOrder,
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Buyurtma'),
      ),
    );
  }
}

// Ro'yxatdagi bitta buyurtma kartasi.
class _OrderCard extends StatelessWidget {
  final ProductionOrder order;

  const _OrderCard({required this.order});

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final percent = (order.progress * 100).round();
    final itemsSummary =
        order.items.map((i) => '${i.name} — ${i.qty} dona').join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShefOrderDetailUi(orderId: order.id),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderId.isEmpty ? '№${order.id}' : order.orderId,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  productionStatusChip(order.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(order.created),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                itemsSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: order.progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          order.status == ProductionStatus.tayyor
                              ? Colors.green
                              : _accentColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$percent%  (${order.totalDone}/${order.totalQty})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Buyurtma statusi uchun rangli chip (home + tafsilot ekranlarida ishlatiladi).
Widget productionStatusChip(String status) {
  final String label;
  final Color color;
  switch (status) {
    case ProductionStatus.jarayonda:
      label = 'Jarayonda';
      color = Colors.orange.shade700;
      break;
    case ProductionStatus.tayyor:
      label = 'Tayyor';
      color = Colors.green.shade700;
      break;
    default:
      label = 'Yangi';
      color = Colors.blue.shade700;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}
