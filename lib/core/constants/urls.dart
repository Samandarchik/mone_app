// core/constants/urls.dart — BARCHA backend endpoint manzillari (AppUrls):
// baseUrl + har bir API yo'li (login, products, ombor, yuk, production, stock,
// prices, analytics, POS, filials...). Yangi endpoint SHU YERGA qo'shiladi.
// baseUrl/coreUrl RUNTIME'da sozlanadi (ServerConfig) — shuning uchun hamma
// manzil `static String get` (const emas).
import 'package:uz_ai_dev/core/config/server_config.dart';

abstract final class AppUrls {
  // Runtime qiymat — ServerConfig (SharedPreferences 'base_url'), sozlama
  // dialogi orqali almashtiriladi. Shu sabab quyida hammasi GETTER (const emas).
  static String get baseUrl => ServerConfig.baseUrl;
  // mone_core (/api/v2) yadro manzili — ServerConfig 'core_url'.
  static String get coreUrl => ServerConfig.coreUrl;
  static String get coreApi => '$coreUrl/api/v2';

  static String get login => '$baseUrl/api/login';
  // v1 login — FAQAT parol bilan kirish (eski /api/login telefon+parol
  // bilan ishlashda davom etadi, eski ilova versiyalari uchun).
  static String get loginV1 => '$baseUrl/api/v1/login';
  static String get register => '$baseUrl/api/register';
  static String get productAll => '$baseUrl/api/products/all';
  static String get product1 => '$baseUrl/api/products1';
  static String get product => '$baseUrl/api/products';
  // Masalliqning QO'LDA kiritilgan xarid narxi (hech qachon sotib olinmagan
  // mahsulot uchun): PUT {"manual_price": 8000} — BUTUN so'm, mahsulotning
  // TO'LIQ birligi uchun (кг → 1 kg narxi, шт → 1 dona narxi). 0 —
  // o'chirish. Faqat admin.
  static String productManualPrice(int id) =>
      '$baseUrl/api/products/$id/manual-price';

  // Retsept (tex karta) tarixi: GET — versiyalar ro'yxati (meta, kartasiz),
  // POST rollback {"version_id": N} — kartani tanlangan nusxaga qaytaradi.
  // Faqat admin.
  static String techCardVersions(int id) =>
      '$baseUrl/api/products/$id/tech-card/versions';
  static String techCardRollback(int id) =>
      '$baseUrl/api/products/$id/tech-card/rollback';

  // Ombor (bozor mahsulotlari)
  static String get omborProducts => '$baseUrl/api/ombor/products';

  // Yuk keltiruvchi (sklad buyurtmalari)
  static String get yukOrders => '$baseUrl/api/yuk/orders';
  // Yuk keltiruvchi buyurtmaga biriktiriladigan rasm/video yuklash
  static String get yukUpload => '$baseUrl/api/yuk/upload';
  // Qo'shimcha yozuv "Nomi" maydoni uchun takliflar
  // (?item_type=proche — katalog + ilgarigi nomlar, ?item_type=rasxod —
  // faqat ilgari yozilgan xarajat nomlari).
  static String get procheNames => '$baseUrl/api/yuk/proche-names';
  // Har mahsulotning oxirgi birlik narxi (narxlashda «oldingi narx» + keskin
  // og'ish ogohlantirishi): {products:{id:{price,unit,date}}, names:{...}}.
  static String get yukLastPrices => '$baseUrl/api/yuk/last-prices';
  // Yuk keltiruvchining kunlik hisob daftari (ostatok/rasxod/prixod)
  static String get yukLedger => '$baseUrl/api/yuk/ledger';
  // Bitta kunning xarajat tafsiloti (?date=YYYY-MM-DD[&user_id=N])
  static String get yukLedgerDay => '$baseUrl/api/yuk/ledger/day';
  // Yuk keltiruvchi foydalanuvchilar ro'yxati (bugalter pul berishi uchun)
  static String get yukUsers => '$baseUrl/api/yuk-users';
  // Bugalter yuk keltiruvchiga pul berishi (prixod yozuvi)
  static String get payments => '$baseUrl/api/payments';
  // Targovli (qilinadigan_ishlar) tizimidan yuborilgan pullar —
  // yuk keltiruvchi qabul qiladi/rad etadi (accept/reject POST'lari ham
  // shu bazaviy yo'l ostida: /{id}/accept, /{id}/reject).
  static String get yukTransfers => '$baseUrl/api/yuk/transfers';
  // Yuk keltiruvchining qarz daftari (magazinchilardan qarzlar). Ost-yo'llar:
  //   /{id}                  — magazinni tahrirlash (PUT) / o'chirish (DELETE)
  //   /{id}/debts            — qarz yozuvlari (GET ro'yxat, POST qo'shish)
  //   /{id}/debts/{debtId}   — qarz yozuvini o'chirish (DELETE)
  static String get magazins => '$baseUrl/api/magazins';

  // Bugalter (hisobchi): barcha skladlarning narxlangan/qabul qilingan
  // buyurtmalari.
  static String get bugalterOrders => '$baseUrl/api/bugalter/orders';
  // Bugalter buyurtma ichidagi mahsulot miqdori yoki SUMMASINI tuzatishi
  // (eski APK'lardan qolgan gram xatolari va xato narxlar uchun).
  // PUT {taken?, received?, count?, subtotal?} — kamida bittasi; miqdorlar
  // API birlikda (кг/л -> butun gr/ml), subtotal — BUTUN so'm.
  static String bugalterOrderItemQty(int orderId, int productId) =>
      '$baseUrl/api/bugalter/orders/$orderId/items/$productId/qty';
  // DELETE — bugalter mahsulotni o'chiradi (soft-delete: deleted=true,
  // miqdor/summa nolga qaytadi). Rollar: bugalter yoki admin.
  static String bugalterOrderItem(int orderId, int productId) =>
      '$baseUrl/api/bugalter/orders/$orderId/items/$productId';
  // Shu tahrirlarning TARIXI: GET ?order_id=&product_id=&limit= — kim,
  // qachon, qaysi maydonni, eski → yangi. Eng yangisi birinchi.
  // Rollar: bugalter yoki admin. Javob — audit yozuvlari (AuditLogEntry).
  static String get bugalterEdits => '$baseUrl/api/bugalter/edits';
  // Bugalter Excel hisobot: GET ?from=YYYY-MM-DD&to=YYYY-MM-DD (ikkalasi
  // majburiy, `to` kuni ham kiradi) -> .xlsx binar fayl (attachment).
  // Rollar: bugalter yoki admin. Xato JSON {success:false, message}.
  static String get bugalterExport => '$baseUrl/api/bugalter/export';

  // Ishlab chiqarish (производство) — shef roli.
  // Tex kartasi bor mahsulotlar ro'yxati (buyurtma yaratish uchun).
  static String get productionProducts => '$baseUrl/api/production/products';

  // Admin boshqaruv paneli: bugungi buyurtmalar, ishlab chiqarish holati,
  // kam qolgan xomashyo jamlanmasi.
  static String get dashboard => '$baseUrl/api/dashboard';

  // Kunlik ishlab chiqarish rejasi (MRP): ?date=YYYY-MM-DD&sklad_id=N —
  // filial buyurtmalaridan tort → П/Ф → xomashyo ehtiyoji va defitsit.
  static String get productionRequirements => '$baseUrl/api/production/requirements';
  // Ishlab chiqarish buyurtmalari. Ost-yo'llar:
  //   /{id}                                   — bitta buyurtma
  //   /{id}/items/{pi}/stages/{si}/accept     — shef masalliqni qabul qildi
  //   /{id}/items/{pi}/stages/{si}/reject     — rad etdi (body: {comment})
  //   /{id}/items/{pi}/stages/{si}/progress   — done_qty kiritish (PUT)
  // pi/si — 0-based item/stage indekslari.
  static String get productionOrders => '$baseUrl/api/production/orders';
  // Полуфабрикат qoldig'i bo'yicha buyurtma limiti:
  // GET ?product_id=N&qty=Q (shef/ombor — o'z skladi; admin/bugalter
  // qo'shimcha &sklad_id=M berishi mumkin). data: { sklad_id, max_qty
  // (null = cheksiz), limits: [{product_id, name, image_url, batch_qty,
  // per_batch_need, need, stock, reserved, available}] }.
  static String get pfAvailability => '$baseUrl/api/production/pf-availability';
  // Полуфабрикат QOLDIG'I (butun ro'yxat, buyurtmaga bog'liq emas):
  // GET [?sklad_id=N] (shef/ombor — o'z skladi; admin/bugalter sklad_id
  // berishi mumkin). data: { sklad_id, items: [{product_id, name, image_url,
  // unit, stock, reserved, available, batch_qty, used_in}] }.
  static String get pfStock => '$baseUrl/api/production/pf-stock';
  // Takrorlanadigan bir xil bazalarni полуфабрикат mahsulotlarga aylantirish
  // (faqat admin). POST {"dry_run": true|false} -> data: {created, skipped}.
  static String get techcardsConvertPf => '$baseUrl/api/techcards/convert-pf';

  // Sklad qoldig'i (to'liq inventar). GET ?sklad_id=N — qoldiqlar ro'yxati.
  static String get stock => '$baseUrl/api/stock';
  // POST {sklad_id, product_id, qty(+/-), comment} — qo'lda korreksiya.
  static String get stockAdjust => '$baseUrl/api/stock/adjust';
  // GET ?sklad_id=N[&product_id=M][&limit=K] — harakatlar tarixi (desc).
  static String get stockMoves => '$baseUrl/api/stock/moves';
  // POST {sklad_id, product_id, qty(+), reason} — SPISANIYA (brak/yo'qotish):
  // skladdan chiqim + audit ("spisaniya" — POS spisaniyasi bilan bitta hisobot).
  static String get stockWriteOff => '$baseUrl/api/stock/write-off';
  // POST {sklad_id, product_id, min_qty} — minimal qoldiq chegarasi.
  static String get stockMin => '$baseUrl/api/stock/min';
  // POST {sklad_id, items:[{product_id, actual_qty}]} — inventarizatsiya
  // (real sanab chiqilgan qoldiqlar; farqlar korreksiya bo'lib yoziladi).
  static String get stockInventory => '$baseUrl/api/stock/inventory';
  // Inventarizatsiya dalolatnomalari (акт): qachon sanalgan, nima kam chiqqan
  // va bu qancha pul. Ombor — o'z skladi, admin — istalgani. Ost-yo'llar:
  //   GET ?sklad_id=N[&limit=K] — ro'yxat (eng yangisi birinchi, items'siz)
  //   GET /{id}                 — bitta dalolatnoma, items (farqli qatorlar)
  //                               bilan; narxlar sanash paytidagi holatda.
  static String get stockInventories => '$baseUrl/api/stock/inventories';

  // Tannarx: GET ?product_id=N — mahsulot tex kartasi bo'yicha 1 partiya /
  // 1 dona tannarxi (admin/bugalter).
  static String get productionCost => '$baseUrl/api/production/cost';
  // Statistika: GET ?from=YYYY-MM-DD&to=YYYY-MM-DD (admin/bugalter).
  static String get productionStats => '$baseUrl/api/production/stats';
  // Oxirgi xarid narxlari: GET — barcha mahsulotlarning eng so'nggi narxi.
  // unit_price ENG KICHIK birlik uchun (кг/л -> 1 gr/ml, шт -> 1 dona,
  // м -> 1 metr). Hech narxlanmaganlar ro'yxatda yo'q. Admin/bugalter.
  static String get latestPrices => '$baseUrl/api/prices/latest';
  // Xarid narxlari tarixi: GET ?product_id=N&limit=20 — bitta mahsulotning
  // narxlangan xaridlari (eng yangisi birinchi). Admin/bugalter.
  static String get pricesHistory => '$baseUrl/api/prices/history';
  // Foyda analitikasi: GET ?days=N (7/30/90) — tortlar bo'yicha tushum/
  // tannarx/foyda, kunlik marja dinamikasi va masalliq narx sakrashlari.
  // Admin/bugalter.
  static String get profitAnalytics => '$baseUrl/api/analytics/profit';

  // Audit jurnali: GET ?limit=&entity=&action= — admin harakatlari tarixi
  // (narx o'zgarishi, sklad korreksiyasi, o'chirishlar...). Faqat admin.
  static String get auditLog => '$baseUrl/api/audit-log';

  static String get users => '$baseUrl/api/users';
  // Login+parolni Telegram orqali yuborish:
  //   POST $users/{id}/send-credentials — bitta foydalanuvchiga (service ichida quriladi)
  //   POST quyidagi manzil — barcha foydalanuvchilarga birdan
  static String get usersSendAllCredentials => '$users/send-all-credentials';
  // GET — Telegram bot username'i ({"data":{"username":"..."}}).
  static String get telegramBot => '$baseUrl/api/telegram-bot';
  static String get orders => '$baseUrl/api/orders';

  // Real-time buyurtmalar uchun WebSocket. https->wss, http->ws avtomatik.
  static String get wsOrders => '${baseUrl.replaceFirst('http', 'ws')}/api/ws';
  //filials
  static String get filials => '$baseUrl/api/filials';

  // Skladlar (omborxonalar): GET — hamma rol o'qiydi (nom/tab/dropdown shu
  // ro'yxatdan); POST {name}, PUT /{id} {name}, DELETE /{id} — faqat superadmin.
  static String get sklads => '$baseUrl/api/sklads';

  // Print agentlar (admin): ulangan Windows agentlar va ulardagi real printer
  // nomlari — kategoriya oynasidagi printer dropdown shu ro'yxatdan quriladi.
  static String get printAgents => '$baseUrl/api/print-agents';
  // Filial limitlari: GET ?filial_id=N — filialning mahsulot limitlari;
  // POST {filial_id, product_id, limit_qty} — upsert (limit_qty: 0 —
  // o'chirish). limit_qty birlik kontrakti: кг/л -> BUTUN gr/ml. Faqat admin.
  static String get filialLimits => '$baseUrl/api/filial-limits';
  // POS (Konak) buyurtmalari: GET ?limit=50 — «POS avto» useri yaratgan
  // avto-buyurtmalar (eng yangisi birinchi). Faqat admin.
  static String get posOrders => '$baseUrl/api/pos-orders';
  // POST — buyurtmani bazadan POS'ga yuborish (PosDelivery yaratadi).
  static String posOrderDispatch(int id) =>
      '$baseUrl/api/pos-orders/$id/dispatch';
  // POS smena sotuvlari hisoboti: GET ?days=30[&filial_id=] —
  // {sales:[...], total}. days default 30, clamp [1,92]. Faqat admin.
  static String get posSales => '$baseUrl/api/pos-sales';
  // POS smena solishtirish (recon): GET ?days=30[&filial_id=] —
  // {recons:[...]}. days default 30, clamp [1,92]. Faqat admin.
  static String get posRecons => '$baseUrl/api/pos-recons';
  // POS menyu — Konak POS ko'radigan katalog: GET ?filial_id=N (ixtiyoriy,
  // default birinchi filial) — {filial_id, filial_name, categories, products}.
  // Faqat admin.
  static String get posMenu => '$baseUrl/api/pos-menu';
  // RK7 integratsiyasi (faqat admin). Import qilingan smenalar: GET ?days=30 —
  // {shifts:[...]}, eng yangisi birinchi, days clamp [1,92].
  static String get rk7Shifts => '$baseUrl/api/rk7/shifts';
  // Bitta smena to'liq: items/voids/deductions/unmapped.
  static String rk7Shift(int id) => '$baseUrl/api/rk7/shifts/$id';
  // Sotuvda uchragan bog'lanmagan RK7 taomlari (smenalardan jamlab):
  // {dish_guid, dish_name, last_date, total_qty_milli}.
  static String get rk7Unmapped => '$baseUrl/api/rk7/unmapped';
  // Taom → Mone mahsuloti bog'lanishi: GET ?q= (nom/kod qidiruvi, limit 200);
  // POST {dish_guid, product_id, deduct_mode, per_portion, active} — upsert.
  // per_portion — BUTUN (1 porsiyaga necha saqlash birligi), float yo'q.
  static String get rk7Mappings => '$baseUrl/api/rk7/mappings';
  // RK7 sotuv nuqtalari: GET — hammasi (mapping holati bilan);
  // POST {uot_guid, filial_id, sklad_id, active} — upsert.
  static String get rk7SalePlaces => '$baseUrl/api/rk7/sale-places';
  // SH5 (StoreHouse) qoldiq ko'rinishi (faqat admin, PLAN_OSTATKA bosqich 0):
  // GET — omborlar ro'yxati {sklads:[{id, sh5_rid, name, taken_at,
  // goods_count}]}; manba vaqtincha StoreHouse, keyin Mone stock egallaydi.
  static String get sh5Remains => '$baseUrl/api/sh5/remains';
  // Bitta SH5 ombori tovarlari: GET ?q= (nom qidiruvi) — {name, taken_at,
  // goods:[{rid, name, unit, qty_milli}]}. qty_milli — qoldiq×1000 BUTUN.
  static String sh5Remain(int id) => '$baseUrl/api/sh5/remains/$id';
  // Bridge'dan qoldiqni QAYTA o'qishni so'rash (kassir «yangilash» bosganda):
  // POST — {requested:true}. Bridge poll qilib push qiladi, keyin taken_at
  // yangilanadi (ilova shuni kutadi).
  static String get sh5Refresh => '$baseUrl/api/sh5/refresh';
  // Smena topshirish qoralamasi: GET ?sklad_id= — {sklad_id, sklad_name,
  // taken_at, has_open, open_handover_id, prev, items:[{rid, name, unit,
  // sh5_milli, prev_out_milli}]}. Miqdorlar milli BUTUN son.
  static String get sh5HandoverDraft => '$baseUrl/api/sh5/handover/draft';
  // Qabul kutayotgan topshiriq: GET ?sklad_id= — Sh5Handover yoki null.
  static String get sh5HandoverOpen => '$baseUrl/api/sh5/handover/open';
  // Smenani topshirish: POST {sklad_id, note, items:[{rid, qty_milli}]}.
  // Yuborilmagan tovar StoreHouse soni bilan yoziladi.
  static String get sh5Handover => '$baseUrl/api/sh5/handover';
  // Qabul qilish: POST {note, items:[{rid, qty_milli}]} — farq = kamomad.
  static String sh5HandoverAccept(int id) =>
      '$baseUrl/api/sh5/handover/$id/accept';
  // Topshiriqlar tarixi: GET ?sklad_id=&days=&all=1 — {handovers:[...]}.
  static String get sh5Handovers => '$baseUrl/api/sh5/handovers';
  // Bitta topshiriq: GET ?diff=1 — faqat farq chiqqan qatorlar.
  static String sh5HandoverDetail(int id) => '$baseUrl/api/sh5/handovers/$id';

  //Category
  static String get category => '$baseUrl/api/categories';
  static String get categoryReorder => '$baseUrl/api/categories/reorder';
  static String get productReorder => '$baseUrl/api/products/reorder';

  // Upload
  static String get upload => '$baseUrl/api/upload';

  // Kategoriya mahsulotlari PDF katalogi (POST — stream yuklab olinadi).
  static String categoryPdf(int categoryId) =>
      '$baseUrl/api/products/category/$categoryId/pdf';
}
