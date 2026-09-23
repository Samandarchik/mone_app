// shef/ui/widgets/cake_photo_3d.dart — TORTNING ASOSIY FOTOSIDAN 3D model
// (CakePhoto3DView): tort konstruktori 3-qadami («Tort»,
// shef_cake_constructor_page.dart) fotosi bor tort uchun shu ko'rinishni
// ko'rsatadi. Kutubxona YO'Q — hammasi dart:ui bilan: Canvas.drawVertices +
// ImageShader (GPU'da tekstura qo'yilgan uchburchaklar, web'da ham ishlaydi).
//
// PRINSIP — FOTONI O'ZGARTIRMASLIK. Modelga hech narsa «o'ylab» qo'shilmaydi:
//   1. Segmentatsiya (analyzeCakePhoto): fon rangi rasm chetidan olinadi,
//      chetdan «suzib» fon belgilanadi, qolgan eng katta bo'lak — tort.
//   2. Geometriya SILUETDAN: har qatorda tortning yarim kengligi → balandlik
//      bo'yicha radius profili (proporsiya, yaruslar/pog'onalar o'z-o'zidan
//      chiqadi — «hamma tort bir xil shakl» EMAS). Tepa konturi ellips
//      shaklidan kamera balandligi (sinE) va yumaloq/kvadrat shakli
//      aniqlanadi.
//   3. Tekstura — FOTONING O'ZI: har mesh nuqtasi o'sha kamera modeli bilan
//      fotoga proyeksiya qilinadi (u = cx + x·a, v = ysil(h) + z·a·sinE).
//      Ranglar, dekor, yozuvlar, faktura — fotodagidek. Fotoda KO'RINMAYDIGAN
//      orqa tomon uchun ko'rinadigan (old) tomon ko'zgu qilinadi — bu eng kam
//      «o'ylab topish». Tepa yuzasining orqa yarmi fotoda bor (ellipsning
//      yuqori qismi) — u ko'zgusiz olinadi.
//   4. Aylantirish — barmoq/sichqoncha: yon tomonga — atrofida (360°),
//      tepa/past — qarash burchagi (yondan ↔ tepadan); pinch / g'ildirak —
//      masshtab. Mesh BIR MARTA quriladi, har kadrda faqat buriladi va
//      chuqurlik bo'yicha saralanadi — burchak o'zgarganda detallar yo'qolmaydi
//      va qayta «chizilmaydi». Yorug'lik juda yumshoq (0.8–1.0), rang
//      o'zgarmasin deb.
// Chegara: bitta fotodan haqiqiy orqa tomon va dekorning hajmiy geometriyasi
// tiklanmaydi (bu neyro-rekonstruksiya servisi talab qiladi) — dekor tekstura
// sifatida yuzada saqlanadi. Fon murakkab bo'lsa (tort fon bilan bir rangda,
// tort rasm chetiga tegib turibdi) segmentatsiya butun rasmni tort deb oladi.
// Model URL bo'yicha keshlanadi (CakePhotoModel.load) — tortlar almashganda
// tez. Foto yuklanmasa — xato va «Qayta urinish»; UMUMIY model ATAYLAB yo'q:
// bu ko'rinish har doim aynan shu tortning fotosidan (tort A → foto A →
// model A). Fotosiz tort — chaqiruvchi (konstruktor) o'zi hal qiladi.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

const Color _heroTop = Color(0xFFFFFFFF);
const Color _heroBottom = Color(0xFFE6DDF3);
const Color _accentColor = Color(0xFFC5A97B);

// ---------------------------------------------------------------------------
// 1. FOTO TAHLILI — siluetdan shakl
// ---------------------------------------------------------------------------

/// Fotodan olingan tort shakli (o'lchamlar tahlil rasmi pikselida).
class CakePhotoShape {
  /// Tepa konturi ellips emas, tekis — kvadrat (superellips kesim).
  final bool square;

  /// Kamera balandligi sinusi: 0 — yondan, 1 — tepadan (ellips b/a).
  final double sinE;

  /// Tort balandligi / radiusi (dunyo birligida, radius = 1).
  final double heightRatio;

  /// Radius profili pastdan tepaga, radius birligida (≤ ~1): (h, r) —
  /// h ∈ [0, 1]. Bir xil h'li ikki nuqta — pog'ona (yarus chegarasi).
  final List<(double, double)> profile;

  /// Tekstura xaritalash (tahlil rasmi pikselida): markaz ustuni, yarim
  /// kenglik, tepa gardishi qatori (chetda), past gardishi qatori (chetda).
  final double cx;
  final double a;
  final double yTop;
  final double yBottom;

  /// Tahlil rasmining o'lchami — teksturaga (to'liq rasm) ko'paytirish uchun.
  final int imageW;
  final int imageH;

  const CakePhotoShape({
    required this.square,
    required this.sinE,
    required this.heightRatio,
    required this.profile,
    required this.cx,
    required this.a,
    required this.yTop,
    required this.yBottom,
    required this.imageW,
    required this.imageH,
  });

  /// Pog'onalar (yaruslar) soni — profildagi keskin o'zgarishlar.
  int get tiers {
    var n = 1;
    for (var i = 1; i < profile.length; i++) {
      if (profile[i].$1 == profile[i - 1].$1) n++;
    }
    return n;
  }
}

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// RGBA piksellardan tort shaklini aniqlaydi. Tahlil uchun rasm kichik
/// (≈256 px) bo'lgani ma'qul — BFS va profil uchun yetarli va tez.
/// Hech qachon null qaytarmaydi: segmentatsiya ishonchsiz bo'lsa butun rasm
/// tort deb olinadi (foto baribir ko'rsatiladi).
CakePhotoShape analyzeCakePhoto(Uint8List px, int w, int h) {
  final n = w * h;
  // --- FON MODELI: fon bir rang emas — silliq gradient bo'lishi mumkin
  // (studiya foni, yorug'lik tushishi). Har chet uchun rang: tepa/past qator
  // ustun bo'yicha, chap/o'ng ustun qator bo'yicha (9 px oynada o'rtacha);
  // piksel uchun fon — to'rt chetning bilinear aralashmasi. Shunda OQ KREM
  // oq-lavanda fondan ham ajraladi: chegara mahalliy fonga nisbatan tor.
  // Tort rasm chetiga tegib tursa (masalan pastki gardish kadrdan chiqqan)
  // o'sha chet qismi fon emas — chetning medianasidan 25 dan ko'p farq
  // qilgan joylar mediana bilan almashtiriladi (silliq gradient qoladi).
  Float32List edgeColors(int count, int Function(int) index) {
    final out = Float32List(count * 3);
    final med = [<double>[], <double>[], <double>[]];
    for (var k = 0; k < count; k++) {
      double r = 0, g = 0, b = 0, m = 0;
      for (var d = -4; d <= 4; d++) {
        final kk = k + d;
        if (kk < 0 || kk >= count) continue;
        final i = index(kk) * 4;
        if (px[i + 3] < 40) continue; // shaffof chet — hisobga olinmaydi
        r += px[i];
        g += px[i + 1];
        b += px[i + 2];
        m++;
      }
      out[k * 3] = m == 0 ? 255 : r / m;
      out[k * 3 + 1] = m == 0 ? 255 : g / m;
      out[k * 3 + 2] = m == 0 ? 255 : b / m;
      for (var c = 0; c < 3; c++) {
        med[c].add(out[k * 3 + c]);
      }
    }
    final mr = _median(med[0]), mg = _median(med[1]), mb = _median(med[2]);
    for (var k = 0; k < count; k++) {
      final dr = out[k * 3] - mr, dg = out[k * 3 + 1] - mg, db = out[k * 3 + 2] - mb;
      if (dr * dr + dg * dg + db * db > 25 * 25) {
        out[k * 3] = mr;
        out[k * 3 + 1] = mg;
        out[k * 3 + 2] = mb;
      }
    }
    return out;
  }

  final topC = edgeColors(w, (x) => x);
  final botC = edgeColors(w, (x) => (h - 1) * w + x);
  final leftC = edgeColors(h, (y) => y * w);
  final rightC = edgeColors(h, (y) => y * w + w - 1);
  // Modeldan og'ish (rang masofasi) — piksel (x, y) uchun.
  double bgDist(int x, int y) {
    final o = (y * w + x) * 4;
    final tx = w > 1 ? x / (w - 1) : 0.0, ty = h > 1 ? y / (h - 1) : 0.0;
    var d2 = 0.0;
    for (var c = 0; c < 3; c++) {
      final hz = leftC[y * 3 + c] * (1 - tx) + rightC[y * 3 + c] * tx;
      final vt = topC[x * 3 + c] * (1 - ty) + botC[x * 3 + c] * ty;
      final e = px[o + c] - (hz + vt) / 2;
      d2 += e * e;
    }
    return math.sqrt(d2);
  }

  // Chegara — fonning O'Z shovqinidan: chetdan 2 px ichkaridagi halqaning
  // modeldan og'ishi (90-persentil): chegara = 6 + 2·p90, [8, 30].
  // Toza fon → ~8–10, ya'ni oq fondagi oq krem (og'ish 15–30) tort bo'ladi.
  final ring = <double>[];
  if (w > 6 && h > 6) {
    for (var x = 2; x < w - 2; x++) {
      ring.add(bgDist(x, 2));
      ring.add(bgDist(x, h - 3));
    }
    for (var y = 3; y < h - 3; y++) {
      ring.add(bgDist(2, y));
      ring.add(bgDist(w - 3, y));
    }
  }
  var threshold = 8.0;
  if (ring.isNotEmpty) {
    ring.sort();
    final p90 = ring[(ring.length * 0.9).floor().clamp(0, ring.length - 1)];
    threshold = (6 + 2 * p90).clamp(8.0, 30.0);
  }
  final bgLike = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (px[i * 4 + 3] < 40 || bgDist(x, y) <= threshold) bgLike[i] = 1;
    }
  }

  // --- chetdan suzib fonni belgilash (tort ichidagi fon rangli joylar
  // fon bo'lmaydi — teshik qolmaydi) ------------------------------------
  final label = Int32List(n); // 0 — hali yo'q, -1 — fon, k>0 — bo'lak
  final queue = Int32List(n);
  var qh = 0, qt = 0;
  void seed(int i) {
    if (label[i] == 0 && bgLike[i] == 1) {
      label[i] = -1;
      queue[qt++] = i;
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (qh < qt) {
    final i = queue[qh++];
    final x = i % w, y = i ~/ w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (y > 0) seed(i - w);
    if (y < h - 1) seed(i + w);
  }

  // --- old plan bo'laklari: eng kattasi — tort ---------------------------
  var best = 0, bestSize = 0;
  var comp = 0;
  for (var s = 0; s < n; s++) {
    if (label[s] != 0) continue;
    comp++;
    var size = 0;
    qh = 0;
    qt = 0;
    label[s] = comp;
    queue[qt++] = s;
    while (qh < qt) {
      final i = queue[qh++];
      size++;
      final x = i % w, y = i ~/ w;
      void grow(int j) {
        if (label[j] == 0) {
          label[j] = comp;
          queue[qt++] = j;
        }
      }

      if (x > 0) grow(i - 1);
      if (x < w - 1) grow(i + 1);
      if (y > 0) grow(i - w);
      if (y < h - 1) grow(i + w);
    }
    if (size > bestSize) {
      bestSize = size;
      best = comp;
    }
  }

  // Bo'lak juda kichik (fon aniqlanmadi / tort rasm chetiga tegib turibdi) —
  // butun rasm tort.
  final wholeImage = bestSize < n * 0.06;

  // --- ustun/qator konturlari ------------------------------------------
  final topY = List<double>.filled(w, double.nan);
  final botY = List<double>.filled(w, double.nan);
  final left = List<int>.filled(h, -1);
  final right = List<int>.filled(h, -1);
  var x0 = w, x1 = -1, y0 = h, y1 = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inCake = wholeImage || label[y * w + x] == best;
      if (!inCake) continue;
      if (topY[x].isNaN) topY[x] = y.toDouble();
      botY[x] = y.toDouble();
      if (left[y] < 0) left[y] = x;
      right[y] = x;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 - x0 < 4 || y1 - y0 < 4) {
    // Bo'sh/degenerat — standart silindr, butun rasm tekstura.
    return CakePhotoShape(
      square: false,
      sinE: 0.3,
      heightRatio: 0.7,
      profile: const [(0, 1), (1, 1)],
      cx: w / 2,
      a: w / 2,
      yTop: h * 0.25,
      yBottom: h * 0.95,
      imageW: w,
      imageH: h,
    );
  }

  final cx = (x0 + x1) / 2;
  final a = math.max(2.0, (x1 - x0) / 2);

  double halfAt(int y) {
    final yy = y.clamp(0, h - 1);
    if (left[yy] < 0) return 0;
    return (right[yy] - left[yy] + 1) / 2;
  }

  // --- ENG TEPADAGI YARUS va uning gardishi — KENGLIK PROFILIDAN (tepadan
  // pastga): avval yoy (tepa ellipsining orqa yarmi — kenglik o'sadi), so'ng
  // TEKIS joy (yarusning yon tomoni — kenglik o'zgarmaydi). Tepaga chiqib
  // turgan bezak (безе, shariklar, figurkalar) kenglikni deyarli
  // o'zgartirmaydi — bu «osmon chizig'i»ni ellipsga moslashdan ancha
  // barqaror. Tekis joy: keyingi 0.15·a qatorda kenglik ±4% ichida.
  final hw = [for (var y = y0; y <= y1; y++) halfAt(y)];
  final win = math.max(3, (0.15 * a).round());
  var r1 = a;
  var yPlateau = y0;
  for (var k = 0; k + win < hw.length; k++) {
    final w0 = hw[k];
    if (w0 < 0.1 * a) continue;
    var flat = true;
    for (var m = 1; m <= win; m++) {
      if ((hw[k + m] - w0).abs() > 0.04 * w0) {
        flat = false;
        break;
      }
    }
    if (flat) {
      r1 = w0;
      yPlateau = y0 + k;
      break;
    }
  }
  // Gardish qatori (θ = 90°): kenglik birinchi marta r1'ning 95% ga yetgan joy.
  var yCi = yPlateau;
  for (var k = 0; k <= yPlateau - y0; k++) {
    if (hw[k] >= 0.95 * r1) {
      yCi = y0 + k;
      break;
    }
  }

  final cxTop = (left[yPlateau] + right[yPlateau]) / 2;

  // --- kvadrat: 3/4 rakursdan olingan kvadrat tortning tepa konturi ellips
  // emas, «tom» (^): ikki to'g'ri chiziq. Tepa yarus ustunlari bo'yicha
  // ikkala model eng kichik kvadratlar bilan solishtiriladi — «tom» aniq
  // yaxshiroq mos kelsagina kvadrat. Old tomondan olingan kvadrat siluetda
  // silindrdan farq qilmaydi — yumaloq deb olinadi (ko'proq uchraydi).
  var square = false;
  {
    final gEll = <double>[], gRoof = <double>[], ys = <double>[];
    for (var x = (cxTop - r1).ceil(); x <= (cxTop + r1).floor(); x++) {
      if (x < 0 || x >= w || topY[x].isNaN) continue;
      final t = ((x - cxTop) / r1).abs();
      if (t > 0.97) continue;
      gEll.add(math.sqrt(1 - t * t));
      gRoof.add(1 - t);
      ys.add(topY[x]);
    }
    // y = c − b·g uchun (c, b, SSE).
    (double, double, double)? fit(List<double> gs) {
      double n = 0, sg = 0, sgg = 0, sy = 0, sgy = 0;
      for (var i = 0; i < gs.length; i++) {
        n++;
        sg += gs[i];
        sgg += gs[i] * gs[i];
        sy += ys[i];
        sgy += gs[i] * ys[i];
      }
      final det = n * sgg - sg * sg;
      if (n < 6 || det.abs() < 1e-9) return null;
      final bb = (sg * sy - n * sgy) / det;
      final c = (sy + bb * sg) / n;
      var sse = 0.0;
      for (var i = 0; i < gs.length; i++) {
        final d = ys[i] - (c - bb * gs[i]);
        sse += d * d;
      }
      return (c, bb, sse);
    }

    final e = fit(gEll), r = fit(gRoof);
    if (e != null && r != null && r.$2 > 0.05 * r1 && r.$3 < 0.5 * e.$3) {
      square = true;
    }
  }

  // --- gardish qatori (yC) va kamera balandligi (b = r1·sinE) — gardish
  // USTIDAGI yoy qatorlaridan, eng kichik kvadratlar: yumaloq —
  // y = yC − b·√(1 − (w/r1)²); kvadrat («tom») — y = yC − b·(1 − w/r1).
  // Kenglik 0.3–0.97·r1 bo'lgan qatorlar (tepadagi tor bezak tashlanadi).
  var yC = yCi.toDouble();
  var b = 0.0;
  {
    double n = 0, sg = 0, sgg = 0, sy = 0, sgy = 0;
    for (var k = 0; k <= yPlateau - y0; k++) {
      final t = hw[k] / r1;
      if (t < 0.3 || t > 0.97) continue;
      final g = square ? 1 - t : math.sqrt(1 - t * t);
      final y = (y0 + k).toDouble();
      n++;
      sg += g;
      sgg += g * g;
      sy += y;
      sgy += g * y;
    }
    final det = n * sgg - sg * sg;
    if (n >= 3 && det.abs() > 1e-9) {
      b = (sg * sy - n * sgy) / det;
      yC = (sy + b * sg) / n;
    }
  }
  b = b.clamp(0.0, 0.85 * r1);
  // Tekis joy ±4% bilan gardishdan biroz OLDIN boshlanadi — regressiya
  // yC'si undan pastroq bo'lishi tabiiy (oyna chegarasida).
  yC = yC.clamp(y0.toDouble(), (yPlateau + win).toDouble());
  final sinE = (b / r1).clamp(0.06, 0.8);

  // Past gardishi cheti: eng past qator minus past ellipsining old yoyi.
  final rb = halfAt((y1 - a * sinE).round().clamp(y0, y1).toInt());
  var yBot = y1 - rb * sinE;
  if (yBot - yC < 3) yBot = math.min(y1.toDouble(), yC + math.max(3, 0.5 * a));

  // Radius profili: yBot (h=0) → yC (h=1), qator yarim kengligi / a.
  // 3-median filtr — bezak shovqinini oladi, pog'onalarni saqlaydi.
  final rows = <double>[];
  for (var y = yC.round(); y <= yBot.round(); y++) {
    rows.add(halfAt(y) / a);
  }
  if (rows.length < 2) rows.addAll([1, 1]);
  final filtered = List<double>.generate(rows.length, (i) {
    final v = [
      rows[math.max(0, i - 1)],
      rows[i],
      rows[math.min(rows.length - 1, i + 1)],
    ]..sort();
    return v[1].clamp(0.02, 1.0);
  });
  // YARUS CHEGARASI siluetda keskin emas: pastki yarusning tepa gardishi
  // (ellips) siluetni r_tepa'dan r_past'ga r_past·sinE qator davomida
  // «yoy» bilan kengaytiradi. Kengayish uzunligi aynan shu yoyga teng
  // bo'lsa — bu pog'ona (yoy oxirida), qiya (konus) emas: yoy qatorlari
  // tepa radiusiga tenglashtiriladi. Torayish (osilib turgan yarus) — teskari.
  {
    var i = 0;
    while (i < filtered.length - 1) {
      final dir = (filtered[i + 1] - filtered[i]).sign;
      if (dir == 0) {
        i++;
        continue;
      }
      // Yugurish: bir yo'nalishda (o'rtadagi tekis joylar mumkin); oxiri —
      // OXIRGI o'zgargan qator (undan keyingi tekislik yoyga kirmaydi).
      var j = i, end = i, flat = 0;
      while (j < filtered.length - 1 &&
          (filtered[j + 1] - filtered[j]) * dir >= 0) {
        j++;
        if (filtered[j] != filtered[j - 1]) {
          end = j;
          flat = 0;
        } else if (++flat > 3) {
          break; // uzun tekis joy — yarusning yon tomoni, yoy tugadi
        }
      }
      j = end;
      final wA = filtered[i], wB = filtered[j];
      final small = math.min(wA, wB), big = math.max(wA, wB);
      if (big - small > 0.06) {
        final arc = big * a * sinE * math.sqrt(math.max(0.0, 1 - (small / big) * (small / big)));
        if (j - i <= 1.4 * arc + 2) {
          // Kengayish (dir > 0): pog'ona yoy OXIRIDA (j) — oldingi qatorlar
          // tepa radiusida. Torayish (dir < 0): pog'ona yoy BOSHIDA (i).
          if (dir > 0) {
            for (var k = i; k < j; k++) {
              filtered[k] = wA;
            }
          } else {
            for (var k = i + 1; k <= j; k++) {
              filtered[k] = wB;
            }
          }
        }
      }
      i = j;
    }
  }
  final count = filtered.length.clamp(2, 56).toInt();
  final sampled = List<double>.generate(count, (i) {
    final t = i / (count - 1);
    final idx = ((1 - t) * (filtered.length - 1)).round(); // pastdan tepaga
    return filtered[idx];
  });
  // Pog'onalar: keskin sakrash — ikki nuqta bir xil h'da (gorizontal halqa).
  final profile = <(double, double)>[];
  for (var i = 0; i < count; i++) {
    final hh = i / (count - 1);
    if (i > 0 && (sampled[i] - sampled[i - 1]).abs() > 0.06) {
      profile.add((hh, sampled[i - 1]));
    }
    profile.add((hh, sampled[i]));
  }

  final cosE = math.sqrt(math.max(0.0, 1 - sinE * sinE));
  final heightRatio = ((yBot - yC) / a / cosE).clamp(0.08, 6.0);

  return CakePhotoShape(
    square: square,
    sinE: sinE,
    heightRatio: heightRatio,
    profile: profile,
    cx: cx,
    a: a,
    yTop: yC,
    yBottom: yBot,
    imageW: w,
    imageH: h,
  );
}

// ---------------------------------------------------------------------------
// 2. MESH — profildan aylanma jism, tekstura koordinatalari fotoga proyeksiya
// ---------------------------------------------------------------------------

class _Mesh {
  // Har uchburchak uchun 3 ta nuqta: dunyo koordinatalari (radius = 1).
  final Float32List pos; // 9 * tris
  final Float32List nrm; // 3 * tris (yuza normali)
  final Float32List uv; // 6 * tris (to'liq rasm pikselida)
  final int tris;

  _Mesh(this.pos, this.nrm, this.uv, this.tris);
}

const int _segments = 64;

double _superRadius(double theta, double n) {
  final c = math.cos(theta).abs(), s = math.sin(theta).abs();
  return math.pow(math.pow(c, n) + math.pow(s, n), -1 / n).toDouble();
}

_Mesh _buildMesh(CakePhotoShape s, int texW, int texH) {
  final scaleU = texW / s.imageW, scaleV = texH / s.imageH;
  final hWorld = s.heightRatio;
  final prof = s.profile;

  // Nuqta va uning tekstura koordinatasi. [mirrorBack] — orqa (z<0) tomon
  // uchun old tomon ko'zgusi; tepa yuzasi uchun false (fotoda bor).
  final pos = <double>[], uvs = <double>[];
  void vertex(double x, double y, double z, bool mirrorBack) {
    pos.addAll([x, y, z]);
    final zz = mirrorBack ? z.abs() : z;
    final hh = (y / hWorld).clamp(0.0, 1.0);
    final ySil = s.yBottom + (s.yTop - s.yBottom) * hh;
    // Siluet chetidan 2.5% ichkarida — kontur pikseli fon bilan aralashgan,
    // yon tomonda (θ≈90°) u keng polosa bo'lib cho'zilib ketmasin.
    final u = (s.cx + x.clamp(-0.975, 0.975) * s.a) * scaleU;
    final v = (ySil + zz * s.a * s.sinE) * scaleV;
    uvs.addAll([u, v]);
  }

  // Ko'ndalang kesim: yumaloq (1) yoki yumshoq kvadrat (superellips n=6).
  // Kvadrat 3/4 rakursdan aniqlangan — fotoda burchak kameraga qaragan,
  // shuning uchun kesim 45° burilgan va burchak radiusi = siluet yarim
  // kengligi (1).
  final corner = _superRadius(math.pi / 4, 6);
  final ring = List<double>.generate(
    _segments,
    (j) => s.square
        ? _superRadius(2 * math.pi * j / _segments + math.pi / 4, 6) / corner
        : 1.0,
  );
  double sx(int j) => math.sin(2 * math.pi * j / _segments) * ring[j];
  double sz(int j) => math.cos(2 * math.pi * j / _segments) * ring[j];

  void tri(
    double x0, double y0, double z0,
    double x1, double y1, double z1,
    double x2, double y2, double z2,
    bool mirror,
  ) {
    vertex(x0, y0, z0, mirror);
    vertex(x1, y1, z1, mirror);
    vertex(x2, y2, z2, mirror);
  }

  // Yon sirt (va pog'ona halqalari): profil nuqtalari orasidagi kvadlar.
  for (var k = 0; k + 1 < prof.length; k++) {
    final (h0, r0) = prof[k];
    final (h1, r1) = prof[k + 1];
    if (h0 == h1 && (r0 - r1).abs() < 1e-6) continue;
    final y0 = h0 * hWorld, y1 = h1 * hWorld;
    for (var j = 0; j < _segments; j++) {
      final j1 = (j + 1) % _segments;
      final ax = r0 * sx(j), az = r0 * sz(j);
      final bx = r0 * sx(j1), bz = r0 * sz(j1);
      final cx = r1 * sx(j1), cz = r1 * sz(j1);
      final dx = r1 * sx(j), dz = r1 * sz(j);
      tri(ax, y0, az, bx, y0, bz, cx, y1, cz, true);
      tri(ax, y0, az, cx, y1, cz, dx, y1, dz, true);
    }
  }

  // Qopqoqlar: bir necha konsentrik halqa (tekstura aniqroq tarqalsin).
  void cap(double y, double r, bool top) {
    const rings = 4;
    for (var k = 0; k < rings; k++) {
      final ri = r * k / rings, ro = r * (k + 1) / rings;
      for (var j = 0; j < _segments; j++) {
        final j1 = (j + 1) % _segments;
        final ax = ri * sx(j), az = ri * sz(j);
        final bx = ri * sx(j1), bz = ri * sz(j1);
        final cx = ro * sx(j1), cz = ro * sz(j1);
        final dx = ro * sx(j), dz = ro * sz(j);
        // Tepa: normal yuqoriga (θ o'sishi × radius o'sishi); past — teskari.
        if (top) {
          tri(ax, y, az, cx, y, cz, bx, y, bz, false);
          if (k > 0) tri(ax, y, az, dx, y, dz, cx, y, cz, false);
        } else {
          tri(ax, y, az, bx, y, bz, cx, y, cz, true);
          if (k > 0) tri(ax, y, az, cx, y, cz, dx, y, dz, true);
        }
      }
    }
  }

  cap(prof.last.$1 * hWorld, prof.last.$2, true);
  cap(prof.first.$1 * hWorld, prof.first.$2, false);

  final tris = pos.length ~/ 9;
  final nrm = Float32List(tris * 3);
  for (var t = 0; t < tris; t++) {
    final o = t * 9;
    final ux = pos[o + 3] - pos[o], uy = pos[o + 4] - pos[o + 1], uz = pos[o + 5] - pos[o + 2];
    final vx = pos[o + 6] - pos[o], vy = pos[o + 7] - pos[o + 1], vz = pos[o + 8] - pos[o + 2];
    var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 1e-9) {
      nx /= len;
      ny /= len;
      nz /= len;
    }
    nrm[t * 3] = nx;
    nrm[t * 3 + 1] = ny;
    nrm[t * 3 + 2] = nz;
  }
  return _Mesh(Float32List.fromList(pos), nrm, Float32List.fromList(uvs), tris);
}

// ---------------------------------------------------------------------------
// 3. MODEL — rasm + shakl + mesh, URL bo'yicha kesh
// ---------------------------------------------------------------------------

/// Tayyor model: to'liq rasm (tekstura), shakl va mesh.
class CakePhotoModel {
  final ui.Image image;
  final CakePhotoShape shape;
  final _Mesh _mesh;

  CakePhotoModel._(this.image, this.shape, this._mesh);

  /// Rasmdan model (tahlil ≈256 px nusxada, tekstura — rasmning o'zi).
  static Future<CakePhotoModel> fromImage(ui.Image image) async {
    final scale = math.min(1.0, 256 / image.width);
    final w = math.max(8, (image.width * scale).round());
    final h = math.max(8, (image.height * scale).round());
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await rec.endRecording().toImage(w, h);
    final bytes = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    CakePhotoShape shape;
    try {
      shape = analyzeCakePhoto(bytes!.buffer.asUint8List(), w, h);
    } catch (e, st) {
      // Tahlil xatosi — baribir SHU tortning fotosi silindrga qo'yiladi
      // (umumiy model emas), xato logda.
      debugPrint('CakePhotoModel: tahlil xatosi, butun rasm silindr: $e\n$st');
      shape = CakePhotoShape(
        square: false,
        sinE: 0.3,
        heightRatio: 0.7,
        profile: const [(0, 1), (1, 1)],
        cx: w / 2,
        a: w / 2,
        yTop: h * 0.25,
        yBottom: h * 0.95,
        imageW: w,
        imageH: h,
      );
    }
    return CakePhotoModel._(image, shape, _buildMesh(shape, image.width, image.height));
  }

  // Testlar uchun: URL → rasm yuklovchini almashtirish.
  @visibleForTesting
  static Future<ui.Image> Function(BuildContext context, String url)? loader;

  static final Map<String, Future<CakePhotoModel>> _cache = {};
  static const int _cacheLimit = 6;

  /// URL bo'yicha model (keshlanadi — tort qayta ochilsa darhol).
  static Future<CakePhotoModel> load(BuildContext context, String url) {
    final cached = _cache[url];
    if (cached != null) return cached;
    final future = (loader ?? _loadImage)(context, url).then(fromImage);
    // Xato — keshda qolmasin (keyingi ochilishda qayta uriniladi). Bu
    // hosila future xatosiz tugaydi — «unhandled» bo'lmaydi.
    future.then((_) {}, onError: (_) {
      _cache.remove(url);
    });
    _cache[url] = future;
    // Eng eskisi tashlanadi (rasm ochiq sahifada ishlatilayotgan bo'lishi
    // mumkin — dispose qilinmaydi, GC o'zi oladi).
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
    return future;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();

  // Tekstura uchun to'liq (1024 px, backend saqlagan) rasm kerak — ekrandagi
  // o'lchamda emas: aylantirilganda / yaqinlashtirilganda detal yo'qolmasin.
  // Shu bois displayWidth = 1024 (appNetworkImageProvider limiti).
  static Future<ui.Image> _loadImage(BuildContext context, String url) {
    final completer = Completer<ui.Image>();
    final stream = appNetworkImageProvider(context, url, displayWidth: 1024)
        .resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image.clone());
        info.dispose();
        stream.removeListener(l);
      },
      onError: (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
        stream.removeListener(l);
      },
    );
    stream.addListener(l);
    return completer.future;
  }
}

// ---------------------------------------------------------------------------
// 4. PAINTER — burish, saralash, drawVertices
// ---------------------------------------------------------------------------

class CakePhotoPainter extends CustomPainter {
  final CakePhotoModel model;
  final double yaw; // atrofida (radian)
  final double pitch; // qarash burchagi: 0 — yondan, π/2 — tepadan
  final double zoom;

  CakePhotoPainter({
    required this.model,
    required this.yaw,
    required this.pitch,
    this.zoom = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mesh = model._mesh;
    final hW = model.shape.heightRatio;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    // Ko'rinish radiusi — tort butunlay sig'sin.
    final bound = math.sqrt(1 + hW * hW / 4) * 1.06;
    final scale = math.min(size.width, size.height) / 2 / bound * 0.92 * zoom;
    final ox = size.width / 2, oy = size.height / 2;
    const dist = 6.0; // perspektiva (radius birligida)

    // Kamera fazosi: avval Y atrofida (yaw), so'ng X atrofida (pitch).
    // Ekran: x o'ngga, y pastga (kamera y'ning teskarisi).
    final n = mesh.tris;
    final depth = Float64List(n);
    final order = List<int>.generate(n, (i) => i);
    final cam = Float32List(n * 9);
    final shade = Float32List(n);
    const lx = -0.35, ly = 0.8, lz = 0.55; // yorug'lik — tepa-chap-old
    final pos = mesh.pos, nrm = mesh.nrm;
    var visible = 0;
    for (var t = 0; t < n; t++) {
      // Normal — faqat burish.
      final nx0 = nrm[t * 3], ny0 = nrm[t * 3 + 1], nz0 = nrm[t * 3 + 2];
      final nx1 = nx0 * cy + nz0 * sy, nz1 = -nx0 * sy + nz0 * cy;
      final ny2 = ny0 * cp - nz1 * sp, nz2 = ny0 * sp + nz1 * cp;
      if (nz2 <= 0) {
        depth[t] = double.negativeInfinity; // orqa yuza — chizilmaydi
        continue;
      }
      visible++;
      final dot = nx1 * lx + ny2 * ly + nz2 * lz;
      shade[t] = 0.8 + 0.2 * dot.clamp(0.0, 1.0);
      var zsum = 0.0;
      for (var k = 0; k < 3; k++) {
        final o = t * 9 + k * 3;
        final x = pos[o], y = pos[o + 1] - hW / 2, z = pos[o + 2];
        final x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
        final y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
        cam[o] = x1;
        cam[o + 1] = y2;
        cam[o + 2] = z2;
        zsum += z2;
      }
      depth[t] = zsum;
    }
    if (visible == 0) return;
    // Uzoqdan yaqinga (rassom algoritmi).
    order.sort((p, q) => depth[p].compareTo(depth[q]));

    // Yerdagi yumshoq soya — tort emas, faqat «turgan joyi» hissi.
    if (pitch > 0.02) {
      final shadowR = scale * 1.05;
      final syFloor = -(-hW / 2) * cp; // y = 0 tekisligi kamera y'da
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ox, oy + syFloor * scale * (dist / (dist + hW / 2 * sp))),
          width: shadowR * 2,
          height: shadowR * 2 * sp,
        ),
        Paint()
          ..color = const Color(0x2A4A3A5A)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    final positions = Float32List(visible * 6);
    final tex = Float32List(visible * 6);
    final colors = Int32List(visible * 3);
    var vi = 0;
    for (var i = n - visible; i < n; i++) {
      final t = order[i];
      final g = (255 * shade[t]).round().clamp(0, 255);
      final color = 0xFF000000 | (g << 16) | (g << 8) | g;
      for (var k = 0; k < 3; k++) {
        final o = t * 9 + k * 3;
        final persp = dist / (dist - cam[o + 2]);
        positions[vi * 2] = ox + cam[o] * scale * persp;
        positions[vi * 2 + 1] = oy - cam[o + 1] * scale * persp;
        tex[vi * 2] = mesh.uv[(t * 3 + k) * 2];
        tex[vi * 2 + 1] = mesh.uv[(t * 3 + k) * 2 + 1];
        colors[vi] = color;
        vi++;
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: tex,
      colors: colors,
    );
    final paint = Paint()
      ..shader = ui.ImageShader(
        model.image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
        filterQuality: FilterQuality.medium,
      );
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(CakePhotoPainter old) =>
      old.model != model ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom;
}

// ---------------------------------------------------------------------------
// 5. WIDGET — yuklash, aylantirish, burchak tugmalari
// ---------------------------------------------------------------------------

/// Fotodan 3D tort. Foto yuklanmasa — xato matni va «Qayta urinish»; boshqa
/// (umumiy) model ATAYLAB ko'rsatilmaydi: 3D har doim SHU tortning fotosidan.
class CakePhoto3DView extends StatefulWidget {
  final String imageUrl;
  final double height;
  final BorderRadius borderRadius;

  const CakePhoto3DView({
    super.key,
    required this.imageUrl,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<CakePhoto3DView> createState() => _CakePhoto3DViewState();
}

// Tez burchaklar: (yozuv, yaw, pitch).
const List<(String, double, double)> _views = [
  ('Old', 0, 0.32),
  ('Yon', math.pi / 2, 0.32),
  ('Orqa', math.pi, 0.32),
  ('Tepa', 0, 1.45),
];

class _CakePhoto3DViewState extends State<CakePhoto3DView>
    with TickerProviderStateMixin {
  CakePhotoModel? _model;
  // Yuklash/tahlil xatosi matni (null — xato yo'q).
  String? _error;
  double _yaw = 0;
  double _pitch = 0.32;
  double _zoom = 1;
  bool _touched = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..addListener(() {
      if (!_touched && mounted) setState(() {});
    });
  // Tugma bosilganda burchakka silliq o'tish.
  AnimationController? _move;
  double _fromYaw = 0, _fromPitch = 0, _toYaw = 0, _toPitch = 0;
  double _startZoom = 1;

  @override
  void initState() {
    super.initState();
    _spin.repeat();
    _load();
  }

  @override
  void didUpdateWidget(CakePhoto3DView old) {
    super.didUpdateWidget(old);
    // Boshqa tort tanlandi — model almashadi.
    if (old.imageUrl != widget.imageUrl) {
      _model = null;
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _move?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = widget.imageUrl;
    try {
      final m = await CakePhotoModel.load(context, url);
      if (!mounted || url != widget.imageUrl) return;
      setState(() => _model = m);
    } catch (e) {
      debugPrint('CakePhoto3DView: $url — $e');
      if (!mounted || url != widget.imageUrl) return;
      setState(() => _error = '$e');
    }
  }

  void _stopAuto() {
    if (_touched) return;
    _touched = true;
    _spin.stop();
    _yaw = _currentYaw;
  }

  double get _currentYaw => _touched ? _yaw : _yaw + _spin.value * 2 * math.pi;

  void _goTo(double yaw, double pitch) {
    _stopAuto();
    _move?.dispose();
    _fromYaw = _yaw;
    _fromPitch = _pitch;
    // Eng qisqa yo'l bilan burish.
    var dy = (yaw - _yaw) % (2 * math.pi);
    if (dy > math.pi) dy -= 2 * math.pi;
    _toYaw = _yaw + dy;
    _toPitch = pitch;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    final curve = CurvedAnimation(parent: c, curve: Curves.easeInOut);
    c.addListener(() {
      if (!mounted) return;
      setState(() {
        _yaw = _fromYaw + (_toYaw - _fromYaw) * curve.value;
        _pitch = _fromPitch + (_toPitch - _fromPitch) * curve.value;
      });
    });
    _move = c..forward();
  }

  // Foto yuklanmadi / model qurilmadi — sabab va qayta urinish. Umumiy
  // model ko'rsatilmaydi.
  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.brown.shade300, size: 30),
            const SizedBox(height: 6),
            const Text(
              '3D model qurilmadi — tort fotosi yuklanmadi',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            Text(
              _error ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Qayta urinish'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: widget.borderRadius,
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_heroTop, _heroBottom],
              ),
            ),
            child: _error != null
                ? _errorView()
                : model == null
                    ? _loading()
                    : _viewer(model),
          ),
        ),
        if (model != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final v in _views)
                ActionChip(
                  label: Text(v.$1, style: const TextStyle(fontSize: 11.5)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade300),
                  onPressed: () => _goTo(v.$2, v.$3),
                ),
              ActionChip(
                avatar: const Icon(Icons.threed_rotation, size: 14),
                label: const Text('360°', style: TextStyle(fontSize: 11.5)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                backgroundColor: Colors.white,
                side: const BorderSide(color: _accentColor),
                onPressed: () => setState(() {
                  _move?.dispose();
                  _move = null;
                  _touched = false;
                  _zoom = 1;
                  _spin.repeat();
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // Yuklanmoqda (foto + tahlil odatda < 1 s) — indikator.
  Widget _loading() {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor),
      ),
    );
  }

  Widget _viewer(CakePhotoModel model) {
    return Listener(
      // Sichqoncha g'ildiragi — masshtab.
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          setState(() {
            _zoom = (_zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.5, 3.0);
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Bitta detektor: surish — burish, ikki barmoq — masshtab.
        onScaleStart: (d) {
          _stopAuto();
          _move?.dispose();
          _move = null;
          _startZoom = _zoom;
        },
        onScaleUpdate: (d) => setState(() {
          _yaw += d.focalPointDelta.dx * 0.012;
          _pitch = (_pitch + d.focalPointDelta.dy * 0.008).clamp(-0.35, 1.5);
          if (d.pointerCount > 1) {
            _zoom = (_startZoom * d.scale).clamp(0.5, 3.0);
          }
        }),
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: CakePhotoPainter(
              model: model,
              yaw: _currentYaw,
              pitch: _pitch,
              zoom: _zoom,
            ),
          ),
        ),
      ),
    );
  }
}
