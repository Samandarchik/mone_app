// core2/ui/widgets/core_entry_menu.dart — oddiy foydalanuvchi (seller/ombor/
// bozorchi/shef) bosh ekranidagi «Ombor 2.0» kirish menyusi (CoreEntryMenu):
// AppBar action — PopupMenu: Hujjatlar, Qoldiq, Bozor приход, Ombor 2.0 (hub).
// Bandlar CoreSession.perms bo'yicha; yadro tokeni umuman yo'q bo'lsa
// (v2 login urinilmagan) tugma ko'rinmaydi; ulanish xato bo'lsa hub ochiladi
// (u yerda «qayta urinish»). Mavjud ekranlar o'zgarmaydi — faqat bitta ikonka.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/core_hub_ui.dart';
import 'package:uz_ai_dev/core2/ui/doc_form_ui.dart';
import 'package:uz_ai_dev/core2/ui/docs_list_ui.dart';
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';

class CoreEntryMenu extends StatelessWidget {
  const CoreEntryMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    if (session.state == CoreConnState.idle) return const SizedBox.shrink();
    final connected = session.connected;
    return PopupMenuButton<String>(
      tooltip: 'Ombor 2.0',
      icon: Badge(
        isLabelVisible: !connected,
        backgroundColor: Colors.red,
        smallSize: 8,
        child: const Icon(Icons.warehouse_outlined),
      ),
      itemBuilder: (_) => [
        if (connected && (session.canAnyDoc || session.has(CorePerms.stockView)))
          const PopupMenuItem(
            value: 'docs',
            child: ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('Hujjatlar'),
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
        if (connected && session.canCreate(CoreDocType.receipt))
          const PopupMenuItem(
            value: 'market',
            child: ListTile(
              leading: Icon(Icons.shopping_basket_outlined),
              title: Text('Bozor приход'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'hub',
          child: ListTile(
            leading: Icon(connected ? Icons.grid_view : Icons.cloud_off,
                color: connected ? null : Colors.red),
            title: Text(connected ? 'Ombor 2.0' : 'Ombor 2.0 — ulanmagan'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (v) {
        switch (v) {
          case 'docs':
            context.push(const DocsListUi());
            break;
          case 'stock':
            context.push(const StockUi());
            break;
          case 'market':
            context.push(const DocFormUi.marketReceipt());
            break;
          default:
            context.push(const CoreHubUi());
        }
      },
    );
  }
}
