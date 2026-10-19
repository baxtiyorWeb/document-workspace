import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1,
  duration: '5s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<400'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://127.0.0.1:8085';

export default function () {
  // 1. Health Liveness
  const liveRes = http.get(`${BASE_URL}/health/live`);
  const liveJson = JSON.parse(liveRes.body || '{}');
  check(liveRes, {
    'health live status is 200': (r) => r.status === 200,
    'health live body is live': () => liveJson.data && liveJson.data.status === 'live',
  });

  // 2. Public Plans
  const plansRes = http.get(`${BASE_URL}/api/v1/plans`);
  const plansJson = JSON.parse(plansRes.body || '{}');
  check(plansRes, {
    'plans status is 200': (r) => r.status === 200,
    'plans list has free and pro': () => plansJson.data && plansJson.data.length >= 2,
  });

  // 3. Acquire Token
  const tokenRes = http.post(`${BASE_URL}/api/v1/test/token?user_id=smoke-user-1`);
  const tokenJson = JSON.parse(tokenRes.body || '{}');
  check(tokenRes, {
    'token acquired': (r) => r.status === 200 && tokenJson.token !== undefined,
  });
  const token = tokenJson.token;
  const headers = {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  // 4. Models Catalog
  const modelsRes = http.get(`${BASE_URL}/api/v1/models`, { headers });
  const modelsJson = JSON.parse(modelsRes.body || '{}');
  check(modelsRes, {
    'models status is 200': (r) => r.status === 200,
    'models data returned': () => modelsJson.data && modelsJson.data.length >= 1,
  });

  // 5. Entitlements
  const entRes = http.get(`${BASE_URL}/api/v1/me/entitlements`, { headers });
  const entJson = JSON.parse(entRes.body || '{}');
  check(entRes, {
    'entitlements status is 200': (r) => r.status === 200,
    'plan_id is defined': () => entJson.data && entJson.data.plan_id !== undefined,
  });

  // 6. Create Conversation
  const convRes = http.post(
    `${BASE_URL}/api/v1/conversations`,
    JSON.stringify({ title: 'Smoke Test Conversation', category: 'general' }),
    { headers }
  );
  const convJson = JSON.parse(convRes.body || '{}');
  check(convRes, {
    'conversation created': (r) => (r.status === 200 || r.status === 201) && convJson.data && convJson.data.id !== undefined,
  });
  const convID = (convJson.data && convJson.data.id) ? convJson.data.id : 'conv-smoke-1';

  // 7. Streaming Generation (SSE)
  const genPayload = JSON.stringify({
    message: 'Hello, this is a smoke test prompt.',
    model_id: 'nemotron-ultra',
  });
  const genRes = http.post(
    `${BASE_URL}/api/v1/conversations/${convID}/generations`,
    genPayload,
    { headers }
  );
  check(genRes, {
    'generation stream status is 200': (r) => r.status === 200,
    'generation stream has sse content-type': (r) => (r.headers['Content-Type'] || '').includes('text/event-stream'),
    'generation contains completed event': (r) => r.body.includes('generation.completed') || r.body.includes('message.delta'),
  });

  sleep(0.5);
}
