// core2/ui/widgets/core_entry_menu.dart — oddiy foydalanuvchi (seller/ombor/
// bozorchi/shef) bosh ekranidagi «Ombor 2.0» kirish tugmasi (CoreEntryMenu).
//
// PLAN_UI_OSON §2.1: tugma endi «Bugun» ekraniga (CoreHomeUi) olib kiradi —
// oddiy xodim uchun bitta kirish nuqtasi. Admin/bugalter (dict.edit,
// users.manage, report.view, integration.manage) uchun qo'shimcha menyu
// bandlari: «Qoldiq» va «Boshqaruv» (eski CoreHubUi — hamma eski ekranlar).
// Yadro tokeni umuman yo'q bo'lsa tugma ko'rinmaydi; ulanish xato bo'lsa
// «Bugun» ekranidagi darvoza «qayta urinish» beradi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/core_home_ui.dart';
import 'package:uz_ai_dev/core2/ui/core_hub_ui.dart';
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';

class CoreEntryMenu extends StatelessWidget {
  const CoreEntryMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    if (session.state == CoreConnState.idle) return const SizedBox.shrink();
    final connected = session.connected;
    // «Boshqaruv» — faqat sozlash/hisobot ruxsati borlarga.
    final manager = session.has(CorePerms.dictEdit) ||
        session.has(CorePerms.usersManage) ||
        session.has(CorePerms.reportView) ||
        session.has(CorePerms.integrationManage);

    final icon = Badge(
      isLabelVisible: !connected,
      backgroundColor: Colors.red,
      smallSize: 8,
      child: const Icon(Icons.warehouse_outlined),
    );

    if (!manager) {
      return IconButton(
        tooltip: connected ? 'Ombor 2.0 — Bugun' : 'Ombor 2.0 — ulanmagan',
        onPressed: () => context.push(const CoreHomeUi()),
        icon: icon,
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Ombor 2.0',
      icon: icon,
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'home',
          child: ListTile(
            leading: Icon(Icons.today_outlined),
            title: Text('Bugun'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (connected && session.has(CorePerms.stockView))
          const PopupMenuItem(
            value: 'stock',
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined),
              title: Text('Qoldiq'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'hub',
          child: ListTile(
            leading: Icon(connected ? Icons.grid_view : Icons.cloud_off,
                color: connected ? null : Colors.red),
            title: Text(connected ? 'Boshqaruv' : 'Boshqaruv — ulanmagan'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (v) {
        switch (v) {
          case 'stock':
            context.push(const StockUi());
            break;
          case 'hub':
            context.push(const CoreHubUi());
            break;
          default:
            context.push(const CoreHomeUi());
        }
      },
    );
  }
}
