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
// Mevalar (BiscuitFruit.detect — вишня, клубника, малина, банан, киви ...)
// biskvit NOMIDAN; FAQAT yon tomonda (kesimda) chiziladi, tepada bezak yo'q.
// Tex kartada biskvit FOTOSI bo'lsa (biscuit_photo_url) — yon tomonga shu
// fotoning O'ZI o'raladi (biscuit_side_photo.dart yuklaydi): g'ovak/meva
// chizilmaydi, fotodan rang/meva «taxmin qilinmaydi». Tepa — oddiy qobiq.
// BiscuitThumb — grid kartasi uchun kichik statik rasm.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
import 'package:uz_ai_dev/core/constants/urls.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_side_photo.dart';
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

  // Biskvit ranglari — ustuvorlik bilan: tex kartadagi «Biskvit rangi»
  // palitrasidan tanlangan rang (biscuit_color) → nom/tarkibdan (detect).
  static BiscuitPalette of(String name, TechCard? card) {
    final picked = fillingColorFromHex(card?.biscuitColor ?? '');
    return picked != null ? fromColor(picked) : detect(name, card);
  }

  // Bitta rangdan butun palitra: [c] — biskvit (yon tomon) rangi; qobiq,
  // g'ovak va chet chiziqlari — o'sha rangning to'qroq tuslari (pishgan
  // tepa yon tomondan to'qroq bo'ladi), hech qanday begona tus qo'shilmaydi.
  static BiscuitPalette fromColor(Color c) {
    Color dark(double k) => Color.lerp(c, Colors.black, k)!;
    return BiscuitPalette(
      sponge: c,
      spongeShade: dark(0.12),
      spongeLight: Color.lerp(c, Colors.white, 0.28)!,
      crustLight: dark(0.10),
      crust: dark(0.22),
      crustDark: dark(0.34),
      pore: dark(0.22),
      baked: dark(0.30),
      rim: dark(0.40),
    );
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

// Biskvit ichidagi mevalar / rezavorlar — 3D rasmda FAQAT yon tomonda
// (kesimda) chiziladi, tepaga hech narsa qo'yilmaydi.
enum BiscuitFruit {
  cherry,
  strawberry,
  raspberry,
  blueberry,
  currant,
  banana,
  kiwi,
  orange,
  peach,
  pineapple;

  // Kalit so'zlar (ru / uz / en).
  static const Map<BiscuitFruit, List<String>> _words = {
    cherry: ['вишн', 'черешн', 'cherry', 'olcha', 'gilos'],
    strawberry: ['клубни', 'землян', 'strawberr', 'qulupnay'],
    raspberry: ['малин', 'raspberr', 'malina'],
    blueberry: ['черник', 'голубик', 'blueberr'],
    currant: ['смородин', 'клюкв', 'брусник', 'currant', 'cranberr'],
    banana: ['банан', 'banan'],
    kiwi: ['киви', 'kiwi'],
    orange: ['апельсин', 'мандарин', 'orange', 'apelsin', 'mandarin'],
    peach: ['персик', 'абрикос', 'манго', 'peach', 'apricot', 'mango',
        'shaftoli', 'o\'rik'],
    pineapple: ['ананас', 'pineapple', 'ananas'],
  };

  // Mevalar FAQAT biskvit NOMIDAN («...с вишней», «Клубничный» ...), ko'pi
  // bilan 3 xil. Masalliqlar hisobga OLINMAYDI: ular xamirga aralashtiriladi
  // (masalan «Баннофе»dagi banan pyuresi) — yon tomonda bo'lak bo'lib
  // ko'rinmaydi. Nomida meva yo'q — mevasiz oddiy biskvit.
  static List<BiscuitFruit> detect(String name) {
    final text = name.toLowerCase();
    final found = <(int, BiscuitFruit)>[];
    for (final e in _words.entries) {
      var at = -1;
      for (final w in e.value) {
        final i = text.indexOf(w);
        if (i >= 0 && (at < 0 || i < at)) at = i;
      }
      if (at >= 0) found.add((at, e.key));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, f) in found.take(3)) f];
  }
}

// Tex kartadagi biskvit fotosining to'liq URL'i (yo'q bo'lsa null).
String? biscuitPhotoUrlOf(TechCard? card) {
  final raw = card?.biscuitPhotoUrl ?? '';
  if (raw.isEmpty) return null;
  return raw.startsWith('http') ? raw : '${AppUrls.baseUrl}$raw';
}

class Biscuit3DView extends StatelessWidget {
  final BiscuitDims dims;
  final BiscuitPalette palette;
  // Yon tomondagi mevalar (biskvit nomidan).
  final List<BiscuitFruit> fruits;
  // Tex kartadagi foto: berilsa — yon tomonga (mevalar chiziladigan tasma
  // o'rniga) shu FOTONING O'ZI o'raladi; chizilgan meva/g'ovak bo'lmaydi.
  // Foto saqlangach 3D o'zi yangilanadi.
  final String? photoUrl;
  final double height;

  const Biscuit3DView({
    super.key,
    required this.dims,
    this.palette = BiscuitPalette.classic,
    this.fruits = const [],
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
        painter: (tilt, rotation) => BiscuitPainter(
          dims: dims,
          palette: palette,
          fruits: fruits,
          sidePhoto: photo,
          tilt: tilt,
          rotation: rotation,
        ),
      ),
    );
  }
}

// Kartadagi kichik statik rasm: shu biskvitning o'zi (o'lchami, turi,
// mevalari; foto bo'lsa — yon tomoni fotoning o'zi), yumshoq fon ustida.
class BiscuitThumb extends StatelessWidget {
  final BiscuitDims dims;
  final BiscuitPalette palette;
  final List<BiscuitFruit> fruits;
  final String? photoUrl;

  const BiscuitThumb({
    super.key,
    required this.dims,
    required this.palette,
    this.fruits = const [],
    this.photoUrl,
  });

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
            painter: BiscuitPainter(
              dims: dims,
              palette: palette,
              fruits: fruits,
              sidePhoto: photo,
              tilt: 0.36,
              rotation: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class BiscuitPainter extends CustomPainter {
  final BiscuitDims dims;
  final BiscuitPalette palette;
  // Yon tomondagi mevalar (bo'sh — mevasiz).
  final List<BiscuitFruit> fruits;
  // Tex kartadagi foto: berilsa yon tomon shu fotoning o'zi bilan o'raladi
  // (g'ovak/meva CHIZILMAYDI); tepa — oddiy pishgan qobiq.
  final ui.Image? sidePhoto;
  final double tilt;
  final double rotation;

  BiscuitPainter({
    required this.dims,
    this.palette = BiscuitPalette.classic,
    this.fruits = const [],
    this.sidePhoto,
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
    if (sidePhoto != null) {
      _textureRound(canvas, sidePhoto!, r, top, bottom, h);
      // Hajm soyasi: chetlari qoramtirroq — silindr ko'rinishi uchun.
      canvas.drawRect(
        Rect.fromLTRB(_cx - r, top - r * tilt, _cx + r, bottom + r * tilt),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.30),
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.30),
            ],
            stops: const [0, 0.3, 0.7, 1],
          ).createShader(bottomOval),
      );
      canvas.restore();
      _paintRoundTop(canvas, r, bottomOval, h);
      return;
    }
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
    _fruitsRound(canvas, r, top, h, pxPerCm);
    canvas.restore();
    _paintRoundTop(canvas, r, bottomOval, h);
  }

  // Fotodan yon tomonga tushadigan qism: o'rtadagi gorizontal tasma,
  // nisbati yuzaning o'ziniki ([aspect] = uzunlik / balandlik) — rasm
  // cho'zilib/ezilib ketmaydi (BoxFit.cover kabi).
  static Rect _photoBand(ui.Image img, double aspect) {
    final w = img.width.toDouble(), hgt = img.height.toDouble();
    final bandH = math.min(hgt, w / math.max(aspect, 0.01));
    final bandW = math.min(w, bandH * aspect);
    return Rect.fromCenter(
        center: Offset(w / 2, hgt / 2), width: bandW, height: bandH);
  }

  // Yumaloq biskvit yon tomoniga fotoni «o'rash»: old yarim aylana ingichka
  // vertikal bo'laklarga bo'linadi, har biriga tasmaning mos qismi chiziladi.
  // Tasma yarim aylanaga teng; ikkinchi yarmida ko'zgu (chok ko'rinmasin).
  // Biskvit burilganda foto ham birga buriladi.
  void _textureRound(Canvas canvas, ui.Image img, double r, double top,
      double bottom, double h) {
    final band = _photoBand(img, math.pi * r / math.max(h, 1));
    final paint = Paint()..filterQuality = FilterQuality.medium;
    double u(double t) {
      var a = (t - rotation) % (2 * math.pi);
      if (a < 0) a += 2 * math.pi;
      return a < math.pi ? a / math.pi : 2 - a / math.pi;
    }

    const n = 72;
    for (var j = 0; j < n; j++) {
      final t0 = -math.pi / 2 + math.pi * j / n;
      final t1 = -math.pi / 2 + math.pi * (j + 1) / n;
      final yOff = r * tilt * math.cos((t0 + t1) / 2);
      final ua = u(t0);
      final ub = u(t1);
      final lo = math.min(ua, ub);
      final hi = math.max(math.max(ua, ub), lo + 0.002);
      final src = Rect.fromLTRB(band.left + lo * band.width, band.top,
          band.left + math.min(hi, 1) * band.width, band.bottom);
      final dst = Rect.fromLTRB(_cx + r * math.sin(t0) - 0.4, top + yOff,
          _cx + r * math.sin(t1) + 0.4, bottom + yOff);
      if (ua <= ub) {
        canvas.drawImageRect(img, src, dst, paint);
      } else {
        // Ko'zgu qismi — bo'lak ichidagi rasm ham teskari chiziladi,
        // aks holda rasm «maydalanib» ko'rinadi.
        canvas.save();
        canvas.translate(dst.center.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-dst.center.dx, 0);
        canvas.drawImageRect(img, src, dst, paint);
        canvas.restore();
      }
    }
  }

  // To'rtburchak biskvitning bitta yon yuziga foto (yuz bo'ylab to'liq,
  // ekranda chapdan o'ngga — rasm teskari chiqmaydi). [lenPx] — yuzning
  // haqiqiy uzunligi (burilishdan qat'i nazar), tasma nisbati uchun.
  void _textureFace(Canvas canvas, ui.Image img, Offset a, Offset b,
      double h, double lenPx) {
    if (a.dx > b.dx) {
      final t = a;
      a = b;
      b = t;
    }
    final band = _photoBand(img, lenPx / math.max(h, 1));
    final paint = Paint()..filterQuality = FilterQuality.medium;
    const n = 32;
    for (var j = 0; j < n; j++) {
      final p0 = Offset.lerp(a, b, j / n)!;
      final p1 = Offset.lerp(a, b, (j + 1) / n)!;
      final y = (p0.dy + p1.dy) / 2;
      canvas.drawImageRect(
        img,
        Rect.fromLTRB(band.left + band.width * j / n, band.top,
            band.left + band.width * (j + 1) / n, band.bottom),
        Rect.fromLTRB(p0.dx - 0.4, y - 1, p1.dx + 0.4, y + h + 1),
        paint,
      );
    }
  }

  // Meva o'lchami (radius, sm) — haqiqiy kattalikka yaqin.
  static double _fruitRadiusCm(BiscuitFruit f) => switch (f) {
        BiscuitFruit.cherry => 0.9,
        BiscuitFruit.strawberry => 1.1,
        BiscuitFruit.raspberry => 0.8,
        BiscuitFruit.blueberry => 0.55,
        BiscuitFruit.currant => 0.45,
        BiscuitFruit.banana => 1.2,
        BiscuitFruit.kiwi => 1.2,
        BiscuitFruit.orange => 1.3,
        BiscuitFruit.peach => 0.9,
        BiscuitFruit.pineapple => 0.9,
      };

  // Yumaloq biskvit YON tomonidagi mevalar (kesimda ko'rinadigan bo'laklar).
  // Joylari tasodifiy, lekin har doim bir xil (seed) — biskvit bilan birga
  // aylanadi; faqat old tomondagilari chiziladi. Tepaga hech narsa yo'q.
  void _fruitsRound(
      Canvas canvas, double r, double top, double h, double pxPerCm) {
    if (fruits.isEmpty) return;
    final rnd = math.Random(17);
    // Aylana uzunligiga qarab soni (≈ har 3 sm ga bitta).
    final n = (2 * math.pi * r / pxPerCm / 3).round().clamp(10, 36);
    for (var i = 0; i < n; i++) {
      final fruit = fruits[i % fruits.length];
      final a = (i + rnd.nextDouble() * 0.6) * 2 * math.pi / n;
      final v = 0.3 + rnd.nextDouble() * 0.4;
      final t = a + rotation;
      final c = math.cos(t);
      if (c < 0.12) continue;
      final rad = math.min(_fruitRadiusCm(fruit) * pxPerCm, h * 0.3);
      final center = Offset(_cx + r * math.sin(t), top + r * tilt * c + v * h);
      _paintFruit(canvas, fruit, center, rad * (0.35 + 0.65 * c), rad,
          i + (rnd.nextDouble() * 100).toInt());
    }
  }

  // To'rtburchak biskvitning bitta yon yuzidagi mevalar.
  void _fruitsFace(Canvas canvas, Offset a, Offset b, double h,
      double pxPerCm, double facing, int seed) {
    if (fruits.isEmpty) return;
    final rnd = math.Random(31 + seed);
    final lenCm = (b - a).distance / pxPerCm / math.max(facing, 0.2);
    final n = (lenCm / 3).round().clamp(3, 16);
    for (var i = 0; i < n; i++) {
      final fruit = fruits[(i + seed) % fruits.length];
      final u = (i + 0.2 + rnd.nextDouble() * 0.6) / n;
      final v = 0.3 + rnd.nextDouble() * 0.4;
      final rad = math.min(_fruitRadiusCm(fruit) * pxPerCm, h * 0.3);
      final center = Offset.lerp(a, b, u)!.translate(0, v * h);
      _paintFruit(canvas, fruit, center, rad * (0.35 + 0.65 * facing), rad,
          i + seed * 7);
    }
  }

  // Bitta meva bo'lagi (kesim ko'rinishi). [rx] — kenglik (burilishga qarab
  // qisqaradi), [ry] — balandlik.
  void _paintFruit(Canvas canvas, BiscuitFruit fruit, Offset c, double rx,
      double ry, int seed) {
    Rect box([double k = 1]) =>
        Rect.fromCenter(center: c, width: rx * 2 * k, height: ry * 2 * k);
    Paint grad(List<Color> colors, [Alignment center = const Alignment(-0.3, -0.35)]) =>
        Paint()
          ..shader = RadialGradient(center: center, colors: colors)
              .createShader(box());
    void gloss() => canvas.drawOval(
          Rect.fromCenter(
            center: c.translate(-rx * 0.35, -ry * 0.4),
            width: rx * 0.55,
            height: ry * 0.35,
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.45),
        );

    switch (fruit) {
      case BiscuitFruit.cherry:
        canvas.drawOval(box(), grad(const [
          Color(0xFFD7324A),
          Color(0xFF9A0F28),
          Color(0xFF5A0616),
        ]));
        // Sharbat izi atrofida.
        canvas.drawOval(
          box(1.18),
          Paint()
            ..color = const Color(0xFF8E0E24).withValues(alpha: 0.18),
        );
        gloss();
      case BiscuitFruit.strawberry:
        canvas.drawOval(box(), Paint()..color = const Color(0xFFD9283C));
        canvas.drawOval(box(0.72), Paint()..color = const Color(0xFFF26C7A));
        canvas.drawOval(box(0.38), Paint()..color = const Color(0xFFFFD3D6));
        final seedPaint = Paint()..color = const Color(0xFFF7D774);
        for (var k = 0; k < 7; k++) {
          final ang = k * 2 * math.pi / 7 + seed;
          canvas.drawCircle(
            c.translate(math.cos(ang) * rx * 0.86, math.sin(ang) * ry * 0.86),
            math.max(0.6, ry * 0.07),
            seedPaint,
          );
        }
      case BiscuitFruit.raspberry:
        final p = Paint()..color = const Color(0xFFC2185B);
        final hi = Paint()..color = const Color(0xFFE35D8A);
        for (var k = 0; k < 6; k++) {
          final ang = k * 2 * math.pi / 6;
          final o = c.translate(math.cos(ang) * rx * 0.5, math.sin(ang) * ry * 0.5);
          canvas.drawOval(
              Rect.fromCenter(center: o, width: rx * 0.9, height: ry * 0.9), p);
          canvas.drawCircle(o.translate(-rx * 0.12, -ry * 0.12),
              math.max(0.6, ry * 0.12), hi);
        }
        canvas.drawOval(box(0.45), p);
      case BiscuitFruit.blueberry:
      case BiscuitFruit.currant:
        canvas.drawOval(box(), grad(fruit == BiscuitFruit.blueberry
            ? const [Color(0xFF6D78C4), Color(0xFF34397A), Color(0xFF1E2152)]
            : const [Color(0xFF5A4A6E), Color(0xFF2A1E36), Color(0xFF140C1C)]));
        gloss();
      case BiscuitFruit.banana:
        canvas.drawOval(box(), Paint()..color = const Color(0xFFF1E2A2));
        canvas.drawOval(box(0.8), Paint()..color = const Color(0xFFFBF1C8));
        final d = Paint()..color = const Color(0xFF8A6A3A);
        for (var k = 0; k < 3; k++) {
          final ang = k * 2 * math.pi / 3 + 0.5;
          canvas.drawCircle(
            c.translate(math.cos(ang) * rx * 0.22, math.sin(ang) * ry * 0.22),
            math.max(0.5, ry * 0.06),
            d,
          );
        }
      case BiscuitFruit.kiwi:
        canvas.drawOval(box(), Paint()..color = const Color(0xFF6E4B2A));
        canvas.drawOval(box(0.9), Paint()..color = const Color(0xFF7DBA3A));
        canvas.drawOval(box(0.36), Paint()..color = const Color(0xFFE9F2C8));
        final s = Paint()..color = const Color(0xFF1B1B1B);
        for (var k = 0; k < 10; k++) {
          final ang = k * 2 * math.pi / 10;
          canvas.drawCircle(
            c.translate(math.cos(ang) * rx * 0.5, math.sin(ang) * ry * 0.5),
            math.max(0.5, ry * 0.05),
            s,
          );
        }
      case BiscuitFruit.orange:
        canvas.drawOval(box(), Paint()..color = const Color(0xFFF08A1C));
        canvas.drawOval(box(0.86), Paint()..color = const Color(0xFFFFB347));
        final line = Paint()
          ..color = const Color(0xFFFFE0A8)
          ..strokeWidth = math.max(0.6, ry * 0.06);
        for (var k = 0; k < 8; k++) {
          final ang = k * 2 * math.pi / 8;
          canvas.drawLine(
            c,
            c.translate(math.cos(ang) * rx * 0.84, math.sin(ang) * ry * 0.84),
            line,
          );
        }
      case BiscuitFruit.peach:
      case BiscuitFruit.pineapple:
        final colors = fruit == BiscuitFruit.peach
            ? const [Color(0xFFFFC870), Color(0xFFF59E3A), Color(0xFFD9772A)]
            : const [Color(0xFFFFF09A), Color(0xFFF2D34A), Color(0xFFD8AE2A)];
        canvas.drawRRect(
          RRect.fromRectAndRadius(box(), Radius.circular(ry * 0.35)),
          grad(colors),
        );
        gloss();
    }
  }

  // Tepa — pishgan qobiq (mevalar faqat yon tomonda).
  void _paintRoundTop(Canvas canvas, double r, Rect bottomOval, double h) {
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
      if (sidePhoto != null) {
        // Foto bor — yuzga fotoning o'zi; g'ovak/meva chizilmaydi.
        _textureFace(canvas, sidePhoto!, tops[k], tops[k1], h,
            k.isEven ? hw * 2 : hl * 2);
      } else {
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
                center: p,
                width: s * (0.4 + 0.6 * npz) + 0.6,
                height: s * 0.8),
            palette.speck != null && i % 3 == 0 ? speck : pore,
          );
        }
        _fruitsFace(canvas, tops[k], tops[k1], h, pxPerCm, npz, k);
      }
      // Yon yuzning yorug'lik soyasi (mevalar ham soyada qoladi).
      canvas.drawPath(
        face,
        Paint()..color = Colors.black.withValues(alpha: (1 - f) * 0.18),
      );
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
      !listEquals(old.fruits, fruits) ||
      old.sidePhoto != sidePhoto ||
      old.tilt != tilt ||
      old.rotation != rotation;
}
