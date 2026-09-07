// core2/ui/widgets/core_widgets.dart — «Ombor 2.0» ekranlari uchun umumiy
// vidjet/yordamchilar: ranglar (kCoreBg/kCoreAccent), CoreConnectGate
// (yadro ulanmagan bo'lsa «server ulanmagan» + qayta urinish + sozlama),
// coreStatusChip (hujjat holati rangli chip), docTypeIcon, coreMoney (butun
// so'm → «1 250 000»), CoreSkladDropdown / CoreCorrDropdown, pickDate,
// showCoreError (CoreApiException → SnackBar), showWarningsDialog (post
// javobidagi manfiy qoldiq ro'yxati), CoreErrorView (xato + qayta urinish).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/utils/money_input.dart';
import 'package:uz_ai_dev/core/widgets/server_settings_dialog.dart';
import 'package:uz_ai_dev/core2/models/core_dicts.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_qty.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_client.dart';

const Color kCoreBg = Color(0xFFFAF6F1);
const Color kCoreAccent = Color(0xFFC5A97B);
const Color kCoreAccentDark = Color(0xFF8A6F45);

/// Butun so'm → «1 250 000».
String coreMoney(num v) => formatMoneyInput(v);

/// "YYYY-MM-DD" → "dd.MM.yyyy"; RFC3339 bo'lsa vaqt bilan.
String coreDate(String? raw, {bool withTime = false}) {
  if (raw == null || raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final local = raw.length > 10 ? dt.toLocal() : dt;
  return DateFormat(withTime ? 'dd.MM.yyyy HH:mm' : 'dd.MM.yyyy').format(local);
}

String todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());
String isoOf(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Sana tanlash; [allowPast] false bo'lsa bugungidan oldingi kun tanlanmaydi
/// (doc.backdate ruxsati yo'q holat).
Future<String?> pickDate(BuildContext context, String current,
    {bool allowPast = true}) async {
  final now = DateTime.now();
  final initial = DateTime.tryParse(current) ?? now;
  final first = allowPast ? DateTime(now.year - 3) : DateTime(now.year, now.month, now.day);
  final picked = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(first) ? first : initial,
    firstDate: first,
    lastDate: DateTime(now.year + 1),
  );
  return picked == null ? null : isoOf(picked);
}

IconData docTypeIcon(String type) {
  switch (type) {
    case CoreDocType.receipt:
      return Icons.download_outlined;
    case CoreDocType.issue:
      return Icons.upload_outlined;
    case CoreDocType.transfer:
      return Icons.swap_horiz;
    case CoreDocType.production:
      return Icons.factory_outlined;
    case CoreDocType.act:
      return Icons.restaurant_menu;
    case CoreDocType.inventory:
      return Icons.fact_check_outlined;
    case CoreDocType.reserve:
      return Icons.bookmark_border;
    default:
      return Icons.description_outlined;
  }
}

Color docStatusColor(String status) {
  switch (status) {
    case CoreDocStatus.posted:
      return Colors.green.shade700;
    case CoreDocStatus.cancelled:
      return Colors.red.shade700;
    default:
      return Colors.orange.shade700;
  }
}

Widget coreStatusChip(String status) {
  final color = docStatusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      CoreDocStatus.title(status),
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// Xatoni SnackBar'da ko'rsatish (403 bo'lsa qaysi perm yetmagani bilan).
void showCoreError(BuildContext context, Object e) {
  final err = CoreClient.wrap(e);
  var msg = err.display;
  if (err.forbidden && err.perm.isNotEmpty) msg = '$msg (ruxsat: ${err.perm})';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: err.notImplemented ? Colors.orange.shade800 : Colors.red.shade700,
  ));
}

void showCoreInfo(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Post javobidagi ogohlantirishlar (manfiy qoldiq) — dialog.
Future<void> showWarningsDialog(
    BuildContext context, List<CoreDocWarning> warnings) async {
  if (warnings.isEmpty) return;
  final dict = context.read<CoreDictProvider>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.warning_amber, color: Colors.orange),
        SizedBox(width: 8),
        Expanded(child: Text('Ogohlantirish')),
      ]),
      content: SizedBox(
        width: 420,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: warnings.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (_, i) {
            final w = warnings[i];
            final good = dict.goodById(w.goodId);
            final name = w.goodName.isNotEmpty
                ? w.goodName
                : (good?.name ?? 'Tovar #${w.goodId}');
            final qtyText = good == null
                ? '${w.qty}'
                : coreFormatQtyUnit(w.qty, good.baseUnit);
            // negative_stock | no_batch | no_recipe | rounding
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                w.code == 'negative_stock' ? Icons.remove_circle_outline : Icons.info_outline,
                color: Colors.red.shade700,
              ),
              title: Text(name),
              subtitle: Text(
                '${dict.skladName(w.skladId)} · $qtyText${w.msg.isNotEmpty ? '\n${w.msg}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String body,
    {String okText = 'Ha', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: danger
              ? ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white)
              : null,
          child: Text(okText),
        ),
      ],
    ),
  );
  return r == true;
}

/// Xato + qayta urinish.
class CoreErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const CoreErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // 501 (ledger hali yo'q) — qizil xato emas, sariq «hali yoqilmagan».
    final notImpl = message.contains('not_implemented') ||
        message.contains('hali yoqmagan');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(notImpl ? Icons.construction : Icons.error_outline,
                color: notImpl ? Colors.orange.shade800 : Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                    backgroundColor: kCoreAccent, foregroundColor: Colors.white),
                child: const Text('Qayta urinish'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Yadro ulanmagan bo'lsa child o'rniga «server ulanmagan» ko'rsatadi;
/// ulangan bo'lsa lug'atlarni yuklab child'ni beradi.
class CoreConnectGate extends StatelessWidget {
  final Widget child;
  final bool needDicts;
  const CoreConnectGate({super.key, required this.child, this.needDicts = true});

  @override
  Widget build(BuildContext context) {
    final state = context.select<CoreSession, CoreConnState>((s) => s.state);
    final error = context.select<CoreSession, String?>((s) => s.error);
    if (state == CoreConnState.connecting) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state != CoreConnState.connected) {
      return _NotConnected(error: error);
    }
    if (!needDicts) return child;
    return _DictGate(child: child);
  }
}

class _NotConnected extends StatelessWidget {
  final String? error;
  const _NotConnected({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text('Ombor yadrosi (v2) ulanmagan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              error ?? 'Ilovaga qayta kiring yoki server manzilini tekshiring.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => context.read<CoreSession>().retry(),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kCoreAccent, foregroundColor: Colors.white),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Qayta urinish'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showServerSettingsDialog(context);
                    if (saved && context.mounted) {
                      context.read<CoreSession>().retry();
                    }
                  },
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('Server'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DictGate extends StatefulWidget {
  final Widget child;
  const _DictGate({required this.child});

  @override
  State<_DictGate> createState() => _DictGateState();
}

class _DictGateState extends State<_DictGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoreDictProvider>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loaded = context.select<CoreDictProvider, bool>((d) => d.loaded);
    final error = context.select<CoreDictProvider, String?>((d) => d.error);
    if (loaded) return widget.child;
    if (error != null) {
      return CoreErrorView(
        message: 'Lug\'atlar yuklanmadi: $error',
        onRetry: () => context.read<CoreDictProvider>().ensureLoaded(force: true),
      );
    }
    return const Center(child: CircularProgressIndicator.adaptive());
  }
}

class CoreSkladDropdown extends StatelessWidget {
  final int? value;
  final String label;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final bool allowNull;
  const CoreSkladDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.allowNull = false,
  });

  @override
  Widget build(BuildContext context) {
    final sklads = context.select<CoreDictProvider, List<CoreSklad>>(
        (d) => d.activeSklads);
    final ids = sklads.map((s) => s.id).toSet();
    return DropdownButtonFormField<int?>(
      // Tashqaridan qiymat o'zgarsa (masalan default ombor) maydon yangilansin.
      key: ValueKey('sklad-$label-$value'),
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        if (allowNull)
          const DropdownMenuItem<int?>(value: null, child: Text('Hammasi')),
        for (final s in sklads)
          DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

class CoreCorrDropdown extends StatelessWidget {
  final int? value;
  final String label;
  final List<String> kinds;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  const CoreCorrDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.kinds,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final dict = context.watch<CoreDictProvider>();
    final corrs = dict.corrsOfKind(kinds);
    final ids = corrs.map((c) => c.id).toSet();
    return DropdownButtonFormField<int?>(
      key: ValueKey('corr-$label-$value'),
      initialValue: ids.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final c in corrs)
          DropdownMenuItem<int?>(
            value: c.id,
            child: Text('${c.name}  ·  ${c.kind}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Oddiy matn maydoni (forma ichida takrorlanadigan dekoratsiya).
InputDecoration coreInput(String label, {String? hint, Widget? suffix}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: suffix,
    );

/// Kartochka ichida «label: value» qatori.
Widget kv(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
