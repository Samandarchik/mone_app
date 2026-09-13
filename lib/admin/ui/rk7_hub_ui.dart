// admin/ui/rk7_hub_ui.dart — RK7 integratsiyasi markazi (Rk7HubUi, faqat
// admin): 3 tab — «Import» (smenalar), «Mapping» (taom → mahsulot),
// «Nuqtalar» (sotuv nuqtasi → filial/sklad). O'z mantig'i yo'q, tablarni yig'adi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/rk7_mapping_ui.dart';
import 'package:uz_ai_dev/admin/ui/rk7_sale_places_ui.dart';
import 'package:uz_ai_dev/admin/ui/rk7_shifts_ui.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/bugalter/ui/sh5_kirim_ui.dart';
import 'package:uz_ai_dev/core/context_extension.dart';

// RK7 markazi — RK7 POS'dan tushgan yopilgan smenalar va ularning skladdan
// yechilishi shu bo'limdan boshqariladi (PLAN_RK7 §6).
class Rk7HubUi extends StatelessWidget {
  const Rk7HubUi({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kRk7Bg,
        appBar: AppBar(
          backgroundColor: kRk7Bg,
          elevation: 0,
          title: const Text(
            'RK7',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            // SH5 kirim — bozor buyurtmasi → SH5 «Приходная накладная»
            // (asosiy foydalanuvchi bugalter, admin ham ko'ra oladi).
            IconButton(
              tooltip: 'SH5 kirim',
              icon: const Icon(Icons.move_to_inbox_outlined),
              onPressed: () => context.push(const Sh5KirimUi()),
            ),
          ],
          bottom: const TabBar(
            labelColor: kRk7AccentDark,
            unselectedLabelColor: Colors.black54,
            indicatorColor: kRk7Accent,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Import'),
              Tab(text: 'Mapping'),
              Tab(text: 'Nuqtalar'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            Rk7ShiftsTab(),
            Rk7MappingTab(),
            Rk7SalePlacesTab(),
          ],
        ),
      ),
    );
  }
}
