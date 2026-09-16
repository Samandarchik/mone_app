// bugalter/ui/bugalter_home_ui.dart — Bugalter roli bosh ekrani: BugalterHomeUi (BugalterProvider).
// Barcha skladlarning narxlangan/qabul buyurtmalari, "Hammasi" + har sklad tab, yuk keltiruvchi filtri.
// Qator bosilganda miqdor/summa tahrir dialogi (tarixi bilan), bosib turilganda o'chirish
// tasdiq dialogi (soft-delete); AppBar'da to'liq tahrirlar tarixi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uz_ai_dev/admin/model/audit_log_model.dart';
import 'package:uz_ai_dev/admin/ui/admin_production_stats_ui.dart';
import 'package:uz_ai_dev/bugalter/provider/bugalter_provider.dart';
import 'package:uz_ai_dev/bugalter/services/bugalter_service.dart';
import 'package:uz_ai_dev/bugalter/ui/bugalter_edits_ui.dart';
import 'package:uz_ai_dev/bugalter/ui/bugalter_production_ui.dart';
import 'package:uz_ai_dev/bugalter/ui/sh5_kirim_ui.dart';
import 'package:uz_ai_dev/bugalter/ui/widgets/edit_history.dart';
import 'package:uz_ai_dev/core/auth/session.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/utils/qty_units.dart';
import 'package:uz_ai_dev/core/widgets/order_period.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_entry_menu.dart';
import 'package:uz_ai_dev/yuk/models/yuk_order_model.dart';
import 'package:uz_ai_dev/yuk/ui/widgets/yuk_day_cards.dart';

// Kunlik kartalar (YukDayCard), guruhlash va sklad nomlari — yuk tarixi
// ekrani bilan UMUMIY: yuk/ui/widgets/yuk_day_cards.dart.

// Bugalter (hisobchi) roli uchun bosh ekran.
// Barcha skladlarning narxlangan/qabul qilingan buyurtmalari — mahsulotlar va
// xarajatlar (rasxod) bilan. "Hammasi" + har sklad uchun alohida tab.
class BugalterHomeUi extends StatefulWidget {
  const BugalterHomeUi({super.key});

  @override
  State<BugalterHomeUi> createState() => _BugalterHomeUiState();
}

class _BugalterHomeUiState extends State<BugalterHomeUi> {
  static const Color _bgColor = Color(0xFFFAF6F1);
  static const Color _accentColor = Color(0xFFC5A97B);

  // Tablar: null -> "Hammasi", keyin skladlar (SkladRegistry ro'yxati —
  // superadmin sklad qo'shsa/o'chirsa keyingi ochilishda o'zgaradi).
  List<int?> get _tabs => [null, ...kYukSkladNames.keys];

  // AppBar'dagi tugma bilan yoqiladi: buyurtmaga biriktirilgan
  // rasm/videolarni kartada ko'rsatish.
  bool _showImages = false;

  // Yuk keltiruvchi bo'yicha filtr (null -> hammasi). Buyurtma priced_by
  // maydoni bilan solishtiriladi.
  int? _selectedYukUserId;

  // Excel hisobot hozir yuklanmoqdami (AppBar tugmasida spinner uchun).
  bool _exporting = false;

  // Excel hisobot uchun alohida servis (provider'nikidan mustaqil).
  final BugalterService _exportService = BugalterService();

  // Excel hisobot: davr tanlanadi (standart — joriy oy boshi..bugun),
  // .xlsx fayl yuklab olinadi va share oynasi ochiladi.
  Future<void> _exportExcel() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: today,
      ),
    );
    if (range == null || !mounted) return;

    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _exportService.downloadExport(range.start, range.end);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        text: 'Mone Excel hisobot',
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BugalterProvider>().fetchOrders();
      // Tepadagi filtr chiplari uchun yuk keltiruvchilar ro'yxati.
      context.read<BugalterProvider>().fetchYukUsers();
    });
  }

  void _logout() {
    logoutAndClear(context);
  }

  // Mahsulot (yoki xarajat) qatori bosilganda: miqdor (eski APK'lardan
  // qolgan gram xatolari) va SUMMANI tuzatish dialogi. Har bir o'zgarish
  // serverda tahrirlar tarixiga yoziladi.
  void _openEditItemDialog(YukOrder order, YukOrderItem item) {
    showDialog(
      context: context,
      builder: (_) => _EditItemQtyDialog(
        order: order,
        item: item,
        provider: context.read<BugalterProvider>(),
      ),
    );
  }

  // Mahsulot (yoki xarajat) qatori BOSIB TURILGANDA: o'chirishni tasdiqlash
  // dialogi. Tasdiqlansa server itemni soft-delete qiladi (deleted=true,
  // miqdor/summa nolga qaytadi) va audit jurnaliga yozadi.
  Future<void> _confirmDeleteItem(YukOrder order, YukOrderItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          item.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '«${item.name}» o\'chirilsinmi?\n'
          'Miqdor va summa nolga qaytariladi.',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Bekor qilish',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<BugalterProvider>().deleteItem(
            orderId: order.id,
            productId: item.productId,
          );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Mahsulot o\'chirildi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _tabName(int? id) =>
      id == null ? 'Hammasi' : (kYukSkladNames[id] ?? 'Sklad $id');

  // Sklad tablari tepasidagi yuk keltiruvchi filtri: "Hammasi" + har bir
  // yuk keltiruvchi nomi. Tanlanganda buyurtmalar priced_by bo'yicha
  // filtrlanadi.
  Widget _buildYukUserChips() {
    return Consumer<BugalterProvider>(
      builder: (context, provider, _) {
        if (provider.yukUsers.isEmpty) return const SizedBox(height: 44);
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final entry in <int?, String>{
                null: 'Hammasi',
                for (final u in provider.yukUsers) u.id: u.name,
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _selectedYukUserId == entry.key,
                    onSelected: (_) =>
                        setState(() => _selectedYukUserId = entry.key),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selectedYukUserId == entry.key
                          ? Colors.white
                          : Colors.black54,
                    ),
                    selectedColor: _accentColor,
                    backgroundColor: Colors.white,
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: _selectedYukUserId == entry.key
                          ? _accentColor
                          : Colors.grey.shade300,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          title: const Text(
            'Bugalter',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            // Ombor 2.0 (mone_core) — hujjatlar/qoldiq/hub, perms bo'yicha.
            const CoreEntryMenu(),
            // Excel hisobot (.xlsx): davr tanlab yuklab olish va ulashish.
            _exporting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Excel hisobot',
                    onPressed: _exportExcel,
                    icon: const Icon(Icons.download),
                  ),
            // Yopiq buyurtmalar tarixi oynasi (30/90 kun / hammasi).
            Consumer<BugalterProvider>(
              builder: (context, provider, _) => OrderPeriodButton(
                value: provider.ordersPeriod,
                onChanged: (p) => provider.setOrdersPeriod(p),
              ),
            ),
            // SH5 kirim: bozor buyurtmalarini SH5 «Приходная накладная»
            // qilib yuborish (PLAN_KIRIM — bugalter/Xilola ekrani).
            IconButton(
              tooltip: 'SH5 kirim',
              onPressed: () => context.push(const Sh5KirimUi()),
              icon: const Icon(Icons.move_to_inbox_outlined),
            ),
            // Ishlab chiqarish buyurtmalari (o'chirish + status — faqat bugalter).
            IconButton(
              tooltip: 'Ishlab chiqarish',
              onPressed: () => context.push(const BugalterProductionUi()),
              icon: const Icon(Icons.factory_outlined),
            ),
            // Ishlab chiqarish statistikasi (backend bugalterga ham ochiq).
            IconButton(
              tooltip: 'Ishlab chiqarish statistikasi',
              onPressed: () => context.push(const AdminProductionStatsUi()),
              icon: const Icon(Icons.query_stats),
            ),
            // Tahrirlar tarixi: kim, qachon, qaysi mahsulotning sonini yoki
            // summasini o'zgartirgan (append-only, o'chirib bo'lmaydi).
            IconButton(
              tooltip: 'Tahrirlar tarixi',
              onPressed: () => context.push(const BugalterEditsUi()),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: _showImages
                  ? 'Rasmlarni yashirish'
                  : 'Rasmlarni ko\'rsatish',
              onPressed: () => setState(() => _showImages = !_showImages),
              icon: Icon(
                _showImages ? Icons.image : Icons.image_outlined,
                color: _showImages ? _accentColor : null,
              ),
            ),
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight + 44),
            child: Column(
              children: [
                _buildYukUserChips(),
                TabBar(
                  isScrollable: true,
                  labelColor: _accentColor,
                  unselectedLabelColor: Colors.black54,
                  indicatorColor: _accentColor,
                  tabs: _tabs.map((id) => Tab(text: _tabName(id))).toList(),
                ),
              ],
            ),
          ),
        ),
        body: Consumer<BugalterProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.orders.isEmpty) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }

            if (provider.errorMessage != null && provider.orders.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => provider.fetchOrders(),
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

            return TabBarView(
              children: _tabs.map((id) {
                var orders = provider.forSklad(id);
                // Yuk keltiruvchi filtri (tepadagi chiplar).
                if (_selectedYukUserId != null) {
                  orders = orders
                      .where((o) => o.pricedBy == _selectedYukUserId)
                      .toList();
                }
                // Buyurtmalar KUNLIK kartalarga jamlanadi (buyurtma IDlarisiz):
                // hech narsa ko'rsatmaydigan (bo'sh) buyurtmalar tashlanadi,
                // qolganlari lokal kalendar kuni bo'yicha guruhlanadi.
                final days = groupYukOrdersByDay(
                    orders.where(yukOrderContributes).toList());
                return RefreshIndicator(
                  color: _accentColor,
                  onRefresh: () => provider.fetchOrders(),
                  child: days.isEmpty
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
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: days.length + 1,
                          itemBuilder: (context, index) {
                            // Tepada tab bo'yicha qisqa yig'indi.
                            if (index == 0) {
                              return _TabSummary(orders: orders);
                            }
                            final day = days[index - 1];
                            return YukDayCard(
                              key: ValueKey(day.day),
                              day: day.day,
                              orders: day.orders,
                              showImages: _showImages,
                              // "Hammasi" tabida sklad almashganda kichik
                              // sklad nomi yorlig'i ko'rsatiladi.
                              showSkladLabels: id == null,
                              // Bugalter mahsulot qatorini bosib miqdorni
                              // (gram xatolarini) tuzatadi.
                              onEditItem: _openEditItemDialog,
                              // Bosib turilganda — o'chirish tasdig'i
                              // (soft-delete: miqdor/summa nolga qaytadi).
                              onDeleteItem: _confirmDeleteItem,
                            );
                          },
                        ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

// Bugalter uchun mahsulot miqdori va SUMMASINI tahrirlash dialogi.
// "Soni" (taken) va "Summa" (subtotal) tahrirlanadi; "Qabul qilingan (ombor)"
// maydoni FAQAT haqiqiy kamomad yozilgan itemda (accepted && received > 0 &&
// received != taken) ko'rsatiladi — aks holda received yuborilmaydi (server
// uni o'zi sinxronlaydi). Rasxod (xarajat) qatorida faqat "Summa" bo'ladi.
//
// Serverga FAQAT O'ZGARGAN maydonlar yuboriladi — shunda tahrirlar tarixiga
// (audit) o'zgarmagan maydon uchun soxta yozuv tushmaydi.
// Dialog pastida shu mahsulotning oldingi tahrirlari ko'rsatiladi.
class _EditItemQtyDialog extends StatefulWidget {
  final YukOrder order;
  final YukOrderItem item;
  final BugalterProvider provider;
  const _EditItemQtyDialog({
    required this.order,
    required this.item,
    required this.provider,
  });

  @override
  State<_EditItemQtyDialog> createState() => _EditItemQtyDialogState();
}

class _EditItemQtyDialogState extends State<_EditItemQtyDialog> {
  static const Color _accentColor = Color(0xFFC5A97B);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _takenController;
  late final TextEditingController _receivedController;
  late final TextEditingController _subtotalController;
  bool _saving = false;

  // Shu mahsulotning oldingi tahrirlari (GET /api/bugalter/edits).
  final BugalterService _service = BugalterService();
  List<AuditLogEntry>? _history;
  String? _historyError;

  // кг/л — kasr kiritish mumkin (kg -> BUTUN gr yuboriladi); boshqa
  // birliklar faqat butun son.
  bool get _isDecimal => qtyUnitFactor(widget.item.type) > 1;

  // Xarajat (rasxod) qatorida miqdor yo'q — faqat summasi tahrirlanadi.
  bool get _isRasxod => widget.item.isRasxod;

  // Faqat haqiqiy kamomad yozilgan itemda received alohida tahrirlanadi.
  bool get _showReceived =>
      !_isRasxod &&
      widget.item.accepted &&
      widget.item.received > 0 &&
      widget.item.received != widget.item.taken;

  @override
  void initState() {
    super.initState();
    _takenController = TextEditingController(
      text: formatQty(widget.item.taken, widget.item.type),
    );
    _receivedController = TextEditingController(
      text: formatQty(widget.item.received, widget.item.type),
    );
    _subtotalController = TextEditingController(
      text: formatMoneyInput(widget.item.subtotal),
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _takenController.dispose();
    _receivedController.dispose();
    _subtotalController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final list = await _service.fetchEdits(
        orderId: widget.order.id,
        productId: widget.item.productId,
        limit: 20,
      );
      if (!mounted) return;
      setState(() => _history = list);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString().replaceFirst('Exception: ', '');
        _history = const [];
      });
    }
  }

  // "1,5" -> 1.5. Parse bo'lmasa null.
  // Pul maydoni raqamlarni probel bilan guruhlaydi (200 000) — probellar
  // parse'dan oldin tashlanadi (miqdor maydonlariga ta'siri yo'q).
  double? _parse(String? text) {
    final t = (text ?? '').replaceAll(' ', '').trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _validate(String? text) {
    final v = _parse(text);
    if (v == null || v <= 0) return 'Miqdor 0 dan katta bo\'lishi kerak';
    return null;
  }

  // Summa — BUTUN so'm, manfiy bo'lmagan (0 — "olinmagan" qator).
  String? _validateMoney(String? text) {
    final v = _parse(text);
    if (v == null || v < 0) return 'Summani kiriting';
    return null;
  }

  // UI qiymatini API butun soniga o'girish (kg -> gr). Serverga hech qachon
  // kasr yuborilmaydi.
  num _toApi(String text) {
    num api = qtyFromUi(_parse(text)!, widget.item.type);
    if (api is double && api == api.roundToDouble()) api = api.toInt();
    return api;
  }

  // Kiritilgan summa (butun so'm).
  int get _enteredSubtotal => (_parse(_subtotalController.text) ?? 0).round();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // FAQAT o'zgargan maydonlar yuboriladi.
    final taken = _isRasxod ? null : _toApi(_takenController.text);
    final received = _showReceived ? _toApi(_receivedController.text) : null;
    final subtotal = _enteredSubtotal;

    final sendTaken = taken != null && taken != widget.item.taken ? taken : null;
    final sendReceived =
        received != null && received != widget.item.received ? received : null;
    final sendSubtotal =
        subtotal != widget.item.subtotal.round() ? subtotal : null;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (sendTaken == null && sendReceived == null && sendSubtotal == null) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('O\'zgarish yo\'q')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.provider.editItemQty(
        orderId: widget.order.id,
        productId: widget.item.productId,
        taken: sendTaken,
        received: sendReceived,
        subtotal: sendSubtotal,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(sendSubtotal != null && sendTaken == null
              ? 'Summa yangilandi'
              : 'Yangilandi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  InputDecoration _decoration(String label, {String? suffix}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix ?? widget.item.type,
        border: const OutlineInputBorder(),
      );

  List<TextInputFormatter> get _formatters => _isDecimal
      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
      : [FilteringTextInputFormatter.digitsOnly];

  // Kiritilayotgan summa va undan kelib chiqadigan dona narxi
  // ("63 000 so'm · Donasi: 42 000 so'm/кг") — faqat ko'rsatish uchun.
  Widget _moneyHint() {
    final subtotal = _enteredSubtotal;
    final takenUi = _isRasxod
        ? 0.0
        : qtyToUi(
            _parse(_takenController.text) == null
                ? widget.item.taken
                : _toApi(_takenController.text),
            widget.item.type,
          );
    final unit = takenUi > 0 && subtotal > 0
        ? ' · Donasi: ${formatMoney(subtotal / takenUi)} so\'m'
            '${(widget.item.type ?? '').isNotEmpty ? '/${widget.item.type}' : ''}'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${formatMoney(subtotal)} so\'m$unit',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  // Shu mahsulotning oldingi tahrirlari (bo'lsa).
  Widget _historySection() {
    final history = _history;
    if (history == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (history.isEmpty) {
      // Xato bo'lsa ham dialog ishlayveradi — faqat tarix ko'rinmaydi.
      if (_historyError != null) {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tarix yuklanmadi: $_historyError',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 22),
        Row(
          children: [
            Icon(Icons.history, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              'Tahrirlar tarixi (${history.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        for (final e in history) EditHistoryTile(entry: e, compact: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = (widget.item.type ?? '').trim();
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        type.isNotEmpty && !_isRasxod
            ? '${widget.item.name} ($type)'
            : widget.item.name,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isRasxod)
                TextFormField(
                  controller: _takenController,
                  autofocus: true,
                  enabled: !_saving,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: _isDecimal),
                  inputFormatters: _formatters,
                  decoration: _decoration('Soni'),
                  validator: _validate,
                  onChanged: (_) => setState(() {}),
                ),
              if (_showReceived) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _receivedController,
                  enabled: !_saving,
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: _isDecimal),
                  inputFormatters: _formatters,
                  decoration: _decoration('Qabul qilingan (ombor)'),
                  validator: _validate,
                ),
              ],
              if (!_isRasxod) const SizedBox(height: 12),
              // Summa — butun so'm (tiyin yo'q); yozayotganda har 3 xonadan
              // probel bilan guruhlanadi: 200 000.
              TextFormField(
                controller: _subtotalController,
                autofocus: _isRasxod,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                decoration: _decoration('Summa', suffix: 'so\'m'),
                validator: _validateMoney,
                onChanged: (_) => setState(() {}),
              ),
              _moneyHint(),
              _historySection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Bekor qilish',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }
}

// Tab tepasidagi yig'indi: shu tabdagi jami mahsulot va jami xarajat.
class _TabSummary extends StatelessWidget {
  final List<YukOrder> orders;
  const _TabSummary({required this.orders});

  static const Color _accent = Color(0xFFC5A97B);

  @override
  Widget build(BuildContext context) {
    double products = 0, expenses = 0;
    for (final o in orders) {
      products += o.total.toDouble();
      expenses += o.expensesTotal;
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mahsulot',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatMoney(products)} so\'m',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Xarajat',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatMoney(expenses)} so\'m',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
