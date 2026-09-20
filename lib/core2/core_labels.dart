// core2/core_labels.dart — «Oson rejim» yorliqlari va XATO TARJIMONI.
// Tamoyil (PLAN_UI_OSON §1.5): foydalanuvchi vazifa nomini ko'radi («Kirim»),
// SH5 atamasi kichik kulrang ostyozuv («Приход»); xato va ogohlantirishlar —
// oddiy o'zbekcha, sabab + nima qilish kerak.
//
// Bu yerda YAGONA manba: vazifa plitkalari (CoreTask — nom, rang, ikonka,
// kerakli ruxsat), hujjat turi/holati nomlari, ruxsat kalitlarining o'zbekcha
// nomi, HTTP/server `code` → matn (coreErrorUz), post javobidagi `warnings`
// kodlari (negative_stock|no_batch|no_recipe|recipe_cycle|rounding) → guruh
// sarlavhasi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

// ───────────────────────────── Vazifalar ─────────────────────────────

/// Bosh sahifadagi amal plitkasi: vazifa nomi + SH5 atamasi + ruxsat.
class CoreTask {
  /// Hujjat turi (`CoreDocType.*`) yoki `stock` — qoldiq ekrani.
  final String key;
  final String title; // «Kirim»
  final String sh5; // «Приход» — Xilola tanishi uchun
  final String hint; // bir qatorli tushuntirish
  final IconData icon;
  final Color color;

  const CoreTask({
    required this.key,
    required this.title,
    required this.sh5,
    required this.hint,
    required this.icon,
    required this.color,
  });

  /// Shu plitka uchun kerak bo'lgan ruxsat kaliti.
  String get perm => key == coreTaskStock
      ? CorePerms.stockView
      : CorePerms.docCreate(CoreDocType.permType(key));
}

/// Hujjat turi emas — qoldiq ekrani plitkasi.
const String coreTaskStock = 'stock';

const List<CoreTask> coreTasks = [
  CoreTask(
    key: CoreDocType.receipt,
    title: 'Kirim',
    sh5: 'Приход',
    hint: 'Bozor, ta\'minotchi',
    icon: Icons.download_outlined,
    color: Color(0xFF2E7D32),
  ),
  CoreTask(
    key: CoreDocType.transfer,
    title: 'Ko\'chirish',
    sh5: 'Перемещение',
    hint: 'Ombordan omborga',
    icon: Icons.swap_horiz,
    color: Color(0xFF1565C0),
  ),
  CoreTask(
    key: CoreDocType.inventory,
    title: 'Sanash',
    sh5: 'Сличительная',
    hint: 'Fakt qoldiqni kiritish',
    icon: Icons.fact_check_outlined,
    color: Color(0xFF6A1B9A),
  ),
  CoreTask(
    key: CoreDocType.issue,
    title: 'Hisobdan chiqarish',
    sh5: 'Расход',
    hint: 'Yaroqsiz, sarf, sotuv',
    icon: Icons.upload_outlined,
    color: Color(0xFFC62828),
  ),
  CoreTask(
    key: CoreDocType.production,
    title: 'Ishlab chiqarish',
    sh5: 'Переработка',
    hint: 'Sarf → mahsulot',
    icon: Icons.factory_outlined,
    color: Color(0xFFEF6C00),
  ),
  CoreTask(
    key: coreTaskStock,
    title: 'Qoldiq',
    sh5: 'Остатки',
    hint: 'Ombordagi tovarlar',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF546E7A),
  ),
];

CoreTask? coreTaskOf(String key) {
  for (final t in coreTasks) {
    if (t.key == key) return t;
  }
  return null;
}

// ─────────────────────── Hujjat turi va holati ───────────────────────

/// Tur → vazifa nomi («Kirim», «Ko'chirish»…).
String coreTypeUz(String type) {
  switch (type) {
    case CoreDocType.receipt:
      return 'Kirim';
    case CoreDocType.issue:
      return 'Hisobdan chiqarish';
    case CoreDocType.transfer:
      return 'Ko\'chirish';
    case CoreDocType.inventory:
      return 'Sanash';
    case CoreDocType.production:
      return 'Qayta ishlash';
    case CoreDocType.act:
      return 'Ishlab chiqarish akti';
    case CoreDocType.reserve:
      return 'Rezerv';
    default:
      return type;
  }
}

/// Tur → SH5 atamasi (kichik kulrang ostyozuv).
String coreTypeSh5(String type) {
  switch (type) {
    case CoreDocType.receipt:
      return 'Приход';
    case CoreDocType.issue:
      return 'Расход';
    case CoreDocType.transfer:
      return 'Перемещение';
    case CoreDocType.inventory:
      return 'Сличительная';
    case CoreDocType.production:
      return 'Переработка';
    case CoreDocType.act:
      return 'Акт';
    case CoreDocType.reserve:
      return 'Резерв';
    default:
      return '';
  }
}

Color coreTypeColor(String type) =>
    coreTaskOf(type)?.color ?? const Color(0xFF546E7A);

IconData coreTypeIconUz(String type) =>
    coreTaskOf(type)?.icon ?? Icons.description_outlined;

/// Holat → oddiy til: draft «Tugallanmagan», posted «Bajarildi».
String coreStatusUz(String status) {
  switch (status) {
    case CoreDocStatus.draft:
      return 'Tugallanmagan';
    case CoreDocStatus.posted:
      return 'Bajarildi';
    case CoreDocStatus.cancelled:
      return 'Bekor qilingan';
    default:
      return status;
  }
}

// ───────────────────────────── Ruxsatlar ─────────────────────────────

/// Ruxsat kaliti → o'zbekcha nom («doc.receipt.post» → «Kirimni o'tkazish»).
String corePermUz(String perm) {
  switch (perm) {
    case CorePerms.docBackdate:
      return 'Orqa sana bilan hujjat';
    case CorePerms.docCancel:
      return 'Hujjatni bekor qilish';
    case CorePerms.dictEdit:
      return 'Lug\'atlarni tahrirlash';
    case CorePerms.recipeEdit:
      return 'Retseptlarni tahrirlash';
    case CorePerms.stockView:
      return 'Qoldiqni ko\'rish';
    case CorePerms.stockCostView:
      return 'Qoldiq summasini ko\'rish';
    case CorePerms.reportView:
      return 'Hisobotlar';
    case CorePerms.usersManage:
      return 'Foydalanuvchilar';
    case CorePerms.integrationManage:
      return 'Integratsiya sozlamalari';
  }
  final parts = perm.split('.');
  if (parts.length == 3 && parts.first == 'doc') {
    final name = coreTypeUz(parts[1]);
    return parts[2] == 'post' ? '$name — o\'tkazish' : '$name — yaratish';
  }
  return perm;
}

// ──────────────────────────── Xato tarjimoni ────────────────────────────

/// Foydalanuvchiga ko'rsatiladigan xato: sarlavha (sabab) + maslahat
/// (nima qilish kerak). `warning` — qizil emas, sariq ko'rsatiladi.
class CoreUiError {
  final String title;
  final String hint;
  final bool warning;
  const CoreUiError(this.title, {this.hint = '', this.warning = false});

  String get text => hint.isEmpty ? title : '$title\n$hint';
}

/// Serverdan kelgan texnik matnni tozalash: «ledger: …» prefiksi, nuqta-vergul.
String _clean(String msg) {
  var m = msg.trim();
  for (final p in ['ledger: ', 'api: ', 'sql: ']) {
    if (m.startsWith(p)) m = m.substring(p.length);
  }
  return m;
}

/// Xatodagi `details.sklad_id` (403 «bu omborga ruxsat yo'q», 422 «ombor
/// topilmadi») — ombor nomini ko'rsatish uchun.
int? _skladIdOf(CoreApiException err) {
  final v = err.details['sklad_id'];
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}');
}

/// «Retsept yo'q» xatosimi: yangi serverda `422 validation` («retsept yo'q:
/// `good_id`»), eski serverda oddiy `500` (ACT_KONTRAKT §7).
bool coreIsNoRecipeError(Object e) {
  final err = CoreClient.wrap(e);
  if (err.status == 500) return true;
  if (err.status != 422) return false;
  final m = err.message.toLowerCase();
  return m.contains('retsept') || m.contains('recipe') || m.contains('рецепт');
}

/// HTTP kod + server `code` → oddiy o'zbekcha matn.
/// 401/403 (ruxsat nomi bilan, ombor cheklovi `details.sklad_id` bilan),
/// 409, 422 `insufficient`/`validation` (shu jumladan `from_sklad` —
/// xomashyo ombori), 501, tarmoq uzilishi — har biri uchun «nima qilish
/// kerak» maslahati bilan.
///
/// [skladName] — ombor ID sini nomga aylantiruvchi (odatda
/// `CoreDictProvider.skladName`); berilmasa «Ombor #id» yoziladi.
CoreUiError coreErrorUz(Object e, {String Function(int)? skladName}) {
  final err = CoreClient.wrap(e);
  final details = _detailsUz(err);
  String nameOf(int id) => skladName?.call(id) ?? 'Ombor #$id';

  if (err.network) {
    return const CoreUiError(
      'Server bilan aloqa yo\'q',
      hint: 'Internet yoki ombor serverini tekshiring, so\'ng qayta urining.',
    );
  }
  if (err.notImplemented) {
    return CoreUiError(
      'Bu amal serverda hali yoqilmagan',
      hint: _clean(err.message),
      warning: true,
    );
  }
  switch (err.status) {
    case 401:
      return const CoreUiError(
        'Kirish muddati tugagan',
        hint: 'Ilovaga qaytadan kiring.',
      );
    case 403:
      // Ombor cheklovi (users.sklads): aktda IKKALA ombor ham ruxsat
      // etilgan bo'lishi shart — qaysi biri yopiq ekanini aytamiz.
      final sklad = _skladIdOf(err);
      if (sklad != null && sklad > 0) {
        return CoreUiError(
          'Bu omborga ruxsatingiz yo\'q: ${nameOf(sklad)}',
          hint: 'Aktda xomashyo ombori ham, mahsulot ombori ham sizga '
              'ochiq bo\'lishi kerak. Boshqa omborni tanlang yoki '
              'rahbaringizdan ruxsat so\'rang.',
        );
      }
      final p = err.perm.isEmpty
          ? ''
          : 'Kerakli ruxsat: «${corePermUz(err.perm)}». ';
      return CoreUiError(
        'Sizda bu amalga ruxsat yo\'q',
        hint: '${p}Rahbaringizdan so\'rang.',
      );
    case 404:
      return const CoreUiError(
        'Topilmadi',
        hint: 'Hujjat yoki yozuv o\'chirilgan bo\'lishi mumkin. Ro\'yxatni yangilang.',
      );
    case 409:
      return CoreUiError(
        'Hujjat holati o\'zgargan',
        hint: details.isNotEmpty
            ? details
            : 'Uni boshqa xodim o\'tkazgan yoki bekor qilgan bo\'lishi mumkin. '
                'Ekranni yangilab, qaytadan ko\'ring.',
      );
    case 422:
      if (err.code == 'insufficient') {
        return CoreUiError(
          'Qoldiq yetmaydi',
          hint: '${_clean(err.message)}\n'
              'Miqdorni kamaytiring yoki avval kirim qiling.',
        );
      }
      final msg422 = _clean(err.message);
      final low = msg422.toLowerCase();
      // Xomashyo ombori noto'g'ri (`from_sklad <= 0`).
      if (low.contains('from_sklad')) {
        return const CoreUiError(
          'Xomashyo ombori noto\'g\'ri tanlangan',
          hint: '«Xomashyo qayerdan?» ni qaytadan tanlang. Bo\'sh qoldirilsa '
              'xomashyo mahsulot omboridan yechiladi.',
        );
      }
      // «ombor topilmadi: <id>» — ID ni nomga aylantiramiz.
      if (low.startsWith('ombor topilmadi')) {
        final id = int.tryParse(msg422.split(':').last.trim());
        return CoreUiError(
          id == null
              ? 'Ombor topilmadi'
              : 'Ombor topilmadi: ${nameOf(id)}',
          hint: 'Ombor o\'chirilgan bo\'lishi mumkin. Ro\'yxatni yangilab, '
              'boshqa omborni tanlang.',
        );
      }
      if (coreIsNoRecipeError(err)) {
        return CoreUiError(
          'Retsept topilmadi',
          hint: '$msg422\nSarf qatorlarini qo\'lda kiriting yoki retsept '
              'qo\'shing.',
          warning: true,
        );
      }
      return CoreUiError(
        'Ma\'lumot to\'liq emas',
        hint: details.isNotEmpty ? details : msg422,
      );
  }
  final msg = _clean(err.message);
  return CoreUiError(
    msg.isEmpty ? 'Xatolik yuz berdi' : msg,
    hint: details,
  );
}

/// Server `details` (422/409) — qisqa matn: «good_id: 33 · base_units: kg».
String _detailsUz(CoreApiException err) {
  if (err.details.isEmpty) return '';
  final parts = <String>[];
  for (final e in err.details.entries) {
    final v = e.value;
    final text = v is List ? v.take(5).join(', ') : '$v';
    if (text.isEmpty) continue;
    parts.add('${e.key}: $text');
    if (parts.length >= 3) break;
  }
  return parts.join(' · ');
}

/// Xatoni oddiy tilda SnackBar'da ko'rsatish. Ombor nomi lug'at keshidan
/// olinadi (403 «bu omborga ruxsat yo'q» → ombor nomi bilan).
void showErrorUz(BuildContext context, Object e) {
  String Function(int)? nameOf;
  try {
    final dict = context.read<CoreDictProvider>();
    nameOf = (id) => dict.skladName(id);
  } catch (_) {
    // Provider yo'q (test/alohida ekran) — ID bilan ko'rsatiladi.
  }
  final ui = coreErrorUz(e, skladName: nameOf);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ui.text),
    duration: Duration(seconds: ui.hint.isEmpty ? 4 : 6),
    backgroundColor:
        ui.warning ? Colors.orange.shade800 : Colors.red.shade700,
  ));
}

/// Oddiy xabar (yashil emas — neytral).
void showInfoUz(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

// ──────────────────────── Post ogohlantirishlari ────────────────────────

/// `warnings[].code` → guruh sarlavhasi (oddiy til).
String coreWarnTitleUz(String code) {
  switch (code) {
    case 'negative_stock':
      return 'Qoldiq yetmadi (minusga ketdi)';
    case 'no_batch':
      return 'Partiya topilmadi (tannarxsiz yechildi)';
    case 'no_recipe':
      return 'Retsept topilmadi';
    case 'recipe_cycle':
      return 'Retseptda sikl (ichkariga yoyilmadi)';
    case 'rounding':
      return 'Yaxlitlash farqi';
    default:
      return 'Ogohlantirish';
  }
}

/// Guruh uchun «nima qilish kerak».
String coreWarnHintUz(String code) {
  switch (code) {
    case 'negative_stock':
      return 'Hujjat o\'tdi, lekin bu tovarlar ombor hisobida minusda. '
          'Kirimni kiriting yoki sanab chiqing.';
    case 'no_batch':
      return 'Kirim hujjati kiritilmagani uchun tannarx 0 bilan yozildi. '
          'Kirimni kiriting — tannarx tiklanadi.';
    case 'no_recipe':
      return 'Taomning retsepti yo\'q — ingredientlar yechilmadi. '
          'Retsept qo\'shilsa keyingi hujjatlar to\'g\'ri hisoblanadi.';
    case 'recipe_cycle':
      return 'Yarim tayyorning retsepti o\'zini o\'zi chaqiradi yoki juda '
          'chuqur. Uning ichi yoyilmadi — yarim tayyorning o\'zi ombordan '
          'yechildi. Retseptni tekshiring.';
    case 'rounding':
      return 'Miqdor eng kichik birlikka yaxlitlandi — farq juda kichik.';
    default:
      return '';
  }
}

IconData coreWarnIconUz(String code) {
  switch (code) {
    case 'negative_stock':
      return Icons.remove_circle_outline;
    case 'no_batch':
      return Icons.layers_clear_outlined;
    case 'no_recipe':
      return Icons.menu_book_outlined;
    case 'recipe_cycle':
      return Icons.loop;
    case 'rounding':
      return Icons.straighten;
    default:
      return Icons.info_outline;
  }
}

/// Ogohlantirishlarni kod bo'yicha guruhlash (tartib: eng muhimi birinchi).
Map<String, List<CoreDocWarning>> coreGroupWarnings(
    List<CoreDocWarning> warnings) {
  const order = [
    'negative_stock',
    'no_batch',
    'no_recipe',
    'recipe_cycle',
    'rounding',
  ];
  final byCode = <String, List<CoreDocWarning>>{};
  for (final w in warnings) {
    byCode.putIfAbsent(w.code, () => []).add(w);
  }
  final keys = byCode.keys.toList()
    ..sort((a, b) {
      final ia = order.indexOf(a), ib = order.indexOf(b);
      return (ia < 0 ? order.length : ia).compareTo(ib < 0 ? order.length : ib);
    });
  return {for (final k in keys) k: byCode[k]!};
}
