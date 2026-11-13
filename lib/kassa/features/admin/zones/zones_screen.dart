import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../widgets/admin_widgets.dart';

class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  List<dynamic> _zones = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // `force: true` SHART. Ilgari kesh o'qilardi va zona tahrirlanganda
      // dialogga ESKI stol soni tushardi. Server esa `count` dan ortiq
      // stollarni O'CHIRADI: boshqa qurilmadan 3 ta stol qo'shilgan bo'lsa,
      // admin faqat zona NOMINI tuzatib saqlaganda o'sha 3 ta stol (va
      // ularning QR kodlari) yo'q bo'lib ketardi.
      final zones = await ApiService().getZones(force: true);
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorText(error);
      });
    }
  }

  String _zoneName(Map<String, dynamic> zone) {
    final raw = zone['name'];
    if (raw is Map) return (raw['uz'] ?? raw.values.first ?? '').toString();
    return '${raw ?? ''}';
  }

  Future<void> _openForm({Map<String, dynamic>? zone}) async {
    final editing = zone != null;
    final tables = zone?['tables'] as List<dynamic>? ?? [];
    final nameC = TextEditingController(text: editing ? _zoneName(zone) : '');
    final countC = TextEditingController(
      text: editing ? tables.length.toString() : '',
    );

    final saved = await showAdminForm(
      context: context,
      title: editing ? _zoneName(zone) : 'Yangi zona',
      subtitle: editing
          ? 'Hozir ${tables.length} ta stol bor'
          : 'Zal, tashqari, VIP…',
      icon: Icons.table_restaurant_rounded,
      color: AppColors.primary,
      fields: (ctx, refresh) => [
        AdminField(
          label: 'Zona nomi',
          controller: nameC,
          hint: 'Masalan: ZAL',
          icon: Icons.label_outline_rounded,
          autofocus: !editing,
        ),
        AdminField(
          label: 'Stollar soni',
          controller: countC,
          hint: '0 dan 200 gacha',
          helper: editing
              ? 'Sonni kamaytirsangiz oxirgi stollar QR kodlari bilan '
                  'birga o‘chiriladi'
              : 'Stollar avtomatik raqamlanadi',
          icon: Icons.chair_alt_outlined,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 3,
        ),
      ],
      submitLabel: editing ? 'Saqlash' : 'Yaratish',
      onSubmit: () async {
        final name = nameC.text.trim();
        final count = int.tryParse(countC.text.trim());
        if (name.isEmpty) {
          showErr(context, 'Zona nomini kiriting');
          return false;
        }
        if (count == null || count < 0 || count > 200) {
          showErr(context, 'Stollar soni 0 dan 200 gacha bo‘lsin');
          return false;
        }
        // Stol soni KAMAYTIRILSA server ortiqchasini o'chiradi — QR
        // kodlari bilan birga. Qaytarib bo'lmaydi, shuning uchun so'raladi.
        if (editing && count < tables.length) {
          final ok = await confirmAction(
            context: context,
            title: 'Stollar o‘chiriladi',
            message: 'Hozir ${tables.length} ta stol bor, siz $count ta '
                'qoldirmoqchisiz. Oxirgi ${tables.length - count} ta stol '
                'QR kodlari bilan birga o‘chiriladi.',
            confirmLabel: 'Ha, o‘chirilsin',
            danger: true,
          );
          if (ok != true) return false;
        }
        try {
          ApiService().invalidateZones();
          if (editing) {
            await ApiService().updateZone(zone['id'], name, count);
          } else {
            await ApiService().createZone(name, count);
          }
          return true;
        } catch (e) {
          if (mounted) showErr(context, apiErrorText(e));
          return false;
        }
      },
      onDelete: editing ? () => _delete(zone, silent: true) : null,
      deleteLabel: 'Zonani o‘chirish',
    );

    if (saved == true) {
      if (mounted) showOk(context, editing ? 'Yangilandi' : 'Zona yaratildi');
      await _load();
    }
  }

  Future<bool> _delete(Map<String, dynamic> zone, {bool silent = false}) async {
    if (!silent) {
      final ok = await confirmAction(
        context: context,
        title: 'Zonani o‘chirish',
        message: '${_zoneName(zone)} o‘chirilsinmi? Band stol yoki ochiq '
            'buyurtma bo‘lsa o‘chirilmaydi.',
        confirmLabel: 'O‘chirish',
        danger: true,
      );
      if (ok != true) return false;
    }
    try {
      ApiService().invalidateZones();
      await ApiService().deleteZone(zone['id']);
      if (!silent) {
        if (mounted) showOk(context, 'Zona o‘chirildi');
        await _load();
      }
      return true;
    } catch (e) {
      if (mounted) showErr(context, apiErrorText(e));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    var totalTables = 0;
    var totalFree = 0;
    for (final z in _zones.whereType<Map>()) {
      final t = z['tables'] as List<dynamic>? ?? [];
      totalTables += t.length;
      totalFree += t.where((x) => x['status'] == 'free').length;
    }

    return AdminPage(
      subtitle: '${_zones.length} zona · $totalTables stol',
      loading: _loading,
      error: _error,
      onRetry: _load,
      onRefresh: _load,
      primaryAction: AdminAction(
        label: 'Yangi zona',
        icon: Icons.add_rounded,
        onPressed: () => _openForm(),
      ),
      toolbar: _zones.isEmpty
          ? null
          : AdminStatsRow(
              items: [
                AdminStatData(
                  label: 'BO‘SH STOLLAR',
                  value: '$totalFree',
                  icon: Icons.event_available_rounded,
                  color: AppColors.success,
                ),
                AdminStatData(
                  label: 'BAND STOLLAR',
                  value: '${totalTables - totalFree}',
                  icon: Icons.event_busy_rounded,
                  color: AppColors.danger,
                ),
              ],
            ),
      child: _zones.isEmpty
          ? AdminEmpty(
              icon: Icons.table_restaurant_outlined,
              title: 'Hali zona yaratilmagan',
              message: 'Zona — bu stollar guruhi (ZAL, TASHQARI). '
                  'Zona yaratilganda stollar avtomatik raqamlanadi.',
              actionLabel: 'Zona yaratish',
              onAction: () => _openForm(),
            )
          : AdminList(
              children: [
                for (final raw in _zones.whereType<Map>())
                  _ZoneCard(
                    zone: Map<String, dynamic>.from(raw),
                    name: _zoneName(Map<String, dynamic>.from(raw)),
                    onEdit: () =>
                        _openForm(zone: Map<String, dynamic>.from(raw)),
                    onDelete: () => _delete(Map<String, dynamic>.from(raw)),
                  ),
              ],
            ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final Map<String, dynamic> zone;
  final String name;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ZoneCard({
    required this.zone,
    required this.name,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tables = zone['tables'] as List<dynamic>? ?? [];
    final free = tables.where((t) => t['status'] == 'free').length;
    final busy = tables.length - free;

    return AdminSection(
      title: name,
      subtitle: '${tables.length} ta stol · $free bo‘sh · $busy band',
      icon: Icons.table_restaurant_rounded,
      color: AppColors.primary,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textFaint),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'edit',
            height: 44,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
                SizedBox(width: 10),
                Text('Tahrirlash'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            height: 44,
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.danger),
                SizedBox(width: 10),
                Text('O‘chirish', style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ),
      children: [
        if (tables.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Bu zonada stol yo‘q — tahrirlab stol soni kiriting',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tables.whereType<Map>())
                _TableChip(
                  label: (t['label'] ?? t['sku'] ?? '').toString(),
                  free: t['status'] == 'free',
                ),
            ],
          ),
      ],
    );
  }
}

class _TableChip extends StatelessWidget {
  final String label;
  final bool free;
  const _TableChip({required this.label, required this.free});

  @override
  Widget build(BuildContext context) {
    final c = free ? AppColors.success : AppColors.danger;
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: free ? AppColors.text : c,
            ),
          ),
        ],
      ),
    );
  }
}
