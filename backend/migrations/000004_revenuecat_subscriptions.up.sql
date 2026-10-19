-- =====================================================================
-- MIGRATION 000004: REVENUECAT SUBSCRIPTIONS & MULTI-STORE BILLING
-- =====================================================================

-- 1. Make legacy lemon_subscription_id nullable so non-Lemon providers can insert records
ALTER TABLE subscriptions ALTER COLUMN lemon_subscription_id DROP NOT NULL;

-- 2. Add provider column (defaults to revenuecat)
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS provider VARCHAR(32) NOT NULL DEFAULT 'revenuecat';

-- 3. Add RevenueCat tracking fields
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS original_transaction_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS revenuecat_app_user_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS product_id VARCHAR(128);
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS store VARCHAR(32) DEFAULT 'play_store';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS environment VARCHAR(32) DEFAULT 'PRODUCTION';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS raw_data JSONB DEFAULT '{}';

-- 4. Create indexes for high-performance lookup
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_rc_orig_trans_id 
    ON subscriptions (original_transaction_id) 
    WHERE original_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_status 
    ON subscriptions (user_id, status);

CREATE INDEX IF NOT EXISTS idx_subscriptions_rc_user_id 
    ON subscriptions (revenuecat_app_user_id) 
    WHERE revenuecat_app_user_id IS NOT NULL;
