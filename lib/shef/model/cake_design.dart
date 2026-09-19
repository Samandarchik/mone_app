// shef/model/cake_design.dart — tort konstruktori (CakeConstructorPage)
// ma'lumotlari: 3D ko'rinish tavsifi (CakeLook → widgets/cake_3d.dart),
// variantlar katalogi (shakl, ta'm, rang, toppinglar, yozuv rangi,
// qo'shimchalar) va tanlangan tort (CakeDesign) — jami narx shu yerda.
// Katalog va narxlar HOZIRCHA LOKAL (backend'da konstruktor endpoint'i yo'q);
// narxni o'zgartirish — shu faylda. Pul — BUTUN so'm.
import 'package:flutter/material.dart';

enum CakeShape { round, square, tiered }

// Tortda ko'rinadigan bezaklar (toppinglar + ko'rinadigan qo'shimchalar).
enum CakeDeco { pearls, berries, macarons, drip, sprinkles, flowers, candles, topper }

// 3D ko'rinish uchun tavsif (faqat vizual).
class CakeLook {
  final CakeShape shape;
  // Tort kengligi nisbati (1 — eng katta, patnisga nisbatan).
  final double scale;
  final Color color;
  final Set<CakeDeco> decos;
  final String text;
  final Color textColor;

  const CakeLook({
    this.shape = CakeShape.round,
    this.scale = 1,
    this.color = const Color(0xFFF1E4C6),
    this.decos = const {CakeDeco.pearls},
    this.text = '',
    this.textColor = const Color(0xFF4A2C1D),
  });

  @override
  bool operator ==(Object other) =>
      other is CakeLook &&
      other.shape == shape &&
      other.scale == scale &&
      other.color == color &&
      other.text == text &&
      other.textColor == textColor &&
      other.decos.length == decos.length &&
      other.decos.containsAll(decos);

  @override
  int get hashCode =>
      Object.hash(shape, scale, color, text, textColor, Object.hashAllUnordered(decos));
}

class ShapeOption {
  final String id;
  final String name;
  final int persons;
  final int diameterSm;
  final int price;
  final CakeShape shape;
  final double scale;
  final bool hit;

  const ShapeOption(this.id, this.name, this.persons, this.diameterSm,
      this.price, this.shape, this.scale,
      {this.hit = false});

  bool get isRound => shape == CakeShape.round;
}

class FlavorOption {
  final String id;
  final String name;
  final String description;
  final int price;
  final Color color;

  const FlavorOption(this.id, this.name, this.description, this.price, this.color);
}

class ColorOption {
  final String id;
  final String name;
  final Color color;
  final int price;

  const ColorOption(this.id, this.name, this.color, [this.price = 0]);
}

// Topping yoki qo'shimcha. [deco] — tortda ko'rinsa (aks holda null).
class AddonOption {
  final String id;
  final String name;
  final int price;
  final CakeDeco? deco;
  final IconData icon;

  const AddonOption(this.id, this.name, this.price, this.icon, [this.deco]);
}

class CakeCatalog {
  CakeCatalog._();

  static const List<ShapeOption> shapes = [
    ShapeOption('klassik', 'Klassik Aylana', 6, 16, 205000, CakeShape.round, 0.95),
    ShapeOption('kichik', 'Kichik standart', 4, 15, 180000, CakeShape.round, 0.86,
        hit: true),
    ShapeOption('bento', 'Bento', 2, 12, 115000, CakeShape.round, 0.7),
    ShapeOption('standart', 'Standart', 8, 17, 245000, CakeShape.round, 1),
    ShapeOption('kvadrat', 'Kvadrat', 8, 18, 260000, CakeShape.square, 0.95),
    ShapeOption('kvadrat_mini', 'Kvadrat mini', 4, 14, 170000, CakeShape.square, 0.78),
    ShapeOption('ikki_qavat', 'Ikki qavatli', 12, 20, 380000, CakeShape.tiered, 1),
  ];

  static const List<FlavorOption> flavors = [
    FlavorOption('vanil', 'Vanilli', 'Vanil biskvit, qaymoqli krem', 0, Color(0xFFF5E6C4)),
    FlavorOption('shokolad', 'Shokoladli', 'Shokolad biskvit, ganash', 15000, Color(0xFF6B4226)),
    FlavorOption('qizil', 'Qizil baxmal', 'Red velvet, krem-chiz', 25000, Color(0xFFB0283A)),
    FlavorOption('qulupnay', 'Qulupnayli', 'Vanil biskvit, qulupnay konfiturasi', 20000, Color(0xFFF08DA0)),
    FlavorOption('karamel', 'Karamel-yong\'oq', 'Sho\'r karamel, yong\'oq', 25000, Color(0xFFC98B4B)),
    FlavorOption('limon', 'Limonli', 'Limon kurd, bezeli', 15000, Color(0xFFF3DB6B)),
    FlavorOption('pista', 'Pista', 'Pista kremi, malina', 30000, Color(0xFFA9C47F)),
  ];

  static const List<ColorOption> colors = [
    ColorOption('krem', 'Krem', Color(0xFFF1E4C6)),
    ColorOption('oq', 'Oq', Color(0xFFFBFAF7)),
    ColorOption('pushti', 'Pushti', Color(0xFFF6C9D2)),
    ColorOption('lavanda', 'Lavanda', Color(0xFFD9CCF0)),
    ColorOption('havorang', 'Havorang', Color(0xFFC7E1F3)),
    ColorOption('yalpiz', 'Yalpiz', Color(0xFFCDEBDD)),
    ColorOption('shaftoli', 'Shaftoli', Color(0xFFF8D2B8)),
    ColorOption('shokolad', 'Shokolad', Color(0xFF7A4B31), 10000),
    ColorOption('qora', 'Qora', Color(0xFF2F2A33), 15000),
  ];

  static const List<AddonOption> toppings = [
    AddonOption('pearls', 'Marvaridlar', 10000, Icons.bubble_chart_outlined, CakeDeco.pearls),
    AddonOption('berries', 'Rezavorlar', 30000, Icons.spa_outlined, CakeDeco.berries),
    AddonOption('macarons', 'Makaronlar', 35000, Icons.cookie_outlined, CakeDeco.macarons),
    AddonOption('drip', 'Shokolad oqimi', 20000, Icons.water_drop_outlined, CakeDeco.drip),
    AddonOption('sprinkles', 'Sepmalar', 8000, Icons.grain, CakeDeco.sprinkles),
    AddonOption('flowers', 'Qand gullar', 25000, Icons.local_florist_outlined, CakeDeco.flowers),
  ];

  static const int inscriptionPrice = 15000;
  static const int inscriptionMaxLength = 30;

  static const List<ColorOption> textColors = [
    ColorOption('shokolad', 'Shokolad', Color(0xFF4A2C1D)),
    ColorOption('oq', 'Oq', Color(0xFFFFFFFF)),
    ColorOption('oltin', 'Oltin', Color(0xFFC9A04A)),
    ColorOption('pushti', 'Pushti', Color(0xFFE0708A)),
    ColorOption('qora', 'Qora', Color(0xFF222222)),
  ];

  static const List<AddonOption> extras = [
    AddonOption('candles', 'Shamlar', 10000, Icons.local_fire_department_outlined, CakeDeco.candles),
    AddonOption('topper', 'Topper «Tabriklaymiz»', 25000, Icons.celebration_outlined, CakeDeco.topper),
    AddonOption('sparkler', 'Bengal shami', 15000, Icons.auto_awesome_outlined),
    AddonOption('box', 'Sovg\'a qutisi', 20000, Icons.card_giftcard_outlined),
    AddonOption('card', 'Otkritka', 10000, Icons.mail_outline),
  ];
}

// Konstruktorda tanlangan tort. Jami narx — tanlanganlar yig'indisi.
class CakeDesign {
  ShapeOption shape = CakeCatalog.shapes.firstWhere((s) => s.hit);
  FlavorOption flavor = CakeCatalog.flavors.first;
  ColorOption color = CakeCatalog.colors.first;
  final Set<String> toppingIds = {};
  String text = '';
  ColorOption textColor = CakeCatalog.textColors.first;
  final Set<String> extraIds = {};

  Iterable<AddonOption> get toppings =>
      CakeCatalog.toppings.where((t) => toppingIds.contains(t.id));
  Iterable<AddonOption> get extras =>
      CakeCatalog.extras.where((e) => extraIds.contains(e.id));

  bool get hasText => text.trim().isNotEmpty;

  int get total {
    var sum = shape.price + flavor.price + color.price;
    for (final t in toppings) {
      sum += t.price;
    }
    for (final e in extras) {
      sum += e.price;
    }
    if (hasText) sum += CakeCatalog.inscriptionPrice;
    return sum;
  }

  CakeLook get look => CakeLook(
        shape: shape.shape,
        scale: shape.scale,
        color: color.color,
        decos: {
          for (final a in [...toppings, ...extras])
            if (a.deco != null) a.deco!,
        },
        text: text.trim(),
        textColor: textColor.color,
      );
}

// 180000 → «180 000».
String formatSom(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
