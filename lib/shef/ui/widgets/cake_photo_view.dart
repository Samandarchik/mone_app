// shef/ui/widgets/cake_photo_view.dart — TAYYOR TORTNI KO'RSATISH
// (CakePhotoView): tort konstruktori 3-qadami («Tort»). Bu yerda HECH QANDAY
// 3D qurilmaydi va tort qayta chizilmaydi — tortning O'Z fotosi ko'rsatiladi,
// lekin:
//   • FONI OLIB TASHLANADI va rasm tortning chetlarigacha QIRQILADI
//     (cake_cutout.dart) — tort blok foniga «yotqizilgan» va yaqinroq
//     ko'rinadi, atrofida bo'sh oq joy qolmaydi;
//   • EKRANDAGI O'LCHAMI tex kartadagi o'lchamdan olinadi: barcha tortlar
//     uchun BITTA sm→piksel masshtabi. Ø 30 sm tort blokni to'ldiradi,
//     Ø 16 sm esa taxminan yarmini egallaydi — tortlar bir-biriga nisbatan
//     to'g'ri kattalikda ko'rinadi. Yozuv bilan emas, RASMNING O'ZI bilan.
// Yumaloq tortda diametr, to'rtburchakda eng uzun tomon (uzunlik) olinadi.
// Tex kartada o'lcham yo'q bo'lsa — rasm blokka to'liq sig'adi.
//
// NEGA 3D YO'Q: avval foto siluetidan model qurilardi (cake_photo_3d.dart).
// Mone fotolarida tort OQ patnis ustida, fon ham oq — siluet patnis bilan
// qo'shilib ketardi va model goh patnisdan qurilardi. Bitta fotodan
// ishonchli geometriya chiqmadi, shuning uchun bu yo'l tashlandi.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_cutout.dart';

// Blok kengligiga to'g'ri keladigan o'lcham (sm): shu masshtab HAMMA tort
// uchun bir xil, shuning uchun tortlar o'zaro solishtirib ko'rinadi.
const double _fullWidthCm = 32;

/// Tex kartadagi o'lcham (sm): yumaloq — diametr, to'rtburchak — eng uzun
/// tomon. 0 — kiritilmagan.
int cakeSizeCm(TechCard? card) {
  if (card == null) return 0;
  final d = card.diameterCm ?? 0;
  if (d > 0) return d;
  final w = card.widthCm ?? 0;
  final l = card.lengthCm ?? 0;
  final m = w > l ? w : l;
  return m > 0 ? m : 0;
}

/// Rasmning blok kengligidagi ulushi. O'lcham yo'q — 1.0 (to'liq sig'adi).
/// Katta tort blokdan oshmaydi, juda kichigi ham ko'rinib turadi.
double cakeSizeFraction(TechCard? card) {
  final cm = cakeSizeCm(card);
  if (cm <= 0) return 1;
  return (cm / _fullWidthCm).clamp(0.22, 1.0);
}

class CakePhotoView extends StatefulWidget {
  final String imageUrl;
  final TechCard? card;
  final double height;
  final BorderRadius borderRadius;

  const CakePhotoView({
    super.key,
    required this.imageUrl,
    required this.card,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<CakePhotoView> createState() => _CakePhotoViewState();
}

class _CakePhotoViewState extends State<CakePhotoView> {
  ui.Image? _cut;
  // true — fonni olib tashlab bo'lmadi (yoki rasm yuklanmadi): ASL foto
  // ko'rsatiladi, tort baribir ko'rinib tursin.
  bool _raw = false;

  @override
  void initState() {
    super.initState();
    // context (MediaQuery) birinchi kadrdan keyin ishonchli.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(CakePhotoView old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) {
      setState(() {
        _cut = null;
        _raw = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.imageUrl;
    if (!mounted) return;
    try {
      final c = await CakeCutout.load(context, url);
      if (!mounted || url != widget.imageUrl) return;
      setState(() {
        if (c.ok) {
          _cut = c.image;
        } else {
          _raw = true;
        }
      });
    } catch (e) {
      debugPrint('CakePhotoView: $url — $e');
      if (!mounted || url != widget.imageUrl) return;
      setState(() => _raw = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = cakeSizeFraction(widget.card);
    final cut = _cut;
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, box) {
            // Kenglik — tex kartadagi o'lchamdan; balandlik rasmning O'Z
            // nisbatidan (cho'zilmaydi) va blokdan oshmaydi.
            final wantW = box.maxWidth * fraction;
            return Center(
              child: SizedBox(
                width: wantW,
                height: box.maxHeight,
                child: cut != null
                    ? RawImage(
                        image: cut,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      )
                    // Fonni olib tashlab bo'lmadi — asl foto.
                    : _raw
                        ? AppNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.contain,
                          )
                        // Tayyorlanmoqda (odatda < 1 s) — ikki marta
                        // yuklamaslik uchun asl foto chizilmaydi.
                        : const SizedBox.shrink(),
              ),
            );
          },
        ),
      ),
    );
  }
}
