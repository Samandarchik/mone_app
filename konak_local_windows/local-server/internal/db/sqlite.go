package db

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5/pgxpool"
)

var Pool *pgxpool.Pool

func Init(dbURL string) error {
	var err error
	Pool, err = pgxpool.New(context.Background(), dbURL)
	if err != nil {
		return err
	}
	if err := Pool.Ping(context.Background()); err != nil {
		return err
	}
	log.Println("PostgreSQL connected")
	return runMigrations()
}

func Close() {
	if Pool != nil {
		Pool.Close()
	}
}
