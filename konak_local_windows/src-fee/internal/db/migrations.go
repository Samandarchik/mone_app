package db

import "context"

func runMigrations() error {
	ctx := context.Background()
	migrations := []string{
		`CREATE TABLE IF NOT EXISTS categories (
			id SERIAL PRIMARY KEY,
			name_uz TEXT NOT NULL DEFAULT '',
			name_ru TEXT NOT NULL DEFAULT '',
			name_tr TEXT NOT NULL DEFAULT '',
			icon TEXT NOT NULL DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS products (
			id SERIAL PRIMARY KEY,
			name_uz TEXT NOT NULL DEFAULT '',
			name_ru TEXT NOT NULL DEFAULT '',
			name_tr TEXT NOT NULL DEFAULT '',
			description_uz TEXT,
			description_ru TEXT,
			description_tr TEXT,
			category_id INTEGER NOT NULL REFERENCES categories(id),
			price INTEGER NOT NULL DEFAULT 0,
			old_price INTEGER,
			media JSONB NOT NULL DEFAULT '[]',
			status TEXT NOT NULL DEFAULT 'active',
			is_recommended BOOLEAN NOT NULL DEFAULT false,
			availability JSONB,
			ingredients JSONB,
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS zones (
			id SERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			count INTEGER NOT NULL DEFAULT 0,
			sort_order INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS tables (
			id SERIAL PRIMARY KEY,
			zone_id INTEGER NOT NULL REFERENCES zones(id),
			sku TEXT NOT NULL UNIQUE,
			number INTEGER NOT NULL,
			label TEXT NOT NULL,
			seats INTEGER NOT NULL DEFAULT 4,
			status TEXT NOT NULL DEFAULT 'free',
			qr_code TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS orders (
			id SERIAL PRIMARY KEY,
			order_number TEXT NOT NULL UNIQUE,
			type TEXT NOT NULL,
			table_sku TEXT,
			table_id INTEGER,
			zone_id INTEGER,
			delivery JSONB,
			items JSONB NOT NULL DEFAULT '[]',
			subtotal INTEGER NOT NULL DEFAULT 0,
			service_fee INTEGER NOT NULL DEFAULT 0,
			delivery_fee INTEGER NOT NULL DEFAULT 0,
			discount INTEGER NOT NULL DEFAULT 0,
			total INTEGER NOT NULL DEFAULT 0,
			payment_method TEXT,
			payment_status TEXT NOT NULL DEFAULT 'unpaid',
			status TEXT NOT NULL DEFAULT 'new',
			source TEXT NOT NULL DEFAULT 'pos',
			created_by INTEGER,
			customer_name TEXT,
			customer_phone TEXT,
			note TEXT,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS stocks (
			product_id INTEGER PRIMARY KEY,
			count INTEGER NOT NULL DEFAULT 0,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			phone TEXT NOT NULL UNIQUE,
			role TEXT NOT NULL,
			pin TEXT NOT NULL,
			custom_permissions JSONB,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS shifts (
			id SERIAL PRIMARY KEY,
			date TEXT NOT NULL,
			opened_by JSONB NOT NULL DEFAULT '{}',
			opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			opening_cash INTEGER NOT NULL DEFAULT 0,
			closed_by JSONB,
			closed_at TIMESTAMPTZ,
			closing_cash INTEGER,
			status TEXT NOT NULL DEFAULT 'open',
			summary JSONB
		)`,
		`CREATE TABLE IF NOT EXISTS expense_categories (
			id SERIAL PRIMARY KEY,
			name_uz TEXT NOT NULL DEFAULT '',
			name_ru TEXT NOT NULL DEFAULT '',
			name_tr TEXT NOT NULL DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active',
			created_by INTEGER,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS expenses (
			id SERIAL PRIMARY KEY,
			category_id INTEGER NOT NULL REFERENCES expense_categories(id),
			amount INTEGER NOT NULL DEFAULT 0,
			description TEXT NOT NULL DEFAULT '',
			date TEXT NOT NULL,
			created_by JSONB NOT NULL DEFAULT '{}',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS table_locks (
			table_sku TEXT PRIMARY KEY,
			user_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			role TEXT NOT NULL,
			source TEXT NOT NULL,
			locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS qr_sessions (
			id SERIAL PRIMARY KEY,
			order_number TEXT,
			table_sku TEXT NOT NULL,
			token TEXT NOT NULL UNIQUE,
			pin_code TEXT NOT NULL,
			pin_time TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			closed_at TIMESTAMPTZ
		)`,
		`ALTER TABLE qr_sessions ALTER COLUMN pin_code DROP NOT NULL`,
		`ALTER TABLE qr_sessions ALTER COLUMN pin_time DROP NOT NULL`,
		`ALTER TABLE qr_sessions ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ`,
		`ALTER TABLE qr_sessions ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ`,
		`ALTER TABLE qr_sessions ADD COLUMN IF NOT EXISTS call_waiter_at TIMESTAMPTZ`,
		`ALTER TABLE qr_sessions ADD COLUMN IF NOT EXISTS bill_requested_at TIMESTAMPTZ`,
		`CREATE INDEX IF NOT EXISTS idx_qr_sessions_active ON qr_sessions(token,status,expires_at)`,
		`CREATE TABLE IF NOT EXISTS menu_version (
			id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
			version INTEGER NOT NULL DEFAULT 1,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`INSERT INTO menu_version (id, version) VALUES (1, 1) ON CONFLICT (id) DO NOTHING`,
		`CREATE TABLE IF NOT EXISTS sync_queue (
			id SERIAL PRIMARY KEY,
			event_type TEXT NOT NULL,
			payload JSONB NOT NULL DEFAULT '{}',
			status TEXT NOT NULL DEFAULT 'pending',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			synced_at TIMESTAMPTZ,
			retry_count INTEGER NOT NULL DEFAULT 0
		)`,
		// Printer stations
		`CREATE TABLE IF NOT EXISTS printer_stations (
			id SERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			address TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS printer_station_id INTEGER REFERENCES printer_stations(id)`,
		`ALTER TABLE products ADD COLUMN IF NOT EXISTS printer_station_id INTEGER REFERENCES printer_stations(id)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_date ON orders(created_at)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_table ON orders(table_sku)`,
		`CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)`,
		// ---- Sync: multi-master envelope + idempotentlik (2026-07) ----
		// event_id Go tomonida (crypto/rand) generatsiya qilinadi — DB funksiyasiga
		// (gen_random_uuid/pgcrypto) bog'liqlik yo'q, har qanday PG versiyada ishlaydi.
		`ALTER TABLE sync_queue ADD COLUMN IF NOT EXISTS event_id TEXT`,
		`ALTER TABLE sync_queue ADD COLUMN IF NOT EXISTS origin TEXT`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_event_id ON sync_queue(event_id)`,
		// Qo'llangan eventlar — replay xavfsiz (idempotentlik)
		`CREATE TABLE IF NOT EXISTS sync_applied (
			event_id TEXT PRIMARY KEY,
			origin TEXT,
			event_type TEXT,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_pin_unique ON users(pin) WHERE status = 'active'`,
		// PINning o'zi saqlanmaydi: pin = HMAC lookup fingerprint,
		// pin_hash = salted PBKDF2. Eski ochiq PIN login paytida avtomatik ko'chadi.
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_hash TEXT NOT NULL DEFAULT ''`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ`,
		// pin_sync — PINning SYNC_TOKEN bilan shifrlangan nusxasi.
		// NEGA KERAK: pin/pin_hash har node'ning O'Z PIN_PEPPER'iga bog'liq,
		// ularni ko'chirib bo'lmaydi. Ilgari PIN faqat `user:*` eventida bir
		// marta uzatilardi — event yo'qolsa yoki keyin to'liq resync qilinsa
		// xodim ikkinchi node'da PINsiz qolardi. Endi PIN qator bilan birga
		// ko'chadi va qabul qiluvchi uni O'Z pepperi bilan qayta hisoblaydi.
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_sync TEXT NOT NULL DEFAULT ''`,

		// Barcha muhim HTTP o'zgarishlarining markaziy audit jurnali.
		`CREATE TABLE IF NOT EXISTS audit_logs (
			id BIGSERIAL PRIMARY KEY,
			actor_id INTEGER,
			actor_name TEXT NOT NULL DEFAULT '',
			actor_role TEXT NOT NULL DEFAULT '',
			action TEXT NOT NULL,
			entity_type TEXT NOT NULL,
			entity_id TEXT NOT NULL DEFAULT '',
			request_data JSONB NOT NULL DEFAULT '{}',
			response_data JSONB NOT NULL DEFAULT '{}',
			metadata JSONB NOT NULL DEFAULT '{}',
			ip_address TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id, created_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id, created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS backups (
			id BIGSERIAL PRIMARY KEY,
			filename TEXT NOT NULL DEFAULT '',
			size_bytes BIGINT NOT NULL DEFAULT 0,
			checksum TEXT NOT NULL DEFAULT '',
			trigger TEXT NOT NULL DEFAULT 'automatic',
			status TEXT NOT NULL,
			error_message TEXT NOT NULL DEFAULT '',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_backups_created ON backups(created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS order_daily_counters (
			business_date DATE PRIMARY KEY,
			last_value BIGINT NOT NULL DEFAULT 0
		)`,

		// CRM: mijoz profili, sodiqlik ballari va promo-kodlar.
		`CREATE TABLE IF NOT EXISTS customers (
			id BIGSERIAL PRIMARY KEY,
			phone TEXT NOT NULL UNIQUE,
			name TEXT NOT NULL DEFAULT '',
			birthday DATE,
			gender TEXT NOT NULL DEFAULT '',
			tags JSONB NOT NULL DEFAULT '[]',
			notes TEXT NOT NULL DEFAULT '',
			loyalty_points BIGINT NOT NULL DEFAULT 0,
			total_spent BIGINT NOT NULL DEFAULT 0,
			visit_count INTEGER NOT NULL DEFAULT 0,
			last_visit_at TIMESTAMPTZ,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(LOWER(name))`,
		`CREATE INDEX IF NOT EXISTS idx_customers_last_visit ON customers(last_visit_at DESC)`,
		`CREATE TABLE IF NOT EXISTS loyalty_transactions (
			id BIGSERIAL PRIMARY KEY,
			customer_id BIGINT NOT NULL REFERENCES customers(id),
			order_number TEXT NOT NULL DEFAULT '',
			type TEXT NOT NULL,
			points BIGINT NOT NULL,
			balance_after BIGINT NOT NULL,
			note TEXT NOT NULL DEFAULT '',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_loyalty_customer ON loyalty_transactions(customer_id,created_at DESC)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_loyalty_order_earn
		 ON loyalty_transactions(order_number,type)
		 WHERE order_number<>'' AND type='earn'`,
		`CREATE TABLE IF NOT EXISTS promo_codes (
			id BIGSERIAL PRIMARY KEY,
			code TEXT NOT NULL UNIQUE,
			discount_type TEXT NOT NULL,
			value INTEGER NOT NULL,
			min_order_total INTEGER NOT NULL DEFAULT 0,
			max_discount INTEGER,
			starts_at TIMESTAMPTZ,
			ends_at TIMESTAMPTZ,
			usage_limit INTEGER,
			used_count INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_promo_codes_active ON promo_codes(status,starts_at,ends_at)`,
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id BIGINT REFERENCES customers(id)`,
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS promo_code TEXT`,
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS loyalty_points_earned BIGINT NOT NULL DEFAULT 0`,
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS loyalty_points_redeemed BIGINT NOT NULL DEFAULT 0`,
		`CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id,created_at DESC)`,

		// Online (saboy / dostafka) — Telegram verification
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS tg_user_id BIGINT`,
		`CREATE TABLE IF NOT EXISTS online_verifications (
			id SERIAL PRIMARY KEY,
			code TEXT NOT NULL UNIQUE,
			pending_token TEXT NOT NULL UNIQUE,
			verification_token TEXT UNIQUE,
			status TEXT NOT NULL DEFAULT 'pending',
			tg_user_id BIGINT,
			tg_username TEXT,
			phone TEXT,
			location_lat DOUBLE PRECISION,
			location_lng DOUBLE PRECISION,
			note TEXT,
			used_for_order_number TEXT,
			expires_at TIMESTAMPTZ NOT NULL,
			confirmed_at TIMESTAMPTZ,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_online_verif_token ON online_verifications(verification_token)`,
		`CREATE INDEX IF NOT EXISTS idx_online_verif_tg ON online_verifications(tg_user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_online_verif_status ON online_verifications(status, expires_at)`,

		// Spisaniya / inventarizatsiya / smena qoldiq surati
		`CREATE TABLE IF NOT EXISTS write_offs (
			id SERIAL PRIMARY KEY,
			product_id INTEGER NOT NULL,
			qty INTEGER NOT NULL,
			reason TEXT NOT NULL,
			note TEXT,
			created_by INTEGER,
			created_by_name TEXT,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS inventory_corrections (
			id SERIAL PRIMARY KEY,
			product_id INTEGER NOT NULL,
			old_count INTEGER,
			new_count INTEGER NOT NULL,
			created_by INTEGER,
			created_by_name TEXT,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS shift_stock_snapshots (
			shift_id INTEGER NOT NULL,
			product_id INTEGER NOT NULL,
			count INTEGER NOT NULL,
			PRIMARY KEY (shift_id, product_id)
		)`,

		// Aralash to'lov (split payment) — chek 2-3 usul bilan yopilganda taqsimot:
		// [{"method":"cash","amount":10000},{"method":"click","amount":1904000}]
		// Oddiy (bitta usul) to'lovda NULL bo'lib qoladi.
		`ALTER TABLE orders ADD COLUMN IF NOT EXISTS payments JSONB`,

		// Sozlamalar (key/value) — cloud sync URL/token shu yerda saqlanadi
		`CREATE TABLE IF NOT EXISTS settings (
			key TEXT PRIMARY KEY,
			value TEXT NOT NULL DEFAULT '',
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,

		// ============ OMBOR (ingredientlar) ============
		// Hamma miqdor — saqlash birligida BUTUN son: kg→gr, l→ml (float taqiqlangan).
		`CREATE TABLE IF NOT EXISTS ingredients (
			id SERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			unit TEXT NOT NULL DEFAULT 'gr',
			count BIGINT NOT NULL DEFAULT 0,
			min_qty BIGINT NOT NULL DEFAULT 0,
			waste_percent INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		// Har bir harakat (100% hisob): kirim | pishirish | korreksiya | spisaniye | qaytarildi
		`CREATE TABLE IF NOT EXISTS ing_moves (
			id SERIAL PRIMARY KEY,
			ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
			qty BIGINT NOT NULL,
			reason TEXT NOT NULL,
			ref TEXT NOT NULL DEFAULT '',
			comment TEXT NOT NULL DEFAULT '',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_ing_moves_ing ON ing_moves(ingredient_id, id DESC)`,

		// ============ BOZOR XARIDI ============
		`CREATE TABLE IF NOT EXISTS purchases (
			id SERIAL PRIMARY KEY,
			note TEXT NOT NULL DEFAULT '',
			total BIGINT NOT NULL DEFAULT 0,
			expense_id INTEGER,
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS purchase_items (
			id SERIAL PRIMARY KEY,
			purchase_id INTEGER NOT NULL REFERENCES purchases(id),
			ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
			qty BIGINT NOT NULL,
			subtotal BIGINT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_purchase_items_ing ON purchase_items(ingredient_id, id DESC)`,

		// ============ RETSEPT (partiya asosida) ============
		// items: [{"ingredient_id":1,"name":"Un","unit":"gr","amount":2000}] — amount BUTUN PARTIYA uchun
		`CREATE TABLE IF NOT EXISTS recipes (
			product_id INTEGER PRIMARY KEY REFERENCES products(id),
			batch_qty INTEGER NOT NULL DEFAULT 1,
			items JSONB NOT NULL DEFAULT '[]',
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,

		// ============ PISHIRISH ============
		// ingredients: boshlanganda kamaytirilgan miqdorlar surati (bekorda shu qaytadi)
		`CREATE TABLE IF NOT EXISTS cookings (
			id SERIAL PRIMARY KEY,
			product_id INTEGER NOT NULL,
			product_name TEXT NOT NULL DEFAULT '',
			qty INTEGER NOT NULL,
			status TEXT NOT NULL DEFAULT 'cooking',
			ingredients JSONB NOT NULL DEFAULT '[]',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			done_at TIMESTAMPTZ
		)`,
		// Pishirish limiti: count < limit_qty bo'lsa "pishirish kerak" ro'yxatiga tushadi
		`ALTER TABLE stocks ADD COLUMN IF NOT EXISTS limit_qty INTEGER NOT NULL DEFAULT 0`,

		// Mahsulot turi: 'cooked' = tayyorlanadi (retsept shart, masalan tort),
		// 'ready' = tayyor keladi, o'zi sotiladi (masalan Chortoq suvi)
		`ALTER TABLE products ADD COLUMN IF NOT EXISTS product_type TEXT NOT NULL DEFAULT 'cooked'`,

		// HAMMA mahsulot kuzatiladi: qoldiq 0 dan boshlanadi, bazaga
		// qo'shilgandagina (pishirildi/kirim) POS'da sotuvga chiqadi
		`INSERT INTO stocks (product_id, count)
		 SELECT id, 0 FROM products WHERE id NOT IN (SELECT product_id FROM stocks)`,

		// Yetkazib beruvchilar va ingredient kirim partiyalari (FIFO).
		`CREATE TABLE IF NOT EXISTS suppliers (
			id BIGSERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			phone TEXT NOT NULL DEFAULT '',
			address TEXT NOT NULL DEFAULT '',
			notes TEXT NOT NULL DEFAULT '',
			status TEXT NOT NULL DEFAULT 'active',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`ALTER TABLE purchases ADD COLUMN IF NOT EXISTS supplier_id BIGINT REFERENCES suppliers(id)`,
		`ALTER TABLE purchases ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`,
		`CREATE TABLE IF NOT EXISTS ingredient_batches (
			id BIGSERIAL PRIMARY KEY,
			ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
			supplier_id BIGINT REFERENCES suppliers(id),
			purchase_item_id INTEGER REFERENCES purchase_items(id),
			batch_code TEXT NOT NULL DEFAULT '',
			received_qty BIGINT NOT NULL,
			remaining_qty BIGINT NOT NULL,
			total_cost BIGINT NOT NULL DEFAULT 0,
			received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			status TEXT NOT NULL DEFAULT 'active',
			note TEXT NOT NULL DEFAULT '',
			created_by TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_batches_fifo
		 ON ingredient_batches(ingredient_id,received_at,id)
		 WHERE status='active' AND remaining_qty>0`,
		`CREATE INDEX IF NOT EXISTS idx_batches_supplier
		 ON ingredient_batches(supplier_id,received_at DESC)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_batches_purchase_item
		 ON ingredient_batches(purchase_item_id)
		 WHERE purchase_item_id IS NOT NULL`,
		`CREATE TABLE IF NOT EXISTS ing_batch_moves (
			id BIGSERIAL PRIMARY KEY,
			batch_id BIGINT NOT NULL REFERENCES ingredient_batches(id),
			ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
			qty BIGINT NOT NULL,
			reason TEXT NOT NULL,
			ref TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_batch_moves_ref ON ing_batch_moves(ref,id DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_batch_moves_batch ON ing_batch_moves(batch_id,id DESC)`,

		// `updated_at` — node'lararo "kim oxirgi yozdi" (last-write-wins)
		// qoidasi shu ustunga tayanadi (internal/sync/replication.go).
		// Ustunsiz jadvalda kechikib kelgan ESKI event yangi holatni bosib
		// ketardi: masalan cloud'da eski nom bilan turgan kategoriya kassada
		// tuzatilgan nomni qaytarib yuborardi.
		`ALTER TABLE categories ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`,
		`ALTER TABLE zones ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`,
		`ALTER TABLE tables ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`,

		// Smena/moliya hisoboti har safar shu shartlar bo'yicha 8 ta so'rov
		// yuboradi (buildInitOK, broadcastShiftStats, /api/shift/current,
		// /api/finance/daily). Indekssiz har biri butun `orders` jadvalini
		// to'liq skanerlaydi — chek soni o'sgani sari kassa sekinlashadi.
		`CREATE INDEX IF NOT EXISTS idx_orders_paid_created
		 ON orders(created_at) WHERE status = 'completed' AND payment_status = 'paid'`,
		`CREATE INDEX IF NOT EXISTS idx_orders_active
		 ON orders(table_sku) WHERE status NOT IN ('completed','cancelled')`,
		`CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)`,
		`CREATE INDEX IF NOT EXISTS idx_loyalty_tx_order ON loyalty_transactions(order_number)`,

		// Bir vaqtda faqat BITTA ochiq smena. Ilgari "ochiq smena bormi?"
		// tekshiruvi va INSERT alohida edi: ikki kassir bir vaqtda smena
		// ochsa (yoki ikki marta bosilsa) ikkita ochiq smena tug'ilardi.
		// Keyin `WHERE status='open' LIMIT 1` ularning tasodifiy birini
		// olardi — ikkinchisi ko'rinmas bo'lib qolib, hech qachon
		// yopilmasdi va butun kunlik hisob chalkashardi.
		//
		// Eski bazada allaqachon ikkita ochiq smena bo'lsa indeks yaratilmay
		// server ko'tarilmay qolardi — shuning uchun avval eskisi yopiladi.
		`UPDATE shifts SET status='closed', closed_at=COALESCE(closed_at, NOW())
		  WHERE status='open' AND id < (SELECT MAX(id) FROM shifts WHERE status='open')`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_single_open
		 ON shifts((status)) WHERE status = 'open'`,
	}

	for _, m := range migrations {
		if _, err := Pool.Exec(ctx, m); err != nil {
			return err
		}
	}
	return nil
}
