import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'analytics/analytics_screen.dart';
import 'bozor/bozor_screen.dart';
import 'customers/customers_screen.dart';
import 'customers/reviews_screen.dart';
import 'customers/tg_customers_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'expenses/expenses_screen.dart';
import 'finance/finance_screen.dart';
import 'menu_management/products_screen.dart';
import 'music/music_screen.dart';
import 'operations/operations_screen.dart';
import 'orders/admin_orders_screen.dart';
import 'printers/printers_screen.dart';
import 'settings/cloud_settings_screen.dart';
import 'settings/mone_screen.dart';
import 'stock/ingredients_screen.dart';
import 'supply/supply_screen.dart';
import 'users/users_screen.dart';
import 'yandex/yandex_screen.dart';
import 'zones/zones_screen.dart';
import 'cooking/admin_cooking_page.dart';
import 'tutorials/admin_tutorials_page.dart';

/// Admin panelidagi BITTA bo'lim.
///
/// Ilgari bu ro'yxat to'g'ridan-to'g'ri shell ichida turardi va har bir
/// layout (drawer / rail) uni o'zicha chizardi. Endi bo'lim ta'rifi bitta
/// joyda: yon panel, pastki menyu va qidiruv (Ctrl+K) — uchalasi ham shu
/// ro'yxatdan oziqlanadi, ya'ni bo'lim qo'shish = shu yerga bitta qator.
class AdminDestination {
  /// Barqaror kalit — tanlangan bo'lim SHU orqali eslab qolinadi.
  /// (Ilgari indeks saqlanardi: ruxsatlar o'zgarsa boshqa ekran ochilardi.)
  final String id;
  final String label;

  /// Qidiruvda va bo'limlar ro'yxatida ko'rinadigan izoh — foydalanuvchi
  /// «qaysi bo'limda nima bor» ni ochmasdan bilishi uchun.
  final String hint;
  final IconData icon;
  final IconData activeIcon;
  final String group;
  final String resource;
  final Color accent;

  /// Telefonda pastki panelga tushish navbati (kichik son — oldinroq).
  /// `null` — faqat «Yana» ro'yxatida ko'rinadi.
  final int? primaryOrder;

  /// Qidiruv uchun qo'shimcha so'zlar (ruscha/sinonim).
  final List<String> keywords;

  /// Texnik bo'lim — odatda yon panelda ham, qidiruvda ham KO'RINMAYDI.
  /// Ular «Local server» belgisini 5 soniya bosib turib ochiladi
  /// (kassir tasodifan sync/server sozlamalariga kirib qolmasin).
  final bool hidden;

  final Widget Function() build;

  const AdminDestination({
    required this.id,
    required this.label,
    required this.hint,
    required this.icon,
    required this.activeIcon,
    required this.group,
    required this.resource,
    required this.accent,
    required this.build,
    this.primaryOrder,
    this.keywords = const [],
    this.hidden = false,
  });

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (label.toLowerCase().contains(q)) return true;
    if (hint.toLowerCase().contains(q)) return true;
    if (group.toLowerCase().contains(q)) return true;
    for (final k in keywords) {
      if (k.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// Bo'limlar guruhi — yon panelda sarlavha bo'lib turadi.
class AdminGroups {
  static const main = 'Asosiy';
  static const money = 'Moliya';
  static const stock = 'Ombor';
  static const people = 'Odamlar';
  static const settings = 'Sozlamalar';

  /// Yon paneldagi tartib.
  static const order = [main, money, stock, people, settings];
}

/// Barcha bo'limlar (ruxsatga qarab filtrlanadi).
const List<AdminDestination> kAdminDestinations = [
  // ===== Asosiy =====
  AdminDestination(
    id: 'dashboard',
    label: 'Bosh sahifa',
    hint: 'Smena, bugungi tushum, faol cheklar',
    icon: Icons.space_dashboard_outlined,
    activeIcon: Icons.space_dashboard_rounded,
    group: AdminGroups.main,
    resource: 'finance',
    accent: AppColors.primary,
    primaryOrder: 0,
    keywords: ['home', 'главная', 'dashboard', 'smena'],
    build: DashboardScreen.new,
  ),
  AdminDestination(
    id: 'orders',
    label: 'Buyurtmalar',
    hint: 'Kunlik cheklar, to‘lovlar, qaytarish',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
    group: AdminGroups.main,
    resource: 'orders',
    accent: AppColors.info,
    primaryOrder: 1,
    keywords: ['chek', 'заказы', 'order', 'tarix'],
    build: AdminOrdersScreen.new,
  ),
  AdminDestination(
    id: 'products',
    label: 'Menyu',
    hint: 'Mahsulotlar, kategoriyalar, narxlar, retsept',
    icon: Icons.restaurant_menu_outlined,
    activeIcon: Icons.restaurant_menu_rounded,
    group: AdminGroups.main,
    resource: 'products',
    accent: AppColors.warning,
    primaryOrder: 2,
    keywords: ['mahsulot', 'меню', 'narx', 'retsept', 'kategoriya'],
    build: ProductsScreen.new,
  ),
  AdminDestination(
    id: 'cooking',
    label: 'Pishirish',
    hint: 'Yarim tayyor mahsulot tayyorlash',
    icon: Icons.bakery_dining_outlined,
    activeIcon: Icons.bakery_dining_rounded,
    group: AdminGroups.main,
    resource: 'cooking',
    accent: Color(0xFFF97316),
    keywords: ['oshxona', 'готовка', 'tayyorlash'],
    build: AdminCookingPage.new,
  ),
  AdminDestination(
    id: 'yandex',
    label: 'Yandex Eda',
    hint: 'Stop-list: qaysi taom sotuvda, qaysi biri stopda',
    icon: Icons.delivery_dining_outlined,
    activeIcon: Icons.delivery_dining_rounded,
    group: AdminGroups.main,
    resource: 'products',
    accent: Color(0xFFFC3F1D),
    keywords: ['yandex', 'яндекс', 'stop', 'стоп', 'eda', 'еда', 'dostavka'],
    build: YandexScreen.new,
  ),

  // ===== Moliya =====
  AdminDestination(
    id: 'finance',
    label: 'Moliya',
    hint: 'Kunlik/oylik tushum, foyda, to‘lov usullari',
    icon: Icons.account_balance_wallet_outlined,
    activeIcon: Icons.account_balance_wallet_rounded,
    group: AdminGroups.money,
    resource: 'finance',
    accent: AppColors.success,
    primaryOrder: 3,
    keywords: ['pul', 'финансы', 'tushum', 'foyda', 'kassa'],
    build: FinanceScreen.new,
  ),
  AdminDestination(
    id: 'analytics',
    label: 'Analitika',
    hint: 'Sotuv statistikasi, top mahsulotlar, soatlar',
    icon: Icons.insights_outlined,
    activeIcon: Icons.insights_rounded,
    group: AdminGroups.money,
    resource: 'analytics',
    accent: Color(0xFF14B8A6),
    keywords: ['statistika', 'аналитика', 'hisobot', 'grafik'],
    build: AnalyticsScreen.new,
  ),
  AdminDestination(
    id: 'expenses',
    label: 'Xarajatlar',
    hint: 'Chiqimlar va ularning kategoriyalari',
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments_rounded,
    group: AdminGroups.money,
    resource: 'expenses',
    accent: AppColors.danger,
    keywords: ['chiqim', 'расходы', 'xarajat'],
    build: ExpensesScreen.new,
  ),

  // ===== Ombor =====
  AdminDestination(
    id: 'ingredients',
    label: 'Ombor',
    hint: 'Ingredient qoldig‘i, o‘lchov birligi, minimal zaxira',
    icon: Icons.inventory_2_outlined,
    activeIcon: Icons.inventory_2_rounded,
    group: AdminGroups.stock,
    resource: 'ingredients',
    accent: Color(0xFF06B6D4),
    primaryOrder: 4,
    keywords: ['zaxira', 'склад', 'ingredient', 'qoldiq'],
    build: IngredientsScreen.new,
  ),
  AdminDestination(
    id: 'supply',
    label: 'Kirim partiyalari',
    hint: 'Omborga kirim, tannarx, muddat',
    icon: Icons.local_shipping_outlined,
    activeIcon: Icons.local_shipping_rounded,
    group: AdminGroups.stock,
    resource: 'ingredient_batches',
    accent: Color(0xFF0F766E),
    keywords: ['kirim', 'приход', 'partiya', 'yetkazib'],
    build: SupplyScreen.new,
  ),
  AdminDestination(
    id: 'bozor',
    label: 'Bozor ro‘yxati',
    hint: 'Tugayotgan mahsulotlar — xarid ro‘yxati',
    icon: Icons.shopping_cart_outlined,
    activeIcon: Icons.shopping_cart_rounded,
    group: AdminGroups.stock,
    resource: 'bozor',
    accent: AppColors.success,
    keywords: ['xarid', 'закупка', 'ro‘yxat', 'bozor'],
    build: BozorScreen.new,
  ),

  // ===== Odamlar =====
  AdminDestination(
    id: 'users',
    label: 'Xodimlar',
    hint: 'Kassir, ofitsiant, oshpaz — PIN va ruxsatlar',
    icon: Icons.badge_outlined,
    activeIcon: Icons.badge_rounded,
    group: AdminGroups.people,
    resource: 'users',
    accent: Color(0xFF8B5CF6),
    keywords: ['xodim', 'сотрудники', 'kassir', 'ofitsiant', 'pin'],
    build: UsersScreen.new,
  ),
  AdminDestination(
    id: 'customers',
    label: 'Mijozlar',
    hint: 'Mehmonlar bazasi, keshbek, buyurtma tarixi',
    icon: Icons.loyalty_outlined,
    activeIcon: Icons.loyalty_rounded,
    group: AdminGroups.people,
    resource: 'customers',
    accent: Color(0xFFDB2777),
    keywords: ['mijoz', 'клиенты', 'keshbek', 'bonus'],
    build: CustomersScreen.new,
  ),
  AdminDestination(
    id: 'reviews',
    label: 'Izohlar',
    hint: 'Mijoz baholari, shikoyatlar va ularga javob',
    icon: Icons.reviews_outlined,
    activeIcon: Icons.reviews_rounded,
    group: AdminGroups.people,
    resource: 'customers',
    accent: Color(0xFFF59E0B),
    keywords: ['izoh', 'отзывы', 'baho', 'reyting', 'review', 'shikoyat'],
    build: ReviewsScreen.new,
  ),
  AdminDestination(
    id: 'tg_customers',
    label: 'Telegram bazasi',
    hint: 'Botga /start bosganlar va ommaviy xabar',
    icon: Icons.telegram_outlined,
    activeIcon: Icons.telegram_rounded,
    group: AdminGroups.people,
    resource: 'customers',
    accent: Color(0xFF229ED9),
    keywords: ['telegram', 'bot', 'рассылка', 'xabar', 'broadcast', 'start'],
    build: TgCustomersScreen.new,
  ),
  AdminDestination(
    id: 'zones',
    label: 'Zona va stollar',
    hint: 'Zal, tashqari, stol raqamlari va QR',
    icon: Icons.table_restaurant_outlined,
    activeIcon: Icons.table_restaurant_rounded,
    group: AdminGroups.people,
    resource: 'zones',
    accent: AppColors.primary,
    keywords: ['stol', 'зона', 'zal', 'qr'],
    build: ZonesScreen.new,
  ),

  // ===== Sozlamalar =====
  AdminDestination(
    id: 'printers',
    label: 'Printerlar',
    hint: 'Chek va oshxona printerlari, kategoriya biriktirish',
    icon: Icons.print_outlined,
    activeIcon: Icons.print_rounded,
    group: AdminGroups.settings,
    resource: 'printers',
    accent: Color(0xFF475569),
    keywords: ['printer', 'принтер', 'chek', 'oshxona'],
    build: PrintersScreen.new,
  ),
  AdminDestination(
    id: 'music',
    label: 'Musiqa',
    hint: 'Fon musiqasi, navbat va pleylistlar',
    icon: Icons.library_music_outlined,
    activeIcon: Icons.library_music_rounded,
    group: AdminGroups.settings,
    resource: 'music',
    accent: Color(0xFFEC4899),
    keywords: ['musiqa', 'музыка', 'youtube', 'pleylist'],
    build: MusicScreen.new,
  ),
  AdminDestination(
    id: 'tutorials',
    label: 'Video qo‘llanma',
    hint: 'Har bir bo‘lim qanday ishlashi — ovozli videolar',
    icon: Icons.play_circle_outline_rounded,
    activeIcon: Icons.play_circle_rounded,
    group: AdminGroups.settings,
    resource: kAnyResource,
    accent: AppColors.primary,
    keywords: ['video', 'qo‘llanma', 'qollanma', 'yordam', 'help', 'обучение'],
    build: AdminTutorialsPage.new,
  ),
  AdminDestination(
    id: 'operations',
    label: 'Tizim nazorati',
    hint: 'Amallar tarixi, sync holati, xatolar',
    icon: Icons.shield_outlined,
    activeIcon: Icons.shield_rounded,
    group: AdminGroups.settings,
    resource: 'audit',
    accent: Color(0xFF7C3AED),
    keywords: ['audit', 'надзор', 'log', 'sync', 'tarix'],
    hidden: true,
    build: OperationsScreen.new,
  ),
  AdminDestination(
    id: 'mone',
    label: 'Mone',
    hint: 'Mone bilan aloqa: katalog, yuborilgan cheklar, sinxron',
    icon: Icons.sync_alt_rounded,
    activeIcon: Icons.sync_alt_rounded,
    group: AdminGroups.settings,
    resource: 'settings',
    accent: AppColors.primary,
    keywords: ['mone', 'sinxron', 'sync', 'katalog', 'sklad'],
    build: MoneScreen.new,
  ),
  AdminDestination(
    id: 'cloud',
    label: 'Bulut',
    hint: 'Server manzili, sinxronizatsiya sozlamalari',
    icon: Icons.cloud_outlined,
    activeIcon: Icons.cloud_rounded,
    group: AdminGroups.settings,
    resource: 'settings',
    accent: AppColors.info,
    keywords: ['cloud', 'облако', 'server', 'sync'],
    hidden: true,
    build: CloudSettingsScreen.new,
  ),
];

/// Eski backend build'lar login javobida bu ruxsatlarni yubormaydi, natijada
/// super_admin o'zining bo'limini ko'rmay qoladi.
const Set<String> kSuperAdminAlways = {'printers'};

/// Ruxsat talab qilmaydigan bo'lim (video qo'llanma) — hammaga ko'rinadi.
const String kAnyResource = '*';

/// Ruxsatga qarab ko'rinadigan bo'limlar.
///
/// [includeHidden] — texnik bo'limlar (`hidden: true`) ham qo'shiladi.
/// Ular faqat «Local server» belgisi 5 soniya bosib turilganda ochiladi.
List<AdminDestination> visibleDestinations(
  Map<String, dynamic> permissions,
  String role, {
  bool includeHidden = false,
}) {
  final list = kAdminDestinations
      .where((d) {
        if (d.hidden && !includeHidden) return false;
        if (d.resource == kAnyResource) return true;
        final actions = permissions[d.resource];
        final hasAny = actions is List && actions.isNotEmpty;
        return hasAny ||
            (role == 'super_admin' && kSuperAdminAlways.contains(d.resource));
      })
      .toList(growable: false);
  // Faqat qo'llanma qolsa — demak hech qanday ruxsat yo'q («Ruxsat yo'q»
  // ekrani chiqishi kerak, qo'llanma yolg'iz ko'rinmaydi).
  if (list.every((d) => d.resource == kAnyResource)) return const [];
  return list;
}

/// Yashirin bo'limlar umuman bormi (ruxsat bo'yicha) — belgini bosib
/// turishdan ma'no bo'lishi uchun tekshiriladi.
bool hasHiddenDestinations(Map<String, dynamic> permissions, String role) {
  final open = visibleDestinations(permissions, role).length;
  final all = visibleDestinations(
    permissions,
    role,
    includeHidden: true,
  ).length;
  return all > open;
}

/// Ochiq bo'lim va navigatsiya — ekranlar shu orqali sarlavhasini oladi
/// va bir-biriga o'tadi (masalan «Ombor» dan «Kirim partiyalari» ga).
class AdminScope extends InheritedWidget {
  final AdminDestination destination;
  final bool isPhone;

  /// Boshqa bo'limga o'tish. Noma'lum id — e'tiborsiz qoldiriladi.
  final void Function(String id) go;

  /// Bo'limlar ro'yxatini ochish (telefonda pastdan, desktopda qidiruv).
  final VoidCallback openNav;

  const AdminScope({
    super.key,
    required this.destination,
    required this.isPhone,
    required this.go,
    required this.openNav,
    required super.child,
  });

  static AdminScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminScope>();

  @override
  bool updateShouldNotify(AdminScope old) =>
      old.destination.id != destination.id || old.isPhone != isPhone;
}
