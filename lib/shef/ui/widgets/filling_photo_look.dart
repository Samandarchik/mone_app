// shef/ui/widgets/filling_photo_look.dart — «П/Ф Начинка» tex kartasidagi
// FOTOdan (masalan kesilgan tort, ichida nachinka) nachinka ko'rinishini
// olish. Foto kichraytirib yuklanadi (~240px). Ikki usul, tartib bilan:
//
// A) QATLAMLAR (_fromLayers) — kesilgan tort fotosi uchun asosiy usul.
//    Kesimda qatlamlar TEPADAN PASTGA ketadi: kadr o'rtasidagi vertikal
//    tasma bo'ylab har qatorning o'rtacha rangi olinadi, biskvit qatorlari
//    (korjlar) topiladi va IKKI KORJ ORASIDAGI hamma narsa nachinka deb
//    olinadi — yo'llari (masalan krem – jele – krem), ranglari va qalinlik
//    nisbati bilan. 1-oraliq → 1-nachinka qatlami, 2-oraliq → 2-si.
//    Fon va rasm maydoni bu yerda ahamiyatsiz: ingichka qizil jele ham
//    (kadrning ~5%) yo'qolmaydi, kulrang fon esa nachinka bo'lib qolmaydi.
// B) RANG GURUHLARI (_fromClusters) — qatlam topilmasa: markaziy piksellar
//    k-means bilan guruhlanadi, fon (chet hoshiyada ko'proq uchraydigan
//    rang) va biskvit rangi tashlanadi, qolgan eng katta 1–2 rang olinadi.
//
// Yo'l rangi «toza» olinadi (_pureOf): chegaradagi aralash qatorlar/
// piksellar tashlanadi, och kremlarda eng oq, jeleda eng to'yingan piksellar.
// Hech narsa topilmasa — null: rang avvalgidek тех карта nomi/tarkibidan
// olinadi (FillingLook.detect).
// Bu RANG tahlili (sun'iy intellekt emas): korj rangi och/oltin deb
// faraz qilinadi — shokoladli biskvit korj deb tanilmaydi (B usuliga o'tadi).
// Natija URL bo'yicha keshlanadi — karta va katta 3D qayta hisoblamaydi.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

// Bitta rang guruhi: o'rtacha rang va markaz/hoshiyadagi ulushi.
class _Cluster {
  double r, g, b;
  int center = 0;
  int border = 0;
  // Markazdagi shu guruhga tushgan piksellar (RGBA ofsetlari) — «toza»
  // rangni hisoblash uchun.
  final List<int> members = [];

  _Cluster(this.r, this.g, this.b);

  double dist(double pr, double pg, double pb) {
    final dr = r - pr, dg = g - pg, db = b - pb;
    return dr * dr + dg * dg + db * db;
  }

  Color get color => Color.fromARGB(255, r.round(), g.round(), b.round());
}

class FillingPhotoLook {
  FillingPhotoLook._();

  // URL → natija (null ham keshlanadi: foto tahlil qilingan, rang topilmagan).
  static final Map<String, FillingLook?> _cache = {};

  static bool isCached(String url) => _cache.containsKey(url);
  static FillingLook? cached(String url) => _cache[url];

  static const int _k = 6;
  // Guruhlar shu masofadan (RGB) yaqin bo'lsa — bitta rang deb birlashadi.
  static const double _mergeDist = 45;
  // Ikkinchi nachinka rangi birinchisidan kamida shuncha farq qilsin.
  static const double _distinctDist = 60;

  // Foto piksellaridan (RGBA, w×h) nachinka ko'rinishi; topilmasa null.
  // AVVAL kesim qatlamlari qidiriladi (_fromLayers — kesilgan tort fotosi
  // uchun eng aniq usul); topilmasa — rang guruhlari (_fromClusters).
  static FillingLook? analyze(ByteData rgba, int w, int h) =>
      _fromLayers(rgba, w, h) ?? _fromClusters(rgba, w, h);

  // Biskvit (korj) rangi: och/oltin sariq-jigarrang. Krem undan kam
  // to'yingan (oqish), jele/shokolad — boshqa tus yoki to'q.
  static bool _isSponge(double r, double g, double b) {
    final hsv = HSVColor.fromColor(
        Color.fromARGB(255, r.round(), g.round(), b.round()));
    return hsv.hue >= 25 &&
        hsv.hue <= 55 &&
        hsv.saturation >= 0.18 &&
        hsv.saturation <= 0.8 &&
        hsv.value >= 0.45;
  }

  // Kesilgan tort fotosi: qatlamlar TEPADAN PASTGA ketadi. Vertikal tasma
  // bo'ylab har qatorning o'rtacha rangi olinadi, biskvit qatorlari
  // (korjlar) topiladi — IKKI KORJ ORASIDAGI hamma narsa nachinka: uning
  // yo'llari (masalan krem – jele – krem) rang va qalinlik nisbati bilan
  // olinadi. 1-oraliq → 1-nachinka qatlami, 2-oraliq → 2-si. Tort kadr
  // o'rtasida bo'lmasa — chap/o'ng tasmalar ham sinab ko'riladi.
  static FillingLook? _fromLayers(ByteData rgba, int w, int h) {
    for (final mid in const [0.5, 0.38, 0.62]) {
      final x0 = (w * (mid - 0.12)).floor().clamp(0, w - 1);
      final x1 = (w * (mid + 0.12)).ceil().clamp(x0 + 1, w);
      final look = _layersInStrip(rgba, w, h, x0, x1);
      if (look != null) return look;
    }
    return null;
  }

  static FillingLook? _layersInStrip(
      ByteData rgba, int w, int h, int x0, int x1) {
    final n = x1 - x0;
    final rows = <(double, double, double)>[];
    for (var y = 0; y < h; y++) {
      double r = 0, g = 0, b = 0;
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        r += rgba.getUint8(i);
        g += rgba.getUint8(i + 1);
        b += rgba.getUint8(i + 2);
      }
      rows.add((r / n, g / n, b / n));
    }

    // Biskvit qatorlari; yakka «adashgan» qatorlar 3 qatorlik ko'pchilik
    // ovozi bilan tekislanadi.
    final raw = [for (final (r, g, b) in rows) _isSponge(r, g, b)];
    final sponge = [
      for (var y = 0; y < h; y++)
        ((y > 0 && raw[y - 1]) ? 1 : 0) +
                (raw[y] ? 1 : 0) +
                ((y < h - 1 && raw[y + 1]) ? 1 : 0) >=
            2,
    ];

    // Korjlar: kamida 3% balandlikdagi uzluksiz biskvit qatorlari.
    final minRun = math.max(3, (h * 0.03).round());
    final runs = <(int, int)>[]; // [boshi, oxiri)
    var start = -1;
    for (var y = 0; y <= h; y++) {
      final on = y < h && sponge[y];
      if (on && start < 0) start = y;
      if (!on && start >= 0) {
        if (y - start >= minRun) runs.add((start, y));
        start = -1;
      }
    }
    if (runs.length < 2) return null;

    // Korjlar orasi — nachinka. Juda qalin oraliq (fon, boshqa tort) emas.
    final layers = <List<FillingBand>>[];
    for (var k = 0; k + 1 < runs.length && layers.length < 2; k++) {
      final g0 = runs[k].$2, g1 = runs[k + 1].$1;
      if (g1 - g0 < 2 || g1 - g0 > h * 0.3) continue;
      final bands = _bandsInGap(rgba, w, x0, x1, rows, g0, g1);
      if (bands.isNotEmpty) layers.add(bands);
    }
    if (layers.isEmpty) return null;
    return FillingLook.layered(
        layers[0], layers.length > 1 ? layers[1] : null);
  }

  // [g0, g1) qatorlari (ikki korj orasi) ni rang yo'llariga bo'lish.
  static List<FillingBand> _bandsInGap(ByteData rgba, int w, int x0, int x1,
      List<(double, double, double)> rows, int g0, int g1) {
    double dist((double, double, double) a, (double, double, double) b) {
      final dr = a.$1 - b.$1, dg = a.$2 - b.$2, db = a.$3 - b.$3;
      return math.sqrt(dr * dr + dg * dg + db * db);
    }

    // Ketma-ket o'xshash qatorlar — bitta yo'l: [boshi, oxiri).
    var segs = <(int, int)>[];
    var s = g0;
    for (var y = g0 + 1; y <= g1; y++) {
      if (y == g1 || dist(rows[y], rows[y - 1]) > 34) {
        segs.add((s, y));
        s = y;
      }
    }

    (double, double, double) meanOf((int, int) seg) {
      double r = 0, g = 0, b = 0;
      for (var y = seg.$1; y < seg.$2; y++) {
        r += rows[y].$1;
        g += rows[y].$2;
        b += rows[y].$3;
      }
      final n = seg.$2 - seg.$1;
      return (r / n, g / n, b / n);
    }

    // Juda ingichka yo'llar (ikki rang chegarasidagi ARALASH qatorlar) va
    // o'xshash qo'shnilar birlashtiriladi; ko'pi bilan 3 ta yo'l qoladi.
    final minLen = math.max(1.0, (g1 - g0) * 0.10);
    bool mergeOnce() {
      if (segs.length < 2) return false;
      var pick = -1;
      for (var i = 0; i < segs.length; i++) {
        final len = segs[i].$2 - segs[i].$1;
        if (len >= minLen && segs.length <= 3) continue;
        if (pick < 0 ||
            len < segs[pick].$2 - segs[pick].$1) {
          pick = i;
        }
      }
      if (pick < 0) {
        // O'xshash rangli qo'shnilar.
        for (var i = 0; i + 1 < segs.length; i++) {
          if (dist(meanOf(segs[i]), meanOf(segs[i + 1])) < 34) {
            segs = [
              ...segs.take(i),
              (segs[i].$1, segs[i + 1].$2),
              ...segs.skip(i + 2),
            ];
            return true;
          }
        }
        return false;
      }
      // Ingichka yo'l — rangi yaqinroq qo'shnisiga qo'shiladi.
      final m = meanOf(segs[pick]);
      final left = pick > 0 ? dist(m, meanOf(segs[pick - 1])) : null;
      final right =
          pick + 1 < segs.length ? dist(m, meanOf(segs[pick + 1])) : null;
      final toLeft = right == null || (left != null && left <= right);
      final i = toLeft ? pick - 1 : pick;
      segs = [
        ...segs.take(i),
        (segs[i].$1, segs[i + 1].$2),
        ...segs.skip(i + 2),
      ];
      return true;
    }

    while (mergeOnce()) {}

    // Yo'l rangi faqat ICHKI qatorlardan: chekka qatorlarda qo'shni yo'l
    // bilan aralash tus bo'ladi (krem + jele = xira pushti). Qalinlik
    // (part) esa to'liq yo'ldan.
    return [
      for (final seg in segs)
        () {
          final len = seg.$2 - seg.$1;
          final trim = len >= 5 ? 2 : (len >= 3 ? 1 : 0);
          return FillingBand(
            _pureOf(rgba, [
              for (var y = seg.$1 + trim; y < seg.$2 - trim; y++)
                for (var x = x0; x < x1; x++) (y * w + x) * 4,
            ]),
            len.toDouble(),
          );
        }(),
    ];
  }

  // Rang guruhlari usuli (qatlamlar topilmagan fotolar uchun).
  static FillingLook? _fromClusters(ByteData rgba, int w, int h) {
    // Markaz — o'rtadagi 64%; hoshiya — chetdagi 8% ramka.
    final cx0 = (w * 0.18).floor(), cx1 = (w * 0.82).ceil();
    final cy0 = (h * 0.18).floor(), cy1 = (h * 0.82).ceil();
    final bx = math.max(1, (w * 0.08).round());
    final by = math.max(1, (h * 0.08).round());

    final center = <int>[]; // piksel indekslari (RGBA ofset)
    final border = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        if (rgba.getUint8(i + 3) < 128) continue;
        if (x >= cx0 && x < cx1 && y >= cy0 && y < cy1) {
          center.add(i);
        } else if (x < bx || x >= w - bx || y < by || y >= h - by) {
          border.add(i);
        }
      }
    }
    if (center.length < _k * 4) return null;

    int lum(int i) =>
        rgba.getUint8(i) * 3 + rgba.getUint8(i + 1) * 6 + rgba.getUint8(i + 2);

    // Boshlang'ich markazlar — yorug'lik bo'yicha kvantillar (har doim bir
    // xil natija: tasodif yo'q).
    final sorted = [...center]..sort((a, b) => lum(a).compareTo(lum(b)));
    final clusters = [
      for (var j = 0; j < _k; j++)
        () {
          final i = sorted[((j + 0.5) / _k * sorted.length).floor()];
          return _Cluster(
            rgba.getUint8(i).toDouble(),
            rgba.getUint8(i + 1).toDouble(),
            rgba.getUint8(i + 2).toDouble(),
          );
        }(),
    ];

    int nearest(int i) {
      final pr = rgba.getUint8(i).toDouble();
      final pg = rgba.getUint8(i + 1).toDouble();
      final pb = rgba.getUint8(i + 2).toDouble();
      var best = 0;
      var bestD = double.infinity;
      for (var j = 0; j < clusters.length; j++) {
        final d = clusters[j].dist(pr, pg, pb);
        if (d < bestD) {
          bestD = d;
          best = j;
        }
      }
      return best;
    }

    for (var iter = 0; iter < 8; iter++) {
      final n = List<int>.filled(_k, 0);
      final sr = List<double>.filled(_k, 0);
      final sg = List<double>.filled(_k, 0);
      final sb = List<double>.filled(_k, 0);
      for (final i in center) {
        final j = nearest(i);
        n[j]++;
        sr[j] += rgba.getUint8(i);
        sg[j] += rgba.getUint8(i + 1);
        sb[j] += rgba.getUint8(i + 2);
      }
      for (var j = 0; j < _k; j++) {
        if (n[j] == 0) continue;
        clusters[j]
          ..r = sr[j] / n[j]
          ..g = sg[j] / n[j]
          ..b = sb[j] / n[j];
      }
    }
    for (final i in center) {
      final c = clusters[nearest(i)];
      c.center++;
      c.members.add(i);
    }
    for (final i in border) {
      clusters[nearest(i)].border++;
    }

    // O'xshash guruhlarni birlashtirish (bir rangning och/to'q tusi).
    final merged = <_Cluster>[];
    for (final c in clusters..sort((a, b) => b.center.compareTo(a.center))) {
      if (c.center == 0 && c.border == 0) continue;
      _Cluster? into;
      for (final m in merged) {
        if (math.sqrt(m.dist(c.r, c.g, c.b)) < _mergeDist) {
          into = m;
          break;
        }
      }
      if (into == null) {
        merged.add(c);
        continue;
      }
      final total = into.center + c.center;
      if (total > 0) {
        into
          ..r = (into.r * into.center + c.r * c.center) / total
          ..g = (into.g * into.center + c.g * c.center) / total
          ..b = (into.b * into.center + c.b * c.center) / total;
      }
      into
        ..center = total
        ..border += c.border
        ..members.addAll(c.members);
    }

    final centerN = center.length;
    final borderN = math.max(border.length, 1);
    final picks = <_Cluster>[];
    for (final c in merged) {
      final share = c.center / centerN;
      if (share < 0.06) continue;
      // Fon: hoshiyada markazdagidan ancha ko'p.
      final borderShare = c.border / borderN;
      if (borderShare > 0.25 && borderShare > share * 1.4) continue;
      final hsv = HSVColor.fromColor(c.color);
      // Qop-qora soya.
      if (hsv.value < 0.12) continue;
      // Biskvit (oltin-sariq korj / pishgan qobiq) — nachinka emas.
      if (hsv.hue >= 24 &&
          hsv.hue <= 52 &&
          hsv.saturation >= 0.22 &&
          hsv.saturation <= 0.78 &&
          hsv.value >= 0.5) {
        continue;
      }
      picks.add(c);
    }
    if (picks.isEmpty || picks.first.center / centerN < 0.08) return null;

    final first = picks.first;
    _Cluster? second;
    for (final c in picks.skip(1)) {
      if (math.sqrt(first.dist(c.r, c.g, c.b)) >= _distinctDist) {
        second = c;
        break;
      }
    }
    return FillingLook(
      _pure(rgba, first),
      second == null ? null : _pure(rgba, second),
    );
  }

  // Guruhning «toza» rangi. Kichraytirilgan fotoda nachinka va biskvit
  // chegarasidagi piksellar ARALASH tusda bo'ladi — oddiy o'rtacha rang
  // xira, biskvitga tortilgan chiqadi. Shuning uchun guruhning eng «toza»
  // 40% pikseli olinadi va shularning o'rtachasi:
  //  - rangli guruh (qulupnay, manго, fisitashka ...) — eng YORQIN-to'yingan
  //    piksellar (to'yinganlik × yorug'lik): soyadagi to'q joylar emas;
  //  - rangsiz/xira guruh (qaymoq, shokolad) — biskvit rangidan ENG UZOQ
  //    piksellar (qaymoq — eng oqlari, shokolad — eng to'qlari).
  static Color _pure(ByteData rgba, _Cluster c) => _pureOf(rgba, c.members);

  // [pixels] (RGBA ofsetlari) ning «toza» rangi — yuqoridagi qoida bilan.
  static Color _pureOf(ByteData rgba, List<int> pixels) {
    const sr = 242.0, sg = 206.0, sb = 126.0; // BiscuitPalette.classic.sponge
    double mr = 0, mg = 0, mb = 0;
    for (final i in pixels) {
      mr += rgba.getUint8(i);
      mg += rgba.getUint8(i + 1);
      mb += rgba.getUint8(i + 2);
    }
    final len = math.max(pixels.length, 1);
    final mean = Color.fromARGB(
        255, (mr / len).round(), (mg / len).round(), (mb / len).round());
    if (pixels.length < 8) return mean;
    // To'yingan ranglar (jele, meva) — eng to'yingan piksellar. Shokolad
    // kabi to'q jigarranglar bunga kirmaydi: ularda eng to'yingan piksellar
    // aynan biskvit bilan aralashgan chegaradagilar bo'ladi.
    final hsv = HSVColor.fromColor(mean);
    final brownish = hsv.hue > 12 && hsv.hue < 50 && hsv.value < 0.5;
    final vivid = hsv.saturation > 0.5 && !brownish;
    // Och kremlar (qaymoq, slivka) — eng OQ piksellar: biskvit ushoqlari va
    // jele izlari rangni xira/pushti qilib yubormasin.
    final light = !vivid && hsv.value > 0.7;
    double score(int i) {
      final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      if (vivid) {
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        // s × v = (max − min) / 255.
        return (mx - mn).toDouble();
      }
      if (light) return (r + g + b).toDouble();
      final dr = r - sr, dg = g - sg, db = b - sb;
      return dr * dr + dg * dg + db * db;
    }

    final sorted = [...pixels]
      ..sort((a, b) => score(b).compareTo(score(a)));
    final n = math.max(8, (sorted.length * 0.4).round());
    double r = 0, g = 0, b = 0;
    for (final i in sorted.take(n)) {
      r += rgba.getUint8(i);
      g += rgba.getUint8(i + 1);
      b += rgba.getUint8(i + 2);
    }
    final count = math.min(n, sorted.length);
    final pure = Color.fromARGB(
        255, (r / count).round(), (g / count).round(), (b / count).round());
    if (!vivid) return pure;
    // Yaltiroq jele/konfi fotoda o'zidan to'qroq tushadi (to'q bordo) va
    // tekis bo'yalganda jigarrangga o'xshab qoladi — tusi va to'yinganligi
    // o'zgarmagan holda yorug'ligi kamida 0.62 ga ko'tariladi.
    final p = HSVColor.fromColor(pure);
    return p.value >= 0.62 ? pure : p.withValue(0.62).toColor();
  }
}

// [url] dagi fotoni kichik o'lchamda yuklab tahlil qiladi va builder'ga
// beradi (yuklanguncha / foto yo'q / rang topilmasa — null). Keshlanadi.
class FillingPhotoLookBuilder extends StatefulWidget {
  final String? url; // to'liq URL yoki null
  final Widget Function(BuildContext context, FillingLook? look) builder;

  const FillingPhotoLookBuilder({
    super.key,
    required this.url,
    required this.builder,
  });

  @override
  State<FillingPhotoLookBuilder> createState() =>
      _FillingPhotoLookBuilderState();
}

class _FillingPhotoLookBuilderState extends State<FillingPhotoLookBuilder> {
  FillingLook? _look;
  String? _url;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(FillingPhotoLookBuilder old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final url = widget.url;
    if (url == _url) return;
    _url = url;
    _unlisten();
    // didChangeDependencies / didUpdateWidget'dan keyin build baribir
    // chaqiriladi — setState kerak emas.
    _look = url == null ? null : FillingPhotoLook.cached(url);
    if (url == null || FillingPhotoLook.isCached(url)) return;
    // Tahlil uchun ~240px: ingichka krem yo'llari (kesimda 2–3% balandlik)
    // bir necha qator bo'lib tushsin. To'liq rasm RAM'ga dekod qilinmaydi.
    final provider = appNetworkImageProvider(
      context,
      url,
      displayWidth: 240,
      maxDecodeWidth: 240,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        final img = info.image.clone();
        info.dispose();
        _unlisten();
        _analyze(url, img);
      },
      onError: (_, __) => _unlisten(),
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  Future<void> _analyze(String url, ui.Image img) async {
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return;
      final look = FillingPhotoLook.analyze(data, img.width, img.height);
      FillingPhotoLook._cache[url] = look;
      if (mounted && _url == url) setState(() => _look = look);
    } finally {
      img.dispose();
    }
  }

  void _unlisten() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _look);
}

// Bir nechta foto uchun (konstruktor: har nachinka qatlamining o'z mahsuloti
// va o'z fotosi bo'lishi mumkin): [urls] dagi har URL tahlil qilinib,
// builder'ga o'sha tartibda beriladi (yuklanmagan / foto yo'q / rang
// topilmagan joyda null). Ichida FillingPhotoLookBuilder'lar ketma-ket
// joylashtiriladi — kesh va qayta yuklash mantiqi o'shaniki.
class FillingPhotoLooksBuilder extends StatelessWidget {
  final List<String?> urls;
  final Widget Function(BuildContext context, List<FillingLook?> looks)
      builder;

  const FillingPhotoLooksBuilder({
    super.key,
    required this.urls,
    required this.builder,
  });

  Widget _level(BuildContext context, int i, List<FillingLook?> acc) {
    if (i >= urls.length) return builder(context, acc);
    return FillingPhotoLookBuilder(
      url: urls[i],
      builder: (context, look) => _level(context, i + 1, [...acc, look]),
    );
  }

  @override
  Widget build(BuildContext context) => _level(context, 0, const []);
}
