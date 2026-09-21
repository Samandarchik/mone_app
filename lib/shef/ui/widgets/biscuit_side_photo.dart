// shef/ui/widgets/biscuit_side_photo.dart — tex kartadagi biskvit FOTOSINI
// 3D chizma uchun yuklash (BiscuitSidePhotoBuilder): foto AppNetworkImage
// keshi orqali kichraytirib yuklanadi va ui.Image holida builder'ga beriladi
// — BiscuitPainter uni biskvitning YON TOMONIGA o'raydi (biscuit_3d.dart).
// Fotodan hech narsa «taxmin qilinmaydi» (rang, meva ...): shef yuklagan
// rasmning o'zi ko'rsatiladi. Yuklanguncha / foto yo'q bo'lsa — null
// (yon tomon oddiy biskvit bo'lib chiziladi).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

class BiscuitSidePhotoBuilder extends StatefulWidget {
  final String? url; // to'liq URL yoki null
  // Ekrandagi taxminiy kenglik (dp) — dekod o'lchami shundan.
  final double displayWidth;
  final Widget Function(BuildContext context, ui.Image? photo) builder;

  const BiscuitSidePhotoBuilder({
    super.key,
    required this.url,
    required this.displayWidth,
    required this.builder,
  });

  @override
  State<BiscuitSidePhotoBuilder> createState() =>
      _BiscuitSidePhotoBuilderState();
}

class _BiscuitSidePhotoBuilderState extends State<BiscuitSidePhotoBuilder> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  String? _url;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BiscuitSidePhotoBuilder old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    if (url == _url) return;
    _url = url;
    _unlisten();
    // didChangeDependencies / didUpdateWidget'dan keyin build baribir
    // chaqiriladi — setState kerak emas.
    _image?.dispose();
    _image = null;
    if (url == null) return;
    final provider = appNetworkImageProvider(
      context,
      url,
      displayWidth: widget.displayWidth,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        // Kesh rasmni chiqarib yuborsa ham bizniki yashashi uchun nusxa.
        final img = info.image.clone();
        info.dispose();
        if (!mounted || _url != url) {
          img.dispose();
          return;
        }
        final old = _image;
        setState(() => _image = img);
        old?.dispose();
      },
      onError: (_, __) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _unlisten() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _image);
}
