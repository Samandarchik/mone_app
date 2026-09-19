// shef/ui/widgets/biscuit_3d.dart — biskvitning O'ZI (kremsiz, bezaksiz) 3D
// ko'rinishi: tepasi pishgan oltin-jigarrang qobiq, yon tomoni g'ovakli
// sariq biskvit, pasti qizargan chiziq. O'lcham тех картадан (BiscuitDims):
// round — diameter_cm, rect — width_cm × length_cm, balandlik — height_cm.
// Proporsiya haqiqiy (sm → px bir xil masshtab); kichik biskvit patnisda
// kichikroq ko'rinadi. Kiritilmagan o'lcham — taxminiy (20 sm / 5 sm) va
// yorliqda «kiritilmagan» deb yoziladi.
// Biscuit3DView — Rotating3DView (cake_3d.dart) qobig'ida: aylanadi, suriladi,
// burchak nuqtalari; tepa chapda nom va o'lcham yorlig'i.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_3d.dart';

const Color _crustLight = Color(0xFFE0B066);
const Color _crust = Color(0xFFC4843D);
const Color _crustDark = Color(0xFFA8692E);
const Color _sponge = Color(0xFFF2CE7E);
const Color _spongeShade = Color(0xFFD9A94F);
const Color _spongeLight = Color(0xFFFBE3A8);
const Color _pore = Color(0xFFC0913F);
const Color _baked = Color(0xFFB9793A);

// Biskvit o'lchami (sm). [known] — тех картада kiritilganmi.
class BiscuitDims {
  final bool rect;
  final int diameterCm;
  final int widthCm;
  final int lengthCm;
  final int heightCm;
  final bool sizeKnown;
  final bool heightKnown;

  const BiscuitDims({
    this.rect = false,
    this.diameterCm = 20,
    this.widthCm = 30,
    this.lengthCm = 40,
    this.heightCm = 5,
    this.sizeKnown = false,
    this.heightKnown = false,
  });

  factory BiscuitDims.fromTechCard(TechCard? card) {
    if (card == null) return const BiscuitDims();
    int? pos(int? v) => (v != null && v > 0) ? v : null;
    final h = pos(card.heightCm);
    if (card.shape == 'rect') {
      final w = pos(card.widthCm);
      final l = pos(card.lengthCm);
      return BiscuitDims(
        rect: true,
        widthCm: w ?? l ?? 30,
        lengthCm: l ?? w ?? 40,
        heightCm: h ?? 5,
        sizeKnown: w != null || l != null,
        heightKnown: h != null,
      );
    }
    final d = pos(card.diameterCm);
    return BiscuitDims(
      diameterCm: d ?? 20,
      heightCm: h ?? 5,
      sizeKnown: d != null,
      heightKnown: h != null,
    );
  }

  // «Ø 20 sm · h 5 sm» / «30×40 sm · h 5 sm».
  String get label {
    if (!sizeKnown && !heightKnown) return 'O\'lcham kiritilmagan';
    final size = !sizeKnown
        ? 'o\'lcham —'
        : rect
            ? '$widthCm×$lengthCm sm'
            : 'Ø $diameterCm sm';
    final h = heightKnown ? 'h $heightCm sm' : 'h —';
    return '$size · $h';
  }

  @override
  bool operator ==(Object other) =>
      other is BiscuitDims &&
      other.rect == rect &&
      other.diameterCm == diameterCm &&
      other.widthCm == widthCm &&
      other.lengthCm == lengthCm &&
      other.heightCm == heightCm;

  @override
  int get hashCode =>
      Object.hash(rect, diameterCm, widthCm, lengthCm, heightCm);
}

class Biscuit3DView extends StatelessWidget {
  final BiscuitDims dims;
  final String title;
  final double height;

  const Biscuit3DView({
    super.key,
    required this.dims,
    required this.title,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Rotating3DView(
          height: height,
          painter: (tilt, rotation) =>
              BiscuitPainter(dims: dims, tilt: tilt, rotation: rotation),
        ),
        Positioned(
          left: 10,
          top: 10,
          right: 10,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E2A4F),
                    ),
                  ),
                  Text(
                    dims.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: dims.sizeKnown
                          ? const Color(0xFF8B6A2F)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BiscuitPainter extends CustomPainter {
  final BiscuitDims dims;
  final double tilt;
  final double rotation;

  BiscuitPainter({
    required this.dims,
    required this.tilt,
    required this.rotation,
  });

  late double _cx;
  late double _cos;
  late double _sin;

  (Offset, double) _project(double lx, double lz, double levelY) {
    final px = lx * _cos + lz * _sin;
    final pz = -lx * _sin + lz * _cos;
    return (Offset(_cx + px, levelY + pz * tilt), pz);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _cx = size.width / 2;
    _cos = math.cos(rotation);
    _sin = math.sin(rotation);

    // Tepa chapdagi yorliq (nom + o'lcham) biskvitni yopmasin.
    const labelInset = 46.0;
    final areaH = size.height - labelInset;
    final plateRx = math.min(size.width * 0.42, areaH * 0.62);
    final plateRy = plateRx * tilt;
    final plateThick = plateRx * 0.05;

    // sm → px: eng katta yarim o'lcham patnisning ~88% iga sig'adi; 14 sm dan
    // kichik biskvitlar haqiqiy nisbatda kichikroq ko'rinadi.
    final halfCm = dims.rect
        ? math.sqrt(dims.widthCm * dims.widthCm +
                dims.lengthCm * dims.lengthCm) /
            2
        : dims.diameterCm / 2;
    final pxPerCm = plateRx * 0.88 / math.max(halfCm, 14);
    final extent = halfCm * pxPerCm;
    final h = math.min(dims.heightCm * pxPerCm, areaH * 0.34);

    final total = h + extent * tilt + plateRy + plateThick;
    final plateY =
        labelInset + (areaH + total) / 2 - plateRy - plateThick;
    final bottom = plateY;
    final top = bottom - h;

    paintPlate3D(canvas, Offset(_cx, plateY), plateRx, plateRy, plateThick);

    // Biskvit tagidagi soya.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(_cx, bottom + extent * tilt * 0.12),
        width: extent * 2.1,
        height: extent * tilt * 2.2,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    if (dims.rect) {
      _paintRect(canvas, dims.widthCm * pxPerCm / 2,
          dims.lengthCm * pxPerCm / 2, top, bottom, h, pxPerCm);
    } else {
      _paintRound(canvas, dims.diameterCm * pxPerCm / 2, top, bottom, h,
          pxPerCm);
    }
  }

  void _paintRound(Canvas canvas, double r, double top, double bottom,
      double h, double pxPerCm) {
    final bottomOval = Rect.fromCenter(
      center: Offset(_cx, bottom),
      width: r * 2,
      height: r * 2 * tilt,
    );
    final side = Path()
      ..addOval(bottomOval)
      ..addRect(Rect.fromLTRB(_cx - r, top, _cx + r, bottom));
    canvas.drawPath(
      side,
      Paint()
        ..shader = const LinearGradient(
          colors: [_spongeShade, _sponge, _spongeLight, _sponge, _spongeShade],
          stops: [0, 0.3, 0.42, 0.62, 1],
        ).createShader(bottomOval),
    );

    canvas.save();
    canvas.clipPath(side);
    // Pastki qizargan chiziq.
    canvas.drawArc(
      bottomOval,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.22
        ..color = _baked.withValues(alpha: 0.75),
    );
    // G'ovaklar — biskvit bilan birga aylanadi.
    final rnd = math.Random(3);
    final pore = Paint()..color = _pore.withValues(alpha: 0.55);
    for (var i = 0; i < 160; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final v = 0.14 + rnd.nextDouble() * 0.72;
      final s = pxPerCm * (0.12 + rnd.nextDouble() * 0.2);
      final t = a + rotation;
      final c = math.cos(t);
      if (c < 0.08) continue; // orqa tomonda
      final x = _cx + r * math.sin(t);
      final y = top + r * tilt * c + v * h;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: s * c + 0.6, height: s * 0.8),
        pore,
      );
    }
    canvas.restore();

    // Tepa — pishgan qobiq.
    final topOval = bottomOval.shift(Offset(0, -h));
    canvas.drawOval(
      topOval,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.15, -0.2),
          radius: 0.85,
          colors: [_crustLight, _crust, _crustDark],
          stops: [0, 0.7, 1],
        ).createShader(topOval),
    );
    // Yengil gumbaz yaltirog'i.
    canvas.drawOval(
      Rect.fromCenter(
        center: topOval.center.translate(-r * 0.18, -r * tilt * 0.2),
        width: r * 0.9,
        height: r * tilt * 0.8,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
    canvas.drawOval(
      topOval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF9C5F28).withValues(alpha: 0.6),
    );
  }

  void _paintRect(Canvas canvas, double hw, double hl, double top,
      double bottom, double h, double pxPerCm) {
    final local = [(-hw, -hl), (hw, -hl), (hw, hl), (-hw, hl)];
    final tops = [for (final (x, z) in local) _project(x, z, top).$1];
    final bottoms = [for (final (x, z) in local) _project(x, z, bottom).$1];
    final rnd = math.Random(3);
    final pore = Paint()..color = _pore.withValues(alpha: 0.55);

    for (var k = 0; k < 4; k++) {
      final k1 = (k + 1) % 4;
      // Yon yuz normali (o'q bo'yicha birlik vektor).
      final nx = (local[k].$1 + local[k1].$1) / 2 / hw;
      final nz = (local[k].$2 + local[k1].$2) / 2 / hl;
      final npx = nx * _cos + nz * _sin;
      final npz = -nx * _sin + nz * _cos;
      if (npz <= 0) continue;
      final f = (0.55 - 0.35 * npx + 0.15 * npz).clamp(0.0, 1.0);
      final face = Path()
        ..addPolygon([tops[k], tops[k1], bottoms[k1], bottoms[k]], true);
      canvas.drawPath(
          face, Paint()..color = Color.lerp(_spongeShade, _spongeLight, f)!);

      canvas.save();
      canvas.clipPath(face);
      canvas.drawLine(
        bottoms[k],
        bottoms[k1],
        Paint()
          ..strokeWidth = h * 0.22
          ..color = _baked.withValues(alpha: 0.75),
      );
      final edgeLen = (tops[k1] - tops[k]).distance;
      final n = (edgeLen / pxPerCm * 2.2).round().clamp(8, 90);
      for (var i = 0; i < n; i++) {
        final u = rnd.nextDouble();
        final v = 0.14 + rnd.nextDouble() * 0.72;
        final s = pxPerCm * (0.12 + rnd.nextDouble() * 0.2);
        final p = Offset.lerp(tops[k], tops[k1], u)!.translate(0, v * h);
        canvas.drawOval(
          Rect.fromCenter(
              center: p, width: s * (0.4 + 0.6 * npz) + 0.6, height: s * 0.8),
          pore,
        );
      }
      canvas.restore();
      canvas.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _spongeShade.withValues(alpha: 0.5),
      );
    }

    final topPath = Path()..addPolygon(tops, true);
    final bounds = topPath.getBounds();
    canvas.drawPath(
      topPath,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.15, -0.2),
          radius: 0.8,
          colors: [_crustLight, _crust, _crustDark],
          stops: [0, 0.7, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      topPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF9C5F28).withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(BiscuitPainter old) =>
      old.dims != dims || old.tilt != tilt || old.rotation != rotation;
}
