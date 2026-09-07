import http from 'k6/http';
import { check, sleep } from 'k6';
import encoding from 'k6/encoding';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const ADMIN_USER = __ENV.API_ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = __ENV.API_ADMIN_PASSWORD;

if (!ADMIN_PASSWORD) {
  throw new Error('API_ADMIN_PASSWORD must be set for the load test');
}

const AUTH_HEADER = `Basic ${encoding.b64encode(`${ADMIN_USER}:${ADMIN_PASSWORD}`)}`;

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m', target: 25 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    // Contract from the requirements: p95 under 500ms, error rate under 1%.
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
  },
};

export default function () {
  const authParams = {
    headers: {
      Authorization: AUTH_HEADER,
      Accept: 'application/json',
    },
    tags: { endpoint: 'employees_list' },
  };

  const health = http.get(`${BASE_URL}/actuator/health`, {
    tags: { endpoint: 'health' },
  });
  check(health, {
    'health returns 200': (r) => r.status === 200,
    'health reports UP': (r) => String(r.body).includes('UP'),
  });

  const list = http.get(`${BASE_URL}/api/v1/employees`, authParams);
  check(list, {
    'list returns 200': (r) => r.status === 200,
    'list returns JSON array': (r) => String(r.body).trim().startsWith('['),
  });

  sleep(1);
}
