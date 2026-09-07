// core2/ui/core_hub_ui.dart — «Ombor 2.0» markazi (CoreHubUi): mone_core
// ekranlari grid'i — hujjatlar, bozor приход, qoldiq, lug'atlar (omborlar,
// tovarlar, kontragentlar), retseptlar, ruxsatlar, foydalanuvchilar, sotuv
// nuqtalari, API kalitlar, webhooklar, hisobotlar, sinxron holati. Kartalar
// `perms` bo'yicha ko'rinadi/yashirinadi. Tepada ulanish holati (server,
// foydalanuvchi, rol) va ⚙ server sozlamalari.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/ui/dict_corrs_ui.dart';
import 'package:uz_ai_dev/core2/ui/dict_goods_ui.dart';
import 'package:uz_ai_dev/core2/ui/dict_sklads_ui.dart';
import 'package:uz_ai_dev/core2/ui/doc_form_ui.dart';
import 'package:uz_ai_dev/core2/ui/docs_list_ui.dart';
import 'package:uz_ai_dev/core2/ui/integration_ui.dart';
import 'package:uz_ai_dev/core2/ui/perms_ui.dart';
import 'package:uz_ai_dev/core2/ui/recipes_ui.dart';
import 'package:uz_ai_dev/core2/ui/reports_ui.dart';
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';
import 'package:uz_ai_dev/core2/ui/sync_status_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class CoreHubUi extends StatelessWidget {
  const CoreHubUi({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    final cards = <_HubItem>[
      _HubItem(
        icon: Icons.description_outlined,
        title: 'Hujjatlar',
        subtitle: 'Приход, расход, ko\'chirish, inventar',
        page: const DocsListUi(),
        visible: session.canAnyDoc || session.has(CorePerms.stockView),
      ),
      _HubItem(
        icon: Icons.shopping_basket_outlined,
        title: 'Bozor приход',
        subtitle: 'Tez kirim: РЫНОК → ombor',
        page: const DocFormUi.marketReceipt(),
        visible: session.canCreate(CoreDocType.receipt),
      ),
      _HubItem(
        icon: Icons.inventory_2_outlined,
        title: 'Qoldiq',
        subtitle: 'Ombor bo\'yicha, kartochka, partiyalar',
        page: const StockUi(),
        visible: session.has(CorePerms.stockView),
      ),
      _HubItem(
        icon: Icons.warehouse_outlined,
        title: 'Omborlar',
        subtitle: 'Ro\'yxat, qo\'shish (1 forma)',
        page: const DictSkladsUi(),
        visible: true,
      ),
      _HubItem(
        icon: Icons.category_outlined,
        title: 'Tovarlar',
        subtitle: 'Qidiruv, qo\'shish, birliklar',
        page: const DictGoodsUi(),
        visible: true,
      ),
      _HubItem(
        icon: Icons.people_alt_outlined,
        title: 'Kontragentlar',
        subtitle: 'Ta\'minotchi, to\'lov, qarzdor',
        page: const DictCorrsUi(),
        visible: true,
      ),
      _HubItem(
        icon: Icons.menu_book_outlined,
        title: 'Retseptlar',
        subtitle: 'Versiyalar, brutto/netto',
        page: const RecipesUi(),
        visible: session.has(CorePerms.recipeEdit) || session.isSuper,
      ),
      _HubItem(
        icon: Icons.bar_chart,
        title: 'Hisobotlar',
        subtitle: 'Aylanma, qoldiq qiymati, defitsit',
        page: const ReportsUi(),
        visible: session.has(CorePerms.reportView),
      ),
      _HubItem(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Ruxsatlar',
        subtitle: 'Rollar × ruxsat kalitlari',
        page: const PermsUi(),
        visible: session.has(CorePerms.usersManage),
      ),
      _HubItem(
        icon: Icons.manage_accounts_outlined,
        title: 'Foydalanuvchilar',
        subtitle: 'Rol, omborlar, faol',
        page: const CoreUsersUi(),
        visible: session.has(CorePerms.usersManage),
      ),
      _HubItem(
        icon: Icons.point_of_sale,
        title: 'Sotuv nuqtalari',
        subtitle: 'Konak/RK7 → ombor qoidalari',
        page: const SalePointsUi(),
        visible: session.has(CorePerms.integrationManage),
      ),
      _HubItem(
        icon: Icons.vpn_key_outlined,
        title: 'API kalitlar',
        subtitle: 'Tizim integratsiyasi',
        page: const ApiKeysUi(),
        visible: session.has(CorePerms.integrationManage),
      ),
      _HubItem(
        icon: Icons.webhook,
        title: 'Webhooklar',
        subtitle: 'doc.posted, stock.low',
        page: const WebhooksUi(),
        visible: session.has(CorePerms.integrationManage),
      ),
      _HubItem(
        icon: Icons.sync,
        title: 'Sinxron holati',
        subtitle: 'Rol, peer, navbat',
        page: const SyncStatusUi(),
        visible: session.isSuper ||
            session.has(CorePerms.usersManage) ||
            session.has(CorePerms.integrationManage),
      ),
    ].where((c) => c.visible).toList();

    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Ombor 2.0',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Server sozlamalari',
            onPressed: () async {
              final saved = await showServerSettingsDialog(context);
              if (saved && context.mounted) context.read<CoreSession>().retry();
            },
            icon: const Icon(Icons.dns_outlined),
          ),
          IconButton(
            tooltip: 'Qayta ulanish',
            onPressed: () => context.read<CoreSession>().retry(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBar(session: session),
          Expanded(
            child: session.connected
                ? GridView.count(
                    padding: const EdgeInsets.all(12),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    children: [for (final c in cards) _HubCard(item: c)],
                  )
                : const CoreConnectGate(needDicts: false, child: SizedBox()),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final CoreSession session;
  const _StatusBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final ok = session.connected;
    final color = ok ? Colors.green.shade700 : Colors.red.shade700;
    final user = session.user;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? '${user?.name ?? ''} · ${user?.role ?? ''}'
                      : 'Server ulanmagan',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: color),
                ),
                Text(AppUrls.coreUrl,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (ok)
            Text('${session.perms.length} ruxsat',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _HubItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
  final bool visible;
  const _HubItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
    required this.visible,
  });
}

class _HubCard extends StatelessWidget {
  final _HubItem item;
  const _HubCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(item.page),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kCoreAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(item.icon, color: kCoreAccentDark, size: 22),
              ),
              const Spacer(),
              Text(item.title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 2),
              Text(item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
