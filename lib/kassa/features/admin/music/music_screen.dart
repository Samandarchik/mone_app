import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/wss_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/admin_page.dart';

/// Musiqa — YouTube fon musiqasini boshqarish.
///
/// Pleer restorandagi Windows kassa kompyuterida chalinadi (backend'dagi
/// mpv + yt-dlp agenti). Bu ekran esa istalgan joydan ishlaydi: restoran
/// ichida local serverga, tashqarida bulutga ulanadi — buyruq sync orqali
/// kassaga yetib boradi.
///
/// Progress hisoblash: server `position_sec` + `started_at` beradi, ilova
/// esa soniya sayin o'zi sanaydi — hech qanday so'rovsiz.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _state;
  List<dynamic> _queue = [];
  List<dynamic> _playlists = [];
  bool _loading = true;
  String? _error;

  // Qidiruv
  final _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  List<dynamic>? _results; // null = qidiruv rejimi emas
  bool _searching = false;
  String? _searchError;

  StreamSubscription? _wssSub;
  Timer? _refreshDebounce;
  Timer? _ticker;

  // Progress bazasi (izoh klass sharhida)
  double _baseElapsed = 0;
  DateTime _baseAt = DateTime.now();

  // Ovoz slayderini sudrash paytidagi lokal qiymat
  double? _volDrag;

  // Progress (seek) chizig'ini sudrash paytidagi lokal qiymat (soniya)
  double? _seekDrag;

  @override
  void initState() {
    super.initState();
    _load();
    _wssSub = WssService().eventStream.listen((event) {
      final e = event['event'];
      if (e == 'music:state') {
        final p = event['payload'];
        if (p is Map && mounted) {
          setState(() {
            _state = Map<String, dynamic>.from(p);
            _rebaseProgress();
          });
        }
        // Yangi qo'shiq boshlanganda navbat ham o'zgargan bo'ladi.
        _scheduleRefresh();
      } else if (e == 'music:changed') {
        _scheduleRefresh();
      }
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state?['is_playing'] == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _wssSub?.cancel();
    _refreshDebounce?.cancel();
    _searchDebounce?.cancel();
    _ticker?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  // ===== Ma'lumot =====

  Future<void> _load() async {
    try {
      final data = await _api.musicState();
      if (!mounted) return;
      setState(() {
        _state = Map<String, dynamic>.from(data['state'] as Map? ?? {});
        _queue = List.from(data['queue'] as List? ?? []);
        _playlists = List.from(data['playlists'] as List? ?? []);
        _loading = false;
        _error = null;
        _rebaseProgress(serverTime: data['server_time'] as String?);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errMsg(e);
      });
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _rebaseProgress({String? serverTime}) {
    final st = _state;
    if (st == null) return;
    double pos = (st['position_sec'] as num?)?.toDouble() ?? 0;
    // To'liq holat (GET) server vaqtini ham beradi — started_at'dan beri
    // o'tgan vaqt qo'shiladi. WSS push'da started_at ~ hozir, qo'shimcha yo'q.
    if (st['is_playing'] == true && serverTime != null) {
      final srv = DateTime.tryParse(serverTime);
      final started = DateTime.tryParse(st['started_at']?.toString() ?? '');
      if (srv != null && started != null) {
        pos += srv.difference(started).inMilliseconds / 1000.0;
      }
    }
    _baseElapsed = pos < 0 ? 0 : pos;
    _baseAt = DateTime.now();
  }

  double get _elapsed {
    if (_state?['is_playing'] != true) return _baseElapsed;
    return _baseElapsed +
        DateTime.now().difference(_baseAt).inMilliseconds / 1000.0;
  }

  String _errMsg(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
      return 'Server bilan aloqa xatosi';
    }
    return 'Xatolik yuz berdi';
  }

  Future<void> _run(Future<void> Function() action, [String? okMsg]) async {
    try {
      await action();
      if (okMsg != null && mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(okMsg),
              duration: const Duration(seconds: 2),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(_errMsg(e)),
              backgroundColor: AppColors.danger,
            ),
          );
      }
    }
  }

  // ===== Qidiruv =====

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _results = null;
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _doSearch(q);
    });
  }

  Future<void> _doSearch(String q) async {
    setState(() {
      _searching = true;
      _searchError = null;
      _results ??= [];
    });
    try {
      final r = await _api.musicSearch(q);
      if (!mounted || _searchCtl.text.trim() != q) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = _errMsg(e);
      });
    }
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtl.clear();
    setState(() {
      _results = null;
      _searchError = null;
      _searching = false;
    });
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final agentOnline = _state?['agent_online'] == true;
    return AdminPage(
      helpKey: 'music',
      // POS'da (kassir) nav manzili yo'q — sarlavha bo'sh chiqardi.
      title: 'Musiqa',
      icon: Icons.music_note_rounded,
      subtitle: _loading
          ? 'Yuklanmoqda…'
          : (agentOnline
              ? 'Pleyer ishlayapti'
              : 'Pleyer o‘chiq — kassa kompyuterida mpv ishga tushmagan'),
      loading: _loading,
      error: _state == null ? _error : null,
      onRetry: _load,
      searchController: _searchCtl,
      onSearchChanged: _onSearchChanged,
      searchHint: 'YouTube’dan qo‘shiq qidirish…',
      actions: [
        if (_results != null)
          AdminIconAction(
            icon: Icons.close_rounded,
            tooltip: 'Qidiruvni yopish',
            onPressed: _closeSearch,
          ),
      ],
      padded: false,
      constrained: false,
      bottomBar: _state == null ? null : _nowPlayingBar(),
      child: Column(
        children: [
          if (!agentOnline) _agentBanner(),
          Expanded(child: _results != null ? _searchResults() : _mainList()),
        ],
      ),
    );
  }

  Widget _agentBanner() {
    final err = (_state?['error_text'] ?? '').toString();
    return Container(
      width: double.infinity,
      color: AppColors.warningSoft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.volume_off_rounded,
            color: AppColors.warning,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              err.isNotEmpty
                  ? 'Pleyer o‘chiq: $err'
                  : 'Pleyer o‘chiq — kassa kompyuterida mpv hali ishga tushmagan',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults() {
    if (_searching && (_results?.isEmpty ?? true)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    final results = _results ?? [];
    if (results.isEmpty) {
      return const Center(
        child: Text(
          'Hech narsa topilmadi',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final r = Map<String, dynamic>.from(results[i]);
        return _trackCard(
          title: (r['title'] ?? '').toString(),
          subtitle: _subtitleOf(r),
          thumbnail: (r['thumbnail'] ?? '').toString(),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Hozir chalish',
                icon: const Icon(
                  Icons.play_circle_fill_rounded,
                  color: AppColors.primary,
                  size: 30,
                ),
                onPressed: () => _run(
                  () => _api.musicQueueAdd(r, playNow: true),
                  '▶ ${r['title']}',
                ),
              ),
              IconButton(
                tooltip: 'Navbatga qo‘shish',
                icon: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textMuted,
                  size: 26,
                ),
                onPressed: () => _run(
                  () => _api.musicQueueAdd(r),
                  'Navbatga qo‘shildi',
                ),
              ),
              IconButton(
                tooltip: 'Pleylistga saqlash',
                icon: const Icon(
                  Icons.library_add_rounded,
                  color: AppColors.textMuted,
                  size: 23,
                ),
                onPressed: () => _addToPlaylist(r),
              ),
            ],
          ),
          onTap: () => _run(() => _api.musicQueueAdd(r), 'Navbatga qo‘shildi'),
        );
      },
    );
  }

  // ----- Asosiy ro'yxat: pleylistlar + navbat -----

  Widget _mainList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _playlistsRow(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
          child: Row(
            children: [
              Text(
                'NAVBAT (${_queue.length})',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textFaint,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (_queue.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirm(
                    'Navbatni tozalash',
                    'Navbatdagi ${_queue.length} ta qo‘shiq o‘chirilsinmi?',
                    () => _run(() => _api.musicQueueClear()),
                  ),
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Tozalash'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _queue.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '🎵 Navbat bo‘sh\nQidiruv orqali qo‘shiq qo‘shing',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, height: 1.6),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  buildDefaultDragHandles: false,
                  itemCount: _queue.length,
                  onReorder: (oldI, newI) {
                    setState(() {
                      if (newI > oldI) newI--;
                      final item = _queue.removeAt(oldI);
                      _queue.insert(newI, item);
                    });
                    _run(
                      () => _api.musicQueueReorder(
                        _queue.map<int>((q) => (q['id'] as num).toInt()).toList(),
                      ),
                    );
                  },
                  itemBuilder: (_, i) {
                    final q = Map<String, dynamic>.from(_queue[i]);
                    final id = (q['id'] as num).toInt();
                    return KeyedSubtree(
                      key: ValueKey('mq$id'),
                      child: _trackCard(
                        title: (q['title'] ?? '').toString(),
                        subtitle: _subtitleOf(q),
                        thumbnail: (q['thumbnail'] ?? '').toString(),
                        leadingIndex: i + 1,
                        dragIndex: i,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Hozir chalish',
                              icon: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: AppColors.primary,
                                size: 28,
                              ),
                              onPressed: () => _run(
                                () => _api.musicCommand('play_item', id),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Pleylistga saqlash',
                              icon: const Icon(
                                Icons.library_add_rounded,
                                color: AppColors.textMuted,
                                size: 22,
                              ),
                              onPressed: () => _addToPlaylist(q),
                            ),
                            IconButton(
                              tooltip: 'Olib tashlash',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textFaint,
                                size: 22,
                              ),
                              onPressed: () => _run(
                                () => _api.musicQueueRemove(id),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _playlistsRow() {
    final activeId = (_state?['playlist_id'] as num?)?.toInt() ?? 0;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final p in _playlists)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _playlistChip(Map<String, dynamic>.from(p), activeId),
            ),
          if (_queue.isNotEmpty || (_state?['video_id'] ?? '') != '')
            ActionChip(
              avatar: const Icon(
                Icons.add_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              label: const Text('Pleylist saqlash'),
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
              backgroundColor: AppColors.primarySoft,
              side: BorderSide.none,
              onPressed: _savePlaylistDialog,
            ),
        ],
      ),
    );
  }

  Widget _playlistChip(Map<String, dynamic> p, int activeId) {
    final id = (p['id'] as num).toInt();
    final active = id == activeId;
    return ActionChip(
      avatar: Icon(
        active ? Icons.repeat_on_rounded : Icons.queue_music_rounded,
        size: 18,
        color: active ? Colors.white : AppColors.textMuted,
      ),
      label: Text('${p['name']} · ${p['count']}'),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: active ? Colors.white : AppColors.text,
      ),
      backgroundColor: active ? AppColors.primary : AppColors.surface,
      side: BorderSide(color: active ? AppColors.primary : AppColors.border),
      onPressed: () => _openPlaylist(p, active),
    );
  }

  // ----- Pleylist bottom sheet -----

  Future<void> _openPlaylist(Map<String, dynamic> p, bool active) async {
    final id = (p['id'] as num).toInt();
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.queue_music_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${p['name']}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Pleylistni o‘chirish',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _confirm(
                        'Pleylistni o‘chirish',
                        '"${p['name']}" butunlay o‘chirilsinmi?',
                        () => _run(() => _api.musicPlaylistDelete(id)),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _run(
                          () => _api.musicPlaylistPlay(id),
                          '🔁 ${p['name']} chalinmoqda',
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Chalish (aylanma)'),
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _run(() => _api.musicCommand('set_playlist', 0));
                      },
                      child: const Text('Aylanishni to‘xtatish'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _api.musicPlaylistItems(id),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snap.data!;
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Pleylist bo‘sh',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = Map<String, dynamic>.from(items[i]);
                      return _trackCard(
                        title: (it['title'] ?? '').toString(),
                        subtitle: _subtitleOf(it),
                        thumbnail: (it['thumbnail'] ?? '').toString(),
                        leadingIndex: i + 1,
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: AppColors.textFaint,
                          ),
                          onPressed: () {
                            _run(
                              () => _api.musicPlaylistRemoveItem(
                                id,
                                (it['id'] as num).toInt(),
                              ),
                            );
                            Navigator.of(ctx).pop();
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askPlaylistName(String title) async {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Masalan: Kechki muhit',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePlaylistDialog() async {
    final name = await _askPlaylistName('Pleylist saqlash');
    if (name == null || name.isEmpty) return;
    await _run(
      () => _api.musicPlaylistCreate(name),
      'Pleylist saqlandi: $name',
    );
  }

  // ----- Qo'shiqni pleylistga saqlash -----

  /// Qo'shiqni tanlangan (yoki yangi) pleylistga qo'shadi. Pleylistdagi
  /// qo'shiqlar bazada saqlanadi — navbatdan farqli, chalinib yo'qolmaydi.
  Future<void> _addToPlaylist(Map<String, dynamic> track) async {
    if ((track['video_id'] ?? '').toString().isEmpty) return;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.library_add_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pleylistga saqlash — ${track['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final p in _playlists)
              ListTile(
                leading: const Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.textMuted,
                ),
                title: Text(
                  '${p['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${p['count']} ta qo‘shiq'),
                onTap: () => Navigator.of(ctx).pop((p['id'] as num).toInt()),
              ),
            ListTile(
              leading: const Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Yangi pleylist',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'new') {
      final name = await _askPlaylistName('Yangi pleylist');
      if (name == null || name.isEmpty) return;
      await _run(() async {
        final p = await _api.musicPlaylistCreate(name, fromQueue: false);
        await _api.musicPlaylistAddItem((p['id'] as num).toInt(), track);
      }, '“${track['title']}” → $name');
    } else if (choice is int) {
      final pl = _playlists.firstWhere(
        (p) => (p['id'] as num).toInt() == choice,
        orElse: () => null,
      );
      await _run(
        () => _api.musicPlaylistAddItem(choice, track),
        '“${track['title']}” → ${pl?['name'] ?? 'pleylist'}',
      );
    }
  }

  Future<void> _confirm(
    String title,
    String message,
    VoidCallback onYes,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Bekor'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ha'),
          ),
        ],
      ),
    );
    if (ok == true) onYes();
  }

  // ----- Umumiy qo'shiq kartasi -----

  Widget _trackCard({
    required String title,
    required String subtitle,
    required String thumbnail,
    Widget? trailing,
    int? leadingIndex,
    int? dragIndex,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: AppColors.textGhost,
                      size: 20,
                    ),
                  ),
                )
              else if (leadingIndex != null)
                SizedBox(
                  width: 28,
                  child: Text(
                    '$leadingIndex',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              _thumb(thumbnail, 52, 39),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(String url, double w, double h) {
    final ph = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.textGhost,
        size: 20,
      ),
    );
    if (url.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ph,
      ),
    );
  }

  String _subtitleOf(Map<String, dynamic> m) {
    final parts = <String>[];
    final ch = (m['channel'] ?? '').toString();
    if (ch.isNotEmpty) parts.add(ch);
    final d = (m['duration_sec'] as num?)?.toInt() ?? 0;
    if (d > 0) parts.add(_fmtDur(d.toDouble()));
    final by = (m['added_by'] ?? '').toString();
    if (by.isNotEmpty) parts.add(by);
    return parts.join(' · ');
  }

  String _fmtDur(double secD) {
    final sec = secD.round();
    final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  // ----- Pastki pleer paneli -----

  /// Bluetooth tugmasi — kassadagi BT'ni yoqish/o'chirish. Yoqilganda backend
  /// juftlangan kolonkaga o'zi ulanishga harakat qiladi (holat sync'dan keladi).
  Widget _btButton() {
    final st = _state ?? {};
    final btOn = st['bt_on'] == true;
    final btConn = st['bt_connected'] == true;
    final btDev = (st['bt_device'] ?? '').toString();
    return IconButton(
      tooltip: !btOn
          ? 'Bluetooth yoqish (kolonkaga ulanadi)'
          : btConn
          ? 'Bluetooth: $btDev ulangan — o‘chirish'
          : 'Bluetooth yoniq, kolonka ulanmagan — o‘chirish',
      icon: Icon(
        !btOn
            ? Icons.bluetooth_disabled_rounded
            : btConn
            ? Icons.bluetooth_connected_rounded
            : Icons.bluetooth_rounded,
        size: 22,
        color: !btOn
            ? AppColors.textFaint
            : btConn
            ? AppColors.primary
            : AppColors.warning,
      ),
      onPressed: () {
        final turnOn = !btOn;
        // Optimistik: tugma darhol rang almashtiradi, aniq holat sync'dan keladi.
        setState(() {
          _state?['bt_on'] = turnOn;
          if (!turnOn) {
            _state?['bt_connected'] = false;
          }
        });
        _run(
          () => _api.musicCommand('bt_toggle', turnOn ? 1 : 0),
          turnOn
              ? 'Bluetooth yoqilmoqda — kolonkaga ulanish…'
              : 'Bluetooth o‘chirildi',
        );
      },
    );
  }

  /// Qo'shiq ichida oldinga/orqaga sakrash (soniyalarda).
  void _seekBy(double delta) {
    final st = _state ?? {};
    if ((st['video_id'] ?? '') == '') return;
    final duration = (st['duration_sec'] as num?)?.toDouble() ?? 0;
    var target = _elapsed + delta;
    if (target < 0) target = 0;
    if (duration > 1 && target > duration - 1) target = duration - 1;
    // Darhol javob berayotgandek ko'rinishi uchun lokal rebase;
    // aniq holat music:state eventi bilan keladi.
    setState(() {
      _baseElapsed = target;
      _baseAt = DateTime.now();
    });
    _run(() => _api.musicCommand('seek', target.round()));
  }

  /// Ovozni tugma bilan bosqichma-bosqich o'zgartirish (slayderga qo'shimcha).
  void _bumpVolume(double delta) {
    final cur = _volDrag ?? ((_state?['volume'] as num?)?.toDouble() ?? 60);
    final v = (cur + delta).clamp(0.0, 100.0).roundToDouble();
    if (v == cur) return;
    setState(() => _volDrag = v);
    _run(() => _api.musicCommand('volume', v.round()));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _volDrag = null);
    });
  }

  Widget _nowPlayingBar() {
    final st = _state ?? {};
    final playing = st['is_playing'] == true;
    final title = (st['title'] ?? '').toString();
    final hasTrack = (st['video_id'] ?? '') != '';
    final duration = (st['duration_sec'] as num?)?.toDouble() ?? 0;
    var elapsed = _seekDrag ?? _elapsed;
    if (duration > 0 && elapsed > duration) elapsed = duration;
    final volume = _volDrag ?? ((st['volume'] as num?)?.toDouble() ?? 60);
    final playlistName = (st['playlist_name'] ?? '').toString();
    final activePlaylist = ((st['playlist_id'] as num?)?.toInt() ?? 0) != 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 640;
            final controls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Oldingisi',
                  iconSize: 26,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () => _run(() => _api.musicCommand('prev')),
                ),
                IconButton(
                  tooltip: '10 soniya orqaga',
                  iconSize: 24,
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: hasTrack ? () => _seekBy(-10) : null,
                ),
                IconButton(
                  tooltip: playing ? 'Pauza' : 'Chalish',
                  iconSize: 44,
                  color: AppColors.primary,
                  icon: Icon(
                    playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: () {
                    // Darhol javob berayotgandek ko'rinishi uchun lokal almashtiramiz;
                    // haqiqiy holat music:state eventi bilan keladi.
                    setState(() {
                      _baseElapsed = elapsed;
                      _baseAt = DateTime.now();
                      _state?['is_playing'] = !playing;
                    });
                    _run(() => _api.musicCommand('toggle'));
                  },
                ),
                IconButton(
                  tooltip: '10 soniya oldinga',
                  iconSize: 24,
                  icon: const Icon(Icons.forward_10_rounded),
                  onPressed: hasTrack ? () => _seekBy(10) : null,
                ),
                IconButton(
                  tooltip: 'Keyingisi',
                  iconSize: 26,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => _run(() => _api.musicCommand('next')),
                ),
              ],
            );
            final volumeRow = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                IconButton(
                  tooltip: 'Ovozni pasaytirish',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 22,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => _bumpVolume(-1),
                ),
                SizedBox(
                  width: wide ? 140 : 180,
                  child: Slider(
                    value: volume.clamp(0, 100),
                    max: 100,
                    onChanged: (v) => setState(() => _volDrag = v),
                    onChangeEnd: (v) {
                      _run(() => _api.musicCommand('volume', v.round()));
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _volDrag = null);
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Ovozni oshirish',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 22,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () => _bumpVolume(1),
                ),
                SizedBox(
                  width: 26,
                  child: Text(
                    '${volume.round()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                _btButton(),
              ],
            );

            final info = Row(
              children: [
                _thumb((st['thumbnail'] ?? '').toString(), 46, 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasTrack ? title : 'Hech narsa chalinmayapti',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: hasTrack ? AppColors.text : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (hasTrack)
                            Text(
                              duration > 0
                                  ? '${_fmtDur(elapsed)} / ${_fmtDur(duration)}'
                                  : _fmtDur(elapsed),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          if (activePlaylist) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '🔁 $playlistName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasTrack)
                  IconButton(
                    tooltip: 'Pleylistga saqlash',
                    icon: const Icon(
                      Icons.library_add_rounded,
                      size: 21,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => _addToPlaylist({
                      'video_id': st['video_id'],
                      'title': st['title'] ?? '',
                      'channel': st['channel'] ?? '',
                      'duration_sec': st['duration_sec'] ?? 0,
                      'thumbnail': st['thumbnail'] ?? '',
                    }),
                  ),
              ],
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTrack && duration > 0)
                  // Bosib/sudrab qo'shiq ichida istalgan joyga o'tish mumkin.
                  SizedBox(
                    height: 20,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.surfaceAlt,
                        thumbColor: AppColors.primary,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: elapsed.clamp(0.0, duration),
                        max: duration,
                        onChanged: (v) => setState(() => _seekDrag = v),
                        onChangeEnd: (v) {
                          setState(() {
                            _baseElapsed = v;
                            _baseAt = DateTime.now();
                            _seekDrag = null;
                          });
                          _run(() => _api.musicCommand('seek', v.round()));
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: wide
                      ? Row(
                          children: [
                            Expanded(child: info),
                            controls,
                            const SizedBox(width: 8),
                            volumeRow,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            info,
                            // Telefonda boshqaruv va ovoz bitta qatorga
                            // sig'masdi (~200px overflow) — ikki qator.
                            controls,
                            volumeRow,
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
