import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/media_cache.dart';
import '../theme/app_theme.dart';

/// Menyu rasmi — diskdagi keshdan ko'rsatadi, bo'lmasa asosiy (online)
/// serverdan yuklab oladi va saqlab qo'yadi. Batafsil: [MediaCache].
///
/// [path] — bazadagi nisbiy manzil (`/uploads/products/12_1755.jpg`).
class MediaImage extends StatefulWidget {
  final String? path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Rasm yo'q yoki yuklanmadi — nima ko'rsatiladi.
  final Widget? placeholder;

  const MediaImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  Future<File?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MediaImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    final path = widget.path;
    _future = (path == null || path.isEmpty) ? null : MediaCache().fetch(path);
  }

  Widget get _placeholder =>
      widget.placeholder ??
      const Icon(Icons.fastfood_rounded, size: 26, color: AppColors.textFaint);

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    if (path == null || path.isEmpty) return _placeholder;

    if (kIsWeb) {
      return Image.network(
        '${ApiService().mediaBaseUrl}$path',
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, _, _) => _placeholder,
      );
    }

    return FutureBuilder<File?>(
      future: _future,
      builder: (context, snap) {
        final file = snap.data;
        // Yuklanayotgan paytda ham placeholder — POS gridida aylanma
        // indikatorlar ko'zni oladi, rasm kelganda o'zi almashadi.
        if (file == null) return _placeholder;
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) {
            // Fayl buzilgan — keshdan olib tashlaymiz, keyingi ochilishda
            // qaytadan yuklanadi.
            MediaCache().evict(path);
            return _placeholder;
          },
        );
      },
    );
  }
}
