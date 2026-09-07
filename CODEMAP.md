# CODEMAP — `uz_ai_dev` (Mone Flutter ilovasi)

Bu fayl butun ilova bo'ylab **tez navigatsiya** uchun. Sessiya boshida shuni o'qi:
qaysi papka nima uchun, feature qanday qatlamlarga bo'linadi, muhim ekran/provider
qayerda va «falon vazifa uchun qayerga qarash» kerak.

- Har bir `.dart` faylning eng tepasida qisqa **maqsad izohi** bor (asosiy
  class/screen/provider nomi bilan) — grep uchun ideal boshlanish nuqtasi.
- Stack: **Provider** (ChangeNotifier) holat, **GetIt** (`sl<...>`) DI, **Dio** HTTP,
  **SharedPreferences** lokal saqlash. Feature naqsh: `models/ → services/ → provider/ → ui/`.
- Rollar: `seller` (=user), `admin`/`superadmin`, hamda ichki logistika rollari
  `ombor`, `yuk_keltiruvchi`, `bugalter`, `shef` (roles: `lib/core/constants/roles.dart`).
- ⚠️ **Float serverga yubormaymiz.** кг/л miqdorlar API'da BUTUN гр/мл; pul — BUTUN so'm int.
  Konvert: `lib/core/utils/qty_units.dart`.

---

## 1. Papka xaritasi

| Papka | Roli / feature | Asosiy ekranlar / providerlar |
|---|---|---|
| `lib/admin/` | admin / superadmin: mahsulot, kategoriya, тех карта, foyda, POS, filial, user | `AdminHomeUi`, `AddProductPage`, `EditProductPage`, `TechCardEditorPage`, `ProfitControlUi`, `ProfitAnalyticsUi`, POS ekranlari (`pos_*_ui`), `FilialLimitsUi`, `UserManagementScreen`. Providerlar: `ProductProviderAdmin` (YAGONA manba), `CategoryProviderAdmin`, `FilialProviderAdmin`, `CategoryProviderAdminUpload` |
| `lib/user/` | `seller` (oddiy foydalanuvchi): katalog ko'rish + buyurtma berish | `UserHomeUi`, `ProductsScreen`, `UserProductDetailUi`, `CartPage` (`order_ui`), `OrdersPage`. Provider: `ProductProvider` (`user/provider/provider.dart`) |
| `lib/ombor/` | `ombor` (bozor/sklad): bozor mahsulotidan buyurtma, ishlab chiqarish, qoldiq | `OmborHomeUi`, `OmborCategoryProductsUi`, `OmborOrdersUi`, `OmborProductionUi`, `OmborStockUi`, `OmborLowStockUi`. Provider: `OmborProvider`, `OmborProductionProvider` |
| `lib/yuk/` | `yuk_keltiruvchi`: sklad buyurtmalari, kunlik hisob daftari, magazin qarzlari, targovli pul | `YukHomeUi` (katta), `YukProfileUi`, `YukMagazinUi`/`YukMagazinDetailUi`, `YukHistoryUi`, `YukTransferHistoryUi`. Provider: `YukProvider` (markaziy), `MagazinProvider` |
| `lib/production/` | ishlab chiqarish + sklad qoldig'i + tannarx + narx tarixi + inventarizatsiya (акт). `ombor`/`admin`/`bugalter`/`shef` uchun umumiy | `StockInventoryPage`, `InventoryHistoryPage`, vidjetlar (`stock_widgets`, `production_order_widgets`, `cost_sheet`, `price_history_sheet`). Provider: `StockProvider`, `Base/Ombor/Admin/BugalterProductionProvider` |
| `lib/shef/` | `shef`: ishlab chiqarish buyurtmasi yaratish, bosqichlarni qabul/rad, полуфабрикат limiti | `ShefHomeUi`, `ShefCreateOrderUi`, `ShefOrderDetailUi`. Provider: `ShefProvider` |
| `lib/bugalter/` | `bugalter` (hisobchi): narxlangan buyurtmalar, mahsulot soni/summasini tuzatish + tahrirlar tarixi, yuk keltiruvchiga pul berish | `BugalterHomeUi`, `BugalterProductionUi`, `BugalterEditsUi`, `EditHistoryTile` (`ui/widgets/edit_history.dart`). Provider: `BugalterProvider` |
| `lib/core/` | umumiy yadro: DI, tarmoq, lokal saqlash, endpointlar, birlik konverti, media | `di.dart`, `urls.dart` (`AppUrls`), `config/server_config.dart` (`ServerConfig` — runtime base_url/core_url), `widgets/server_settings_dialog.dart`, `dio_settings.dart`, `order_socket.dart`, `qty_units.dart`, `piece_weight.dart` (nomdan «1шт=Xгр»), `context_extension.dart`, `media/*` (kamera/video) |
| `lib/core2/` | **Ombor 2.0** — `mone_core` (`/api/v2`, port 1020) hujjat oqimlari; SH5 o'rnini bosuvchi. Mavjud ekranlar bilan PARALLEL ishlaydi | `CoreHubUi` (grid), `DocsListUi`/`DocFormUi`/`DocDetailUi`, `StockUi`/`StockCardUi`, `DictSkladsUi`/`DictGoodsUi`/`DictCorrsUi`, `RecipesUi`, `PermsUi`/`CoreUsersUi`, `SalePointsUi`/`ApiKeysUi`/`WebhooksUi`, `ReportsUi`, `SyncStatusUi`. Providerlar: `CoreSession`, `CoreDictProvider`, `CoreDocsProvider`, `CoreStockProvider`. 8-bo'limga qara |
| (root) `lib/` | kirish + marshrutlash | `main.dart`, `splash_screen.dart` (rolga yo'naltirish), `login_page.dart`, `check_version.dart` |

---

## 2. Feature naqshi (`models → services → provider → ui`)

Har bir feature 4 qatlamga bo'linadi:

1. **`models/`** — `fromJson`/`toJson` bilan ma'lumot modeli (backend `snake_case`).
2. **`services/`** — Dio bilan bitta API chaqiruvi; `AppUrls` dan endpoint oladi.
3. **`provider/`** — `ChangeNotifier`, holatni ushlaydi, service'ni chaqiradi, `notifyListeners()`.
4. **`ui/`** — ekran; `context.watch/read<Provider>()` orqali holatga ulanadi.

### Konkret misol — тех карта / полуфабрикат oqimi

Bitta mahsulotning тех карта (kompozitsiya) va tannarxi qanday qatlamlardan o'tadi:

| Qatlam | Fayl | Nima qiladi |
|---|---|---|
| model | `lib/admin/model/tech_card.dart` | `TechCard`, `bases[]`, `consumables[]`; og'irliklar BUTUN gr/ml, avto-hisob |
| model | `lib/admin/model/product_model.dart` | `ProductModelAdmin` — `techCard`, `isSemiFinished`, `wasteBase/wasteAmount`, `pieceWeightG` («1 шт = X gr», tuxum kabi шт mahsulotni tex kartada grammda kiritish uchun) |
| **tannarx** | `lib/admin/model/tech_card_cost.dart` | **YAGONA manba** — sof funksiyalar (`techIngredientPieceCost`, `techFullPieceCost`); narx `GET /api/prices/latest`. шт mahsulot gramm qatori konverti — `techEffectivePieceWeightG` |
| service | `lib/production/services/production_service.dart` | `GET /api/production/products`, narxlar; `admin/services/api_product_service.dart` — mahsulot CRUD |
| provider | `lib/admin/provider/admin_product_provider.dart` | `ProductProviderAdmin` — mahsulotni xotirada saqlaydi/yangilaydi |
| ui | `lib/admin/ui/tech_card_editor_page.dart` | `TechCardEditorPage` — Excel «тех карта» varag'iga o'xshash muharrir |
| ui (widget) | `lib/admin/ui/widgets/tech_card_section.dart`, `tech_item_editor.dart` | muharrir sub-vidjetlari |
| ui (foyda) | `lib/admin/ui/profit_control_ui.dart` | `ProfitControlUi` — o'sha `tech_card_cost.dart` bilan marja hisoblaydi |

**Muhim:** tannarx matematikasi FAQAT `tech_card_cost.dart` da. Yangi joyda tannarx
hisoblama — o'sha helperlarni chaqir.

---

## 3. Yadro (core) qatlami

| Nima | Fayl | Izoh |
|---|---|---|
| **DI (GetIt)** | `lib/core/di/di.dart` | `setupInit()` — `SharedPreferences`, `BaseStorage`/`TokenStorage`, `Dio` singletonlari. `main()` dan birinchi chaqiriladi. `sl<T>()` bilan olinadi |
| **Global providerlar** | `lib/main.dart` | `MultiProvider` ro'yxati (7-bo'limga qara). Yangi global provider shu yerga qo'shiladi |
| **Marshrutlash** | `lib/splash_screen.dart` | token+role bo'yicha mos Home'ga (`context.pushReplacement`). `lib/core/context_extension.dart` — `push`/`pushReplacement`/`pushAndRemove` qisqartmalari (nomli route YO'Q) |
| **Endpointlar** | `lib/core/constants/urls.dart` | `AppUrls` — BARCHA v1 API manzillari, hammasi `static String get` (const EMAS — `baseUrl` runtime). Yangi endpoint SHU YERGA. `coreUrl`/`coreApi` — mone_core (`/api/v2`) |
| **Server manzili (runtime)** | `lib/core/config/server_config.dart` | `ServerConfig` — `base_url` (v1, default prod domen) va `core_url` (v2, default `http://localhost:1020`) SharedPreferences'da; `setupInit()` da yuklanadi; `save()` → `revision` notifier (Dio baseUrl yangilanadi). `normalize()`: «localhost:1020»/IP → http, domen → https. Dialog: `core/widgets/server_settings_dialog.dart` (`showServerSettingsDialog`) — login ⚙, admin menyu «Server sozlamalari», Ombor 2.0 hub; «Tekshirish» = `GET $coreUrl/api/v2/health` |
| **Dio + token** | `lib/core/network/dio_settings.dart` | `AppDioClient.createDio()` — `Bearer` token interceptor, `X-Qty-Unit: milli` header (гр/мл kontrakti), faqat-debug logger |
| **WebSocket** | `lib/core/network/order_socket.dart` | `OrderSocket` (singleton) — buyurtma/targovli-pul/ishlab-chiqarish real-time hodisalari; auto-reconnect |
| **Xato matni** | `lib/core/network/error_handler.dart` | `parseDioError()` — DioException → o'qiladigan matn |
| **Lokal saqlash** | `lib/core/data/local/` | `BaseStorage` interfeys, `SharedPreferencesImpl`, `TokenStorage` (`token`). Kalitlar: `token`, `role`, `is_admin`, `user`, `name` |
| **Dona vazni (nomdan)** | `lib/core/utils/piece_weight.dart` | `pieceWeightFromName` — кг/л mahsulot nomidagi «1шт=200гр»/«(400гр)»/«150 гр» → гр/мл; yuk narxlashda «dona bilan» kiritish va dona narxi (birlik/qoldiq o'zgarmaydi) |
| **Birlik konverti** | `lib/core/utils/qty_units.dart` | `qtyFromUi` (kg/l → BUTUN gr/ml), `qtyToUi`/`formatQty`/`formatQtyUnit` (gr/ml → kg/l). Eski `qtyFromUiSafe` (1000+ = gramm himoyasi) majburiy update joriy bo'lgach OLIB TASHLANDI — 1000 kg endi 1000 kg |
| **Rollar** | `lib/core/constants/roles.dart` | `AppRoles` — role string konstantalari |
| **Media** | `lib/core/media/` | Ilova ICHIDA kamera/video: `InAppPhotoCamera`, `TelegramStyleVideoRecorder`, `VideoPreviewScreen` (`video_pervi`), `VideoProcessor`, `CircularNetworkVideoPlayer` |
| **Tarmoq rasmi** | `lib/core/widgets/app_network_image.dart` | ⚠️ YAGONA yo'l: `AppNetworkImage` (vidjet, `maxDecodeWidth` bilan) yoki `appNetworkImageProvider`/`appFileImageProvider` (CircleAvatar kabi `ImageProvider` kerak bo'lganda). `Image.network`/`NetworkImage`/`CachedNetworkImage` TO'G'RIDAN-TO'G'RI ishlatilmaydi — o'lchamsiz dekod = rasmiga ~4 MB RAM = OOM |
| **Rasm to'liq ekranda** | `lib/core/widgets/full_screen_image.dart` | `openFullScreenImage(context, url)` — ekran o'lchamida dekod qiladi, yopilganda rasmni keshdan chiqaradi (`evict`) |
| **«2 → 1.8» yorlig'i** | `lib/core/widgets/qty_claim_label.dart` | `qtyClaimLabel`/`hasQtyClaimDiff` — yuk kiritgan son (`item.claimed`) ombor tasdiqlagan sondan farq qilganda. YAGONA manba: yuk, ombor va bugalter ekranlari shuni ishlatadi |

---

## 4. Muhim (og'ir) ekranlar

| Ekran | Fayl | Nima uchun og'ir |
|---|---|---|
| Тех карта muharriri | `lib/admin/ui/tech_card_editor_page.dart` (~2200 qator) | Excel varag'iga 1:1 baza bloklari + расходник, jonli tannarx kataklari |
| Mahsulot qo'shish | `lib/admin/ui/admin_add_product_ui.dart` | тип, mone/bozor, tozalash yo'qotishi, полуфабрикат, tex karta |
| Mahsulot tahrirlash | `lib/admin/ui/admin_edit_product_ui.dart` | yuqoridagidek + rasm yuklash |
| Foyda nazorati | `lib/admin/ui/profit_control_ui.dart` | tannarx vs sotuv narxi, marja (`tech_card_cost.dart` bilan) |
| Foyda analitikasi | `lib/admin/ui/profit_analytics_ui.dart` (~1200 qator) | tortlar bo'yicha tushum/tannarx/foyda grafiklari (`GET /api/analytics/profit`) |
| Shef buyurtma | `lib/shef/ui/shef_create_order_ui.dart`, `shef_order_detail_ui.dart` | полуфабрикат limiti (`pf-availability`), bosqich qabul/rad |
| Ombor ishlab chiqarish | `lib/ombor/ui/ombor_production_ui.dart` | ishlab chiqarish oqimi |
| Ombor buyurtmalari | `lib/ombor/ui/ombor_orders_ui.dart` (~1500 qator) | YASSI (flat) lazy ro'yxat: kartochka ko'rinishi saqlangan, lekin har qator alohida `ListView` elementi; qator holati (son+media) faqat tahrirlanadigan qatorda; rasm thumbnail o'lchamida; qabul qilingan qator buyurtma to'liq yopilmaguncha DOUBLE-TAP bilan qayta tahrirlanadi. Fayl boshidagi izohni o'qi — bu qoidalar buzilsa ekran yana qotadi |
| Inventarizatsiya | `lib/production/ui/inventory_page.dart`, `inventory_history_page.dart` | акт инвентаризации, real sanash to'ri |
| Yuk bosh ekran | `lib/yuk/ui/yuk_home_ui.dart` (~2600 qator) | sklad buyurtmalari + targovli pul + kunlik hisob |
| POS (Konak) | `lib/admin/ui/pos_*_ui.dart` (`pos_hub`, `pos_menu`, `pos_orders`, `pos_sales`, `pos_recons`) | Konak POS integratsiyasi (menyu, avto-buyurtma, sotuv, recon) |

---

## 5. «Vazifa → qayerga qarash»

| Vazifa | Qayerga qarash |
|---|---|
| **Yangi endpoint ishlatish** | `lib/core/constants/urls.dart` (`AppUrls` ga URL qo'sh) + tegishli `*/services/*.dart` (Dio chaqiruvi) |
| **Yangi ekran qo'shish** | `*/ui/` (ekran) + `*/provider/` (holat) + agar global bo'lsa `lib/main.dart` provider ro'yxati; navigatsiya `context.push(...)` (`core/context_extension.dart`) |
| **gram/pul konvert** | `lib/core/utils/qty_units.dart` — hech qaerda qo'lda `*1000` yozma; `qtyFromUi`/`qtyToUi`/`formatQty` ishlat |
| **Pul KIRITISH maydoni** | `lib/core/utils/money_input.dart` — **YAGONA manba**: `ThousandsSeparatorInputFormatter` (yozayotganda har 3 xonadan probel: 200 000, kursor joyida qoladi), `formatMoneyInput` (model → matn), `parseMoney` (matn → butun so'm). Pul maydoniga `FilteringTextInputFormatter.digitsOnly` YOZMA. Ko'rsatish uchun esa `fmtCostMoney` (`production/ui/widgets/cost_sheet.dart`) |
| **Tannarx / marja matematikasi** | `lib/admin/model/tech_card_cost.dart` — **YAGONA manba** (`techIngredientPieceCost`, `techFullPieceCost`); yangi hisob shu yerga |
| **Narxni QO'LDA kiritish** | masalliq **xarid** narxi → `lib/production/ui/widgets/price_history_sheet.dart` (tex kartadagi «Цена» katagi ochadi) + `ProductProviderAdmin.setManualPrice` (`PUT /api/products/{id}/manual-price`, `manual_price` — BUTUN so'm, mahsulotning TO'LIQ birligi uchun). Mahsulot **sotish** narxi (`tech_card.sale_price`) → dialog + saqlash oqimi **YAGONA manba**: `admin/ui/widgets/sale_price_dialog.dart` (`showSalePriceDialog` / `editProductSalePrice`); uni «Foyda nazorati», «Foyda analitikasi» («Narx belgilanmagan» ro'yxati) va «POS menyu» chaqiradi. Tex karta muharririda esa o'z inline maydoni — `tech_card_editor_page.dart` → `_salePriceRow` |
| **Тех карта modeli** | `lib/admin/model/tech_card.dart` (struktura) + `admin/model/product_model.dart` (`techCard` maydoni) |
| **Real-time yangilanish** | `lib/core/network/order_socket.dart` (`OrderSocket.instance.events` / `transferEvents` / `productionEvents`) |
| **Token / auth / role saqlash** | `lib/core/data/local/token_storage.dart` + `SharedPreferences` (`token`/`role`/`is_admin`); interceptor `core/network/dio_settings.dart` |
| **Rolga yo'naltirish** | `lib/splash_screen.dart` va `lib/login_page.dart` (`_navigateByRole`) |
| **Admin mahsulot ro'yxati o'zgarishi** | `lib/admin/provider/admin_product_provider.dart` (`ProductProviderAdmin`) — xotirada create/update/delete, re-fetch YO'Q |
| **Rasm/video yuklash** | `lib/admin/provider/upload_image_provider.dart`, `admin/services/tech_image_upload_service.dart`, `core/media/*` |
| **Rasm KO'RSATISH (ro'yxat/avatar/to'liq ekran)** | `lib/core/widgets/app_network_image.dart` + `full_screen_image.dart` — 3-bo'limga qara. Ro'yxatdagi rasm har doim o'z katakchasi o'lchamida dekod qilinsin |
| **Filial limitlari** | `lib/admin/ui/filial_limits_ui.dart` + `admin/services/filial_limit_service.dart` (`GET/POST /api/filial-limits`) |
| **POS (Konak) integratsiya** | `lib/admin/ui/pos_*_ui.dart` + `admin/services/pos_*_service.dart` + `admin/model/pos_*_model.dart` |
| **Ostatka (SH5) — qoldiq, ruxsat, smena topshirish** | `lib/admin/ui/sh5_ostatka_ui.dart` (omborlar + tovarlar + «Yangilash»/«Topshirish»/«Qabul»), `sh5_handover_ui.dart` (sanoq ekrani — topshirish/qabul bitta vidjet), `sh5_handover_history_ui.dart` (tarix + farq detali) + `admin/services/sh5_service.dart` + `admin/model/sh5_remain_model.dart`, `sh5_handover_model.dart`. **Ruxsat:** `User.sh5Sklads` — admin `user_edit_dialog.dart` dagi «Ostatka (SH5) omborlari» chiplaridan beradi; sotuvchi bosh ekranidagi tugma `user/ui/user_home_ui.dart` da (ruxsat bo'lsagina chiqadi). Miqdorlar `*_milli` — BUTUN son, ko'rsatish `formatPortions` |
| **Sklad qoldig'i / korreksiya / inventar** | `lib/production/` — `StockProvider`, `stock_service.dart`, `stock_widgets.dart`, `inventory_page.dart` |
| **Sklad NOMLARI (tab/dropdown) va ro'yxati** | `lib/core/data/sklad_registry.dart` (`SkladRegistry`) — **YAGONA manba**, hardcode map YOZMA. Boshqaruv ekrani (admin qo'shadi/tahrirlaydi/o'chiradi): `admin/ui/sklads_ui.dart` + `admin/services/api_sklad_service.dart` (`/api/sklads`) |
| **Bugalter: soni/summa tuzatish va tarixi** | `lib/bugalter/ui/bugalter_home_ui.dart` (`_EditItemQtyDialog`) + `bugalter/services/bugalter_service.dart` (`editItemQty`, `fetchEdits`) + `bugalter/ui/bugalter_edits_ui.dart` |
| **Versiya tekshiruvi** | `lib/check_version.dart` (`VersionChecker`) |

---

## 6. Providerlar (global — `lib/main.dart` da ro'yxatlangan)

`MultiProvider` da ro'yxatlangan 13 + 4 (Ombor 2.0) ta global `ChangeNotifier`. Har biri nima ushlaydi:

| Provider | Fayl | Nima ushlaydi |
|---|---|---|
| `ProductProvider` | `user/provider/provider.dart` | seller katalogi + savat (cart) |
| `OmborProvider` | `ombor/provider/ombor_provider.dart` | bozor mahsulotlari, savat, ombor buyurtmalari, socket |
| `YukProvider` | `yuk/provider/yuk_provider.dart` | yuk keltiruvchi: buyurtmalar, ledger, transferlar, narx qoralamalari, offline kesh, oxirgi narxlar (`lastPrices` — `yuk/models/yuk_last_price_model.dart`, `/api/yuk/last-prices`) |
| `BugalterProvider` | `bugalter/provider/bugalter_provider.dart` | hisobchi: narxlangan buyurtmalar, yuk userlar, to'lovlar |
| `ShefProvider` | `shef/provider/shef_provider.dart` | shef: ishlab chiqarish buyurtmalari, mahsulotlar, bosqich holati |
| `OmborProductionProvider` | `production/provider/production_orders_provider.dart` | ombor ishlab chiqarish buyurtmalari |
| `AdminProductionProvider` | `production/provider/production_orders_provider.dart` | admin ishlab chiqarish buyurtmalari |
| `BugalterProductionProvider` | `production/provider/production_orders_provider.dart` | bugalter ishlab chiqarish buyurtmalari |
| `StockProvider` | `production/provider/stock_provider.dart` | sklad qoldig'i keshi, korreksiya, harakatlar tarixi, inventar |
| **`ProductProviderAdmin`** | `admin/provider/admin_product_provider.dart` | **admin mahsulotlarining YAGONA manbai** — bir marta yuklab, create/update/delete/reorder'ni xotirada bajaradi (re-fetch YO'Q) |
| `CategoryProviderAdmin` | `admin/provider/admin_categoriy_provider.dart` | admin kategoriyalari |
| `FilialProviderAdmin` | `admin/provider/admin_filial_provider.dart` | filiallar ro'yxati |
| `CategoryProviderAdminUpload` | `admin/provider/upload_image_provider.dart` | rasm/media yuklash holati |
| `CoreSession` | `core2/provider/core_session_provider.dart` | mone_core sessiyasi: `core_token`, user, hisoblangan `perms` to'plami (`has()`, `canCreate/canPost(type)`), ulanish holati, `retry()` |
| `CoreDictProvider` | `core2/provider/core_dict_provider.dart` | omborlar/kontragentlar/tovarlar/birliklar/guruhlar keshi; `skladById`/`corrById`/`goodById` O(1) |
| `CoreDocsProvider` | `core2/provider/core_docs_provider.dart` | hujjatlar ro'yxati (filtr, sahifalash) + create/update/post/cancel/delete/quick (natija xotirada `upsert`) |
| `CoreStockProvider` | `core2/provider/core_stock_provider.dart` | ombor bo'yicha qoldiq keshi, `rowFor(sklad, good)` O(1) indeks |

> Lokal (ekran ichida yaratiladigan) provider: `MagazinProvider`
> (`yuk/provider/magazin_provider.dart`) — magazin qarz daftari ekranlarida.

---

## 8. Ombor 2.0 — `lib/core2/` (mone_core `/api/v2`)

Shartnoma: `../mone_core/docs/API_V2.md`. Yadro alohida serverda (port 1020, manzil `ServerConfig.coreUrl`),
alohida token (`core_token`) — v1 `token` bilan ARALASHMAYDI. Login: v1 parol muvaffaqiyatli bo'lgach o'sha kod bilan
fonda `POST /auth/login {"code"}` (`CoreSession.loginWithCode`), keyin `GET /auth/me` → `perms` ro'yxati. Xato bo'lsa
ilova ishlayveradi, «Ombor 2.0» ekranlari `CoreConnectGate` orqali «server ulanmagan» + «Qayta urinish» ko'rsatadi.

| Qatlam | Fayl | Nima |
|---|---|---|
| model | `core2/models/core_user.dart` | `CoreUser`, `CoreMe` (user + perms), `CorePermDef`, **`CorePerms`** (kalit konstantalari) |
| model | `core2/models/core_dicts.dart` | `CoreSklad`, `CoreCorr`, `CoreUnit`, `CoreGoodGroup`, `CoreGood` (+`units[{unit,to_base}]`, `selectableUnits`, `preferredUnit`) |
| model | **`core2/models/core_qty.dart`** | **YAGONA konvert**: base (g/ml/pcs/m) ↔ UI (kg/l): `coreQtyFromUi(ui, unit)` (BUTUN base), `coreFormatQtyUnit`, `coreLineAmount` (butun so'm). Qo'lda `*1000` YOZMA |
| model | `core2/models/core_doc.dart` | `CoreDoc`, `CoreDocLine` (qty butun base, price/amount butun so'm, flag), `CoreDocType`/`CoreDocStatus`, `CoreDocWarning`, `CoreStockAfter`, `CoreDocPostResult` |
| model | `core2/models/core_stock.dart`, `core_recipe.dart`, `core_report.dart`, `core_integration.dart` | qoldiq/partiya/kartochka; retsept versiyalari; aylanma/defitsit; sotuv nuqtasi/API kalit/webhook/sync holati |
| service | `core2/services/core_client.dart` | **`CoreClient`** — alohida Dio (`core_token` interceptor), `url('/docs')` = `AppUrls.coreApi` + yo'l, `wrap()` → `CoreApiException` (error/code/perm), `idem()` Idempotency-Key |
| service | `core2/services/core_*_service.dart` | auth, dict, doc, stock(+reports), recipe, admin (perms/roles/users/sync), integration |
| provider | `core2/provider/*` | 7-bo'limdagi 4 ta global provider |
| ui | `core2/ui/core_hub_ui.dart` | «Ombor 2.0» grid — kartalar `perms` bo'yicha; ulanish holati; ⚙ server |
| ui | `core2/ui/docs_list_ui.dart`, `doc_form_ui.dart`, `doc_detail_ui.dart` | ro'yxat (filtr/qidiruv/sahifalash) → **universal forma** (tur bo'yicha maydonlar; production 2 jadval flag 1/0; inventory rejimi — joriy qoldiq + fakt, «faqat farqlilar», bo'sh yuborilmaydi; `DocFormUi.marketReceipt()` — bozorchi, supplier «РЫНОК», `/docs/quick`) → tafsilot (qatorlar, stock_after, warnings, tarix; Tasdiqlash/Bekor/O'chirish perms bo'yicha) |
| ui | `core2/ui/stock_ui.dart` | `StockUi` (ombor, qidiruv, manfiy qizil, cost faqat `stock.cost.view`) → `StockCardUi` (kartochka ledger + partiyalar tab) |
| ui | `core2/ui/dict_*_ui.dart`, `recipes_ui.dart`, `perms_ui.dart`, `integration_ui.dart`, `reports_ui.dart`, `sync_status_ui.dart` | lug'atlar (ombor qo'shish = 1 dialog), retsept versiyalari (+yangi versiya nusxa bilan), rollar×perms switch + foydalanuvchilar, sotuv nuqtalari/API kalit (bir marta ko'rsatiladi)/webhook, hisobotlar (3 tab), sinxron kartasi |
| ui (widget) | `core2/ui/widgets/core_widgets.dart`, `good_picker.dart`, `core_entry_menu.dart` | `CoreConnectGate`, chip/dropdown/xato/warnings dialog; tovar tanlash sheet (qoldiq bilan); oddiy user bosh ekranidagi kirish menyusi (user/ombor/shef home AppBar) |

Kirish nuqtalari: admin menyu «Ombor 2.0» (`admin_home_ui.dart`), user/ombor/shef AppBar `CoreEntryMenu`
(Hujjatlar / Qoldiq / Bozor приход / hub). Logout (`core/auth/session.dart`) core providerlarni ham tozalaydi.
