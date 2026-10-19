# ADR 0001: AI Gateway, Model Routing, and Lemon Squeezy Billing Architecture

**Status:** Accepted  
**Date:** 2026-10-14  
**Author:** Principal Software Architect & Engineering Team  

---

## 1. Context and Problem Statement

The application requires an enterprise-grade AI Gateway layer and a monetization model (Free and Pro plans) with automated payment processing via Lemon Squeezy. The gateway must manage model catalogs, rate limits, quotas, cost accounting, and strict entitlement enforcement without adding excessive operational complexity.

---

## 2. Answers to Mandatory Architecture Questions

### Q1: Should the gateway be an internal Go module or a separate service?
**Decision:** Internal Go module (`backend/internal/gateway`, `backend/internal/plans`, `backend/internal/billing`).  
**Rationale:** 
- Avoids extra network hops (saving 20–80ms latency per generation).
- Allows atomic PostgreSQL database transactions for quota reservations without distributed locks or 2PC.
- Keeps deployment unified in a single Go binary container.  
**Alternatives Considered:** Standalone Go service (gRPC/HTTP), Python LiteLLM proxy.  
**Migration Cost:** Low. All gateway logic is behind clean interfaces (`GatewayService`, `ProviderAdapter`, `QuotaManager`) and can be extracted into an independent microservice if RPS exceeds 25,000 req/sec.

### Q2: Should the first release use a custom Go router, an existing gateway, or a hybrid approach?
**Decision:** Custom Go router with explicit provider adapters.  
**Rationale:** An external gateway adds deployment complexity, Python runtimes, and third-party CVE exposure. A custom Go router implements exactly what is required (OpenAI, Groq, OpenRouter adapters, quota check, failover) with zero unnecessary bloat.

### Q3: Which AI providers and model families are genuinely accessible through supported APIs?
**Verified Live:**
1. **OpenRouter:** Active with production API key (`sk-or-v1-...`). Models tested:
   - `nvidia/nemotron-3-ultra-550b-a55b:free` (550B, free, high quality Uzbek).
   - `cohere/north-mini-code:free` (Code & fast chat, free).
   - `nvidia/nemotron-3-super-120b-a12b:free` (Reasoning, free).
   - `openai/gpt-4o` / `openai/gpt-4o-mini` (Paid Pro).
   - `anthropic/claude-3.5-sonnet` (Paid Pro).
   - `deepseek/deepseek-r1` (Reasoning Pro).
2. **Groq (OpenAI-compatible):** Ultra-fast Llama 3.3 70B.
3. **OpenAI Direct:** Standard OpenAI API endpoints.

### Q4: Official API prices, rate limits, and context limits (Verified 2026)
| Model ID | Provider | Input / 1M | Output / 1M | Context | Streaming | Plan |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `nvidia/nemotron-3-ultra-550b-a55b:free` | OpenRouter | $0.00 | $0.00 | 1,000,000 | Yes (SSE) | Free / Pro |
| `cohere/north-mini-code:free` | OpenRouter | $0.00 | $0.00 | 256,000 | Yes (SSE) | Free / Pro |
| `openai/gpt-4o-mini` | OpenRouter/OpenAI | $0.15 | $0.60 | 128,000 | Yes (SSE) | Free / Pro |
| `meta-llama/llama-3.3-70b-instruct` | Groq/OpenRouter | $0.59 | $0.79 | 128,000 | Yes (SSE) | Pro |
| `openai/gpt-4o` | OpenRouter/OpenAI | $2.50 | $10.00 | 128,000 | Yes (SSE) | Pro |
| `anthropic/claude-3.5-sonnet` | OpenRouter | $3.00 | $15.00 | 200,000 | Yes (SSE) | Pro |

### Q5: Which models are suitable for Free vs Pro?
- **Free Tier:** High-performance zero-cost or ultra-economical models: `nvidia/nemotron-3-ultra-550b-a55b:free`, `cohere/north-mini-code:free`, and `openai/gpt-4o-mini`. Provides a great experience without incurring heavy API costs.
- **Pro Tier:** All Free models PLUS flagship frontier models: `openai/gpt-4o`, `anthropic/claude-3.5-sonnet`, `deepseek/deepseek-r1`, and higher daily message & token quotas.

### Q6: Main risks and mitigation
1. **Upstream 429 / Outages:** Mitigated by router fallback policy (if primary fails with 429/5xx, fail over to eligible backup within same plan).
2. **Price changes / Spikes:** Mitigated by database-driven `models` pricing table and atomic quota reservation with strict daily dollar/token budgets.
3. **Runaway billing:** Capped per-request `max_tokens` (2,048 Free, 4,096 Pro) and max 1 active generation per Free user.

### Q7: Plan permission enforcement and preventing quota bypass
- Authenticated JWT resolves user ID -> Server queries PostgreSQL `users.plan_id` and authoritative `subscriptions` table.
- Flutter client has ZERO authority to set plan, token count, or price.
- Quota reservations occur in a database transaction (`INSERT INTO usage_ledger (status = 'reserved')`) before upstream call.
- If concurrent requests attempt to reserve beyond remaining daily quota, subsequent transactions are rejected with HTTP 429 `PLAN_LIMIT_EXCEEDED`.

### Q8: Usage accounting on failure or cancellation
- **Cancelled generation:** Only tokens actually emitted (partial stream) are reconciled and finalized as `cancelled`. Unused reservation is released.
- **Failed generation:** If 0 output tokens were delivered to the user, the cost recorded is $0.00 and status is marked `failed`.
- Never double-count or leak reservations.

### Q9: Implemented now vs Extension points
- **Implemented Now:**
  - Database schema: `plans`, `subscriptions`, `models`, `usage_ledger`, `webhook_events`.
  - Go AI Gateway: Model catalog API, plan entitlement service, atomic quota manager, router with failover.
  - Lemon Squeezy: Auto-discovery client, checkout session creator, customer billing portal, raw HMAC-SHA256 webhook validator, idempotent event handler.
  - Mobile UI: Model picker, plan status, upgrade button, billing portal launcher.
- **Extension Points:**
  - Multi-currency pricing conversion (currently USD standard).
  - Web search tool / Function calling adapters.
  - Enterprise team seat management.

### Q10: Evidence required before claiming a feature works
1. Real PostgreSQL database migrations applied.
2. Unit tests passing for HMAC SHA256 verification (valid, invalid signature, tampered payload).
3. Unit tests passing for quota reservation and concurrent limit enforcement.
4. Live verified OpenRouter streaming request via gateway.
5. Idempotent webhook replay test.
