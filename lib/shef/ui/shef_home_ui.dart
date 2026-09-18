// shef/ui/shef_home_ui.dart — shef bosh ekrani: ShefHomeUi — menyu kartalari.
// 2026-09-06 dan menyuda FAQAT ikki bo'lim: «Полуфабрикат» (qoldiq) va
// «Тех карта». Buyurtmalar / yangi buyurtma / ishlab chiqarish rejasi kartalari
// olib tashlandi (ShefOrdersPage klassi shu faylda qoldi — boshqa joydan
// ochilishi mumkin). productionStatusChip shu yerdan eksport qilinadi (boshqa
// rollar ham ishlatadi).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_entry_menu.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/pf_hub_page.dart';
import 'package:uz_ai_dev/shef/ui/pf_stock_page.dart';
// ShefOrdersPage ichidagi «Yangi buyurtma» tugmasi uchun kerak (bosh menyudan
// olib tashlangan bo'lsa ham).
import 'package:uz_ai_dev/shef/ui/shef_create_order_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_order_detail_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_tech_card_page.dart';

const Color _bgColor = Color(0xFFFAF6F1);
const Color _accentColor = Color(0xFFC5A97B);

// Shef roli uchun bosh ekran: bo'limlar menyusi. Buyurtmalar ro'yxati bu yerda
// chizilmaydi — «Buyurtmalar» kartasi orqali ShefOrdersPage ochiladi.
class ShefHomeUi extends StatelessWidget {
  const ShefHomeUi({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        title: const Text(
          'Shef — Ishlab chiqarish',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Ombor 2.0 (mone_core): retseptlar/hujjatlar — perms bo'yicha.
          const CoreEntryMenu(),
          IconButton(
            onPressed: () => logoutAndClear(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.05,
        children: [
          // Полуфабрикат — avval guruhlar (Biskvit: shakllar / nachinka /
          // krem / bezaklar), ichida esa qoldiq: bor / band / mumkin.
          _MenuCard(
            icon: Icons.inventory_2_outlined,
            title: 'Полуфабрикат',
            subtitle: 'Biskvit va boshqa пф qoldig\'i',
            onTap: () => _open(context, const PfHubPage()),
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
        ],
      ),
    );
  }
}

// Bosh menyudagi bitta bo'lim kartasi.
class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _accentColor, size: 26),
              ),
              const Spacer(),
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
