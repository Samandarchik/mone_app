// shef/ui/shef_home_ui.dart — shef bosh ekrani: ShefHomeUi — mening ishlab
// chiqarish buyurtmalarim ro'yxati (status chip, progress); ShefProvider ustida,
// productionStatusChip shu yerda eksport qilinadi.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_entry_menu.dart';
import 'package:uz_ai_dev/shef/model/production_model.dart';
import 'package:uz_ai_dev/production/ui/production_plan_page.dart';
import 'package:uz_ai_dev/shef/provider/shef_provider.dart';
import 'package:uz_ai_dev/shef/ui/shef_create_order_ui.dart';
import 'package:uz_ai_dev/shef/ui/shef_order_detail_ui.dart';

// Shef roli uchun bosh ekran: mening ishlab chiqarish buyurtmalarim.
// Har karta: order_id, sana, mahsulotlar qisqacha, status chip va umumiy
// progress (jami oxirgi-bo'lim done / jami qty).
class ShefHomeUi extends StatefulWidget {
  const ShefHomeUi({super.key});

  @override
  State<ShefHomeUi> createState() => _ShefHomeUiState();
}

class _ShefHomeUiState extends State<ShefHomeUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

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

  void _logout() {
    logoutAndClear(context);
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
          'Shef — Ishlab chiqarish',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Ombor 2.0 (mone_core): retseptlar/hujjatlar — perms bo'yicha.
          const CoreEntryMenu(),
          // Kunlik ishlab chiqarish rejasi (MRP) — nima pishirish kerak.
          IconButton(
            tooltip: 'Ishlab chiqarish rejasi',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductionPlanPage()),
            ),
            icon: const Icon(Icons.event_note),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
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

  static const Color _accentColor = Color(0xFFC5A97B);

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
