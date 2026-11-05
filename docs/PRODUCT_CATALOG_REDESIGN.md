# Mone mahsulot katalogi: sodda foydalanish va rivojlantirish rejasi

Sana: 2026-10-19. Tekshiruv: lokal Flutter va Go kodi, r_keeper / StoreHouse rasmiy hujjatlari.
Jonli bazadagi mahsulotlar va foydalanuvchi ish jarayoni tekshirilmadi.

## 1. Qaror

Mone uchun eng mos yo'l: **bitta mahsulot kartasi + alohida retsept + mustaqil sotuv va xarid sozlamalari**.

r_keeper yoki SH5'ni to'liq ko'chirish shart emas. Ularning mas'uliyatlarni ajratish tamoyili foydali:

- Mahsulot: «Bu nima va qaysi birlikda hisoblanadi?»
- Retsept: «Nimadan, qancha va qanday tayyorlanadi?»
- Sotuv: «Kim buyurtma bera oladi va bir bosishda qancha qo'shiladi?»
- Xarid: «Qayerdan keladi, qaysi ombor buyurtma beradi?»
- Qoldiq: «Hujjatlar bo'yicha hozir qancha bor?»
- Integratsiya: «Tashqi tizimdagi qaysi yozuvga mos?»

Foydalanuvchiga bitta tushunarli karta ko'rinadi. Har bir ma'lumotning vazifasi aniq bo'ladi.
Bu universal «eng yaxshi ERP» da'vosi emas, Mone'ning mavjud tuzilmasiga mos muhandislik qarori.

## 2. Hozir aslida nima bor?

Oldingi `REJA_NOMENKLATURA.md` 2026-10-12 dagi ishni tasvirlaydi. Uni yangi audit deb qabul qilmaslik kerak.

| Qism | Kodda tekshirilgan holat | Qaror |
|---|---|---|
| Asosiy katalog | `core/catalog/product.dart`: bitta `Product`, `raw/pf/product` | Saqlaymiz |
| Katalog yuklash | `CatalogRepository`, `GET /api/products`, `include=recipe` | Yangi takroriy katalog yaratmaymiz |
| Retsept | `TechCard`, ichida `RecipeSpec`, `RecipePricing`, `RecipeVisual` | Bor tuzilmani ishlatamiz; barcha ajratish tugagan deb hisoblamaymiz |
| Go modeli | `models.go` Product, eski JSON nomlari | API nomlarini hozir almashtirmaymiz |
| Forma | Avval add 795, edit 906 qator, deyarli bir xil qoidalar | Bitta `ProductFormPage`ga birlashtirildi |
| Tarkib | Mijozga ko'rinadigan matn va texnologik retsept boshqa-boshqa ma'lumot | Formada farqi tushuntirildi |
| Miqdor | kg/l uchun butun g/ml; qolgan birliklar uchun mavjud kontrakt | Qadamni saqlashdan oldin aniq tekshirish qo'shildi |
| SH5/RK bog'lash | Backendda tashqi mahsulot/retsept ID bog'lanishlari mavjud | Tashqi tizim chegarasida qoldiriladi |
| `core2` | Alohida `CoreGood`, birlik koeffitsiyentlari, sanali `CoreRecipeVersion` bor | Ularni oddiy takroriy Product deb o'chirish mumkin emas |
| Ishlab chiqarish | Buyurtma ingredient/bosqich modellari tarixiy nusxani ifodalaydi | Katalog modeliga zo'rlab birlashtirilmaydi |

Muhim tuzatish: ombor papkasidagi `ombor_product_model.dart` hozir `OmborCategory`ni saqlaydi.
Fayl nomidagi «product» sababli uni yana bir faol Product modeli deb sanash xato.

## 3. r_keeper va SH5 taqqoslash

| Yondashuv | Kuchli tomoni | Mone uchun qanday olamiz? |
|---|---|---|
| r_keeper menyusi | Sotuv pozitsiyasi, guruhlar, narx turlari, modifikatorlar | Sotuv ko'rinishi mahsulotning barcha ombor maydonlarini ko'rsatmasin |
| StoreHouse tovar kartasi | Hisob birligi, bir nechta qadoq/birlik va koeffitsiyent, komplektga bog'lanish | Mahsulotning identifikatsiyasi va retseptini farqlaymiz |
| StoreHouse komplekti | Retsept tarkibi, versiya/davr bilan ishlash | Tarixni qayta hisoblatmaydigan retsept versiyalashiga yo'nalish |
| RK → SH import | Tashqi kataloglarni bog'lash | Tashqi IDlar integratsiya qatlamida qoladi; ichki ID nomdan hisoblanmaydi |

SH5 kuchsiz degan xulosa yo'q: undagi ko'p sozlama katta ombor va restoran tarmoqlariga kerak.
Mone foydalanuvchisiga esa har bir mahsulotda barcha sozlamalarni birdan ko'rsatish shart emas.

«Hamma katta tizimlarda bir xil kind enum bor», «SH5 versiya bilmaydi» yoki
«bitta katalog qilsak tashqi mapping yo'qoladi» degan xulosalar chiqarilmaydi.
Ichki katalog birlashsa ham RK/SH kabi mustaqil tizimlar bilan tashqi bog'lash qoladi.

Rasmiy manbalar (2026-10-19 kuni qidiruv orqali tekshirildi; `/sh5` hujjatlarining ayrimlari hozir StoreHouse Pro nomida):

1. [r_keeper: menyu ma'lumotnomasi](https://docs.rkeeper.ru/rk7/7.7.0/ru/spravochnik-menyu-4037802.html)
2. [StoreHouse: tovar kartasi va birliklar](https://docs.rkeeper.ru/sh5/zapolnenie-kartochki-tovara-9799444.html)
3. [StoreHouse: GoodsItem API, komplekt va davrlar](https://docs.rkeeper.ru/sh5/api/protsedury-servera/slovari/tovary/goodsitem-tovar)
4. [StoreHouse: komplektlar versiya/davrlari](https://docs.rkeeper.ru/sh5/komandy-kontekstnogo-menyu-spiska-komplektov-10814438.html)
5. [StoreHouse: r_keeper'dan import qilingan tovarlar](https://docs.rkeeper.ru/sh5/tovary-importirovannye-iz-r_keeper-9799475.html)
6. [StoreHouse 5 qo'llanmasi, PDF](https://docs.rkeeper.ru/sh5/files/19602461/19602595/20/1663334293462/storehouse_v5_user_manual.pdf)

## 4. Foydalanuvchi uchun mahsulotlarning sodda tushunchasi

Yangi mahsulot ochishda to'rtta **boshlang'ich andoza**:

| Foydalanuvchi tanlovi | Misol | Saqlanadigan kind | Sotuv | Xarid |
|---|---|---|---|---|
| Xomashyo | Un, shakar, qadoq | raw | O'chiq | Yoqiq |
| Tayyor olib sotamiz | Coca-Cola, qadoqlangan shokolad | raw | Yoqiq | Yoqiq |
| Yarim tayyor mahsulot | Krem, biskvit | pf | O'chiq | O'chiq |
| O'zimiz tayyorlaymiz | Tort, pirojnoe | product | Yoqiq | O'chiq |

Bu jadval boshlang'ich qiymatlar. `raw` va `product` uchun sotuv/xarid alohida o'zgartiriladi.
Masalan, o'zimiz qiladigan nonni ba'zida yetkazib beruvchidan ham olsak, xaridni yoqish mumkin.

`pf` uchun sotuv/xarid cheklovi hozirgi backend qoidasi. Sotiladigan yoki tashqaridan
olinadigan yarim tayyor mahsulotni qo'llash alohida domen o'zgarishi bo'ladi;
uni faqat UI switchini ochish bilan hal qilib bo'lmaydi.

Andoza yangi DB turi emas. Shu sababli Coca-Cola uchun yangi tur migratsiyasi kerak emas:
`raw + sellable + purchasable` yetarli. Tahrirlashda mavjud maxsus kanal kombinatsiyalari
avtomatik andozaga almashtirilmaydi.

## 5. Yangi mahsulot kartasi

1. **Asosiy ma'lumot:** andoza/tur, nom, kategoriya, o'lchov birligi.
2. **Sotuv:** ko'rinish switchi, buyurtma qadami, filiallar. Switch o'chiq bo'lsa tafsilotlar yashiriladi.
3. **Xarid:** xarid switchi, qadam, yuk manbalari, buyurtma beradigan omborlar.
4. **Retsept:** mavjud/yo'q holati va «Saqlab, retseptni ochish» tugmasi.
5. **Qo'shimcha ma'lumot:** yig'iladigan bo'lim — brend, mijozga ko'rinadigan tarkib, yo'qotish, dona og'irligi, rasm.

Saqlash tugmasi ekran pastida turadi. PF kartasida sotuv/xarid bo'limlari ko'rsatilmaydi.
Kategoriya ichidan qo'shilsa, shu kategoriya oldindan tanlanadi.

Ro'yxatda tur va yoqilgan kanallar ko'rinadi. Retsept yo'q bo'lsa ham uni qo'shish tugmasi bor:
foydalanuvchi yashirin double-tap ishorasini bilishi shart emas.

### Uchta amaliy misol

**Un:** Xomashyo → nom → kategoriya → kg → Xarid: 25 kg → manba va ombor → saqlash.
Tarkib matni, filial va retsept talab qilinmaydi.

**Coca-Cola:** Tayyor olib sotamiz → dona → sotuv filiali → xarid ombori → saqlash.
Mahsulot ishlab chiqarish retsepti talab qilinmaydi.

**Krem:** Yarim tayyor mahsulot → birlik → saqlab retseptni ochish → masalliqlarni tanlash.
Sotuv/xarid sozlamalari chalg'itmaydi.

## 6. Dasturchi uchun mas'uliyatlar

```text
Product                        saqlangan yagona katalog yozuvi
  id / name / category / unit   mahsulotning o'zi
  kind                         ishlab chiqarishdagi roli
  sellable / filials / step     sotuv sozlamasi
  purchasable / sklads / step   xarid sozlamasi
  sources                      yuk manbalari
  techCard                     mavjud retsept obyektiga aloqa

ProductFormDraft               faqat ekrandagi tahrir holati va tekshiruv
ProductTemplate                faqat yangi forma uchun boshlang'ich qiymatlar
ProductFormPage                qo'shish va tahrirlashning umumiy ko'rinishi
ProductProviderAdmin           serverga saqlash, repositoryni yangilash
CatalogRepository              katalogni o'qish va ID bo'yicha olish
```

`ProductFormDraft` ikkinchi katalog emas: JSON modeli yoki keshga yoziladigan nusxa emas.
Retseptni formani ochib-yopishda controller orqali qayta qurish olib tashlandi.
Oddiy karta saqlanishida mavjud `TechCard` saqlanadi; qo'lda xarid narxi o'z endpointida qoladi.

Birliklar ro'yxati va ko'rsatish nomlari `core/catalog/product_unit.dart`ga ko'chirildi.
Eski tex karta widget importlari uchun qayta eksport bor. `type` JSON kaliti hali birlikni bildiradi.

## 7. Hozir joriy qilingan ishlar

- [x] Add/edit formalarini bitta sahifaga birlashtirish.
- [x] To'rtta tushunarli boshlang'ich andoza.
- [x] Tur bilan kanalni ajratish, mavjud kombinatsiyalarni tahrirlashda saqlash.
- [x] Majburiy bo'lmagan tarkib matnini majburiy tekshiruvdan chiqarish.
- [x] Qo'shimcha sozlamalarni yig'iladigan bo'limga olish.
- [x] Miqdorda vergulni qabul qilish; manfiy, nol, NaN, cheksiz va aniqlikdan kichik qiymatni rad etish.
- [x] Noto'g'ri yo'qotishni nolga almashtirish o'rniga xatoni ko'rsatish.
- [x] Suyuqlikdagi yo'qotishga ml deb yozish.
- [x] Nol/default qadamni oddiy tahrirlashda sun'iy ravishda 1 ga aylantirmaslik.
- [x] Saqlash davomida takroriy bosishni to'sish va server xatosini ko'rsatish.
- [x] Saqlangan yangi ID bilan retsept muharririga o'tish.
- [x] Kategoriya ichidan qo'shishda kategoriyani oldindan tanlash.
- [x] Mahsulot ro'yxatida aniq retsept tugmasi, tur va kanal izohlari.
- [x] Model va telefon ekranidagi xatti-harakatlar uchun regressiya testlari.

Bu ishlar lokal kodda. Server migratsiyasi, deploy yoki APK tarqatish amalga oshirilmagan.

## 8. Keyingi arxitektura bosqichlari — hozir bajarilgan deb hisoblanmaydi

### A. Asosiy va core2 katalog chegarasini aniq belgilash

Avval `Product.id` va `CoreGood.id` qaysi operatsiyalarda ishlatilishini xaritalash.
`CoreGood`da allaqachon `base_unit` va qo'shimcha birliklar bor; ularni yana ixtiro qilmaslik.
Qaysi servis hisobning egasi bo'lishi deployment va haqiqiy ma'lumot bilan tasdiqlanishi kerak.

Natija: har bir operatsiya uchun aniq egasi va ID bog'lanishi. Bir xil raqamli IDlarni
avtomatik bir mahsulot deb qabul qilmaslik. Nom bo'yicha taxminiy bog'lashni foydalanuvchi ko'rib chiqadi.

### B. Retseptni mahsulotdan mustaqil saqlash va tahrirlash

`TechCard`ning retsept, narx va ko'rinish qismlari hozir kodda guruhlangan,
lekin mahsulotni to'liq PUT qilish hali barcha sohalarga ta'sir qilishi mumkin.

Maqsad: retsept uchun alohida yozish kontrakti, versiya/revision nazorati,
konfliktda tushunarli xato. Narx va tashqi ko'rinish tahriri retsept versiyasini asossiz oshirmasin.
`CoreRecipeVersion`dagi sanali model bilan moslashuv tekshirilsin.

Qabul mezoni: ikki foydalanuvchi bir payt tahrirlasa, birining retsepti ikkinchisining
mahsulot nomi tahriri bilan yo'qolmasin. Eski ishlab chiqarish hujjati o'z retsept nusxasini ishlatsin.

### C. Haqiqiy qadoqlar va birlik konvertatsiyasi

Hozir `buy_step=25000` — kg mahsulot uchun «+25 kg» degani. U `1 qop = 25 kg`
degan mustaqil qadoq yozuvi emas. `piece_weight_g` ham umumiy qadoq jadvali o'rnini bosa olmaydi.

Kerakli keyingi ko'rinish: bitta mahsulot, asosiy birlik, bir nechta qadoq va aniq koeffitsiyent.
Masalan, un: g hisob birligi; kg=1000 g; qop=25000 g. Sotuv qadami bundan mustaqil.

Qabul mezoni: 2 qop kirim, 3 kg sarf → 47 kg qoldiq. Turli hajmdagi qadoq uchun
bir xil unni ikki katalog yozuvi qilib ochish talab qilinmasin.

### D. Faollik va arxivlash

Mahsulot qoldig'i, hujjati yoki retseptdagi ishlatilishi bo'lsa, o'chirish o'rniga arxivlash.
Qaysi joylarda ishlatilayotgani ID orqali ko'rsatilsin. Tarixiy hujjatlar nom va birlik nusxasini saqlasin.

Qabul mezoni: arxivlangan mahsulot yangi buyurtmada tanlanmaydi, eski hujjatda ochiladi.

### E. Katalog sifati va katta ro'yxat

Tur, sotuv, xarid, retsept yo'qligi bo'yicha qidiruv/filtr; bog'lanmagan masalliqlar hisoboti.
Dublikatlar ro'yxati tavsiya sifatida chiqadi. Birlashtirishda retsept, qoldiq, narx tarixi va tashqi IDlar
bir transaction/migratsiya rejasida hisobga olinadi; nom tengligi birlashtirish uchun yetarli emas.

Qabul mezoni: filtr va tartiblash bir-biriga xalaqit bermaydi; katta katalogda serverdan retseptlar
hamisha to'liq qayta yuklanmaydi. Qidiruv natijasi ichida reorder qilish umumiy tartibni buzmasin.

## 9. Ish tartibi va o'tish shartlari

| Bosqich | Kirish sharti | Natija |
|---|---|---|
| Joriy UI soddalashtirish | Mavjud API | Shu o'zgarishdagi yagona forma va testlar |
| A — hisob egasi | Core2 deployment va ID moslik auditi | Tasdiqlangan ma'lumot oqimi |
| B — retsept kontrakti | A qarori, eski klientlar ro'yxati | Versiyali yozish va tarix sinovlari |
| C — qadoqlar | Birlik va hisob egasi aniq | Konvertatsiya + kirim/sarf testlari |
| D — arxiv | Bog'liqliklar ro'yxati | Eski hujjatlar saqlangan holda faollik boshqaruvi |
| E — katalog sifati | A–D kontraktlari | Filtr, xato hisoboti, boshqariladigan tozalash |

Jonli ma'lumotni o'zgartiradigan bosqichlarda: o'qish auditi → zaxira → dry-run hisoboti →
staging → nazoratli migratsiya → hisobotlarni oldin/keyin solishtirish.
Hozirgi UI o'zgarishi uchun yangi DB migratsiyasi kerak emas.

## 10. Tekshiruv mezonlari

- Nomi bo'sh mahsulot yoki noto'g'ri miqdor serverga yuborilmasin.
- Faqat yoqilgan kanal uchun filial/ombor/manba talab qilinsin.
- `0,5 kg` → 500 g; `0.001 l` → 1 ml; yarim dona qadam rad etilsin.
- Noto'g'ri yo'qotish saqlanmasin va avvalgi qiymat indamay o'chmasin.
- Oddiy mahsulot tahriri retsept va qo'lda narx sanasini o'zgartirmasin.
- Server xatosida foydalanuvchi kiritgan ma'lumot qolib, qayta saqlay olsin.
- Yangi mahsulotni saqlab retseptga o'tishda server bergan ID ishlatilsin.
- 360 px telefonda overflow bo'lmasin; saqlash vaqtida ikki so'rov ketmasin.
- Mavjud shef/retsept ekranlari va birlik tanlovi ishlashda davom etsin.
