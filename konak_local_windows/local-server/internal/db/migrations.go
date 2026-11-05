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
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_pin_unique ON users(pin) WHERE status = 'active'`,

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
	}

	for _, m := range migrations {
		if _, err := Pool.Exec(ctx, m); err != nil {
			return err
		}
	}
	return nil
}
