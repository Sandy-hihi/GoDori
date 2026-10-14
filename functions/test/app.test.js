'use strict';
// 실행: cd functions && node --test test/*.test.js   (네트워크 없이 가짜 BGG로 확인)
const test = require('node:test');
const assert = require('node:assert');
const { createHandler, difficultyFromWeight } = require('../src/app');
const { parseThingFullXml } = require('../src/bgg-client');

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
const make = () => createHandler({ bgg: fakeBgg(), getAdminPassword: async () => '123456' });
const req = (method, path, { query = {}, body, pw = '123456', origin } = {}) => ({
  method, path, query, body, headers: { ...(pw ? { 'x-admin-password': pw } : {}), ...(origin ? { origin } : {}) },
});

test('health는 로그인 없이', async () => {
  const r = await make()(req('GET', '/api/health', { pw: null }));
  assert.equal(r.status, 200);
});
test('비밀번호 틀리면 401', async () => {
  const r = await make()(req('GET', '/api/bgg/lookup', { query: { id: '13' }, pw: '0000' }));
  assert.equal(r.status, 401);
  assert.equal(r.body.error, 'UNAUTHORIZED');
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
  const ok = await h(req('OPTIONS', '/api/bgg/search', { origin: 'http://localhost:51234', pw: null }));
  assert.equal(ok.status, 204);
  assert.equal(ok.headers['Access-Control-Allow-Origin'], 'http://localhost:51234');
  const bad = await h(req('OPTIONS', '/api/bgg/search', { origin: 'https://evil.example', pw: null }));
  assert.equal(bad.headers['Access-Control-Allow-Origin'], undefined);
});
test('비밀번호 20번 넘게 틀리면 429', async () => {
  const h = make();
  let last;
  for (let i = 0; i < 21; i++) last = await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, pw: 'bad' }));
  assert.equal(last.status, 429);
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
