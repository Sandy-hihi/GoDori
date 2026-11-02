'use strict';
// 실행: cd functions && node --test test/*.test.js   (네트워크 없이 가짜 BGG로 확인)
const test = require('node:test');
const assert = require('node:assert');
const { createHandler, difficultyFromWeight } = require('../src/app');
const { parseThingFullXml } = require('../src/bgg-client');
const { createMemoryAttempts } = require('../src/attempts');

function fakeBgg() {
  const games = {
    13: { id: '13', name: '카탄', bggName: 'CATAN', minPlayers: 3, maxPlayers: 4, recommendedPlayers: '4', weight: 2.29, rank: 600 },
    99: { id: '99', name: 'No Players', bggName: 'No Players', minPlayers: null, maxPlayers: null },
  };
  return {
    async search(q) { return q === '카탄' ? [{ id: '13', name: 'CATAN', yearPublished: 1995, thumbnail: null }] : []; },
    async fetchDetails(id) { if (!games[id]) { const e = new Error('x'); e.code = 'BGG_NOT_FOUND'; throw e; } return games[id]; },
    async fetchDetailsBatch(ids) { const m = new Map(); for (const id of ids) if (games[id]) m.set(id, games[id]); return m; },
    async fetchImage(id) { if (id !== '13') { const e = new Error('x'); e.code = 'BGG_NO_IMAGE'; throw e; } return { buffer: Buffer.from('abc'), contentType: 'image/png', name: '카탄' }; },
  };
}
// 가짜 Firebase 인증: 'admin-token'은 관리자, 'guest-token'은 익명 손님, 나머지는 잘못된 토큰
const fakeVerify = async (t) => {
  if (t === 'admin-token') return { uid: 'admin-web', admin: true };
  if (t === 'guest-token') return { uid: 'anon123' };
  throw new Error('bad token');
};
const make = (secrets = { pin: '123456', webPassword: 'web-pass' }) => createHandler({
  bgg: fakeBgg(),
  getAdminSecrets: async () => secrets,
  verifyIdToken: fakeVerify,
  createAdminToken: async (kind) => `custom-${kind}`,
  attempts: createMemoryAttempts(),
});
const req = (method, path, { query = {}, body, token = 'admin-token', origin, ip } = {}) => ({
  method, path, query, body,
  headers: {
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...(origin ? { origin } : {}),
    ...(ip ? { 'x-forwarded-for': ip } : {}),
  },
});
const login = (h, kind, password, ip = '1.1.1.1') => h(req('POST', '/api/auth/login', { token: null, body: { kind, password }, ip }));

test('health는 로그인 없이', async () => {
  const r = await make()(req('GET', '/api/health', { token: null }));
  assert.equal(r.status, 200);
});
test('BGG: 토큰 없으면 401, 잘못된 토큰 401, 손님 토큰 403', async () => {
  const h = make();
  const none = await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: null }));
  assert.equal(none.status, 401);
  assert.equal(none.body.error, 'UNAUTHORIZED');
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'forged' }))).status, 401);
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'guest-token' }))).status, 403);
});
test('로그인: 태블릿은 PIN, 관리자 웹은 webPassword', async () => {
  const h = make();
  const pad = await login(h, 'pad', '123456');
  assert.equal(pad.status, 200);
  assert.equal(pad.body.token, 'custom-pad');
  const web = await login(h, 'web', 'web-pass');
  assert.equal(web.status, 200);
  assert.equal(web.body.token, 'custom-web');
  // 태블릿에 웹 비밀번호, 웹에 PIN은 안 됨 (webPassword가 따로 있을 때)
  assert.equal((await login(h, 'pad', 'web-pass')).status, 401);
  assert.equal((await login(h, 'web', '123456', '2.2.2.2')).status, 401);
});
test('로그인: webPassword가 없으면 관리자 웹도 PIN 사용', async () => {
  const r = await login(make({ pin: '123456' }), 'web', '123456');
  assert.equal(r.status, 200);
});
test('로그인: 빈 비밀번호 400, 설정 없음 503', async () => {
  assert.equal((await login(make(), 'pad', '')).status, 400);
  assert.equal((await login(make({}), 'pad', '1234')).status, 503);
});
test('로그인: 같은 IP에서 5번 틀리면 맞는 PIN도 429', async () => {
  const h = make();
  for (let i = 0; i < 5; i++) assert.equal((await login(h, 'pad', '000000')).status, 401);
  assert.equal((await login(h, 'pad', '123456')).status, 429);
  // 다른 IP는 아직 가능
  assert.equal((await login(h, 'pad', '123456', '9.9.9.9')).status, 200);
});
test('로그인: IP를 바꿔 가며 틀려도 전체 30번이면 잠금', async () => {
  const h = make();
  for (let i = 0; i < 30; i++) await login(h, 'pad', '000000', `10.0.0.${i}`);
  assert.equal((await login(h, 'pad', '123456', '10.0.1.1')).status, 429);
});
test('로그인 성공하면 그 IP의 실패 기록 초기화', async () => {
  const h = make();
  for (let i = 0; i < 4; i++) await login(h, 'pad', '000000');
  assert.equal((await login(h, 'pad', '123456')).status, 200);
  for (let i = 0; i < 4; i++) await login(h, 'pad', '000000');
  assert.equal((await login(h, 'pad', '123456')).status, 200);
});
test('lookup: 난이도 계산 포함', async () => {
  const r = await make()(req('GET', '/api/bgg/lookup', { query: { id: '13' } }));
  assert.equal(r.status, 200);
  assert.equal(r.body.name, '카탄');
  assert.equal(r.body.bggName, 'CATAN');
  assert.equal(r.body.difficulty.label, '어려움');
});
test('lookup: 인원 정보 없으면 422, 없는 게임 404, 잘못된 id 400', async () => {
  const h = make();
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '99' } }))).status, 422);
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '5' } }))).status, 404);
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: 'abc' } }))).status, 400);
});
test('search', async () => {
  const r = await make()(req('GET', '/api/bgg/search', { query: { q: '카탄' } }));
  assert.equal(r.status, 200);
  assert.equal(r.body.results.length, 1);
});
test('image: dataUrl', async () => {
  const h = make();
  const r = await h(req('GET', '/api/bgg/image', { query: { id: '13' } }));
  assert.equal(r.body.dataUrl, 'data:image/png;base64,' + Buffer.from('abc').toString('base64'));
  assert.equal((await h(req('GET', '/api/bgg/image', { query: { id: '99' } }))).status, 422);
});
test('details: 찾은 것/못 찾은 것 나눔', async () => {
  const r = await make()(req('POST', '/api/bgg/details', { body: { ids: ['13', '99', '5', 'x'] } }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.games.map((g) => g.geekId), ['13']);
  assert.deepEqual(r.body.missing, ['99', '5']);
});
test('CORS: localhost만 허용', async () => {
  const h = make();
  const ok = await h(req('OPTIONS', '/api/bgg/search', { origin: 'http://localhost:51234', token: null }));
  assert.equal(ok.status, 204);
  assert.equal(ok.headers['Access-Control-Allow-Origin'], 'http://localhost:51234');
  const bad = await h(req('OPTIONS', '/api/bgg/search', { origin: 'https://evil.example', token: null }));
  assert.equal(bad.headers['Access-Control-Allow-Origin'], undefined);
});
test('난이도 구간', () => {
  assert.equal(difficultyFromWeight(1.0).label, '매우쉬움');
  assert.equal(difficultyFromWeight(3.5).label, '전문');
  assert.equal(difficultyFromWeight(null), null);
});
test('BGG XML 파싱 (추천 인원·한글 이름)', () => {
  const xml = `<items><item type="boardgame" id="13"><name type="primary" value="CATAN"/><name type="alternate" value="카탄"/>
  <minplayers value="3"/><maxplayers value="4"/>
  <poll name="suggested_numplayers"><results numplayers="3"><result value="Best" numvotes="5"/><result value="Recommended" numvotes="9"/><result value="Not Recommended" numvotes="1"/></results>
  <results numplayers="4"><result value="Best" numvotes="20"/><result value="Recommended" numvotes="3"/><result value="Not Recommended" numvotes="1"/></results></poll>
  <statistics><ratings><averageweight value="2.29"/><ranks><rank type="subtype" value="600"/></ranks></ratings></statistics></item></items>`;
  const d = parseThingFullXml(xml).get('13');
  assert.equal(d.name, '카탄');
  assert.equal(d.recommendedPlayers, '4');
  assert.equal(d.rank, 600);
});
