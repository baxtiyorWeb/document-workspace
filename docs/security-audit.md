# Application Cybersecurity Audit Report — The Go-getters

**Date:** 2026-10-16  
**Auditor:** Application Cybersecurity Audit Agent  
**Target Systems:**
- Go REST & SSE Streaming Backend (`backend/`)
- Flutter Android Application (`mobile/`)
- PostgreSQL Persistence & Schema (`database.sql`, `backend/migrations/`)
- RevenueCat & Payment Integrations (`revenuecat-keys.txt`, `billing/`, `subscription/`)

**Reference Frameworks:**
- OWASP Application Security Verification Standard (ASVS 4.0)
- OWASP API Security Top 10 (2023)
- OWASP Mobile Application Security Verification Standard (MASVS / MASTG)
- OWASP Top 10 for Large Language Model Applications (2025)

---

## 1. Executive Summary

A comprehensive, defense-in-depth cybersecurity audit of **The Go-getters AI Platform** repository was conducted in a read-only inspection phase. The codebase exhibits modern architectural design, parameterized SQL queries throughout, robust bcrypt hashing, and structured SSE streaming.

However, several critical and high-severity vulnerabilities were identified across billing integrity, tenant isolation in RAG retrieval, exposed secret keys, quota race conditions, and mobile transport security.

### Summary of Findings by Severity

| ID | Title | Severity | Standard Reference | Status |
|---|---|---|---|---|
| **SEC-01** | Client-Authoritative Plan Escalation in `/api/v1/billing/sync` | **CRITICAL** | OWASP API6:2023 / ASVS V1.15 | Confirmed |
| **SEC-02** | Cross-User Document Data Leakage / IDOR in RAG Pipeline | **CRITICAL** | OWASP API1:2023 / LLM08:2025 | Confirmed |
| **SEC-03** | Plaintext Live Secret Key in Workspace & Incomplete `.gitignore` | **HIGH** | OWASP ASVS V14.2 / CWE-312 | Confirmed |
| **SEC-04** | Time-of-Check to Time-of-Use (TOCTOU) Quota Bypass Race Condition | **HIGH** | OWASP API4:2023 / CWE-362 | Confirmed |
| **SEC-05** | RevenueCat Webhook Authentication Bypass in Unconfigured Environments | **HIGH** | OWASP API2:2023 / ASVS V3.6 | Confirmed |
| **SEC-06** | Unrestricted Decompression / Zip Bomb Vulnerability in File Parsers | **HIGH** | OWASP ASVS V12.1 / CWE-409 | Confirmed |
| **SEC-07** | Overly Permissive CORS with Wildcard Origin & Credentials | **MEDIUM** | OWASP API7:2023 / ASVS V14.4 | Confirmed |
| **SEC-08** | Android Production Manifest Allows Cleartext HTTP Traffic | **MEDIUM** | OWASP MASVS-NETWORK / CWE-319 | Confirmed |
| **SEC-09** | Insecure Fallback to Unencrypted SharedPreferences & Missing Backup Control | **MEDIUM** | OWASP MASVS-STORAGE / CWE-922 | Confirmed |
| **SEC-10** | Suspended / Deactivated User Bypass via Refresh Token Rotation | **MEDIUM** | OWASP ASVS V3.2 / API2:2023 | Confirmed |
| **SEC-11** | Missing Brute-Force Rate Limiting on Authentication Endpoints | **LOW** | OWASP API8:2023 / ASVS V2.2 | Confirmed |
| **SEC-12** | Indirect Prompt Injection Vulnerability in RAG Delimiters | **LOW** | OWASP LLM01:2025 / LLM07:2025 | Confirmed |

---

## 2. Threat Model Assessment

```
                      +---------------------------------------+
                      |       Attacker / Malicious User       |
                      +---------------------------------------+
                           |              |             |
           (Fake Webhook)  |              |             | (Manipulated Sync Request)
                           v              |             v
    [POST /billing/webhook]               |   [POST /billing/sync {"is_active": true}]
     (Unauthenticated Dev Bypass)         |    (Client-Authoritative Plan Escalation)
                           |              |             |
                           +--------+     |     +-------+
                                    |     |     |
                                    v     v     v
                         +-----------------------------+
                         |      Go Backend API         |
                         +-----------------------------+
                           |              |            |
  (Cross-User File IDs)    |              |            | (Concurrent Requests)
  [POST .../generations]   |              |            | [Quota Check Race]
           |               |              |            |
           v               |              v            v
 +-------------------+     |     +-------------------------+
 | Missing user_id   |     |     | Non-Atomic SELECT/COUNT |
 | filter in chunks  |     |     | Usage Ledger Bypass     |
 +-------------------+     |     +-------------------------+
           |               |
           v               v
  (Private Document Data Injected into Prompt)
```

### Trust Boundaries & Assets
1. **Client to Backend**: Mobile client must be treated as untrusted. Never accept client-asserted permissions, plan upgrades, or arbitrary cross-user identifiers.
2. **Document & RAG Store**: User-uploaded documents and text chunks must have strict row-level ownership enforcement.
3. **Upstream AI Gateway**: API keys and model credentials must never leave the server boundary or be exposed to client configurations.
4. **Payment Webhooks**: Inbound notifications from payment providers (RevenueCat / Lemon Squeezy) require mandatory cryptographic validation.

---

## 3. Detailed Vulnerability Findings

### SEC-01 [CRITICAL]: Client-Authoritative Plan Escalation via `/api/v1/billing/sync`

- **Severity:** CRITICAL (CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N - Base Score: 8.1)
- **Standard Reference:** OWASP API Security Top 10 API6:2023 (Flawed Business Logic / Mass Assignment), OWASP ASVS V1.15
- **File & Line:**
  - `backend/internal/billing/revenuecat.go` (Lines 150–197)
  - `backend/internal/http/handlers/billing.go` (Lines 62–88)
- **Evidence:**
  ```go
  // backend/internal/billing/revenuecat.go
  func (h *RevenueCatHandler) SyncFromClient(ctx context.Context, userID string, req ClientSyncRequest) error {
      status := "active"
      planID := "pro"
      if !req.IsActive {
          status = "expired"
          planID = "free"
      }
      ...
      // Update user's direct plan_id
      _, err = h.pool.Exec(ctx, `UPDATE users SET plan_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2::uuid`, planID, userID)
      return err
  }
  ```
- **Impact:** Any authenticated user on the free tier can issue an HTTP POST request to `/api/v1/billing/sync` with payload `{"is_active": true}` to grant themselves the Pro plan for free, bypassing all paywalls and financial controls.
- **Remediation:**
  1. Deprecate client-asserted `is_active` updates.
  2. Implement server-side verification: when a sync request is received, the backend must query RevenueCat V2 API (`https://api.revenuecat.com/v2/projects/{project_id}/customers/{customer_id}`) using the server's private `REVENUECAT_API_KEY` to verify active entitlements.
  3. Alternatively, make subscription activation strictly event-driven via cryptographically signed webhooks.
- **Regression Tests:**
  - Unit/Integration test: Submit `POST /api/v1/billing/sync` with `{"is_active": true}` using a free user JWT without upstream RevenueCat proof; assert that the user plan remains `free` and request is rejected or validated against upstream API.
- **Residual Risk:** Dependency on upstream RevenueCat API availability during synchronous restore requests.

---

### SEC-02 [CRITICAL]: Cross-User Document Data Leakage / IDOR in RAG Pipeline

- **Severity:** CRITICAL (CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:N/A:N - Base Score: 8.5)
- **Standard Reference:** OWASP API Security API1:2023 (Broken Object Level Authorization), OWASP LLM08:2025 (Vector & RAG Cross-user Document Leakage)
- **File & Line:**
  - `backend/internal/generations/service.go` (Lines 156–178)
  - `backend/internal/files/service.go` (Lines 226–270)
- **Evidence:**
  In `generations/service.go`:
  ```go
  for _, fID := range fileIDs {
      f, err := s.filesService.GetFile(r.Context(), userID, fID)
      if err == nil && f != nil && f.FileType == files.FileTypeImage {
          hasImages = true
      }
  }
  // All fileIDs passed regardless of GetFile ownership result!
  ctxStr, cList, err := s.filesService.RetrieveRelevantContext(r.Context(), fileIDs, userMessageContent)
  ```
  In `files/service.go`:
  ```sql
  SELECT c.file_id, f.filename, c.page_number, c.section_title, c.content
  FROM file_chunks c
  JOIN files f ON f.id = c.file_id
  WHERE c.file_id = ANY($1::uuid[])
  ```
- **Impact:** There is no check verifying that `fileIDs` belong to the calling `userID`. A malicious user who obtains, guesses, or enumerates file UUIDs belonging to other users can submit them in `file_ids` during generation. The server extracts chunks from the victim's private files and injects them into the attacker's prompt, leaking private documents, proprietary data, and PII.
- **Remediation:**
  1. In `files/service.go`, update `RetrieveRelevantContext` signature to accept `userID string` and enforce SQL tenant isolation:
     `WHERE c.file_id = ANY($1::uuid[]) AND f.user_id = $2::uuid`
  2. In `generations/service.go`, filter `fileIDs` strictly to validated owned files prior to calling retrieval.
- **Regression Tests:**
  - Integration test: User A uploads file `F_A`. User B calls `POST /conversations/{conv_B}/generations` specifying `file_ids: [F_A]`. Verify that zero chunks are retrieved and response does not contain file content or citations from User A.
- **Residual Risk:** None after enforcing parameterized SQL user_id isolation in retrieval queries.

---

### SEC-03 [HIGH]: Plaintext Live Secret Key in Workspace & Unsafe `.gitignore`

- **Severity:** HIGH (CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N - Base Score: 7.7)
- **Standard Reference:** OWASP ASVS V14.2 (Secrets Management), CWE-312
- **File & Line:**
  - `revenuecat-keys.txt` (Line 4)
  - `.gitignore` (Lines 1–37)
- **Evidence:**
  `revenuecat-keys.txt` contains a live RevenueCat secret key:
  ```
  SECRET_API_KEY=sk_...
  ```
  Additionally, `.gitignore` omits `revenuecat-keys.txt` and `backend/storage/uploads/`.
- **Impact:** Plaintext API keys stored in workspace directories risk inadvertent commit to source control repositories. Exposure of RevenueCat secret API keys allows unauthorized access to customer records, entitlement tampering, and subscriber metadata.
- **Remediation:**
  1. Immediately rotate the exposed secret key in the RevenueCat dashboard.
  2. Remove `revenuecat-keys.txt` from local workspace.
  3. Add `revenuecat-keys.txt`, `*.txt` key artifacts, and `backend/storage/uploads/` to `.gitignore`.
- **Regression Tests:**
  - Automated pre-commit hook / secret scanning check (e.g. `gitleaks` or `trufflehog`) detecting `sk_` and API key patterns.
- **Residual Risk:** Any commits previously pushed to external Git remotes require history purging or key revocation.

---

### SEC-04 [HIGH]: Time-of-Check to Time-of-Use (TOCTOU) Quota Bypass Race Condition

- **Severity:** HIGH (CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:H/A:N - Base Score: 5.3)
- **Standard Reference:** OWASP API Security API4:2023 (Unrestricted Resource Consumption), CWE-362
- **File & Line:**
  - `backend/internal/gateway/quotas.go` (Lines 48–164)
- **Evidence:**
  `ReserveQuota` executes a non-atomic `SELECT COUNT(*) FROM usage_ledger WHERE user_id = $1...`, checks limits in Go memory, and then executes a separate `INSERT INTO usage_ledger`.
  ```go
  // Query usage counts across all 3 windows
  err := q.pool.QueryRow(ctx, `SELECT COUNT(*) ... FROM usage_ledger ...`).Scan(...)
  ...
  // In-memory check
  if hourlyCount >= limits.HourlyLimit { return QuotaError }
  ...
  // Subsequent separate INSERT
  err = q.pool.QueryRow(ctx, `INSERT INTO usage_ledger ...`).Scan(...)
  ```
- **Impact:** An attacker dispatching 20–50 concurrent requests at the exact same millisecond will find that all concurrent checks see `used < limit`, allowing simultaneous executions to bypass hourly, daily, and weekly quotas. This can lead to financial exhaustion of backend AI provider credits.
- **Remediation:** Execute the quota reservation within a serializable transaction with advisory locking on `user_id` (`pg_advisory_xact_lock(hashtext($1))`), or execute an atomic conditional insertion:
  ```sql
  INSERT INTO usage_ledger (id, user_id, conversation_id, model_id, plan_id, status)
  SELECT gen_random_uuid(), $1, $2, $3, $4, 'reserved'
  WHERE (SELECT COUNT(*) FROM usage_ledger WHERE user_id = $1 AND created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour' AND status IN ('reserved', 'settled')) < $5
  RETURNING id;
  ```
  If zero rows are returned, reject the request immediately with `HOURLY_LIMIT_EXCEEDED`.
- **Regression Tests:**
  - Concurrency integration test: Dispatch 20 concurrent goroutines against `ReserveQuota` for a user with 5 quota slots remaining. Verify that exactly 5 succeed and 15 fail with `PLAN_LIMIT_EXCEEDED`.
- **Residual Risk:** Minor database lock contention on extreme burst loads.

---

### SEC-05 [HIGH]: RevenueCat Webhook Authentication Bypass in Unconfigured Environments

- **Severity:** HIGH (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:N - Base Score: 7.5)
- **Standard Reference:** OWASP API Security API2:2023 (Broken Authentication), OWASP ASVS V3.6
- **File & Line:**
  - `backend/internal/billing/revenuecat.go` (Lines 76–86)
- **Evidence:**
  ```go
  func (h *RevenueCatHandler) VerifyAuthorization(authHeader string) bool {
      if h.authToken == "" {
          // If no token is configured in server environment, warn and accept for development
          log.Println("[WARN] [RevenueCat] REVENUECAT_WEBHOOK_AUTH_TOKEN is not configured; allowing request in dev mode")
          return true
      }
      ...
  }
  ```
- **Impact:** In staging or production deployments where `REVENUECAT_WEBHOOK_AUTH_TOKEN` is accidentally omitted from `.env` or container environment variables, the system fails open. Any unauthenticated attacker can forge webhook events and alter customer subscriptions.
- **Remediation:** Fail closed. If `h.authToken == ""`, reject all incoming webhook requests with HTTP 401 Unauthorized or refuse server startup if billing is enabled.
- **Regression Tests:**
  - Unit test: With `authToken = ""`, assert `VerifyAuthorization` returns `false`.
- **Residual Risk:** Staging setups must provide a placeholder secret for webhook tests.

---

### SEC-06 [HIGH]: Unrestricted Decompression / Zip Bomb Vulnerability in File Parsers (DoS)

- **Severity:** HIGH (CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H - Base Score: 6.5)
- **Standard Reference:** OWASP ASVS V12.1 (File Parsing & Denial of Service), CWE-409
- **File & Line:**
  - `backend/internal/files/parsers.go` (`ExtractDocxContent`, `ExtractXLSXContent`, `ExtractPPTXContent`, `decompressZlib`)
- **Evidence:**
  In `parsers.go`, archive members and zlib streams are decompressed using unbounded readers:
  ```go
  rc, err := f.Open()
  decoder := xml.NewDecoder(rc) // Unbounded stream read
  ...
  zr, err := zlib.NewReader(bytes.NewReader(data))
  var out bytes.Buffer
  io.Copy(&out, zr) // Unbounded zlib decompression
  ```
- **Impact:** An authenticated user uploading a crafted DOCX, XLSX, or PDF containing a compression bomb (e.g. 50KB expanding to 20GB) can cause rapid CPU spikes, RAM exhaustion, and Go runtime out-of-memory panics, causing denial of service to all users.
- **Remediation:**
  1. Wrap all decompression readers in `io.LimitReader(rc, maxDecompressedBytes)` (e.g., maximum 50MB uncompressed).
  2. In `decompressZlib`, use `io.CopyN(&out, zr, maxDecompressedBytes)`.
- **Regression Tests:**
  - Unit test with a compressed file exceeding decompression quota; verify parser returns `ErrFileCorrupted` or a bounded error without exceeding memory limits.
- **Residual Risk:** Legitimate, unusually large complex documents may be truncated if thresholds are set too low.

---

### SEC-07 [MEDIUM]: Overly Permissive CORS with Wildcard Origin & Credentials

- **Severity:** MEDIUM (CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:N - Base Score: 5.4)
- **Standard Reference:** OWASP API Security API7:2023 (Security Misconfiguration), OWASP ASVS V14.4
- **File & Line:**
  - `backend/cmd/api/main.go` (Lines 374–381)
- **Evidence:**
  ```go
  r.Use(cors.Handler(cors.Options{
      AllowedOrigins:   []string{"*"},
      AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
      AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "X-Signature"},
      ExposedHeaders:   []string{"Link", "X-Request-ID"},
      AllowCredentials: true,
      MaxAge:           300,
  }))
  ```
- **Impact:** `AllowedOrigins: []string{"*"}` with `AllowCredentials: true` is non-standard. Many CORS engines reflect the calling origin when credentials are enabled, potentially exposing authenticated API responses across origins. Furthermore, `cfg.AllowedOrigins` is completely ignored by `main.go`.
- **Remediation:** Bind CORS configuration to `cfg.AllowedOrigins` (comma-separated list of allowed origins), and disallow `AllowCredentials: true` with wildcard origins.
- **Regression Tests:**
  - HTTP OPTIONS request test asserting that unauthorized origins do not receive `Access-Control-Allow-Origin` with `Access-Control-Allow-Credentials: true`.
- **Residual Risk:** Client web deployments must have their exact domains added to `ALLOWED_ORIGINS`.

---

### SEC-08 [MEDIUM]: Android Production Manifest Enables Cleartext HTTP Traffic

- **Severity:** MEDIUM (CVSS:3.1/AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N - Base Score: 6.5)
- **Standard Reference:** OWASP MASVS-NETWORK, CWE-319
- **File & Line:**
  - `mobile/android/app/src/main/AndroidManifest.xml` (Line 9)
- **Evidence:**
  ```xml
  <application
      android:label="The Go-getters"
      android:name="${applicationName}"
      android:icon="@mipmap/ic_launcher"
      android:usesCleartextTraffic="true">
  ```
- **Impact:** Cleartext HTTP communication is globally allowed on Android. If the app connects over HTTP (e.g. public Wi-Fi or compromised router), JWT tokens, conversation transcripts, and uploaded files are transmitted in cleartext and subject to interception.
- **Remediation:** Remove `android:usesCleartextTraffic="true"` from `src/main/AndroidManifest.xml`. If local development over cleartext is needed, restrict it to `src/debug/AndroidManifest.xml` or configure a debug `network_security_config.xml` that permits cleartext only for `10.0.2.2` and `localhost`.
- **Regression Tests:**
  - Static manifest analysis verifying `usesCleartextTraffic` is absent or false in release manifests.
- **Residual Risk:** Developers running debug builds against local IP addresses must configure port forwarding (`adb reverse tcp:8080 tcp:8080`) or local HTTPS proxies.

---

### SEC-09 [MEDIUM]: Insecure Fallback to Unencrypted SharedPreferences & Missing Backup Control

- **Severity:** MEDIUM (CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N - Base Score: 6.2)
- **Standard Reference:** OWASP MASVS-STORAGE, CWE-922
- **File & Line:**
  - `mobile/lib/core/storage/storage_service.dart` (Lines 14–41)
  - `mobile/android/app/src/main/AndroidManifest.xml`
- **Evidence:**
  `StorageService` disables `encryptedSharedPreferences`:
  ```dart
  FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,
      resetOnError: true,
    ),
  );
  ```
  And implements an unencrypted fallback:
  ```dart
  try {
    await _secureStorage.write(key: key, value: value);
  } catch (e) {
    _useFallback = true;
    final prefs = await _getPrefs();
    await prefs.setString(key, value); // Plaintext XML storage!
  }
  ```
  Additionally, `android:allowBackup` is omitted from `AndroidManifest.xml` (defaults to `true`).
- **Impact:** Sensitive authentication credentials (JWT access tokens and refresh tokens) can be written into plaintext XML files. These files can be extracted via `adb backup` or physical access to unlocked devices.
- **Remediation:**
  1. Set `encryptedSharedPreferences: true` in `AndroidOptions`.
  2. Do not fallback to unencrypted `SharedPreferences` for authentication tokens. If secure storage fails, return a graceful error prompting the user to re-authenticate.
  3. Explicitly set `android:allowBackup="false"` in `AndroidManifest.xml`.
- **Regression Tests:**
  - Test verifying tokens are encrypted on disk and `allowBackup` is `false`.
- **Residual Risk:** Older Android devices with faulty vendor KeyStore implementations may require app re-installs if keys desynchronize.

---

### SEC-10 [MEDIUM]: Suspended / Deactivated User Bypass via Refresh Token Rotation

- **Severity:** MEDIUM (CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:L/I:L/A:N - Base Score: 5.4)
- **Standard Reference:** OWASP ASVS V3.2 (Session Management), OWASP API Security API2:2023
- **File & Line:**
  - `backend/internal/auth/service.go` (Lines 120–161)
- **Evidence:**
  In `Login()`, the user status is verified:
  ```go
  if user.Status != "active" {
      return nil, fmt.Errorf("hisob faol emas")
  }
  ```
  However, in `RefreshToken()`, after querying the user record:
  ```go
  user, err := s.GetUserByID(ctx, userID)
  if err != nil {
      return nil, err
  }
  return s.generateAuthSession(ctx, user, userAgent, ip)
  ```
  The user status is never checked.
- **Impact:** An administrator suspending or deactivating a user account does not stop that user from exchanging their refresh token for new access tokens. The suspended account can continue calling protected endpoints until the refresh session expires.
- **Remediation:** Add a status check in `RefreshToken()`:
  ```go
  if user.Status != "active" {
      return nil, errors.New("ACCOUNT_SUSPENDED: Ushbu hisob faol emas")
  }
  ```
- **Regression Tests:**
  - Unit test: Update user `status = 'suspended'`; assert `RefreshToken` fails with `ACCOUNT_SUSPENDED`.
- **Residual Risk:** Active JWT access tokens remain valid until expiration (15 minutes); an access token blacklist is needed if instantaneous revocation is required.

---

### SEC-11 [LOW]: Missing Brute-Force Rate Limiting on Authentication Endpoints

- **Severity:** LOW (CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N - Base Score: 3.7)
- **Standard Reference:** OWASP API Security API8:2023, OWASP ASVS V2.2
- **File & Line:**
  - `backend/cmd/api/main.go`
  - `backend/internal/http/handlers/auth.go`
- **Evidence:** No IP-based or account-based rate limiting middleware is applied to `/api/v1/auth/login` or `/api/v1/auth/register`.
- **Impact:** Automated attacks (credential stuffing, dictionary brute forcing, and mass registration spam) can be conducted without throttling.
- **Remediation:** Introduce a rate-limiting middleware (e.g. `go-chi/httprate` or a Redis token bucket) limiting authentication endpoints to 5–10 requests per minute per IP.
- **Regression Tests:**
  - Test verifying that rapid successive login requests from the same IP result in HTTP 429 Too Many Requests.
- **Residual Risk:** Distributed botnets can cycle IP addresses.

---

### SEC-12 [LOW]: Indirect Prompt Injection Vulnerability in RAG Delimiters

- **Severity:** LOW (CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:L/I:L/A:N - Base Score: 4.2)
- **Standard Reference:** OWASP Top 10 for LLM Applications 2025 (LLM01: Prompt Injection)
- **File & Line:**
  - `backend/internal/files/service.go` (Lines 295–302)
  - `backend/internal/generations/service.go` (Lines 314–322)
- **Evidence:** Document context snippets are interpolated with static tags:
  ```
  <<<HUJJATLAR_KONTEKSTI_START (XAVFSIZLIK: TASHQI MA'LUMOT)>>>
  ...
  <<<HUJJATLAR_KONTEKSTI_END>>>
  ```
  If an uploaded file contains `<<<HUJJATLAR_KONTEKSTI_END>>>` followed by new instructions, the LLM may interpret the document text as system directives.
- **Impact:** Evasion of system prompt constraints, extraction of backend prompt instructions, or biased answers.
- **Remediation:** Sanitize document snippets to strip or escape delimiter markers, or use structured XML/JSON message schemas with explicit instructions.
- **Regression Tests:**
  - Prompt injection test dataset verifying that delimiter break attempts in uploaded documents do not alter expected safety behaviors.
- **Residual Risk:** Inherent non-deterministic nature of large language models.

---

## 4. Prioritized Remediation Roadmap

```
+--------------------------------------------------------------------------+
| PHASE 1: IMMEDIATE ISOLATED DEFENSE FIXES (No Shared Contract Changes)   |
| - SEC-02: Enforce user_id tenant isolation in RetrieveRelevantContext   |
| - SEC-05: Webhook authorization fail-closed enforcement                  |
| - SEC-06: Bound decompression stream lengths (Zip bomb defense)          |
| - SEC-08: Disable cleartext HTTP traffic in release AndroidManifest.xml   |
| - SEC-09: Enable encryptedSharedPreferences and allowBackup=false       |
| - SEC-10: Verify user.Status == "active" on token refresh               |
+--------------------------------------------------------------------------+
                                    |
                                    v
+--------------------------------------------------------------------------+
| PHASE 2: COORDINATED CORE ARCHITECTURE CHANGES (Peer Agent Alignment)    |
| - SEC-01: Replace client-authoritative sync with server-side RevenueCat  |
|           API verification or webhook-only entitlement grants            |
| - SEC-03: Rotate exposed RevenueCat secret key & update .gitignore       |
| - SEC-04: Implement atomic SQL reservation query for quota checking      |
| - SEC-07: Configure explicit allowed origins for CORS                     |
+--------------------------------------------------------------------------+
```

---

## 5. Residual Risk & Assurance Statement

> [!WARNING]
> In accordance with professional cybersecurity audit standards and ethical guidelines:
> Security cannot be mathematically guaranteed, and no audit can eliminate all potential vulnerabilities. Software security is an ongoing, lifecycle-driven practice.
>
> Residual risks remain regarding:
> 1. Third-party dependency security (upstream Go modules, Flutter packages, and Android Gradle dependencies).
> 2. Operational key rotation hygiene and cloud infrastructure configuration (PostgreSQL Neon SSL enforcement, Google Play console access controls).
> 3. Evolving prompt injection techniques targeting upstream LLM foundation models.

---
*Report generated and archived at `docs/security-audit.md`.*
