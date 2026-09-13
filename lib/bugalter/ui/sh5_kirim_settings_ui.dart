// bugalter/ui/sh5_kirim_settings_ui.dart — «SH5 kirim» sozlamalari
// (PLAN_KIRIM §6): sklad ↔ SH5 ombor (Departs), manba ↔ kontragent (Corrs)
// va saqlangan SH5 login (ko'rsatish/o'chirish).
//
// Sklad ↔ ombor xaritasi to'ldirilmaguncha hujjat yuborib bo'lmaydi —
// kirim ekrani shu sabab qizil ogohlantirish ko'rsatadi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/ui/widgets/rk7_common.dart';
import 'package:uz_ai_dev/bugalter/model/sh5_kirim_model.dart';
import 'package:uz_ai_dev/bugalter/services/sh5_kirim_service.dart';

class Sh5KirimSettingsUi extends StatefulWidget {
  const Sh5KirimSettingsUi({super.key});

  @override
  State<Sh5KirimSettingsUi> createState() => _Sh5KirimSettingsUiState();
}

class _Sh5KirimSettingsUiState extends State<Sh5KirimSettingsUi> {
  final Sh5KirimService _service = Sh5KirimService();

  Sh5KirimSettings? _settings;
  Sh5KirimCredentials _creds = const Sh5KirimCredentials();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Tahrirlanayotgan tanlovlar: sklad_id → dep_rid, manba → cntr_rid.
  final Map<int, int> _depBySklad = {};
  final Map<String, int> _cntrBySource = {};

  // Sozlama o'zgardimi (orqaga qaytishda ekranni yangilash uchun).
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _service.getSettings();
      // Login/parol holati — sozlama yuklanmasa ham ekran ishlayversin.
      Sh5KirimCredentials creds = const Sh5KirimCredentials();
      try {
        creds = await _service.getCredentials();
      } catch (_) {
        // Cred holati ko'rsatish uchun — xatosi sozlamalarni buzmasin.
      }
      if (!mounted) return;
      _depBySklad
        ..clear()
        ..addEntries(settings.sklads.map((s) => MapEntry(s.skladId, s.depRid)));
      _cntrBySource
        ..clear()
        ..addEntries(
            settings.sources.map((s) => MapEntry(s.source, s.cntrRid)));
      setState(() {
        _settings = settings;
        _creds = creds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final settings = _settings;
    if (settings == null) return;
    setState(() => _saving = true);
    try {
      await _service.saveSettings(
        sklads: [
          for (final entry in _depBySklad.entries)
            Sh5KirimSkladMap(skladId: entry.key, depRid: entry.value),
        ],
        sources: [
          for (final entry in _cntrBySource.entries)
            Sh5KirimSourceMap(source: entry.key, cntrRid: entry.value),
        ],
      );
      if (!mounted) return;
      _dirty = true;
      setState(() => _saving = false);
      rk7Snack(context, 'Sozlamalar saqlandi');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  // Saqlangan SH5 login/parolini o'chirish — keyingi yuborishda qayta
  // so'raladi.
  Future<void> _deleteCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('SH5 login', style: TextStyle(fontSize: 15)),
        content: Text(
          '«${_creds.sh5User}» o\'chirilsinmi?\n'
          'Keyingi yuborishda login/parol qayta so\'raladi.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish',
                style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
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
    try {
      await _service.deleteCredentials();
      if (!mounted) return;
      setState(() => _creds = const Sh5KirimCredentials());
      rk7Snack(context, 'SH5 login o\'chirildi');
    } catch (e) {
      if (!mounted) return;
      rk7Snack(context, e.toString().replaceFirst('Exception: ', ''),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Sozlama saqlangan bo'lsa kirim ekrani qayta yuklasin.
        Navigator.pop(context, _dirty);
      },
      child: Scaffold(
        backgroundColor: kRk7Bg,
        appBar: AppBar(
          backgroundColor: kRk7Accent,
          foregroundColor: Colors.white,
          title: const Text('SH5 kirim sozlamalari'),
        ),
        body: _body(),
        bottomNavigationBar: _settings == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: kRk7AccentDark,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Saqlash'),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return rk7ErrorState(_error!, onRetry: _load);
    final settings = _settings;
    if (settings == null) {
      return rk7EmptyState(Icons.settings_outlined, 'Sozlama topilmadi');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _sectionTitle('Sklad → SH5 ombor'),
        _hint(
          'Har bir Mone skladiga SH5 ombori (Departs) biriktiriladi — '
          'hujjat aynan shu omborga kiradi.',
        ),
        if (settings.sklads.isEmpty)
          _hint('Sklad ro\'yxati bo\'sh')
        else
          for (final s in settings.sklads) _skladRow(settings, s),
        const SizedBox(height: 16),
        _sectionTitle('Manba → kontragent'),
        _hint(
          'Buyurtma manbasiga qarab hujjatning kontragenti (kimdan) '
          'tanlanadi. «Boshqa» — manba ko\'rsatilmagan buyurtmalar.',
        ),
        for (final source in kSh5KirimSources) _sourceRow(settings, source),
        const SizedBox(height: 16),
        _sectionTitle('SH5 login'),
        _credentialsCard(),
      ],
    );
  }

  // Sklad qatori: nom + SH5 ombor dropdown'i.
  Widget _skladRow(Sh5KirimSettings settings, Sh5KirimSkladMap sklad) {
    final current = _depBySklad[sklad.skladId] ?? 0;
    final rids = <int>[
      for (final d in settings.departs) d.rid,
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: current == 0 ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sklad.skladName.isEmpty
                  ? 'Sklad #${sklad.skladId}'
                  : sklad.skladName,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey('sklad-${sklad.skladId}-$current'),
              initialValue: current,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: 0, child: Text('Tanlanmagan')),
                // Sozlamada saqlangan rid lug'atda yo'q bo'lsa ham tanlov
                // yo'qolmasin (SH5 da ombor o'chirilgan bo'lishi mumkin).
                if (current != 0 && !rids.contains(current))
                  DropdownMenuItem(
                    value: current,
                    child: Text(sklad.depName.isEmpty
                        ? 'SH5 ombor #$current'
                        : sklad.depName),
                  ),
                for (final d in settings.departs)
                  DropdownMenuItem(value: d.rid, child: Text(d.name)),
              ],
              onChanged: (v) =>
                  setState(() => _depBySklad[sklad.skladId] = v ?? 0),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              decoration: const InputDecoration(
                labelText: 'SH5 ombori',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: kRk7Accent, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Manba qatori: nom + kontragent dropdown'i.
  Widget _sourceRow(Sh5KirimSettings settings, String source) {
    final current = _cntrBySource[source] ?? 0;
    final rids = <int>[for (final c in settings.corrs) c.rid];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sh5KirimSourceName(source),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey('source-$source-$current'),
              initialValue: current,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: 0, child: Text('Tanlanmagan')),
                if (current != 0 && !rids.contains(current))
                  DropdownMenuItem(
                    value: current,
                    child: Text('Kontragent #$current'),
                  ),
                for (final c in settings.corrs)
                  DropdownMenuItem(value: c.rid, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _cntrBySource[source] = v ?? 0),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              decoration: const InputDecoration(
                labelText: 'Kontragent',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: kRk7Accent, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Saqlangan SH5 foydalanuvchisi (parol hech qachon ko'rsatilmaydi).
  Widget _credentialsCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: Icon(
          _creds.has ? Icons.vpn_key : Icons.vpn_key_off_outlined,
          color: _creds.has ? kRk7AccentDark : Colors.grey,
        ),
        title: Text(
          _creds.has ? _creds.sh5User : 'Saqlanmagan',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          !_creds.has
              ? 'Birinchi yuborishda so\'raladi'
              : (_creds.verified
                  ? 'Tekshirilgan'
                  : (_creds.lastError.isEmpty
                      ? 'Hali tekshirilmagan'
                      : _creds.lastError)),
          style: TextStyle(
            fontSize: 11.5,
            color: _creds.has && !_creds.verified && _creds.lastError.isNotEmpty
                ? Colors.red.shade700
                : Colors.grey.shade600,
          ),
        ),
        trailing: !_creds.has
            ? null
            : IconButton(
                tooltip: 'O\'chirish',
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                onPressed: _deleteCredentials,
              ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(
          text,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      );
}
