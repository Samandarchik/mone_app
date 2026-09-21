// FillingLook.detect — «П/Ф Начинка» rangi тех картадан: nom → blok nomi →
// masalliqlar (miqdori eng ko'p rang beruvchi masalliq; neytral asos oxirida).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/admin/ui/widgets/filling_color_palette.dart';
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
