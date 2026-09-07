// core/widgets/server_settings_dialog.dart — server manzillarini sozlash
// dialogi (showServerSettingsDialog): v1 backend `base_url` va mone_core
// `core_url` kiritiladi («localhost:1020», IP yoki domen — sxema o'zi
// qo'shiladi), «Tekshirish» yadroning /api/v2/health'ini va v1 serverni
// so'raydi, «Saqlash» ServerConfig'ga yozadi. Login ekranidagi ⚙ tugma,
// admin menyusi va «Ombor 2.0» hub'i shu dialogni ochadi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/config/server_config.dart';

/// Dialogni ochadi; saqlansa `true` qaytaradi.
Future<bool> showServerSettingsDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _ServerSettingsDialog(),
  );
  return saved == true;
}

class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late final TextEditingController _base =
      TextEditingController(text: ServerConfig.baseUrl);
  late final TextEditingController _core =
      TextEditingController(text: ServerConfig.coreUrl);

  bool _checking = false;
  HealthResult? _coreRes;
  HealthResult? _baseRes;

  @override
  void dispose() {
    _base.dispose();
    _core.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _coreRes = null;
      _baseRes = null;
    });
    final results = await Future.wait([
      ServerConfig.checkCore(_core.text),
      ServerConfig.checkBase(_base.text),
    ]);
    if (!mounted) return;
    setState(() {
      _coreRes = results[0];
      _baseRes = results[1];
      _checking = false;
    });
  }

  Future<void> _save() async {
    await ServerConfig.save(baseUrl: _base.text, coreUrl: _core.text);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _status(String label, HealthResult? r) {
    if (r == null) return const SizedBox.shrink();
    final color = r.ok ? Colors.green.shade700 : Colors.red.shade700;
    final text = r.ok
        ? '$label: ulandi${r.node.isNotEmpty ? ' (${r.node})' : ''}'
        : '$label: ulanmadi — ${r.error}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(r.ok ? Icons.check_circle : Icons.error_outline,
              size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.dns_outlined, color: Colors.blueGrey),
          SizedBox(width: 8),
          Text('Server sozlamalari'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _base,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Mone server (v1)',
                hintText: 'moneapp.monebakeryuz.uz yoki 192.168.1.5:1010',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _core,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Ombor yadrosi (v2, mone_core)',
                hintText: 'localhost:1020 yoki 192.168.1.5:1020',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sxema yozilmasa: localhost/IP → http, domen → https.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            _status('v1', _baseRes),
            _status('v2', _coreRes),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 18),
                  label: const Text('Tekshirish'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    _base.text = ServerConfig.defaultBaseUrl;
                    _core.text = ServerConfig.defaultCoreUrl;
                  },
                  child: const Text('Default'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Bekor'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Saqlash'),
        ),
      ],
    );
  }
}
