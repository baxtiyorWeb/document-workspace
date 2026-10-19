-- =====================================================================
-- MIGRATION 000003: MULTIMODAL FILES, CHUNKING, AND TIERED (HOURLY/DAILY/WEEKLY) LIMITS
-- =====================================================================

-- 1. Extend Plans table with Hourly, Daily, Weekly limits and Multimodal capabilities
ALTER TABLE plans ADD COLUMN IF NOT EXISTS hourly_requests INT NOT NULL DEFAULT 15;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS weekly_requests INT NOT NULL DEFAULT 200;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_file_size_bytes BIGINT NOT NULL DEFAULT 10485760; -- 10MB
ALTER TABLE plans ADD COLUMN IF NOT EXISTS max_files_per_request INT NOT NULL DEFAULT 2;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_vision BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_document_rag BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plans ADD COLUMN IF NOT EXISTS allows_media BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Seed Free, Pro, and Ultra plans with exact tiered parameters
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
    'free', 
    'Bepul (Free)', 
    'Boshlang''ich foydalanuvchilar uchun: soatiga 15 ta, kuniga 40 ta so''rov, 10MB hujjatlar va tejamkor modellar', 
    15, 40, 200, 500000, 
    4000, 1024, 1, 
    10485760, 2, 
    TRUE, TRUE, FALSE, 
    '{"nemotron-ultra","cohere-code","gpt-4o-mini"}', 0, TRUE
),
(
    'pro', 
    'Pro Obuna ($9.99/oy)', 
    'Mutaxassislar uchun: soatiga 60 ta, kuniga 400 ta so''rov, 50MB fayllar, GPT-4o, Claude 3.5 va 32k kontekst', 
    60, 400, 2000, 10000000, 
    32000, 4096, 3, 
    52428800, 5, 
    TRUE, TRUE, TRUE, 
    '{"nemotron-ultra","cohere-code","gpt-4o-mini","gpt-4o","claude-3-5-sonnet","deepseek-r1","llama-70b"}', 999, TRUE
),
(
    'ultra', 
    'Ultra Obuna ($24.99/oy)', 
    'Cheksiz professional imkoniyatlar: soatiga 180 ta, kuniga 1200 ta so''rov, 200MB fayllar, to''liq multimodal va eng yuqori navbat ustuvorligi', 
    180, 1200, 6000, 30000000, 
    128000, 8192, 6, 
    209715200, 10, 
    TRUE, TRUE, TRUE, 
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

-- 3. Extend models catalog with multimodal capabilities
ALTER TABLE models ADD COLUMN IF NOT EXISTS is_vision BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE models ADD COLUMN IF NOT EXISTS is_multimodal BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE models SET is_vision = TRUE, is_multimodal = TRUE WHERE id IN ('gpt-4o', 'gpt-4o-mini', 'claude-3-5-sonnet');

-- 4. Files Table (Stored metadata, hashes, MIME and size)
CREATE TABLE IF NOT EXISTS files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    file_type VARCHAR(32) NOT NULL, -- 'pdf', 'docx', 'image', 'audio', 'video', 'text'
    mime_type VARCHAR(128) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    sha256_hash VARCHAR(64) NOT NULL,
    storage_path TEXT NOT NULL,
    extracted_text TEXT,
    chunk_count INT NOT NULL DEFAULT 0,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_files_user_id ON files(user_id);
CREATE INDEX IF NOT EXISTS idx_files_conversation_id ON files(conversation_id);
CREATE INDEX IF NOT EXISTS idx_files_created_at ON files(created_at);

-- 5. Document Chunks Table (for RAG & Section/Page retrieval)
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

CREATE INDEX IF NOT EXISTS idx_file_chunks_file_id ON file_chunks(file_id);
CREATE INDEX IF NOT EXISTS idx_file_chunks_page ON file_chunks(file_id, page_number);

-- 6. Media Processing Jobs (Async Queue for Video/Audio)
CREATE TABLE IF NOT EXISTS media_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
    job_type VARCHAR(32) NOT NULL, -- 'transcription', 'frame_extraction', 'audio_analysis'
    progress_percent INT NOT NULL DEFAULT 0,
    result_text TEXT,
    error_message TEXT,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_media_jobs_user_id ON media_jobs(user_id);
CREATE INDEX IF NOT EXISTS idx_media_jobs_file_id ON media_jobs(file_id);
CREATE INDEX IF NOT EXISTS idx_media_jobs_status ON media_jobs(status);

-- 7. Add file references to messages table
ALTER TABLE messages ADD COLUMN IF NOT EXISTS attached_file_ids UUID[] DEFAULT '{}';
