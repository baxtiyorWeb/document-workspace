-- =====================================================================
-- MIGRATION 000005: MESSAGE REPORTS (AIGC POLICY COMPLIANCE)
-- =====================================================================

CREATE TABLE IF NOT EXISTS message_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    reason VARCHAR(100) NOT NULL,
    comment TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'dismissed', 'actioned')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_message_reports_user_id ON message_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_message_reports_message_id ON message_reports(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reports_status ON message_reports(status);
