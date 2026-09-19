// shef/ui/widgets/cake_3d.dart — Biskvit bo'limidagi 3D tort ko'rinishi
// (konstruktor uslubida): patnis ustidagi silindr tort, yon tomoni hajmli
// soyali, tepa cheti bo'ylab krem marvaridlari. Model/plagin YO'Q — hammasi
// CustomPainter bilan chiziladi (asset va WebView'siz, yengil).
// Cake3DHero — tepadagi katta ko'rinish: sekin o'zi aylanadi, yon tomonga
// surilsa aylanadi; bosish / nuqtalar — 3 ta burchak (yondan, tepadan, past). Cake3D — kichik statik variant
// (rasmi yo'q kategoriya kartasi uchun).
import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color _cream = Color(0xFFF1E4C6);
const Color _creamShade = Color(0xFFD9C49A);
const Color _heroTop = Color(0xFFFFFFFF);
const Color _heroBottom = Color(0xFFE6DDF3);
const Color _dotActive = Color(0xFF8E83B8);

// Ko'rinish burchaklari: ellips balandligi / kengligi nisbati
// (0 — yondan, 1 — tepadan).
const List<double> _tilts = [0.26, 0.48, 0.14];

class Cake3DHero extends StatefulWidget {
  final double height;

  const Cake3DHero({super.key, this.height = 260});

  @override
  State<Cake3DHero> createState() => _Cake3DHeroState();
}

class _Cake3DHeroState extends State<Cake3DHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();
  int _page = 0;
  // Barmoq bilan surilgan qo'shimcha burilish (radian).
  double _drag = 0;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: widget.height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_heroTop, _heroBottom],
              ),
            ),
            child: GestureDetector(
              // Gorizontal surish — aylantirish (vertikal — sahifa scroll'i).
              onHorizontalDragUpdate: (d) =>
                  setState(() => _drag += d.delta.dx * 0.015),
              // Bosish — keyingi burchak.
              onTap: () => setState(() => _page = (_page + 1) % _tilts.length),
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _tilts[_page]),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  builder: (context, tilt, _) => AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _CakePainter(
                        tilt: tilt,
                        rotation: _spin.value * 2 * math.pi + _drag,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _tilts.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _page = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page ? _dotActive : Colors.grey.shade300,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// Kichik statik 3D tort (animatsiyasiz).
class Cake3D extends StatelessWidget {
  final double tilt;

  const Cake3D({super.key, this.tilt = 0.26});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _CakePainter(tilt: tilt, rotation: 0.6),
    );
  }
}

class _CakePainter extends CustomPainter {
  final double tilt;
  final double rotation;

  _CakePainter({required this.tilt, required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Tort + patnis ko'rinish maydoniga sig'ishi uchun o'lcham.
    final plateRx = math.min(size.width * 0.42, size.height * 0.62);
    final plateRy = plateRx * tilt;
    final cakeRx = plateRx * 0.62;
    final cakeRy = cakeRx * tilt;
    final cakeH = cakeRx * 0.78;
    final plateThick = plateRx * 0.05;

    // Tort tepasidan patnis ostigacha bo'lgan balandlik — markazlash uchun.
    final total = cakeH + cakeRy + plateRy + plateThick;
    final plateY = (size.height + total) / 2 - plateRy - plateThick;
    final bottomY = plateY;
    final topY = bottomY - cakeH;

    // 1. Patnis ostidagi yumshoq soya.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, plateY + plateThick + plateRy * 0.35),
        width: plateRx * 2.1,
        height: plateRy * 2.2 + 6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 2. Patnis: qalinligi (kumush chet) + ustki oq yuzasi.
    final plateTop = Rect.fromCenter(
      center: Offset(cx, plateY),
      width: plateRx * 2,
      height: plateRy * 2,
    );
    final plateEdge = Path()
      ..addOval(plateTop.shift(Offset(0, plateThick)))
      ..addRect(Rect.fromLTRB(plateTop.left, plateY, plateTop.right,
          plateY + plateThick));
    canvas.drawPath(
      plateEdge,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF9E97A8), Color(0xFFE9E6EE), Color(0xFFA8A1B2)],
        ).createShader(plateTop),
    );
    canvas.drawOval(
      plateTop,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.2, -0.4),
          radius: 0.9,
          colors: [Color(0xFFFFFFFF), Color(0xFFE4E1EA)],
        ).createShader(plateTop),
    );

    // 3. Tort tagidagi soya patnis ustida.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, bottomY + cakeRy * 0.15),
        width: cakeRx * 2.12,
        height: cakeRy * 2.3,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 4. Tort yon tomoni — silindr: ostki yarim ellips + to'rtburchak.
    final bottomOval = Rect.fromCenter(
      center: Offset(cx, bottomY),
      width: cakeRx * 2,
      height: cakeRy * 2,
    );
    final topOval = bottomOval.shift(Offset(0, -cakeH));
    final side = Path()
      ..addOval(bottomOval)
      ..addRect(Rect.fromLTRB(bottomOval.left, topY, bottomOval.right, bottomY));
    // Yorug'lik aylanish bilan biroz siljiydi — hajm hissi.
    final light = 0.35 * math.sin(rotation);
    canvas.drawPath(
      side,
      Paint()
        ..shader = LinearGradient(
          colors: const [_creamShade, _cream, Color(0xFFFBF3E2), _cream,
              _creamShade],
          stops: [
            0,
            (0.30 + light * 0.3).clamp(0.05, 0.9),
            (0.42 + light * 0.3).clamp(0.1, 0.95),
            (0.62 + light * 0.3).clamp(0.15, 0.97),
            1,
          ],
        ).createShader(bottomOval),
    );
    // Ostki chetdagi yengil qoramtir chiziq — tort patnisga tegib turadi.
    canvas.drawArc(
      bottomOval,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _creamShade.withValues(alpha: 0.8),
    );

    // 5. Tepa yuzasi.
    canvas.drawOval(
      topOval,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.2),
          radius: 0.95,
          colors: [Color(0xFFFDF7EA), _cream],
        ).createShader(topOval),
    );
    canvas.drawOval(
      topOval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.7),
    );

    // 6. Tepa cheti bo'ylab krem marvaridlari — aylanishni ko'rsatadi.
    // Orqadagilar avval (kichikroq, xiraroq), oldindagilar keyin chiziladi.
    const n = 18;
    final pearls = <(double depth, Offset pos)>[];
    for (var i = 0; i < n; i++) {
      final t = rotation + i * 2 * math.pi / n;
      final x = cx + cakeRx * 0.9 * math.sin(t);
      final depth = math.cos(t); // 1 — oldinda, -1 — orqada
      final y = topY + cakeRy * 0.9 * depth;
      pearls.add((depth, Offset(x, y)));
    }
    pearls.sort((a, b) => a.$1.compareTo(b.$1));
    final r0 = cakeRx * 0.07;
    for (final (depth, pos) in pearls) {
      final r = r0 * (0.85 + 0.15 * depth);
      final rect = Rect.fromCircle(center: pos, radius: r);
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.35, -0.45),
            colors: [Color(0xFFFFFFFF), Color(0xFFEAD9B4)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_CakePainter old) =>
      old.tilt != tilt || old.rotation != rotation;
}
