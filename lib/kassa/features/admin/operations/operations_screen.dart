import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  Map<String, dynamic>? _summary;
  List<dynamic> _audits = [];
  List<dynamic> _backups = [];
  Map<String, dynamic> _backupStatus = {};
  bool _loading = true;
  bool _backupBusy = false;

  /// 0 — holat, 1 — audit, 2 — backup.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService().getOperationsSummary(),
        ApiService().getAuditLogs(),
        ApiService().getBackups(),
      ]);
      if (!mounted) return;
      final backupResult = results[2] as Map<String, dynamic>;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _audits = results[1] as List<dynamic>;
        _backups = backupResult['items'] as List<dynamic>? ?? [];
        _backupStatus = backupResult['status'] as Map<String, dynamic>? ?? {};
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  String _errorText(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return 'Ma’lumotni yuklab bo‘lmadi';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.success),
    );
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_errorText(error)),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  bool _recovering = false;

  /// Retseptlarni audit jurnalidan tiklash.
  ///
  /// NEGA KERAK: retsept saqlash `PUT /api/recipe` orqali ketadi va audit
  /// oraliq qatlami har bir bunday so'rovning TO'LIQ tanasini saqlaydi.
  /// Ya'ni kiritilgan retsept yo'qolib qolgan bo'lsa ham (boshqa serverga
  /// tushib ketgan, sync yetkazmagan) uni jurnaldan qaytarish mumkin.
  Future<void> _recoverRecipes() async {
    if (_recovering) return;
    setState(() => _recovering = true);
    try {
      // 1-qadam: faqat HISOBOT — hech narsa yozilmaydi.
      final report = await ApiService().recoverRecipes(apply: false);
      if (!mounted) return;
      final list = (report['recipes'] as List<dynamic>? ?? []);
      final missing = list.where((r) => r['state'] == 'missing').toList();
      final different = list.where((r) => r['state'] == 'different').toList();
      final total = report['in_audit_log'] ?? 0;

      if (missing.isEmpty && different.isEmpty) {
        _snack('Jurnalda $total ta retsept bor — hammasi joyida, '
            'tiklash kerak emas');
        return;
      }

      final names = missing
          .take(12)
          .map((r) => '• ${r['product_name'] ?? r['product_id']}')
          .join('\n');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Retseptlarni tiklash'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit jurnalida $total ta retsept topildi.'),
                const SizedBox(height: 8),
                Text('Bazada YO‘Q: ${missing.length} ta',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (names.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(names, style: const TextStyle(fontSize: 12)),
                  if (missing.length > 12)
                    Text('… va yana ${missing.length - 12} ta',
                        style: const TextStyle(fontSize: 12)),
                ],
                if (different.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Farq qilyapti: ${different.length} ta '
                      '(ular TEGILMAYDI)',
                      style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bekor')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('${missing.length} tasini tiklash'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      // 2-qadam: faqat YO'Q retseptlar tiklanadi (mavjudlari tegilmaydi).
      final applied = await ApiService().recoverRecipes(apply: true);
      if (!mounted) return;
      _snack('${applied['restored']} ta retsept tiklandi'
          '${(applied['skipped'] ?? 0) != 0 ? ", ${applied['skipped']} ta o‘tkazib yuborildi" : ""}');
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Widget _recipeRecoveryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Retseptlarni tiklash',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Yo‘qolgan retseptlarni audit jurnalidan qaytaradi'),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _recovering ? null : _recoverRecipes,
              icon: _recovering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded),
              label: const Text('Tekshirish'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await ApiService().createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shifrlangan backup yaratildi')),
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final filename = item['filename']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bazani tiklash'),
        content: Text(
          '$filename nusxasi keyingi backend restartida tiklansinmi?\n\n'
          'Hozirgi baza backupdagi holat bilan almashtiriladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Tiklashni rejalash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await ApiService().scheduleBackupRestore(filename);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tiklash tayyor'),
          content: Text(
            result['message']?.toString() ?? 'Backendni qayta ishga tushiring.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tushunarli'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  String _formatTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '—';
    return DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal());
  }

  String _formatBytes(dynamic raw) {
    final bytes = raw is num ? raw.toDouble() : 0;
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      subtitle: switch (_tab) {
        0 => 'Server holati va sync navbati',
        1 => 'Kim nima qilgani — amallar tarixi',
        _ => 'Bazaning zaxira nusxalari',
      },
      loading: _loading,
      onRefresh: _load,
      segments: const ['Holat', 'Audit', 'Backup'],
      segmentIndex: _tab,
      onSegmentChanged: (i) => setState(() => _tab = i),
      child: switch (_tab) {
        0 => _buildSummary(),
        1 => _buildAudit(),
        _ => _buildBackups(),
      },
    );
  }

  Widget _buildSummary() {
    final summary = _summary ?? {};
    final sync = summary['sync'] as Map<String, dynamic>? ?? {};
    final database = summary['database'] as Map<String, dynamic>? ?? {};
    final cards = [
      (
        'Faol buyurtmalar',
        summary['active_orders'] ?? 0,
        Icons.receipt_long_outlined,
        AppColors.info,
      ),
      (
        'Ochiq smena',
        summary['open_shifts'] ?? 0,
        Icons.schedule_rounded,
        AppColors.warning,
      ),
      (
        'Pishirilmoqda',
        summary['cooking'] ?? 0,
        Icons.bakery_dining_outlined,
        AppColors.primary,
      ),
      (
        'Kam ingredient',
        summary['low_ingredients'] ?? 0,
        Icons.inventory_2_outlined,
        AppColors.danger,
      ),
      (
        'Sync navbati',
        sync['pending'] ?? 0,
        Icons.sync_rounded,
        AppColors.info,
      ),
      (
        'Sync xatosi',
        sync['failed'] ?? 0,
        Icons.sync_problem_rounded,
        AppColors.danger,
      ),
    ];
    return ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          // Telefon ekraniga sig'sin: matnlar Expanded ichida —
          // «Uptime» uzun bo'lsa qisqartiriladi, chetiga chiqib ketmaydi.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  sync['connected'] == true
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: sync['connected'] == true
                      ? AppColors.success
                      : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sync['connected'] == true
                        ? 'Cloud sync ulangan'
                        : 'Offline rejim',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${((summary['uptime_seconds'] ?? 0) / 3600).toStringAsFixed(1)} soat',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 900
                  ? 3
                  : constraints.maxWidth > 520
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards
                    .map(
                      (card) => SizedBox(
                        width: width,
                        child: _MetricCard(
                          label: card.$1,
                          value: card.$2.toString(),
                          icon: card.$3,
                          color: card.$4,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('PostgreSQL ulanishlari'),
              subtitle: Text(
                'Jami: ${database['total_connections'] ?? 0} • '
                'Faol: ${database['acquired_connections'] ?? 0} • '
                'Bo‘sh: ${database['idle_connections'] ?? 0}',
              ),
            ),
          ),
        ],
    );
  }

  Widget _buildAudit() {
    if (_audits.isEmpty) {
      return const AdminEmpty(
        icon: Icons.history_toggle_off_rounded,
        title: 'Audit yozuvlari hali yo‘q',
        message: 'Xodimlarning muhim amallari (chek o‘chirish, narx '
            'o‘zgartirish) shu yerda qayd etiladi.',
        color: Color(0xFF7C3AED),
      );
    }
    return ListView.separated(
              padding: const EdgeInsets.only(top: 14, bottom: 28),
              itemCount: _audits.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _audits[index] as Map<String, dynamic>;
                final metadata =
                    item['metadata'] as Map<String, dynamic>? ?? {};
                final status = metadata['status'] ?? '';
                return Card(
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      child: Text(
                        (item['actor_name']?.toString().isNotEmpty == true)
                            ? item['actor_name'].toString()[0].toUpperCase()
                            : '?',
                      ),
                    ),
                    title: Text(
                      '${item['actor_name'] ?? 'Tizim'} • '
                      '${item['action']?.toString().toUpperCase()} '
                      '${item['entity_type']}',
                    ),
                    subtitle: Text(
                      '${_formatTime(item['created_at'])} • HTTP $status',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert({
                            'entity_id': item['entity_id'],
                            'request': item['request_data'],
                            'response': item['response_data'],
                            'ip': item['ip_address'],
                          }),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
    );
  }

  Widget _buildBackups() {
    final running = _backupStatus['running'] == true || _backupBusy;
    return ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shifrlangan PostgreSQL nusxasi',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text('Avtomatik saqlash va xavfsiz tiklash'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: running ? null : _createBackup,
                    icon: running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_to_drive_rounded),
                    label: const Text('Backup olish'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _recipeRecoveryCard(),
          const SizedBox(height: 8),
          if (_backups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 100),
              child: Center(child: Text('Hali backup yaratilmagan')),
            ),
          ..._backups.map((raw) {
            final item = raw as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.lock_outline_rounded),
                ),
                title: Text(item['filename']?.toString() ?? ''),
                subtitle: Text(
                  '${_formatBytes(item['size_bytes'])} • '
                  '${_formatTime(item['created_at'])}',
                ),
                trailing: OutlinedButton.icon(
                  onPressed: () => _restore(item),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Tiklash'),
                ),
              ),
            );
          }),
        ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
