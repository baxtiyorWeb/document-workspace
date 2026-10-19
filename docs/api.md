# Universal AI Assistant — API Contract Documentation

Standard Response Envelope:
```json
{
  "data": { ... }
}
```

Standard Error Envelope:
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error explanation",
    "request_id": "b3e34bcf-6199-4d6b-95bb-eb6a7c6c4c51"
  }
}
```

Standard Error Codes:
- `UNAUTHENTICATED`: Missing or expired JWT access token
- `FORBIDDEN`: Ownership or permission violation
- `MODEL_NOT_FOUND`: Requested model identifier does not exist
- `MODEL_DISABLED`: Model is temporarily disabled in catalog
- `MODEL_NOT_PERMITTED_ON_PLAN`: Requested model requires a Pro subscription
- `PLAN_LIMIT_EXCEEDED`: User has reached their daily request limit
- `CONCURRENCY_LIMIT_REACHED`: User has active generations exceeding max concurrency
- `INVALID_SIGNATURE`: Lemon Squeezy HMAC-SHA256 signature mismatch
- `VALIDATION_FAILED`: Request payload malformed or fields invalid

---

## 1. Plans & Model Catalog

### GET `/api/v1/plans`
- **Auth**: Public
- **Description**: Returns the active subscription plans and their limits.
- **Response**: `200 OK`
```json
{
  "data": [
    {
      "id": "free",
      "name": "Bepul (Free)",
      "description": "Boshlang'ich bepul tarif",
      "daily_requests": 40,
      "monthly_tokens": 100000,
      "max_input_tokens": 4000,
      "max_output_tokens": 1024,
      "max_active_streams": 1,
      "allowed_models": ["nemotron-ultra", "cohere-code"],
      "price_usd_cents": 0,
      "is_active": true
    },
    {
      "id": "pro",
      "name": "Pro Obuna ($9.99/oy)",
      "description": "Cheksiz sifat va premium modellar",
      "daily_requests": 400,
      "monthly_tokens": 1000000,
      "max_input_tokens": 32000,
      "max_output_tokens": 4096,
      "max_active_streams": 3,
      "allowed_models": ["nemotron-ultra", "cohere-code", "nemotron-super", "gpt-4o"],
      "price_usd_cents": 999,
      "is_active": true
    }
  ]
}
```

### GET `/api/v1/models`
- **Auth**: Bearer JWT
- **Description**: Returns safe public model metadata with permissions relative to the authenticated user's plan. Never exposes provider credentials or internal keys.
- **Response**: `200 OK`
```json
{
  "data": [
    {
      "id": "nemotron-ultra",
      "name": "Nvidia Nemotron 550B",
      "description": "550B ochiq parametrli model",
      "allowed_plans": ["free", "pro"],
      "max_context_tokens": 8192,
      "max_output_tokens": 2048,
      "is_free_tier": true,
      "is_reasoning": false,
      "is_pro_only": false
    },
    {
      "id": "gpt-4o",
      "name": "GPT-4o Omni",
      "description": "Yuqori aniqlikdagi universal intellekt",
      "allowed_plans": ["pro"],
      "max_context_tokens": 32768,
      "max_output_tokens": 4096,
      "is_free_tier": false,
      "is_reasoning": false,
      "is_pro_only": true
    }
  ]
}
```

---

## 2. Entitlements & Usage

### GET `/api/v1/me/entitlements`
- **Auth**: Bearer JWT
- **Description**: Returns the authoritative entitlement state for the authenticated user.
- **Response**: `200 OK`
```json
{
  "data": {
    "user_id": "4b684cb0-e547-4974-9b2f-2f801646ee18",
    "plan_id": "free",
    "plan_name": "Bepul (Free)",
    "is_pro": false,
    "daily_requests_limit": 40,
    "daily_requests_remaining": 39,
    "max_context_tokens": 4000,
    "max_output_tokens": 1024,
    "max_active_streams": 1,
    "allowed_models": ["nemotron-ultra", "cohere-code"]
  }
}
```

### GET `/api/v1/me/usage`
- **Auth**: Bearer JWT
- **Description**: Returns daily and monthly usage totals and recent generation ledger records for auditing.
- **Response**: `200 OK`
```json
{
  "data": {
    "today_requests": 1,
    "month_tokens": 420,
    "month_estimated_cost_usd": 0.0000,
    "recent_generations": [
      {
        "generation_id": "c1f7da35-18ea-4819-bf9f-6e06b3a209ec",
        "model_id": "nemotron-ultra",
        "input_tokens": 240,
        "output_tokens": 180,
        "cost_usd": 0.0000,
        "status": "settled",
        "created_at": "2026-10-14T13:40:00Z"
      }
    ]
  }
}
```

---

## 3. RevenueCat & Google Play Subscriptions

### POST `/api/v1/billing/sync` (or `/api/v1/subscriptions/sync`)
- **Auth**: Bearer JWT
- **Description**: Allows the mobile client to immediately synchronize its active RevenueCat entitlement upon purchase or restoration.
- **Request**:
```json
{
  "original_transaction_id": "GPA.3391-2314-1123-99120",
  "product_id": "monthly",
  "entitlement_id": "cognidoc_ai_document_analyzer_and_chatbot_pro",
  "is_active": true,
  "expiration_date": "2026-11-15T00:00:00Z",
  "store": "play_store"
}
```
- **Response**: `200 OK` (Returns authoritatively refreshed `UserEntitlement` JSON)

### GET `/api/v1/billing/status` (or `/api/v1/subscriptions/status`)
- **Auth**: Bearer JWT
- **Description**: Returns the user's authoritative subscription status, limits, and active entitlement.
- **Response**: `200 OK`

### POST `/api/v1/billing/webhook` (or `/api/v1/subscriptions/webhook`)
- **Auth**: `Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>`
- **Description**: Authoritatively receives RevenueCat server-to-server webhook events and updates PostgreSQL subscriptions idempotently.
- **Headers**:
  - `Content-Type: application/json`
  - `Authorization: Bearer <REVENUECAT_WEBHOOK_AUTH_TOKEN>`
- **Handled Events**:
  - `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `UNCANCELLATION`: Promotes user to Pro.
  - `CANCELLATION`: Keeps Pro benefits active until `ends_at`.
  - `EXPIRATION`: Reverts user to Free plan.
  - `BILLING_ISSUE`: Sets status to `past_due`.
- **Response**: `200 OK` `{"received":true}`


---

## 4. Chat & Streaming Generations

### POST `/api/v1/conversations/{conversationID}/generations`
- **Auth**: Bearer JWT
- **Description**: Atomically reserves a quota slot, selects and authorizes the requested model, dispatches to provider, and streams response tokens via Server-Sent Events (SSE).
- **Request**:
```json
{
  "message": "Assalomu alaykum! AI Gateway qanday ishlaydi?",
  "model_id": "nemotron-ultra"
}
```
- **SSE Stream Protocol**:
```
event: generation.started
data: {"generation_id":"...","provider":"openrouter","model":"nemotron-ultra"}

event: message.delta
data: {"text":"Assalomu "}

event: message.delta
data: {"text":"alaykum!"}

event: generation.completed
data: {"message_id":"...","tokens":120,"content":"Assalomu alaykum! ..."}
```
- **Error Stream (on failure or cancellation)**:
```
event: generation.failed
data: {"code":"PLAN_LIMIT_EXCEEDED","message":"Kunlik limitingiz tugadi"}
```

### POST `/api/v1/generations/{generationID}/cancel`
- **Auth**: Bearer JWT
- **Description**: Immediately cancels an active generation, stops provider streaming, persists partial output, and releases quota reservation.
- **Response**: `200 OK` `{"data":{"status":"cancelled"}}`
