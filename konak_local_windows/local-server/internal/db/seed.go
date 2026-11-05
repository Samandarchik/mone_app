package db

import (
	"context"
	"fmt"
	"log"
)

func Seed() {
	ctx := context.Background()
	// Always clean locks on startup
	Pool.Exec(ctx, "DELETE FROM table_locks")

	var count int
	Pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
	if count > 0 {
		return
	}
	log.Println("Seeding database with test data...")

	Pool.Exec(ctx, `INSERT INTO users (id, name, phone, role, pin, status) VALUES
		(1, 'Samandar', '+998901234567', 'super_admin', '1234', 'active'),
		(2, 'Aziz', '+998909876543', 'cashier', '5678', 'active'),
		(3, 'Bobur', '+998905554433', 'waiter', '9012', 'active'),
		(4, 'Shoxrux', '+998903332211', 'kitchen', '3456', 'active')`)

	Pool.Exec(ctx, `INSERT INTO categories (id, name_uz, name_ru, name_tr, icon, sort_order) VALUES
		(1, 'Baqlava', 'Баклава', 'Baklava', '', 1),
		(2, 'Desertlar', 'Десерты', 'Tatlılar', '', 2),
		(3, 'Sovuq ichimliklar', 'Холодные напитки', 'Soğuk İçecekler', '', 3),
		(4, 'Nonushta', 'Завтрак', 'Kahvaltı', '', 4),
		(5, 'O''zim bilan qahva', 'Кофе с собой', 'Paket Kahve', '', 5),
		(6, 'Qahva (zalda)', 'Кофе в заведении', 'Kahve', '', 6),
		(7, 'Choy', 'Чай', 'Çay', '', 7),
		(8, 'Boshqa', 'Прочее', 'Diğer', '', 8)`)

	Pool.Exec(ctx, `INSERT INTO products (id, name_uz, name_ru, name_tr, category_id, price, media, is_recommended, sort_order) VALUES
		(1, 'Beta Ozel Baqlava', 'Бета Озель Баклава', 'Beta Özel Baklava', 1, 10000, '[]', false, 1),
		(2, 'Pistali Sarma', 'Фыстык Сарма (Пахлава с фисташками)', 'Fıstık Sarma', 1, 30000, '[]', false, 2),
		(3, 'Sabzili Baqlava (Havuch Dilimi)', 'Пахлава Хавуч Дилими (морковный ломтик)', 'Havuç Dilimi', 1, 60000, '[]', false, 3),
		(4, 'Quruq Baqlava', 'Сухая пахлава', 'Kuru Baklava', 1, 20000, '[]', false, 4),
		(5, 'Shobiyet Baqlava', 'Шобиет пахлава', 'Şöbiyet Baklava', 1, 25000, '[]', false, 5),
		(6, 'Pistali Kadayif', 'Пахлава с фисташковой кадаиф', 'Fıstıklı Kadayıf', 1, 60000, '[]', false, 6),
		(7, 'Brauni', 'Брауни', 'Brownie', 2, 55000, '[]', false, 1),
		(8, 'Pistali Trayfl', 'Фисташковый трайфл', 'Fıstıklı Trifle', 2, 50000, '[]', false, 2),
		(9, 'Kinder Bueno Chizkeyk', 'Киндер Буэно чизкейк', 'Kinder Bueno Cheesecake', 2, 55000, '[]', false, 3),
		(10, 'Qulupnayli Tart', 'Клубничный тарт', 'Çilekli Tart', 2, 50000, '[]', false, 4),
		(11, 'Shokoladli Qulupnay (katta)', 'Клубника в шоколаде (большая)', 'Çikolatalı Çilek (büyük)', 2, 19500, '[]', false, 5),
		(12, 'Shokoladli Qulupnay (o''rtacha)', 'Клубника в шоколаде (средняя)', 'Çikolatalı Çilek (orta)', 2, 14990, '[]', false, 6),
		(13, 'Shokoladli Qulupnay (mini)', 'Клубника в шоколаде (мини)', 'Çikolatalı Çilek (mini)', 2, 10000, '[]', false, 7),
		(14, 'Qulupnayli Chizkeyk', 'Клубничный чизкейк', 'Çilekli Cheesecake', 2, 55000, '[]', false, 8),
		(15, 'Limonli Chizkeyk', 'Лимонный чизкейк', 'Limonlu Cheesecake', 2, 50000, '[]', false, 9),
		(16, 'Mangoli Desert', 'Манговый десерт', 'Mangolu Tatlı', 2, 54500, '[]', false, 10),
		(17, 'Asalli tort (Medovik)', 'Медовик', 'Ballı Pasta (Medovik)', 2, 55000, '[]', false, 11),
		(18, 'Qovoqli Chizkeyk', 'Тыквенный чизкейк', 'Balkabağı Cheesecake', 2, 50000, '[]', false, 12),
		(19, 'San Sebastyan Ko''k mevali', 'Сан Себастьян с голубикой', 'San Sebastian Yaban Mersinli', 2, 40000, '[]', false, 13),
		(20, 'Kofeli San Sebastyan', 'Кофейный Сан Себастьян', 'Kahveli San Sebastian', 2, 40000, '[]', false, 14),
		(21, 'Shakarsiz Pechenye', 'Печенье без сахара', 'Şekersiz Kurabiye', 2, 28000, '[]', false, 15),
		(22, 'Shokolad', 'Шоколад', 'Çikolata', 2, 20000, '[]', false, 16),
		(23, 'Shokoladli Trayfl', 'Шоколадный трайфл', 'Çikolatalı Trifle', 2, 55000, '[]', false, 17),
		(24, 'Uch Shokolad', 'Три шоколада', 'Üç Çikolata', 2, 55000, '[]', false, 18),
		(25, 'Olchali Milka', 'Вишнёвая Милка', 'Vişneli Milka', 2, 55000, '[]', false, 19),
		(26, 'Pistali Yumcha', 'Юмча фисташковая', 'Fıstıklı Yumcha', 2, 45000, '[]', false, 20),
		(27, 'Qulupnayli Yumcha', 'Юмча клубничная', 'Çilekli Yumcha', 2, 45000, '[]', false, 21),
		(28, 'Mangoli Yumcha', 'Юмча манго', 'Mangolu Yumcha', 2, 45000, '[]', false, 22),
		(29, 'Behi desertisi (Ayva tatlisi)', 'Десерт айва (айва татлиси)', 'Ayva Tatlısı', 2, 28000, '[]', false, 23),
		(30, 'Bananli Maffin', 'Банановый маффин', 'Muzlu Muffin', 2, 25000, '[]', false, 24),
		(31, 'Olchali pirog muzqaymoq bilan', 'Вишнёвый пирог с мороженым', 'Dondurmalı Vişneli Pasta', 2, 55000, '[]', false, 25),
		(32, 'Olchali Chizkeyk', 'Вишнёвый чизкейк', 'Vişneli Cheesecake', 2, 55000, '[]', false, 26),
		(33, 'Ukrupli Pogacha', 'Погача с укропом (дереотлу погача)', 'Dereotlu Poğaça', 2, 9000, '[]', false, 27),
		(34, 'Dubay Trayfli', 'Дубайский трайфл', 'Dubai Trifle', 2, 50000, '[]', false, 28),
		(35, 'Qovoq Tatlisi', 'Тыквенный десерт (ковок татлиси)', 'Kabak Tatlısı', 2, 20000, '[]', false, 29),
		(36, 'Qizil Baxmal Chizkeyk', 'Красный бархат чизкейк', 'Kırmızı Kadife Cheesecake', 2, 55000, '[]', false, 30),
		(37, 'Qizil Trayfl', 'Красный трайфл', 'Kırmızı Trifle', 2, 50000, '[]', false, 31),
		(38, 'Labneli Pogacha', 'Лабнели погача', 'Labneli Poğaça', 2, 10000, '[]', false, 32),
		(39, 'Mangoli Chizkeyk', 'Манго чизкейк', 'Mangolu Cheesecake', 2, 50000, '[]', false, 33),
		(40, 'Milka', 'Милка', 'Milka', 2, 50000, '[]', false, 34),
		(41, 'Mini Chizkeyk Limonli', 'Мини чизкейк лимон', 'Mini Cheesecake Limon', 2, 25000, '[]', false, 35),
		(42, 'Mini Chizkeyk Malinali', 'Мини чизкейк малиновый', 'Mini Cheesecake Ahududulu', 2, 25000, '[]', false, 36),
		(43, 'Mini Chizkeyk Rafaello', 'Мини чизкейк Рафаэлло', 'Mini Cheesecake Rafaello', 2, 25000, '[]', false, 37),
		(44, 'Mini Chizkeyk Snikers', 'Мини чизкейк Сникерс', 'Mini Cheesecake Snickers', 2, 25000, '[]', false, 38),
		(45, 'Mini Chizkeyk Pistali', 'Мини чизкейк фисташковый', 'Mini Cheesecake Fıstıklı', 2, 25000, '[]', false, 39),
		(46, 'Muzqaymoqli Chizkeyk', 'Мороженое чизкейк', 'Dondurmalı Cheesecake', 2, 30000, '[]', false, 40),
		(47, 'Napoleon', 'Наполеон', 'Napolyon Pastası', 2, 50000, '[]', false, 41),
		(48, 'Olmali Maffin', 'Яблочный маффин (олмали маффин)', 'Elmalı Muffin', 2, 25000, '[]', false, 42),
		(49, 'Rafaello Chizkeyk', 'Рафаэлло чизкейк', 'Rafaello Cheesecake', 2, 48000, '[]', false, 43),
		(50, 'San Sebastyan Belgiya Shokoladi bilan', 'Сан Себастьян с бельгийским шоколадом', 'San Sebastian Belçika Çikolatalı', 2, 60000, '[]', false, 44),
		(51, 'San Sebastyan (klassik)', 'Сан Себастьян (классический)', 'San Sebastian (klasik)', 2, 40000, '[]', false, 45),
		(52, 'Turk Muzqaymog''i Pistali', 'Турецкое мороженое с фисташкой', 'Türk Dondurması Fıstıklı', 2, 25000, '[]', false, 46),
		(53, 'Malinali Pistali desert', 'Фисташка с малиной', 'Ahududulu Fıstıklı', 2, 50000, '[]', false, 47),
		(54, 'Pistali Baxmal', 'Фисташковый бархат', 'Fıstıklı Kadife', 2, 55000, '[]', false, 48),
		(55, 'Pistali San Sebastyan', 'Фисташковый сан себастьян', 'Fıstıklı San Sebastian', 2, 70000, '[]', false, 49),
		(56, 'Laym-Qulupnay Chizkeyk', 'Чизкейк лайм-клубника', 'Misket Limonu-Çilek Cheesecake', 2, 50000, '[]', false, 50),
		(57, 'Lotus Chizkeyk', 'Чизкейк Лотус', 'Lotus Cheesecake', 2, 48000, '[]', false, 51),
		(58, 'Mango-Malina Chizkeyk', 'Чизкейк манго-малина', 'Mango-Ahududu Cheesecake', 2, 50000, '[]', false, 52),
		(59, 'Tiramisu Chizkeyk', 'Чизкейк тирамису', 'Tiramisu Cheesecake', 2, 55000, '[]', false, 53),
		(60, 'Shokoladli Maffin', 'Шоколадный маффин', 'Çikolatalı Muffin', 2, 28000, '[]', false, 54),
		(61, 'Shokoladli Baxmal', 'Шоколадный бархат', 'Çikolatalı Kadife', 2, 50000, '[]', false, 55),
		(62, 'Chortoq 0.5L Gazsiz', 'Чортоқ 0.5 л без газа', 'Chortoq 0.5L Gazsız', 3, 5000, '[]', false, 1),
		(63, 'Chortoq 0.33L Limonli', 'Чортоқ 0.33 л лимон', 'Chortoq 0.33L Limonlu', 3, 15000, '[]', false, 2),
		(64, 'Chortoq 0.33L Mineral', 'Чортоқ 0.33 л минеральная', 'Chortoq 0.33L Maden Suyu', 3, 15000, '[]', false, 3),
		(65, 'Chortoq 0.5L Gazli', 'Чортоқ 0.5 л газированная', 'Chortoq 0.5L Gazlı', 3, 5000, '[]', false, 4),
		(66, 'Chortoq 0.5L Mineral', 'Чортоқ 0.5 л минеральная', 'Chortoq 0.5L Maden Suyu', 3, 20000, '[]', false, 5),
		(67, 'Chortoq Premium 0.33L', 'Чортоқ Премиум 0.33 л', 'Chortoq Premium 0.33L', 3, 20000, '[]', false, 6),
		(68, 'Cola Turka', 'Кола Турка', 'Cola Turka', 3, 15000, '[]', false, 7),
		(69, 'Muzli Matcha Qulupnayli', 'Айс матча с клубникой', 'Buzlu Çilekli Matcha', 3, 40000, '[]', false, 8),
		(70, 'Latte Matcha', 'Латте матча', 'Matcha Latte', 3, 40000, '[]', false, 9),
		(71, 'Non ichida Qovurma (Ekmek arasi kavurma)', 'Экмек араси кавурма (сэндвич с кавурмой)', 'Ekmek Arası Kavurma', 4, 80000, '[]', false, 1),
		(72, 'Qovurmali Tuxum', 'Яичница с кавурмой', 'Kavurmalı Yumurta', 4, 110000, '[]', false, 2),
		(73, 'Non', 'Хлеб (нон)', 'Ekmek', 4, 6000, '[]', false, 3),
		(74, 'Nutella', 'Нутелла', 'Nutella', 4, 15000, '[]', false, 4),
		(75, 'Pastirmali Tost', 'Тост с пастырмой', 'Pastırmalı Tost', 4, 90000, '[]', false, 5),
		(76, 'Sigara Buregi', 'Сигара буреги', 'Sigara Böreği', 4, 5000, '[]', false, 6),
		(77, 'Katta Qutu', 'Коробка большая', 'Büyük Kutu', 5, 10000, '[]', false, 1),
		(78, 'Mini Qutu', 'Коробка мини', 'Mini Kutu', 5, 7000, '[]', false, 2),
		(79, 'O''rtacha Qutu', 'Коробка средняя', 'Orta Kutu', 5, 8000, '[]', false, 3),
		(80, 'Mokko', 'Мокко', 'Mocha', 6, 40000, '[]', false, 1),
		(81, 'Zanjabil Choy', 'Имбирный чай', 'Zencefil Çayı', 7, 40000, '[]', false, 1),
		(82, 'Qora Choy', 'Чёрный чай (кора чой)', 'Siyah Çay', 7, 12000, '[]', false, 2),
		(83, 'Ko''k Choy', 'Зелёный чай (кўк чой)', 'Yeşil Çay', 7, 10000, '[]', false, 3),
		(84, 'Limonli Choy', 'Лимонный чай', 'Limonlu Çay', 7, 25000, '[]', false, 4),
		(85, 'Malinali Choy', 'Малиновый чай', 'Ahududu Çayı', 7, 40000, '[]', false, 5),
		(86, 'Shakar', 'Сахар', 'Şeker', 7, 5000, '[]', false, 6),
		(87, 'Turk Choyi', 'Турецкий чай', 'Türk Çayı', 7, 10000, '[]', false, 7),
		(88, 'Turk Choyi Samovar (katta)', 'Турецкий чай самовар (большой)', 'Semaver Türk Çayı (büyük)', 7, 80000, '[]', false, 8),
		(89, 'Turk Choyi Samovar (kichik)', 'Турецкий чай самовар (маленький)', 'Semaver Türk Çayı (küçük)', 7, 50000, '[]', false, 9),
		(90, 'Tinchlantiruvchi Choy', 'Успокаивающий чай', 'Sakinleştirici Çay', 7, 30000, '[]', false, 10),
		(91, 'Meva Choy', 'Ягодный чай', 'Meyve Çayı', 7, 40000, '[]', false, 11),
		(92, 'Paket', 'Пакет', 'Poşet', 8, 6000, '[]', false, 1)`)

	Pool.Exec(ctx, `INSERT INTO zones (id, name, count, sort_order) VALUES (1, 'ZAL', 5, 1), (2, 'TASHQARI', 3, 2)`)

	for i := 1; i <= 5; i++ {
		Pool.Exec(ctx, `INSERT INTO tables (zone_id, sku, number, label, seats, qr_code) VALUES ($1, $2, $3, $4, 4, $5)`,
			1, fmt.Sprintf("1-%d", i), i, fmt.Sprintf("ZAL-%d", i), fmt.Sprintf("https://konak.uz/table/1-%d", i))
	}
	for i := 1; i <= 3; i++ {
		Pool.Exec(ctx, `INSERT INTO tables (zone_id, sku, number, label, seats, qr_code) VALUES ($1, $2, $3, $4, 4, $5)`,
			2, fmt.Sprintf("2-%d", i), i, fmt.Sprintf("TASHQARI-%d", i), fmt.Sprintf("https://konak.uz/table/2-%d", i))
	}

	// Stock yo'q — hamma mahsulot cheksiz (∞)

	Pool.Exec(ctx, `INSERT INTO expense_categories (id, name_uz, name_ru, name_tr, sort_order) VALUES
		(1, 'Ish haqi', 'Зарплата', 'Maaş', 1),
		(2, 'Mahsulotlar', 'Продукты', 'Ürünler', 2),
		(3, 'Kommunal', 'Коммунальные', 'Faturalar', 3)`)

	Pool.Exec(ctx, "SELECT setval('users_id_seq', (SELECT MAX(id) FROM users))")
	Pool.Exec(ctx, "SELECT setval('categories_id_seq', (SELECT MAX(id) FROM categories))")
	Pool.Exec(ctx, "SELECT setval('products_id_seq', (SELECT MAX(id) FROM products))")
	Pool.Exec(ctx, "SELECT setval('zones_id_seq', (SELECT MAX(id) FROM zones))")
	Pool.Exec(ctx, "SELECT setval('expense_categories_id_seq', (SELECT MAX(id) FROM expense_categories))")

	log.Println("Seed data inserted")
}
