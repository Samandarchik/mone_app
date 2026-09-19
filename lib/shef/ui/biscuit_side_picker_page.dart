// shef/ui/biscuit_side_picker_page.dart — biskvit fotosida YON TOMON
// (ichi / chetlari: qatlamlar, rezavorlar, mevalar ko'rinadigan joy)
// tasmasini tanlash: BiscuitSidePickerPage. Fotoda ramka surib qo'yiladi
// (o'rtasidan tortish — joyini, pastki tutqich — balandligini o'zgartiradi),
// pastda o'sha zahoti 3D biskvit shu tasma bilan chiziladi.
// Natija — (topPm, hPm): rasm balandligining ‰ ulushi (BUTUN son).
// TechCardEditorPage «Biskvit fotosi» bo'limidan ochiladi.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';

class BiscuitSidePickerPage extends StatefulWidget {
  final String photoUrl; // to'liq URL
  final int topPm;
  final int hPm;
  final BiscuitDims dims;
  final BiscuitPalette palette;

  const BiscuitSidePickerPage({
    super.key,
    required this.photoUrl,
    required this.topPm,
    required this.hPm,
    required this.dims,
    required this.palette,
  });

  @override
  State<BiscuitSidePickerPage> createState() => _BiscuitSidePickerPageState();
}

class _BiscuitSidePickerPageState extends State<BiscuitSidePickerPage> {
  // Ulushlar 0..1 (ekranda); saqlashda ‰ butun songa aylanadi.
  late double _top;
  late double _h;

  static const double _minH = 0.06;

  @override
  void initState() {
    super.initState();
    _h = widget.hPm > 0 ? widget.hPm / 1000 : 0.3;
    _top = widget.hPm > 0 ? widget.topPm / 1000 : 0.35;
    _clamp();
  }

  void _clamp() {
    _h = _h.clamp(_minH, 1.0);
    _top = _top.clamp(0.0, 1.0 - _h);
  }

  BiscuitPhoto get _photo => BiscuitPhoto(
        url: widget.photoUrl,
        topPm: (_top * 1000).round(),
        hPm: (_h * 1000).round(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6F1),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6F1),
        elevation: 0,
        title: const Text(
          'Biskvit yon tomoni',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              (_photo.topPm, _photo.hPm),
            ),
            child: const Text(
              'Tayyor',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            'Ramkani fotodagi biskvitning YON tomoniga (ichi, qatlamlari, '
            'rezavor/mevalari ko\'rinadigan joyga) qo\'ying. O\'rtasidan '
            'tortib suring, pastki tutqich — balandligi.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          BiscuitSideLoader(
            photo: BiscuitPhoto(url: widget.photoUrl),
            displayWidth: 600,
            builder: (context, side) {
              if (side == null) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                );
              }
              final img = side.image;
              return AspectRatio(
                aspectRatio: img.width / img.height,
                child: LayoutBuilder(
                  builder: (context, box) => _bandEditor(
                    RawImage(image: img, fit: BoxFit.fill),
                    box.maxHeight,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            '3D ko\'rinishi',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Biscuit3DView(
            height: 220,
            dims: widget.dims,
            palette: widget.palette,
            photo: _photo,
          ),
        ],
      ),
    );
  }

  // Foto + ustida tasma ramkasi (tashqarisi xiralashtirilgan).
  Widget _bandEditor(Widget image, double height) {
    final top = _top * height;
    final h = _h * height;
    const handle = 28.0;
    final shade = Colors.black.withValues(alpha: 0.45);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Positioned.fill(child: image),
          Positioned(left: 0, right: 0, top: 0, height: top,
              child: ColoredBox(color: shade)),
          Positioned(left: 0, right: 0, top: top + h, bottom: 0,
              child: ColoredBox(color: shade)),
          // Ramka: o'rtasidan tortish — joyini surish.
          Positioned(
            left: 0,
            right: 0,
            top: top,
            height: h,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() {
                _top += d.delta.dy / height;
                _clamp();
              }),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
          ),
          // Pastki tutqich — balandlik.
          Positioned(
            left: 0,
            right: 0,
            top: math.max(0, top + h - handle / 2),
            height: handle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() {
                _h += d.delta.dy / height;
                _clamp();
              }),
              child: Center(
                child: Container(
                  width: 56,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.unfold_more, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
