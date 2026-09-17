// core2/ui/core_home_ui.dart — «Bugun» bosh sahifa (PLAN_UI_OSON §2.1).
// Oddiy xodim (omborchi, bozorchi, kassir) shu ekrandan boshlaydi: vazifa
// plitkalari (Kirim · Ko'chirish · Sanash · Hisobdan chiqarish · Ishlab
// chiqarish · Qoldiq — faqat RUXSATI borlari), «Kutilmoqda» (menga kelayotgan
// ko'chirishlar + tugallanmagan qoralamalarim), «Bugungi hujjatlar» (oxirgi
// 10 ta) va bugalter/admin uchun «Nazorat» qatori (SH5 solishtiruv %,
// defitsit, «Boshqaruv» → eski CoreHubUi).
//
// CoreEntryMenu shu ekranga olib kiradi; eski hub «Boshqaruv» tugmasi ortida.
// Ombor tanlovi SharedPreferences'da saqlanadi (`core_home_sklad`).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core2/core_format.dart';
import 'package:uz_ai_dev/core2/core_labels.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_report.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_doc_service.dart';
import 'package:uz_ai_dev/core2/services/core_stock_service.dart';
import 'package:uz_ai_dev/core2/ui/core_hub_ui.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/docs_list_ui.dart';
import 'package:uz_ai_dev/core2/ui/inventory_count_ui.dart';
import 'package:uz_ai_dev/core2/ui/quick_doc_ui.dart';
import 'package:uz_ai_dev/core2/ui/sh5_compare_ui.dart';
import 'package:uz_ai_dev/core2/ui/stock_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class CoreHomeUi extends StatelessWidget {
  const CoreHomeUi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Bugun',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Server sozlamalari',
            onPressed: () async {
              final saved = await showServerSettingsDialog(context);
              if (saved && context.mounted) context.read<CoreSession>().retry();
            },
            icon: const Icon(Icons.dns_outlined),
          ),
        ],
      ),
      body: const CoreConnectGate(child: _HomeBody()),
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody();

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  static const String _kSkladPref = 'core_home_sklad';

  final CoreDocService _docs = CoreDocService();
  final CoreStockService _stock = CoreStockService();

  int? _sklad;
  bool _loading = false;
  String? _error;
  bool _initDone = false;

  List<CoreDoc> _incoming = const [];
  List<CoreDoc> _drafts = const [];
  List<CoreDoc> _today = const [];
  CoreSh5Compare? _sh5;
  String? _sh5Error;
  int? _deficit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;
    _restoreSklad();
  }

  Future<void> _restoreSklad() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final dict = context.read<CoreDictProvider>();
    final user = context.read<CoreSession>().user;
    final saved = prefs.getInt(_kSkladPref);
    final ids = dict.activeSklads.map((s) => s.id).toSet();
    int? pick;
    if (saved != null && ids.contains(saved)) {
      pick = saved;
    } else if (user != null && user.sklads.isNotEmpty) {
      pick = user.sklads.first;
    } else if (dict.activeSklads.length == 1) {
      pick = dict.activeSklads.first.id;
    }
    setState(() => _sklad = pick);
    _load();
  }

  Future<void> _setSklad(int id) async {
    setState(() => _sklad = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSkladPref, id);
    _load();
  }

  Future<void> _load() async {
    final session = context.read<CoreSession>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drafts = await _docs.list(
        status: CoreDocStatus.draft,
        sklad: _sklad,
        limit: 50,
      );
      final today = await _docs.list(
        dateFrom: coreToday(),
        dateTo: coreToday(),
        sklad: _sklad,
        limit: 10,
      );
      if (!mounted) return;
      final incoming = <CoreDoc>[];
      final mine = <CoreDoc>[];
      for (final d in drafts.items) {
        final toMe = d.type == CoreDocType.transfer &&
            _sklad != null &&
            d.toSklad == _sklad &&
            d.fromSklad != _sklad;
        (toMe ? incoming : mine).add(d);
      }
      setState(() {
        _incoming = incoming;
        _drafts = mine;
        _today = today.items;
      });
    } catch (e) {
      if (mounted) setState(() => _error = coreErrorUz(e).text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (session.has(CorePerms.reportView)) _loadControl();
  }

  /// Nazorat qatori: SH5 solishtiruv (kechagi kun) va defitsit soni.
  Future<void> _loadControl() async {
    try {
      final r = await _stock.sh5Compare(date: coreDaysAgo(1));
      if (mounted) {
        setState(() {
          _sh5 = r;
          _sh5Error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _sh5Error = coreErrorUz(e).title);
    }
    try {
      final d = await _stock.deficit(
          dateFrom: coreDaysAgo(7), dateTo: coreToday(), skladId: _sklad);
      if (mounted) setState(() => _deficit = d.length);
    } catch (_) {/* hisobot yo'q — qator ko'rsatilmaydi */}
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    final wide = MediaQuery.of(context).size.width >= kWideBreakpoint;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _greeting(session),
          const SizedBox(height: 10),
          _tasks(session, wide: wide),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _errorCard(),
          ],
          if (_incoming.isNotEmpty || _drafts.isNotEmpty) ...[
            const SizedBox(height: 14),
            _pending(),
          ],
          const SizedBox(height: 14),
          _todayDocs(),
          if (session.has(CorePerms.reportView) ||
              session.has(CorePerms.usersManage) ||
              session.has(CorePerms.dictEdit)) ...[
            const SizedBox(height: 14),
            _control(session),
          ],
        ],
      ),
    );
  }

  // ───────────────────────────── Tepa ─────────────────────────────

  Widget _greeting(CoreSession session) {
    final dict = context.watch<CoreDictProvider>();
    final user = session.user;
    final allowed = user?.sklads ?? const <int>[];
    final sklads = dict.activeSklads
        .where((s) => allowed.isEmpty || allowed.contains(s.id))
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${coreGreetingUz()}${user == null || user.name.isEmpty ? '' : ', ${user.name}'}!',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              if (_loading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Yangilash',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          Text(coreDateUz(coreToday()),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          if (sklads.length > 1 || _sklad == null) ...[
            const SizedBox(height: 8),
            _skladPicker(sklads),
          ] else if (_sklad != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.warehouse_outlined,
                      size: 15, color: Colors.grey.shade700),
                  const SizedBox(width: 5),
                  Text(dict.skladName(_sklad),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _skladPicker(List<CoreSklad> sklads) {
    return InkWell(
      onTap: () async {
        final id = await showModalBottomSheet<int>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => _SkladSheet(sklads: sklads, current: _sklad),
        );
        if (id != null) _setSklad(id);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: kCoreBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _sklad == null ? Colors.orange.shade400 : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.warehouse_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _sklad == null
                    ? 'Omborni tanlang'
                    : context.read<CoreDictProvider>().skladName(_sklad),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Amallar to'ri ───────────────────────────

  Widget _tasks(CoreSession session, {required bool wide}) {
    final items = coreTasks.where((t) => _taskVisible(session, t)).toList();
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: wide ? 3 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [for (final t in items) _taskTile(t)],
    );
  }

  bool _taskVisible(CoreSession session, CoreTask t) {
    if (t.key == CoreDocType.production) {
      return session.canCreate(CoreDocType.production) ||
          session.canCreate(CoreDocType.act);
    }
    return session.has(t.perm);
  }

  Widget _taskTile(CoreTask t) {
    return Material(
      color: t.color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openTask(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(t.icon, size: 28, color: t.color),
              const Spacer(),
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: t.color)),
              Text(t.sh5,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  void _openTask(CoreTask t) {
    if (_sklad == null && t.key != coreTaskStock) {
      showInfoUz(context, 'Avval omborni tanlang');
      return;
    }
    switch (t.key) {
      case coreTaskStock:
        _open(StockUi(initialSklad: _sklad));
        break;
      case CoreDocType.inventory:
        _open(InventoryCountUi(skladId: _sklad));
        break;
      default:
        _open(QuickDocUi(type: t.key, skladId: _sklad));
    }
  }

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_error!, style: const TextStyle(fontSize: 12.5))),
            TextButton(onPressed: _load, child: const Text('Qayta')),
          ],
        ),
      );

  // ───────────────────────────── Kutilmoqda ─────────────────────────────

  Widget _pending() {
    return _section(
      title: 'Kutilmoqda',
      badge: _incoming.length + _drafts.length,
      child: Column(
        children: [
          for (final d in _incoming) _pendingTile(d, incoming: true),
          for (final d in _drafts) _pendingTile(d, incoming: false),
        ],
      ),
    );
  }

  Widget _pendingTile(CoreDoc d, {required bool incoming}) {
    final dict = context.watch<CoreDictProvider>();
    final color = coreTypeColor(d.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: incoming ? Colors.blue.shade200 : Colors.grey.shade300),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(coreTypeIconUz(d.type), size: 17, color: color),
        ),
        title: Text(
          incoming
              ? '${dict.skladName(d.fromSklad)} dan keldi'
              : '${coreTypeUz(d.type)} · tugallanmagan',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${coreDayUz(d.docDate)} · № ${d.number.isEmpty ? d.id : d.number}'
          '${d.total > 0 ? ' · ${coreSumUz(d.total)}' : ''}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: incoming ? Colors.blue.shade700 : kCoreAccentDark,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => _openPending(d, incoming: incoming),
          child: Text(incoming ? 'Qabul qilish' : 'Davom',
              style: const TextStyle(fontSize: 12.5)),
        ),
      ),
    );
  }

  Future<void> _openPending(CoreDoc d, {required bool incoming}) async {
    // Ro'yxatdagi hujjatda qatorlar yo'q — to'liq nusxa olinadi.
    CoreDoc full = d;
    try {
      full = await _docs.get(d.id);
    } catch (e) {
      if (mounted) showErrorUz(context, e);
      return;
    }
    if (!mounted) return;
    if (d.type == CoreDocType.inventory) {
      // Inventar qoralamasi «Sanash» ekranida davom etadi (UI-2).
      await _open(InventoryCountUi(skladId: full.toSklad ?? _sklad, docId: full.id));
      return;
    }
    await _open(QuickDocUi(
      type: d.type,
      skladId: _sklad,
      draft: full,
      receiveMode: incoming,
    ));
  }

  // ──────────────────────── Bugungi hujjatlar ────────────────────────

  Widget _todayDocs() {
    return _section(
      title: 'Bugungi hujjatlar',
      trailing: TextButton(
        onPressed: () => _open(const DocsListUi()),
        child: const Text('Hammasi'),
      ),
      child: _today.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                _loading ? 'Yuklanmoqda…' : 'Bugun hali hujjat yo\'q',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            )
          : Column(children: [for (final d in _today) _docTile(d)]),
    );
  }

  Widget _docTile(CoreDoc d) {
    final dict = context.watch<CoreDictProvider>();
    final color = coreTypeColor(d.type);
    final route = [
      if (d.fromSklad != null) dict.skladName(d.fromSklad),
      if (d.toSklad != null) dict.skladName(d.toSklad),
      if (d.corrId != null) dict.corrName(d.corrId),
    ].join(' → ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(coreTypeIconUz(d.type), size: 17, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(coreTypeUz(d.type),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text(
              coreStatusUz(d.status),
              style: TextStyle(fontSize: 11.5, color: docStatusColor(d.status)),
            ),
          ],
        ),
        subtitle: Text(
          '$route${d.total > 0 ? ' · ${coreSumUz(d.total)}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        onTap: () => _open(DocDetailUi(docId: d.id, initial: d)),
      ),
    );
  }

  // ────────────────────────────── Nazorat ──────────────────────────────

  Widget _control(CoreSession session) {
    final sh5 = _sh5;
    final ok = sh5 != null && sh5.diffPct.abs() <= 0.5;
    return _section(
      title: 'Nazorat',
      child: Column(
        children: [
          if (session.has(CorePerms.reportView))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.compare_arrows,
                  color: sh5 == null
                      ? Colors.grey
                      : (ok ? Colors.green.shade700 : Colors.red.shade700)),
              title: const Text('SH5 solishtiruv',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text(
                sh5 == null
                    ? (_sh5Error ?? 'Hali hisoblanmagan')
                    : '${coreDateUz(sh5.date)} · farq ${coreNumUz(sh5.diffPct, maxFrac: 2)}% '
                        '(${sh5.diffRows}/${sh5.rows} qator)',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const Sh5CompareUi()),
            ),
          if (_deficit != null && _deficit! > 0)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.warning_amber, color: Colors.orange.shade800),
              title: const Text('Partiyasiz yechilgan (defitsit)',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text('Oxirgi 7 kunda $_deficit ta tovar',
                  style: const TextStyle(fontSize: 11.5)),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _open(const CoreHubUi()),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.grid_view, size: 18),
            label: const Text('Boshqaruv (eski ekranlar)'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Yordamchi ─────────────────────────────

  Widget _section({
    required String title,
    required Widget child,
    int badge = 0,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _SkladSheet extends StatefulWidget {
  final List<CoreSklad> sklads;
  final int? current;
  const _SkladSheet({required this.sklads, this.current});

  @override
  State<_SkladSheet> createState() => _SkladSheetState();
}

class _SkladSheetState extends State<_SkladSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = widget.sklads
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Ombor',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (widget.sklads.length > 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: coreInput('Qidirish',
                    suffix: const Icon(Icons.search, size: 18)),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = items[i];
                return ListTile(
                  dense: true,
                  title: Text(s.name),
                  trailing: s.id == widget.current
                      ? Icon(Icons.check, color: Colors.green.shade700)
                      : null,
                  onTap: () => Navigator.pop(context, s.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
