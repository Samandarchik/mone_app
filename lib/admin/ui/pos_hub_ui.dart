// admin/ui/pos_hub_ui.dart — Konak POS markazi ekrani (faqat admin):
// PosHubUi — 5 ta POS ekraniga (buyurtmalar, sotuvlar, solishtirish, filial
// limitlari, menyu) yo'naltiruvchi grid hub, o'z mantig'i yo'q.
import 'package:uz_ai_dev/admin/ui/departments_ui.dart';
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/filial_limits_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_menu_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_mone_stations_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_orders_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_recons_ui.dart';
import 'package:uz_ai_dev/admin/ui/pos_sales_ui.dart';
import 'package:uz_ai_dev/core/context_extension.dart';

// POS (Konak) markazi — admin bosh menyusini soddalash uchun POS'ga oid
// 5 ta ekran bitta hub'ga yig'ilgan: buyurtmalar, sotuvlar, solishtirish,
// filial limitlari, POS menyu. Har karta mavjud ekranga o'tkazadi, yangi
// mantiq yo'q.

const Color _kBgColor = Color(0xFFFAF6F1);
const Color _kAccent = Color(0xFFC5A97B);

class PosHubUi extends StatelessWidget {
  const PosHubUi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        elevation: 0,
        title: const Text(
          'POS',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.95,
        children: [
          _hubCard(
            context,
            icon: Icons.settings_input_component,
            title: 'POS kassalar',
            subtitle: 'Filial, sklad va bar/oshxona bo\'limlari',
            page: const PosMoneStationsUi(),
          ),
          _hubCard(
            context,
            icon: Icons.account_tree_outlined,
            title: 'Bo‘limlar',
            subtitle: 'Bar, oshxona, vitrina: ombor va kategoriyalar',
            page: const DepartmentsUi(),
          ),
          _hubCard(
            context,
            icon: Icons.restaurant_menu,
            title: 'Kassa menyusi',
            subtitle: 'Filial kassasida nima sotiladi',
            page: const PosMenuUi(kassa: true),
          ),
          _hubCard(
            context,
            icon: Icons.point_of_sale,
            title: 'POS buyurtmalari',
            subtitle: 'Bazadan yuborish va qabul holati',
            page: const PosOrdersUi(),
          ),
          _hubCard(
            context,
            icon: Icons.storefront,
            title: 'POS sotuvlari',
            subtitle: 'Smena sotuv hisobotlari',
            page: const PosSalesUi(),
          ),
          _hubCard(
            context,
            icon: Icons.fact_check,
            title: 'POS solishtirish',
            subtitle: 'Kutilgan va fakt qoldiq farqlari',
            page: const PosReconsUi(),
          ),
          _hubCard(
            context,
            icon: Icons.rule,
            title: 'Filial limitlari',
            subtitle: 'Avto-buyurtma limitlari',
            page: const FilialLimitsUi(),
          ),
          _hubCard(
            context,
            icon: Icons.menu_book,
            title: 'POS menyu',
            subtitle: 'POS ko\'radigan katalog',
            page: const PosMenuUi(),
          ),
        ],
      ),
    );
  }

  // Bitta hub kartasi: ikonka + sarlavha + bir qatorlik izoh.
  Widget _hubCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(page),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF8A6F45), size: 24),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
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
