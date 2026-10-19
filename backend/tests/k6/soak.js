import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const BASE_URL = __ENV.TARGET_URL || 'http://127.0.0.1:8085';

export const soakLatency = new Trend('soak_api_latency');
export const soakErrors = new Rate('soak_error_rate');
export const soakRequests = new Counter('soak_requests_completed');

export const options = {
  stages: [
    { duration: '5s', target: 20 },  // Ramp-up
    { duration: '30s', target: 20 }, // Steady soak state
    { duration: '5s', target: 0 },   // Ramp-down
  ],
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'soak_error_rate': ['rate<0.01'],
    'http_req_duration': ['p(95)<100'],
  },
};

export function setup() {
  const res = http.post(`${BASE_URL}/api/v1/test/token?user_id=soak-tester`);
  return { token: res.json('token') };
}

export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  const ep = Math.random();

  if (ep < 0.4) {
    const res = http.get(`${BASE_URL}/health/live`);
    const ok = check(res, { 'live 200': (r) => r.status === 200 });
    soakErrors.add(!ok);
    soakLatency.add(res.timings.duration);
    soakRequests.add(1);
  } else if (ep < 0.7) {
    const res = http.get(`${BASE_URL}/api/v1/plans`);
    const ok = check(res, { 'plans 200': (r) => r.status === 200 });
    soakErrors.add(!ok);
    soakLatency.add(res.timings.duration);
    soakRequests.add(1);
  } else {
    const res = http.get(`${BASE_URL}/api/v1/models`, { headers });
    const ok = check(res, { 'models 200': (r) => r.status === 200 });
    soakErrors.add(!ok);
    soakLatency.add(res.timings.duration);
    soakRequests.add(1);
  }

  sleep(0.05);
}
