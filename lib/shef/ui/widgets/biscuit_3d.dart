// shef/ui/widgets/biscuit_3d.dart — biskvitning O'ZI (kremsiz, bezaksiz) 3D
// ko'rinishi: tepasi pishgan oltin-jigarrang qobiq, yon tomoni g'ovakli
// sariq biskvit, pasti qizargan chiziq. O'lcham тех картадан (BiscuitDims):
// round — diameter_cm, rect — width_cm × length_cm, balandlik — height_cm.
// Proporsiya haqiqiy (sm → px bir xil masshtab); kichik biskvit patnisda
// kichikroq ko'rinadi. Kiritilmagan o'lcham — taxminiy (20 sm / 5 sm).
// Тех карта o'zgarsa (masalan balandlik qo'shilsa) — dims yangi kartadan
// qayta olinadi va chizma darhol o'zgaradi.
// Rangi biskvit TURIdan (BiscuitPalette.detect): mahsulot nomi → blok
// nomlari → masalliqlar kalit so'zlari (шоколад/какао → shokoladli,
// красный бархат → qizil, морковь → sabzi sepkili, мак → qora sepkil ...).
// Biscuit3DView — Rotating3DView (cake_3d.dart) qo'lda rejimida: barmoq yon
// tomonga — burish, tepaga/pastga — qarash burchagi. Yozuv/nuqtalar yo'q.
// BiscuitThumb — grid kartasi uchun kichik statik rasm.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_3d.dart';

// Biskvit o'lchami (sm).
class BiscuitDims {
  final bool rect;
  final int diameterCm;
  final int widthCm;
  final int lengthCm;
  final int heightCm;

  const BiscuitDims({
    this.rect = false,
    this.diameterCm = 20,
    this.widthCm = 30,
    this.lengthCm = 40,
    this.heightCm = 5,
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
      );
    }
    return BiscuitDims(
      diameterCm: pos(card.diameterCm) ?? 20,
      heightCm: h ?? 5,
    );
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

// Biskvit ranglari (turi bo'yicha): yon tomon (sponge*), tepa qobiq (crust*),
// g'ovak, pastki qizargan chiziq, tepa cheti va ixtiyoriy sepkil (mak,
// sabzi bo'lakchalari, yong'oq ...).
class BiscuitPalette {
  final Color sponge;
  final Color spongeShade;
  final Color spongeLight;
  final Color crustLight;
  final Color crust;
  final Color crustDark;
  final Color pore;
  final Color baked;
  final Color rim;
  final Color? speck;

  const BiscuitPalette({
    required this.sponge,
    required this.spongeShade,
    required this.spongeLight,
    required this.crustLight,
    required this.crust,
    required this.crustDark,
    required this.pore,
    required this.baked,
    required this.rim,
    this.speck,
  });

  // Klassik (vanil) biskvit.
  static const classic = BiscuitPalette(
    sponge: Color(0xFFF2CE7E),
    spongeShade: Color(0xFFD9A94F),
    spongeLight: Color(0xFFFBE3A8),
    crustLight: Color(0xFFE0B066),
    crust: Color(0xFFC4843D),
    crustDark: Color(0xFFA8692E),
    pore: Color(0xFFC0913F),
    baked: Color(0xFFB9793A),
    rim: Color(0xFF9C5F28),
  );

  static const chocolate = BiscuitPalette(
    sponge: Color(0xFF6B4029),
    spongeShade: Color(0xFF4E2D1C),
    spongeLight: Color(0xFF8A5638),
    crustLight: Color(0xFF5E3823),
    crust: Color(0xFF4A2A1A),
    crustDark: Color(0xFF331C10),
    pore: Color(0xFF3A2114),
    baked: Color(0xFF2E190E),
    rim: Color(0xFF26140B),
  );

  static const redVelvet = BiscuitPalette(
    sponge: Color(0xFFB02A36),
    spongeShade: Color(0xFF861C27),
    spongeLight: Color(0xFFCC4450),
    crustLight: Color(0xFFA8323A),
    crust: Color(0xFF8C222C),
    crustDark: Color(0xFF6E1820),
    pore: Color(0xFF7A1822),
    baked: Color(0xFF5E121A),
    rim: Color(0xFF55101A),
  );

  static const carrot = BiscuitPalette(
    sponge: Color(0xFFD9964A),
    spongeShade: Color(0xFFB87533),
    spongeLight: Color(0xFFEBB273),
    crustLight: Color(0xFFC9823C),
    crust: Color(0xFFA9652A),
    crustDark: Color(0xFF8A4F1F),
    pore: Color(0xFF9E6128),
    baked: Color(0xFF7E4719),
    rim: Color(0xFF6E3E16),
    speck: Color(0xFFE8631C),
  );

  static const honey = BiscuitPalette(
    sponge: Color(0xFFE0A74E),
    spongeShade: Color(0xFFC0853A),
    spongeLight: Color(0xFFF0C77E),
    crustLight: Color(0xFFC98A3C),
    crust: Color(0xFFA86A28),
    crustDark: Color(0xFF8A531D),
    pore: Color(0xFFA9722F),
    baked: Color(0xFF8A531D),
    rim: Color(0xFF7A4818),
  );

  static const lemon = BiscuitPalette(
    sponge: Color(0xFFF7E48A),
    spongeShade: Color(0xFFE2C95E),
    spongeLight: Color(0xFFFFF3B8),
    crustLight: Color(0xFFE8C46A),
    crust: Color(0xFFD0A248),
    crustDark: Color(0xFFB5873A),
    pore: Color(0xFFCFB14C),
    baked: Color(0xFFC09040),
    rim: Color(0xFFA67A30),
  );

  static const pistachio = BiscuitPalette(
    sponge: Color(0xFFB7CC7A),
    spongeShade: Color(0xFF93AA58),
    spongeLight: Color(0xFFCFE09C),
    crustLight: Color(0xFFC9B060),
    crust: Color(0xFFA88E45),
    crustDark: Color(0xFF8A7336),
    pore: Color(0xFF7F964A),
    baked: Color(0xFF8A7336),
    rim: Color(0xFF6E5C2A),
  );

  static const berry = BiscuitPalette(
    sponge: Color(0xFFF0A3B2),
    spongeShade: Color(0xFFD9808F),
    spongeLight: Color(0xFFF9C5CF),
    crustLight: Color(0xFFDDA070),
    crust: Color(0xFFC4824F),
    crustDark: Color(0xFFA6683C),
    pore: Color(0xFFCC6F82),
    baked: Color(0xFFB0664A),
    rim: Color(0xFF94553A),
    speck: Color(0xFFB0203E),
  );

  static const coffee = BiscuitPalette(
    sponge: Color(0xFFB08058),
    spongeShade: Color(0xFF8E6240),
    spongeLight: Color(0xFFC79C76),
    crustLight: Color(0xFF9A6A44),
    crust: Color(0xFF7E5234),
    crustDark: Color(0xFF643F27),
    pore: Color(0xFF7A5234),
    baked: Color(0xFF5E3B24),
    rim: Color(0xFF52331F),
  );

  static const caramel = BiscuitPalette(
    sponge: Color(0xFFE3B070),
    spongeShade: Color(0xFFC48E4E),
    spongeLight: Color(0xFFF0CB98),
    crustLight: Color(0xFFCB8A45),
    crust: Color(0xFFAE6C2E),
    crustDark: Color(0xFF8E5522),
    pore: Color(0xFFB07A3E),
    baked: Color(0xFF8E5522),
    rim: Color(0xFF7A471C),
  );

  static const nut = BiscuitPalette(
    sponge: Color(0xFFD8B98A),
    spongeShade: Color(0xFFBB9866),
    spongeLight: Color(0xFFE9D2AE),
    crustLight: Color(0xFFC9975C),
    crust: Color(0xFFAC7A42),
    crustDark: Color(0xFF8E6133),
    pore: Color(0xFFA9885A),
    baked: Color(0xFF8E6133),
    rim: Color(0xFF7A522B),
    speck: Color(0xFF7A5230),
  );

  static const poppy = BiscuitPalette(
    sponge: Color(0xFFF1D89A),
    spongeShade: Color(0xFFD8BC74),
    spongeLight: Color(0xFFFAEAC0),
    crustLight: Color(0xFFDDB068),
    crust: Color(0xFFC08A42),
    crustDark: Color(0xFFA36F33),
    pore: Color(0xFFC4A060),
    baked: Color(0xFFB07A3A),
    rim: Color(0xFF94622B),
    speck: Color(0xFF26262E),
  );

  // Kalit so'zlar → rang (tartib muhim: birinchi mos kelgani olinadi).
  static const List<(List<String>, BiscuitPalette)> _rules = [
    (['красн', 'бархат', 'velvet', 'qizil'], redVelvet),
    (['шоколад', 'какао', 'брауни', 'chocolate', 'cocoa', 'shokolad', 'kakao'],
        chocolate),
    (['морков', 'carrot', 'sabzi'], carrot),
    (['мед', 'мёд', 'honey', 'asal'], honey),
    (['фисташ', 'pista', 'матча', 'matcha'], pistachio),
    (['клубни', 'малин', 'вишн', 'ягод', 'qulupnay', 'malina', 'olcha'], berry),
    (['кофе', 'coffee', 'qahva', 'kofe'], coffee),
    (['карамел', 'caramel', 'karamel'], caramel),
    (['лимон', 'lemon', 'limon'], lemon),
    (['мак', 'poppy'], poppy),
    (['орех', 'миндал', 'фундук', 'грецк', 'yong\'oq', 'bodom'], nut),
  ];

  static BiscuitPalette? _match(String text) {
    final t = text.toLowerCase();
    for (final (words, palette) in _rules) {
      for (final w in words) {
        // «мак» qisqa — so'z boshida bo'lishi kerak («макарон»/«мака» emas).
        if (w == 'мак') {
          if (RegExp(r'(^|[^а-яё])мак(а|ов|ом)?([^а-яё]|$)').hasMatch(t) ||
              t.contains('маков')) {
            return palette;
          }
        } else if (t.contains(w)) {
          return palette;
        }
      }
    }
    return null;
  }

  // Turi тех картадан: AVVAL mahsulot nomi (eng ishonchli), keyin blok
  // nomlari, oxirida masalliqlar (masalan «Какао-порошок» → shokoladli).
  // Hech narsa mos kelmasa — klassik.
  static BiscuitPalette detect(String name, TechCard? card) {
    final byName = _match(name);
    if (byName != null) return byName;
    if (card == null) return classic;
    final bases = card.bases.map((b) => b.name).join(' ');
    final byBase = _match(bases);
    if (byBase != null) return byBase;
    final items = [
      for (final b in card.bases)
        for (final i in b.ingredients) i.name,
    ].join(' ');
    return _match(items) ?? classic;
  }
}

class Biscuit3DView extends StatelessWidget {
  final BiscuitDims dims;
  final BiscuitPalette palette;
  final double height;

  const Biscuit3DView({
    super.key,
    required this.dims,
    this.palette = BiscuitPalette.classic,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Rotating3DView(
      height: height,
      manual: true,
      painter: (tilt, rotation) => BiscuitPainter(
        dims: dims,
        palette: palette,
        tilt: tilt,
        rotation: rotation,
      ),
    );
  }
}

// Kartadagi kichik statik rasm: shu biskvitning o'zi (o'lchami va turi
// тех картадан), yumshoq fon ustida.
class BiscuitThumb extends StatelessWidget {
  final BiscuitDims dims;
  final BiscuitPalette palette;

  const BiscuitThumb({super.key, required this.dims, required this.palette});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFEDE6F6)],
        ),
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: BiscuitPainter(
            dims: dims,
            palette: palette,
            tilt: 0.36,
            rotation: 0.5,
          ),
        ),
      ),
    );
  }
}

class BiscuitPainter extends CustomPainter {
  final BiscuitDims dims;
  final BiscuitPalette palette;
  final double tilt;
  final double rotation;

  BiscuitPainter({
    required this.dims,
    this.palette = BiscuitPalette.classic,
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

    final areaH = size.height;
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
        (areaH + total) / 2 - plateRy - plateThick;
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
        ..shader = LinearGradient(
          colors: [palette.spongeShade, palette.sponge, palette.spongeLight, palette.sponge, palette.spongeShade],
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
        ..color = palette.baked.withValues(alpha: 0.75),
    );
    // G'ovaklar — biskvit bilan birga aylanadi.
    final rnd = math.Random(3);
    final pore = Paint()..color = palette.pore.withValues(alpha: 0.55);
    final speck = Paint()..color = palette.speck ?? palette.pore;
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
        palette.speck != null && i % 3 == 0 ? speck : pore,
      );
    }
    canvas.restore();

    // Tepa — pishgan qobiq.
    final topOval = bottomOval.shift(Offset(0, -h));
    canvas.drawOval(
      topOval,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.15, -0.2),
          radius: 0.85,
          colors: [palette.crustLight, palette.crust, palette.crustDark],
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
        ..color = palette.rim.withValues(alpha: 0.6),
    );
  }

  void _paintRect(Canvas canvas, double hw, double hl, double top,
      double bottom, double h, double pxPerCm) {
    final local = [(-hw, -hl), (hw, -hl), (hw, hl), (-hw, hl)];
    final tops = [for (final (x, z) in local) _project(x, z, top).$1];
    final bottoms = [for (final (x, z) in local) _project(x, z, bottom).$1];
    final rnd = math.Random(3);
    final pore = Paint()..color = palette.pore.withValues(alpha: 0.55);
    final speck = Paint()..color = palette.speck ?? palette.pore;

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
          face, Paint()..color = Color.lerp(palette.spongeShade, palette.spongeLight, f)!);

      canvas.save();
      canvas.clipPath(face);
      canvas.drawLine(
        bottoms[k],
        bottoms[k1],
        Paint()
          ..strokeWidth = h * 0.22
          ..color = palette.baked.withValues(alpha: 0.75),
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
          palette.speck != null && i % 3 == 0 ? speck : pore,
        );
      }
      canvas.restore();
      canvas.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = palette.spongeShade.withValues(alpha: 0.5),
      );
    }

    final topPath = Path()..addPolygon(tops, true);
    final bounds = topPath.getBounds();
    canvas.drawPath(
      topPath,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.15, -0.2),
          radius: 0.8,
          colors: [palette.crustLight, palette.crust, palette.crustDark],
          stops: [0, 0.7, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      topPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = palette.rim.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(BiscuitPainter old) =>
      old.dims != dims ||
      old.palette != palette ||
      old.tilt != tilt ||
      old.rotation != rotation;
}
