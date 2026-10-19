-- Down migration: 000001_initial_schema.down.sql

DROP TRIGGER IF EXISTS trigger_messages_touch_conversation ON messages;
DROP FUNCTION IF EXISTS update_conversation_last_message();

DROP TABLE IF EXISTS generations CASCADE;
DROP TABLE IF EXISTS messages CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;
DROP TABLE IF EXISTS refresh_sessions CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP FUNCTION IF EXISTS set_updated_at_timestamp();
