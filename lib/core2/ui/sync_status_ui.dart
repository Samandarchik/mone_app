// core2/ui/sync_status_ui.dart — mone_core sinxron holati (SyncStatusUi,
// admin): GET /sync/status → oddiy karta (rol dialer/acceptor/off, peer,
// pending navbat soni, qo'shimcha maydonlar ro'yxat sifatida). Yangilash
// tugmasi. Endpoint shartnomada hali yo'q — 404 bo'lsa shuni yozadi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/core2/models/core_integration.dart';
import 'package:uz_ai_dev/core2/services/core_admin_service.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class SyncStatusUi extends StatefulWidget {
  const SyncStatusUi({super.key});

  @override
  State<SyncStatusUi> createState() => _SyncStatusUiState();
}

class _SyncStatusUiState extends State<SyncStatusUi> {
  final _service = CoreAdminService();
  CoreSyncStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _error = null;
    });
    try {
      final s = await _service.syncStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      final err = CoreClient.wrap(e);
      if (mounted) {
        setState(() => _error = err.status == 404
            ? 'Serverda /sync/status hali yo\'q (${AppUrls.coreApi})'
            : err.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Sinxron holati',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: CoreConnectGate(
        needDicts: false,
        child: _error != null
            ? CoreErrorView(message: _error!, onRetry: _load)
            : s == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  s.role == 'off' ? Icons.sync_disabled : Icons.sync,
                                  color: s.role == 'off' ? Colors.grey : kCoreAccentDark,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.role.isEmpty ? 'Noma\'lum' : s.role,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                            const Divider(),
                            kv('Rol', s.role.isEmpty ? '—' : s.role),
                            kv('Peer', s.peer.isEmpty ? '—' : s.peer),
                            kv('Navbatda (pending)', '${s.pending}',
                                bold: s.pending > 0),
                            for (final e in s.extra.entries)
                              kv(e.key, e.value?.toString() ?? '—'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manba: GET ${AppUrls.coreApi}/sync/status',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
      ),
    );
  }
}
