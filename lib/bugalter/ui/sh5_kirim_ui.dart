// bugalter/ui/sh5_kirim_ui.dart — «SH5 kirim» ekrani (PLAN_KIRIM §6):
// bir kunning narxlangan bozor buyurtmalari Mone ↔ SH5 juftliklari bilan
// ko'rsatiladi, bugalter bog'lanmaganlarini bog'laydi va «SH5 ga yuborish»
// bilan «Приходная накладная» hujjatlarini navbatga qo'yadi.
//
// Bog'lanmagan mahsulot katta qizil «?» bo'lib ko'rinadi — bosilsa o'sha
// yerda tanlash dialogi ochiladi. Mahsulot SH5 lug'atida bo'lmasa «SH5'da
// yo'q — o'tkazib yuborish»: qator hujjatga qo'shilmaydi («o'tkazildi»),
// lekin yuborishga to'siq bo'lmaydi.
//
// Hujjatni SH5 da BRIDGE yaratadi (shu kompyuterda), shuning uchun yuborgandan
// keyin ekran 3 soniyada bir `docs?date=` ni so'raydi va statuslarni yangilaydi
// (hammasi done/error bo'lguncha yoki ekran yopilguncha).
//
// Ruxsat backendda: bugalter roli yoki admin — ekran rolni O'ZI tekshirmaydi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/bugalter/model/sh5_kirim_model.dart';
import 'package:uz_ai_dev/bugalter/services/sh5_kirim_service.dart';
import 'package:uz_ai_dev/bugalter/ui/sh5_kirim_goods_dialog.dart';
import 'package:uz_ai_dev/bugalter/ui/sh5_kirim_settings_ui.dart';
import 'package:uz_ai_dev/yuk/ui/widgets/yuk_day_cards.dart' show formatMoney;

// Hujjat statusini 3 s da bir so'rash oralig'i (PLAN_KIRIM §6).
const Duration _kPollInterval = Duration(seconds: 3);

class Sh5KirimUi extends StatefulWidget {
  const Sh5KirimUi({super.key});

  @override
  State<Sh5KirimUi> createState() => _Sh5KirimUiState();
}

class _Sh5KirimUiState extends State<Sh5KirimUi> {
  final Sh5KirimService _service = Sh5KirimService();

  // Standart sana — KECHA (Xilola hujjatni ertasi kuni kiritadi).
  late DateTime _date;
  Sh5KirimDay? _day;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  // Hozir bog'lanayotgan item kalitlari (qatorda spinner).
  final Set<String> _busyKeys = {};

  // Statuslarni yangilab turuvchi taymer (ekran yopilsa to'xtaydi).
  Timer? _poll;

  // Auth xatosi uchun dialog bir marta chiqsin (poll har 3 s da keladi).
  bool _authDialogShown = false;

  // So'nggi yuborishda hujjat yaratilmagan buyurtmalar (`skipped_orders`) —
  // sana almashsa tozalanadi.
  final Set<int> _skippedOrders = {};

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // ─────────────────────────── Yuklash ───────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await _service.getDay(_dateStr);
      if (!mounted) return;
      setState(() {
        _day = day;
        _loading = false;
      });
      _syncPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _skippedOrders.clear();
    });
    _poll?.cancel();
    await _load();
  }

  void _shiftDate(int days) {
    final next = _date.add(Duration(days: days));
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month, now.day))) return;
    setState(() {
      _date = next;
      _skippedOrders.clear();
    });
    _poll?.cancel();
    _load();
  }

  // ─────────────────────── Statuslarni kuzatish ───────────────────────

  // Navbatdagi/yuborilayotgan hujjat bo'lsa taymer ishlaydi, bo'lmasa
  // to'xtaydi (keraksiz so'rov yuborilmaydi).
  void _syncPoll() {
    final pending = _day?.hasPendingDocs ?? false;
    if (!pending) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    if (_poll != null) return;
    _poll = Timer.periodic(_kPollInterval, (_) => _pollDocs());
  }

  Future<void> _pollDocs() async {
    final date = _dateStr;
    try {
      final docs = await _service.getDocs(date);
      if (!mounted || date != _dateStr) return;
      final day = _day;
      if (day == null) return;
      setState(() => _day = day.withDocs(docs));
      _syncPoll();
      // SH5 login/parol xatosi — dialog qayta chiqadi (bir marta).
      final auth = docs.any((d) => d.isError && d.isAuthError);
      if (auth && !_authDialogShown) {
        _authDialogShown = true;
        final saved = await _askCredentials();
        if (!mounted) return;
        _authDialogShown = false;
        if (saved) await _retryErrored();
      }
    } catch (_) {
      // Tarmoq uzilishi — keyingi urinishda qayta so'raladi.
    }
  }

  // ─────────────────────────── Bog'lash ───────────────────────────

  Future<void> _openMapDialog(Sh5KirimItem item) async {
    final pick = await showSh5KirimGoodsDialog(
      context,
      item: item,
      service: _service,
    );
    if (pick == null || !mounted) return;
    setState(() => _busyKeys.add(item.key));
    try {
      if (pick.action == Sh5KirimPickAction.delete) {
        await _service.deleteMap(item.key);
        if (!mounted) return;
        rk7Snack(context, 'Bog\'lanish o\'chirildi');
      } else if (pick.action == Sh5KirimPickAction.skip) {
        // «SH5'da yo'q» — qator hujjatga qo'shilmaydi, ammo «?» ham qolmaydi.
        await _service.setMap(
          key: item.key,
          productId: item.productId,
          productName: item.name,
          skip: true,
        );
        if (!mounted) return;
        rk7Snack(context, 'O\'tkazib yuboriladi: ${item.name}');
      } else {
        await _service.setMap(
          key: item.key,
          productId: item.productId,
          productName: item.name,
          sh5Rid: pick.sh5Rid,
        );
        if (!mounted) return;
        rk7Snack(context, 'Bog\'landi: ${pick.sh5Name}');
      }
    } catch (e) {
      if (!mounted) return;
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    } finally {
      if (mounted) setState(() => _busyKeys.remove(item.key));
    }
    if (!mounted) return;
    await _load();
  }

  // ─────────────────────────── Yuborish ───────────────────────────

  // Yuborishga to'siq bo'lgan sabab (null — yuborsa bo'ladi).
  String? get _blockReason {
    final day = _day;
    if (day == null) return 'Ma\'lumot yuklanmadi';
    if (day.orders.isEmpty) return 'Bu kunda buyurtma yo\'q';
    if (!day.settingsOk || day.missingSklads.isNotEmpty) {
      return 'Sklad ↔ SH5 ombor sozlanmagan';
    }
    // Faqat «?» qolganda to'siq bo'ladi — o'tkazilganlar yuborishga xalaqit
    // qilmaydi (ular hujjatga qo'shilmaydi, xolos).
    if (day.unmappedCount > 0) {
      return '${day.unmappedCount} ta mahsulotda «?» — SH5 tovarini tanlang';
    }
    if (day.pendingOrders.isEmpty) {
      return day.orders.every((o) => o.allSkipped)
          ? 'Hamma qatorlar o\'tkazilgan — hujjat yaratilmaydi'
          : 'Hammasi SH5 ga yuborilgan';
    }
    return null;
  }

  Future<void> _send() async {
    final day = _day;
    if (day == null) return;
    final ids = day.pendingOrders.map((o) => o.id).toList(growable: false);
    if (ids.isEmpty) return;

    setState(() => _sending = true);
    try {
      var result = await _service.send(date: _dateStr, orderIds: ids);
      // 428 — SH5 login/parol bir marta so'raladi, keyin qayta yuboriladi.
      if (result.needCredentials) {
        if (!mounted) return;
        final saved = await _askCredentials();
        if (!mounted) return;
        if (!saved) {
          setState(() => _sending = false);
          return;
        }
        result = await _service.send(date: _dateStr, orderIds: ids);
      }
      if (!mounted) return;
      setState(() => _sending = false);
      if (result.unmapped.isNotEmpty) {
        rk7Snack(
          context,
          '${result.unmapped.length} ta mahsulot bog\'lanmagan — avval '
          'bog\'lang',
          error: true,
        );
        await _load();
        return;
      }
      if (result.needCredentials) {
        rk7Snack(context, result.message, error: true);
        return;
      }
      // Hamma qatori o'tkazilgan buyurtmalar uchun hujjat yaratilmaydi.
      if (result.skippedOrders.isNotEmpty) {
        setState(() => _skippedOrders.addAll(result.skippedOrders));
      }
      rk7Snack(
        context,
        [
          '${result.docs.length} ta hujjat navbatga qo\'yildi',
          if (result.skippedOrders.isNotEmpty)
            '${result.skippedOrders.length} ta buyurtma o\'tkazildi',
        ].join(' · '),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  // Bitta xato hujjatni qayta yuborish.
  Future<void> _retryDoc(Sh5KirimDoc doc) async {
    try {
      await _service.retryDoc(doc.id);
      if (!mounted) return;
      rk7Snack(context, 'Qayta yuborishga qo\'yildi');
      await _load();
    } catch (e) {
      if (!mounted) return;
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  // Login/parol yangilangach barcha xato hujjatlarni qayta navbatga qo'yish.
  Future<void> _retryErrored() async {
    final day = _day;
    if (day == null) return;
    for (final order in day.orders) {
      final doc = order.doc;
      if (doc != null && doc.isError) {
        try {
          await _service.retryDoc(doc.id);
        } catch (_) {
          // Bittasi bo'lmasa ham qolganlari urinib ko'riladi.
        }
      }
    }
    if (!mounted) return;
    await _load();
  }

  // SH5 login/parol dialogi. true — saqlandi.
  Future<bool> _askCredentials() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _Sh5CredentialsDialog(service: _service),
    );
    return saved == true;
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const Sh5KirimSettingsUi()),
    );
    if (!mounted) return;
    if (changed == true) await _load();
  }

  // ─────────────────────────── Ko'rinish ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kRk7Bg,
      appBar: AppBar(
        backgroundColor: kRk7Accent,
        foregroundColor: Colors.white,
        title: const Text('SH5 kirim'),
        actions: [
          IconButton(
            tooltip: 'Sozlamalar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _dateBar(),
          Expanded(
            child: RefreshIndicator(
              color: kRk7Accent,
              onRefresh: _load,
              child: _body(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _sendBar(),
    );
  }

  // Sana tanlash qatori: ‹ 13.09.2026 › (kelajakka o'tib bo'lmaydi).
  Widget _dateBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Oldingi kun',
            icon: const Icon(Icons.chevron_left),
            onPressed: _loading ? null : () => _shiftDate(-1),
          ),
          Expanded(
            child: InkWell(
              onTap: _loading ? null : _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: kRk7AccentDark),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd.MM.yyyy').format(_date),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: kRk7AccentDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Keyingi kun',
            icon: const Icon(Icons.chevron_right),
            onPressed: _loading ? null : () => _shiftDate(1),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _day == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _day == null) {
      return rk7ErrorState(_error!, onRetry: _load);
    }
    final day = _day;
    if (day == null || day.orders.isEmpty) {
      return rk7EmptyState(
        Icons.inbox_outlined,
        'Bu kunda narxlangan bozor buyurtmasi yo\'q',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        _summary(day),
        if (!day.settingsOk || day.missingSklads.isNotEmpty)
          _settingsWarning(day),
        for (final order in day.orders) _orderCard(order),
      ],
    );
  }

  // Xulosa: «14 buyurtma · 56 mahsulot» + «3 ta «?»» / «2 o'tkazildi».
  Widget _summary(Sh5KirimDay day) {
    final skipped = day.skippedTotal;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kRk7Accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${day.orders.length} buyurtma · ${day.itemCount} mahsulot',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (skipped > 0)
                rk7Badge('$skipped o\'tkazildi', color: Colors.grey.shade600),
              rk7Badge(
                day.unmappedCount == 0
                    ? 'hammasi bog\'langan'
                    : '${day.unmappedCount} ta «?»',
                color: day.unmappedCount == 0
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Sklad ↔ SH5 ombor sozlanmagan — yuborib bo'lmaydi.
  Widget _settingsWarning(Sh5KirimDay day) {
    final names = day.missingSklads
        .map((s) => s.skladName.isEmpty ? 'Sklad #${s.skladId}' : s.skladName)
        .join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: Colors.red.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Sklad ↔ SH5 ombor sozlanmagan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              names,
              style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Sozlamalarni ochish'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Buyurtma kartasi ───────────────────────

  Widget _orderCard(Sh5KirimOrder order) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: order.unmappedCount > 0
              ? Colors.red.shade200
              : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sarlavha: sklad → SH5 ombor, nomer va jami.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${order.skladName.isEmpty ? 'Sklad #${order.skladId}' : order.skladName}'
                    ' → ${order.depName.isEmpty ? 'ombor tanlanmagan' : order.depName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatMoney(order.total)} so\'m',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: kRk7AccentDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                order.numLabel,
                if (order.cntrName.isNotEmpty) order.cntrName,
                if (order.pricedByName.isNotEmpty)
                  'narxlagan: ${order.pricedByName}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                rk7Badge(
                  order.accepted ? 'qabul qilingan' : 'qabul qilinmagan',
                  color: order.accepted
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
                if (order.unmappedCount > 0)
                  rk7Badge('«?»: ${order.unmappedCount}',
                      color: Colors.red.shade700),
                if (order.skippedCount > 0)
                  rk7Badge('o\'tkazildi: ${order.skippedCount}',
                      color: Colors.grey.shade600),
              ],
            ),
            _skippedOrderNote(order),
            _docStatus(order),
            const Divider(height: 16),
            for (final item in order.items) _itemRow(item),
          ],
        ),
      ),
    );
  }

  // Hamma qatorlar «SH5'da yo'q» — bu buyurtmadan hujjat chiqmaydi
  // (`skipped_orders` yoki qatorlardan aniqlanadi).
  Widget _skippedOrderNote(Sh5KirimOrder order) {
    final skippedByServer = _skippedOrders.contains(order.id);
    if (!order.allSkipped && !skippedByServer) return const SizedBox.shrink();
    if (order.doc != null && !skippedByServer) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Hujjat yaratilmadi — hamma qatorlar o\'tkazilgan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // SH5 hujjat holati: queued / sending (spinner) / done «SH5 № …» /
  // error (qizil + «Qayta yuborish»). Hujjatga tushmagan qatorlar bo'lsa
  // ular kichik kulrang matnda ko'rsatiladi.
  Widget _docStatus(Sh5KirimOrder order) {
    final doc = order.doc;
    if (doc == null) return const SizedBox.shrink();
    final skippedNote = doc.skippedLabel;
    if (doc.isDone) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text(
                  doc.numLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            _skippedDocNote(skippedNote),
          ],
        ),
      );
    }
    if (doc.isError) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    doc.error.isEmpty ? 'SH5 xatosi' : doc.error,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            _skippedDocNote(skippedNote),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _retryDoc(doc),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Qayta yuborish'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }
    // queued / sending — natija kutilyapti.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kRk7AccentDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                doc.isSending ? 'SH5 ga yuborilmoqda...' : 'Navbatda...',
                style: const TextStyle(fontSize: 12.5, color: kRk7AccentDark),
              ),
            ],
          ),
          _skippedDocNote(skippedNote),
        ],
      ),
    );
  }

  // Hujjatga qo'shilmagan qatorlar: «O'tkazildi: Сита, Ведро».
  Widget _skippedDocNote(String note) {
    if (note.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        note,
        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
      ),
    );
  }

  // ─────────────────────── Mahsulot qatori ───────────────────────

  Widget _itemRow(Sh5KirimItem item) {
    final map = item.map;
    final busy = _busyKeys.contains(item.key);
    final skipped = item.isSkipped;
    return InkWell(
      onTap: busy ? null : () => _openMapDialog(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chap: Mone nomi, miqdor va summa.
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: skipped ? Colors.grey.shade500 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (item.qtyDisplay.isNotEmpty) item.qtyDisplay,
                      '${formatMoney(item.subtotal)} so\'m',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // O'ng: SH5 tovari va manba belgisi.
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (item.unitWarning) ...[
                        Icon(Icons.warning_amber_rounded,
                            size: 14, color: Colors.red.shade700),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          skipped
                              ? 'SH5 ga yuborilmaydi'
                              : (map == null
                                  ? '—'
                                  : (map.sh5Name.isEmpty
                                      ? 'SH5 #${map.sh5Rid}'
                                      : map.sh5Name)),
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: item.isLinked
                                ? Colors.black87
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _sourceChip(item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Manba chipi: yashil «qo'lda», ko'k «tarixdan ×N», kulrang «o'tkazildi»
  // (bosilsa dialog qayta ochiladi), bog'lanmaganda — katta qizil «?».
  Widget _sourceChip(Sh5KirimItem item) {
    final map = item.map;
    if (map == null) return _unknownChip(item);
    if (map.isSkip) {
      return InkWell(
        onTap: () => _openMapDialog(item),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 13, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            rk7Badge('o\'tkazildi', color: Colors.grey.shade600),
          ],
        ),
      );
    }
    final unit = map.sh5UnitName.isEmpty ? '' : ' · ${map.sh5UnitName}';
    if (map.isLearned) {
      return rk7Badge(
        'tarixdan ×${map.confidence}$unit',
        color: Colors.blue.shade700,
      );
    }
    return rk7Badge('qo\'lda$unit', color: Colors.green.shade700);
  }

  // Bog'lanmagan mahsulot — katta «?»: bosilsa o'sha yerda tanlash dialogi
  // (takliflar + qidiruv + «SH5'da yo'q — o'tkazib yuborish»).
  Widget _unknownChip(Sh5KirimItem item) {
    return InkWell(
      onTap: () => _openMapDialog(item),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                shape: BoxShape.circle,
              ),
              child: const Text(
                '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'tanlang',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── Pastki «yuborish» paneli ───────────────────────

  Widget _sendBar() {
    if (_day == null) return const SizedBox.shrink();
    final reason = _blockReason;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kRk7AccentDark,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: (reason != null || _sending || _loading)
                    ? null
                    : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: const Text('SH5 ga yuborish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── SH5 login/parol dialogi ───────────────────────

// Bir marta kiritiladi va serverda shifrlangan holda saqlanadi — keyingi
// safar so'ralmaydi (hujjat SH5 da aynan shu foydalanuvchi nomidan yaratiladi).
class _Sh5CredentialsDialog extends StatefulWidget {
  final Sh5KirimService service;
  const _Sh5CredentialsDialog({required this.service});

  @override
  State<_Sh5CredentialsDialog> createState() => _Sh5CredentialsDialogState();
}

class _Sh5CredentialsDialogState extends State<_Sh5CredentialsDialog> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  // Avval saqlangan login bo'lsa maydonga qo'yiladi (parol qaytmaydi).
  Future<void> _loadUser() async {
    try {
      final creds = await widget.service.getCredentials();
      if (!mounted || creds.sh5User.isEmpty) return;
      setState(() {
        _user.text = creds.sh5User;
        if (creds.lastError.isNotEmpty && !creds.verified) {
          _error = creds.lastError;
        }
      });
    } catch (_) {
      // Dialog baribir ochiq qolsin — foydalanuvchi qo'lda kiritadi.
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Foydalanuvchi va parolni kiriting');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveCredentials(user: user, pass: pass);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text(
        'SH5 login/paroli',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _user,
            autofocus: true,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'SH5 foydalanuvchi',
              isDense: true,
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kRk7Accent, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            enabled: !_saving,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Parol',
              isDense: true,
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: kRk7Accent, width: 2),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bir marta kiritiladi, keyingi safar so\'ralmaydi. Hujjat SH5 da '
            'shu foydalanuvchi nomidan yaratiladi.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text(
            'Bekor qilish',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: kRk7Accent,
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
