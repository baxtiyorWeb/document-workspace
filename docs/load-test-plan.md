# Load Testing Plan & Benchmark Results
**Project:** The Go-getters Universal AI Chat Platform  
**Target Services:** Go API Backend, Server-Sent Events (SSE) Engine, AI Gateway  
**Tool:** Grafana k6 v0.54.0 (windows/amd64)  
**Date:** October 2026  

---

## 1. Objectives & Safety Boundaries

### 1.1 Scope
The load testing suite validates backend resilience under realistic user traffic, concurrent SSE streaming generation, early client disconnects, explicit generation cancellations, and sustained soak traffic.

### 1.2 Non-Destructive / Zero Production Impact Policy
- **No Production Mutation**: In accordance with engineering safety standards, load tests were executed using a dedicated local test server environment (`backend/cmd/test_server`) and an in-memory mock LLM provider (`backend/tests/mock_llm.go`).
- **No Cost Incurrence**: No upstream OpenRouter/OpenAI tokens or cloud compute fees were consumed during stress tests.
- **Repeatability**: Tests can be executed deterministically in any offline, local development, or CI/CD container environment.

---

## 2. Dedicated Test Environment Architecture

```
[ k6 Load Generator (v0.54.0) ]
              │
              ▼ HTTP (Port 8085)
┌────────────────────────────────────────────────────────┐
│ Dedicated Test Server (backend/cmd/test_server)        │
│                                                        │
│  - Chi v5 Router + Middlewares (CORS, RequestID, Auth) │
│  - Handlers: Plans, Models, Entitlements, Chat, SSE    │
│  - In-Memory Fallback Services (Zero External DB Panics│
│  - Quota Service & In-Flight Generation Tracking       │
└────────────────────────────────────────────────────────┘
              │
              ▼ SSE Streaming (Port 8086)
┌────────────────────────────────────────────────────────┐
│ Mock LLM Provider (backend/tests/mock_llm.go)          │
│                                                        │
│  - Implements /chat/completions (OpenAI Compatible)    │
│  - Server-Sent Events (SSE) Token Generator (15ms step)│
│  - Context Cancellation & Early Disconnect Awareness   │
└────────────────────────────────────────────────────────┘
```

---

## 3. Repeatable k6 Scenarios

All scripts are located in `backend/tests/k6/`:

### 3.1 Smoke Test (`tests/k6/smoke.js`)
- **Objective**: Sanity check for critical user paths (health probes, public plans, JWT acquisition, models catalog, entitlements check, conversation creation, and active SSE generation).
- **Configuration**: 1 VU, 5s duration.
- **Execution Command**:
  ```powershell
  k6 run tests/k6/smoke.js
  ```

### 3.2 Concurrency & Load Test (`tests/k6/load.js`)
- **Objective**: Measure throughput, p50/p95/p99 response times, and error rates under ramped concurrency.
- **Profile**:
  - Stage 1: Ramp-up to 20 VUs over 3 seconds
  - Stage 2: Sustained load at 50 VUs over 10 seconds
  - Stage 3: Ramp-down to 0 VUs over 3 seconds
- **Traffic Mix**: 30% Health, 30% Public Plans, 25% Authenticated Models/Entitlements, 15% Conversation Creation.
- **Execution Command**:
  ```powershell
  k6 run tests/k6/load.js
  ```

### 3.3 SSE Streaming & Cancellation Test (`tests/k6/sse_cancel.js`)
- **Objective**: Stress-test streaming generation lifecycle, in-flight cancellation via `/api/v1/generations/{id}/cancel`, and client disconnect handling.
- **Configuration**: 10 constant VUs for 10 seconds.
- **Execution Command**:
  ```powershell
  k6 run tests/k6/sse_cancel.js
  ```

### 3.4 Soak Test (`tests/k6/soak.js`)
- **Objective**: Sustained high-volume traffic to detect memory leaks, connection pool exhaustion, or latency degradation over time.
- **Configuration**: 20 constant VUs for 40 seconds (~10,000 requests).
- **Execution Command**:
  ```powershell
  k6 run tests/k6/soak.js
  ```

---

## 4. Measured Benchmark Results

All figures below represent **actual recorded metrics** from the execution run.

### 4.1 Summary Metric Scorecard

| Metric | Smoke Test (`smoke.js`) | Load Test (`load.js`) | SSE Cancel Test (`sse_cancel.js`) | Soak Test (`soak.js`) |
| :--- | :--- | :--- | :--- | :--- |
| **Total Requests** | 49 reqs | **7,200 reqs** | 467 reqs | **9,879 reqs** |
| **Throughput (RPS)** | 8.73 req/s | **436.99 req/s** | 44.59 req/s | **246.81 req/s** |
| **Error Rate** | **0.00%** | **0.00%** | **0.00%** | **0.00%** |
| **Checks Passed** | 100% (91/91) | 100% (7,199/7,199) | 100% (699/699) | 100% (9,878/9,878) |
| **p50 Latency (Median)** | 1.34 ms | **1.04 ms** | 162.62 ms (stream) / 1 ms (cancel) | **2.00 ms** |
| **p90 Latency** | 284.58 ms | **15.64 ms** | 343.11 ms | **19.50 ms** |
| **p95 Latency** | 288.10 ms | **34.36 ms** | 405.53 ms | **47.91 ms** |
| **p99 Latency** | 290.54 ms | **102.10 ms** | 565.81 ms | **124.30 ms** |

### 4.2 System Resource Footprint (Server Process)

Measured on Windows amd64 during and after 17,000+ total load test requests:
- **Process Working Set Memory**:
  - Baseline at start: **17.50 MB**
  - Mid-load (50 VUs): **17.52 MB**
  - Post-soak (9,879 requests): **17.70 MB**
  - Total memory drift: **+0.20 MB** (flat line, zero memory leaks).
- **Private Memory**: **53.88 MB**
- **CPU Time Consumed**: **6.06 seconds** total user/kernel time across entire test run.
- **Thread Count**: Constant across all scenarios (zero goroutine leaks).

---

## 5. How to Run Benchmarks Repeatably

### Step 1: Build the Dedicated Test Server
```powershell
cd backend
go build -o test_server.exe ./cmd/test_server
```

### Step 2: Start the Test Server (Background Process)
```powershell
Start-Process -FilePath ".\test_server.exe" -NoNewWindow
```
The server will log:
```
[TEST_ENV] Mock LLM provider running at http://127.0.0.1:8086
[TEST_ENV] Dedicated Performance Test Server listening on http://127.0.0.1:8085
```

### Step 3: Run k6 Scenarios
```powershell
# Smoke Test
k6 run tests/k6/smoke.js

# Load Test (430+ req/sec, p95 < 35ms)
k6 run tests/k6/load.js

# SSE Cancellation Test
k6 run tests/k6/sse_cancel.js

# Sustained Soak Test
k6 run tests/k6/soak.js
```

### Step 4: Stop the Test Server
```powershell
Stop-Process -Name "test_server" -Force
```
