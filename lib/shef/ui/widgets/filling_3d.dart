// shef/ui/widgets/filling_3d.dart — «П/Ф Начинка» uchun 3D ko'rinish:
// bo'lagi kesib olingan yumaloq tort — 3 ta biskvit qatlami va ular orasida
// 2 ta NACHINKA qatlami. Kesimda (va «yalang'och» yon tomonda) nachinka
// ko'rinadi; uning rangi FAQAT тех картадан (FillingLook.detect):
//   1) mahsulot nomi → 2) blok nomlari → 3) masalliqlar.
// Masalliqlarda miqdori (g/ml) ENG KO'P bo'lgan rang beruvchi masalliq
// tanlanadi (masalan 300 g qulupnay pyuresi + 50 g shokolad → qulupnay);
// slivka/tvorog kabi neytral asos faqat boshqa hech narsa topilmasa olinadi.
// Foto, meva bo'laklari va boshqa bezak CHIZILMAYDI — faqat rang.
// Filling3DView — Rotating3DView (cake_3d.dart) qo'lda rejimida;
// FillingThumb — grid kartasi uchun kichik statik rasm.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_3d.dart';

// Nachinka rangi (тех картадан).
class FillingLook {
  final Color color;

  const FillingLook(this.color);

  // Hech narsa mos kelmasa — neytral qaymoqrang.
  static const FillingLook neutral = FillingLook(Color(0xFFF6E7C8));

  // Kalit so'zlar (ru / uz / en) → rang. Oxirgi qoida — neytral asoslar
  // (slivka, tvorog ...): masalliqlar orasida ular eng oxirida hisobga
  // olinadi, chunki deyarli har nachinkada bor.
  static const List<(List<String>, Color)> _rules = [
    (['клубни', 'землян', 'strawberr', 'qulupnay'], Color(0xFFD9364A)),
    (['малин', 'raspberr', 'malina'], Color(0xFFC2185B)),
    (['вишн', 'черешн', 'cherry', 'olcha', 'gilos'], Color(0xFF8E1230)),
    (['черник', 'голубик', 'ежевик', 'blueberr'], Color(0xFF4B3B8F)),
    (['смородин', 'клюкв', 'брусник', 'currant', 'cranberr'],
        Color(0xFF6A1B3A)),
    (['маракуй', 'passion'], Color(0xFFF2B01E)),
    (['манго', 'mango'], Color(0xFFF6A821)),
    (['персик', 'абрикос', 'peach', 'apricot', 'shaftoli', 'o\'rik'],
        Color(0xFFF7A94B)),
    (['апельсин', 'мандарин', 'orange', 'apelsin', 'mandarin'],
        Color(0xFFF28C28)),
    (['лимон', 'лайм', 'lemon', 'lime', 'limon'], Color(0xFFF5E26B)),
    (['ананас', 'pineapple', 'ananas'], Color(0xFFF4D35E)),
    (['банан', 'banan'], Color(0xFFF3E2A0)),
    (['киви', 'kiwi'], Color(0xFF8BC34A)),
    (['яблок', 'груш', 'apple', 'olma', 'nok'], Color(0xFFE8D28A)),
    (['фисташ', 'pista', 'матча', 'matcha'], Color(0xFFA8C66C)),
    (['шоколад', 'какао', 'ганаш', 'брауни', 'chocolate', 'cocoa',
        'shokolad', 'kakao'], Color(0xFF5A3420)),
    (['карамел', 'сгущ', 'дульсе', 'ирис', 'caramel', 'karamel'],
        Color(0xFFC8863C)),
    (['кофе', 'капучино', 'тирамису', 'coffee', 'qahva', 'kofe'],
        Color(0xFFA47551)),
    (['орех', 'пралине', 'фундук', 'миндал', 'арахис', 'грецк', 'yong\'oq',
        'bodom'], Color(0xFFB98A55)),
    (['мед', 'мёд', 'honey', 'asal'], Color(0xFFE0A74E)),
    (['кокос', 'coconut', 'kokos'], Color(0xFFFBF7EF)),
    (['сливк', 'сметан', 'творог', 'творож', 'сыр', 'маскарпоне', 'чиз',
        'йогурт', 'ванил', 'молок', 'пломбир', 'cream', 'qaymoq', 'tvorog',
        'vanil'], Color(0xFFFFF3DC)),
  ];

  static int? _ruleOf(String text) {
    final t = text.toLowerCase();
    for (var i = 0; i < _rules.length; i++) {
      for (final w in _rules[i].$1) {
        // «мед» qisqa — «медленно» kabi so'zlarga tushmasin.
        if (w == 'мед') {
          if (RegExp(r'(^|[^а-яё])м[её]д(а|ом|ов|овый|овая|овое)?([^а-яё]|$)')
              .hasMatch(t)) {
            return i;
          }
        } else if (t.contains(w)) {
          return i;
        }
      }
    }
    return null;
  }

  static FillingLook detect(String name, TechCard? card) {
    final byName = _ruleOf(name);
    if (byName != null) return FillingLook(_rules[byName].$2);
    if (card == null) return neutral;
    final byBase = _ruleOf(card.bases.map((b) => b.name).join(' '));
    if (byBase != null) return FillingLook(_rules[byBase].$2);

    // Masalliqlar: har qoida bo'yicha miqdor yig'indisi (g/ml; dona/metr
    // miqdori solishtirib bo'lmaydi — 1 deb olinadi).
    final weight = <int, int>{};
    for (final b in card.bases) {
      for (final item in b.ingredients) {
        final rule = _ruleOf(item.name);
        if (rule == null) continue;
        final amount =
            (item.unit == 'g' || item.unit == 'ml') ? item.amount : 1;
        weight[rule] = (weight[rule] ?? 0) + math.max(amount, 1);
      }
    }
    if (weight.isEmpty) return neutral;
    final neutralRule = _rules.length - 1;
    int? best;
    for (final e in weight.entries) {
      if (e.key == neutralRule) continue;
      if (best == null || e.value > weight[best]!) best = e.key;
    }
    return FillingLook(_rules[best ?? neutralRule].$2);
  }

  @override
  bool operator ==(Object other) =>
      other is FillingLook && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

class Filling3DView extends StatelessWidget {
  final FillingLook look;
  final double height;

  const Filling3DView({
    super.key,
    this.look = FillingLook.neutral,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return Rotating3DView(
      height: height,
      manual: true,
      painter: (tilt, rotation) =>
          FillingCakePainter(look: look, tilt: tilt, rotation: rotation),
    );
  }
}

// Kartadagi kichik statik rasm: shu nachinkali kesilgan tort.
class FillingThumb extends StatelessWidget {
  final FillingLook look;

  const FillingThumb({super.key, required this.look});

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
          // Kesim tomoshabinga qarab turadi.
          painter: FillingCakePainter(look: look, tilt: 0.36, rotation: 0),
        ),
      ),
    );
  }
}

// Bo'lagi kesib olingan yumaloq tort. Burchak t: ekranda x = cx + r·sin t,
// chuqurlik cos t (> 0 — tomoshabin tomonda). Chizish tartibi (orqadan
// oldinga): patnis → kesim yuzlari → oldingi yon devor → tepa.
class FillingCakePainter extends CustomPainter {
  final FillingLook look;
  final double tilt;
  final double rotation;

  FillingCakePainter({
    required this.look,
    required this.tilt,
    required this.rotation,
  });

  static const BiscuitPalette _sponge = BiscuitPalette.classic;
  // Kesib olingan bo'lak: markazi va kengligi (radian, tort o'qida).
  // Markaz 0 — burilmagan holatda kesim tomoshabinga qarab ochiladi va
  // ikkala kesim yuzi ham ko'rinadi (kartadagi statik rasm shunday).
  static const double _wedgeCenter = 0;
  static const double _wedgeWidth = 1.05;
  // Qatlamlar pastdan tepaga emas, TEPADAN pastga: (ulush, nachinkami).
  static const List<(double, bool)> _layers = [
    (0.22, false),
    (0.17, true),
    (0.22, false),
    (0.17, true),
    (0.22, false),
  ];

  late double _cx;
  late double _r;
  late double _top;
  late double _h;

  Offset _rim(double t, double y) =>
      Offset(_cx + _r * math.sin(t), y + _r * tilt * math.cos(t));

  @override
  void paint(Canvas canvas, Size size) {
    _cx = size.width / 2;
    final areaH = size.height;
    final plateRx = math.min(size.width * 0.42, areaH * 0.62);
    final plateRy = plateRx * tilt;
    final plateThick = plateRx * 0.05;
    _r = plateRx * 0.66;
    _h = math.min(_r * 0.85, areaH * 0.42);

    final total = _h + _r * tilt + plateRy + plateThick;
    final plateY = (areaH + total) / 2 - plateRy - plateThick;
    final bottom = plateY;
    _top = bottom - _h;

    paintPlate3D(canvas, Offset(_cx, plateY), plateRx, plateRy, plateThick);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(_cx, bottom + _r * tilt * 0.12),
        width: _r * 2.1,
        height: _r * tilt * 2.2,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final w0 = _wedgeCenter - _wedgeWidth / 2 + rotation;
    final w1 = _wedgeCenter + _wedgeWidth / 2 + rotation;

    // Kesim yuzlari: normali tomoshabinga qaraganlari ko'rinadi.
    // w0 yuzining normali +dp/dt = (cos, −sin), w1 niki — teskarisi.
    if (math.sin(w0) < 0) _paintCutFace(canvas, w0, math.cos(w0));
    if (math.sin(w1) > 0) _paintCutFace(canvas, w1, -math.cos(w1));

    // Oldingi yarim aylana (−π/2 … π/2) dan kesilgan bo'lak olib tashlanadi.
    var walls = <(double, double)>[(-math.pi / 2, math.pi / 2)];
    for (final shift in [-2 * math.pi, 0.0, 2 * math.pi]) {
      final a = _norm(w0) + shift, b = a + _wedgeWidth;
      walls = [
        for (final (s, e) in walls) ...[
          if (a > s) (s, math.min(e, a)),
          if (b < e) (math.max(s, b), e),
        ],
      ].where((w) => w.$2 - w.$1 > 1e-4).toList();
    }
    for (final (s, e) in walls) {
      _paintWall(canvas, s, e);
    }

    _paintTop(canvas, w1, w0 + 2 * math.pi);
  }

  // Burchakni (−π, π] oralig'iga keltirish.
  static double _norm(double t) {
    var a = t % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    if (a <= -math.pi) a += 2 * math.pi;
    return a;
  }

  Color get _fill => look.color;
  Color get _fillLight => Color.lerp(look.color, Colors.white, 0.22)!;
  Color get _fillShade => Color.lerp(look.color, Colors.black, 0.16)!;

  // Kesim yuzi: o'qdan chetgacha vertikal to'rtburchak, qatlamlar bo'yicha
  // bo'yalgan. [nx] — normalning ekran-x tashkil etuvchisi (yorug'lik uchun).
  void _paintCutFace(Canvas canvas, double t, double nx) {
    final axis = Offset(_cx, _top);
    final rim = _rim(t, _top);
    final face = Path()
      ..addPolygon([
        axis,
        rim,
        rim.translate(0, _h),
        axis.translate(0, _h),
      ], true);

    canvas.save();
    canvas.clipPath(face);
    var f = 0.0;
    final rnd = math.Random(7 + (t * 10).round());
    final pore = Paint()..color = _sponge.pore.withValues(alpha: 0.5);
    for (final (part, isFilling) in _layers) {
      final y0 = f * _h, y1 = (f + part) * _h;
      final band = Path()
        ..addPolygon([
          axis.translate(0, y0),
          rim.translate(0, y0),
          rim.translate(0, y1),
          axis.translate(0, y1),
        ], true);
      if (isFilling) {
        canvas.drawPath(
          band,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_fillLight, _fill, _fillShade],
            ).createShader(band.getBounds()),
        );
      } else {
        canvas.drawPath(band, Paint()..color = _sponge.spongeLight);
        // Kesimdagi g'ovaklar.
        final n = ((rim - axis).distance / 3).round().clamp(6, 60);
        for (var i = 0; i < n; i++) {
          final u = rnd.nextDouble();
          final v = y0 + (0.12 + rnd.nextDouble() * 0.76) * (y1 - y0);
          final s = 1.2 + rnd.nextDouble() * 1.8;
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.lerp(axis, rim, u)!.translate(0, v),
              width: s,
              height: s * 0.75,
            ),
            pore,
          );
        }
      }
      f += part;
    }
    // Yuzning yorug'lik soyasi: chapga qaragani ochroq, o'ngga — to'qroq.
    canvas.drawPath(
      face,
      Paint()
        ..color = Colors.black
            .withValues(alpha: (0.10 + 0.12 * nx).clamp(0.0, 0.25)),
    );
    canvas.restore();
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _sponge.spongeShade.withValues(alpha: 0.5),
    );
  }

  // Tashqi yon devor bo'lagi [s, e] (oldingi yarim aylana ichida) —
  // «yalang'och» tort: qatlamlar tashqaridan ham ko'rinadi.
  void _paintWall(Canvas canvas, double s, double e) {
    const step = math.pi / 60;
    final n = math.max(2, ((e - s) / step).ceil());
    List<Offset> arc(double y) =>
        [for (var i = 0; i <= n; i++) _rim(s + (e - s) * i / n, y)];

    final whole = Path()
      ..addPolygon([...arc(_top), ...arc(_top + _h).reversed], true);
    canvas.save();
    canvas.clipPath(whole);
    var f = 0.0;
    for (final (part, isFilling) in _layers) {
      final band = Path()
        ..addPolygon([
          ...arc(_top + f * _h),
          ...arc(_top + (f + part) * _h).reversed,
        ], true);
      canvas.drawPath(
          band, Paint()..color = isFilling ? _fill : _sponge.sponge);
      f += part;
    }
    // Biskvit qatlamlaridagi g'ovaklar — tort bilan birga aylanadi.
    final rnd = math.Random(3);
    final pore = Paint()..color = _sponge.pore.withValues(alpha: 0.55);
    for (var i = 0; i < 220; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final layer = rnd.nextInt(3) * 2; // 0, 2, 4 — biskvit qatlamlari
      final v = 0.15 + rnd.nextDouble() * 0.7;
      final size = 1.0 + rnd.nextDouble() * 1.6;
      final t = a + rotation;
      final c = math.cos(t);
      if (c < 0.08) continue;
      var y = 0.0;
      for (var k = 0; k < layer; k++) {
        y += _layers[k].$1;
      }
      y = (y + v * _layers[layer].$1) * _h;
      canvas.drawOval(
        Rect.fromCenter(
          center: _rim(t, _top + y),
          width: size * c + 0.5,
          height: size * 0.8,
        ),
        pore,
      );
    }
    // Pastki qizargan chiziq va silindr hajm soyasi.
    final bottomOval = Rect.fromCenter(
      center: Offset(_cx, _top + _h),
      width: _r * 2,
      height: _r * 2 * tilt,
    );
    canvas.drawArc(
      bottomOval,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _h * 0.05
        ..color = _sponge.baked.withValues(alpha: 0.6),
    );
    canvas.drawRect(
      Rect.fromLTRB(_cx - _r, _top - _r * tilt, _cx + _r,
          _top + _h + _r * tilt),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.26),
            Colors.black.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.26),
          ],
          stops: const [0, 0.3, 0.42, 0.62, 1],
        ).createShader(bottomOval),
    );
    canvas.restore();
  }

  // Tepa — pishgan biskvit qobig'i, kesilgan bo'laksiz sektor [from, to].
  void _paintTop(Canvas canvas, double from, double to) {
    const n = 72;
    final arc = [
      for (var i = 0; i <= n; i++) _rim(from + (to - from) * i / n, _top),
    ];
    final sector = Path()..addPolygon([Offset(_cx, _top), ...arc], true);
    final topOval = Rect.fromCenter(
      center: Offset(_cx, _top),
      width: _r * 2,
      height: _r * 2 * tilt,
    );
    canvas.drawPath(
      sector,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.2),
          radius: 0.85,
          colors: [_sponge.crustLight, _sponge.crust, _sponge.crustDark],
          stops: const [0, 0.7, 1],
        ).createShader(topOval),
    );
    canvas.drawPath(
      Path()..addPolygon(arc, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _sponge.rim.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(FillingCakePainter old) =>
      old.look != look || old.tilt != tilt || old.rotation != rotation;
}
