DROP INDEX IF EXISTS idx_subscriptions_rc_orig_trans_id;
DROP INDEX IF EXISTS idx_subscriptions_user_status;
DROP INDEX IF EXISTS idx_subscriptions_rc_user_id;

ALTER TABLE subscriptions DROP COLUMN IF EXISTS provider;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS original_transaction_id;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS revenuecat_app_user_id;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS product_id;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS store;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS environment;
ALTER TABLE subscriptions DROP COLUMN IF EXISTS raw_data;
