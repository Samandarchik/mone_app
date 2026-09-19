// shef/ui/widgets/biscuit_photo_look.dart — tex kartadagi biskvit FOTOSIDAN
// 3D ko'rinishni moslash (BiscuitPhotoLook): foto kichraytirib yuklanadi,
// markaziy qismi (fon/patnis chetlari tashlab) ranglar bo'yicha tahlil
// qilinadi:
//  - biskvit rangi: och/oltin (o'z rangidan palitra), to'q jigarrang →
//    shokoladli, qizil massa → qizil baxmal;
//  - mevalar (yon tomonda chiziladi): to'q qizil dog'lar → olcha, yorqin
//    qizil → qulupnay, to'q ko'k → chernika, yashil → kivi.
// Bu RANG tahlili (sun'iy intellekt emas): aniq ko'rinadigan rezavorlarni va
// biskvit rangini ushlaydi, lekin masalan qizil likopcha xato beradi.
// Natija URL bo'yicha keshlanadi — karta va katta 3D qayta hisoblamaydi.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:uz_ai_dev/core/widgets/app_network_image.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';

class BiscuitPhotoLook {
  // null — fotodan biskvit rangi aniqlanmadi (nom/tarkib palitrasi qoladi).
  final BiscuitPalette? palette;
  final List<BiscuitFruit> fruits;

  const BiscuitPhotoLook({this.palette, this.fruits = const []});

  static final Map<String, BiscuitPhotoLook> _cache = {};

  static BiscuitPhotoLook? cached(String url) => _cache[url];

  // Foto piksellaridan (RGBA, w×h) ko'rinish.
  static BiscuitPhotoLook analyze(ByteData rgba, int w, int h) {
    // Markaziy 70% — fon va likopcha chetlari kamroq tushadi.
    final x0 = (w * 0.15).floor(), x1 = (w * 0.85).ceil();
    final y0 = (h * 0.15).floor(), y1 = (h * 0.85).ceil();
    var total = 0;
    var cherry = 0, straw = 0, blue = 0, kiwi = 0, choc = 0, red = 0;
    var sponge = 0;
    double sr = 0, sg = 0, sb = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
        final b = rgba.getUint8(i + 2), a = rgba.getUint8(i + 3);
        if (a < 128) continue;
        total++;
        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        final hue = hsv.hue, s = hsv.saturation, v = hsv.value;
        final isRedHue = hue >= 335 || hue <= 8;
        if (isRedHue && s > 0.55 && v >= 0.18 && v < 0.6) {
          cherry++;
          red++;
        } else if (isRedHue && s > 0.5 && v >= 0.6) {
          straw++;
          red++;
        } else if (hue >= 200 && hue <= 290 && s > 0.25 && v < 0.55) {
          blue++;
        } else if (hue >= 70 && hue <= 150 && s > 0.35 && v > 0.3) {
          kiwi++;
        } else if (hue > 8 && hue <= 40 && s > 0.25 && v < 0.42) {
          choc++;
        } else if (hue >= 22 && hue <= 55 && s >= 0.15 && s <= 0.75 &&
            v >= 0.55) {
          sponge++;
          sr += r;
          sg += g;
          sb += b;
        }
      }
    }
    if (total == 0) return const BiscuitPhotoLook();
    double part(int n) => n / total;

    BiscuitPalette? palette;
    var redIsSponge = false;
    if (part(choc) > 0.3) {
      palette = BiscuitPalette.chocolate;
    } else if (part(red) > 0.3) {
      // Qizil — biskvitning o'zi (qizil baxmal), meva emas.
      palette = BiscuitPalette.redVelvet;
      redIsSponge = true;
    } else if (part(sponge) > 0.15) {
      palette = _fromSponge(
        Color.fromARGB(
          255,
          (sr / sponge).round(),
          (sg / sponge).round(),
          (sb / sponge).round(),
        ),
      );
    }

    // Meva — kamida 2.5% maydon (tasodifiy nuqtalar hisobga olinmaydi),
    // ko'p ko'ringani oldin.
    final fruits = <(int, BiscuitFruit)>[
      if (!redIsSponge && part(cherry) > 0.025) (cherry, BiscuitFruit.cherry),
      if (!redIsSponge && part(straw) > 0.025) (straw, BiscuitFruit.strawberry),
      if (part(blue) > 0.025) (blue, BiscuitFruit.blueberry),
      if (part(kiwi) > 0.025) (kiwi, BiscuitFruit.kiwi),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return BiscuitPhotoLook(
      palette: palette,
      fruits: [for (final (_, f) in fruits.take(3)) f],
    );
  }

  // Fotodagi biskvit rangidan palitra (qobiq — klassik pishgan).
  static BiscuitPalette _fromSponge(Color s) {
    const c = BiscuitPalette.classic;
    return BiscuitPalette(
      sponge: s,
      spongeShade: Color.lerp(s, Colors.black, 0.14)!,
      spongeLight: Color.lerp(s, Colors.white, 0.35)!,
      crustLight: c.crustLight,
      crust: c.crust,
      crustDark: c.crustDark,
      pore: Color.lerp(s, Colors.black, 0.25)!,
      baked: c.baked,
      rim: c.rim,
    );
  }

  // Nom/tarkibdan olingan ko'rinish bilan birlashtirish: fotodagi rang
  // ustun, mevalar — nomdagilar + fotodagilar (takrorsiz, ko'pi bilan 3).
  (BiscuitPalette, List<BiscuitFruit>) mergeWith(
      BiscuitPalette palette, List<BiscuitFruit> fruits) {
    final all = <BiscuitFruit>[...fruits];
    for (final f in this.fruits) {
      if (!all.contains(f)) all.add(f);
    }
    return (this.palette ?? palette, all.take(3).toList());
  }
}

// [url] dagi fotoni kichik o'lchamda yuklab tahlil qiladi va builder'ga
// beradi (yuklanguncha / foto yo'q bo'lsa null). Natija keshlanadi.
class BiscuitPhotoLookBuilder extends StatefulWidget {
  final String? url; // to'liq URL yoki null
  final Widget Function(BuildContext context, BiscuitPhotoLook? look) builder;

  const BiscuitPhotoLookBuilder({
    super.key,
    required this.url,
    required this.builder,
  });

  @override
  State<BiscuitPhotoLookBuilder> createState() =>
      _BiscuitPhotoLookBuilderState();
}

class _BiscuitPhotoLookBuilderState extends State<BiscuitPhotoLookBuilder> {
  BiscuitPhotoLook? _look;
  String? _url;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(BiscuitPhotoLookBuilder old) {
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
    _look = url == null ? null : BiscuitPhotoLook.cached(url);
    if (url == null || _look != null) return;
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
      final look = BiscuitPhotoLook.analyze(data, img.width, img.height);
      BiscuitPhotoLook._cache[url] = look;
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
