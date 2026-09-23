// shef/ui/widgets/cake_photo_view.dart — TAYYOR TORTNI KO'RSATISH
// (CakePhotoView): tort konstruktori 3-qadami («Tort»). Bu yerda HECH QANDAY
// 3D qurilmaydi va foto qayta chizilmaydi — tortning O'Z fotosi shundayligicha
// ko'rsatiladi, faqat EKRANDAGI O'LCHAMI tex kartadagi diametrga qarab
// beriladi: Ø 30 sm tort blokni to'ldiradi, Ø 16 sm esa ancha kichik chiqadi.
// Shunday qilib turli tortlar bir-biriga nisbatan to'g'ri kattalikda ko'rinadi.
//
// NEGA SHUNDAY: avval foto siluetidan 3D model qurilardi
// (cake_photo_3d.dart). Mone fotolarida tort OQ patnis ustida, fon ham oq —
// siluet patnis bilan qo'shilib ketardi va model goh patnisdan qurilar, goh
// tortning oq qismlari kesilib «bel» hosil bo'lardi. Bitta fotodan ishonchli
// geometriya chiqmadi, shuning uchun bu yo'l butunlay olib tashlandi.
//
// O'lcham: yumaloq tortda diametr, to'rtburchakda eng uzun tomon.
// Tex kartada o'lcham yo'q bo'lsa foto to'liq kenglikda ko'rsatiladi va
// ostida «o'lchamni tex kartaga kiriting» eslatmasi chiqadi.
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

const Color _heroTop = Color(0xFFFFFFFF);
const Color _heroBottom = Color(0xFFE6DDF3);

// Blokni to'ldiradigan o'lcham (sm). Bundan kattasi ham to'liq kenglikda.
const double _fullSizeCm = 30;
// Eng kichik ko'rsatish ulushi — Ø 10 sm tort ham ko'rinib tursin.
const double _minFraction = 0.42;

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

/// Fotoning blok kengligidagi ulushi (0.42 … 1.0). O'lcham yo'q — 1.0.
double cakeSizeFraction(TechCard? card) {
  final cm = cakeSizeCm(card);
  if (cm <= 0) return 1;
  return (cm / _fullSizeCm).clamp(_minFraction, 1.0);
}

/// «Ø 26 sm · 8 sm» / «30×40 sm · 5 sm» — bo'lgan qismlaridan; yo'q — ''.
String cakeSizeLabel(TechCard? card) {
  if (card == null) return '';
  final parts = <String>[];
  final d = card.diameterCm ?? 0;
  final w = card.widthCm ?? 0;
  final l = card.lengthCm ?? 0;
  final h = card.heightCm ?? 0;
  if (d > 0) {
    parts.add('Ø $d sm');
  } else if (w > 0 && l > 0) {
    parts.add('$w×$l sm');
  }
  if (h > 0) parts.add('balandligi $h sm');
  return parts.join(' · ');
}

class CakePhotoView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final label = cakeSizeLabel(card);
    final fraction = cakeSizeFraction(card);
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_heroTop, _heroBottom],
          ),
        ),
        child: Stack(
          children: [
            // Foto — markazda, nisbati saqlanib (contain), o'lchami tex
            // kartadagi diametrga qarab.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth * fraction;
                  return Center(
                    child: SizedBox(
                      width: side,
                      // Yozuv qatoriga joy qoldiramiz.
                      height: (box.maxHeight - 26).clamp(24.0, box.maxHeight),
                      child: AppNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
            // O'lcham yozuvi (yoki eslatma) — pastda.
            Positioned(
              left: 8,
              right: 8,
              bottom: 6,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    label.isEmpty
                        ? 'O\'lcham tex kartada ko\'rsatilmagan'
                        : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: label.isEmpty
                          ? Colors.grey.shade600
                          : Colors.brown.shade800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
