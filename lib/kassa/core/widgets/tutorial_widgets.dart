import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../services/tutorial_service.dart';
import '../theme/app_theme.dart';
import '../theme/ui_kit.dart';

/// Bo'lim sarlavhasi yonidagi «i» tugmasi — shu bo'lim bo'yicha video
/// qo'llanma(lar)ni ochadi. Bu bo'lim uchun video bo'lmasa — umuman
/// ko'rinmaydi (bo'sh joy qoldirmaydi).
class TutorialHelpButton extends StatefulWidget {
  final String helpKey;
  final double size;
  const TutorialHelpButton(this.helpKey, {super.key, this.size = 30});

  @override
  State<TutorialHelpButton> createState() => _TutorialHelpButtonState();
}

class _TutorialHelpButtonState extends State<TutorialHelpButton> {
  final _svc = TutorialService();

  @override
  void initState() {
    super.initState();
    _svc.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final videos = _svc.videosFor(widget.helpKey, _svc.role);
        if (videos.isEmpty) return const SizedBox.shrink();
        return Tooltip(
          message: 'Video qo‘llanma',
          child: InkResponse(
            radius: widget.size,
            onTap: () => showTutorialsFor(context, widget.helpKey),
            child: Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryTint),
              ),
              child: Icon(
                Icons.info_outline_rounded,
                size: widget.size * 0.62,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// «i» bosilganda: bitta video bo'lsa — darhol pleyer, bir nechta bo'lsa —
/// ro'yxat (pastida «Barcha qo'llanmalar»).
Future<void> showTutorialsFor(BuildContext context, String key) async {
  final svc = TutorialService();
  await svc.ensureLoaded();
  if (!context.mounted) return;
  final videos = svc.videosFor(key, svc.role);
  if (videos.isEmpty) return;
  if (videos.length == 1) {
    openTutorialPlayer(context, videos.first);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.play_circle_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Video qo‘llanma',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                children: [
                  for (final v in videos)
                    TutorialTile(
                      video: v,
                      onTap: () {
                        Navigator.pop(ctx);
                        openTutorialPlayer(context, v);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openTutorialsScreen(context);
                  },
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Barcha qo‘llanmalar'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void openTutorialsScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const TutorialsScreen()),
  );
}

void openTutorialPlayer(BuildContext context, TutorialVideo v) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TutorialPlayerScreen(video: v)),
  );
}

/// Ro'yxatdagi bitta video qatori: rasm, nom, davomiylik, yuklab olish holati.
class TutorialTile extends StatelessWidget {
  final TutorialVideo video;
  final VoidCallback onTap;
  const TutorialTile({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final svc = TutorialService();
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final p = svc.progress[video.file];
        final done = svc.isDownloaded(video);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: video.isFull ? AppColors.primarySoft : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _Poster(video: video),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: video.isFull
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${video.durationLabel} · ${video.sizeLabel}'
                            '${done ? ' · yuklangan' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: done
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (p != null) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: p,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      done
                          ? Icons.play_circle_fill_rounded
                          : Icons.download_for_offline_rounded,
                      color: done ? AppColors.success : AppColors.primary,
                      size: 30,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Poster extends StatelessWidget {
  final TutorialVideo video;
  const _Poster({required this.video});

  @override
  Widget build(BuildContext context) {
    final url = video.posterUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 46,
        height: 72,
        color: const Color(0xFF151A2E),
        child: url == null
            ? const Icon(Icons.movie_rounded, color: Colors.white54)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.movie_rounded, color: Colors.white54),
              ),
      ),
    );
  }
}

/// Barcha qo'llanmalar bitta joyda (POS'dan ochiladigan alohida sahifa).
class TutorialsScreen extends StatelessWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          'Video qo‘llanmalar',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: const TutorialsList(),
    );
  }
}

/// Qo'llanmalar ro'yxati: rol bo'yicha guruhlar, har guruh boshida
/// «to'liq video». Admin panelida bo'lim sifatida ham shu ishlatiladi.
class TutorialsList extends StatefulWidget {
  const TutorialsList({super.key});

  @override
  State<TutorialsList> createState() => _TutorialsListState();
}

class _TutorialsListState extends State<TutorialsList> {
  final _svc = TutorialService();

  @override
  void initState() {
    super.initState();
    _svc.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final groups = _svc.groupsFor(_svc.role);
        if (!_svc.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: _svc.refresh,
          child: groups.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: 'Qo‘llanmalar yuklanmadi',
                      subtitle: 'Internetni tekshirib, pastga torting',
                    ),
                  ],
                )
              : ListView(
                  padding:
                      EdgeInsets.fromLTRB(context.gutter, 12, context.gutter, 24),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                        child: Text(
                          g.title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      if (g.full != null)
                        TutorialTile(
                          video: g.full!,
                          onTap: () => openTutorialPlayer(context, g.full!),
                        ),
                      for (final v in g.videos)
                        TutorialTile(
                          video: v,
                          onTap: () => openTutorialPlayer(context, v),
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// Video avval diskka yuklanadi (keyingi safar internetsiz ochiladi), keyin
/// ilova ichida ijro etiladi. Windows/Linux'da video_player yo'q — u yerda
/// yuklangan fayl tizim pleyerida ochiladi.
class TutorialPlayerScreen extends StatefulWidget {
  final TutorialVideo video;
  const TutorialPlayerScreen({super.key, required this.video});

  @override
  State<TutorialPlayerScreen> createState() => _TutorialPlayerScreenState();
}

class _TutorialPlayerScreenState extends State<TutorialPlayerScreen> {
  final _svc = TutorialService();
  VideoPlayerController? _ctl;
  String? _error;
  File? _file;

  bool get _inAppPlayer =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      if (kIsWeb) {
        await _play(VideoPlayerController.networkUrl(Uri.parse(widget.video.url)));
        return;
      }
      final f = await _svc.download(widget.video);
      if (!mounted) return;
      _file = f;
      if (_inAppPlayer) {
        await _play(VideoPlayerController.file(f));
      } else {
        await _openExternal();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Video yuklanmadi. Internetni tekshiring.');
      }
    }
  }

  Future<void> _play(VideoPlayerController c) async {
    await c.initialize();
    if (!mounted) {
      c.dispose();
      return;
    }
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _ctl = c);
    await c.play();
  }

  Future<void> _openExternal() async {
    final f = _file;
    if (f == null) return;
    await launchUrl(Uri.file(f.path));
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: c != null && c.value.isInitialized
            ? _buildPlayer(c)
            : _buildLoading(),
      ),
    );
  }

  Widget _buildLoading() {
    return ListenableBuilder(
      listenable: _svc,
      builder: (context, _) {
        final p = _svc.progress[widget.video.file];
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Qayta urinish'),
                  ),
                ] else if (_file != null && !_inAppPlayer) ...[
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 48),
                  const SizedBox(height: 12),
                  const Text('Video yuklandi va pleyerda ochildi',
                      style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Yana ochish'),
                  ),
                ] else ...[
                  SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    p == null
                        ? 'Tayyorlanmoqda…'
                        : 'Yuklab olinmoqda… ${(p * 100).round()}%'
                            ' (${widget.video.sizeLabel})',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayer(VideoPlayerController c) {
    final v = c.value;
    final pos = v.position, dur = v.duration;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => v.isPlaying ? c.pause() : c.play(),
            child: Center(
              child: AspectRatio(
                aspectRatio: v.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(c),
                    if (!v.isPlaying)
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 56),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                iconSize: 32,
                onPressed: () => v.isPlaying ? c.pause() : c.play(),
                icon: Icon(v.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
              ),
              IconButton(
                color: Colors.white,
                tooltip: '10 soniya orqaga',
                onPressed: () =>
                    c.seekTo(pos - const Duration(seconds: 10)),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              Expanded(
                child: Slider(
                  value: pos.inMilliseconds
                      .clamp(0, dur.inMilliseconds)
                      .toDouble(),
                  max: dur.inMilliseconds <= 0
                      ? 1
                      : dur.inMilliseconds.toDouble(),
                  onChanged: (x) =>
                      c.seekTo(Duration(milliseconds: x.round())),
                ),
              ),
              Text(
                '${_fmt(pos)} / ${_fmt(dur)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
