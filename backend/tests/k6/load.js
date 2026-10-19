import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.TARGET_URL || 'http://127.0.0.1:8085';

// Custom metrics
export const errorRate = new Rate('custom_error_rate');
export const apiLatency = new Trend('custom_api_latency');
export const completedRequests = new Counter('custom_requests_total');

export const options = {
  stages: [
    { duration: '3s', target: 20 },  // Ramp-up to 20 VUs
    { duration: '10s', target: 50 }, // Sustained load at 50 VUs
    { duration: '3s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration': ['p(50)<50', 'p(95)<150', 'p(99)<300'],
    'custom_error_rate': ['rate<0.01'],
  },
};

export function setup() {
  // Pre-generate a test token
  const res = http.post(`${BASE_URL}/api/v1/test/token?user_id=load-tester-pool`);
  const token = res.json('token');
  return { token };
}

export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  // Randomized endpoint distribution
  const rand = Math.random();

  if (rand < 0.30) {
    // 30%: Public health & plans
    const res = http.get(`${BASE_URL}/health/live`);
    const success = check(res, { 'health live 200': (r) => r.status === 200 });
    errorRate.add(!success);
    apiLatency.add(res.timings.duration);
    completedRequests.add(1);
  } else if (rand < 0.60) {
    // 30%: Plans catalog
    const res = http.get(`${BASE_URL}/api/v1/plans`);
    const success = check(res, { 'plans 200': (r) => r.status === 200 });
    errorRate.add(!success);
    apiLatency.add(res.timings.duration);
    completedRequests.add(1);
  } else if (rand < 0.85) {
    // 25%: Authenticated models & entitlements
    const res = http.get(`${BASE_URL}/api/v1/models`, { headers });
    const success = check(res, { 'models 200': (r) => r.status === 200 });
    errorRate.add(!success);
    apiLatency.add(res.timings.duration);
    completedRequests.add(1);
  } else {
    // 15%: Conversation creation & list
    const convRes = http.post(
      `${BASE_URL}/api/v1/conversations`,
      JSON.stringify({ title: 'Load Test Chat', category: 'general' }),
      { headers }
    );
    const success = check(convRes, { 'create conv 201': (r) => r.status === 200 || r.status === 201 });
    errorRate.add(!success);
    apiLatency.add(convRes.timings.duration);
    completedRequests.add(1);
  }

  sleep(0.05); // Rapid paced concurrent load
}
