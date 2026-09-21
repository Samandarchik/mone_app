// shef/ui/widgets/biscuit_photo_look.dart — tex kartadagi biskvit FOTOSIDAN
// 3D ko'rinishni moslash (BiscuitPhotoLook): foto kichraytirib yuklanadi,
// markaziy qismi (fon/patnis chetlari tashlab) ranglar bo'yicha tahlil
// qilinadi:
//  - biskvit rangi: fotodagi ENG KO'P uchragan rang klasteri — qaysi tus
//    bo'lishidan qat'i nazar (qulupnayli pushti, fisitashli yashil, oqish
//    vanil, sariq-oltin ...); shu rangdan butun palitra yasaladi (qobiq ham
//    o'sha rangning pishgani). To'q jigarrang → shokoladli, to'yingan qizil
//    massa → qizil baxmal tayyor palitralari olinadi;
//  - mevalar (yon kesimda chiziladi): biskvitning O'Z rangidan AJRALIB
//    turadigan dog'lar — to'q qizil → olcha, yorqin qizil → qulupnay,
//    to'q ko'k → chernika, yashil → kivi. Shuning uchun pushti biskvitning
//    o'zi «qulupnay bo'lagi» deb sanalmaydi, ustidagi haqiqiy bo'laklar esa
//    (to'yingroq/to'qroq) sanaladi.
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

  // Rang doirasi shuncha savatga bo'linadi (har biri 15°) — biskvit tanasi
  // rangini topish uchun.
  static const int _hueBins = 24;

  // Foto piksellaridan (RGBA, w×h) ko'rinish. Ikki o'tish: avval biskvit
  // TANASI rangi (eng ko'p uchragan rang), keyin shu rangdan ajralib
  // turadigan meva dog'lari.
  static BiscuitPhotoLook analyze(ByteData rgba, int w, int h) {
    // Markaziy 70% — fon va likopcha chetlari kamroq tushadi.
    final x0 = (w * 0.15).floor(), x1 = (w * 0.85).ceil();
    final y0 = (h * 0.15).floor(), y1 = (h * 0.85).ceil();

    final binN = List<int>.filled(_hueBins, 0);
    final binR = List<double>.filled(_hueBins, 0);
    final binG = List<double>.filled(_hueBins, 0);
    final binB = List<double>.filled(_hueBins, 0);
    // Rangsiz-ochlar: oqish vanil biskvit, tvorog qatlami va h.k.
    var paleN = 0;
    double paleR = 0, paleG = 0, paleB = 0;
    // Biskvit bo'lishi mumkin bo'lgan piksellar (fon va soya tashlangach).
    var body = 0;

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
        final b = rgba.getUint8(i + 2), a = rgba.getUint8(i + 3);
        if (a < 128) continue;
        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        final s = hsv.saturation, v = hsv.value;
        // Qop-qora soya va yorqin oq fon (patnis, dasturxon) — biskvit emas.
        if (v < 0.13 || (s < 0.12 && v > 0.86)) continue;
        body++;
        if (s < 0.12) {
          paleN++;
          paleR += r;
          paleG += g;
          paleB += b;
          continue;
        }
        final bin = (hsv.hue / 360 * _hueBins).floor() % _hueBins;
        binN[bin]++;
        binR[bin] += r;
        binG[bin] += g;
        binB[bin] += b;
      }
    }
    if (body == 0) return const BiscuitPhotoLook();

    // Eng ko'p uchragan tus + ikkala qo'shnisi = biskvit tanasi klasteri
    // (bir rangning ochrog'i/to'qrog'i qo'shni savatga tushib ketadi).
    var top = 0;
    for (var i = 1; i < _hueBins; i++) {
      if (binN[i] > binN[top]) top = i;
    }
    final lo = (top + _hueBins - 1) % _hueBins;
    final hi = (top + 1) % _hueBins;
    final huedN = binN[lo] + binN[top] + binN[hi];

    // Rangli klaster ham, oqish qism ham maydonning kamida 12% ini
    // egallamasa — fotodan rang olinmaydi (nom/tarkib palitrasi qoladi).
    Color? sponge;
    if (huedN >= paleN && huedN / body > 0.12) {
      sponge = Color.fromARGB(
        255,
        ((binR[lo] + binR[top] + binR[hi]) / huedN).round(),
        ((binG[lo] + binG[top] + binG[hi]) / huedN).round(),
        ((binB[lo] + binB[top] + binB[hi]) / huedN).round(),
      );
    } else if (paleN > huedN && paleN / body > 0.12) {
      sponge = Color.fromARGB(
        255,
        (paleR / paleN).round(),
        (paleG / paleN).round(),
        (paleB / paleN).round(),
      );
    }

    BiscuitPalette? palette;
    // Biskvitning o'z tusi/to'yinganligi — meva dog'larini undan ajratish
    // uchun (-1 — rang aniqlanmadi, hamma dog'lar sanaladi).
    var spongeHue = -1.0, spongeSat = 0.0;
    if (sponge != null) {
      final hsv = HSVColor.fromColor(sponge);
      spongeHue = hsv.hue;
      spongeSat = hsv.saturation;
      final isRedHue = hsv.hue >= 335 || hsv.hue <= 8;
      if (hsv.hue > 8 && hsv.hue <= 45 && hsv.saturation > 0.2 &&
          hsv.value < 0.42) {
        palette = BiscuitPalette.chocolate;
      } else if (isRedHue && hsv.saturation > 0.45 && hsv.value < 0.75) {
        palette = BiscuitPalette.redVelvet;
      } else {
        palette = _fromSponge(sponge);
      }
    }

    // 2-o'tish: meva dog'lari. Biskvitning O'Z rangiga yaqin piksellar
    // sanalmaydi — dog' tus bo'yicha ajralib turishi yoki ancha to'yingroq
    // bo'lishi kerak (pushti biskvit ustidagi to'q qulupnay bo'laklari).
    var cherry = 0, straw = 0, blue = 0, kiwi = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * w + x) * 4;
        final r = rgba.getUint8(i), g = rgba.getUint8(i + 1);
        final b = rgba.getUint8(i + 2), a = rgba.getUint8(i + 3);
        if (a < 128) continue;
        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        final hue = hsv.hue, s = hsv.saturation, v = hsv.value;
        if (v < 0.13 || (s < 0.12 && v > 0.86)) continue;
        if (spongeHue >= 0) {
          var d = (hue - spongeHue).abs();
          if (d > 180) d = 360 - d;
          if (d < 28 && s < spongeSat + 0.18) continue;
        }
        final isRedHue = hue >= 335 || hue <= 8;
        if (isRedHue && s > 0.55 && v >= 0.18 && v < 0.6) {
          cherry++;
        } else if (isRedHue && s > 0.5 && v >= 0.6) {
          straw++;
        } else if (hue >= 200 && hue <= 290 && s > 0.25 && v < 0.55) {
          blue++;
        } else if (hue >= 70 && hue <= 150 && s > 0.35 && v > 0.3) {
          kiwi++;
        }
      }
    }

    // Meva — kamida 2% maydon (tasodifiy nuqtalar hisobga olinmaydi),
    // ko'p ko'ringani oldin.
    final fruits = <(int, BiscuitFruit)>[
      if (cherry / body > 0.02) (cherry, BiscuitFruit.cherry),
      if (straw / body > 0.02) (straw, BiscuitFruit.strawberry),
      if (blue / body > 0.02) (blue, BiscuitFruit.blueberry),
      if (kiwi / body > 0.02) (kiwi, BiscuitFruit.kiwi),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return BiscuitPhotoLook(
      palette: palette,
      fruits: [for (final (_, f) in fruits.take(3)) f],
    );
  }

  // Fotodagi biskvit rangidan butun palitra. Qobiq ham SHU rangdan
  // yasaladi (jigarrangga tortilgan pishgan tusi) — shuning uchun pushti
  // yoki yashil biskvitda ham chetlari tabiiy ko'rinadi, oltin qobiq
  // yopishib qolmaydi.
  static BiscuitPalette _fromSponge(Color s) {
    // Pishgan qobiqning umumiy jigarrangi — har qanday tus shunga tortiladi.
    const baked = Color(0xFF8A5A2E);
    final crust = Color.lerp(Color.lerp(s, baked, 0.45)!, Colors.black, 0.08)!;
    return BiscuitPalette(
      sponge: s,
      spongeShade: Color.lerp(s, Colors.black, 0.14)!,
      spongeLight: Color.lerp(s, Colors.white, 0.35)!,
      crustLight: Color.lerp(crust, Colors.white, 0.18)!,
      crust: crust,
      crustDark: Color.lerp(crust, Colors.black, 0.18)!,
      pore: Color.lerp(s, Colors.black, 0.25)!,
      baked: Color.lerp(crust, Colors.black, 0.12)!,
      rim: Color.lerp(crust, Colors.black, 0.28)!,
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
