// shef/ui/widgets/filling_3d.dart — «П/Ф Начинка» uchun 3D ko'rinish:
// nachinka/kremning O'ZI (biskvitsiz, tortsiz) — patnis ustidagi oq sopol
// kosa, ichida krem. Ikki holat:
//  1) Tex kartada FOTO bor (biscuit_photo_url — «Rasm qo'shish» bo'limi):
//     kosadagi krem yuzasi shu FOTONING O'ZI (doira qilib qirqilgan, kosa
//     bilan birga aylanadi). Tarkib/nomga QARALMAYDI.
//  2) Foto yo'q: krem uyumi va uning burama izi (konditer qopidan
//     siqilgandek) chiziladi; rangi тех картадан (FillingLook.detect):
//     mahsulot nomi → blok nomlari → masalliqlar. Masalliqlarda miqdori
//     (g/ml) ENG KO'P rang beruvchi masalliq tanlanadi (300 g qulupnay
//     pyuresi + 50 g shokolad → qulupnay); slivka/tvorog kabi neytral asos
//     faqat boshqa hech narsa topilmasa olinadi.
// Filling3DView — Rotating3DView (cake_3d.dart) qo'lda rejimida;
// FillingThumb — grid kartasi uchun kichik statik rasm (o'sha kosa).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_side_photo.dart';
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
  // Tex kartadagi foto (to'liq URL): berilsa krem yuzasi shu fotoning o'zi,
  // [look] ishlatilmaydi. Foto saqlangach 3D o'zi yangilanadi.
  final String? photoUrl;
  final double height;

  const Filling3DView({
    super.key,
    this.look = FillingLook.neutral,
    this.photoUrl,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return BiscuitSidePhotoBuilder(
      url: photoUrl,
      displayWidth: 600,
      builder: (context, photo) => Rotating3DView(
        height: height,
        manual: true,
        painter: (tilt, rotation) => FillingBowlPainter(
          look: look,
          photo: photo,
          tilt: tilt,
          rotation: rotation,
        ),
      ),
    );
  }
}

// Kartadagi kichik statik rasm: shu nachinkali kosa (foto bo'lsa — fotodan).
class FillingThumb extends StatelessWidget {
  final FillingLook look;
  final String? photoUrl;

  const FillingThumb({super.key, required this.look, this.photoUrl});

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
      child: BiscuitSidePhotoBuilder(
        url: photoUrl,
        displayWidth: 240,
        builder: (context, photo) => RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            // Tepadanroq qaraladi — krem yuzasi yaxshi ko'rinsin.
            painter: FillingBowlPainter(
              look: look,
              photo: photo,
              tilt: 0.46,
              rotation: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

// Patnis ustidagi sopol kosa va ichidagi krem. Krem yuzasi — kosa og'zidagi
// tekis doira: ekranda ellips (balandligi [tilt] ga ko'paytirilgan) va
// [rotation] ga burilgan; foto ham, burama iz ham shu doirada chiziladi.
class FillingBowlPainter extends CustomPainter {
  final FillingLook look;
  final ui.Image? photo;
  final double tilt;
  final double rotation;

  FillingBowlPainter({
    required this.look,
    this.photo,
    required this.tilt,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final areaH = size.height;
    final plateRx = math.min(size.width * 0.42, areaH * 0.62);
    final plateRy = plateRx * tilt;
    final plateThick = plateRx * 0.05;

    final rim = plateRx * 0.64; // kosa og'zi radiusi
    final base = rim * 0.5; // tag radiusi
    final bowlH = math.min(rim * 0.62, areaH * 0.32);
    // Foto yo'q — krem kosadan uyum bo'lib chiqib turadi.
    final mound = photo == null ? rim * 0.42 : 0.0;

    final total = mound + rim * tilt + bowlH + plateRy + plateThick;
    final plateY = (areaH + total) / 2 - plateRy - plateThick;
    final rimY = plateY - bowlH;

    paintPlate3D(canvas, Offset(cx, plateY), plateRx, plateRy, plateThick);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, plateY + base * tilt * 0.2),
        width: base * 2.5,
        height: base * tilt * 2.6,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final rimOval = Rect.fromCenter(
        center: Offset(cx, rimY), width: rim * 2, height: rim * 2 * tilt);
    final baseOval = Rect.fromCenter(
        center: Offset(cx, plateY), width: base * 2, height: base * 2 * tilt);

    // Kosa tanasi: og'izdan tagga torayadi.
    final body = Path()
      ..moveTo(cx - rim, rimY)
      ..cubicTo(cx - rim, rimY + bowlH * 0.6, cx - base * 1.3, plateY,
          cx - base, plateY)
      ..arcTo(baseOval, math.pi, -math.pi, false)
      ..cubicTo(cx + base * 1.3, plateY, cx + rim, rimY + bowlH * 0.6,
          cx + rim, rimY)
      ..arcTo(rimOval, 0, math.pi, false)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFC9C3D3),
            Color(0xFFFFFFFF),
            Color(0xFFF3F0F7),
            Color(0xFFBDB6C8),
          ],
          stops: [0, 0.34, 0.6, 1],
        ).createShader(rimOval),
    );
    // Og'iz halqasi (sopol labi).
    canvas.drawOval(rimOval, Paint()..color = const Color(0xFFFBFAFD));
    canvas.drawOval(
      rimOval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB9B2C6),
    );

    final creamR = rim * 0.9;
    if (photo != null) {
      _paintPhoto(canvas, photo!, Offset(cx, rimY), creamR);
    } else {
      _paintCream(canvas, Offset(cx, rimY), creamR, mound);
    }
  }

  // Krem yuzasi = fotoning o'zi: o'rtasidan kvadrat qirqib, doiraga
  // joylanadi. Doira tekisligi ekranga affin o'tadi: y o'qi [tilt] ga
  // siqiladi va [rotation] ga buriladi (x = lx·cos + lz·sin).
  void _paintPhoto(Canvas canvas, ui.Image img, Offset c, double r) {
    final side = math.min(img.width, img.height).toDouble();
    final src = Rect.fromCenter(
      center: Offset(img.width / 2, img.height / 2),
      width: side,
      height: side,
    );
    final oval = Rect.fromCenter(center: c, width: r * 2, height: r * 2 * tilt);
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, tilt);
    canvas.rotate(-rotation);
    canvas.drawImageRect(
      img,
      src,
      Rect.fromCircle(center: Offset.zero, radius: r),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    // Kosa ichidagi yengil soya (chetlari) — foto «yopishtirilgan» emas,
    // kosada turgandek ko'rinsin.
    canvas.drawOval(
      oval,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.78, 1],
        ).createShader(oval),
    );
  }

  // Foto yo'q: krem uyumi + burama iz, rangi [look] dan.
  void _paintCream(Canvas canvas, Offset c, double r, double mound) {
    final color = look.color;
    final light = Color.lerp(color, Colors.white, 0.35)!;
    final shade = Color.lerp(color, Colors.black, 0.18)!;
    final deep = Color.lerp(color, Colors.black, 0.30)!;

    // Uyum yuzasi — aylanish jismi: markazdan ρ (0..r) masofadagi balandlik
    // qo'ng'iroqsimon (chetda 0, markazda [mound]).
    double heightAt(double rho) =>
        mound * (0.5 + 0.5 * math.cos(math.pi * (rho / r).clamp(0.0, 1.0)));

    // Siluet: har ustunda (x) yuzaning ekrandagi eng baland nuqtasi
    // (chuqurlik lz bo'ylab qidiriladi), pasti — og'iz ellipsining old yarmi.
    const cols = 56, depthSteps = 20;
    final topEdge = <Offset>[];
    for (var i = 0; i <= cols; i++) {
      final lx = r * (-1 + 2 * i / cols);
      final span = math.sqrt(math.max(0.0, r * r - lx * lx));
      var y = double.infinity;
      for (var k = 0; k <= depthSteps; k++) {
        final lz = span * (-1 + 2 * k / depthSteps);
        final sy =
            c.dy + lz * tilt - heightAt(math.sqrt(lx * lx + lz * lz));
        if (sy < y) y = sy;
      }
      topEdge.add(Offset(c.dx + lx, y));
    }
    final oval =
        Rect.fromCenter(center: c, width: r * 2, height: r * 2 * tilt);
    final shape = Path()
      ..addPolygon(topEdge, false)
      ..arcTo(oval, 0, math.pi, false)
      ..close();
    final bounds = shape.getBounds();
    canvas.drawPath(
      shape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.45),
          radius: 0.95,
          colors: [light, color, shade],
          stops: const [0, 0.55, 1],
        ).createShader(bounds),
    );

    // Burama iz (konditer qopidan siqilgandek): chetdan markazga o'ralib,
    // yuza bo'ylab tepaga ko'tariladi; kosa bilan birga aylanadi. Uyum
    // ortida qolgan (tomoshabindan teskari qiyalikdagi) qismi chizilmaydi.
    const turns = 3.2;
    const n = 260;
    final groove = Path(), ridge = Path();
    final w = math.max(1.2, r * 0.075);
    var pen = false;
    for (var i = 0; i <= n; i++) {
      final s = i / n;
      final a = s * turns * 2 * math.pi + rotation;
      final rho = r * 0.9 * (1 - s);
      final lz = rho * math.cos(a);
      // Ekran-y ning chuqurlik bo'yicha hosilasi: > 0 — yuza ko'rinadi.
      final slope = rho < 1e-6
          ? 0.0
          : mound * 0.5 * math.pi / r * math.sin(math.pi * rho / r) * lz / rho;
      if (tilt + slope <= 0.02) {
        pen = false;
        continue;
      }
      final p = Offset(
          c.dx + rho * math.sin(a), c.dy + lz * tilt - heightAt(rho));
      if (pen) {
        groove.lineTo(p.dx, p.dy);
        ridge.lineTo(p.dx, p.dy - w * 0.5);
      } else {
        groove.moveTo(p.dx, p.dy);
        ridge.moveTo(p.dx, p.dy - w * 0.5);
        pen = true;
      }
    }
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
      groove,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w
        ..color = deep.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      ridge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.5
        ..color = light.withValues(alpha: 0.9),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FillingBowlPainter old) =>
      old.look != look ||
      old.photo != photo ||
      old.tilt != tilt ||
      old.rotation != rotation;
}
