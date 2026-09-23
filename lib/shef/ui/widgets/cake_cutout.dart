// shef/ui/widgets/cake_cutout.dart — tort fotosidan FONNI OLIB TASHLASH va
// tortning o'ziga QIRQISH (CakeCutout). Natija — shaffof fonli, tort
// chetlarigacha qirqilgan rasm: konstruktorning 3-qadamida tort blok foniga
// «yotqizilgan» holda, kattaroq ko'rinadi.
//
// QANDAY: fon rasm CHETLARIDAN modellashtiriladi (tepa/past qator va
// chap/o'ng ustun ranglari, orasi bilinear aralashtiriladi) — shunda silliq
// gradientli studiya foni ham, bir xil oq fon ham qamrab olinadi. Har piksel
// shu modeldan qancha uzoqligiga qarab baholanadi; chegara fonning O'Z
// shovqinidan olinadi. So'ng fon CHETDAN «suzib» belgilanadi: tortning
// ichidagi fon rangli joylar (oq krem, oq patnis usti) fon bo'lib qolmaydi —
// rasmda teshik ochilmaydi.
//
// Chegara: tort oq patnis ustida tursa, patnis ham fondan ajralib qoladi va
// kesilgan rasmga kiradi — u tortning bir qismi bo'lib ko'rinadi. Bitta
// fotodan patnisni tortdan ajratishning ishonchli yo'li yo'q (ilgari
// urinilgan va tashlangan), shuning uchun patnis ATAYLAB qoldiriladi: uni
// noto'g'ri kesgandan ko'ra qoldirgan afzal.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';

// Tahlil va natija o'lchami: blokda ~235 px balandlikda ko'rsatiladi, 512 px
// yetib ortadi va xotira ham tejaladi.
const int _workSize = 512;

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// Fonni shaffof qilib, tortga qirqilgan rasm. [image] — tayyor natija,
/// [ok] false bo'lsa segmentatsiya ishonchsiz bo'lgan va ASL rasm qaytgan.
class CakeCutout {
  final ui.Image image;
  final bool ok;

  const CakeCutout(this.image, this.ok);

  static final Map<String, Future<CakeCutout>> _cache = {};
  static const int _cacheLimit = 8;

  /// Testlar uchun: URL → rasm yuklovchini almashtirish.
  @visibleForTesting
  static Future<ui.Image> Function(BuildContext context, String url)? loader;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// URL bo'yicha (keshlanadi — tort qayta ochilsa darhol).
  static Future<CakeCutout> load(BuildContext context, String url) {
    final cached = _cache[url];
    if (cached != null) return cached;
    final future = (loader ?? _loadImage)(context, url).then(fromImage);
    future.then((_) {}, onError: (_) {
      _cache.remove(url);
    });
    _cache[url] = future;
    if (_cache.length > _cacheLimit) _cache.remove(_cache.keys.first);
    return future;
  }

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

  /// Rasmdan fonsiz, qirqilgan nusxa. Xato bo'lsa asl rasm qaytadi.
  static Future<CakeCutout> fromImage(ui.Image src) async {
    try {
      final scale = math.min(1.0, _workSize / math.max(src.width, src.height));
      final w = math.max(8, (src.width * scale).round());
      final h = math.max(8, (src.height * scale).round());
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final small = await rec.endRecording().toImage(w, h);
      final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      if (data == null) return CakeCutout(src, false);
      final px = data.buffer.asUint8List();
      final cut = _cutout(px, w, h);
      if (cut == null) return CakeCutout(src, false);
      return CakeCutout(await cut, true);
    } catch (e) {
      debugPrint('CakeCutout: $e');
      return CakeCutout(src, false);
    }
  }
}

// Fonni shaffof qiladi va tortning chegarasiga qirqadi. null — segmentatsiya
// ishonchsiz (deyarli butun rasm yoki juda kichik bo'lak).
Future<ui.Image>? _cutout(Uint8List px, int w, int h) {
  final n = w * h;

  // --- FON MODELI: chetlardan (silliq gradient ham qamrab olinsin).
  Float32List edgeColors(int count, int Function(int) index) {
    final out = Float32List(count * 3);
    final med = [<double>[], <double>[], <double>[]];
    for (var k = 0; k < count; k++) {
      double r = 0, g = 0, b = 0, m = 0;
      for (var d = -4; d <= 4; d++) {
        final kk = k + d;
        if (kk < 0 || kk >= count) continue;
        final i = index(kk) * 4;
        if (px[i + 3] < 40) continue;
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
    // Tort kadr chetiga tegib tursa — o'sha joy fon emas; chetning
    // medianasidan uzoq qiymatlar mediana bilan almashtiriladi.
    final mr = _median(med[0]), mg = _median(med[1]), mb = _median(med[2]);
    for (var k = 0; k < count; k++) {
      final dr = out[k * 3] - mr,
          dg = out[k * 3 + 1] - mg,
          db = out[k * 3 + 2] - mb;
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

  // Chegara — fonning O'Z shovqinidan (chetdan 2 px ichkaridagi halqa).
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

  // --- fon CHETDAN suzib belgilanadi: tort ichidagi oq joylar fon emas.
  final isBg = Uint8List(n);
  final queue = Int32List(n);
  var qh = 0, qt = 0;
  void seed(int i) {
    if (isBg[i] == 0 && bgLike[i] == 1) {
      isBg[i] = 1;
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

  // Old plan chegaralari.
  var x0 = w, x1 = -1, y0 = h, y1 = -1, fg = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (isBg[y * w + x] == 1) continue;
      fg++;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  // Ishonchsiz: fon topilmadi (deyarli butun rasm) yoki bo'lak juda kichik.
  if (fg > n * 0.92 || fg < n * 0.02 || x1 - x0 < 8 || y1 - y0 < 8) return null;

  // Alfa: fon — 0, qolgani — 255; chetini 3×3 o'rtacha bilan yumshatamiz
  // (qaychi bilan qirqilgandek keskin chet qolmasin).
  final alpha = Uint8List(n);
  for (var i = 0; i < n; i++) {
    alpha[i] = isBg[i] == 1 ? 0 : 255;
  }
  final soft = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0, cnt = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final yy = y + dy, xx = x + dx;
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          sum += alpha[yy * w + xx];
          cnt++;
        }
      }
      soft[y * w + x] = (sum / cnt).round();
    }
  }

  // Qirqish: chegaralar + 2% joy.
  final pad = math.max(2, ((x1 - x0 + 1) * 0.02).round());
  final cx0 = math.max(0, x0 - pad), cy0 = math.max(0, y0 - pad);
  final cx1 = math.min(w - 1, x1 + pad), cy1 = math.min(h - 1, y1 + pad);
  final cw = cx1 - cx0 + 1, ch = cy1 - cy0 + 1;

  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final src = ((y + cy0) * w + (x + cx0)) * 4;
      final dst = (y * cw + x) * 4;
      final a = soft[(y + cy0) * w + (x + cx0)];
      // Oldindan ko'paytirilgan alfa EMAS — decodeImageFromPixels rgba8888
      // oddiy (straight) alfani kutadi.
      out[dst] = px[src];
      out[dst + 1] = px[src + 1];
      out[dst + 2] = px[src + 2];
      out[dst + 3] = a;
    }
  }

  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(out, cw, ch, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}
