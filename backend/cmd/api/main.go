package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"ai-chat-backend/internal/ai"
	"ai-chat-backend/internal/auth"
	"ai-chat-backend/internal/billing"
	"ai-chat-backend/internal/config"
	"ai-chat-backend/internal/conversations"
	"ai-chat-backend/internal/files"
	"ai-chat-backend/internal/gateway"
	"ai-chat-backend/internal/generations"
	"ai-chat-backend/internal/http/handlers"
	"ai-chat-backend/internal/messages"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/persistence"
	"ai-chat-backend/internal/plans"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

// Embedded base schema fallback if migrations folder is loaded or directly run
const initialSchemaSQL = `
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(120) NOT NULL DEFAULT '',
    plan_id VARCHAR(32) NOT NULL DEFAULT 'free',
    status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users (LOWER(email));
CREATE INDEX IF NOT EXISTS idx_users_plan_id ON users(plan_id);

CREATE TABLE IF NOT EXISTS refresh_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    user_agent TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_refresh_sessions_user_id ON refresh_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_sessions_token_hash ON refresh_sessions(token_hash);

CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL DEFAULT 'Yangi suhbat',
    category VARCHAR(64) NOT NULL DEFAULT 'general',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_conversations_user_last_msg ON conversations(user_id, last_message_at DESC);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(32) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'streaming', 'completed', 'failed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at ASC);

CREATE TABLE IF NOT EXISTS generations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    provider VARCHAR(64) NOT NULL DEFAULT 'openrouter',
    model VARCHAR(128) NOT NULL DEFAULT 'nemotron-ultra',
    prompt_tokens INT DEFAULT 0,
    completion_tokens INT DEFAULT 0,
    total_tokens INT DEFAULT 0,
    error_code VARCHAR(64),
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_generations_conversation ON generations(conversation_id);

CREATE TABLE IF NOT EXISTS plans (
    id VARCHAR(32) PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    daily_requests INT NOT NULL DEFAULT 40,
    monthly_tokens BIGINT NOT NULL DEFAULT 100000,
    max_input_tokens INT NOT NULL DEFAULT 4000,
    max_output_tokens INT NOT NULL DEFAULT 1024,
    max_active_streams INT NOT NULL DEFAULT 1,
    allowed_models TEXT[] NOT NULL DEFAULT '{}',
    price_usd_cents INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS models (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    provider VARCHAR(64) NOT NULL DEFAULT 'openrouter',
    provider_model_id VARCHAR(128) NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_plans TEXT[] NOT NULL DEFAULT '{"free","pro"}',
    max_context_tokens INT NOT NULL DEFAULT 8192,
    max_output_tokens INT NOT NULL DEFAULT 2048,
    input_price_per_million_usd NUMERIC(10,4) NOT NULL DEFAULT 0,
    output_price_per_million_usd NUMERIC(10,4) NOT NULL DEFAULT 0,
    is_free_tier BOOLEAN NOT NULL DEFAULT FALSE,
    is_reasoning BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lemon_subscription_id VARCHAR(100) UNIQUE,
    provider VARCHAR(32) NOT NULL DEFAULT 'revenuecat',
    original_transaction_id VARCHAR(128) UNIQUE,
    revenuecat_app_user_id VARCHAR(128),
    product_id VARCHAR(128),
    store VARCHAR(32) DEFAULT 'play_store',
    environment VARCHAR(32) DEFAULT 'PRODUCTION',
    raw_data JSONB DEFAULT '{}',
    plan_id VARCHAR(32) NOT NULL DEFAULT 'pro' REFERENCES plans(id),
    status VARCHAR(32) NOT NULL CHECK (status IN ('active', 'on_trial', 'paused', 'past_due', 'unpaid', 'cancelled', 'expired', 'pending_verification')),
    renews_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    customer_portal_url TEXT,
    test_mode BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE subscriptions ALTER COLUMN lemon_subscription_id DROP NOT NULL;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS provider VARCHAR(32) NOT NULL DEFAULT 'revenuecat';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS original_transaction_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS revenuecat_app_user_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS product_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS store VARCHAR(32) DEFAULT 'play_store';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS environment VARCHAR(32) DEFAULT 'PRODUCTION';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS raw_data JSONB DEFAULT '{}';
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
ALTER TABLE subscriptions ADD CONSTRAINT subscriptions_status_check CHECK (status IN ('active', 'on_trial', 'paused', 'past_due', 'unpaid', 'cancelled', 'expired', 'pending_verification'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_rc_orig_trans_id ON subscriptions(original_transaction_id) WHERE original_transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS usage_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    generation_id UUID REFERENCES generations(id) ON DELETE SET NULL,
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    model_id VARCHAR(64) NOT NULL,
    plan_id VARCHAR(32) NOT NULL,
    input_tokens INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    estimated_cost_usd NUMERIC(10,6) NOT NULL DEFAULT 0,
    actual_cost_usd NUMERIC(10,6) NOT NULL DEFAULT 0,
    status VARCHAR(32) NOT NULL CHECK (status IN ('reserved', 'settled', 'released', 'failed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(100) UNIQUE NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Tiered Usage Limits and Multimodal Schema
ALTER TABLE plans ADD COLUMN IF NOT EXISTS hourly_requests INT NOT NULL DEFAULT 15;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS weekly_requests INT NOT NULL DEFAULT 200;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_file_size_bytes BIGINT NOT NULL DEFAULT 10485760;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_files_per_request INT NOT NULL DEFAULT 2;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_vision BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_document_rag BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_media BOOLEAN NOT NULL DEFAULT FALSE;

INSERT INTO plans (
    id, name, description, 
    hourly_requests, daily_requests, weekly_requests, monthly_tokens, 
    max_input_tokens, max_output_tokens, max_active_streams, 
    max_file_size_bytes, max_files_per_request,
    allows_vision, allows_document_rag, allows_media,
    allowed_models, price_usd_cents, is_active
)
VALUES 
(
    'free', 'Bepul (Free)', 'Soatiga 15 ta, kuniga 40 ta so''rov, 10MB hujjatlar va tejamkor modellar', 
    15, 40, 200, 500000, 4000, 1024, 1, 10485760, 2, TRUE, TRUE, FALSE, 
    '{"nemotron-ultra","cohere-code","gpt-4o-mini"}', 0, TRUE
),
(
    'pro', 'Pro Obuna ($9.99/oy)', 'Soatiga 60 ta, kuniga 400 ta so''rov, 50MB fayllar, GPT-4o, Claude 3.5 va 32k kontekst', 
    60, 400, 2000, 10000000, 32000, 4096, 3, 52428800, 5, TRUE, TRUE, TRUE, 
    '{"nemotron-ultra","cohere-code","gpt-4o-mini","gpt-4o","claude-3-5-sonnet","deepseek-r1","llama-70b"}', 999, TRUE
),
(
    'ultra', 'Ultra Obuna ($24.99/oy)', 'Cheksiz imkoniyatlar: soatiga 180 ta, kuniga 1200 ta so''rov, 200MB fayllar, to''liq multimodal va eng yuqori navbat', 
    180, 1200, 6000, 30000000, 128000, 8192, 6, 209715200, 10, TRUE, TRUE, TRUE, 
    '{"nemotron-ultra","cohere-code","gpt-4o-mini","gpt-4o","claude-3-5-sonnet","deepseek-r1","llama-70b","gemini-1-5-pro"}', 2499, TRUE
)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    hourly_requests = EXCLUDED.hourly_requests,
    daily_requests = EXCLUDED.daily_requests,
    weekly_requests = EXCLUDED.weekly_requests,
    monthly_tokens = EXCLUDED.monthly_tokens,
    max_input_tokens = EXCLUDED.max_input_tokens,
    max_output_tokens = EXCLUDED.max_output_tokens,
    max_active_streams = EXCLUDED.max_active_streams,
    max_file_size_bytes = EXCLUDED.max_file_size_bytes,
    max_files_per_request = EXCLUDED.max_files_per_request,
    allows_vision = EXCLUDED.allows_vision,
    allows_document_rag = EXCLUDED.allows_document_rag,
    allows_media = EXCLUDED.allows_media,
    allowed_models = EXCLUDED.allowed_models,
    price_usd_cents = EXCLUDED.price_usd_cents;

ALTER TABLE models ADD COLUMN IF NOT EXISTS is_vision BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE models ADD COLUMN IF NOT EXISTS is_multimodal BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE models SET is_vision = TRUE, is_multimodal = TRUE WHERE id IN ('gpt-4o', 'gpt-4o-mini', 'claude-3-5-sonnet');

CREATE TABLE IF NOT EXISTS files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    file_type VARCHAR(32) NOT NULL,
    mime_type VARCHAR(128) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    sha256_hash VARCHAR(64) NOT NULL,
    storage_path TEXT NOT NULL,
    extracted_text TEXT,
    chunk_count INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS file_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    chunk_index INT NOT NULL,
    page_number INT,
    section_title VARCHAR(255),
    content TEXT NOT NULL,
    token_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS media_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    job_type VARCHAR(32) NOT NULL,
    progress_percent INT NOT NULL DEFAULT 0,
    result_text TEXT,
    error_message TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS message_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reason VARCHAR(64) NOT NULL,
    comment TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_message_reports_user_id ON message_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reports_message_id ON message_reports(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reports_status ON message_reports(status);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS attached_file_ids UUID[] DEFAULT '{}';
`

func main() {
	cfg := config.Load()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 1. Initialize Database
	if cfg.DatabaseURL == "" {
		log.Fatalf("[FATAL] DATABASE_URL is not set in configuration or .env")
	}

	db, err := persistence.NewDB(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("[FATAL] Database initialization failed: %v", err)
	}
	defer db.Close()

	// Automatically apply base schema on startup
	if err := db.AutoMigrate(ctx, initialSchemaSQL); err != nil {
		log.Printf("[WARN] AutoMigrate warning: %v", err)
	}

	// 2. Initialize AI Provider
	aiProvider := ai.NewOpenAICompatibleProvider(
		cfg.AIBaseURL,
		cfg.AIAPIKey,
		cfg.AIModel,
		cfg.AISystemPrompt,
		cfg.AIMaxTokens,
		cfg.AITemperature,
	)

	// 3. Initialize Services
	authService := auth.NewService(db.Pool, cfg.JWTSecret, cfg.JWTAccessExpiry, cfg.JWTRefreshExpiry)
	convService := conversations.NewService(db.Pool)
	msgService := messages.NewService(db.Pool)
	plansService := plans.NewService(db.Pool)
	modelRegistry := gateway.NewModelRegistry(db.Pool)
	gatewayRouter := gateway.NewRouter(modelRegistry)
	quotaService := gateway.NewQuotaService(db.Pool)

	revenueCatHandler := billing.NewRevenueCatHandler(db.Pool, cfg.RevenueCatWebhookAuthToken, cfg.AndroidPackageName)
	filesService := files.NewService(db.Pool, "./storage/uploads")

	genService := generations.NewService(
		db.Pool,
		aiProvider,
		msgService,
		plansService,
		filesService,
		gatewayRouter,
		quotaService,
	)

	// 4. Initialize Handlers
	authHandler := handlers.NewAuthHandler(authService)
	convHandler := handlers.NewConversationHandler(convService)
	msgHandler := handlers.NewMessageHandler(msgService)
	genHandler := handlers.NewGenerationHandler(genService)
	plansHandler := handlers.NewPlansHandler(plansService)
	modelsHandler := handlers.NewModelsHandler(modelRegistry, plansService)
	billingHandler := handlers.NewBillingHandler(revenueCatHandler, plansService, db.Pool)
	filesHandler := handlers.NewFilesHandler(filesService, plansService)
	healthHandler := handlers.NewHealthHandler(db)

	authenticator := middleware.NewAuthenticator(cfg.JWTSecret)

	// 5. Setup Router
	r := chi.NewRouter()

	// Global Middlewares
	r.Use(middleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(chimiddleware.Recoverer)
	// CORS Configuration (SEC-07: Respect AllowedOrigins, disallow wildcard origin with credentials)
	var allowedOrigins []string
	if cfg.AllowedOrigins == "*" || cfg.AllowedOrigins == "" {
		allowedOrigins = []string{"*"}
	} else {
		for _, o := range strings.Split(cfg.AllowedOrigins, ",") {
			trimmed := strings.TrimSpace(o)
			if trimmed != "" {
				allowedOrigins = append(allowedOrigins, trimmed)
			}
		}
	}
	allowCreds := true
	if len(allowedOrigins) == 1 && allowedOrigins[0] == "*" {
		allowCreds = false
	}
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "X-Signature"},
		ExposedHeaders:   []string{"Link", "X-Request-ID"},
		AllowCredentials: allowCreds,
		MaxAge:           300,
	}))

	// Health Checks
	r.Get("/health/live", healthHandler.Live)
	r.Get("/health/ready", healthHandler.Ready)

	authRateLimiter := middleware.NewIPRateLimiter(15, 1*time.Minute)

	// API v1
	r.Route("/api/v1", func(api chi.Router) {
		// Public Auth with Rate Limiting (Brute-force protection)
		api.Group(func(authRouter chi.Router) {
			authRouter.Use(authRateLimiter.Limit)
			authRouter.Post("/auth/register", authHandler.Register)
			authRouter.Post("/auth/login", authHandler.Login)
			authRouter.Post("/auth/refresh", authHandler.Refresh)
		})
		api.Post("/auth/logout", authHandler.Logout)

		// Public Plans & RevenueCat Webhooks
		api.Get("/plans", plansHandler.ListPlans)
		api.Post("/billing/webhook", billingHandler.Webhook)
		api.Post("/subscriptions/webhook", billingHandler.Webhook)

		// Protected endpoints
		api.Group(func(protected chi.Router) {
			protected.Use(authenticator.RequireAuth)

			protected.Get("/me", authHandler.Me)
			protected.Delete("/me", authHandler.DeleteAccount)
			protected.Get("/me/entitlements", plansHandler.GetMyEntitlements)
			protected.Get("/me/usage", plansHandler.GetMyUsage)

			// Models catalog (public DTOs with plan permission flags)
			protected.Get("/models", modelsHandler.ListModels)

			// RevenueCat Subscription synchronization and status
			protected.Post("/billing/sync", billingHandler.Sync)
			protected.Post("/subscriptions/sync", billingHandler.Sync)
			protected.Get("/billing/status", billingHandler.GetStatus)
			protected.Get("/subscriptions/status", billingHandler.GetStatus)

			// Conversations
			protected.Get("/conversations", convHandler.List)
			protected.Post("/conversations", convHandler.Create)
			protected.Get("/conversations/{conversationID}", convHandler.GetByID)
			protected.Patch("/conversations/{conversationID}", convHandler.Patch)
			protected.Delete("/conversations/{conversationID}", convHandler.Delete)

			// Messages
			protected.Get("/conversations/{conversationID}/messages", msgHandler.List)
			protected.Post("/conversations/{conversationID}/messages", msgHandler.Create)
			protected.Post("/messages/{messageID}/report", msgHandler.Report)

			// Streaming Generations (Gateway & Quota Enforced)
			protected.Post("/conversations/{conversationID}/generations", genHandler.StreamGeneration)
			protected.Post("/generations/{generationID}/cancel", genHandler.CancelGeneration)

			// Multimodal Files & Documents
			protected.Post("/files/upload", filesHandler.Upload)
			protected.Get("/files/{id}", filesHandler.GetMetadata)
			protected.Get("/files/{id}/download", filesHandler.Download)
			protected.Delete("/files/{id}", filesHandler.Delete)
		})
	})

	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 0, // Keep 0 for persistent SSE streaming
		IdleTimeout:  60 * time.Second,
	}

	// 6. Graceful Shutdown
	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("[INFO] Universal AI Chat Backend listening on port %s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("[FATAL] Server failed: %v", err)
		}
	}()

	<-stopChan
	log.Println("[INFO] Shutting down server gracefully...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("[ERROR] Server forced to shutdown: %v", err)
	} else {
		log.Println("[INFO] Server stopped cleanly")
	}
	fmt.Println("Server exiting")
}
