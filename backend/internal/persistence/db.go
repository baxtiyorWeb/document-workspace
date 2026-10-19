package persistence

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DB wraps the pgxpool connection.
type DB struct {
	Pool *pgxpool.Pool
}

// NewDB initializes a connection pool to PostgreSQL.
func NewDB(ctx context.Context, databaseURL string) (*DB, error) {
	if databaseURL == "" {
		return nil, fmt.Errorf("database URL is empty")
	}

	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse database configuration: %w", err)
	}

	// Optimize connection pool for serverless / Neon / containerized setups
	config.MaxConns = 25
	config.MinConns = 0
	config.MaxConnLifetime = 1 * time.Hour
	config.MaxConnIdleTime = 15 * time.Minute
	config.HealthCheckPeriod = 1 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Verify connection with retry for serverless wake-up (Neon cold start can take 15-25s)
	var lastErr error
	const maxAttempts = 5
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		pingCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		err = pool.Ping(pingCtx)
		cancel()
		if err == nil {
			log.Println("[INFO] Successfully connected to PostgreSQL database")
			return &DB{Pool: pool}, nil
		}
		lastErr = err
		log.Printf("[WARN] Attempt %d/%d to connect to database failed: %v. Retrying in 3s...", attempt, maxAttempts, err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(3 * time.Second):
		}
	}

	return nil, fmt.Errorf("failed to connect to database after %d attempts: %w", maxAttempts, lastErr)
}

// Close closes the database connection pool.
func (db *DB) Close() {
	if db.Pool != nil {
		db.Pool.Close()
	}
}

// Ping checks database health.
func (db *DB) Ping(ctx context.Context) error {
	if db == nil || db.Pool == nil {
		return fmt.Errorf("database is not connected")
	}
	return db.Pool.Ping(ctx)
}

// AutoMigrate applies the base schema if tables do not exist.
func (db *DB) AutoMigrate(ctx context.Context, schemaSQL string) error {
	if db == nil || db.Pool == nil {
		return fmt.Errorf("database is not connected")
	}
	_, err := db.Pool.Exec(ctx, schemaSQL)
	if err != nil {
		return fmt.Errorf("failed to execute migration schema: %w", err)
	}
	log.Println("[INFO] Database schema migration executed successfully")
	return nil
}
