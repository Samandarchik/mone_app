// core2/ui/docs_list_ui.dart — mone_core hujjatlar ro'yxati (DocsListUi):
// tur/holat/sana/ombor filtrlari (chip + sheet), qidiruv, kartada tur,
// raqam, sana, ombor(lar), summa, holat chip; scroll oxirida `loadMore`;
// FAB «+» → tur tanlash (perms bo'yicha) → DocFormUi. Karta bosilsa
// DocDetailUi. Ro'yxat `Selector` bilan faqat items/loading'ni kuzatadi.
//
// CORE_DEBT_KONTRAKT §4: qatorda KIM KIRITGANI (`created_by_name`) ko'rinadi,
// filtrlarga «Kim kiritgan» (`?created_by=` — foydalanuvchilar `GET /users`
// dan, ruxsat bo'lmasa faqat «Men») va «Manba» (`?source=` — Ilova / SH5 /
// Kassa) qo'shildi.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uz_ai_dev/core/context_extension.dart';
import 'package:uz_ai_dev/core2/models/core_doc.dart';
import 'package:uz_ai_dev/core2/models/core_user.dart';
import 'package:uz_ai_dev/core2/provider/core_dict_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_docs_provider.dart';
import 'package:uz_ai_dev/core2/provider/core_session_provider.dart';
import 'package:uz_ai_dev/core2/services/core_admin_service.dart';
import 'package:uz_ai_dev/core2/ui/doc_actions_logic.dart';
import 'package:uz_ai_dev/core2/ui/doc_detail_ui.dart';
import 'package:uz_ai_dev/core2/ui/doc_form_ui.dart';
import 'package:uz_ai_dev/core2/ui/widgets/core_widgets.dart';

class DocsListUi extends StatelessWidget {
  const DocsListUi({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCoreBg,
      appBar: AppBar(
        backgroundColor: kCoreBg,
        elevation: 0,
        title: const Text('Hujjatlar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: const CoreConnectGate(child: _DocsBody()),
      floatingActionButton: const _AddFab(),
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CoreSession>();
    if (!session.connected || !session.canAnyDoc) return const SizedBox.shrink();
    return FloatingActionButton(
      backgroundColor: kCoreAccent,
      foregroundColor: Colors.white,
      onPressed: () => _pickType(context, session),
      child: const Icon(Icons.add),
    );
  }

  Future<void> _pickType(BuildContext context, CoreSession session) async {
    final types = CoreDocType.all.where(session.canCreate).toList();
    final t = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Hujjat turi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            for (final type in types)
              ListTile(
                leading: Icon(docTypeIcon(type), color: kCoreAccentDark),
                title: Text(CoreDocType.title(type)),
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (t != null && context.mounted) {
      context.push(DocFormUi(type: t));
    }
  }
}

class _DocsBody extends StatefulWidget {
  const _DocsBody();

  @override
  State<_DocsBody> createState() => _DocsBodyState();
}

class _DocsBodyState extends State<_DocsBody> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<CoreDocsProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<CoreDocsProvider>();
      _search.text = p.search;
      p.load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CoreDocsProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => p.setFilters(searchText: v.trim()),
            decoration: InputDecoration(
              hintText: 'Raqam / izoh bo\'yicha qidirish',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: p.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _search.clear();
                        p.setFilters(searchText: '');
                      }),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        _FilterBar(provider: p),
        Expanded(child: _list(p)),
      ],
    );
  }

  Widget _list(CoreDocsProvider p) {
    if (p.loading && p.items.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (p.error != null && p.items.isEmpty) {
      return CoreErrorView(message: p.error!, onRetry: p.load);
    }
    return RefreshIndicator(
      onRefresh: p.load,
      child: p.items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 160),
                Center(child: Text('Hujjat yo\'q', style: TextStyle(color: Colors.black54))),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              itemCount: p.items.length + (p.hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= p.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  );
                }
                return DocCard(doc: p.items[i]);
              },
            ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  final CoreDocsProvider provider;
  const _FilterBar({required this.provider});

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  /// «Kim kiritgan» variantlari: id → ism. `users.manage` bo'lmasa faqat
  /// joriy foydalanuvchi («Men») qoladi.
  Map<int, String> _users = const {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final session = context.read<CoreSession>();
    final me = session.user;
    final out = <int, String>{};
    if (me != null) {
      out[me.id] = me.name.isEmpty ? 'Men' : '${me.name} (men)';
    }
    if (session.has(CorePerms.usersManage)) {
      try {
        for (final u in await CoreAdminService().users()) {
          if (!u.active && u.id != me?.id) continue;
          out.putIfAbsent(u.id, () => u.name.isEmpty ? 'user #${u.id}' : u.name);
        }
      } catch (_) {
        // Ruxsat yo'q yoki server javob bermadi — faqat «Men» qoladi.
      }
    }
    if (mounted) setState(() => _users = out);
  }

  String _userLabel(int id) => _users[id] ?? 'user #$id';

  @override
  Widget build(BuildContext context) {
    final dict = context.read<CoreDictProvider>();
    final p = widget.provider;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _chip(
            context,
            label: p.typeFilter == null ? 'Tur' : CoreDocType.title(p.typeFilter!),
            active: p.typeFilter != null,
            onTap: () => _pick(
              context,
              title: 'Tur',
              options: {for (final t in CoreDocType.all) t: CoreDocType.title(t)},
              current: p.typeFilter,
              onPicked: (v) =>
                  v == null ? p.setFilters(clearType: true) : p.setFilters(type: v),
            ),
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: p.statusFilter == null
                ? 'Holat'
                : CoreDocStatus.title(p.statusFilter!),
            active: p.statusFilter != null,
            onTap: () => _pick(
              context,
              title: 'Holat',
              options: {
                CoreDocStatus.draft: 'Qoralama',
                CoreDocStatus.posted: 'O\'tkazilgan',
                CoreDocStatus.cancelled: 'Bekor',
              },
              current: p.statusFilter,
              onPicked: (v) => v == null
                  ? p.setFilters(clearStatus: true)
                  : p.setFilters(status: v),
            ),
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: p.dateFrom == null && p.dateTo == null
                ? 'Sana'
                : '${coreDate(p.dateFrom)} – ${coreDate(p.dateTo)}',
            active: p.dateFrom != null || p.dateTo != null,
            onTap: () async {
              final now = DateTime.now();
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: DateTime(now.year + 1),
                initialDateRange: p.dateFrom != null && p.dateTo != null
                    ? DateTimeRange(
                        start: DateTime.parse(p.dateFrom!),
                        end: DateTime.parse(p.dateTo!))
                    : null,
              );
              if (range != null) {
                p.setFilters(from: isoOf(range.start), to: isoOf(range.end));
              }
            },
            onClear: p.dateFrom == null && p.dateTo == null
                ? null
                : () => p.setFilters(clearDates: true),
          ),
          const SizedBox(width: 6),
          _chip(
            context,
            label: p.skladFilter == null ? 'Ombor' : dict.skladName(p.skladFilter),
            active: p.skladFilter != null,
            onTap: () => _pick(
              context,
              title: 'Ombor',
              options: {for (final s in dict.sklads) '${s.id}': s.name},
              current: p.skladFilter?.toString(),
              onPicked: (v) => v == null
                  ? p.setFilters(clearSklad: true)
                  : p.setFilters(sklad: int.tryParse(v)),
            ),
          ),
          const SizedBox(width: 6),
          // Kim kiritgan (`created_by`) — §4.
          _chip(
            context,
            label: p.createdByFilter == null
                ? 'Kim kiritgan'
                : _userLabel(p.createdByFilter!),
            active: p.createdByFilter != null,
            onTap: () => _pick(
              context,
              title: 'Kim kiritgan',
              options: {
                for (final e in _users.entries) '${e.key}': e.value,
              },
              current: p.createdByFilter?.toString(),
              onPicked: (v) => v == null
                  ? p.setFilters(clearCreatedBy: true)
                  : p.setFilters(createdBy: int.tryParse(v)),
            ),
          ),
          const SizedBox(width: 6),
          // Manba: Ilova / SH5 / Kassa (`source`) — §4.
          _chip(
            context,
            label: p.sourceFilter == null
                ? 'Manba'
                : coreSourceUz(p.sourceFilter!),
            active: p.sourceFilter != null,
            onTap: () => _pick(
              context,
              title: 'Manba',
              options: coreSourceFilterOptions,
              current: p.sourceFilter,
              onPicked: (v) => v == null
                  ? p.setFilters(clearSource: true)
                  : p.setFilters(source: v),
            ),
          ),
          const SizedBox(width: 6),
          Text('${p.total} ta',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label,
      required bool active,
      required VoidCallback onTap,
      VoidCallback? onClear}) {
    return InputChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: active,
      selectedColor: kCoreAccent.withValues(alpha: 0.25),
      backgroundColor: Colors.white,
      onPressed: onTap,
      onDeleted: active ? (onClear ?? onTap) : null,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }

  Future<void> _pick(
    BuildContext context, {
    required String title,
    required Map<String, String> options,
    required String? current,
    required ValueChanged<String?> onPicked,
  }) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: current == null
                  ? null
                  : TextButton(
                      onPressed: () => Navigator.pop(context, ''),
                      child: const Text('Tozalash')),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.value),
                selected: e.key == current,
                selectedColor: kCoreAccentDark,
                onTap: () => Navigator.pop(context, e.key),
              ),
          ],
        ),
      ),
    );
    if (v == null) return;
    onPicked(v.isEmpty ? null : v);
  }
}

/// Ro'yxatdagi bitta hujjat kartasi (tafsilotga o'tadi).
class DocCard extends StatelessWidget {
  final CoreDoc doc;
  const DocCard({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final dict = context.read<CoreDictProvider>();
    final sklads = <String>[];
    if (doc.fromSklad != null) sklads.add(dict.skladName(doc.fromSklad));
    if (doc.toSklad != null) sklads.add(dict.skladName(doc.toSklad));
    final skladText = sklads.join(' → ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(DocDetailUi(docId: doc.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kCoreAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(docTypeIcon(doc.type), color: kCoreAccentDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${CoreDocType.title(doc.type)}  ${doc.number.isEmpty ? '#${doc.id}' : doc.number}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        coreStatusChip(doc.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        coreDate(doc.docDate),
                        if (skladText.isNotEmpty) skladText,
                        if (doc.corrId != null) dict.corrName(doc.corrId),
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (doc.comment.isNotEmpty)
                      Text(doc.comment,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('${coreMoney(doc.total)} so\'m',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        // Kim kiritgan (oyna/kassa hujjatida bo'sh keladi).
                        if (doc.createdByName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.person_outline,
                              size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(doc.createdByName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade600)),
                          ),
                        ],
                        if (doc.source.isNotEmpty && doc.source != 'app') ...[
                          const SizedBox(width: 8),
                          Text(coreSourceUz(doc.source),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
