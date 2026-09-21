// FillingLook.detect — «П/Ф Начинка» rangi тех картадан: nom → blok nomi →
// masalliqlar (miqdori eng ko'p rang beruvchi masalliq; neytral asos oxirida).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uz_ai_dev/admin/model/tech_card.dart';
import 'package:uz_ai_dev/shef/ui/widgets/filling_3d.dart';

const _strawberry = Color(0xFFD9364A);
const _chocolate = Color(0xFF5A3420);
const _cream = Color(0xFFFFF3DC);
const _honey = Color(0xFFE0A74E);

TechCard _card(List<TechItem> items, {String base = 'Основа'}) =>
    TechCard(bases: [TechBase(name: base, ingredients: items)]);

void main() {
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
