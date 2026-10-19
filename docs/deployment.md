# Universal AI Platform — Deployment & Operations Guide

This guide covers production deployment, environment setup, and the complete step-by-step Lemon Squeezy integration procedure.

---

## 1. Lemon Squeezy Setup (2026 Official API)

Once your Lemon Squeezy merchant account is approved or you are operating in Test Mode, follow these steps to connect your billing engine:

### Step 1: Create an API Key
1. Go to [Lemon Squeezy Dashboard](https://app.lemonsqueezy.com).
2. Navigate to **Settings** -> **API Keys**.
3. Click **Create API Key**, name it (e.g. `Universal-AI-Backend`), and copy the token.
4. Set in your server `.env`:
   ```env
   LEMON_SQUEEZY_API_KEY=your_api_key_here
   ```

### Step 2: Configure Webhooks
1. In Lemon Squeezy Dashboard, navigate to **Settings** -> **Webhooks**.
2. Click **Create Webhook**.
3. **Callback URL**: Enter your public backend URL:
   ```
   https://api.yourdomain.com/api/v1/billing/webhook
   ```
4. **Signing Secret**: Enter a strong secret (e.g., 32+ random characters).
5. Set in your server `.env`:
   ```env
   LEMON_SQUEEZY_WEBHOOK_SECRET=your_signing_secret_here
   ```
6. **Events to Select**:
   - `subscription_created`
   - `subscription_updated`
   - `subscription_cancelled`
   - `subscription_resumed`
   - `subscription_expired`
   - `subscription_payment_failed`
   - `order_refunded`

### Step 3: Store & Variant IDs (Automatic Discovery)
- **Automatic**: You do **not** need to manually find your Store ID and Variant ID. The Go backend features an `AutoDiscover` routine that queries `GET /v1/stores` and `GET /v1/variants` on the first checkout request and resolves them automatically!
- **Manual (Optional Override)**: If you have multiple stores or products, you can explicitly set:
   ```env
   LEMON_SQUEEZY_STORE_ID=123456
   LEMON_SQUEEZY_VARIANT_ID=789012
   ```

### Step 4: Test Mode vs Live Mode
- In development and sandbox testing:
  ```env
  LEMON_SQUEEZY_TEST_MODE=true
  ```
  *(Lemon Squeezy will provide test card numbers for zero-dollar trial checkouts).*
- When ready for real payments in production:
  ```env
  LEMON_SQUEEZY_TEST_MODE=false
  ```

---

## 2. Server Environment Variables (.env)

```env
# Application Port
PORT=8080

# PostgreSQL Connection String (Neon, RDS, Supabase, or Local)
DATABASE_URL=postgresql://user:password@endpoint.neon.tech/neondb?sslmode=require

# Authentication
JWT_SECRET=generate-a-cryptographically-secure-random-secret
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=168h

# Primary AI Mesh (OpenRouter or OpenAI Compatible)
AI_PROVIDER_BASE_URL=https://openrouter.ai/api/v1
AI_API_KEY=sk-or-v1-your-openrouter-key
AI_MODEL=nvidia/nemotron-3-ultra-550b-a55b:free

# Lemon Squeezy Billing
LEMON_SQUEEZY_API_KEY=
LEMON_SQUEEZY_STORE_ID=
LEMON_SQUEEZY_VARIANT_ID=
LEMON_SQUEEZY_WEBHOOK_SECRET=
LEMON_SQUEEZY_TEST_MODE=true

# Security
ALLOWED_ORIGINS=*
MAX_REQUEST_SIZE_MB=5
```

---

## 3. Database Migrations

Run database migrations to initialize or upgrade the schema:
```bash
cd backend
go run ./cmd/migrate
```
Or start the backend directly—it checks and applies schema updates on startup:
```bash
go run ./cmd/api
```

---

## 4. Running the Flutter Mobile Client

```bash
cd mobile
flutter pub get
flutter run
```

To point the Flutter client to a remote production backend:
1. Open the app.
2. Navigate to **Sozlamalar (Settings)** -> **Server Tarmoq Sozlamalari**.
3. Enter your server's API URL (e.g., `https://api.yourdomain.com`).
4. Tap **Saqlash (Save)**.
