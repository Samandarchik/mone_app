// shef/ui/widgets/filling_photo_look.dart — «П/Ф Начинка» tex kartasidagi
// FOTOdan (masalan kesilgan tort, ichida nachinka) nachinka ranglarini olish.
// Foto kichraytirib yuklanadi (~96px) va ranglar bo'yicha tahlil qilinadi:
//  1) markaziy qism piksellari k-means bilan bir nechta rang guruhiga
//     bo'linadi, o'xshash guruhlar birlashtiriladi;
//  2) FON tashlanadi — rasm chetidagi hoshiyada markazdagidan ko'proq
//     uchraydigan rang (stol, patnis, devor);
//  3) BISKVIT rangi tashlanadi (oltin-sariq korj / qobiq) — chizmada
//     biskvit qatlamlari baribir bor, bizga nachinka kerak;
//  4) qolganlaridan eng ko'p joy egallagan 1–2 ta rang = nachinka:
//     birinchisi yuqori, ikkinchisi pastki nachinka qatlamiga
//     (masalan «kaymoq + shokolad» → oqish va jigarrang).
// Hech narsa qolmasa (foto faqat biskvit/fon) — null: rang avvalgidek тех
// карта nomi/tarkibidan olinadi (FillingLook.detect).
// Bu RANG tahlili (sun'iy intellekt emas): oq fondagi oq krem fon deb
// tashlanishi, shokoladli biskvit esa nachinka deb olinishi mumkin.
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

  // Foto piksellaridan (RGBA, w×h) nachinka ranglari; topilmasa null.
  static FillingLook? analyze(ByteData rgba, int w, int h) {
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
  static Color _pure(ByteData rgba, _Cluster c) {
    const sr = 242.0, sg = 206.0, sb = 126.0; // BiscuitPalette.classic.sponge
    if (c.members.length < 8) return c.color;
    // To'q ranglar (shokolad) «rangli» hisoblanmaydi: ularda eng to'yingan
    // piksellar aynan biskvit bilan aralashgan chegaradagilar bo'ladi.
    final hsv = HSVColor.fromColor(c.color);
    final vivid = hsv.saturation > 0.5 && hsv.value > 0.5;
    double score(int i) {
      final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      if (vivid) {
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        // s × v = (max − min) / 255.
        return (mx - mn).toDouble();
      }
      final dr = r - sr, dg = g - sg, db = b - sb;
      return dr * dr + dg * dg + db * db;
    }

    final sorted = [...c.members]
      ..sort((a, b) => score(b).compareTo(score(a)));
    final n = math.max(8, (sorted.length * 0.4).round());
    double r = 0, g = 0, b = 0;
    for (final i in sorted.take(n)) {
      r += rgba.getUint8(i);
      g += rgba.getUint8(i + 1);
      b += rgba.getUint8(i + 2);
    }
    final count = math.min(n, sorted.length);
    return Color.fromARGB(
        255, (r / count).round(), (g / count).round(), (b / count).round());
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
    // Tahlil uchun ~96px yetarli (to'liq rasm RAM'ga dekod qilinmaydi).
    final provider = appNetworkImageProvider(
      context,
      url,
      displayWidth: 32,
      maxDecodeWidth: 96,
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
