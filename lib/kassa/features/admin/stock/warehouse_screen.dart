import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'stock_screen.dart';
import 'ingredients_screen.dart';

/// Ombor — ikki bo'lim: tayyor mahsulotlar va ingredientlar
class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primary,
              labelStyle:
                  TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [
                Tab(
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                  text: 'Mahsulotlar',
                  height: 56,
                ),
                Tab(
                  icon: Icon(Icons.egg_alt_outlined, size: 18),
                  text: 'Ingredientlar',
                  height: 56,
                ),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                StockScreen(),
                IngredientsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
