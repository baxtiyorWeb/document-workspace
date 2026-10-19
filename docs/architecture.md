# Universal AI Platform — Architecture Documentation

This document describes the comprehensive architecture of the **The Go-getters Universal AI Platform**, featuring a first-party **Go AI Gateway**, **Model Routing & Quota Accounting**, and **Lemon Squeezy Subscription & Billing Integration (2026 Official API)**.

---

## 1. System Topology

```
┌─────────────────────────────────────────────────────────────┐
│                       Flutter Mobile App                    │
│   (Riverpod, Model Selector, Lemon Squeezy Checkout Sheet)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ HTTPS / REST & SSE Stream
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     First-Party Go Backend                  │
│                                                             │
│  ┌───────────────────────┐      ┌────────────────────────┐  │
│  │   Auth & Middleware   │      │    Lemon Squeezy Hub   │  │
│  │   (JWT, Chi, Sec)     │      │ (HMAC-SHA256, Webhooks)│  │
│  └───────────┬───────────┘      └───────────┬────────────┘  │
│              ▼                              ▼               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Go AI Gateway                      │  │
│  │  - Model Catalog & Registry (Public DTOs vs Secrets)   │  │
│  │  - Plan & Entitlement Resolver (Free vs Pro)          │  │
│  │  - Atomic Quota Reservation & Concurrency Guard       │  │
│  │  - Policy Router (Explicit Model vs Smart Fallback)   │  │
│  │  - Usage Accounting Ledger (USD Pricing per Token)    │  │
│  └───────────────────────────┬───────────────────────────┘  │
└──────────────┬───────────────┴───────────────┬──────────────┘
               │                               │
               ▼                               ▼
┌──────────────────────────────┐ ┌─────────────────────────────┐
│     PostgreSQL Database      │ │      AI Provider Mesh       │
│  - users & sessions          │ │ - OpenRouter (Primary Mesh) │
│  - plans & models            │ │ - Nvidia Nemotron 550B      │
│  - subscriptions             │ │ - Cohere North Mini Code    │
│  - usage_ledger (atomic)     │ │ - GPT-4o Omni (Pro)         │
│  - webhook_events (idempotent│ │ - OpenAI / Groq / Fallbacks │
└──────────────────────────────┘ └─────────────────────────────┘
```

---

## 2. Core Architectural Decisions

As recorded in `docs/decisions/0001-ai-gateway-and-billing.md`:

1. **In-Process Go Gateway vs Microservice**: The gateway is implemented as an internal Go module (`internal/gateway`, `internal/plans`, `internal/billing`) inside the existing Go backend. This eliminates extra network hops, prevents distributed transaction failures, simplifies deployments, and enables atomic PostgreSQL quota reservations.
2. **Server-Side Authority (Zero Client Trust)**:
   - Flutter client **never** communicates with upstream AI providers directly.
   - Provider API keys and Lemon Squeezy webhook secrets remain strictly server-side in `.env`.
   - Client cannot dictate model availability, plan status, or token counts.
   - Any attempt by a Free user to request a Pro model is intercepted and denied with `MODEL_NOT_PERMITTED_ON_PLAN`.
3. **Atomic Quota Reservation & Double-Spend Defense**:
   - Quotas are reserved **before** initiating provider streaming using an atomic SQL query:
     ```sql
     INSERT INTO usage_ledger (...)
     SELECT gen_random_uuid(), $1, $2, $3, $4, $5, 'reserved'
     WHERE (
         SELECT COUNT(*) FROM usage_ledger 
         WHERE user_id = $1 AND created_at >= date_trunc('day', CURRENT_TIMESTAMP)
     ) < $limit
     ```
   - Concurrent requests competing for the last available slot are safely rejected with `PLAN_LIMIT_EXCEEDED` without race conditions.
4. **Lemon Squeezy 2026 Official Integration**:
   - Webhook signature verification uses cryptographic **HMAC-SHA256** against the raw request body bytes and `subtle.ConstantTimeCompare` against `X-Signature`.
   - Event deduplication via `webhook_events (event_id PRIMARY KEY)` ensures idempotent processing during retried or delayed webhooks.
   - Auto-discovery mechanism for Store ID and Pro Variant ID via official `GET /v1/stores` and `GET /v1/variants`.

---

## 3. Database Schema (PostgreSQL Migration V2)

### 3.1 Tables
- **`users`**: User identities, credentials, and `plan_id` reference (`free` or `pro`).
- **`plans`**: Configurable plan policies (`id`, `name`, `daily_requests`, `monthly_tokens`, `max_input_tokens`, `max_output_tokens`, `max_active_streams`, `allowed_models`, `price_usd_cents`).
- **`models`**: Configurable AI catalog (`id`, `name`, `provider`, `provider_model_id`, `is_enabled`, `allowed_plans`, `max_context_tokens`, `input_price_per_million_usd`, `output_price_per_million_usd`, `is_free_tier`, `is_reasoning`).
- **`subscriptions`**: Authoritative subscription state from Lemon Squeezy (`user_id`, `lemon_subscription_id`, `lemon_customer_id`, `plan_id`, `status`, `renews_at`, `ends_at`, `customer_portal_url`, `test_mode`).
- **`usage_ledger`**: Auditable accounting log per generation (`user_id`, `conversation_id`, `generation_id`, `model_id`, `plan_id`, `input_tokens`, `output_tokens`, `actual_cost_usd`, `status`).
- **`webhook_events`**: Idempotent event ledger for payment webhooks (`event_id`, `event_name`, `payload`).

---

## 4. AI Gateway Lifecycle

```
Client POST /api/v1/conversations/{id}/generations
   │
   ├─► 1. Authenticate user via JWT middleware
   │
   ├─► 2. Resolve User Entitlement (authoritative DB query on subscriptions + plans)
   │
   ├─► 3. Select and Authorize Model:
   │      - If explicit model requested: verify model is enabled and allowed on user's plan.
   │      - If prohibited: return HTTP 403 / SSE error: MODEL_NOT_PERMITTED_ON_PLAN.
   │      - If empty: assign plan default.
   │
   ├─► 4. Atomically Reserve Quota:
   │      - Check concurrent active generations (max_active_streams).
   │      - Atomically reserve slot in usage_ledger.
   │      - If exceeded: return HTTP 429 / PLAN_LIMIT_EXCEEDED.
   │
   ├─► 5. Dispatch to Provider Adapter:
   │      - Call OpenRouter / OpenAI API with timeout and request-scoped Context.
   │      - Stream normalized SSE events: generation.started, message.delta, generation.completed.
   │
   ├─► 6. Finalize & Settle:
   │      - On success: persist message, calculate exact USD cost, mark ledger 'settled'.
   │      - On failure/cancel: mark ledger 'failed' or 'released', release reservation.
   │      - If stream fails before output: attempt safe fallback model if permitted.
```

---

## 5. Lemon Squeezy Subscription Lifecycle

```
User triggers "Pro tarifiga o'tish" in Flutter UI
   │
   ▼
POST /api/v1/billing/checkout
   │
   ├─► Server calls Lemon Squeezy API: POST https://api.lemonsqueezy.com/v1/checkouts
   │   Prefills user email, user name, and custom.user_id
   │
   └─► Returns hosted checkout_url to client (e.g., https://thegogetters.lemonsqueezy.com/checkout/buy/...)
       │
       ▼
User completes payment on Lemon Squeezy hosted page
       │
       ▼
Lemon Squeezy dispatches Webhook to server: POST /api/v1/billing/webhook
   │
   ├─► Verify X-Signature header using HMAC-SHA256(raw_bytes, LEMON_SQUEEZY_WEBHOOK_SECRET)
   │   - Reject if invalid or missing (401 Unauthorized)
   │
   ├─► Check webhook_events for event_id deduplication (Idempotency Guard)
   │
   ├─► Event dispatch:
   │   - subscription_created / updated / resumed:
   │       Upsert subscriptions table -> Update users SET plan_id = 'pro'
   │   - subscription_cancelled:
   │       Update subscriptions status = 'cancelled' (access preserved until ends_at)
   │   - subscription_expired / payment_failed / refunded:
   │       Update subscriptions status = 'expired' -> Update users SET plan_id = 'free'
   │
   └─► Returns HTTP 200 {"received":true}
```
