// FillingLook.detect — «П/Ф Начинка» rangi тех картадан: nom → blok nomi →
// masalliqlar (miqdori eng ko'p rang beruvchi masalliq; neytral asos oxirida).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
import 'package:uz_ai_dev/shef/ui/widgets/biscuit_3d.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

const _strawberry = Color(0xFFD9364A);
const _chocolate = Color(0xFF5A3420);
const _cream = Color(0xFFFFF3DC);
const _honey = Color(0xFFE0A74E);

TechCard _card(List<TechItem> items, {String base = 'Основа'}) =>
    TechCard(bases: [TechBase(name: base, ingredients: items)]);

void main() {
  paletteTests();
  coatingTests();
  twoLayerTests();
  biscuitColorTests();
  test('nom eng ustun — masalliqlarga qaralmaydi', () {
    final card = _card(const [
      TechItem(name: 'Пюре клубника', unit: 'g', amount: 900),
    ]);
    expect(FillingLook.detect('Начинка шоколадная', card).color, _chocolate);
  });

  test('nomda yo\'q — blok nomidan', () {
    final card = _card(const [], base: 'Клубничное конфи');
    expect(FillingLook.detect('Начинка №2', card).color, _strawberry);
  });

  test('masalliqlar: miqdori eng ko\'p rang beruvchi tanlanadi', () {
    final card = _card(const [
      TechItem(name: 'Сливки 33%', unit: 'ml', amount: 500),
      TechItem(name: 'Пюре клубника', unit: 'g', amount: 300),
      TechItem(name: 'Шоколад белый', unit: 'g', amount: 50),
      TechItem(name: 'Сахар', unit: 'g', amount: 100),
    ]);
    expect(FillingLook.detect('Начинка №3', card).color, _strawberry);
  });

  test('faqat neytral asos — qaymoqrang', () {
    final card = _card(const [
      TechItem(name: 'Сливки 33%', unit: 'ml', amount: 500),
      TechItem(name: 'Сахар', unit: 'g', amount: 100),
    ]);
    expect(FillingLook.detect('Начинка №4', card).color, _cream);
  });

  test('hech narsa mos kelmasa — neytral', () {
    expect(FillingLook.detect('Начинка №5', null), FillingLook.neutral);
    expect(
      FillingLook.detect('Начинка №5', _card(const [
        TechItem(name: 'Сахар', unit: 'g', amount: 100),
      ])),
      FillingLook.neutral,
    );
  });

  test('«мед» faqat alohida so\'z sifatida', () {
    expect(FillingLook.detect('Медленная начинка', null), FillingLook.neutral);
    expect(FillingLook.detect('Начинка с мёдом', null).color, _honey);
    expect(FillingLook.detect('Начинка медовая', null).color, _honey);
  });
}

// Palitra (tech_card.filling_color) — eng ustun manba.
void paletteTests() {
  test('hex ↔ Color', () {
    expect(fillingColorFromHex('#D9364A'), const Color(0xFFD9364A));
    expect(fillingColorFromHex(' #d9364a '), const Color(0xFFD9364A));
    expect(fillingColorFromHex(''), isNull);
    expect(fillingColorFromHex('#FFF'), isNull);
    expect(fillingColorFromHex('qizil'), isNull);
    expect(fillingColorToHex(const Color(0xFFD9364A)), '#D9364A');
    // Palitradagi har rang saqlash formatidan o'zgarishsiz qaytadi.
    for (final c in kFillingPalette) {
      expect(fillingColorFromHex(fillingColorToHex(c)), c);
    }
  });

  test('resolve: palitra rangi foto va nomdan ustun, foto tahlil qilinmaydi',
      () {
    const card = TechCard(
      fillingColor: '#8BC34A',
      biscuitPhotoUrl: '/static/tort.jpg',
    );
    final (look, photo) = FillingLook.resolve('Начинка шоколадная', card);
    expect(look, const FillingLook(Color(0xFF8BC34A)));
    expect(photo, isNull);
  });

  test('resolve: rang tanlanmagan — foto URL qaytadi, rang nomdan', () {
    const card = TechCard(biscuitPhotoUrl: '/static/tort.jpg');
    final (look, photo) = FillingLook.resolve('Начинка шоколадная', card);
    expect(look.color, _chocolate);
    expect(photo, endsWith('/static/tort.jpg'));
  });

  test('TechCard: filling_color JSON\'da saqlanadi', () {
    const card = TechCard(fillingColor: '#D9364A');
    expect(card.toJson()['filling_color'], '#D9364A');
    expect(TechCard.fromJson(card.toJson()).fillingColor, '#D9364A');
    expect(TechCard.fromJson(const {}).fillingColor, '');
    expect(card.copyWith(bakeTimeMin: 5).fillingColor, '#D9364A');
  });
}

// «Покрытие» — qoplama rangi nachinka rangidan mustaqil.
void coatingTests() {
  test('coatOf: «Покрытие» palitrasi ustun, nachinka rangi ta\'sir qilmaydi',
      () {
    const card = TechCard(fillingColor: '#5A3420', coatingColor: '#F8BBD0');
    expect(FillingLook.coatOf('Начинка шоколадная', card),
        const Color(0xFFF8BBD0));
    // Nachinka tomoni o'z rangida qoladi.
    expect(FillingLook.resolve('Начинка шоколадная', card).$1,
        const FillingLook(Color(0xFF5A3420)));
  });

  test('coatOf: rang tanlanmagan — nom/tarkibdan', () {
    expect(FillingLook.coatOf('Начинка шоколадная', const TechCard()),
        _chocolate);
    expect(FillingLook.coatOf('Начинка №9', null), FillingLook.neutral.color);
    // Faqat nachinka rangi tanlangan — qoplamaga o'tmaydi.
    expect(
      FillingLook.coatOf(
          'Начинка клубничная', const TechCard(fillingColor: '#8BC34A')),
      _strawberry,
    );
  });

  test('TechCard: coating_color JSON\'da saqlanadi', () {
    const card = TechCard(coatingColor: '#F8BBD0', fillingColor: '#5A3420');
    final json = card.toJson();
    expect(json['coating_color'], '#F8BBD0');
    expect(json['filling_color'], '#5A3420');
    final back = TechCard.fromJson(json);
    expect(back.coatingColor, '#F8BBD0');
    expect(back.fillingColor, '#5A3420');
    expect(TechCard.fromJson(const {}).coatingColor, '');
    expect(card.copyWith(bakeTimeMin: 5).coatingColor, '#F8BBD0');
  });
}

// Tex kartada nachinka uchun YAGONA palitra (filling_color): tanlangan rang
// nachinkaning HAMMA qatlamlariga (bandsOf(0), bandsOf(1)) qo'llanadi.
void twoLayerTests() {
  const pink = Color(0xFFF8BBD0);

  test('resolve: yagona palitra rangi — hamma qatlam bir xil', () {
    const card = TechCard(fillingColor: '#F8BBD0');
    final (look, photo) = FillingLook.resolve('Начинка №1', card);
    expect(photo, isNull);
    expect(look.bandsOf(0).single.color, pink);
    expect(look.bandsOf(1).single.color, pink);
    expect(look.bandsOf(2).single.color, pink);
  });

  test('fromTechCard: palitra rangi nom/tarkibdan ustun, hamma qatlamda', () {
    const card = TechCard(fillingColor: '#5A3420');
    final look = FillingLook.fromTechCard('Начинка клубничная', card);
    expect(look.bandsOf(0).single.color, _chocolate);
    expect(look.bandsOf(1).single.color, _chocolate);
    expect(FillingLook.hasPaletteColor(card), isTrue);
  });

  test('fromTechCard: palitra yo\'q — tavsifdan, foto hisobga olinmaydi', () {
    const card = TechCard(biscuitPhotoUrl: '/x.jpg');
    final look = FillingLook.fromTechCard('Начинка клубничная', card);
    expect(look.bandsOf(0).single.color, _strawberry);
    expect(look.bandsOf(1).single.color, _strawberry);
    expect(FillingLook.hasPaletteColor(card), isFalse);
  });

  test('TechCard: eski filling_color2 JSON\'dan o\'qilmaydi va yuborilmaydi',
      () {
    final card = TechCard.fromJson(
        const {'filling_color': '#F8BBD0', 'filling_color2': '#5A3420'});
    expect(card.fillingColor, '#F8BBD0');
    expect(card.toJson().containsKey('filling_color2'), isFalse);
    expect(card.toJson()['filling_color'], '#F8BBD0');
  });
}

// Biskvit rangi — tex kartadagi «Biskvit rangi» palitrasi (biscuit_color).
void biscuitColorTests() {
  test('BiscuitPalette.of: palitra rangi nom/tarkibdan ustun', () {
    const card = TechCard(biscuitColor: '#F8BBD0');
    final p = BiscuitPalette.of('Бисквит шоколадный', card);
    expect(p.sponge, const Color(0xFFF8BBD0));
    // Qobiq — o'sha rangning to'qrog'i, begona tus emas.
    expect(p.crust, Color.lerp(const Color(0xFFF8BBD0), Colors.black, 0.22));
  });

  test('BiscuitPalette.of: rang tanlanmagan — nom/tarkibdan', () {
    expect(BiscuitPalette.of('Бисквит шоколадный', const TechCard()),
        BiscuitPalette.chocolate);
    expect(BiscuitPalette.of('Бисквит', null), BiscuitPalette.classic);
  });

  test('TechCard: biscuit_color JSON\'da saqlanadi', () {
    const card = TechCard(biscuitColor: '#6B4029');
    expect(card.toJson()['biscuit_color'], '#6B4029');
    expect(TechCard.fromJson(card.toJson()).biscuitColor, '#6B4029');
    expect(TechCard.fromJson(const {}).biscuitColor, '');
    expect(card.copyWith(bakeTimeMin: 5).biscuitColor, '#6B4029');
  });
}
