package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"ai-chat-backend/internal/config"
	"ai-chat-backend/internal/persistence"
)

func main() {
	cfg := config.Load()
	ctx := context.Background()

	db, err := persistence.NewDB(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	sqlBytes, err := os.ReadFile("migrations/000002_gateway_and_billing.up.sql")
	if err != nil {
		log.Fatalf("Failed to read migration: %v", err)
	}

	if _, err := db.Pool.Exec(ctx, string(sqlBytes)); err != nil {
		log.Fatalf("Failed to execute migration: %v", err)
	}

	fmt.Println("Migration 000002 applied successfully to PostgreSQL database!")
}
