// Профіль «мало записів, багато читань»: на 1 запис припадає 9 читань (1:9).
// Запуск (з кореня репозиторію):
//   k6 run -e BASE_URL=http://<alb_dns> -e VUS=50 -e LABEL=no-cache loadtest/script.js
// Швидка перевірка локально (docker compose up):
//   k6 run -e BASE_URL=http://localhost:8000 -e VUS=3 -e RAMP_UP=10s -e STEADY=20s -e RAMP_DOWN=5s loadtest/script.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

const BASE = __ENV.BASE_URL;
const VUS = parseInt(__ENV.VUS || '50');   // N: підбирається експериментально (див. docs/LOADTEST.md)
const LABEL = __ENV.LABEL || 'run';

export const options = {
  scenarios: {
    notes_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: __ENV.RAMP_UP || '3m', target: VUS },   // фаза 1: наростання 0 -> N
        { duration: __ENV.STEADY || '5m', target: VUS },       // фаза 2: стале навантаження
        { duration: __ENV.RAMP_DOWN || '2m', target: 0 },      // фаза 3: спад N -> 0
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const AUTHORS = ['alice', 'bob', 'carol', 'dave', 'erin', 'frank', 'grace', 'heidi', 'ivan', 'judy'];
const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function setup() {
  if (!BASE) throw new Error('Вкажіть -e BASE_URL=http://...');
  const r = http.get(`${BASE}/health`);
  if (r.status !== 200) throw new Error(`/health повернув ${r.status}`);
}

function think() {
  sleep(0.3 + Math.random() * 0.4);   // пауза користувача 0.3-0.7 с
}

// tags.name групує запити за «шаблоном» URL, інакше k6 створить окрему метрику на кожен id
function get(path, name) {
  const r = http.get(`${BASE}${path}`, { tags: { name } });
  check(r, { [`${name} 200`]: (res) => res.status === 200 });
  think();
  return r;
}

export default function () {
  const author = AUTHORS[Math.floor(Math.random() * AUTHORS.length)];

  // 1 запис
  const created = http.post(
    `${BASE}/notes`,
    JSON.stringify({ title: `note ${Date.now()}`, body: 'lorem ipsum '.repeat(20), author }),
    { headers: JSON_HEADERS, tags: { name: 'POST /notes' } },
  );
  const ok = check(created, { 'POST /notes 201': (r) => r.status === 201 });
  if (!ok) { sleep(1); return; }
  const id = created.json('id');
  think();

  // 9 читань: список, щойно створена нотатка, дані автора -- тричі
  for (let i = 0; i < 3; i++) {
    get('/notes', 'GET /notes');
    get(`/notes/${id}`, 'GET /notes/{id}');
    get(`/authors/${author}`, 'GET /authors/{name}');
  }
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: false }),
    [`loadtest/results/summary-${LABEL}.json`]: JSON.stringify(data, null, 2),
  };
}
