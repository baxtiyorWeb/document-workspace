-- =====================================================================
-- MASTER DATABASE SCHEMA FOR AI CHAT APPLICATION
-- Target: PostgreSQL 14+ (Compatible with Neon, Supabase, RDS, Local Postgres)
-- File: database.sql
-- =====================================================================

-- 1. Enable standard extensions (gen_random_uuid is built-in in PG 13+)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Trigger function for updating updated_at timestamp automatically
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 3. USERS TABLE
-- Stores authenticated user accounts with secure password hashes
-- =====================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(120) NOT NULL DEFAULT '',
    status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Case-insensitive unique index for email
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users (LOWER(email));

DROP TRIGGER IF EXISTS trigger_users_updated_at ON users;
CREATE TRIGGER trigger_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_timestamp();

-- =====================================================================
-- 4. REFRESH SESSIONS TABLE
-- Secure refresh token rotation and session management
-- =====================================================================
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
CREATE INDEX IF NOT EXISTS idx_refresh_sessions_active ON refresh_sessions(user_id) WHERE revoked_at IS NULL;

-- =====================================================================
-- 5. CONVERSATIONS TABLE
-- Chat conversations belonging to users with category & activity tracking
-- =====================================================================
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
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(created_at DESC);

DROP TRIGGER IF EXISTS trigger_conversations_updated_at ON conversations;
CREATE TRIGGER trigger_conversations_updated_at
BEFORE UPDATE ON conversations
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_timestamp();

-- =====================================================================
-- 6. MESSAGES TABLE
-- Relational store for user, assistant, and system chat messages
-- =====================================================================
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
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);

DROP TRIGGER IF EXISTS trigger_messages_updated_at ON messages;
CREATE TRIGGER trigger_messages_updated_at
BEFORE UPDATE ON messages
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_timestamp();

-- =====================================================================
-- 7. GENERATIONS TABLE
-- Tracks AI streaming lifecycle, token counts, errors, and cancellation
-- =====================================================================
CREATE TABLE IF NOT EXISTS generations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    provider VARCHAR(64) NOT NULL DEFAULT 'openai_compatible',
    model VARCHAR(128) NOT NULL DEFAULT 'gpt-4o-mini',
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
CREATE INDEX IF NOT EXISTS idx_generations_user_status ON generations(user_id, status);

-- =====================================================================
-- 8. HELPER FUNCTION TO UPDATE CONVERSATION LAST MESSAGE TIMESTAMP
-- =====================================================================
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET last_message_at = NEW.created_at,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_messages_touch_conversation ON messages;
CREATE TRIGGER trigger_messages_touch_conversation
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION update_conversation_last_message();

-- =====================================================================
-- 9. PLANS AND MODEL CATALOG
-- =====================================================================
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_id VARCHAR(32) NOT NULL DEFAULT 'free';
CREATE INDEX IF NOT EXISTS idx_users_plan_id ON users(plan_id);

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

INSERT INTO plans (id, name, description, daily_requests, monthly_tokens, max_input_tokens, max_output_tokens, max_active_streams, allowed_models, price_usd_cents)
VALUES 
('free', 'Bepul (Free)', 'Kundalik 40 ta so''rov va bepul yuqori sifatli AI modellar', 40, 500000, 4000, 1024, 1, '{"nemotron-ultra","cohere-code","gpt-4o-mini"}', 0),
('pro', 'Pro Obuna ($9.99/oy)', 'Kundalik 400 ta so''rov, flagman GPT-4o, Claude 3.5 va 32k kontekst', 400, 10000000, 32000, 4096, 3, '{"nemotron-ultra","cohere-code","gpt-4o-mini","gpt-4o","claude-3-5-sonnet","deepseek-r1","llama-70b"}', 999)
ON CONFLICT (id) DO UPDATE SET 
    daily_requests = EXCLUDED.daily_requests,
    monthly_tokens = EXCLUDED.monthly_tokens,
    max_input_tokens = EXCLUDED.max_input_tokens,
    max_output_tokens = EXCLUDED.max_output_tokens,
    allowed_models = EXCLUDED.allowed_models,
    price_usd_cents = EXCLUDED.price_usd_cents;

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

INSERT INTO models (id, name, description, provider, provider_model_id, is_enabled, allowed_plans, max_context_tokens, max_output_tokens, input_price_per_million_usd, output_price_per_million_usd, is_free_tier, is_reasoning)
VALUES
('nemotron-ultra', 'Nvidia Nemotron 550B', '550 milliard parametrli kuchli Nvidia super-modeli', 'openrouter', 'nvidia/nemotron-3-ultra-550b-a55b:free', TRUE, '{"free","pro"}', 1000000, 2048, 0.0000, 0.0000, TRUE, FALSE),
('cohere-code', 'Cohere North Mini Code', 'Dasturlash va tezkor suhbatlar uchun maxsus bepul model', 'openrouter', 'cohere/north-mini-code:free', TRUE, '{"free","pro"}', 256000, 2048, 0.0000, 0.0000, TRUE, FALSE),
('gpt-4o-mini', 'GPT-4o mini', 'OpenAI-ning o''ta tezkor va tejamkor aqlli modeli', 'openrouter', 'openai/gpt-4o-mini', TRUE, '{"free","pro"}', 128000, 4096, 0.1500, 0.6000, FALSE, FALSE),
('gpt-4o', 'GPT-4o Flagship (Pro)', 'Eng yuqori darajadagi mantiq va chuqur tahlil', 'openrouter', 'openai/gpt-4o', TRUE, '{"pro"}', 128000, 4096, 2.5000, 10.0000, FALSE, FALSE),
('claude-3-5-sonnet', 'Claude 3.5 Sonnet (Pro)', 'Dunyoning yetakchi dasturlash va yozish AI modeli', 'openrouter', 'anthropic/claude-3.5-sonnet', TRUE, '{"pro"}', 200000, 4096, 3.0000, 15.0000, FALSE, FALSE),
('deepseek-r1', 'DeepSeek R1 Reasoning (Pro)', 'Ochiq kodli ilg''or mulohaza yurituvchi model', 'openrouter', 'deepseek/deepseek-r1', TRUE, '{"pro"}', 64000, 4096, 0.5500, 2.1900, FALSE, TRUE)
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    provider_model_id = EXCLUDED.provider_model_id,
    allowed_plans = EXCLUDED.allowed_plans,
    is_free_tier = EXCLUDED.is_free_tier,
    is_reasoning = EXCLUDED.is_reasoning;

-- =====================================================================
-- 10. LEMON SQUEEZY SUBSCRIPTIONS
-- =====================================================================
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lemon_subscription_id VARCHAR(100) UNIQUE NOT NULL,
    lemon_customer_id VARCHAR(100),
    lemon_order_id VARCHAR(100),
    plan_id VARCHAR(32) NOT NULL DEFAULT 'pro' REFERENCES plans(id),
    variant_id VARCHAR(100),
    status VARCHAR(32) NOT NULL CHECK (status IN ('active', 'on_trial', 'paused', 'past_due', 'unpaid', 'cancelled', 'expired')),
    renews_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    customer_portal_url TEXT,
    test_mode BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_lemon_id ON subscriptions(lemon_subscription_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

-- =====================================================================
-- 11. USAGE LEDGER & QUOTA TRACKING
-- =====================================================================
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

CREATE INDEX IF NOT EXISTS idx_usage_ledger_user_date ON usage_ledger(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_generation ON usage_ledger(generation_id);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_status ON usage_ledger(status);

-- =====================================================================
-- 12. WEBHOOK EVENTS (IDEMPOTENCY)
-- =====================================================================
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(100) UNIQUE NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_event_id ON webhook_events(event_id);

