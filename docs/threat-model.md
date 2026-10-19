# Threat Model & Abuse Resistance

## 1. Scope and Objective
This document assesses threat vectors and countermeasures for **The Go-getters AI Platform**, with a focus on entitlement bypass, financial abuse, data isolation, and API integrity.

---

## 2. Threat Analysis & Mitigations

### Threat 1: Free User Directly Requests Pro Model
- **Attack Vector:** Client edits JSON request body sent to `POST /api/v1/conversations/{id}/generations` with `model: "openai/gpt-4o"` or `"anthropic/claude-3.5-sonnet"`.
- **Mitigation:** The server resolves the user's plan from the PostgreSQL `subscriptions` / `users.plan_id` table using the authenticated JWT `user_id`. The gateway verifies whether the requested model is in `plan.allowed_models`. If unauthorized, it immediately returns `403 FORBIDDEN` with code `MODEL_NOT_PERMITTED_ON_PLAN`. Client-submitted plan IDs or roles are completely ignored.

### Threat 2: IDOR / Cross-User Conversation Access
- **Attack Vector:** Attacker specifies another user's `conversationID` in URL path.
- **Mitigation:** All database queries for conversations and messages enforce `WHERE id = $1 AND user_id = $2`. If no matching row is found for that user, the server returns `404 NOT_FOUND` to prevent ID enumeration.

### Threat 3: Quota Bypass via Concurrent Requests (Race Condition)
- **Attack Vector:** User sends 50 parallel requests at the exact same millisecond when they have only 1 remaining quota slot.
- **Mitigation:** Atomic database reservation. Before initiating upstream streaming, the server executes an atomic reservation query:
  ```sql
  INSERT INTO usage_ledger (id, user_id, generation_id, status)
  SELECT gen_random_uuid(), $1, $2, 'reserved'
  WHERE (
    SELECT COUNT(*) FROM usage_ledger 
    WHERE user_id = $1 AND created_at >= CURRENT_DATE AND status IN ('reserved', 'settled')
  ) < $3;
  ```
  If 0 rows are inserted, the quota has been exhausted and subsequent parallel requests are rejected with `429 PLAN_LIMIT_EXCEEDED`.

### Threat 4: Fake Lemon Squeezy Webhook Events (Payment Spoofing)
- **Attack Vector:** Malicious party posts a forged `subscription_created` payload to `/api/v1/billing/webhook` to grant themselves Pro access without paying.
- **Mitigation:**
  1. The server reads the **raw body bytes** before JSON decoding.
  2. Computes the HMAC-SHA256 signature using the server's private `LEMON_SQUEEZY_WEBHOOK_SECRET`.
  3. Uses `crypto/subtle.ConstantTimeCompare` against the incoming `X-Signature` header.
  4. Any signature mismatch returns `401 UNAUTHORIZED` immediately.

### Threat 5: Webhook Replay Attacks & Duplicate Processing
- **Attack Vector:** Attacker intercepts and replays an old valid webhook or Lemon Squeezy retries an event.
- **Mitigation:** Webhook events are stored in a dedicated `webhook_events` table with a unique constraint on `event_id`. Duplicate deliveries are caught by `ON CONFLICT (event_id) DO NOTHING` and return `200 OK` idempotently without updating user credits twice.

### Threat 6: Upstream Secret Leakage
- **Attack Vector:** Provider API keys or database connection strings leaked to Flutter client or logged in error messages.
- **Mitigation:** 
  1. Zero provider keys in mobile app code, configuration, or APK assets.
  2. `GET /api/v1/models` returns only public metadata (`id`, `name`, `description`, `is_free_tier`, `max_context_tokens`). Internal `provider` credentials and internal deployment URLs are excluded.
  3. Structured logger strips tokens and passwords; error handler returns normalized error codes instead of raw upstream stack traces.
