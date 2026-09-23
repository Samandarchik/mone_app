// shef/ui/widgets/cake_3d.dart — 3D tort ko'rinishi (konstruktor uslubida):
// patnis ustidagi tort — shakli (yumaloq / kvadrat / ikki qavat), o'lchami,
// rangi, bezaklari (marvarid, rezavor, makaron, shokolad oqimi, sepma, gul,
// sham, topper) va yozuvi CakeLook'dan (model/cake_design.dart) olinadi.
// Model/plagin YO'Q — hammasi CustomPainter bilan chiziladi.
// Cake3DView — katta ko'rinish: BIR HOLATDA turadi (o'zi aylanmaydi), yon
// tomonga surilsa buriladi; bosish / nuqtalar — 3 ta burchak (yondan,
// tepadan, past). [faceFront] — yozuv o'qilishi uchun old tomondan, tepadan.
// Cake3D — kichik statik variant (kartalar uchun).
// Rotating3DView — umumiy qobiq (biskvit ham shuni ishlatadi: biscuit_3d.dart).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/shef/model/cake_design.dart';

const Color _heroTop = Color(0xFFFFFFFF);
const Color _heroBottom = Color(0xFFE6DDF3);
const Color _dotActive = Color(0xFF8E83B8);
const Color _chocolate = Color(0xFF4A2A1A);

// Ko'rinish burchaklari: ellips balandligi / kengligi nisbati
// (0 — yondan, 1 — tepadan).
const List<double> _tilts = [0.26, 0.46, 0.14];
const double _frontTilt = 0.55;

class Cake3DView extends StatelessWidget {
  final CakeLook look;
  final double height;
  final BorderRadius borderRadius;
  final bool faceFront;

  const Cake3DView({
    super.key,
    this.look = const CakeLook(),
    this.height = 260,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.faceFront = false,
  });

  @override
  Widget build(BuildContext context) {
    return Rotating3DView(
      height: height,
      borderRadius: borderRadius,
      faceFront: faceFront,
      painter: (tilt, rotation) =>
          CakePainter(look: look, tilt: tilt, rotation: rotation),
    );
  }
}

// 3D chizma uchun painter: ko'rinish burchagi (tilt) va burilish (radian).
typedef Painter3DBuilder = CustomPainter Function(
    double tilt, double rotation);

// Aylanadigan 3D ko'rinish qobig'i: fon, o'zi aylanish, surib burish,
// burchak nuqtalari. Nima chizilishini [painter] beradi (tort / biskvit).
class Rotating3DView extends StatefulWidget {
  final Painter3DBuilder painter;
  final double height;
  final BorderRadius borderRadius;
  final bool faceFront;
  // true — qo'lda boshqarish: nuqtalar yo'q; barmoq yon tomonga — burish,
  // tepaga/pastga — qarash burchagi (yondan ↔ tepadan).
  final bool manual;

  const Rotating3DView({
    super.key,
    required this.painter,
    this.height = 260,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.faceFront = false,
    this.manual = false,
  });

  @override
  State<Rotating3DView> createState() => _Rotating3DViewState();
}

// O'ZI AYLANMAYDI: model bir holatda turadi (_restRotation), faqat barmoq
// bilan buriladi. [_spin] doim 0 da — painter'lar uchun burilish manbai
// o'zgarmasin deb saqlangan (repeat() chaqirilmaydi).
const double _restRotation = 0.6;

class _Rotating3DViewState extends State<Rotating3DView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  int _page = 0;
  // Burilish (radian): boshlanishida tinch holat, barmoq bilan o'zgaradi.
  double _drag = _restRotation;
  // Qo'lda rejimdagi qarash burchagi (manual).
  double _tilt = _tilts.first;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.manual) return _buildManual();
    final front = widget.faceFront;
    return Column(
      children: [
        ClipRRect(
          borderRadius: widget.borderRadius,
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
              onHorizontalDragUpdate: front
                  ? null
                  : (d) => setState(() => _drag += d.delta.dx * 0.015),
              // Bosish — keyingi burchak.
              onTap: front
                  ? null
                  : () => setState(() => _page = (_page + 1) % _tilts.length),
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: front ? _frontTilt : _tilts[_page]),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  builder: (context, tilt, _) => AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: widget.painter(
                        tilt,
                        front ? 0 : _spin.value * 2 * math.pi + _drag,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _tilts.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: front ? null : () => setState(() => _page = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !front && i == _page
                        ? _dotActive
                        : Colors.grey.shade300,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildManual() {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        height: widget.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_heroTop, _heroBottom],
          ),
        ),
        // Gorizontal va vertikal alohida: ichki vertikal surish sahifa
        // scroll'idan ustun turadi (ko'rinish scroll ichida bo'lsa ham
        // burchakni o'zgartiradi).
        child: GestureDetector(
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag += d.delta.dx * 0.015),
          // Pastga surish — tepadan ko'proq qarash.
          onVerticalDragUpdate: (d) => setState(
            () => _tilt = (_tilt + d.delta.dy * 0.004).clamp(0.06, 0.95),
          ),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: widget.painter(
                  _tilt,
                  _spin.value * 2 * math.pi + _drag,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Kichik statik 3D tort (animatsiyasiz).
class Cake3D extends StatelessWidget {
  final CakeLook look;
  final double tilt;

  const Cake3D({super.key, this.look = const CakeLook(), this.tilt = 0.26});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: CakePainter(look: look, tilt: tilt, rotation: 0.6),
    );
  }
}

// Kumush chetli oq patnis (ostida soya). [c] — ustki yuza markazi.
// Tort va biskvit (biscuit_3d.dart) ikkalasi ham shuni ishlatadi.
void paintPlate3D(Canvas canvas, Offset c, double rx, double ry, double thick) {
  canvas.drawOval(
    Rect.fromCenter(
      center: c.translate(0, thick + ry * 0.35),
      width: rx * 2.1,
      height: ry * 2.2 + 6,
    ),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );
  final plateTop = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
  final edge = Path()
    ..addOval(plateTop.shift(Offset(0, thick)))
    ..addRect(Rect.fromLTRB(plateTop.left, c.dy, plateTop.right, c.dy + thick));
  canvas.drawPath(
    edge,
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
}

class _Tier {
  final double r;
  final double h;

  const _Tier(this.r, this.h);
}

// Tepa yuzadagi narsa: chuqurlik bo'yicha tartiblab chiziladi
// (orqadagi avval, oldindagi keyin).
class _Item {
  final double depth;
  final void Function(Canvas canvas) draw;

  const _Item(this.depth, this.draw);
}

class CakePainter extends CustomPainter {
  final CakeLook look;
  final double tilt;
  final double rotation;

  CakePainter({required this.look, required this.tilt, required this.rotation});

  late double _cx;
  late double _cos;
  late double _sin;

  bool _has(CakeDeco d) => look.decos.contains(d);

  // Tortning lokal koordinatasi (lx — o'ng, lz — tomoshabin tomon) →
  // ekran nuqtasi [levelY] balandlikda. depth > 0 — oldinda.
  (Offset, double) _project(double lx, double lz, double levelY) {
    final px = lx * _cos + lz * _sin;
    final pz = -lx * _sin + lz * _cos;
    return (Offset(_cx + px, levelY + pz * tilt), pz);
  }

  List<Offset> _squareCorners(double s, double levelY) => [
        for (final (lx, lz) in [(-s, -s), (s, -s), (s, s), (-s, s)])
          _project(lx, lz, levelY).$1,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    _cx = size.width / 2;
    _cos = math.cos(rotation);
    _sin = math.sin(rotation);
    final square = look.shape == CakeShape.square;

    final plateRx = math.min(size.width * 0.42, size.height * 0.62);
    final plateRy = plateRx * tilt;
    final plateThick = plateRx * 0.05;
    final unit = plateRx * 0.62;
    final r0 = unit * look.scale;
    final tiers = look.shape == CakeShape.tiered
        ? [_Tier(r0, unit * 0.5), _Tier(r0 * 0.64, unit * 0.46)]
        : [_Tier(r0, unit * (0.62 + 0.16 * look.scale))];
    final stackH = tiers.fold<double>(0, (s, t) => s + t.h);
    final topR = tiers.last.r;
    final tall = _has(CakeDeco.candles) || _has(CakeDeco.topper);
    final total =
        (tall ? topR * 0.6 : 0) + stackH + topR * tilt + plateRy + plateThick;
    final plateY = (size.height + total) / 2 - plateRy - plateThick;

    _drawPlate(canvas, plateRx, plateRy, plateThick, plateY);

    // Tort tagidagi soya patnis ustida.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(_cx, plateY + r0 * tilt * 0.15),
        width: r0 * (square ? 2.5 : 2.12),
        height: r0 * tilt * (square ? 2.8 : 2.3),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final base = look.color;
    final shade = Color.lerp(base, Colors.black, 0.18)!;
    final light = Color.lerp(base, Colors.white, 0.5)!;
    final drip = _has(CakeDeco.drip);

    var level = plateY;
    var deferred = <_Item>[];
    for (var i = 0; i < tiers.length; i++) {
      final t = tiers[i];
      final isTop = i == tiers.length - 1;
      final bottom = level;
      final top = level - t.h;
      final s = t.r * 0.84; // kvadrat yarim tomoni

      if (square) {
        _drawSquareSide(canvas, s, top, bottom, shade, light);
      } else {
        _drawRoundSide(canvas, t.r, top, bottom, base, shade, light);
      }
      // Pastki qavatning oldingi marvaridlari — ustki qavat yon tomonidan
      // oldinda turadi.
      for (final it in deferred) {
        it.draw(canvas);
      }
      deferred = [];

      if (isTop && drip) {
        _drawDrip(canvas, square ? s : t.r, top, t.h, square);
      }
      final topColor = isTop && drip
          ? const Color(0xFF5A3421)
          : Color.lerp(base, Colors.white, 0.22)!;
      if (square) {
        final pts = _squareCorners(s, top);
        final path = Path()..addPolygon(pts, true);
        canvas.drawPath(path, Paint()..color = topColor);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.5),
        );
      } else {
        final topOval = Rect.fromCenter(
          center: Offset(_cx, top),
          width: t.r * 2,
          height: t.r * 2 * tilt,
        );
        canvas.drawOval(
          topOval,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.25, -0.2),
              radius: 0.95,
              colors: [Color.lerp(topColor, Colors.white, 0.35)!, topColor],
            ).createShader(topOval),
        );
        canvas.drawOval(
          topOval,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.6),
        );
      }

      final pearls = _has(CakeDeco.pearls)
          ? _rimPearls(square ? s : t.r, top, square)
          : <_Item>[];
      if (isTop) {
        final radius = square ? s : t.r;
        if (_has(CakeDeco.sprinkles)) _drawSprinkles(canvas, radius, top);
        if (look.text.isNotEmpty) _drawText(canvas, radius, top);
        final items = [...pearls, ..._topItems(radius, top)]
          ..sort((a, b) => a.depth.compareTo(b.depth));
        for (final it in items) {
          it.draw(canvas);
        }
      } else {
        for (final p in pearls) {
          if (p.depth < 0) p.draw(canvas);
        }
        deferred = [
          for (final p in pearls)
            if (p.depth >= 0) p,
        ];
      }
      level = top;
    }
  }

  void _drawPlate(Canvas canvas, double rx, double ry, double thick, double y) =>
      paintPlate3D(canvas, Offset(_cx, y), rx, ry, thick);

  void _drawRoundSide(Canvas canvas, double r, double top, double bottom,
      Color base, Color shade, Color light) {
    final bottomOval = Rect.fromCenter(
      center: Offset(_cx, bottom),
      width: r * 2,
      height: r * 2 * tilt,
    );
    final side = Path()
      ..addOval(bottomOval)
      ..addRect(Rect.fromLTRB(_cx - r, top, _cx + r, bottom));
    // Yorug'lik aylanish bilan biroz siljiydi — hajm hissi.
    final l = 0.1 * math.sin(rotation);
    canvas.drawPath(
      side,
      Paint()
        ..shader = LinearGradient(
          colors: [shade, base, light, base, shade],
          stops: [0, 0.3 + l, 0.42 + l, 0.62 + l, 1],
        ).createShader(bottomOval),
    );
    canvas.drawArc(
      bottomOval,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = shade.withValues(alpha: 0.6),
    );
  }

  void _drawSquareSide(Canvas canvas, double s, double top, double bottom,
      Color shade, Color light) {
    const local = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)];
    final tops = _squareCorners(s, top);
    final bottoms = _squareCorners(s, bottom);
    for (var k = 0; k < 4; k++) {
      final k1 = (k + 1) % 4;
      final nx = (local[k].$1 + local[k1].$1) / 2;
      final nz = (local[k].$2 + local[k1].$2) / 2;
      final npx = nx * _cos + nz * _sin;
      final npz = -nx * _sin + nz * _cos;
      if (npz <= 0) continue; // orqa tomon ko'rinmaydi
      final f = (0.55 - 0.35 * npx + 0.15 * npz).clamp(0.0, 1.0);
      final face = Path()
        ..addPolygon([tops[k], tops[k1], bottoms[k1], bottoms[k]], true);
      canvas.drawPath(face, Paint()..color = Color.lerp(shade, light, f)!);
      canvas.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = shade.withValues(alpha: 0.35),
      );
    }
  }

  // Shokolad oqimi: tepa chetidan yon tomonga turli uzunlikdagi tomchilar.
  void _drawDrip(
      Canvas canvas, double r, double top, double h, bool square) {
    final paint = Paint()..color = _chocolate;
    double len(double a) {
      final v = math.sin(a * 8) * 0.5 + 0.5;
      return h * (0.08 + 0.3 * math.pow(v, 6));
    }

    void strip(List<(Offset, double)> rim) {
      if (rim.length < 2) return;
      final path = Path()..moveTo(rim.first.$1.dx, rim.first.$1.dy);
      for (final (p, _) in rim) {
        path.lineTo(p.dx, p.dy);
      }
      for (final (p, a) in rim.reversed) {
        path.lineTo(p.dx, p.dy + len(a));
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    if (square) {
      const local = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)];
      for (var k = 0; k < 4; k++) {
        final k1 = (k + 1) % 4;
        final nx = (local[k].$1 + local[k1].$1) / 2;
        final nz = (local[k].$2 + local[k1].$2) / 2;
        if (-nx * _sin + nz * _cos <= 0) continue;
        const n = 24;
        strip([
          for (var j = 0; j <= n; j++)
            (
              _project(
                r * (local[k].$1 + (local[k1].$1 - local[k].$1) * j / n),
                r * (local[k].$2 + (local[k1].$2 - local[k].$2) * j / n),
                top,
              ).$1,
              (k + j / n) * math.pi / 2,
            ),
        ]);
      }
    } else {
      const n = 90;
      strip([
        for (var j = 0; j <= n; j++)
          () {
            final th = -math.pi / 2 + math.pi * j / n;
            return (
              Offset(_cx + r * math.sin(th), top + r * tilt * math.cos(th)),
              th - rotation,
            );
          }(),
      ]);
    }
  }

  List<_Item> _rimPearls(double r, double top, bool square) {
    final pts = <(double, double)>[];
    if (square) {
      const local = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)];
      for (var k = 0; k < 4; k++) {
        final k1 = (k + 1) % 4;
        for (var j = 0; j < 5; j++) {
          pts.add((
            r * 0.9 * (local[k].$1 + (local[k1].$1 - local[k].$1) * j / 5),
            r * 0.9 * (local[k].$2 + (local[k1].$2 - local[k].$2) * j / 5),
          ));
        }
      }
    } else {
      const n = 18;
      for (var i = 0; i < n; i++) {
        final a = i * 2 * math.pi / n;
        pts.add((r * 0.9 * math.sin(a), r * 0.9 * math.cos(a)));
      }
    }
    final r0 = r * 0.07;
    return [
      for (final (lx, lz) in pts)
        () {
          final (pos, depth) = _project(lx, lz, top);
          final k = depth / r; // -1..1
          return _Item(depth, (canvas) {
            final pr = r0 * (0.85 + 0.15 * k);
            final c = pos.translate(0, -pr * 0.5);
            canvas.drawCircle(
              c,
              pr,
              Paint()
                ..shader = const RadialGradient(
                  center: Alignment(-0.35, -0.45),
                  colors: [Color(0xFFFFFFFF), Color(0xFFE6D6B8)],
                ).createShader(Rect.fromCircle(center: c, radius: pr)),
            );
          });
        }(),
    ];
  }

  // Polyar joylash: [rho] — radius ulushi, [a] — burchak (π — orqa markaz).
  (Offset, double) _at(double r, double rho, double a, double top) =>
      _project(r * rho * math.sin(a), r * rho * math.cos(a), top);

  List<_Item> _topItems(double r, double top) {
    final items = <_Item>[];
    const pi = math.pi;

    if (_has(CakeDeco.berries)) {
      const spots = [
        (0.62, 0.78 * pi, 0), (0.62, 0.92 * pi, 1), (0.62, 1.06 * pi, 2),
        (0.62, 1.2 * pi, 0), (0.36, 0.86 * pi, 1), (0.36, 1.12 * pi, 0),
      ];
      for (final (rho, a, kind) in spots) {
        final (pos, depth) = _at(r, rho, a, top);
        items.add(_Item(depth, (c) => _berry(c, pos, r, kind)));
      }
    }
    if (_has(CakeDeco.macarons)) {
      const spots = [
        (0.84 * pi, Color(0xFFF4A7B9)),
        (1.0 * pi, Color(0xFFB9D98C)),
        (1.16 * pi, Color(0xFFC7B5E8)),
      ];
      for (final (a, color) in spots) {
        final (pos, depth) = _at(r, 0.6, a, top);
        items.add(_Item(depth, (c) => _macaron(c, pos, r, color)));
      }
    }
    if (_has(CakeDeco.flowers)) {
      const spots = [
        (0.66, 0.7 * pi, Color(0xFFFFFFFF)),
        (0.66, 1.3 * pi, Color(0xFFF7B6C8)),
        (0.3, 1.0 * pi, Color(0xFFF7B6C8)),
      ];
      for (final (rho, a, color) in spots) {
        final (pos, depth) = _at(r, rho, a, top);
        items.add(_Item(depth, (c) => _flower(c, pos, r, color)));
      }
    }
    if (_has(CakeDeco.candles)) {
      const spots = [
        (0.9 * pi, Color(0xFFF49AB5)),
        (1.0 * pi, Color(0xFF8EC5EC)),
        (1.1 * pi, Color(0xFFF5D469)),
      ];
      for (final (a, color) in spots) {
        final (pos, depth) = _at(r, 0.42, a, top);
        items.add(_Item(depth, (c) => _candle(c, pos, r, color)));
      }
    }
    if (_has(CakeDeco.topper)) {
      final (pos, depth) = _at(r, 0.5, pi, top);
      items.add(_Item(depth - 0.01, (c) => _topper(c, pos, r)));
    }
    return items;
  }

  void _berry(Canvas canvas, Offset pos, double r, int kind) {
    const colors = [Color(0xFFD8323F), Color(0xFF3B3F8C), Color(0xFFC2185B)];
    final br = r * (kind == 1 ? 0.065 : 0.085);
    final c = pos.translate(0, -br * 0.7);
    canvas.drawCircle(
      c,
      br,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(colors[kind], Colors.white, 0.35)!, colors[kind]],
        ).createShader(Rect.fromCircle(center: c, radius: br)),
    );
    if (kind == 0) {
      // Qulupnay bargi.
      canvas.drawOval(
        Rect.fromCenter(
            center: c.translate(0, -br * 0.85), width: br * 1.1, height: br * 0.45),
        Paint()..color = const Color(0xFF4E9A45),
      );
    }
  }

  void _macaron(Canvas canvas, Offset pos, double r, Color color) {
    final w = r * 0.28;
    final h = w * 0.62;
    final shell = h * 0.38;
    final dark = Color.lerp(color, Colors.black, 0.12)!;
    RRect rr(double bottom, double width, double height) => RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(pos.dx, bottom - height / 2),
            width: width,
            height: height,
          ),
          Radius.circular(height / 2),
        );
    final b = pos.dy;
    canvas.drawRRect(rr(b, w, shell), Paint()..color = dark);
    canvas.drawRRect(
        rr(b - shell * 0.8, w * 0.9, h * 0.24), Paint()..color = const Color(0xFFFFF8EE));
    canvas.drawRRect(rr(b - shell * 0.8 - h * 0.2, w, shell), Paint()..color = color);
  }

  void _flower(Canvas canvas, Offset pos, double r, Color color) {
    final pr = r * 0.055;
    final c = pos.translate(0, -pr * 0.6);
    final squash = math.max(tilt, 0.4);
    final petal = Paint()..color = color;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black.withValues(alpha: 0.12);
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5 + 0.3;
      final p = c.translate(math.cos(a) * pr * 1.1, math.sin(a) * pr * 1.1 * squash);
      canvas.drawOval(
          Rect.fromCenter(center: p, width: pr * 1.6, height: pr * 1.6 * squash + 1),
          petal);
      canvas.drawOval(
          Rect.fromCenter(center: p, width: pr * 1.6, height: pr * 1.6 * squash + 1),
          edge);
    }
    canvas.drawCircle(c, pr * 0.55, Paint()..color = const Color(0xFFF2C14E));
  }

  void _candle(Canvas canvas, Offset pos, double r, Color color) {
    final w = r * 0.055;
    final ch = r * 0.42;
    final body = Rect.fromLTWH(pos.dx - w / 2, pos.dy - ch, w, ch);
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(w * 0.3)), Paint()..color = color);
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (var y = body.top + ch * 0.12; y < body.bottom - ch * 0.1; y += ch * 0.2) {
      canvas.drawRect(Rect.fromLTWH(body.left, y, w, ch * 0.06), stripe);
    }
    final flame = Offset(pos.dx, body.top - w * 1.5);
    canvas.drawCircle(
      flame,
      w * 2.4,
      Paint()
        ..color = const Color(0xFFFFD54F).withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.2),
    );
    canvas.drawOval(Rect.fromCenter(center: flame, width: w * 1.2, height: w * 2.4),
        Paint()..color = const Color(0xFFFF9800));
    canvas.drawOval(
        Rect.fromCenter(
            center: flame.translate(0, w * 0.35), width: w * 0.6, height: w * 1.2),
        Paint()..color = const Color(0xFFFFF176));
  }

  void _topper(Canvas canvas, Offset pos, double r) {
    const gold = Color(0xFFC9A04A);
    final stickH = r * 0.5;
    final stick = Paint()
      ..color = gold
      ..strokeWidth = math.max(1.2, r * 0.015);
    canvas.drawLine(pos.translate(-r * 0.28, 0), pos.translate(-r * 0.28, -stickH), stick);
    canvas.drawLine(pos.translate(r * 0.28, 0), pos.translate(r * 0.28, -stickH), stick);
    final tp = TextPainter(
      text: TextSpan(
        text: 'Tabriklaymiz!',
        style: TextStyle(
          fontSize: r * 0.17,
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          color: gold,
          shadows: const [Shadow(color: Color(0x55000000), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos.translate(-tp.width / 2, -stickH - tp.height * 0.8));
  }

  void _drawSprinkles(Canvas canvas, double r, double top) {
    const colors = [
      Color(0xFFF06292), Color(0xFF64B5F6), Color(0xFFFFD54F),
      Color(0xFF81C784), Color(0xFFBA68C8), Color(0xFFFFFFFF),
    ];
    final rnd = math.Random(11);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, r * 0.022);
    final l = r * 0.035;
    for (var i = 0; i < 45; i++) {
      final rho = math.sqrt(rnd.nextDouble()) * 0.82;
      final a = rnd.nextDouble() * 2 * math.pi;
      final d = rnd.nextDouble() * 2 * math.pi;
      final (p, _) = _at(r, rho, a, top);
      final dx = math.cos(d) * l;
      final dy = math.sin(d) * l * tilt;
      paint.color = colors[i % colors.length];
      canvas.drawLine(p.translate(-dx, -dy), p.translate(dx, dy), paint);
    }
  }

  // Yozuv tepa yuzada yotadi: tort bilan birga buriladi va qiyalanadi.
  void _drawText(Canvas canvas, double r, double top) {
    final light = look.textColor.computeLuminance() > 0.6;
    final tp = TextPainter(
      text: TextSpan(
        text: look.text,
        style: TextStyle(
          fontSize: r * 0.22,
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
          color: look.textColor,
          height: 1.1,
          shadows: [
            Shadow(
              color: light ? const Color(0x66000000) : const Color(0x33FFFFFF),
              blurRadius: 2,
            ),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: r * 1.5);
    final (pos, _) = _project(0, r * 0.18, top);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(1, tilt);
    canvas.rotate(-rotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(CakePainter old) =>
      old.look != look || old.tilt != tilt || old.rotation != rotation;
}
