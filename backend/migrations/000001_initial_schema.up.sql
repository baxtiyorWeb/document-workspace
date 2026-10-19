-- Up migration: 000001_initial_schema.up.sql

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
    status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users (LOWER(email));

DROP TRIGGER IF EXISTS trigger_users_updated_at ON users;
CREATE TRIGGER trigger_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_timestamp();

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
