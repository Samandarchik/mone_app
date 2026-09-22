// shef/ui/widgets/cake_illustration.dart — TAYYOR TORTNING vektor
// ILLYUSTRATSIYASI (CakeIllustrationView / CakeIllustrationPainter): yassi,
// «flat» grafika — patnisda butun tort, yon tomonida qizil lenta va bant,
// tepasida glazur va dekor doirasi, patnis oldida «Mone · BAKERY & COFFEE»
// yozuvi. Foto emas — hammasi tex kartadan chiziladi (CakeIllustrationSpec.
// fromTechCard):
//   • o'lchami (diametr/balandlik nisbati) — tex kartadan;
//   • qoplama rangi — tex kartadagi «Покрытие rangi» palitrasi
//     (coating_color); tanlanmagan bo'lsa avtomatik: qoplama bloki
//     (покрытие/глазурь/выравнивание) nomi/masalliqlaridan, bo'lmasa oxirgi
//     krem; kokos bo'lsa — kokos qirindili yon tomon, yong'oq — ushoq;
//   • tepa rangi — глазурь/карамель/джем/конфитюр bloki bo'lsa o'sha rang,
//     aks holda qoplama rangi;
//   • dekor — dekor blokidagi (bo'lmasa tort nomi va qoplama blokidagi)
//     so'zlardan: Рафаэлло shariklari, безе tomchilari, миндаль lepestkalari,
//     kokos qirindisi, qulupnay/malina/olcha/chernika, shokolad bo'laklari,
//     yong'oq; hech narsa topilmasa — qoplama rangidagi krem tomchilari.
// Tort konstruktori 3-qadami (shef_cake_constructor_page.dart) va «Торты»
// gridida fotosiz tort kartasi (shef_cakes_page.dart) shu rasmni ko'rsatadi.
// Statik (burilmaydi) — referens illyustratsiyadagi kabi bitta rakurs.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

// Tex karta blokining tortdagi roli — nomidan (ru / uz), harf farqsiz.
enum CakeBlockRole {
  biscuit,
  filling,
  coat,
  decor,
  other;

  static const List<(List<String>, CakeBlockRole)> _rules = [
    // Tashqi qoplama — krem/glazur bilan qoplash, tekislash, velyur.
    (['покрыт', 'выравн', 'глазур', 'обтяж', 'обмаз', 'велюр', 'qoplama'],
        coat),
    (['бискв', 'корж', 'biskvit', 'korj', 'основ'], biscuit),
    (['декор', 'украш', 'посып', 'bezak'], decor),
    // Tortga qatlam qo'shmaydigan bloklar.
    (['пропит', 'сироп', 'сборк', 'упаков', 'sirop'], other),
  ];

  static CakeBlockRole of(TechBase b) {
    final n = b.name.toLowerCase();
    for (final (words, role) in _rules) {
      if (words.any(n.contains)) return role;
    }
    // Krem, nachinka, konfi, muss, jele, ganash ... — ichki qatlam.
    return filling;
  }

  String get label => switch (this) {
        biscuit => 'Biskvit',
        filling => 'Nachinka',
        coat => 'Qoplama',
        decor => 'Bezak',
        other => 'Bosqich',
      };
}

// Blok rangi — nomi va masalliqlaridan (faqat shu blok hisobga olinadi).
Color cakeBlockColor(TechBase b) =>
    FillingLook.detect(b.name, TechCard(bases: [b])).color;

// Tepadagi dekor turlari.
enum CakeDecor {
  raffaello,
  meringue,
  almond,
  coconut,
  strawberry,
  raspberry,
  cherry,
  blueberry,
  chocolate,
  nut;

  static const Map<CakeDecor, List<String>> _words = {
    raffaello: ['рафаэлл', 'рафаел', 'raffaello', 'rafaello', 'rafaell'],
    meringue: ['безе', 'меренг', 'meringue', 'beze'],
    almond: ['миндал', 'almond', 'bodom'],
    coconut: ['кокос', 'coconut', 'kokos'],
    strawberry: ['клубни', 'землян', 'strawberr', 'qulupnay'],
    raspberry: ['малин', 'raspberr', 'malina'],
    cherry: ['вишн', 'черешн', 'cherry', 'olcha', 'gilos'],
    blueberry: ['черник', 'голубик', 'ежевик', 'blueberr'],
    chocolate: ['шоколад', 'chocolate', 'какао', 'shokolad'],
    nut: ['орех', 'фундук', 'фисташ', 'арахис', 'пекан', 'грецк', 'yong'],
  };

  // Matnda uchragan dekorlar — uchrash tartibida, takrorsiz.
  static List<CakeDecor> detect(String text) {
    final t = text.toLowerCase();
    final found = <(int, CakeDecor)>[];
    for (final e in _words.entries) {
      var at = -1;
      for (final w in e.value) {
        final i = t.indexOf(w);
        if (i >= 0 && (at < 0 || i < at)) at = i;
      }
      if (at >= 0) found.add((at, e.key));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, d) in found) d];
  }
}

// Yon tomon fakturasi.
enum CakeCoatTexture { smooth, coconut, nuts }

// Illyustratsiya uchun kerak bo'lgan hamma narsa (tex kartadan hisoblanadi).
@immutable
class CakeIllustrationSpec {
  final BiscuitDims dims;
  final Color coat;
  final Color top;
  final CakeCoatTexture texture;
  final List<CakeDecor> decor;
  // Yon tomondagi lenta (bant bilan); null — lentasiz.
  final Color? ribbon;

  const CakeIllustrationSpec({
    this.dims = const BiscuitDims(diameterCm: 22, heightCm: 9),
    this.coat = const Color(0xFFFFF6E3),
    this.top = const Color(0xFFFFF6E3),
    this.texture = CakeCoatTexture.smooth,
    this.decor = const [],
    this.ribbon = const Color(0xFFD62828),
  });

  static const List<String> _glazeWords = [
    'глазур', 'карамел', 'джем', 'конфитюр', 'ганаш', 'желе', 'glazur',
  ];

  // Tex kartadan: qoplama/tepa rangi, faktura, dekor.
  static CakeIllustrationSpec fromTechCard(String name, TechCard? card) {
    if (card == null) {
      return CakeIllustrationSpec(decor: CakeDecor.detect(name));
    }
    TechBase? coatBlock;
    TechBase? lastFilling;
    TechBase? glazeBlock;
    final decorText = StringBuffer();
    for (final b in card.bases) {
      final role = CakeBlockRole.of(b);
      final n = b.name.toLowerCase();
      if (role == CakeBlockRole.coat) coatBlock ??= b;
      if (role == CakeBlockRole.filling) lastFilling = b;
      if (role == CakeBlockRole.decor) {
        decorText
          ..write(b.name)
          ..write(' ');
        for (final i in b.ingredients) {
          decorText
            ..write(i.name)
            ..write(' ');
        }
      }
      // Tepa glazuri — ASOSIY qoplama blokidan boshqa, nomida glazur/
      // karamel/jem bor blok (masalan «Покрытие» + «Карамельная глазурь»).
      // Yagona «Глазурь» bloki — butun tort qoplamasi, alohida tepa yo'q.
      if (!identical(b, coatBlock) && _glazeWords.any(n.contains)) {
        glazeBlock = b;
      }
    }
    // Qoplama rangi: tex kartadagi «Покрытие rangi» palitrasi (coating_color)
    // — aynan o'sha; tanlanmagan bo'lsa avtomatik — qoplama bloki (bo'lmasa
    // oxirgi krem) nomi/masalliqlaridan, krem ko'rinishi uchun sal oqartirib.
    final coatSrc = coatBlock ?? lastFilling;
    // Yagona palitra («Nachinka rangi»); eski coating_color bo'lsa — ustun.
    final picked = fillingColorFromHex(card.coatingColor) ??
        fillingColorFromHex(card.fillingColor);
    final coat = picked ??
        (coatSrc == null
            ? const Color(0xFFFFF6E3)
            : _softenCoat(cakeBlockColor(coatSrc)));
    // Tepa: alohida glazur bloki bo'lsa — uning rangi (avtomatik), aks holda
    // qoplama bilan bir xil.
    final top = glazeBlock == null ? coat : cakeBlockColor(glazeBlock);

    // Faktura — tort nomi, qoplama bloki va dekor bloklari so'zlaridan
    // (kokos qirindisi odatda dekor/qoplamada yoziladi).
    final coatText = StringBuffer(name)..write(' ');
    if (coatSrc != null) {
      coatText
        ..write(coatSrc.name)
        ..write(' ');
      for (final i in coatSrc.ingredients) {
        coatText
          ..write(i.name)
          ..write(' ');
      }
    }
    final ct = coatText.toString().toLowerCase();
    final tt = '$ct ${decorText.toString().toLowerCase()}';

    // Dekor — dekor bloki; bo'lmasa tort nomi + qoplama bloki.
    var decor = CakeDecor.detect(decorText.toString());
    if (decor.isEmpty) decor = CakeDecor.detect(ct);

    // Рафаэлло / kokos — yon tomon kokos qirindili; yong'oq/ushoq — yong'oqli.
    final texture = (tt.contains('кокос') ||
            tt.contains('kokos') ||
            decor.contains(CakeDecor.raffaello))
        ? CakeCoatTexture.coconut
        : (tt.contains('орех') || tt.contains('крошк') || tt.contains('yong'))
            ? CakeCoatTexture.nuts
            : CakeCoatTexture.smooth;
    return CakeIllustrationSpec(
      dims: BiscuitDims.fromTechCard(card),
      coat: coat,
      top: top,
      texture: texture,
      decor: decor,
    );
  }

  // Juda to'q/yorqin nachinka rangi qoplama sifatida yumshatiladi (krem
  // ko'rinishi uchun oq bilan aralashtiriladi).
  static Color _softenCoat(Color c) => Color.lerp(c, Colors.white, 0.18)!;

  @override
  bool operator ==(Object other) =>
      other is CakeIllustrationSpec &&
      other.dims == dims &&
      other.coat == coat &&
      other.top == top &&
      other.texture == texture &&
      other.ribbon == ribbon &&
      _listEq(other.decor, decor);

  static bool _listEq(List<CakeDecor> a, List<CakeDecor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(dims, coat, top, texture, ribbon, Object.hashAll(decor));
}

// Statik illyustratsiya vidjeti.
class CakeIllustrationView extends StatelessWidget {
  final CakeIllustrationSpec spec;
  final double height;
  // Patnis oldidagi yozuv (null — yozuvsiz, masalan kichik kartada).
  final String? label;
  final String? subLabel;

  const CakeIllustrationView({
    super.key,
    required this.spec,
    this.height = 230,
    this.label = 'Mone',
    this.subLabel = 'BAKERY & COFFEE',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: CakeIllustrationPainter(
            spec: spec,
            label: label,
            subLabel: subLabel,
          ),
        ),
      ),
    );
  }
}

class CakeIllustrationPainter extends CustomPainter {
  final CakeIllustrationSpec spec;
  final String? label;
  final String? subLabel;

  CakeIllustrationPainter({required this.spec, this.label, this.subLabel});

  // Ellips nisbati (qarash burchagi).
  static const double _tilt = 0.36;

  late double _cx;
  late double _r;
  late double _topY;
  late double _h;

  Offset _rim(double t, double y) =>
      Offset(_cx + _r * math.sin(t), y + _r * _tilt * math.cos(t));

  static Color _dark(Color c, double k) => Color.lerp(c, Colors.black, k)!;
  static Color _light(Color c, double k) => Color.lerp(c, Colors.white, k)!;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, hgt = size.height;
    _cx = w / 2;
    // Tort radiusi — maydonga sig'adigan; diametr 14–30 sm oralig'ida
    // haqiqiy nisbatda bir oz farqlanadi.
    final d = spec.dims.rect
        ? math.max(spec.dims.widthCm, spec.dims.lengthCm)
        : spec.dims.diameterCm;
    final base = math.min(w * 0.30, hgt * 0.40);
    _r = base * (0.85 + 0.15 * ((d.clamp(14, 30) - 14) / 16));
    final hd = spec.dims.heightCm / math.max(d, 1);
    _h = (_r * 2 * hd).clamp(_r * 0.55, _r * 1.25);
    final plateRx = _r * 1.62;
    final plateRy = plateRx * _tilt;
    final labelH = label == null ? 0.0 : plateRy * 0.55;

    // Vertikal joylash: dekor (0.32r) + tepa ellips yarmi + balandlik +
    // patnis pastki yarmi + yozuv.
    final ext = _r * 0.32 + _r * _tilt + _h + plateRy + labelH;
    final start = (hgt - ext) / 2;
    _topY = start + _r * 0.32 + _r * _tilt;
    final bottomY = _topY + _h;
    final plateCy = bottomY + plateRy * 0.02;

    _paintPlate(canvas, Offset(_cx, plateCy), plateRx, plateRy);
    _paintSide(canvas, bottomY);
    if (spec.ribbon != null) _paintRibbonBand(canvas, spec.ribbon!);
    _paintTop(canvas);
    _paintDecor(canvas);
    if (spec.ribbon != null) _paintBow(canvas, spec.ribbon!);
    if (label != null) _paintLabel(canvas, Offset(_cx, plateCy), plateRx, plateRy);
  }

  // Patnis: och binafsha-oq ellips, ostida qalinlik va yumshoq soya.
  void _paintPlate(Canvas canvas, Offset c, double rx, double ry) {
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, ry * 0.18), width: rx * 2.15, height: ry * 2.3),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final thick = ry * 0.16;
    canvas.drawOval(
      Rect.fromCenter(center: c.translate(0, thick), width: rx * 2, height: ry * 2),
      Paint()..color = const Color(0xFFCFCBDD),
    );
    canvas.drawOval(
      Rect.fromCenter(center: c, width: rx * 2, height: ry * 2),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.0,
          colors: const [Color(0xFFF7F5FC), Color(0xFFEAE7F3), Color(0xFFDCD8E8)],
          stops: const [0, 0.7, 1],
        ).createShader(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2)),
    );
    // Tort ostidagi soya.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(_cx, _topY + _h + _r * _tilt * 0.1),
          width: _r * 2.25,
          height: _r * _tilt * 2.4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  // Yon devor: silliq qoplama, yengil gradient; faktura — kokos/yong'oq.
  void _paintSide(Canvas canvas, double bottomY) {
    const n = 64;
    final path = Path()
      ..addPolygon([
        for (var i = 0; i <= n; i++) _rim(-math.pi / 2 + math.pi * i / n, _topY),
        for (var i = n; i >= 0; i--) _rim(-math.pi / 2 + math.pi * i / n, bottomY),
      ], true);
    final coat = spec.coat;
    final box = Rect.fromLTRB(_cx - _r, _topY, _cx + _r, bottomY + _r * _tilt);
    canvas.drawPath(path, Paint()..color = coat);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _dark(coat, 0.16),
            _dark(coat, 0.03),
            _light(coat, 0.35),
            _dark(coat, 0.02),
            _dark(coat, 0.18),
          ],
          stops: const [0, 0.22, 0.42, 0.7, 1],
        ).createShader(box),
    );
    // Pastki chet — patnisga tegib turgan joy soyasi.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, _dark(coat, 0.22).withValues(alpha: 0.35)],
          stops: const [0.78, 1],
        ).createShader(box),
    );
    canvas.save();
    canvas.clipPath(path);
    _paintTexture(canvas, _topY, bottomY, coat, math.Random(11));
    canvas.restore();
  }

  // Kokos qirindisi / yong'oq ushog'i — mayda dog'lar (seed — har doim
  // bir xil joyda).
  void _paintTexture(
      Canvas canvas, double top, double bottom, Color coat, math.Random rnd) {
    if (spec.texture == CakeCoatTexture.smooth) return;
    final coconut = spec.texture == CakeCoatTexture.coconut;
    final count = (_r * (coconut ? 2.2 : 2.8)).round();
    for (var i = 0; i < count; i++) {
      final t = -math.pi / 2 + rnd.nextDouble() * math.pi;
      final y = top + rnd.nextDouble() * (bottom - top);
      final p = _rim(t, y);
      final c = math.cos(t);
      final s = _r * (0.022 + rnd.nextDouble() * 0.03);
      // Kokos — oq va juda och krem qirindilar, past kontrast (referensdagidek
      // yumshoq); yong'oq — jigarrang ushoqlar.
      final paint = Paint()
        ..color = coconut
            ? (rnd.nextBool()
                ? Colors.white.withValues(alpha: 0.6)
                : _dark(coat, 0.05).withValues(alpha: 0.4))
            : _dark(const Color(0xFFC79A5B), rnd.nextDouble() * 0.3)
                .withValues(alpha: 0.85);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(rnd.nextDouble() * math.pi);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: s * (0.5 + c), height: s * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  // Lenta — tort atrofidagi tasma (old yarim), bant alohida (_paintBow).
  double get _ribbonY => _topY + _h * 0.40;
  double get _ribbonH => _h * 0.10;

  void _paintRibbonBand(Canvas canvas, Color ribbon) {
    const n = 64;
    final y0 = _ribbonY, y1 = _ribbonY + _ribbonH;
    final band = Path()
      ..addPolygon([
        for (var i = 0; i <= n; i++) _rim(-math.pi / 2 + math.pi * i / n, y0),
        for (var i = n; i >= 0; i--) _rim(-math.pi / 2 + math.pi * i / n, y1),
      ], true);
    final box = Rect.fromLTRB(_cx - _r, y0, _cx + _r, y1 + _r * _tilt);
    canvas.drawPath(band, Paint()..color = ribbon);
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _dark(ribbon, 0.3),
            ribbon,
            _light(ribbon, 0.18),
            ribbon,
            _dark(ribbon, 0.3),
          ],
          stops: const [0, 0.25, 0.45, 0.7, 1],
        ).createShader(box),
    );
    // Lentaning yuqori/pastki chetida ingichka soya.
    canvas.drawPath(
      Path()..addPolygon([for (var i = 0; i <= n; i++) _rim(-math.pi / 2 + math.pi * i / n, y1)], false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  // Bant: ikki halqa, tugun, ikki dum — old markazda, lenta ustida.
  void _paintBow(Canvas canvas, Color ribbon) {
    final c = Offset(_cx, _ribbonY + _ribbonH * 0.5 + _r * _tilt);
    final s = _r * 0.30;
    final fill = Paint()..color = ribbon;
    final shade = Paint()..color = _dark(ribbon, 0.28);
    final hi = Paint()..color = _light(ribbon, 0.22);

    // Dumlar (orqada): pastga-chetga tushadigan ikki tasma.
    Path tail(double dir) => Path()
      ..moveTo(c.dx, c.dy)
      ..quadraticBezierTo(
          c.dx + dir * s * 0.35, c.dy + s * 0.9, c.dx + dir * s * 1.05, c.dy + s * 1.55)
      ..lineTo(c.dx + dir * s * 0.75, c.dy + s * 1.7)
      ..lineTo(c.dx + dir * s * 0.55, c.dy + s * 1.45)
      ..quadraticBezierTo(c.dx + dir * s * 0.2, c.dy + s * 0.8, c.dx, c.dy + s * 0.3)
      ..close();
    canvas.drawPath(tail(-1), shade);
    canvas.drawPath(tail(1), shade);
    // Halqalar.
    for (final dir in [-1.0, 1.0]) {
      final loop = Path()
        ..moveTo(c.dx, c.dy)
        ..cubicTo(c.dx + dir * s * 0.5, c.dy - s * 0.95, c.dx + dir * s * 1.5,
            c.dy - s * 0.65, c.dx + dir * s * 1.35, c.dy + s * 0.05)
        ..cubicTo(c.dx + dir * s * 1.2, c.dy + s * 0.55, c.dx + dir * s * 0.5,
            c.dy + s * 0.5, c.dx, c.dy)
        ..close();
      canvas.drawPath(loop, fill);
      // Halqa ichidagi soya (ichki bo'shliq).
      final inner = Path()
        ..moveTo(c.dx + dir * s * 0.25, c.dy - s * 0.05)
        ..cubicTo(c.dx + dir * s * 0.55, c.dy - s * 0.55, c.dx + dir * s * 1.15,
            c.dy - s * 0.4, c.dx + dir * s * 1.05, c.dy + s * 0.02)
        ..cubicTo(c.dx + dir * s * 0.95, c.dy + s * 0.3, c.dx + dir * s * 0.5,
            c.dy + s * 0.3, c.dx + dir * s * 0.25, c.dy - s * 0.05)
        ..close();
      canvas.drawPath(inner, shade);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + dir * s * 0.15, c.dy - s * 0.2)
          ..cubicTo(c.dx + dir * s * 0.5, c.dy - s * 0.8, c.dx + dir * s * 1.2,
              c.dy - s * 0.6, c.dx + dir * s * 1.25, c.dy - s * 0.15)
          ..cubicTo(c.dx + dir * s * 1.0, c.dy - s * 0.55, c.dx + dir * s * 0.5,
              c.dy - s * 0.6, c.dx + dir * s * 0.15, c.dy - s * 0.2)
          ..close(),
        hi,
      );
    }
    // Tugun.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.5),
        Radius.circular(s * 0.12),
      ),
      shade,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c.translate(0, -s * 0.05), width: s * 0.3, height: s * 0.3),
        Radius.circular(s * 0.1),
      ),
      hi,
    );
  }

  // Tepa: qoplama rangidagi hoshiya, ichida glazur (bo'lsa) va nurlar.
  void _paintTop(Canvas canvas) {
    final oval = Rect.fromCenter(
        center: Offset(_cx, _topY), width: _r * 2, height: _r * 2 * _tilt);
    final coat = spec.coat;
    canvas.drawOval(
      oval,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.4),
          radius: 0.95,
          colors: [_light(coat, 0.3), coat, _dark(coat, 0.06)],
          stops: const [0, 0.65, 1],
        ).createShader(oval),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(oval));
    _paintTexture(canvas, _topY - _r * _tilt, _topY + _r * _tilt, coat,
        math.Random(23));
    canvas.restore();
    // Tepa chetidagi och qirra.
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, _r * 0.02)
        ..color = _light(coat, 0.45),
    );
    if (spec.top != coat) {
      final inner = Rect.fromCenter(
          center: Offset(_cx, _topY), width: _r * 1.7, height: _r * 1.7 * _tilt);
      final top = spec.top;
      canvas.drawOval(
        inner,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.15, -0.3),
            radius: 0.95,
            colors: [_light(top, 0.22), top, _dark(top, 0.08)],
            stops: const [0, 0.7, 1],
          ).createShader(inner),
      );
      // Glazur ustidagi nurlar (referensdagi yorug' chiziqlar).
      final ray = Paint()
        ..color = _light(top, 0.5).withValues(alpha: 0.75)
        ..strokeWidth = math.max(1, _r * 0.018)
        ..strokeCap = StrokeCap.round;
      final rnd = math.Random(5);
      for (var i = 0; i < 14; i++) {
        final a = rnd.nextDouble() * 2 * math.pi;
        final r0 = _r * (0.25 + rnd.nextDouble() * 0.2);
        final r1 = r0 + _r * (0.12 + rnd.nextDouble() * 0.2);
        canvas.drawLine(
          Offset(_cx + r0 * math.cos(a), _topY + r0 * _tilt * math.sin(a)),
          Offset(_cx + r1 * math.cos(a), _topY + r1 * _tilt * math.sin(a)),
          ray,
        );
      }
    }
  }

  // Dekor doirasi — chetga yaqin, teng oraliqda, turlar navbat bilan;
  // orqadagilar avval (y bo'yicha saralanadi). Dekor yo'q — krem tomchilari.
  void _paintDecor(Canvas canvas) {
    final types = spec.decor.isEmpty ? const <CakeDecor>[] : spec.decor;
    final items = <(double, CakeDecor?, int)>[];
    const count = 10;
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / count + 0.15;
      final type = types.isEmpty ? null : types[i % types.length];
      items.add((a, type, i));
    }
    // Kokos/mindal — chetga sochiladigan mayda narsalar (alohida, pastda).
    final ringR = _r * 0.80;
    Offset pos(double a) =>
        Offset(_cx + ringR * math.cos(a), _topY + ringR * _tilt * math.sin(a));
    final petals = types.contains(CakeDecor.almond);
    final flakes = types.contains(CakeDecor.coconut);
    if (petals || flakes) {
      final rnd = math.Random(41);
      final n = (_r * 0.9).round();
      for (var i = 0; i < n; i++) {
        final a = rnd.nextDouble() * 2 * math.pi;
        final rr = _r * (0.72 + rnd.nextDouble() * 0.2);
        final p = Offset(_cx + rr * math.cos(a), _topY + rr * _tilt * math.sin(a));
        if (petals) {
          _almondPetal(canvas, p, _r * (0.05 + rnd.nextDouble() * 0.03),
              rnd.nextDouble() * math.pi);
        } else {
          canvas.drawOval(
            Rect.fromCenter(center: p, width: _r * 0.05, height: _r * 0.03),
            Paint()..color = Colors.white.withValues(alpha: 0.9),
          );
        }
      }
    }
    // Katta dekorlar — y bo'yicha (orqadan oldinga).
    final big = [
      for (final (a, t, i) in items)
        if (t != CakeDecor.almond && t != CakeDecor.coconut) (a, t, i),
    ]..sort((x, y) => math.sin(x.$1).compareTo(math.sin(y.$1)));
    for (final (a, t, i) in big) {
      final p = pos(a);
      final depth = 0.9 + 0.2 * ((math.sin(a) + 1) / 2); // oldingilari kattaroq
      final s = _r * 0.17 * depth;
      switch (t) {
        case CakeDecor.raffaello:
          _raffaello(canvas, p, s, i);
        case CakeDecor.meringue:
          _meringue(canvas, p, s, Colors.white);
        case CakeDecor.strawberry:
          _strawberry(canvas, p, s);
        case CakeDecor.raspberry:
          _raspberry(canvas, p, s, i);
        case CakeDecor.cherry:
          _cherry(canvas, p, s);
        case CakeDecor.blueberry:
          _sphere(canvas, p, s * 0.7, const Color(0xFF4B3B8F));
        case CakeDecor.chocolate:
          _chocolate(canvas, p, s);
        case CakeDecor.nut:
          _nut(canvas, p, s);
        case CakeDecor.almond:
        case CakeDecor.coconut:
          break;
        case null:
          // Dekor topilmadi — qoplama rangidagi krem tomchilari.
          _meringue(canvas, p, s * 0.9, _light(spec.coat, 0.2));
      }
    }
  }

  void _shadow(Canvas canvas, Offset p, double s) {
    canvas.drawOval(
      Rect.fromCenter(center: p.translate(0, s * 0.55), width: s * 2.1, height: s * 0.7),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  // Shar (rang bilan) — yorug' yuqori-chap, soya pastki-o'ng.
  void _sphere(Canvas canvas, Offset p, double s, Color c) {
    _shadow(canvas, p, s);
    final rect = Rect.fromCircle(center: p, radius: s);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.9,
          colors: [_light(c, 0.45), c, _dark(c, 0.3)],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
  }

  // Рафаэлло shari: oq shar + kokos qirindisi nuqtalari.
  void _raffaello(Canvas canvas, Offset p, double s, int seed) {
    _sphere(canvas, p, s, const Color(0xFFFBF5EA));
    final rnd = math.Random(seed * 7 + 1);
    for (var i = 0; i < 26; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rr = math.sqrt(rnd.nextDouble()) * s * 0.9;
      final q = Offset(p.dx + rr * math.cos(a), p.dy + rr * math.sin(a));
      final shade = (q.dx - p.dx) / s * 0.5 + (q.dy - p.dy) / s * 0.5;
      canvas.drawOval(
        Rect.fromCenter(center: q, width: s * 0.22, height: s * 0.14),
        Paint()
          ..color = shade > 0.2
              ? const Color(0xFFD9CDB8)
              : Colors.white.withValues(alpha: 0.95),
      );
    }
  }

  // Безе tomchisi: asos ellips + uchi egilgan konus.
  void _meringue(Canvas canvas, Offset p, double s, Color c) {
    _shadow(canvas, p, s * 0.9);
    final path = Path()
      ..moveTo(p.dx - s * 0.95, p.dy + s * 0.15)
      ..quadraticBezierTo(p.dx - s * 0.6, p.dy - s * 1.0, p.dx + s * 0.15, p.dy - s * 1.75)
      ..quadraticBezierTo(p.dx + s * 0.2, p.dy - s * 0.9, p.dx + s * 0.95, p.dy + s * 0.15)
      ..quadraticBezierTo(p.dx, p.dy + s * 0.55, p.dx - s * 0.95, p.dy + s * 0.15)
      ..close();
    final box = Rect.fromLTRB(p.dx - s, p.dy - s * 1.8, p.dx + s, p.dy + s * 0.5);
    // Oq, yumshoq soyali (chap tomoni yorug', o'ng tomoni sal kremrang).
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [_light(c, 0.4), c, Color.lerp(c, const Color(0xFFD8CBB4), 0.35)!],
          stops: const [0, 0.5, 1],
        ).createShader(box),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0xFFCDBFA6).withValues(alpha: 0.45),
    );
  }

  void _almondPetal(Canvas canvas, Offset p, double s, double rot) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(rot);
    final rect = Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 1.1);
    canvas.drawOval(rect, Paint()..color = const Color(0xFFF1D58C));
    canvas.drawOval(
      rect.deflate(s * 0.25),
      Paint()..color = const Color(0xFFF8E7B3).withValues(alpha: 0.8),
    );
    canvas.restore();
  }

  void _strawberry(Canvas canvas, Offset p, double s) {
    _shadow(canvas, p, s);
    const red = Color(0xFFD9364A);
    final body = Path()
      ..moveTo(p.dx - s * 0.85, p.dy - s * 0.5)
      ..quadraticBezierTo(p.dx - s * 0.9, p.dy + s * 0.6, p.dx, p.dy + s * 1.0)
      ..quadraticBezierTo(p.dx + s * 0.9, p.dy + s * 0.6, p.dx + s * 0.85, p.dy - s * 0.5)
      ..quadraticBezierTo(p.dx, p.dy - s * 1.0, p.dx - s * 0.85, p.dy - s * 0.5)
      ..close();
    final box = Rect.fromCircle(center: p, radius: s);
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.95,
          colors: [_light(red, 0.3), red, _dark(red, 0.3)],
          stops: const [0, 0.55, 1],
        ).createShader(box),
    );
    final rnd = math.Random(3);
    for (var i = 0; i < 9; i++) {
      final q = Offset(p.dx + (rnd.nextDouble() - 0.5) * s * 1.2,
          p.dy + (rnd.nextDouble() - 0.4) * s * 1.2);
      canvas.drawOval(
        Rect.fromCenter(center: q, width: s * 0.16, height: s * 0.22),
        Paint()..color = const Color(0xFFF6E27A),
      );
    }
    // Barglari.
    final leaf = Paint()..color = const Color(0xFF4CAF50);
    for (final dir in [-1.0, 0.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - s * 0.55)
          ..quadraticBezierTo(p.dx + dir * s * 0.5, p.dy - s * 0.9, p.dx + dir * s * 0.7, p.dy - s * 1.2)
          ..quadraticBezierTo(p.dx + dir * s * 0.25, p.dy - s * 0.95, p.dx, p.dy - s * 0.55)
          ..close(),
        leaf,
      );
    }
  }

  void _raspberry(Canvas canvas, Offset p, double s, int seed) {
    _shadow(canvas, p, s * 0.9);
    const c = Color(0xFFC2185B);
    final rnd = math.Random(seed + 9);
    for (var i = 0; i < 12; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rr = math.sqrt(rnd.nextDouble()) * s * 0.65;
      final q = Offset(p.dx + rr * math.cos(a), p.dy + rr * math.sin(a) * 0.9);
      final rect = Rect.fromCircle(center: q, radius: s * 0.32);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 0.9,
            colors: [_light(c, 0.35), c, _dark(c, 0.25)],
          ).createShader(rect),
      );
    }
  }

  void _cherry(Canvas canvas, Offset p, double s) {
    _sphere(canvas, p, s * 0.75, const Color(0xFF8E1230));
    canvas.drawPath(
      Path()
        ..moveTo(p.dx, p.dy - s * 0.6)
        ..quadraticBezierTo(p.dx + s * 0.3, p.dy - s * 1.3, p.dx + s * 0.7, p.dy - s * 1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.12)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF5D4037),
    );
  }

  void _chocolate(Canvas canvas, Offset p, double s) {
    _shadow(canvas, p, s);
    const c = Color(0xFF4E2A1A);
    final rect = Rect.fromCenter(center: p, width: s * 1.6, height: s * 1.1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(0, s * 0.25), Radius.circular(s * 0.15)),
      Paint()..color = _dark(c, 0.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(s * 0.15)),
      Paint()..color = c,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(s * 0.2), Radius.circular(s * 0.1)),
      Paint()..color = _light(c, 0.12),
    );
  }

  void _nut(Canvas canvas, Offset p, double s) {
    _shadow(canvas, p, s * 0.8);
    const c = Color(0xFFB98A55);
    final rect = Rect.fromCenter(center: p, width: s * 1.5, height: s * 1.1);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [_light(c, 0.35), c, _dark(c, 0.3)],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(p.dx, p.dy - s * 0.45),
      Offset(p.dx, p.dy + s * 0.45),
      Paint()
        ..color = _dark(c, 0.35)
        ..strokeWidth = math.max(1, s * 0.1),
    );
  }

  // Patnis oldidagi yorliq: «Mone» + kichik yozuv.
  void _paintLabel(Canvas canvas, Offset c, double rx, double ry) {
    final title = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF5B3A1E),
          fontSize: (rx * 0.11).clamp(11, 22),
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final sub = subLabel == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: subLabel,
              style: TextStyle(
                color: const Color(0xFF7A5C40),
                fontSize: (rx * 0.045).clamp(6, 10),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout());
    final w = math.max(title.width, sub?.width ?? 0) + rx * 0.16;
    final h = title.height + (sub?.height ?? 0) + rx * 0.05;
    final tab = Rect.fromCenter(
        center: Offset(c.dx, c.dy + ry * 0.92), width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(tab, Radius.circular(h * 0.3)),
      Paint()..color = const Color(0xFFF4F1FA),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tab, Radius.circular(h * 0.3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFD5D0E3),
    );
    title.paint(canvas, Offset(c.dx - title.width / 2, tab.top + rx * 0.02));
    sub?.paint(canvas, Offset(c.dx - sub.width / 2, tab.top + rx * 0.02 + title.height - 2));
  }

  @override
  bool shouldRepaint(CakeIllustrationPainter old) =>
      old.spec != spec || old.label != label || old.subLabel != subLabel;
}
