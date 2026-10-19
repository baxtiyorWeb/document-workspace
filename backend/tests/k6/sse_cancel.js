import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = __ENV.TARGET_URL || 'http://127.0.0.1:8085';

export const cancelLatency = new Trend('cancel_call_latency');
export const streamDuration = new Trend('stream_active_duration');
export const cancelSuccess = new Counter('cancellations_successful_total');

export const options = {
  scenarios: {
    sse_cancellation_load: {
      executor: 'constant-vus',
      vus: 10,
      duration: '10s',
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.02'],
    'cancel_call_latency': ['p(95)<100'],
  },
};

export function setup() {
  const res = http.post(`${BASE_URL}/api/v1/test/token?user_id=cancel-tester`);
  return { token: res.json('token') };
}

export default function (data) {
  const headers = {
    'Authorization': `Bearer ${data.token}`,
    'Content-Type': 'application/json',
  };

  const convID = `conv-cancel-${__VU}-${__ITER}`;

  // 1. Initiate Streaming generation
  const payload = JSON.stringify({
    message: 'Write an extremely long essay about quantum computing algorithms.',
    model_id: 'nemotron-ultra',
  });

  const streamStart = Date.now();
  const streamRes = http.post(
    `${BASE_URL}/api/v1/conversations/${convID}/generations`,
    payload,
    { headers, timeout: '5s' }
  );

  streamDuration.add(Date.now() - streamStart);

  check(streamRes, {
    'stream status is 200': (r) => r.status === 200,
    'stream received sse data': (r) => (r.body || '').includes('generation'),
  });

  // Extract generation_id if present in body
  const body = streamRes.body || '';
  const match = body.match(/"generation_id":"([^"]+)"/);
  if (match && match[1]) {
    const genID = match[1];

    // Issue cancel call
    const cancelStart = Date.now();
    const cancelRes = http.post(
      `${BASE_URL}/api/v1/generations/${genID}/cancel`,
      null,
      { headers, expectedStatuses: [200, 409] }
    );
    cancelLatency.add(Date.now() - cancelStart);

    const isOk = check(cancelRes, {
      'cancel returned 200 or 409 (if finished)': (r) => r.status === 200 || r.status === 409,
    });
    if (isOk) {
      cancelSuccess.add(1);
    }
  }

  sleep(0.1);
}
