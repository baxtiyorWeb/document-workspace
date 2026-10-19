-- =====================================================================
-- MIGRATION 000002: AI GATEWAY, PLANS, QUOTAS, AND LEMON SQUEEZY BILLING
-- =====================================================================

-- 1. Extend Users table with plan_id
ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_id VARCHAR(32) NOT NULL DEFAULT 'free';
CREATE INDEX IF NOT EXISTS idx_users_plan_id ON users(plan_id);

-- 2. Plans Table
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

-- Seed Free and Pro plans
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

-- 3. Models Catalog Table
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

-- 4. Lemon Squeezy Subscriptions Table
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

-- 5. Usage Ledger Table (Atomic Quota & Cost Tracking)
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

-- 6. Webhook Events Table (Idempotency against replay)
CREATE TABLE IF NOT EXISTS webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id VARCHAR(100) UNIQUE NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_event_id ON webhook_events(event_id);
