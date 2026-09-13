// yuk/ui/yuk_home_ui.dart — yuk keltiruvchi roli BOSH ekrani: YukHomeUi + sklad kartasi
// YukSkladCard (buyurtmaga narx kiritish, proche/rasxod qo'shish, rasm/video, yuborish/undo),
// targovli pul kartasi _TransferCard, _NameAutocompleteField, raqam formatterlari
// (ThousandsSeparator/Decimal). YukProvider'ga tayanadi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/media/in_app_photo_camera.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/utils/order_sequence.dart';
import 'package:uz_ai_dev/core/utils/piece_weight.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/core/widgets/full_screen_image.dart';
import 'package:uz_ai_dev/core/widgets/qty_claim_label.dart';
import 'package:uz_ai_dev/admin/ui/widgets/product_type_radio.dart'
    show kProductTypeOptions;
import 'package:uz_ai_dev/yuk/models/proche_name_model.dart';
import 'package:uz_ai_dev/yuk/models/yuk_last_price_model.dart';
import 'package:uz_ai_dev/yuk/models/yuk_order_model.dart';
import 'package:uz_ai_dev/yuk/models/yuk_transfer_model.dart';
import 'package:uz_ai_dev/yuk/provider/yuk_provider.dart';
import 'package:uz_ai_dev/core/data/sklad_registry.dart';
import 'package:uz_ai_dev/yuk/services/yuk_service.dart';
import 'package:uz_ai_dev/yuk/ui/yuk_history_ui.dart';
import 'package:uz_ai_dev/yuk/ui/yuk_magazin_ui.dart';
import 'package:uz_ai_dev/yuk/ui/yuk_profile_ui.dart';
import 'package:uz_ai_dev/yuk/ui/yuk_transfer_history_ui.dart';

// Sklad nomlari — YAGONA manba SkladRegistry (superadmin serverda tahrirlaydi).
Map<int, String> get kSkladNames => SkladRegistry.names;

// kg bilan o'lchanadigan mahsulotlar uchun: raqamlar va bitta o'nlik
// ajratuvchi (nuqta yoki vergul) ga ruxsat. Masalan "8.500", "8,5".
class DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Faqat raqamlar va eng ko'pi bilan bitta nuqta/vergul.
    if (!RegExp(r'^[0-9]*[.,]?[0-9]*$').hasMatch(text)) {
      return oldValue;
    }
    return newValue;
  }
}

// Yuk keltiruvchi roli uchun bosh ekran.
// Foydalanuvchiga biriktirilgan skladlar bo'yicha tablar; har tabда
// o'sha skladning buyurtmalari (FAQAT ko'rish).
class YukHomeUi extends StatefulWidget {
  const YukHomeUi({super.key});

  @override
  State<YukHomeUi> createState() => _YukHomeUiState();
}

class _YukHomeUiState extends State<YukHomeUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

  List<int> _sklads = [];
  bool _loadingSklads = true;

  // AppBar sarlavhasi — kirgan foydalanuvchining ismi (SharedPreferences'dagi
  // 'name', bo'lmasa 'user' JSON ichidagi name). Bo'sh bo'lsa rol nomi qoladi.
  String _userName = '';

  // AppBar'dagi tugma bilan boshqariladi: bosilsa mahsulot katalog rasmlari
  // ro'yxatda ko'rinadi, yana bosilsa yashiriladi.
  bool _showImages = false;

  // dispose() ichida context.read() xavfsiz emas (widget deaktiv bo'lishi mumkin),
  // shuning uchun provider referensini didChangeDependencies'da saqlaymiz.
  YukProvider? _yukProvider;

  @override
  void initState() {
    super.initState();
    _loadSklads();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<YukProvider>();
      // Avval lokal qoralamalarni tiklaymiz (internet o'chiq bo'lsa ham
      // kiritilgan narxlar yo'qolmasin), keyin serverdan ro'yxatni olamiz.
      await provider.loadDrafts();
      await provider.fetchOrders();
      // Targovli tizimidan kelgan (qabul kutayotgan) pullar.
      await provider.fetchTransfers();
      // Real-time: narxlash/buyurtma o'zgarishlari refresh'siz ko'rinishi uchun.
      provider.connectSocket();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _yukProvider = context.read<YukProvider>();
  }

  @override
  void dispose() {
    // Ekrandan chiqishda real-time ulanishni uzamiz (saqlangan referens orqali).
    _yukProvider?.disconnectSocket();
    super.dispose();
  }

  // SharedPreferences'dagi 'user' JSON ichidan `sklads` ro'yxatini va
  // foydalanuvchi ismini (AppBar sarlavhasi uchun) o'qish.
  Future<void> _loadSklads() async {
    final prefs = await SharedPreferences.getInstance();
    final userStr = prefs.getString('user');
    final sklads = <int>[];
    var name = (prefs.getString('name') ?? '').trim();
    if (userStr != null && userStr.isNotEmpty) {
      try {
        final user = jsonDecode(userStr);
        if (user is Map && user['sklads'] is List) {
          for (final s in user['sklads']) {
            if (s is int) {
              sklads.add(s);
            } else if (s is num) {
              sklads.add(s.toInt());
            } else {
              final parsed = int.tryParse(s.toString());
              if (parsed != null) sklads.add(parsed);
            }
          }
        }
        // 'name' kaliti bo'sh bo'lsa (eski login) user JSON'dan olamiz.
        if (name.isEmpty && user is Map) {
          name = (user['name'] ?? '').toString().trim();
        }
      } catch (_) {
        // noto'g'ri JSON bo'lsa bo'sh ro'yxat bilan davom etamiz
      }
    }
    if (!mounted) return;
    setState(() {
      _sklads = sklads;
      _userName = name;
      _loadingSklads = false;
    });
  }

  void _logout() {
    logoutAndClear(context);
  }

  String _skladName(int id) => kSkladNames[id] ?? 'Sklad $id';

  @override
  Widget build(BuildContext context) {
    if (_loadingSklads) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    // Foydalanuvchida sklad bo'lmasa.
    if (_sklads.isEmpty) {
      return Scaffold(
        backgroundColor: _bgColor,
        appBar: _buildAppBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sizga hech qanday sklad biriktirilmagan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: _sklads.length,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: _buildAppBar(
          bottom: TabBar(
            isScrollable: _sklads.length > 2,
            labelColor: _accentColor,
            unselectedLabelColor: Colors.black54,
            indicatorColor: _accentColor,
            tabs: _sklads.map((id) => Tab(text: _skladName(id))).toList(),
          ),
        ),
        // Bo'sh joyga (maydonlardan tashqari) bosilsa klaviatura yopiladi.
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Consumer<YukProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Center(
                    child: CircularProgressIndicator.adaptive());
              }

              if (provider.errorMessage != null) {
                return _ErrorView(
                  message: provider.errorMessage!,
                  onRetry: () => provider.fetchOrders(),
                );
              }

              return Column(
                children: [
                  // Internet yo'q paytda ko'rsatiladigan eslatma. Ro'yxat oxirgi
                  // saqlangan keshdan, kiritilgan narxlar lokal saqlanadi.
                  if (provider.isOffline) const _OfflineBanner(),
                  // Targovli tizimidan kelgan, qabul kutayotgan pullar —
                  // barcha sklad tablarining tepasida ko'rinadi.
                  for (final t in provider.transfers)
                    _TransferCard(
                      key: ValueKey('transfer_${t.id}'),
                      transfer: t,
                    ),
                  Expanded(
                    child: TabBarView(
                      children: _sklads.map((id) {
                        // Asosiy sahifada faqat hali yuborilmagan buyurtmalar
                        // (yuborilganlar AppBar'dagi tarix ekranida).
                        final orders = provider.pendingForSklad(id);
                        return RefreshIndicator(
                          onRefresh: () async {
                            await provider.fetchOrders();
                            await provider.fetchTransfers();
                          },
                          child: orders.isEmpty
                              ? ListView(
                                  children: const [
                                    SizedBox(height: 120),
                                    Center(
                                      child: Text(
                                        'Buyurtmalar yo\'q',
                                        style: TextStyle(color: Colors.black54),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  children: [
                                    // Skladning HAMMA yuborilmagan buyurtmalari
                                    // bitta jamlangan kunlik ro'yxat (buyurtma
                                    // IDlarisiz), pastda bitta "Yuborish".
                                    YukSkladCard(
                                      key: ValueKey('sklad_$id'),
                                      skladId: id,
                                      orders: orders,
                                      showImages: _showImages,
                                    ),
                                  ],
                                ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar({PreferredSizeWidget? bottom}) {
    return AppBar(
      backgroundColor: _bgColor,
      elevation: 0,
      // Sarlavha — foydalanuvchining o'z ismi (ism topilmasa rol nomi).
      title: Text(
        _userName.isNotEmpty ? _userName : 'Yuk keltiruvchi',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      actions: [
        // Mahsulot katalog rasmlarini ko'rsatish/yashirish (toggle).
        IconButton(
          onPressed: () => setState(() => _showImages = !_showImages),
          icon: Icon(
            _showImages ? Icons.hide_image_outlined : Icons.image_outlined,
            color: _showImages ? _accentColor : null,
          ),
          tooltip:
              _showImages ? 'Rasmlarni yashirish' : 'Rasmlarni ko\'rsatish',
        ),
        // Qarz daftari: bozorchi qaysi magazinchilarga qarzdorligini yuritadi.
        IconButton(
          onPressed: () => context.push(const YukMagazinUi()),
          icon: const Icon(Icons.storefront_outlined),
          tooltip: 'Qarz daftari',
        ),
        // Targovli'dan kelgan pullar tarixi (qabul qilingan/rad etilgan/
        // kutilayotgan — jami summalar bilan).
        IconButton(
          onPressed: () => context.push(const YukTransferHistoryUi()),
          icon: const Icon(Icons.account_balance_wallet_outlined),
          tooltip: 'Pullar tarixi',
        ),
        // Yuborilgan buyurtmalar tarixi.
        IconButton(
          onPressed: () => context.push(YukHistoryUi(sklads: _sklads)),
          icon: const Icon(Icons.history),
          tooltip: 'Yuborilganlar tarixi',
        ),
        IconButton(
          onPressed: () => context.push(const YukProfileUi()),
          icon: const Icon(Icons.person_outline),
          tooltip: 'Profil',
        ),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
        ),
      ],
      bottom: bottom,
    );
  }
}

// Internet yo'q paytdagi yupqa eslatma chizig'i.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF3E0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 16, color: Color(0xFFB26A00)),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Internet yo\'q — narxlar telefonда saqlanmoqda, ulanish '
              'tiklanganda yuboriladi',
              style: TextStyle(fontSize: 12, color: Color(0xFFB26A00)),
            ),
          ),
        ],
      ),
    );
  }
}

// Targovli tizimidan kelgan, qabul kutayotgan bitta pul kartasi.
// «Qabul qilish» — summa kunlik hisob daftariga (Prixod) tushadi va targovli
// tomonga "qabul qilindi" qaytariladi. «Rad etish» — sabab yoziladi (majburiy),
// kassir uni ko'rib qayta yuborishi mumkin.
class _TransferCard extends StatelessWidget {
  final YukTransfer transfer;
  const _TransferCard({super.key, required this.transfer});

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rad etish'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Sabab (majburiy)',
            hintText: 'Nima uchun rad etyapsiz?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rad etish', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rad etish uchun sabab yozing'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await _decide(context, accept: false, reason: reason);
  }

  Future<void> _decide(
    BuildContext context, {
    required bool accept,
    String reason = '',
  }) async {
    final provider = context.read<YukProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.decideTransfer(
        transfer.id,
        accept: accept,
        reason: reason,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(accept
              ? 'Pul qabul qilindi ✓ (hisobingizga tushdi)'
              : 'Pul rad etildi'),
          backgroundColor: accept ? Colors.green.shade700 : Colors.orange,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deciding =
        context.watch<YukProvider>().decidingTransferId == transfer.id;
    final dateStr = transfer.created == null
        ? ''
        : DateFormat('dd.MM.yyyy HH:mm').format(transfer.created!.toLocal());
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: const Color(0xFFFFFDE7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: Colors.amber.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    transfer.isOnline
                        ? 'Onlayn to\'lov (Targovli)'
                        : 'Sizga pul yuborildi (Targovli)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (dateStr.isNotEmpty)
                  Text(
                    dateStr,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatMoney(transfer.amount)} so\'m',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (transfer.senderName.isNotEmpty)
              Text(
                'Yubordi: ${transfer.senderName}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (transfer.comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  transfer.comment,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            // Chek rasmi (targovli «Онлайн» to'lovi) — bosilsa to'liq ekran.
            if (transfer.hasImage)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TransferReceiptImage(url: transfer.imageFullUrl),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                    ),
                    onPressed:
                        deciding ? null : () => _decide(context, accept: true),
                    icon: deciding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Qabul qilish'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    onPressed: deciding ? null : () => _reject(context),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Rad etish'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  static const Color _accentColor = Color(0xFFC5A97B);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }
}

// Katalog rasmi TO'LIQ EKRANDA — endi umumiy `FullScreenImagePage`
// (core/widgets/full_screen_image.dart): rasm ekran o'lchamida dekod qilinadi
// va chiqishda keshdan chiqariladi.

// Summalarni chiroyli ko'rsatish: 1000 -> "1 000".
String _formatMoney(num v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

// ═══════════ Sklad bo'yicha JAMLANGAN kunlik ro'yxat (achot) ═══════════
// Asosiy sahifada buyurtma IDlari ko'rsatilmaydi: skladning hamma
// yuborilmagan buyurtmalari bitta ro'yxat bo'lib chiqadi. Bir sklad 2 marta
// buyurtma bersa itemlari ALOHIDA qator bo'lib qo'shiladi (jamlanmaydi) —
// orasida kichik vaqt chizig'i turadi. Yuk kun davomida miqdor/summa yozib
// boradi, kechqurun BITTA "Yuborish" bilan hammasi yopiladi (achot yopiladi).
// Ichkarida har buyurtma backendda alohida saqlanadi — ombor qabuli, kamomad
// va ledger hisoblari o'zgarmaydi.
class YukSkladCard extends StatefulWidget {
  final int skladId;
  final List<YukOrder> orders;
  // AppBar'dagi tugma holati: true bo'lsa mahsulot katalog rasmlari ko'rinadi.
  final bool showImages;
  const YukSkladCard({
    super.key,
    required this.skladId,
    required this.orders,
    this.showImages = false,
  });

  @override
  State<YukSkladCard> createState() => _YukSkladCardState();
}

class _YukSkladCardState extends State<YukSkladCard> {
  static const Color _accentColor = Color(0xFFC5A97B);

  // Jadval ustunlari uchun nisbatlar — sarlavha va qatorlar bir xil ishlatadi.
  static const int _nameFlex = 5;
  static const int _qtyFlex = 3;
  static const int _sumFlex = 3;

  // Controllerlar buyurtma+mahsulot juftligi bo'yicha ('<orderId>_<productId>')
  // — bir xil mahsulot ikki buyurtmada kelsa qatorlar aralashmaydi.
  // Yuk keltiruvchi Soni ustunini ham, Jami summani ham o'zi kiritadi. Soni
  // maydoni faqat ombor itemni QABUL QILGANDA qulflanadi (o'shanda omborchi
  // kiritgan haqiqiy kelgan son yakuniy hisoblanadi).
  final Map<String, TextEditingController> _takenControllers = {};
  final Map<String, TextEditingController> _subtotalControllers = {};
  // Maydon fokusda turganda socketdan kelgan qiymat uni bosib qo'ymasligi
  // uchun ikkala ustunga ham FocusNode kerak.
  final Map<String, FocusNode> _takenFocusNodes = {};
  final Map<String, FocusNode> _subtotalFocusNodes = {};

  // Boshlang'ich qiymatlari tayyorlangan buyurtmalar (socket orqali yangi
  // buyurtma kelsa didUpdateWidget'da faqat yangilari init bo'ladi).
  final Set<int> _initedOrders = {};

  final ImagePicker _picker = ImagePicker();
  final YukService _service = YukService();
  Timer? _undoTicker;

  // Bosilgan rasm alohida ekranda emas, ro'yxat ostida ochiladi. Ochiq
  // turgan rasm shu yerda saqlanadi (yana bosilsa yopiladi, null bo'ladi).
  String? _expandedAttachment;

  // Mahsulot katalog rasmlari (product_id -> relativ /static/... url). Endi
  // alohida "Mahsulot suratlari" ekrani o'rniga har mahsulot nomi ostida shu
  // ro'yxatda ko'rinadi. Bosilgan rasm TO'LIQ EKRANDA ochiladi (ustiga bir
  // marta bosilsa yopiladi).
  Map<int, String> _catalogImages = {};

  String _key(int orderId, int productId) => '${orderId}_$productId';

  static bool _isDoneOrder(YukOrder o) =>
      o.status == 'narxlandi' || o.status == 'qabul_qilindi';

  // Pul hisobiga asos bo'ladigan son (ustuvorlik tartibi):
  //  1) ombor itemni qabul qilgan — omborchi kiritgan haqiqiy kelgan son
  //     (received): u YAKUNIY, yuk uni o'zgartira olmaydi;
  //  2) yuk keltiruvchi o'zi kiritgan son (taken — qoralamada saqlangan);
  //  3) hech biri yo'q — buyurtma qilingan son (count).
  static double _qtyBasis(YukOrderItem item) {
    if (item.accepted && item.received > 0) return item.received;
    if (item.taken > 0) return item.taken;
    return item.count.toDouble();
  }

  // Ombor itemni qabul qilib kelgan sonini tasdiqlaganmi — shunda Soni
  // maydoni QULF (omborchi kiritgan son yakuniy).
  static bool _qtyLocked(YukOrderItem item) =>
      item.accepted && item.received > 0;

  // Qoralamada (draft) saqlanadigan son: ombor tasdiqlagan bo'lsa received,
  // aks holda yuk keltiruvchi kiritgani. 0 = hali kiritilmagan — buyurtma
  // soni (count) bu yerda O'RNIGA QO'YILMAYDI, aks holda omborchi maydonida
  // yuk kiritmagan son "kiritilgandek" ko'rinib qolardi.
  static double _draftTaken(YukOrderItem item) =>
      _qtyLocked(item) ? item.received : item.taken;

  // Birlik narx asosi — YUK KELTIRUVCHI kiritgan son: lokal qoralama →
  // serverdagi taken → buyurtma soni (count). Server taken'i qoralama bilan
  // birga yangilanadi, shuning uchun ombor sonini qo'llash IDEMPOTENT:
  // bir marta kamaytirilgan summa ikkinchi marta kamaymaydi.
  static double _priceBasis(YukOrderItem item, ItemPrice? priced) {
    if (priced != null && priced.taken > 0) return priced.taken;
    if (item.taken > 0) return item.taken;
    return item.count.toDouble();
  }

  // Summani ombor tasdiqlagan songa moslash — birlik narx O'ZGARMAYDI:
  // 2 кг / 100 000 so'm dan 1.8 кг kelsa 90 000 bo'ladi (butun so'm).
  static double _scaleSubtotal(double subtotal, double basis, double received) {
    if (basis <= 0 ||
        subtotal <= 0 ||
        received <= 0 ||
        (basis - received).abs() <= 0.0001) {
      return subtotal;
    }
    return (subtotal / basis * received).roundToDouble();
  }

  // Soni maydonida KO'RSATILADIGAN matn: ombor qabul qilib kelgan sonini
  // kiritgan bo'lsa — o'sha son; yopilgan buyurtmada yoki yuk o'zi son
  // kiritgan bo'lsa — o'sha son; aks holda BO'SH. Buyurtma qilingan son
  // maydonga YOZILMAYDI (u nom ostidagi "1 кг" yorlig'ida turibdi).
  String _qtyText(YukOrder order, YukOrderItem item) {
    if (_qtyLocked(item)) return _fmtQty(item.received, item.type);
    if (_isDoneOrder(order)) return _fmtQty(item.taken, item.type);
    // Lokal qoralama (offline'da ham) serverdagi qiymatdan ustun.
    final priced =
        context.read<YukProvider>().getItemPrice(order.id, item.productId);
    if (priced != null && priced.taken > 0) {
      return _fmtQty(priced.taken, item.type);
    }
    if (item.taken > 0) return _fmtQty(item.taken, item.type);
    return '';
  }

  // Buyurtmalar yagona ketma-ketlikda (created ASC, teng bo'lsa id) — omborchi
  // va bugalter ekranlaridagi bilan bir xil: core/utils/order_sequence.dart.
  List<YukOrder> get _sorted => sortedOrderSeq(
        widget.orders,
        createdOf: (o) => o.created,
        idOf: (o) => o.id,
      );

  // Yangi qo'shimcha yozuv (proche/rasxod) va rasm/video biriktiriladigan
  // buyurtma — eng birinchi yuborilmagan buyurtma (kun davomida barqaror).
  YukOrder? get _anchor {
    for (final o in _sorted) {
      if (!_isDoneOrder(o)) return o;
    }
    return null;
  }

  String _fmt(double v) {
    if (v == 0) return '';
    return _formatMoney(v);
  }

  // API birlikdagi miqdorni (кг/л -> gramm) UI ko'rinishida formatlaydi;
  // 0 bo'lsa bo'sh string (maydon bo'sh qoladi).
  String _fmtQty(double v, String? type) {
    if (v == 0) return '';
    return formatQty(v, type);
  }

  // кг/л (og'irlik/hajm) mahsulotmi — kasr kiritish/1000 faktor uchun.
  bool _isKg(String? type) => qtyUnitFactor(type) == 1000;

  double _parse(String raw) {
    final cleaned = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (cleaned.isEmpty) return 0;
    final v = double.tryParse(cleaned);
    if (v == null || v < 0) return 0;
    return v;
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('dd.MM HH:mm').format(dt.toLocal());
  }

  static bool _isVideoPath(String p) {
    final ext = p.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp'}
        .contains(ext);
  }

  static String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppUrls.baseUrl}$url';

  @override
  void initState() {
    super.initState();
    for (final o in widget.orders) {
      _initOrder(o);
    }
    _maybeStartUndoTicker();
    _loadCatalogImages();
  }

  // Katalog rasmlarini bir marta yuklab olamiz (product_id -> /static/... url).
  // Xato bo'lsa bo'sh xarita qaytadi — rasm ko'rsatilmaydi, ro'yxat ishlayveradi.
  Future<void> _loadCatalogImages() async {
    final imgs = await _service.fetchBozorProductImages();
    if (!mounted || imgs.isEmpty) return;
    setState(() => _catalogImages = imgs);
  }

  // Bitta buyurtma itemlari uchun controllerlarni yaratish va boshlang'ich
  // qiymatlarni tiklash.
  void _initOrder(YukOrder order) {
    if (!_initedOrders.add(order.id)) return;
    final provider = context.read<YukProvider>();
    final done = _isDoneOrder(order);
    for (final item in order.items) {
      // Ombor o'chirgan item uchun controller ham, seed ham YO'Q — qator
      // faqat qizil chizilgan (read-only) ko'rinishda chiqadi.
      if (item.deleted) continue;
      final k = _key(order.id, item.productId);
      // Soni: ombor qabul qilgan bo'lsa omborchi kiritgan haqiqiy son (qulf),
      // aks holda yuk keltiruvchining o'zi kiritgani (lokal qoralama yoki
      // serverdagi taken). Summa: shu sessiyada kiritilgan qiymat, bo'lmasa
      // backenddan kelgan qiymat.
      final existing = provider.getItemPrice(order.id, item.productId);
      final taken0 = _qtyLocked(item)
          ? item.received
          : ((existing != null && existing.taken > 0)
              ? existing.taken
              : _draftTaken(item));
      final rawSubtotal = existing?.subtotal ?? item.subtotal;
      // Ilova yopiq turganda ombor kelgan sonni tasdiqlagan bo'lishi mumkin —
      // summa o'sha songa moslanadi (didUpdateWidget bu qatorni ko'rmaydi,
      // chunki u faqat O'ZGARISHDA ishlaydi).
      final subtotal0 = (!done && _qtyLocked(item))
          ? _scaleSubtotal(
              rawSubtotal, _priceBasis(item, existing), item.received)
          : rawSubtotal;
      _takenControllers[k] = TextEditingController(text: _qtyText(order, item));
      _subtotalControllers[k] = TextEditingController(text: _fmt(subtotal0));
      _takenFocusNodes[k] = FocusNode();
      _subtotalFocusNodes[k] = FocusNode();
      // Summasi bor katalog itemini lokal narxga tiklaymiz: qaytarib olingan
      // buyurtma qiymatlari qayta yuborilishi VA eski qoralamalardagi taken
      // count'ga normallashishi uchun. BOSHQA yuk keltiruvchi boshlagan
      // qoralama (priced_by boshqa) seed QILINMAYDI — aks holda flushDrafts
      // uni bizning nomimizdan qayta yuborib, hisoblar aralashib ketadi.
      if (!done &&
          provider.canSeedOrder(order) &&
          item.itemType.isEmpty &&
          subtotal0 > 0) {
        if (subtotal0 != rawSubtotal) {
          // Summa ombor soniga moslab kamaydi — bu YANGI qiymat, serverdagi
          // qoralamaga ham yozilishi kerak (seed emas, saqlash).
          provider.setItemPriceSilently(
              order.id, item.productId, taken0, subtotal0);
        } else {
          provider.seedItemPrice(order.id, item.productId, taken0, subtotal0);
        }
      }
    }
    // Qaytarib olingan buyurtmaning serverda qolgan biriktirma va
    // proche/rasxod itemlarini lokal ro'yxatlarga tiklaymiz.
    if (!done && provider.canSeedOrder(order)) {
      if (order.attachments.isNotEmpty) {
        provider.seedAttachments(order.id, order.attachments);
      }
      provider.seedAddedItems(order.id, order.items);
    }
  }

  // Ombor biror itemni qabul qilganda (socket orqali keladi) uning kelgan
  // soni "Nechta olgani" maydoniga AVTO to'ldiriladi va maydon QULFLANADI.
  // Shuningdek boshqa qurilma/yuk keltiruvchi yozgan miqdor-summalar ham
  // socketdan kelib maydonlarga JONLI tushiriladi ("Yuborish"siz).
  @override
  void didUpdateWidget(covariant YukSkladCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final provider = context.read<YukProvider>();
    final oldItems = <String, YukOrderItem>{
      for (final o in oldWidget.orders)
        for (final i in o.items) _key(o.id, i.productId): i,
    };
    for (final o in widget.orders) {
      // Kun davomida yangi kelgan buyurtma — controllerlarini hozir yaratamiz.
      _initOrder(o);
      final done = _isDoneOrder(o);
      for (final item in o.items) {
        final k = _key(o.id, item.productId);
        final old = oldItems[k];
        // Buyurtma yopilgach (pending→narxlandi socket/submit) soni maydoni
        // hisob asosini (taken, qabulda received) ko'rsatib turadi —
        // pendingdagi bo'sh ko'rinish yopiq chekda qolib ketmasin.
        if (done && !item.deleted) {
          final t = _qtyText(o, item);
          final ctrl = _takenCtrlFor(o, item);
          if (ctrl.text != t) ctrl.text = t;
          continue;
        }
        // Ombor itemni qabul qildi yoki kelgan sonini QAYTA tahrirladi
        // (socket) — omborchi kiritgan haqiqiy son qulf maydonga tushadi
        // (masalan 2 → 1.8) va summa shu songa PROPORSIONAL kamayadi:
        // yuk kiritgan 2 кг / 100 000 so'm dan 1.8 кг kelgan bo'lsa summa
        // 90 000 bo'ladi (0.2 ning puli ayriladi).
        final receivedChanged = item.accepted &&
            (!(old?.accepted ?? false) || old!.received != item.received);
        if (!done && !item.deleted && receivedChanged) {
          _applyReceived(provider, o, item);
        }
        // ─── REAL-TIME sinxronlash (boshqa qurilma/yuk user yozgani) ───
        // Buyurtma yopiq/qabul qilingan, item o'chirilgan ('item_deleted'
        // socket hodisasi — qator chizilgan ko'rinishga o'tadi, sync shart
        // emas) yoki endi paydo bo'lgan bo'lsa tegmaymiz.
        if (done || item.accepted || item.deleted || old == null) continue;
        if (old.subtotal == item.subtotal && old.taken == item.taken) continue;
        // O'zimning hali serverga yetib bormagan (debounce kutayotgan)
        // qoralamam bor — socketdagi eski qiymat uni bosib qo'ymasin.
        if (provider.draftSaveScheduled(o.id)) continue;
        final qtyFocused = _takenFocusNodes[k]?.hasFocus ?? false;
        final sumFocused = _subtotalFocusNodes[k]?.hasFocus ?? false;
        if (!qtyFocused && old.taken != item.taken) {
          final ctrl = _takenCtrlFor(o, item);
          final t = item.taken > 0 ? _fmtQty(item.taken, item.type) : '';
          if (ctrl.text != t) ctrl.text = t;
        }
        if (!sumFocused) {
          final ctrl = _subtotalCtrlFor(o, item);
          if (_parse(ctrl.text) != item.subtotal) {
            ctrl.text = _fmt(item.subtotal);
          }
        }
        // O'z buyurtmamda (masalan ikkinchi qurilmam yozgan) lokal narxni
        // ham sinxronlaymiz — flush baribir no-op (server bilan teng).
        if (provider.canSeedOrder(o) && !qtyFocused && !sumFocused) {
          provider.seedItemPrice(
              o.id, item.productId, _draftTaken(item), item.subtotal);
        }
      }
    }
    _maybeStartUndoTicker();
  }

  // Ombor tasdiqlagan kelgan son (received) qatorga qo'llanadi:
  //  • Soni maydoni o'sha songa o'tadi va endi QULF (omborchining soni yakuniy);
  //  • yuk kiritgan summa shu songa PROPORSIONAL qayta hisoblanadi — birlik
  //    narx o'zgarmaydi: 2 кг / 100 000 so'm dan 1.8 кг kelsa 90 000 bo'ladi
  //    (yetmagan 0.2 ning puli summadan ayriladi).
  // notifyListeners CHAQIRILMAYDI (setItemPriceSilently) — bu metod build
  // fazasida (didUpdateWidget) ishlaydi; maydonlar qo'lda yangilanadi.
  void _applyReceived(YukProvider provider, YukOrder order, YukOrderItem item) {
    final v = _qtyBasis(item);
    final qtyCtrl = _takenCtrlFor(order, item);
    final qtyText = _fmtQty(v, item.type);
    if (qtyCtrl.text != qtyText) qtyCtrl.text = qtyText;

    if (!provider.canSeedOrder(order)) return;
    final priced = provider.getItemPrice(order.id, item.productId);
    // Summa hali kiritilmagan yoki ataylab 0 yozilgan ("olinmagan") —
    // qayta hisoblaydigan narsa yo'q.
    if (priced == null || priced.zero) return;
    final subtotal =
        _scaleSubtotal(priced.subtotal, _priceBasis(item, priced), v);
    if (subtotal != priced.subtotal) {
      final sumCtrl = _subtotalCtrlFor(order, item);
      final sumText = _fmt(subtotal);
      if (sumCtrl.text != sumText) sumCtrl.text = sumText;
    }
    provider.setItemPriceSilently(order.id, item.productId, v, subtotal);
  }

  // Achot endigina yopilgan bo'lsa "Qaytarib olish" sanog'ini har soniyada
  // yangilab turamiz; muddat tugashi bilan timer to'xtaydi.
  void _maybeStartUndoTicker() {
    final provider = context.read<YukProvider>();
    if (provider.undoRemainingForSklad(widget.skladId) == Duration.zero) {
      return;
    }
    _undoTicker?.cancel();
    _undoTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {});
      if (context.read<YukProvider>().undoRemainingForSklad(widget.skladId) ==
          Duration.zero) {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    _undoTicker?.cancel();
    for (final c in _takenControllers.values) {
      c.dispose();
    }
    for (final c in _subtotalControllers.values) {
      c.dispose();
    }
    for (final f in _takenFocusNodes.values) {
      f.dispose();
    }
    for (final f in _subtotalFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  // Controllerlarni kerak bo'lganda yaratish (masalan buyurtma yuborilgach
  // serverdan yangi proche/rasxod itemlar kelsa) — null crash bo'lmasin.
  TextEditingController _takenCtrlFor(YukOrder order, YukOrderItem item) =>
      _takenControllers.putIfAbsent(
        _key(order.id, item.productId),
        () => TextEditingController(text: _qtyText(order, item)),
      );

  TextEditingController _subtotalCtrlFor(YukOrder order, YukOrderItem item) =>
      _subtotalControllers.putIfAbsent(
        _key(order.id, item.productId),
        () => TextEditingController(text: _fmt(item.subtotal)),
      );

  FocusNode _takenFocusFor(YukOrder order, YukOrderItem item) =>
      _takenFocusNodes.putIfAbsent(
          _key(order.id, item.productId), () => FocusNode());

  FocusNode _subtotalFocusFor(YukOrder order, YukOrderItem item) =>
      _subtotalFocusNodes.putIfAbsent(
          _key(order.id, item.productId), () => FocusNode());

  void _onItemChanged(YukOrder order, YukOrderItem item) {
    final provider = context.read<YukProvider>();
    final k = _key(order.id, item.productId);
    final subtotalText = _subtotalControllers[k]?.text ?? '';
    final subtotal = _parse(subtotalText);
    // "Ataylab 0": yuk summa maydoniga QO'LDA 0 yozsa item "olinmagan" bo'lib
    // yuboriladi (taken=0, subtotal=0 → backend "zeroed" deb yopadi). Bo'sh
    // summa esa yuborilmaydi (pending qoladi).
    final zero = subtotalText.trim().isNotEmpty && subtotal == 0;
    provider.setItemPrice(
      order.id,
      item.productId,
      zero ? 0.0 : _takenFromField(order, item),
      subtotal,
      zero: zero,
    );
  }

  // Soni maydonidan hisob asosi (API birlikda — кг/л uchun butun гр/мл):
  //  • ombor qabul qilgan bo'lsa maydon qulf, omborchining soni yakuniy;
  //  • yuk son kiritgan bo'lsa — o'sha son;
  //  • maydon BO'SH bo'lsa — 0. Bu "yuk hali son kiritmagan" degani: omborchi
  //    maydonida ham bo'sh ko'rinadi, buyurtma soni (count) esa faqat
  //    YUBORISHDA qo'yiladi (YukProvider._wireTaken).
  double _takenFromField(YukOrder order, YukOrderItem item) {
    if (_qtyLocked(item)) return item.received;
    final raw =
        _parse(_takenControllers[_key(order.id, item.productId)]?.text ?? '');
    if (raw <= 0) return 0;
    return qtyFromUi(raw, item.type).toDouble();
  }

  // ─────────────────── Biriktirmalar (rasm/video) ───────────────────

  Future<void> _pickFromCamera(int orderId, {required bool video}) async {
    try {
      // Rasm ilova ICHIDAGI kamerada olinadi (InAppPhotoCamera) — tashqi
      // kamera ilovasi Android'da ilovani orqa fonda o'ldirilishiga
      // (kiritilgan summalar yo'qolishiga) sabab bo'lardi.
      final XFile? file = video
          ? await _picker.pickVideo(source: ImageSource.camera)
          : await Navigator.of(context).push<XFile>(
              MaterialPageRoute(builder: (_) => const InAppPhotoCamera()),
            );
      if (file == null || !mounted) return;
      context.read<YukProvider>().addAttachments(orderId, [file.path]);
    } catch (_) {
      // Ruxsat berilmagan/bekor qilingan — jim.
    }
  }

  Future<void> _pickFromGallery(int orderId) async {
    try {
      final List<XFile> files = await _picker.pickMultipleMedia();
      if (files.isEmpty || !mounted) return;
      context
          .read<YukProvider>()
          .addAttachments(orderId, files.map((f) => f.path).toList());
    } catch (_) {
      // Ruxsat berilmagan/bekor qilingan — jim.
    }
  }

  void _showAddAttachmentSheet(int orderId) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: _accentColor),
              title: const Text('Kamera — rasm'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFromCamera(orderId, video: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: _accentColor),
              title: const Text('Kamera — video'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFromCamera(orderId, video: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: _accentColor),
              title: const Text('Galereya (rasm/video)'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickFromGallery(orderId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAttachment(String entry) {
    if (_isVideoPath(entry)) {
      // Video inline ko'rsatilmaydi — tashqi ilovada ochiladi.
      if (YukProvider.isRemoteAttachment(entry)) {
        launchUrl(Uri.parse(_fullUrl(entry)),
            mode: LaunchMode.externalApplication);
      }
      return;
    }
    // Rasm: alohida ekran o'rniga ro'yxat ostida ochiladi. Bosilgan rasm
    // qayta bosilsa yopiladi.
    setState(() {
      _expandedAttachment = _expandedAttachment == entry ? null : entry;
    });
  }

  // Bosilgan rasm ro'yxat (thumbnail'lar) ostida shu yerda kattalashib ochiladi.
  Widget _buildInlinePreview() {
    final entry = _expandedAttachment;
    if (entry == null || _isVideoPath(entry)) return const SizedBox.shrink();
    final isRemote = YukProvider.isRemoteAttachment(entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              color: Colors.black,
              constraints: const BoxConstraints(maxHeight: 340),
              child: InteractiveViewer(
                child: Center(
                  // Ko'rish oynasi 340px balandlikda — rasm ham ekran
                  // kengligidan kattaroq dekod qilinmaydi.
                  child: isRemote
                      ? AppNetworkImage(
                          imageUrl: _fullUrl(entry),
                          fit: BoxFit.contain,
                        )
                      : Image.file(
                          File(entry),
                          fit: BoxFit.contain,
                          cacheWidth: (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round(),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => setState(() => _expandedAttachment = null),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mahsulot nomi ostida ko'rinadigan katalog rasmi. Bosilsa TO'LIQ EKRANDA
  // ochiladi; ochilgan rasm ustiga bir marta bosilsa yopiladi.
  // Rasmi yo'q mahsulot (yoki qo'shimcha/proche item) uchun hech narsa chizmaydi.
  Widget _productPhoto(YukOrderItem item) {
    // AppBar'dagi tugma o'chiq bo'lsa rasmlar umuman chizilmaydi.
    if (!widget.showImages) return const SizedBox.shrink();
    final rel = _catalogImages[item.productId];
    if (rel == null || rel.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () => openFullScreenImage(context, _fullUrl(rel)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 96,
            height: 64,
            color: const Color(0xFFF5F1EA),
            // ⚠️ Rasm 96px'lik katakcha uchun SHU o'lchamda dekod qilinadi —
            // ro'yxatda o'nlab mahsulot bo'lgani uchun bu hal qiluvchi.
            child: AppNetworkImage(
              imageUrl: _fullUrl(rel),
              fit: BoxFit.cover,
              maxDecodeWidth: 320,
              placeholder: (_) => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentColor,
                  ),
                ),
              ),
              errorWidget: (_) =>
                  const Icon(Icons.broken_image, color: Colors.black26),
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachmentTile(String entry, {VoidCallback? onRemove}) {
    final isRemote = YukProvider.isRemoteAttachment(entry);
    final isVideo = _isVideoPath(entry);

    Widget content;
    if (isVideo) {
      content = Container(
        color: Colors.black87,
        child: const Center(
          child: Icon(Icons.play_circle_outline, color: Colors.white, size: 28),
        ),
      );
    } else if (isRemote) {
      // Plitka 72px — rasm ham shu o'lchamda dekod qilinadi.
      content = AppNetworkImage(
        imageUrl: _fullUrl(entry),
        fit: BoxFit.cover,
        maxDecodeWidth: 256,
        errorWidget: (_) => Container(
          color: const Color(0xFFF5F1EA),
          child: const Icon(Icons.broken_image, color: Colors.black26),
        ),
      );
    } else {
      // Kameradan olingan fayl 4000px bo'lishi mumkin — 72px plitka uchun
      // o'lchamsiz dekod qilinsa bitta rasm ~48 MB RAM egallaydi.
      content = Image.file(
        File(entry),
        fit: BoxFit.cover,
        cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF5F1EA),
          child: const Icon(Icons.broken_image, color: Colors.black26),
        ),
      );
    }

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => _openAttachment(entry),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: content,
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Yuborishdan oldin: hamma ochiq buyurtmalarning biriktirmalari + qo'shish
  // tugmasi (yangi rasm/video anchor buyurtmaga biriktiriladi).
  Widget _buildAttachmentsEditor(
    YukProvider provider,
    List<YukOrder> pending,
    YukOrder? anchor,
  ) {
    final tiles = <Widget>[];
    for (final o in pending) {
      for (final e in provider.attachmentsFor(o.id)) {
        tiles.add(_attachmentTile(
          e,
          onRemove: () {
            provider.removeAttachment(o.id, e);
            if (_expandedAttachment == e) {
              setState(() => _expandedAttachment = null);
            }
          },
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...tiles,
          if (anchor != null)
            GestureDetector(
              onTap: () => _showAddAttachmentSheet(anchor.id),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentColor),
                  color: _accentColor.withValues(alpha: 0.06),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: _accentColor, size: 22),
                    SizedBox(height: 2),
                    Text(
                      'Rasm/video',
                      style: TextStyle(fontSize: 9, color: _accentColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Yopilgan achotda: biriktirmalarni faqat ko'rish.
  Widget _buildAttachmentsViewer(List<YukOrder> orders) {
    final entries = <String>[
      for (final o in orders) ...o.attachments,
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entries.map(_attachmentTile).toList(),
      ),
    );
  }

  // ─────────── Qo'shimcha yozuv (proche mahsulot / rasxod) qo'shish ───────────

  void _showAddEntrySheet(int orderId, {required bool rasxod}) {
    FocusScope.of(context).unfocus();
    final nameController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    final sumController = TextEditingController();
    final provider = context.read<YukProvider>();
    // Proche itemning birligi: standart шт; katalogdagi nom tanlansa
    // mahsulotning o'z birligi qo'yiladi. Bozor nakladnoyida (targovli)
    // «900» va «0.47» birliksiz aralashib ketmasligi uchun majburiy.
    String unit = rasxod ? '' : 'шт';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final name = nameController.text.trim();
          final prev = rasxod ? null : provider.lastPriceFor(name: name);
          // Jonli birlik narx: kiritilgan son (UI birlikda) va summa.
          final qtyUi = _parse(qtyController.text);
          final sum = _parse(sumController.text);
          final unitPrice =
              (!rasxod && qtyUi > 0 && sum > 0) ? sum / qtyUi : null;
          final dev =
              unitPrice == null ? null : yukPriceDeviation(unitPrice, prev);
          final warn = dev != null && dev.abs() >= kYukPriceWarnRatio;
          final isKg = _isKg(unit);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rasxod ? 'Xarajat qo\'shish' : 'Mahsulot qo\'shish',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rasxod
                      ? 'Masalan: yetkazib berish xizmati. Ombor qabul qilmaydi, '
                          'chek oxirida alohida ko\'rsatiladi.'
                      : 'Buyurtmada yo\'q qo\'shimcha mahsulot (masalan gaz plitasi).',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                _NameAutocompleteField(
                  controller: nameController,
                  itemType: rasxod ? 'rasxod' : 'proche',
                  onChanged: (_) => setSheet(() {}),
                  // Katalog mahsuloti tanlansa birligi ham o'zi qo'yiladi.
                  onSelected: (opt) => setSheet(() {
                    final t = opt.type.trim().toLowerCase();
                    if (!rasxod && t.isNotEmpty) unit = t;
                  }),
                ),
                if (!rasxod) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in kProductTypeOptions)
                        ChoiceChip(
                          label: Text(t),
                          selected: unit == t,
                          visualDensity: VisualDensity.compact,
                          selectedColor: _accentColor.withValues(alpha: 0.25),
                          onSelected: (_) => setSheet(() => unit = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      labelText: isKg ? 'Miqdor ($unit)' : 'Soni ($unit)',
                      helperText:
                          isKg ? 'Kilogramm/litrda yozing (masalan 1.5)' : null,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _accentColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: sumController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  onChanged: (_) => setSheet(() {}),
                  decoration: InputDecoration(
                    labelText: 'Jami summa',
                    suffixText: 'so\'m',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _accentColor),
                    ),
                  ),
                ),
                // Oldingi narx + jonli birlik narx + keskin og'ish ogohi.
                if (!rasxod && (prev != null || unitPrice != null)) ...[
                  const SizedBox(height: 8),
                  _priceHint(
                    unitPrice: unitPrice,
                    unit: unit,
                    prev: prev,
                    deviation: dev,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameController.text.trim();
                      final subtotal = _parse(sumController.text);
                      final taken = rasxod ? 0.0 : _parse(qtyController.text);
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Nomini kiriting')),
                        );
                        return;
                      }
                      if (subtotal <= 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('Summani kiriting')),
                        );
                        return;
                      }
                      // Miqdor API birlikda ketadi: кг/л -> butun gramm/ml.
                      final takenUi = rasxod ? 0.0 : (taken > 0 ? taken : 1.0);
                      provider.addAddedItem(
                        orderId,
                        YukAddedItem(
                          itemType: rasxod ? 'rasxod' : 'proche',
                          name: name,
                          type: unit,
                          taken:
                              rasxod ? 0 : qtyFromUi(takenUi, unit).toDouble(),
                          subtotal: subtotal,
                        ),
                      );
                      Navigator.pop(sheetContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          warn ? const Color(0xFFE65100) : _accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      warn ? 'Baribir qo\'shish' : 'Qo\'shish',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Narx izohi: «oldingi: 22 641 so'm/кг (13.08)», joriy birlik narx va
  // og'ish 30%+ bo'lsa qizil ogohlantirish (kg o'rniga gramm, nol ko'p/kam
  // kabi kiritish xatolarini narxlash paytidayoq ushlash uchun).
  Widget _priceHint({
    required double? unitPrice,
    required String unit,
    required YukLastPrice? prev,
    required double? deviation,
  }) {
    final warn = deviation != null && deviation.abs() >= kYukPriceWarnRatio;
    final unitSuffix = unit.isNotEmpty ? '/$unit' : '';
    final parts = <String>[];
    if (unitPrice != null) {
      parts.add('${_formatMoney(unitPrice)} so\'m$unitSuffix');
    }
    if (prev != null) {
      final prevUnit = prev.unit.isNotEmpty ? '/${prev.unit}' : '';
      final when = prev.shortDate.isNotEmpty ? ' (${prev.shortDate})' : '';
      parts.add('oldingi: ${_formatMoney(prev.price)} so\'m$prevUnit$when');
    }
    final pct = deviation == null ? '' : (deviation * 100).round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join('  ·  '),
          style: TextStyle(
            fontSize: 12,
            color: warn ? const Color(0xFFC62828) : _accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (warn)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '⚠ Oldingi narxdan ${deviation > 0 ? '+' : ''}$pct% farq — '
              'birlik (kg/gramm) va summani tekshiring',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFC62828),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _addedValueBox(String text) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1EA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    );
  }

  Widget _addedProcheRow(
    YukProvider provider,
    int orderId,
    int index,
    YukAddedItem item,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _nameFlex,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Qo\'shimcha',
                        style: TextStyle(
                          fontSize: 12,
                          color: _accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => provider.removeAddedItem(orderId, index),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child:
                        Icon(Icons.close, size: 16, color: Color(0xFFC62828)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _qtyFlex,
            // taken API birlikda (кг/л — gramm) — birligi bilan ko'rinadi.
            child: _addedValueBox(
              '${_fmtQty(item.taken, item.type)}'
              '${item.type.isNotEmpty ? ' ${item.type}' : ''}',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _sumFlex,
            child: _addedValueBox(_formatMoney(item.subtotal)),
          ),
        ],
      ),
    );
  }

  // Begona buyurtmaning serverdagi proche itemi — o'chirib bo'lmaydigan qator
  // (kim boshlagan bo'lsa o'sha o'chiradi; bizda faqat ko'rinadi).
  Widget _remoteProcheRow(YukOrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _nameFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Qo\'shimcha',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _qtyFlex,
            // taken API birlikda — item.type bo'yicha UI (kg) ko'rinadi.
            child: _addedValueBox(
              '${_fmtQty(item.taken, item.type)}'
              '${(item.type ?? '').isNotEmpty ? ' ${item.type}' : ''}',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _sumFlex,
            child: _addedValueBox(_formatMoney(item.subtotal)),
          ),
        ],
      ),
    );
  }

  // "Xarajatlar" bloki: HAMMA buyurtmalarning rasxod yozuvlari birga.
  // Begona (boshqa yuk user boshlagan) ochiq buyurtmaning rasxodlari
  // serverdagi itemlardan READ-ONLY ko'rsatiladi (real-time socketdan tushadi).
  Widget _buildRasxodBlock(YukProvider provider, List<YukOrder> orders) {
    final rows = <Widget>[];
    for (final order in orders) {
      if (_isDoneOrder(order)) {
        for (final item in order.items.where((i) => i.isRasxod)) {
          rows.add(_rasxodRow(item.name, item.subtotal));
        }
      } else if (!provider.canSeedOrder(order)) {
        for (final item in order.items.where((i) => i.isRasxod)) {
          rows.add(_rasxodRow(item.name, item.subtotal));
        }
      } else {
        final added = provider.addedItemsFor(order.id);
        for (var i = 0; i < added.length; i++) {
          if (!added[i].isRasxod) continue;
          final index = i;
          rows.add(_rasxodRow(
            added[i].name,
            added[i].subtotal,
            onRemove: () => provider.removeAddedItem(order.id, index),
          ));
        }
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 18),
        const Text(
          'Xarajatlar',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        ...rows,
      ],
    );
  }

  Widget _rasxodRow(String name, double subtotal, {VoidCallback? onRemove}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Text(
            '${_formatMoney(subtotal)} so\'m',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close, size: 16, color: Color(0xFFC62828)),
              ),
            ),
        ],
      ),
    );
  }

  // Inline kichik narx maydoni (jadval ustuni ichida).
  Widget _inlineField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    FocusNode? focusNode,
    String? hint,
    bool decimal = false,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        decimal ? DecimalInputFormatter() : ThousandsSeparatorInputFormatter(),
      ],
      onChanged: onChanged,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        color: enabled ? Colors.black87 : Colors.black54,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        isDense: true,
        filled: !enabled,
        fillColor: const Color(0xFFF5F1EA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accentColor),
        ),
      ),
    );
  }

  // Ikki buyurtma orasidagi yupqa vaqt chizig'i (ID ko'rsatilmaydi —
  // faqat qachon va kim yuborgani).
  Widget _batchLabel(YukOrder order) {
    final label = [
      _formatTime(order.created),
      if (order.username.isNotEmpty) order.username,
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  // Ombor o'chirgan item qatori: nomi va soni qizil chizilgan, summa maydoni
  // O'RNIDA qizil "O'chirildi" belgisi — butunlay read-only. Yuk keltiruvchi
  // shu qatordan itemning o'chirilganini biladi.
  Widget _deletedItemRow(YukOrderItem item) {
    const deletedStyle = TextStyle(
      color: Colors.red,
      decoration: TextDecoration.lineThrough,
      decorationColor: Colors.red,
    );
    const red = Color(0xFFC62828);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _nameFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: deletedStyle.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${formatQty(item.count, item.type)}'
                  '${item.type != null && item.type!.isNotEmpty ? ' ${item.type}' : ''}',
                  style: deletedStyle.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Soni ustuni: buyurtma soni qizil chizilgan holda.
          Expanded(
            flex: _qtyFlex,
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: red.withValues(alpha: 0.35)),
              ),
              child: Text(
                formatQty(item.count, item.type),
                style: deletedStyle.copyWith(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Summa maydoni YO'Q — o'rnida "O'chirildi" belgisi.
          Expanded(
            flex: _sumFlex,
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: red.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'O\'chirildi',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bitta katalog/proche item qatori (controllerlar buyurtma+mahsulot
  // juftligi bo'yicha).
  Widget _itemRow(YukProvider provider, YukOrder order, YukOrderItem item) {
    // Ombor o'chirgan item — chizilgan read-only qator, maydonlarsiz.
    if (item.deleted) return _deletedItemRow(item);
    final done = _isDoneOrder(order);
    final priced = provider.getItemPrice(order.id, item.productId);
    // Birlik narx/farq hisobi maydon matniga emas, hisob asosiga tayanadi:
    // qabulda omborchining received'i, aks holda yuk kiritgan son (lokal
    // qoralama — yozayotganda jonli), u ham bo'lmasa buyurtma soni.
    final takenVal = done
        ? (priced?.taken ?? item.taken)
        : (_qtyLocked(item)
            ? item.received
            : ((priced != null && priced.taken > 0)
                ? priced.taken
                : _qtyBasis(item)));
    final subtotalVal = priced?.subtotal ?? item.subtotal;
    // Birlik narx UI birlikda (so'm/kg): API'dagi gramm avval kg'ga o'giriladi.
    final unitPrice = (takenVal > 0 && subtotalVal > 0)
        ? subtotalVal / qtyToUi(takenVal, item.type)
        : null;
    var unitLabel = unitPrice != null
        ? '${_fmtQty(takenVal, item.type)} * ${_formatMoney(unitPrice)}'
        : '';
    // Oldingi narx (kg/l yoki dona boshiga) va undan og'ish — 30%+ bo'lsa
    // qizil ogohlantirish (kiritish xatosini shu yerdayoq ko'rsatadi).
    final prevPrice = done
        ? null
        : provider.lastPriceFor(productId: item.productId, name: item.name);
    final deviation =
        unitPrice == null ? null : yukPriceDeviation(unitPrice, prevPrice);
    final priceWarn =
        deviation != null && deviation.abs() >= kYukPriceWarnRatio;
    // Donalab olinadigan кг/л mahsulot («1шт=200гр»): dona vazni nomdan
    // o'qiladi — dona soni bilan kiritish tugmasi va dona narxi ko'rinadi.
    final pieceG = pieceWeightFromName(item.name, item.type);
    final pieces = (pieceG != null && takenVal > 0) ? takenVal / pieceG : null;
    final canPieceEntry = pieceG != null && !done && !_qtyLocked(item);
    if (pieces != null && unitPrice != null && subtotalVal > 0) {
      // «40 шт × 29 175» — dona narxi ko'rinsa xato darrov seziladi.
      unitLabel += '  ·  ${_fmtPieces(pieces)} шт × '
          '${_formatMoney(subtotalVal / pieces)}';
    }
    final diff = takenVal - item.count;
    final showDiff = !item.isProche && takenVal > 0 && diff.abs() > 0.0001;
    final diffText = diff > 0
        ? '+${_fmtQty(diff, item.type)}'
        : '-${_fmtQty(diff.abs(), item.type)}';
    final diffColor =
        diff > 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _nameFlex,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        item.isProche
                            ? 'Qo\'shimcha'
                            : '${formatQty(item.count, item.type)}'
                                '${item.type != null && item.type!.isNotEmpty ? ' ${item.type}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (showDiff) ...[
                        const SizedBox(width: 6),
                        Text(
                          diffText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: diffColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Ombor kelgan sonni boshqacha tasdiqlagan bo'lsa:
                  // «2 → 1.8» (kiritilgan → keldi). Summa ham shu songa
                  // proporsional kamaygan.
                  if (hasQtyClaimDiff(item.claimed, takenVal)) ...[
                    const SizedBox(height: 2),
                    qtyClaimLabel(
                      claimed: item.claimed,
                      actual: takenVal,
                      type: item.type,
                      withUnit: true,
                    ),
                  ],
                  if (unitPrice != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      unitLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            priceWarn ? const Color(0xFFC62828) : _accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (pieceG != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '1 шт = ${_fmtQty(pieceG.toDouble(), item.type)} '
                          '${item.type}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (canPieceEntry) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _enterByPieces(order, item, pieceG),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'dona bilan',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (prevPrice != null && !done) ...[
                    const SizedBox(height: 2),
                    Text(
                      'oldingi: ${_formatMoney(prevPrice.price)}'
                      '${prevPrice.unit.isNotEmpty ? '/${prevPrice.unit}' : ''}'
                      '${prevPrice.shortDate.isNotEmpty ? ' (${prevPrice.shortDate})' : ''}'
                      '${priceWarn ? '  ⚠ ${deviation > 0 ? '+' : ''}${(deviation * 100).round()}%' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: priceWarn
                            ? const Color(0xFFC62828)
                            : Colors.grey.shade600,
                        fontWeight:
                            priceWarn ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                  // Mahsulot katalog rasmi nom ostida (bosilsa to'liq ekran).
                  _productPhoto(item),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _qtyFlex,
            // Soni ustiga bosilsa omborchi qabulda yuborgan rasm katta
            // ochiladi (rasm ustiga yana bosilsa yopiladi); faqat video
            // bo'lsa tashqi pleerda ochiladi.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: item.acceptMedia.isEmpty
                  ? null
                  : () => _openAttachment(
                        item.imageUrl.isNotEmpty
                            ? item.imageUrl
                            : item.videoUrl,
                      ),
              child: _inlineField(
                controller: _takenCtrlFor(order, item),
                focusNode: _takenFocusFor(order, item),
                hint: '0',
                decimal: _isKg(item.type),
                // Yuk keltiruvchi olib kelgan sonini O'ZI kiritadi. Ombor
                // itemni qabul qilgach (kelgan sonini tasdiqlagach) maydon
                // QULFLANADI — omborchining soni yakuniy.
                enabled: !done && !_qtyLocked(item),
                onChanged: (_) => _onItemChanged(order, item),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: _sumFlex,
            child: _inlineField(
              controller: _subtotalCtrlFor(order, item),
              focusNode: _subtotalFocusFor(order, item),
              hint: '0',
              enabled: !done,
              onChanged: (_) => _onItemChanged(order, item),
            ),
          ),
        ],
      ),
    );
  }

  // Dona soni ko'rinishi: butun bo'lsa "40", bo'lmasa "2.5".
  String _fmtPieces(double n) {
    final r = (n * 100).round() / 100;
    if (r == r.roundToDouble()) return r.toInt().toString();
    return r.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  // «dona bilan» — donalab olingan кг/л mahsulot uchun dona sonini so'rab,
  // Soni maydoniga kg/l qiymatini (dona × bir dona vazni) yozadi. Birlik va
  // sklad qoldig'i o'zgarmaydi — faqat kiritish xatosi (dona o'rniga kg,
  // gramm o'rniga kg) kamayadi.
  Future<void> _enterByPieces(
    YukOrder order,
    YukOrderItem item,
    int pieceG,
  ) async {
    final ctrl = TextEditingController();
    final n = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [DecimalInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Necha dona?',
            helperText:
                '1 шт = ${_fmtQty(pieceG.toDouble(), item.type)} ${item.type}',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, _parse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _parse(ctrl.text)),
            child: const Text('Qo\'yish'),
          ),
        ],
      ),
    );
    if (n == null || n <= 0 || !mounted) return;
    // API birlikda (gramm/ml) — maydonga UI (kg/l) ko'rinishida yoziladi.
    final apiQty = (n * pieceG).round().toDouble();
    _takenCtrlFor(order, item).text = formatQty(apiQty, item.type);
    _onItemChanged(order, item);
    setState(() {});
  }

  // Yuborishdan oldin keskin narx og'ishi tekshiruvi: oldingi narxdan 3 marta
  // va undan ko'p farq qilgan qatorlar (kg o'rniga gramm, nol ko'p/kam,
  // dona o'rniga kg) ro'yxat qilib ko'rsatiladi — foydalanuvchi tekshiradi
  // yoki ataylab tasdiqlaydi. true = davom etish mumkin.
  Future<bool> _confirmPriceOutliers(
    YukProvider provider,
    List<YukOrder> pending,
  ) async {
    final rows = <String>[];
    for (final o in pending) {
      for (final item in o.items.where((i) => !i.deleted && !i.isRasxod)) {
        final p = provider.getItemPrice(o.id, item.productId);
        if (p == null || p.zero || p.subtotal <= 0) continue;
        final taken = _qtyLocked(item)
            ? item.received
            : (p.taken > 0 ? p.taken : _qtyBasis(item));
        if (taken <= 0) continue;
        final unitPrice = p.subtotal / qtyToUi(taken, item.type);
        final prev =
            provider.lastPriceFor(productId: item.productId, name: item.name);
        final dev = yukPriceDeviation(unitPrice, prev);
        if (dev == null || dev.abs() < kYukPriceBlockRatio) continue;
        final unit = (item.type ?? '').isNotEmpty ? '/${item.type}' : '';
        final times = dev > 0
            ? '${(dev + 1).toStringAsFixed(1)}× qimmat'
            : '${(1 / (dev + 1)).toStringAsFixed(1)}× arzon';
        rows.add('${item.name}: ${_formatMoney(unitPrice)}$unit '
            '(oldingi ${_formatMoney(prev!.price)}) — $times');
      }
    }
    if (rows.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Narx keskin farq qiladi'),
        content: SingleChildScrollView(
          child: Text(
            'Quyidagi qatorlar oldingi narxdan 3 marta va undan ko\'p farq '
            'qiladi — birlik (kg/gramm/dona) va summani tekshiring:\n\n'
            '• ${rows.join('\n• ')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tekshiraman'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Baribir yuborish'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // Yuborishdan oldin tasdiq: summasi kiritilmagan qatorlar bo'lsa
  // ogohlantiramiz — ular YUBORILMAYDI, ro'yxatda (pending) qoladi. Summaga
  // ataylab 0 yozilgan qator esa YUBORILADI (backend "olinmagan" deb yopadi)
  // — u sanalmaydi. Hammasiga summa kiritilgan bo'lsa dialogsiz darhol
  // yuboriladi. LEKIN ombor grami (kelgan soni) kiritib QABUL QILGAN item
  // summasiz qolsa — yuborish umuman BLOKlanadi: bunday item keyin summasiz
  // yopilib, pul hisobida teshik qoldiradi (received>0, subtotal=0).
  Future<void> _confirmAndSubmit(
    YukProvider provider,
    List<YukOrder> pending,
  ) async {
    var unfilled = 0;
    final blocked = <String>[];
    for (final o in pending) {
      // O'chirilgan itemlar sanalmaydi — ular baribir yuborilmaydi.
      for (final item
          in o.items.where((i) => i.itemType.isEmpty && !i.deleted)) {
        // Provider haqiqati: to'liq to'ldirilgan yoki ataylab 0/0 yozilgan
        // qator YUBORILADI (sanalmaydi); qolganlari ro'yxatda qoladi.
        if (!provider.isRowSubmittable(o.id, item.productId)) {
          unfilled++;
          if (item.accepted && item.received > 0) blocked.add(item.name);
        }
      }
    }
    if (blocked.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Summa kiritilmagan'),
          content: Text(
            'Quyidagi mahsulotlarning grami (soni) kiritilgan, '
            'lekin summasi yozilmagan:\n\n'
            '• ${blocked.join('\n• ')}\n\n'
            'Summasini kiriting, shundan keyin yuborish mumkin bo\'ladi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tushunarli'),
            ),
          ],
        ),
      );
      return;
    }
    if (unfilled > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Achotni yopish'),
          content: Text(
            '$unfilled ta mahsulotga summa kiritilmagan — '
            'ular yuborilmaydi, ro\'yxatda qoladi. Davom etasizmi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yuborish'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    if (!await _confirmPriceOutliers(provider, pending)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.submitAllForSklad(widget.skladId);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Yuborildi — achot yopildi')),
      );
    } else if (provider.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
    }
    _maybeStartUndoTicker();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<YukProvider>(
      builder: (context, provider, child) {
        final orders = _sorted;
        final pending = orders.where((o) => !_isDoneOrder(o)).toList();
        final allDone = orders.isNotEmpty && pending.isEmpty;
        final anchor = _anchor;
        final submitting = provider.submittingSkladId == widget.skladId;
        final reverting = provider.revertingSkladId == widget.skladId;
        final hasAnyPrice = provider.hasAnyPriceForSklad(widget.skladId);
        final undoLeft = allDone
            ? provider.undoRemainingForSklad(widget.skladId).inSeconds
            : 0;

        // Jami summalar: yuborilganlari backenddan; ochiqlari — lokal
        // kiritilgan qiymat, bo'lmasa serverdagi (boshqa qurilma/yuk user
        // yozgani socketdan tushadi) qiymat. Begona (boshqa user boshlagan)
        // buyurtmaning proche/rasxodi serverdagi itemlardan olinadi.
        var mahsulot = 0.0;
        var xarajat = 0.0;
        for (final o in orders) {
          if (_isDoneOrder(o)) {
            mahsulot += o.total.toDouble();
            xarajat += o.expensesTotal;
            continue;
          }
          final mine = provider.canSeedOrder(o);
          for (final item in o.items) {
            // O'chirilgan item summaga kirmaydi.
            if (item.deleted) continue;
            if (item.itemType.isEmpty) {
              mahsulot +=
                  provider.getItemPrice(o.id, item.productId)?.subtotal ??
                      item.subtotal;
            } else if (!mine) {
              if (item.isRasxod) {
                xarajat += item.subtotal;
              } else {
                mahsulot += item.subtotal;
              }
            }
          }
          if (mine) {
            mahsulot += provider.addedProductsTotal(o.id);
            xarajat += provider.addedExpensesTotal(o.id);
          }
        }
        final grandTotal = mahsulot + xarajat;

        // Bitta buyurtma bo'lsa vaqt chizig'i shart emas; ikki va undan ko'p
        // bo'lsa har guruh alohida ko'rinadi (itemlar JAMLANMAYDI).
        final showBatchLabels = orders.length > 1;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: allDone
                ? Border.all(color: const Color(0xFF4CAF50), width: 1)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Jadval sarlavhasi (ustun nomlari).
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Expanded(
                      flex: _nameFlex,
                      child: Text(
                        'Mahsulot',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      flex: _qtyFlex,
                      child: Text(
                        'Soni',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      flex: _sumFlex,
                      child: Text(
                        'Jami summa',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Har buyurtma itemlari alohida qator bo'lib ketma-ket chiqadi.
              for (final order in orders) ...[
                if (showBatchLabels) _batchLabel(order),
                ...orderItemSeq(
                  order.items.where((i) =>
                      _isDoneOrder(order) ? !i.isRasxod : i.itemType.isEmpty),
                  isProche: (i) => i.isProche,
                ).map((item) => _itemRow(provider, order, item)),
                // Begona (boshqa yuk user boshlagan) ochiq buyurtmaning
                // serverdagi proche itemlari — read-only, real-time.
                if (!_isDoneOrder(order) && !provider.canSeedOrder(order))
                  ...order.items.where((i) => i.isProche).map(_remoteProcheRow),
                if (!_isDoneOrder(order))
                  ...provider
                      .addedItemsFor(order.id)
                      .asMap()
                      .entries
                      .where((e) => e.value.isProche)
                      .map((e) =>
                          _addedProcheRow(provider, order.id, e.key, e.value)),
              ],
              // Qo'shimcha mahsulot / xarajat qo'shish tugmalari.
              if (anchor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAddEntrySheet(anchor.id, rasxod: false),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Mahsulot qo\'shish',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accentColor,
                            side: const BorderSide(color: _accentColor),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showAddEntrySheet(anchor.id, rasxod: true),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Xarajat qo\'shish',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF8D6E63),
                            side: const BorderSide(color: Color(0xFF8D6E63)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Xarajatlar (rasxod) bloki — Jami'dan oldin.
              _buildRasxodBlock(provider, orders),
              const Divider(height: 18),
              // Achot yakuni: Mahsulot / Xarajat (bo'lsa) / Jami.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mahsulot:',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  Text(
                    '${_formatMoney(mahsulot)} so\'m',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              if (xarajat > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Xarajat:',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    Text(
                      '${_formatMoney(xarajat)} so\'m',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Jami:',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  Text(
                    '${_formatMoney(grandTotal)} so\'m',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Yuborish tugmasi tepasida rasm/video biriktirish joyi.
              if (!allDone)
                _buildAttachmentsEditor(provider, pending, anchor)
              else
                _buildAttachmentsViewer(orders),
              // Bosilgan rasm ro'yxat ostida shu yerda ochiladi.
              _buildInlinePreview(),
              // Achot yopilgan bo'lsa "Yuborilgan" belgisi va (30 soniya
              // ichida) "Qaytarib olish"; aks holda bitta "Yuborish".
              if (allDone)
                Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle,
                              size: 18, color: Color(0xFF2E7D32)),
                          SizedBox(width: 6),
                          Text(
                            'Yuborilgan — achot yopildi',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (undoLeft > 0) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: reverting
                              ? null
                              : () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final ok = await provider
                                      .revertAllForSklad(widget.skladId);
                                  if (ok) {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Qaytarib olindi'),
                                      ),
                                    );
                                  } else if (provider.errorMessage != null) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(provider.errorMessage!),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                          icon: reverting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFC62828),
                                  ),
                                )
                              : const Icon(Icons.undo, size: 18),
                          label: Text(
                            reverting
                                ? 'Qaytarilmoqda...'
                                : 'Qaytarib olish ($undoLeft s)',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC62828),
                            side: const BorderSide(color: Color(0xFFC62828)),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (!hasAnyPrice || submitting)
                        ? null
                        : () => _confirmAndSubmit(provider, pending),
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, size: 18),
                    label: Text(submitting ? 'Yuborilmoqda...' : 'Yuborish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// Qo'shimcha yozuv (proche mahsulot / rasxod) qo'shish oynasidagi "Nomi"
// maydoni — qidiruvli (autocomplete). Yozilgan matn bo'yicha serverdan olingan
// takliflar filtrlanadi: katalogdagi mahsulot nomlari + ilgari yuk
// keltiruvchilar yozgan nomlar.
//
// Takliflar FAQAT qulaylik uchun: foydalanuvchi butunlay yangi nomni qo'lda
// yozaverishi mumkin va katalogga hech narsa qo'shilmaydi. Shu sababli
// takliflarni yuklashdagi xato jim yutiladi — maydon baribir ishlayveradi.
class _NameAutocompleteField extends StatefulWidget {
  const _NameAutocompleteField({
    required this.controller,
    required this.itemType,
    this.onSelected,
    this.onChanged,
  });

  // Oynaning mavjud nameController'i — nima yuborilishi o'zgarmaydi.
  final TextEditingController controller;
  // 'proche' — katalog + ilgarigi nomlar, 'rasxod' — faqat ilgarigi nomlar.
  final String itemType;
  // Taklif tanlanganda (katalog mahsuloti bo'lsa birligini olish uchun).
  final ValueChanged<ProcheNameSuggestion>? onSelected;
  // Matn o'zgarganda (oldingi narxni jonli ko'rsatish uchun).
  final ValueChanged<String>? onChanged;

  @override
  State<_NameAutocompleteField> createState() => _NameAutocompleteFieldState();
}

class _NameAutocompleteFieldState extends State<_NameAutocompleteField> {
  static const Color _accentColor = Color(0xFFC5A97B);
  // Bir vaqtda ko'rsatiladigan takliflar soni.
  static const int _maxOptions = 8;

  final FocusNode _focusNode = FocusNode();
  final YukService _service = YukService();
  List<ProcheNameSuggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // Takliflar oyna ochilganda bir marta olinadi. Yuklanguncha (va xato bo'lsa
  // ham) maydon to'liq ishlaydi — shunchaki taklif chiqmaydi.
  Future<void> _loadSuggestions() async {
    try {
      final list = await _service.fetchProcheNames(itemType: widget.itemType);
      if (!mounted) return;
      setState(() => _suggestions = list);
    } catch (_) {
      // Jim o'tamiz: takliflarsiz ham qo'lda yozish ishlayveradi.
    }
  }

  // Registrga bog'liq bo'lmagan "contains" filtri. Matn bo'sh bo'lsa eng
  // ko'p ishlatilganlari chiqadi (ro'yxat serverda uses bo'yicha saralangan).
  Iterable<ProcheNameSuggestion> _filterOptions(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    final source = query.isEmpty
        ? _suggestions
        : _suggestions.where((s) => s.name.toLowerCase().contains(query));
    return source.take(_maxOptions);
  }

  // O'ng tomondagi kichik izoh: katalog mahsuloti bo'lsa birligi + "katalogda",
  // aks holda necha marta yozilgani.
  String _hintFor(ProcheNameSuggestion option) {
    if (option.inCatalog) {
      return option.type.isEmpty ? 'katalogda' : '${option.type} · katalogda';
    }
    return option.uses > 0 ? '${option.uses} marta' : '';
  }

  @override
  Widget build(BuildContext context) {
    // Takliflar ro'yxati maydon (ya'ni oyna) kengligiga moslanadi.
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<ProcheNameSuggestion>(
        textEditingController: widget.controller,
        focusNode: _focusNode,
        optionsBuilder: _filterOptions,
        // Tanlanganda nom AYNAN shu imloda maydonga tushadi — keyinchalik
        // nomlar bir-biriga mos tushishi uchun muhim.
        displayStringForOption: (option) => option.name,
        onSelected: (option) {
          _focusNode.unfocus();
          widget.onSelected?.call(option);
          widget.onChanged?.call(option.name);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
            TextField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.sentences,
          onChanged: widget.onChanged,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: 'Nomi',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _accentColor),
            ),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 240,
                  maxWidth: constraints.maxWidth,
                ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final hint = _hintFor(option);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (hint.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  hint,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
