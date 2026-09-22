// shef/ui/widgets/filling_3d.dart — «П/Ф Начинка» uchun 3D ko'rinish:
// bo'lagi kesib olingan yumaloq tort — 3 ta biskvit qatlami va ular orasida
// 2 ta NACHINKA qatlami. Kesimda (va «yalang'och» yon tomonda) nachinka
// ko'rinadi. Manba ustuvorligi (FillingLook.resolve): tex kartadagi PALITRADAN
// tanlangan rang (filling_color) → tex kartadagi foto → nom/tarkib.
// Nom/tarkibdan rang (FillingLook.detect):
//   1) mahsulot nomi → 2) blok nomlari → 3) masalliqlar.
// Masalliqlarda miqdori (g/ml) ENG KO'P bo'lgan rang beruvchi masalliq
// tanlanadi (masalan 300 g qulupnay pyuresi + 50 g shokolad → qulupnay);
// slivka/tvorog kabi neytral asos faqat boshqa hech narsa topilmasa olinadi.
// Tex kartada FOTO bo'lsa (biscuit_photo_url — «Rasm qo'shish») nachinka
// qatlamlari rangi shu fotodan olinadi va nom/tarkibdan USTUN turadi
// (filling_photo_look.dart): kesim fotosidan nachinka qatlamining yo'llari
// (krem – jele – krem), ranglari va nisbati olinadi (FillingBand).
// Fotoning o'zi, meva bo'laklari va boshqa bezak CHIZILMAYDI — faqat rang.
// Filling3DView — Rotating3DView (cake_3d.dart) qo'lda rejimida;
// FillingThumb — grid kartasi uchun kichik statik rasm.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_side_photo.dart';
import 'package:uz_ai_dev/shef/ui/widgets/cake_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_photo_look.dart';

// Nachinka qatlami ichidagi bitta yo'l: rangi va qatlamdagi ulushi.
// Masalan fotoda ikki korj orasi «krem – jele – krem» bo'lsa, nachinka
// qatlami uch yo'ldan iborat (oq, qizil, oq).
@immutable
class FillingBand {
  final Color color;
  final double part;

  const FillingBand(this.color, this.part);

  @override
  bool operator ==(Object other) =>
      other is FillingBand && other.color == color && other.part == part;

  @override
  int get hashCode => Object.hash(color, part);
}

// Nachinka rangi (тех картадан; tex kartada foto bo'lsa — fotodan).
class FillingLook {
  // YUQORI nachinka qatlami rangi (bandsOf(0)); asosiy rang sifatida ham.
  // Tex kartadagi YAGONA palitradan (fromTechCard) — u holda HAMMA qatlam
  // shu rangda (color2 = null).
  final Color color;
  // PASTKI nachinka qatlami rangi (bandsOf(1); null — yuqorisi bilan bir
  // xil). FAQAT fotodan keladi (masalan «kaymoq + shokolad» — bir qatlam
  // oqish, ikkinchisi jigarrang, filling_photo_look.dart); palitrada
  // ikkinchi rang yo'q.
  final Color? color2;
  // Fotodagi kesimdan olingan yo'llar (tepadan pastga): 1-nachinka qatlami
  // va (boshqacha bo'lsa) 2-si. null — qatlam bitta rangda ([color]).
  final List<FillingBand>? bands1;
  final List<FillingBand>? bands2;

  const FillingLook(this.color, [this.color2])
      : bands1 = null,
        bands2 = null;

  // Fotodagi kesimdan: [color] — 1-qatlamning eng keng yo'li.
  FillingLook.layered(List<FillingBand> first, [List<FillingBand>? second])
      : color = first.reduce((a, b) => b.part > a.part ? b : a).color,
        color2 = null,
        bands1 = first,
        bands2 = second;

  // [k]-nachinka qatlami (tepadan: 0, 1) yo'llari.
  List<FillingBand> bandsOf(int k) {
    if (k == 0) return bands1 ?? [FillingBand(color, 1)];
    return bands2 ?? bands1 ?? [FillingBand(color2 ?? color, 1)];
  }

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

  // Mahsulot uchun 3D manbai — (ko'rinish, foto URL) — ustuvorlik bilan:
  //  1) tex kartadagi PALITRADAN tanlangan rang (filling_color) — eng ustun:
  //     nachinka aynan shu rangda, foto tahlil QILINMAYDI (URL null);
  //  2) tex kartadagi foto — qatlamlar/ranglar fotodan (URL qaytadi);
  //  3) nom / blok / masalliqlardan (detect).
  static (FillingLook, String?) resolve(String name, TechCard? card) {
    if (hasPaletteColor(card)) return (fromTechCard(name, card), null);
    return (detect(name, card), biscuitPhotoUrlOf(card));
  }

  // Tex kartada nachinka palitrasidan rang tanlanganmi.
  static bool hasPaletteColor(TechCard? card) =>
      fillingColorFromHex(card?.fillingColor ?? '') != null;

  // Rang FAQAT tex kartadan (foto tahlili yo'q): YAGONA palitra (filling_color)
  // → tavsif (detect). Tanlangan rang nachinkaning HAMMA qatlamlariga
  // qo'llanadi; tanlanmagan bo'lsa — hammasi tavsifdan.
  static FillingLook fromTechCard(String name, TechCard? card) {
    final picked = fillingColorFromHex(card?.fillingColor ?? '');
    return picked == null ? detect(name, card) : FillingLook(picked);
  }

  // «Покрытие» bo'limi: shu mahsulot tortni TASHQARIDAN qoplagandagi rang.
  // Tex kartadagi YAGONA palitra («Nachinka rangi», filling_color) — mahsulot
  // qanday rangda tanlangan bo'lsa, qoplama ham shu rangda; eski
  // coating_color qiymati bo'lsa u ustun. Tanlanmagan bo'lsa — nom/tarkibdan
  // (detect). Foto bu yerga ta'sir qilmaydi.
  static Color coatOf(String name, TechCard? card) =>
      fillingColorFromHex(card?.coatingColor ?? '') ??
      fillingColorFromHex(card?.fillingColor ?? '') ??
      detect(name, card).color;

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
      other is FillingLook &&
      other.color == color &&
      other.color2 == color2 &&
      listEquals(other.bands1, bands1) &&
      listEquals(other.bands2, bands2);

  @override
  int get hashCode => Object.hash(
        color,
        color2,
        bands1 == null ? null : Object.hashAll(bands1!),
        bands2 == null ? null : Object.hashAll(bands2!),
      );
}

class Filling3DView extends StatelessWidget {
  // Тех карта nomi/tarkibidan olingan rang (foto yo'q yoki fotodan rang
  // topilmagan holat uchun).
  final FillingLook look;
  // Tex kartadagi foto (to'liq URL): berilsa nachinka qatlamlari rangi
  // FOTODAN olinadi (FillingPhotoLook) va [look] dan ustun turadi. Tex karta
  // saqlangach 3D o'zi yangilanadi.
  final String? photoUrl;
  // «Покрытие» bo'limi: tort shu rangda tashqaridan qoplangan (painter.coat).
  final Color? coat;
  // Konstruktor: qoplangan tortdan ham bo'lak kesiladi (painter.coatCut) va
  // korjlar tanlangan biskvit rangida (painter.sponge).
  final bool coatCut;
  final BiscuitPalette sponge;
  // Konstruktor: tort o'lchami tanlangan biskvitniki (painter.dims).
  final BiscuitDims? dims;
  // Konstruktor: nachinka QATLAMLARI (tepadan pastga) — har biri o'z
  // yo'llari bilan (painter.fillings). null — [look] dan 2 qatlam.
  final List<List<FillingBand>>? fillings;
  // Tort konstruktori (3-qadam): TAYYOR TORTNING fotosi (to'liq URL) —
  // qoplangan butun tortga «o'raladi»: yon devorga tasma bo'lib
  // (biskvitdagidek), tepaga fotoning markazi (doira → ellips). Tort
  // burilganda foto birga buriladi. Faqat [coat] bilan; yuklanguncha —
  // oddiy qoplama rangi.
  final String? sidePhotoUrl;
  final double height;

  const Filling3DView({
    super.key,
    this.look = FillingLook.neutral,
    this.photoUrl,
    this.coat,
    this.coatCut = false,
    this.sponge = BiscuitPalette.classic,
    this.dims,
    this.fillings,
    this.sidePhotoUrl,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context) {
    return FillingPhotoLookBuilder(
      url: photoUrl,
      builder: (context, photoLook) => BiscuitSidePhotoBuilder(
        url: sidePhotoUrl,
        displayWidth: height * 2,
        builder: (context, sidePhoto) => Rotating3DView(
          height: height,
          manual: true,
          painter: (tilt, rotation) => FillingCakePainter(
            look: photoLook ?? look,
            coat: coat,
            coatCut: coatCut,
            sponge: sponge,
            dims: dims,
            fillings: fillings,
            sidePhoto: sidePhoto,
            tilt: tilt,
            rotation: rotation,
          ),
        ),
      ),
    );
  }
}

// Kartadagi kichik statik rasm: shu nachinkali tortning BITTA BO'LAGI
// (butun tort emas) — kesim yuzlarida nachinka ko'rinadi. Karta tanlansa
// tepadagi katta 3D'da o'sha nachinkali butun (kesilgan) tort chiqadi.
class FillingThumb extends StatelessWidget {
  final FillingLook look;
  // Tex kartadagi foto — nachinka rangi shundan (Filling3DView kabi).
  final String? photoUrl;
  // «Покрытие»: shu rangda to'liq qoplangan BUTUN tort (bo'lak emas).
  final Color? coat;
  // true — bo'lak emas, BUTUN (kesilgan) tort: bo'lim kartasi rasmi uchun.
  final bool whole;
  // Konstruktor (3-qadam): qoplangan tort o'lchami TANLANGAN BISKVITNIKI —
  // griddagi hamma qoplama kartalari 1-qadamdagi biskvit o'lchamida
  // (painter.dims). null — standart o'lcham. Bo'lakka ta'sir qilmaydi.
  final BiscuitDims? dims;

  const FillingThumb({
    super.key,
    required this.look,
    this.photoUrl,
    this.coat,
    this.whole = false,
    this.dims,
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
      child: FillingPhotoLookBuilder(
        url: photoUrl,
        builder: (context, photoLook) => RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: FillingCakePainter(
              look: photoLook ?? look,
              coat: coat,
              dims: dims,
              slice: !whole,
              tilt: 0.36,
              rotation: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// «Покрытие» bo'limi kartasi rasmi (shef bosh ekrani / Biskvit bo'limi):
// pushti krem bilan to'liq qoplangan butun tort.
class CoatingSectionThumb extends StatelessWidget {
  const CoatingSectionThumb({super.key});

  @override
  Widget build(BuildContext context) => const FillingThumb(
        look: FillingLook.neutral,
        coat: Color(0xFFF8BBD0),
        whole: true,
      );
}

// Bo'lagi kesib olingan yumaloq tort ([slice] = false) yoki o'sha tortning
// BITTA BO'LAGI ([slice] = true — grid kartalari uchun). Burchak t: ekranda
// x = o'q + r·sin t, chuqurlik cos t (> 0 — tomoshabin tomonda). Chizish
// tartibi orqadan oldinga: patnis → (kesim yuzlari / yon devor) → tepa.
class FillingCakePainter extends CustomPainter {
  final FillingLook look;
  // «Покрытие»: berilsa tort TASHQARIDAN shu rangdagi krem bilan to'liq
  // qoplangan — devor va tepa bir tekis qoplama rangida (qatlamlar
  // ko'rinmaydi). Qoplangan tort har doim BUTUN chiziladi: kesilmaydi va
  // bo'lak rejimi ([slice]) unga ta'sir qilmaydi. null — «yalang'och»,
  // bo'lagi kesilgan tort (nachinka bo'limi).
  final Color? coat;
  // Konstruktor (3-qadam): qoplangan tortdan ham bo'lak KESIB olinadi —
  // kesimda ichidagi nachinka va biskvitni o'rab turgan qoplama qatlami
  // ko'rinadi. Faqat [coat] bilan birga ma'noga ega.
  final bool coatCut;
  // Biskvit (korj) ranglari — konstruktorda tanlangan biskvit turidan
  // (shokoladli, qizil baxmal ...). Bo'limlarda — klassik.
  final BiscuitPalette sponge;
  // Konstruktor: tort o'lchami TANLANGAN BISKVITNIKI (diametr, balandlik —
  // BiscuitPainter bilan AYNAN bir xil masshtab): 1-qadamdan 2/3-qadamga
  // o'tganda tort kattalashib/kichrayib ketmaydi, nachinka qatlamlari shu
  // balandlik ichiga sig'diriladi. null — bo'limlardagi standart o'lcham.
  final BiscuitDims? dims;
  // Konstruktor: nachinka QATLAMLARI (tepadan pastga), har biri o'z
  // yo'llari (rang + ulush) bilan. N ta nachinka → N+1 ta korj, hammasi teng
  // qalinlikda va tort balandligi ICHIGA sig'diriladi. null — [look] dan
  // odatdagi 2 qatlam (bandsOf(0), bandsOf(1)).
  final List<List<FillingBand>>? fillings;
  // Tayyor tort fotosi — qoplangan BUTUN tortga o'raladi (Filling3DView.
  // sidePhotoUrl): yon devor — tasma (BiscuitPainter._textureRound kabi),
  // tepa — fotoning markaziy doirasi. Faqat [coat] != null && ![coatCut].
  final ui.Image? sidePhoto;
  final bool slice;
  final double tilt;
  final double rotation;

  FillingCakePainter({
    required this.look,
    this.coat,
    this.coatCut = false,
    this.sponge = BiscuitPalette.classic,
    this.dims,
    this.fillings,
    this.sidePhoto,
    this.slice = false,
    required this.tilt,
    required this.rotation,
  });

  BiscuitPalette get _sponge => sponge;
  // Qoplama qalinligi: tort balandligi / radiusiga nisbatan ulush.
  static const double _coatPart = 0.075;
  // Kesib olingan bo'lak: markazi va kengligi (radian, tort o'qida).
  // Markaz 0 — burilmagan holatda kesim tomoshabinga qarab ochiladi va
  // ikkala kesim yuzi ham ko'rinadi (kartadagi statik rasm shunday).
  static const double _wedgeCenter = 0;
  static const double _wedgeWidth = 1.05;
  // Nachinka qatlamlari soni (odatda 2).
  int get _fillCount => fillings?.length ?? 2;

  // Qatlamlar TEPADAN pastga: (ulush, nachinkami) — korj, nachinka, korj ...
  // N nachinka → 2N+1 ta teng qism.
  late final List<(double, bool)> _layers = [
    for (var i = 0; i < 2 * _fillCount + 1; i++)
      (1 / (2 * _fillCount + 1), i.isOdd),
  ];

  static bool _sameFillings(
      List<List<FillingBand>>? a, List<List<FillingBand>>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }

  // Bitta bo'lak (slice): burilmagan holatda yoyi orqada, uchi tomoshabinga
  // qaragan — ikkala kesim yuzi ko'rinadi (biri keng, biri tor).
  static const double _sliceCenter = math.pi + 0.35;

  // Tort o'qining ekrandagi x'i (bo'lakda markazdan suriladi).
  late double _cx;
  late double _r;
  late double _top;
  late double _h;

  Offset _rim(double t, double y) =>
      Offset(_cx + _r * math.sin(t), y + _r * tilt * math.cos(t));

  @override
  void paint(Canvas canvas, Size size) {
    final midX = size.width / 2;
    final areaH = size.height;
    final plateRx = math.min(size.width * 0.42, areaH * 0.62);
    final plateRy = plateRx * tilt;
    final plateThick = plateRx * 0.05;
    // Qoplangan tort («Покрытие») har doim BUTUN chiziladi — bo'lak yo'q.
    final asSlice = slice && coat == null;
    // Bo'lak yakka o'zi turadi — kattaroq chiziladi.
    _r = plateRx * (asSlice ? 1.0 : 0.66);
    _h = math.min(plateRx * 0.56, areaH * 0.42);
    final dims = this.dims;
    if (dims != null && !asSlice) {
      // BiscuitPainter'dagi masshtabning O'ZI (sm → px): eng katta yarim
      // o'lcham patnisning ~88% iga sig'adi, 14 sm dan kichigi haqiqiy
      // nisbatda kichikroq. To'rtburchak biskvit — uzun tomoni bo'yicha.
      final halfCm = (dims.rect
              ? math.max(dims.widthCm, dims.lengthCm)
              : dims.diameterCm) /
          2;
      final pxPerCm = plateRx * 0.88 / math.max(halfCm, 14);
      _r = halfCm * pxPerCm;
      _h = math.min(dims.heightCm * pxPerCm, areaH * 0.34);
    }

    final footprint = (asSlice ? plateRx * 0.5 : _r) * tilt;
    final total = _h + footprint + plateRy + plateThick;
    final plateY = (areaH + total) / 2 - plateRy - plateThick;
    final bottom = plateY;

    paintPlate3D(canvas, Offset(midX, plateY), plateRx, plateRy, plateThick);

    if (asSlice) {
      _paintSlice(canvas, midX, bottom);
      return;
    }

    _cx = midX;
    _top = bottom - _h;
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

    _paintBody(canvas);
  }

  // Bitta tort tanasi (_cx, _r, _h, _top, _sponge o'rnatilgan holda).
  void _paintBody(Canvas canvas) {
    // «Покрытие»: tort BUTUN — kesilmagan, bo'laksiz; faqat qoplangan devor
    // (oldingi yarim aylana to'liq) va qoplangan tepa. Konstruktorda
    // ([coatCut]) esa pastdagi umumiy yo'l bilan bo'lagi kesiladi.
    if (coat != null && !coatCut) {
      _paintWall(canvas, -math.pi / 2, math.pi / 2);
      _paintTop(canvas, 0, 2 * math.pi);
      return;
    }

    final w0 = _wedgeCenter - _wedgeWidth / 2 + rotation;
    final w1 = _wedgeCenter + _wedgeWidth / 2 + rotation;

    // Kesim yuzlari: normali tomoshabinga qaraganlari ko'rinadi.
    // w0 yuzining normali +dp/dt = (cos, −sin), w1 niki — teskarisi.
    if (math.sin(w0) < 0) _paintCutFace(canvas, w0, math.cos(w0));
    if (math.sin(w1) > 0) _paintCutFace(canvas, w1, -math.cos(w1));

    // Oldingi yarim aylana (−π/2 … π/2) dan kesilgan bo'lak olib tashlanadi.
    for (final (s, e) in _frontArcs(w0, _wedgeWidth, inside: false)) {
      _paintWall(canvas, s, e);
    }

    _paintTop(canvas, w1, w0 + 2 * math.pi);
  }

  // Tortning bitta bo'lagi: [s0, s1] sektori. Kesim yuzlarining normali
  // bu yerda TASHQARIGA qaraydi: s0 da −dp/dt, s1 da +dp/dt.
  void _paintSlice(Canvas canvas, double midX, double bottom) {
    final c = _sliceCenter + rotation;
    final s0 = c - _wedgeWidth / 2, s1 = c + _wedgeWidth / 2;
    // Bo'lak og'irlik markazi o'qdan ~r/2 da — uni patnis o'rtasiga suramiz.
    _cx = midX - _r * 0.5 * math.sin(c);
    _top = bottom - _h - _r * 0.5 * tilt * math.cos(c);

    // Tagidagi soya — bo'lak izi bo'ylab.
    final foot = Path()
      ..addPolygon([
        Offset(_cx, _top + _h),
        for (var i = 0; i <= 16; i++)
          _rim(s0 + (s1 - s0) * i / 16, _top + _h),
      ], true);
    canvas.drawPath(
      foot.shift(Offset(0, _h * 0.05)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    void faces() {
      if (math.sin(s0) > 0) _paintCutFace(canvas, s0, -math.cos(s0));
      if (math.sin(s1) < 0) _paintCutFace(canvas, s1, math.cos(s1));
    }

    void wall() {
      for (final (s, e) in _frontArcs(s0, _wedgeWidth, inside: true)) {
        _paintWall(canvas, s, e);
      }
    }

    // Yoyi oldinda bo'lsa devor yuzlarni to'sadi, orqada bo'lsa — aksincha.
    if (math.cos(c) > 0) {
      faces();
      wall();
    } else {
      wall();
      faces();
    }
    _paintTop(canvas, s0, s1);
  }

  // Oldingi yarim aylananing (−π/2 … π/2) [from, from + width] sektoriga
  // tushgan ([inside]) yoki undan tashqaridagi qismlari.
  static List<(double, double)> _frontArcs(double from, double width,
      {required bool inside}) {
    const lo = -math.pi / 2, hi = math.pi / 2;
    var out = <(double, double)>[if (!inside) (lo, hi)];
    for (final shift in [-2 * math.pi, 0.0, 2 * math.pi]) {
      final a = _norm(from) + shift, b = a + width;
      if (inside) {
        out.add((math.max(lo, a), math.min(hi, b)));
      } else {
        out = [
          for (final (s, e) in out) ...[
            if (a > s) (s, math.min(e, a)),
            if (b < e) (math.max(s, b), e),
          ],
        ];
      }
    }
    return out.where((w) => w.$2 - w.$1 > 1e-4).toList();
  }

  // Burchakni (−π, π] oralig'iga keltirish.
  static double _norm(double t) {
    var a = t % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    if (a <= -math.pi) a += 2 * math.pi;
    return a;
  }

  // [k]-nachinka qatlamining yo'llari: (rang, boshi, oxiri) — [from..to]
  // oralig'ida tepadan pastga, ulushlariga mutanosib.
  List<(Color, double, double)> _stripes(int k, double from, double to) {
    final bands = fillings?[k] ?? look.bandsOf(k);
    final total = bands.fold<double>(0, (s, b) => s + b.part);
    final out = <(Color, double, double)>[];
    var y = from;
    for (final b in bands) {
      final next = y + (to - from) * b.part / total;
      out.add((b.color, y, next));
      y = next;
    }
    return out;
  }

  // Nachinka va biskvit orasidagi chegara chizig'i — nachinkaning to'qroq
  // tusi: och (qaymoq) nachinka ham biskvitga «qo'shilib» ketmaydi.
  static Color _edgeOf(Color fill) =>
      Color.lerp(fill, Colors.black, 0.32)!.withValues(alpha: 0.85);

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
    var fillIdx = 0;
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
        // Nachinka — TOZA rangda (oqartiruvchi gradientsiz), biskvitdan
        // aniq chegara chiziqlari bilan ajratilgan.
        // Fotodan olingan bo'lsa qatlam bir necha yo'ldan iborat (krem –
        // jele – krem).
        final stripes = _stripes(fillIdx++, y0, y1);
        for (final (color, a, b) in stripes) {
          canvas.drawPath(
            Path()
              ..addPolygon([
                axis.translate(0, a),
                rim.translate(0, a),
                rim.translate(0, b),
                axis.translate(0, b),
              ], true),
            Paint()..color = color,
          );
        }
        final w = math.max(1.0, _h * 0.014);
        canvas.drawLine(
          axis.translate(0, y0),
          rim.translate(0, y0),
          Paint()
            ..strokeWidth = w
            ..color = _edgeOf(stripes.first.$1),
        );
        canvas.drawLine(
          axis.translate(0, y1),
          rim.translate(0, y1),
          Paint()
            ..strokeWidth = w
            ..color = _edgeOf(stripes.last.$1),
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
    // Qoplangan tort kesimi (konstruktor): qoplama biskvitni TASHQARIDAN
    // o'rab turgan qatlam bo'lib ko'rinadi — tepada gorizontal, chetda (tort
    // devori tomonda) vertikal.
    final coat = this.coat;
    if (coat != null) {
      final inward = (axis - rim) * _coatPart;
      final paint = Paint()..color = coat;
      canvas.drawPath(
        Path()
          ..addPolygon([
            axis,
            rim,
            rim.translate(0, _h * _coatPart),
            axis.translate(0, _h * _coatPart),
          ], true),
        paint,
      );
      canvas.drawPath(
        Path()
          ..addPolygon([
            rim,
            rim + inward,
            (rim + inward).translate(0, _h),
            rim.translate(0, _h),
          ], true),
        paint,
      );
      // Qoplama va biskvit orasidagi ingichka chegara.
      final edge = Paint()
        ..strokeWidth = math.max(0.8, _h * 0.01)
        ..color = _edgeOf(coat);
      canvas.drawLine(axis.translate(0, _h * _coatPart),
          (rim + inward).translate(0, _h * _coatPart), edge);
      canvas.drawLine((rim + inward).translate(0, _h * _coatPart),
          (rim + inward).translate(0, _h), edge);
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
    final coat = this.coat;
    if (coat != null) {
      _paintCoatedWall(canvas, whole, coat);
      canvas.restore();
      return;
    }
    var f = 0.0;
    var fillIdx = 0;
    for (final (part, isFilling) in _layers) {
      final band = Path()
        ..addPolygon([
          ...arc(_top + f * _h),
          ...arc(_top + (f + part) * _h).reversed,
        ], true);
      if (isFilling) {
        final stripes =
            _stripes(fillIdx++, _top + f * _h, _top + (f + part) * _h);
        for (final (color, a, b) in stripes) {
          canvas.drawPath(
            Path()..addPolygon([...arc(a), ...arc(b).reversed], true),
            Paint()..color = color,
          );
        }
        // Biskvit bilan aniq chegara (yuqori va pastki yoy bo'ylab).
        Paint edge(Color c) => Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, _h * 0.014)
          ..color = _edgeOf(c);
        canvas.drawPath(
          Path()..addPolygon(arc(_top + f * _h), false),
          edge(stripes.first.$1),
        );
        canvas.drawPath(
          Path()..addPolygon(arc(_top + (f + part) * _h), false),
          edge(stripes.last.$1),
        );
      } else {
        canvas.drawPath(band, Paint()..color = _sponge.sponge);
      }
      f += part;
    }
    // Biskvit qatlamlaridagi g'ovaklar — tort bilan birga aylanadi.
    final rnd = math.Random(3);
    final pore = Paint()..color = _sponge.pore.withValues(alpha: 0.55);
    for (var i = 0; i < 220; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final layer = rnd.nextInt(_fillCount + 1) * 2; // juft — korjlar
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

  // Qoplangan tort devori: qatlamlar ko'rinmaydi — butun devor bir tekis
  // qoplama rangida va SILLIQ (chiziqsiz) — hajmni faqat soya beradi.
  void _paintCoatedWall(Canvas canvas, Path whole, Color coat) {
    // Devor SILLIQ — hech qanday chiziq/izsiz, faqat hajm soyasi.
    canvas.drawPath(whole, Paint()..color = coat);
    // Tayyor tort fotosi — yon devorga o'raladi (butun tortda).
    final photo = sidePhoto;
    if (photo != null && !coatCut) {
      _textureRound(canvas, photo, _r, _top, _top + _h, _h);
    }
    final bottomOval = Rect.fromCenter(
      center: Offset(_cx, _top + _h),
      width: _r * 2,
      height: _r * 2 * tilt,
    );
    // Pastki chetdagi yengil soya (tort patnisga tegib turgan joy).
    canvas.drawArc(
      bottomOval,
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _h * 0.05
        ..color = Colors.black.withValues(alpha: 0.12),
    );
    // Silindr hajm soyasi.
    canvas.drawRect(
      Rect.fromLTRB(_cx - _r, _top - _r * tilt, _cx + _r,
          _top + _h + _r * tilt),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.3, 0.42, 0.62, 1],
        ).createShader(bottomOval),
    );
  }

  // Tepa — pishgan biskvit qobig'i (qoplangan tortda — qoplama), kesilgan
  // bo'laksiz sektor [from, to].
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
    final coat = this.coat;
    if (coat != null) {
      canvas.drawPath(
        sector,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.3),
            radius: 0.9,
            colors: [
              Color.lerp(coat, Colors.white, 0.28)!,
              coat,
              Color.lerp(coat, Colors.black, 0.10)!,
            ],
            stops: const [0, 0.6, 1],
          ).createShader(topOval),
      );
      final photo = sidePhoto;
      if (photo != null && !coatCut) {
        _textureTop(canvas, photo, sector, topOval);
      }
      // Tepa chetidagi yumaloqlangan qirra — ochroq hoshiya.
      canvas.drawPath(
        Path()..addPolygon(arc, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, _h * 0.03)
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(coat, Colors.white, 0.35)!,
      );
      canvas.drawPath(
        Path()..addPolygon(arc, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _edgeOf(coat).withValues(alpha: 0.35),
      );
      return;
    }
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

  // Fotodan yon tomonga tushadigan qism: o'rtadagi gorizontal tasma,
  // nisbati yuzaning o'ziniki ([aspect] = uzunlik / balandlik) — rasm
  // cho'zilib/ezilib ketmaydi (BoxFit.cover kabi). BiscuitPainter bilan bir xil.
  static Rect _photoBand(ui.Image img, double aspect) {
    final w = img.width.toDouble(), hgt = img.height.toDouble();
    final bandH = math.min(hgt, w / math.max(aspect, 0.01));
    final bandW = math.min(w, bandH * aspect);
    return Rect.fromCenter(
        center: Offset(w / 2, hgt / 2), width: bandW, height: bandH);
  }

  // Qoplangan tort yon devoriga fotoni «o'rash»: old yarim aylana ingichka
  // vertikal bo'laklarga bo'linadi, har biriga tasmaning mos qismi chiziladi.
  // Tasma yarim aylanaga teng; ikkinchi yarmida ko'zgu (chok ko'rinmasin).
  // Tort burilganda foto ham birga buriladi (BiscuitPainter._textureRound).
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
        canvas.save();
        canvas.translate(dst.center.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-dst.center.dx, 0);
        canvas.drawImageRect(img, src, dst, paint);
        canvas.restore();
      }
    }
  }

  // Tepaga fotoning MARKAZIY doirasi: doira ellipsga (tilt) ezilib, tort
  // bilan birga buriladi; ustidan yengil hajm soyasi (qirra yorug', chet
  // to'qroq) — tepa yassi rasm emas, qavariq ko'rinadi.
  void _textureTop(Canvas canvas, ui.Image img, Path sector, Rect topOval) {
    final side = math.min(img.width, img.height).toDouble();
    final src = Rect.fromCenter(
      center: Offset(img.width / 2, img.height / 2),
      width: side,
      height: side,
    );
    canvas.save();
    canvas.clipPath(sector);
    canvas.translate(_cx, _top);
    canvas.scale(1, tilt);
    // Chekkadagi nuqta a burchakda ekranda a + rotation'da turadi (_rim) —
    // rasm shunga mos buriladi.
    canvas.rotate(-rotation);
    canvas.drawImageRect(
      img,
      src,
      Rect.fromCircle(center: Offset.zero, radius: _r),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    canvas.drawPath(
      sector,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.14),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(topOval),
    );
  }

  @override
  bool shouldRepaint(FillingCakePainter old) =>
      old.look != look ||
      old.coat != coat ||
      old.coatCut != coatCut ||
      old.sponge != sponge ||
      old.dims != dims ||
      !_sameFillings(old.fillings, fillings) ||
      old.sidePhoto != sidePhoto ||
      old.slice != slice ||
      old.tilt != tilt ||
      old.rotation != rotation;
}
