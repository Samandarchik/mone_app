// core2/ui/sync_status_ui.dart — mone_core sinxron holati (SyncStatusUi,
// admin): GET /sync/status → karta: rol (dialer/acceptor/off), node_id,
// cloud_url, sozlangan/ulangan, navbat (pending/sent/acked/failed), oxirgi
// ack, peerlar ro'yxati, xato yozuvlar. Yangilash tugmasi. Shakl:
// internal/sync/admin.go (CoreSyncStatus).
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
            ? 'Serverda /sync/status yo\'q (${AppUrls.coreApi})'
            : err.display);
      }
    }
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: child,
      );

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
                      _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                s.role == 'off'
                                    ? Icons.sync_disabled
                                    : (s.connected ? Icons.sync : Icons.sync_problem),
                                color: s.role == 'off'
                                    ? Colors.grey
                                    : (s.connected ? Colors.green.shade700 : Colors.orange.shade800),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                s.role.isEmpty ? 'Noma\'lum' : s.role,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const Spacer(),
                              Text(
                                s.role == 'off'
                                    ? 'o\'chiq'
                                    : (s.connected ? 'ulangan' : 'ulanmagan'),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: s.connected ? Colors.green.shade700 : Colors.grey.shade700),
                              ),
                            ],
                          ),
                          const Divider(),
                          kv('Node', s.nodeId.isEmpty ? '—' : s.nodeId),
                          kv('Cloud URL', s.cloudUrl.isEmpty ? '—' : s.cloudUrl),
                          kv('Sozlangan', s.configured ? 'ha' : 'yo\'q'),
                          kv('Epoch', s.epoch.isEmpty ? '—' : s.epoch),
                          kv('ID offset', '${s.idOffset}'),
                          kv('Oxirgi ack',
                              s.lastAckAt.isEmpty || s.lastAckAt == 'null'
                                  ? '—'
                                  : coreDate(s.lastAckAt, withTime: true)),
                        ],
                      )),
                      _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Navbat', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          kv('Kutmoqda (pending)', '${s.pending}', bold: s.pending > 0),
                          kv('Yuborildi (sent)', '${s.sent}'),
                          kv('Tasdiqlandi (acked)', '${s.acked}'),
                          kv('Xato (failed)', '${s.failedCount}', bold: s.failedCount > 0),
                        ],
                      )),
                      _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Peerlar (${s.peers.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          if (s.peers.isEmpty)
                            Text('Peer yo\'q', style: TextStyle(color: Colors.grey.shade600)),
                          for (final p in s.peers)
                            kv(p.nodeId.isEmpty ? '—' : p.nodeId,
                                '${p.remote}${p.lastAckAt.isNotEmpty && p.lastAckAt != 'null' ? ' · ack: ${coreDate(p.lastAckAt, withTime: true)}' : ''}'),
                        ],
                      )),
                      if (s.failed.isNotEmpty)
                        _card(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Xato yozuvlar (${s.failed.length})',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                            const SizedBox(height: 6),
                            for (final f in s.failed)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${f['table'] ?? ''} ${f['op'] ?? ''} #${f['event_id'] ?? ''} '
                                  '(${f['retry_count'] ?? 0}x): ${f['error'] ?? ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        )),
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
