import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/ui_kit.dart';
import '../../../core/widgets/media_image.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

/// TELEGRAM KLIENTSKI BAZA — botga `/start` bosgan barcha odamlar.
///
/// Ikki bo'limcha:
///   «Mijozlar» — ro'yxat, filtrlar, CSV eksport uchun ma'lumot;
///   «Xabarlar» — yuborilgan ommaviy xabarlar va ularning borishi.
///
/// Xabar yuborishni bot ishlaydigan node (bulut) bajaradi: bu ekran uni
/// faqat navbatga qo'yadi va borishini kuzatib turadi.
class TgCustomersScreen extends StatefulWidget {
  const TgCustomersScreen({super.key});

  @override
  State<TgCustomersScreen> createState() => _TgCustomersScreenState();
}

/// Auditoriya — backenddagi nomlar bilan bir xil bo'lishi SHART.
class _Audience {
  final String key;
  final String label;
  final IconData icon;
  const _Audience(this.key, this.label, this.icon);
}

const _audiences = [
  _Audience('all', 'Hammasi', Icons.groups_2_rounded),
  _Audience('with_phone', 'Raqamli', Icons.phone_rounded),
  _Audience('no_phone', 'Raqamsiz', Icons.phone_disabled_rounded),
  _Audience('active_30', '30 kunda faol', Icons.bolt_rounded),
  _Audience('buyers', 'Xarid qilgan', Icons.shopping_bag_rounded),
];

class _TgCustomersScreenState extends State<TgCustomersScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _searchTimer;
  Timer? _pollTimer;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _broadcasts = [];
  Map<String, dynamic> _summary = {};

  /// Ro'yxat filtri — auditoriya kalitlari + `blocked`.
  String _filter = '';

  /// 0 — mijozlar, 1 — ommaviy xabarlar.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _pollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _api.getTgCustomers(search: _search.text, filter: _filter),
        _api.getTgBroadcasts(),
      ]);
      final data = Map<String, dynamic>.from(results[0] as Map);
      if (!mounted) return;
      setState(() {
        _items = _maps(data['items']);
        _summary = _map(data['summary']);
        _broadcasts = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
        _error = null;
      });
      _syncPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(error);
      });
    }
  }

  /// Xabar ketayotgan bo'lsa progress o'zi yangilanib tursin.
  void _syncPolling() {
    final busy = _broadcasts.any(
      (b) => b['status'] == 'pending' || b['status'] == 'sending',
    );
    if (busy && _pollTimer == null) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _load(quiet: true),
      );
    } else if (!busy) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _onSearch(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => _load(quiet: true),
    );
  }

  void _setFilter(String value) {
    setState(() => _filter = _filter == value ? '' : value);
    unawaited(_load(quiet: true));
  }

  Future<void> _compose() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => const _BroadcastDialog(),
    );
    if (sent != true) return;
    setState(() => _tab = 1);
    await _load(quiet: true);
  }

  Future<void> _cancelBroadcast(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xabarni to‘xtatish'),
        content: Text(
          'Hozirgacha ${_int(b['sent'])} kishiga yetdi — ularni qaytarib '
          'bo‘lmaydi. Qolganlariga yuborilmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('To‘xtatish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelTgBroadcast(_int(b['id']));
      await _load(quiet: true);
    } catch (error) {
      if (mounted) _snack(_errorText(error), error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'Telegram bazasi',
      icon: Icons.telegram_rounded,
      accent: const Color(0xFF229ED9),
      subtitle: _tab == 0
          ? '${_int(_summary['total'])} ta odam /start bosgan · '
                '${_int(_summary['reachable'])} tasiga xabar yetadi'
          : '${_broadcasts.length} ta ommaviy xabar',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: () => _load(quiet: true),
      searchController: _tab == 0 ? _search : null,
      onSearchChanged: _tab == 0 ? _onSearch : null,
      searchHint: 'Ism, @username yoki telefon…',
      segments: const ['Mijozlar', 'Xabarlar'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() => _tab = i),
      primaryAction: AdminAction(
        label: 'Xabar yuborish',
        icon: Icons.campaign_rounded,
        onPressed: _compose,
        color: const Color(0xFF229ED9),
      ),
      toolbar: _tab == 0 ? _toolbar() : null,
      child: _tab == 0 ? _buildList() : _buildBroadcasts(),
    );
  }

  Widget _toolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminStatsRow(
          items: [
            AdminStatData(
              label: 'JAMI',
              value: '${_int(_summary['total'])}',
              icon: Icons.groups_2_rounded,
              color: const Color(0xFF229ED9),
            ),
            AdminStatData(
              label: 'RAQAM QOLDIRGAN',
              value: '${_int(_summary['with_phone'])}',
              icon: Icons.phone_rounded,
              color: AppColors.success,
            ),
            AdminStatData(
              label: '30 KUNDA FAOL',
              value: '${_int(_summary['active_30'])}',
              icon: Icons.bolt_rounded,
              color: AppColors.warning,
            ),
            AdminStatData(
              label: 'TUG‘ILGAN KUNI BOR',
              value: '${_int(_summary['birthdays'])}',
              icon: Icons.cake_rounded,
              color: const Color(0xFFDB2777),
            ),
            AdminStatData(
              label: 'BLOKLAGAN',
              value: '${_int(_summary['blocked'])}',
              icon: Icons.block_rounded,
              color: AppColors.danger,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final a in _audiences.skip(1))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: KChip(
                    label: a.label,
                    icon: a.icon,
                    selected: _filter == a.key,
                    accent: const Color(0xFF229ED9),
                    onTap: () => _setFilter(a.key),
                  ),
                ),
              KChip(
                label: 'Bloklagan',
                icon: Icons.block_rounded,
                selected: _filter == 'blocked',
                accent: AppColors.danger,
                onTap: () => _setFilter('blocked'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_items.isEmpty) {
      return const AdminEmpty(
        icon: Icons.telegram_rounded,
        title: 'Hali hech kim /start bosmagan',
        message:
            'Stol QR kodi yoki bot havolasi orqali kirgan har bir odam shu '
            'ro‘yxatga tushadi.',
        color: Color(0xFF229ED9),
      );
    }
    return AdminList(
      children: [
        for (final c in _items)
          AdminTile(
            title: _text(c['name']).isEmpty ? 'Nomsiz' : _text(c['name']),
            subtitle: _subtitle(c),
            initials: _initials(_text(c['name'])),
            color: c['blocked'] == true
                ? AppColors.textFaint
                : const Color(0xFF229ED9),
            badge: c['blocked'] == true
                ? const StatusBadge(
                    label: 'Bloklagan',
                    color: AppColors.danger,
                    icon: Icons.block_rounded,
                  )
                : (_int(c['visit_count']) > 0
                      ? StatusBadge(
                          label: '${_int(c['visit_count'])} tashrif',
                          color: AppColors.success,
                        )
                      : null),
            trailing: _avatar(c),
            onTap: () => _openCustomer(c),
            menu: const [
              AdminMenuItem(
                value: 'telegram',
                label: 'Telegramda ochish',
                icon: Icons.telegram_rounded,
              ),
            ],
            onMenuSelected: (_) => _openTelegram(c),
          ),
      ],
    );
  }

  /// Avatar — bosilsa rasm to'liq ekranda ochiladi.
  Widget? _avatar(Map<String, dynamic> c) {
    final path = _text(c['photo_url']);
    if (path.isEmpty) return null;
    return Tooltip(
      message: 'Rasmni ochish',
      child: GestureDetector(
        onTap: () => showImageViewer(
          context,
          path,
          title: _text(c['name']),
        ),
        child: ClipOval(
          child: SizedBox(
            width: 34,
            height: 34,
            child: MediaImage(
              path: path,
              width: 34,
              height: 34,
              placeholder: const Icon(Icons.person, size: 18),
            ),
          ),
        ),
      ),
    );
  }

  /// Telegram profilini ochadi; ochib bo'lmasa ID nusxalanadi.
  Future<void> _openTelegram(Map<String, dynamic> c) async {
    final username = _text(c['username']);
    final id = _int(c['tg_user_id']);
    if (await openTelegramProfile(username: username, tgUserID: id)) return;
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: username.isEmpty ? '$id' : '@$username'));
    if (!mounted) return;
    _snack(
      username.isEmpty
          ? 'Bu mijozda username yo‘q — ID nusxalandi'
          : 'Telegram ochilmadi — @$username nusxalandi',
    );
  }

  String _subtitle(Map<String, dynamic> c) {
    final parts = <String>[];
    final username = _text(c['username']);
    if (username.isNotEmpty) parts.add('@$username');
    final phone = _text(c['phone']);
    parts.add(phone.isEmpty ? 'raqam yo‘q' : phone);
    final birthday = _text(c['birthday_label']);
    if (birthday.isNotEmpty) parts.add('🎂 $birthday');
    parts.add(_shortDate(c['created_at']));
    return parts.join(' · ');
  }

  Future<void> _openCustomer(Map<String, dynamic> c) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TgCustomerDialog(
        customer: c,
        onOpenTelegram: () => _openTelegram(c),
      ),
    );
  }

  Widget _buildBroadcasts() {
    if (_broadcasts.isEmpty) {
      return AdminEmpty(
        icon: Icons.campaign_rounded,
        title: 'Ommaviy xabar yuborilmagan',
        message:
            'Bazadagi ${_int(_summary['reachable'])} ta mijozga bittada '
            'e’lon, aksiya yoki yangilik yuborishingiz mumkin.',
        actionLabel: 'Xabar yozish',
        onAction: _compose,
        color: const Color(0xFF229ED9),
      );
    }
    return AdminList(
      children: [
        for (final b in _broadcasts)
          _BroadcastCard(
            data: b,
            onCancel: () => _cancelBroadcast(b),
          ),
      ],
    );
  }
}

// ============================================================
// Mijoz kartochkasi
// ============================================================

class _TgCustomerDialog extends StatelessWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onOpenTelegram;
  const _TgCustomerDialog({
    required this.customer,
    required this.onOpenTelegram,
  });

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final username = _text(c['username']);
    final photo = _text(c['photo_url']);
    final name = _text(c['name']).isEmpty ? 'Nomsiz' : _text(c['name']);
    return AlertDialog(
      title: Row(
        children: [
          // Rasm bosilsa to'liq ekranda ochiladi.
          GestureDetector(
            onTap: photo.isEmpty
                ? null
                : () => showImageViewer(context, photo, title: name),
            child: photo.isEmpty
                ? CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        const Color(0xFF229ED9).withValues(alpha: 0.12),
                    child: Text(
                      _initials(_text(c['name'])),
                      style: const TextStyle(
                        color: Color(0xFF229ED9),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ClipOval(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: MediaImage(path: photo, fit: BoxFit.cover),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(fontSize: 18)),
                if (username.isNotEmpty)
                  // Username — bosilsa telegram dasturida profil ochiladi.
                  InkWell(
                    onTap: onOpenTelegram,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.telegram_rounded,
                            size: 15,
                            color: Color(0xFF229ED9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '@$username',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF229ED9),
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF229ED9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KKeyValueRow(
              label: 'Telefon',
              value: _text(c['phone']).isEmpty ? '—' : _text(c['phone']),
            ),
            KKeyValueRow(label: 'Telegram ID', value: '${_int(c['tg_user_id'])}'),
            KKeyValueRow(
              label: 'Kirish yo‘li',
              value: _sourceLabel(_text(c['first_source'])),
            ),
            KKeyValueRow(
              label: 'Tug‘ilgan kuni',
              value: _text(c['birthday_label']).isEmpty
                  ? 'so‘ralmagan'
                  : _text(c['birthday_label']),
            ),
            KKeyValueRow(
              label: '/start bosgan',
              value: '${_int(c['start_count'])} marta',
            ),
            KKeyValueRow(label: 'Tashrif', value: '${_int(c['visit_count'])}'),
            KKeyValueRow(
              label: 'Jami xarid',
              value: _money(c['total_spent']),
            ),
            KKeyValueRow(
              label: 'Keshbek',
              value: _money(c['cashback_balance']),
            ),
            KKeyValueRow(
              label: 'Birinchi kirish',
              value: _shortDate(c['created_at']),
            ),
            KKeyValueRow(
              label: 'Oxirgi faollik',
              value: _shortDate(c['last_seen_at']),
            ),
            if (c['blocked'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: StatusBadge(
                  label: 'Botni bloklagan — xabar yetmaydi',
                  color: AppColors.danger,
                  icon: Icons.block_rounded,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Yopish'),
        ),
        FilledButton.icon(
          onPressed: onOpenTelegram,
          icon: const Icon(Icons.telegram_rounded, size: 18),
          label: const Text('Telegramda ochish'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF229ED9),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Ommaviy xabar kartasi
// ============================================================

class _BroadcastCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCancel;
  const _BroadcastCard({required this.data, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = _text(data['status']);
    final total = _int(data['total']);
    final sent = _int(data['sent']);
    final failed = _int(data['failed']);
    final blocked = _int(data['blocked']);
    final done = sent + failed + blocked;
    final running = status == 'pending' || status == 'sending';
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusBadge(status),
                const SizedBox(width: 8),
                Text(
                  _audienceLabel(_text(data['audience'])),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _shortDate(data['created_at']),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _text(data['text']).isEmpty ? '(faqat rasm)' : _text(data['text']),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: running && total > 0 ? progress : 1.0,
                minHeight: 6,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(
                  status == 'cancelled'
                      ? AppColors.textFaint
                      : const Color(0xFF229ED9),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _metric('✅ Yetdi', '$sent / $total', AppColors.success),
                if (blocked > 0)
                  _metric('🚫 Bloklagan', '$blocked', AppColors.textMuted),
                if (failed > 0)
                  _metric('⚠️ Xato', '$failed', AppColors.danger),
                if (_text(data['created_by']).isNotEmpty)
                  _metric('👤', _text(data['created_by']), AppColors.textMuted),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('To‘xtatish'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Text(
      '$label $value',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    );
  }

  /// Rejalashtirilgan vaqt (bo'lsa) — «Navbatda» o'rniga aynan vaqt
  /// ko'rsatiladi.
  DateTime? get scheduled {
    final raw = _text(data['scheduled_at']);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Widget _statusBadge(String status) {
    switch (status) {
      case 'pending':
        return StatusBadge(
          label: scheduled == null ? 'Navbatda' : _whenLabel(scheduled!),
          color: AppColors.warning,
          icon: Icons.schedule_rounded,
        );
      case 'sending':
        return const StatusBadge(
          label: 'Yuborilmoqda',
          color: Color(0xFF229ED9),
          icon: Icons.send_rounded,
        );
      case 'cancelled':
        return const StatusBadge(
          label: 'To‘xtatilgan',
          color: AppColors.textMuted,
          icon: Icons.stop_circle_outlined,
        );
      default:
        return const StatusBadge(
          label: 'Yuborildi',
          color: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
    }
  }
}

// ============================================================
// Xabar yozish oynasi
// ============================================================

class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog();

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final _api = ApiService();
  final _text = TextEditingController();
  final _btnText = TextEditingController();
  final _btnUrl = TextEditingController();

  /// Yuklangan rasmning server yo'li (`/uploads/broadcasts/...`).
  String _photoUrl = '';
  bool _uploading = false;

  /// Rejalashtirilgan vaqt. `null` — darhol yuboriladi.
  DateTime? _scheduledAt;

  String _audience = 'all';
  int _count = 0;
  int _eta = 0;
  bool _counting = true;
  bool _sending = false;
  bool _extras = false;

  /// Tasdiqlash oynasi ochiqmi. Bu vaqtda «Yuborish» yana bosilmasin —
  /// aks holda ikkita bir xil xabar navbatga tushib qolardi.
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCount());
  }

  @override
  void dispose() {
    _text.dispose();
    _btnText.dispose();
    _btnUrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    setState(() => _counting = true);
    try {
      final data = await _api.getTgBroadcastPreview(_audience);
      if (!mounted) return;
      setState(() {
        _count = _int(data['count']);
        _eta = _int(data['eta_seconds']);
        _counting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _counting = false);
    }
  }

  /// Rasmni tanlab serverga yuklaydi. Telegramga uni yuborish paytida
  /// bot ishlaydigan node yuklaydi — bu yerda faqat saqlanadi.
  Future<void> _pickPhoto() async {
    final path = await pickImagePath();
    if (path == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await _api.uploadTgBroadcastPhoto(path);
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = _errorText(error);
      });
    }
  }

  /// Vaqt tanlash: avval sana, keyin soat. Bekor qilinsa o'zgarmaydi.
  Future<void> _pickTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Qaysi kuni yuborilsin',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduledAt ?? now.add(const Duration(hours: 1)),
      ),
      helpText: 'Soat nechada',
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(now)) {
      setState(() => _error = 'Tanlangan vaqt o‘tib ketgan');
      return;
    }
    setState(() {
      _scheduledAt = picked;
      _error = null;
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty && _photoUrl.isEmpty) {
      setState(() => _error = 'Xabar matnini yozing');
      return;
    }
    if (_count == 0) {
      setState(() => _error = 'Bu auditoriyada hech kim yo‘q');
      return;
    }
    final when = _scheduledAt;
    setState(() => _confirming = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(when == null ? 'Yuborilsinmi?' : 'Rejalashtirilsinmi?'),
        content: Text(
          when == null
              ? 'Xabar $_count ta mijozga ketadi. Yuborilgan xabarni '
                    'qaytarib bo‘lmaydi.'
              : 'Xabar ${_whenLabel(when)} da $_count ta mijozga ketadi. '
                    'Vaqti kelgunicha bekor qilsangiz bo‘ladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF229ED9),
            ),
            child: Text(
              when == null ? 'Ha, $_count kishiga' : 'Rejalashtirish',
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (ok != true) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.sendTgBroadcast(
        text: text,
        audience: _audience,
        photoUrl: _photoUrl,
        buttonText: _btnText.text.trim(),
        buttonUrl: _btnUrl.text.trim(),
        scheduledAt: _scheduledAt,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _errorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.campaign_rounded, color: Color(0xFF229ED9)),
          SizedBox(width: 10),
          Text('Ommaviy xabar'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kimga',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _audiences)
                    KChip(
                      label: a.label,
                      icon: a.icon,
                      selected: _audience == a.key,
                      accent: const Color(0xFF229ED9),
                      onTap: () {
                        setState(() => _audience = a.key);
                        unawaited(_refreshCount());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF229ED9).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_alt_rounded,
                      size: 18,
                      color: Color(0xFF229ED9),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _counting
                            ? 'Hisoblanmoqda…'
                            : '$_count ta mijozga ketadi'
                                  '${_eta > 60 ? " · ~${(_eta / 60).ceil()} daqiqa" : ""}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B6E9E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                maxLines: 6,
                minLines: 4,
                autofocus: false,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Xabar matni',
                  hintText: 'Assalomu alaykum! Bugun…',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.code_rounded,
                    size: 14,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '<b>qalin</b>, <i>qiya</i>, <a href="...">havola</a> '
                      'ishlatsa bo‘ladi · ${_text.text.characters.length} belgi',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(() => _extras = !_extras),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _extras
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      Text(
                        _photoUrl.isEmpty
                            ? 'Rasm va tugma'
                            : 'Rasm va tugma · rasm tanlangan',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_extras) ...[
                _PhotoField(
                  photoUrl: _photoUrl,
                  uploading: _uploading,
                  onPick: _pickPhoto,
                  onClear: () => setState(() => _photoUrl = ''),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _btnText,
                        decoration: const InputDecoration(
                          labelText: 'Tugma matni',
                          hintText: 'Menyuni ochish',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _btnUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Tugma havolasi',
                          hintText: 'https://konak.uz',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Yuborish vaqti: darhol yoki tanlangan payt.
              InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _scheduledAt == null
                          ? AppColors.border
                          : const Color(0xFF229ED9),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _scheduledAt == null
                            ? Icons.bolt_rounded
                            : Icons.schedule_rounded,
                        size: 18,
                        color: _scheduledAt == null
                            ? AppColors.textMuted
                            : const Color(0xFF229ED9),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _scheduledAt == null
                              ? 'Darhol yuboriladi — vaqt tanlash'
                              : _whenLabel(_scheduledAt!),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _scheduledAt == null
                                ? AppColors.textMuted
                                : AppColors.text,
                          ),
                        ),
                      ),
                      if (_scheduledAt != null)
                        IconButton(
                          onPressed: () => setState(() => _scheduledAt = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Darhol yuborish',
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        FilledButton.icon(
          onPressed: _sending || _counting || _confirming ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(
            _sending
                ? 'Yuborilmoqda…'
                : (_scheduledAt == null ? 'Yuborish' : 'Rejalashtirish'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF229ED9),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Rasm tanlash maydoni
// ============================================================

/// Ommaviy xabar rasmi — havola yozish o'rniga tanlanadi.
///
/// Rasm serverga yuklanadi (`/uploads/broadcasts/...`), telegramga esa
/// yuborish paytida bot ishlaydigan node yuklaydi. Shu sababli bu yerda
/// tashqi (public) havola talab qilinmaydi.
class _PhotoField extends StatelessWidget {
  final String photoUrl;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _PhotoField({
    required this.photoUrl,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (uploading) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Rasm yuklanmoqda…'),
            ],
          ),
        ),
      );
    }

    if (photoUrl.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Rasm tanlash'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: const Color(0xFF229ED9),
          side: const BorderSide(color: AppColors.border),
        ),
      );
    }

    return Row(
      children: [
        GestureDetector(
          onTap: () => showImageViewer(context, photoUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 96,
              height: 96,
              child: MediaImage(path: photoUrl, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Rasm tanlandi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              const Text(
                'Xabar rasm + izoh bo‘lib ketadi (izoh 1024 belgigacha).',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    label: const Text('Almashtirish'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('O‘chirish'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Rasmni to'liq ko'rish
// ============================================================

/// Rasmni butun ekranda ochadi — barmoq bilan kattalashtirsa bo'ladi.
void showImageViewer(BuildContext context, String path, {String? title}) {
  if (path.isEmpty) return;
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Stack(
      children: [
        // Rasmdan tashqariga bosilsa yopiladi.
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // Rasm EKRANGA moslanadi: kattasi sig'adi, kichigi cho'ziladi.
        // (O'lchamsiz qoldirilsa katta rasm ekrandan chiqib ketardi.)
        Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: LayoutBuilder(
              builder: (context, constraints) => InteractiveViewer(
                maxScale: 5,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: MediaImage(
                    path: path,
                    fit: BoxFit.contain,
                    placeholder: const Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (title != null && title.isNotEmpty)
          Positioned(
            left: 24,
            right: 72,
            top: 20,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Positioned(
          right: 16,
          top: 12,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// Telegram profilini ochish
// ============================================================

/// Mijozning telegram profilini OCHADI.
///
/// Avval `tg://` — telegram dasturi o'rnatilgan bo'lsa to'g'ridan-to'g'ri
/// o'sha yerda ochiladi (brauzerdan sakrashsiz). Ishlamasa `t.me` havolasi
/// brauzerda ochiladi.
///
/// `username` bo'sh bo'lsa telegram ID ishlatiladi: `tg://user?id=` faqat
/// bot mijoz bilan suhbatlashgan hollarda ishlaydi, shuning uchun ID bilan
/// ochilmasa `false` qaytadi va chaqiruvchi ID ni nusxalashni taklif qiladi.
Future<bool> openTelegramProfile({
  required String username,
  required int tgUserID,
}) async {
  final tries = <String>[
    if (username.isNotEmpty) 'tg://resolve?domain=$username',
    if (username.isEmpty && tgUserID > 0) 'tg://user?id=$tgUserID',
    if (username.isNotEmpty) 'https://t.me/$username',
  ];
  for (final raw in tries) {
    final uri = Uri.parse(raw);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Keyingi variantni sinaymiz.
    }
  }
  return false;
}

// ============================================================
// Yordamchilar
// ============================================================

/// «bugun 18:00» / «ertaga 11:30» / «26.08 09:00» ko'rinishida.
String _whenLabel(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  final hm = '${_two(at.hour)}:${_two(at.minute)}';
  if (diff == 0) return 'bugun $hm';
  if (diff == 1) return 'ertaga $hm';
  return '${_two(at.day)}.${_two(at.month)} $hm';
}

String _audienceLabel(String key) {
  for (final a in _audiences) {
    if (a.key == key) return a.label;
  }
  return key;
}

String _sourceLabel(String source) {
  if (source.isEmpty) return '—';
  switch (source.toLowerCase()) {
    case 'bot':
    case 'menu':
    case 'menyu':
    case 'start':
    case 'konak':
    case 'qr':
      return 'Bot havolasi';
  }
  return 'Stol/kod: $source';
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

String _text(dynamic value) => value == null ? '' : '$value'.trim();

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
    : [];

String _money(dynamic value) {
  final n = _int(value);
  final digits = n.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '${n < 0 ? '-' : ''}$buffer so‘m';
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return (parts.first.characters.first + parts.elementAt(1).characters.first)
      .toUpperCase();
}

String _shortDate(dynamic value) {
  final raw = _text(value);
  if (raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final d = parsed.toLocal();
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'bugun ${_two(d.hour)}:${_two(d.minute)}';
  }
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _errorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) return '${data['message']}';
    if (data is Map && data['error'] != null) return '${data['error']}';
    return error.message ?? 'Tarmoq xatosi';
  }
  return '$error';
}
