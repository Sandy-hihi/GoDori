'use strict';
// 실행: cd functions && node --test test/*.test.js   (네트워크 없이 가짜 BGG로 확인)
const test = require('node:test');
const assert = require('node:assert');
const { createHandler, difficultyFromWeight } = require('../src/app');
const { parseThingFullXml } = require('../src/bgg-client');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores, hashSecret, checkSecret } = require('../src/stores');
const { createMemoryOps, createMonitoring } = require('../src/ops');

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
// 가짜 Firebase 인증: 'admin-token'은 platform6 관리자, 'pad-token'은 platform6 3번 방 패드,
// 'guest-token'은 예전 익명 손님(매장 없음), 'old-admin'은 예전 관리자 토큰(매장 없음), 나머지는 잘못된 토큰
const fakeVerify = async (t) => {
  if (t === 'admin-token') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
  if (t === 'pad-token') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
  if (t === 'guest-token') return { uid: 'anon123' };
  if (t === 'old-admin') return { uid: 'admin-web', admin: true };
  if (t === 'ops-token') return { uid: 'ops', ops: true };
  if (t === 'new-admin') return { uid: 'admin-web.new-cafe', admin: true, store: 'new-cafe' };
  throw new Error('bad token');
};
const ACCOUNT = { padPassword: 'pad-pass', pin: '123456', webPassword: 'web-pass' };
function make({ account = ACCOUNT, rooms = 11, legacy = { pin: '111111', webPassword: 'old-web' }, opsAccount = { password: 'ops-password-1' }, monitoring = null } = {}) {
  const stores = createMemoryStores({ platform6: { name: '플랫폼6', account: { ...account }, rooms } });
  const tokens = [];
  const revoked = [];
  const h = createHandler({
    ops: createMemoryOps(opsAccount),
    monitoring,
    revokeStoreTokens: async (id) => revoked.push(id),
    bgg: fakeBgg(),
    stores,
    getLegacySecrets: async () => legacy,
    verifyIdToken: fakeVerify,
    createToken: async (uid, claims) => { tokens.push([uid, claims]); return `custom:${uid}`; },
    attempts: createMemoryAttempts(),
  });
  h.stores = stores;
  h.tokens = tokens;
  h.revoked = revoked;
  return h;
}
const req = (method, path, { query = {}, body, token = 'admin-token', origin, ip } = {}) => ({
  method, path, query, body,
  headers: {
    ...(token ? { authorization: `Bearer ${token}` } : {}),
    ...(origin ? { origin } : {}),
    ...(ip ? { 'x-forwarded-for': ip } : {}),
  },
});
const padLogin = (h, body, ip = '1.1.1.1') => h(req('POST', '/api/auth/store-login', { token: null, body: { storeId: 'platform6', ...body }, ip }));
const webLogin = (h, password, ip = '1.1.1.1', storeId = 'platform6') => h(req('POST', '/api/auth/login', { token: null, body: { storeId, password }, ip }));

test('health는 로그인 없이', async () => {
  const r = await make()(req('GET', '/api/health', { token: null }));
  assert.equal(r.status, 200);
});
test('BGG: 토큰 없으면 401, 잘못된 토큰 401, 패드·예전 토큰 403', async () => {
  const h = make();
  const none = await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: null }));
  assert.equal(none.status, 401);
  assert.equal(none.body.error, 'UNAUTHORIZED');
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'forged' }))).status, 401);
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'pad-token' }))).status, 403);
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'guest-token' }))).body.error, 'RELOGIN');
  assert.equal((await h(req('GET', '/api/bgg/lookup', { query: { id: '13' }, token: 'old-admin' }))).body.error, 'RELOGIN');
});
test('패드 로그인: 아이디·비밀번호·방 번호 → 그 방 패드 토큰', async () => {
  const h = make();
  const r = await padLogin(h, { password: 'pad-pass', room: 3 });
  assert.equal(r.status, 200);
  assert.equal(r.body.role, 'pad');
  assert.equal(r.body.room, 3);
  assert.equal(r.body.storeName, '플랫폼6');
  assert.deepEqual(h.tokens.at(-1), ['pad.platform6.3', { pad: true, store: 'platform6', room: 3 }]);
  // 아이디는 대소문자·앞뒤 공백 상관없이
  assert.equal((await padLogin(h, { storeId: ' Platform6 ', password: 'pad-pass', room: 1 })).status, 200);
});
test('패드 로그인: 틀린 비밀번호·없는 매장은 같은 문구 401, 방 번호 범위 400', async () => {
  const h = make({ rooms: 5 });
  const wrong = await padLogin(h, { password: 'nope', room: 1 });
  assert.equal(wrong.status, 401);
  const noStore = await padLogin(h, { storeId: 'other-store', password: 'pad-pass', room: 1 }, '2.2.2.2');
  assert.equal(noStore.status, 401);
  assert.equal(noStore.body.message, wrong.body.message);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 6 })).status, 400);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: -1 })).status, 400);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1.5 })).status, 400);
  assert.equal((await padLogin(h, { storeId: 'a/b', password: 'pad-pass', room: 1 })).status, 400);
  // 관리자 PIN·웹 비밀번호로는 손님 패드 로그인 안 됨
  assert.equal((await padLogin(h, { password: '123456', room: 1 }, '3.3.3.3')).status, 401);
});
test('방 번호 0: 비밀번호가 맞으면 PIN을 묻고, PIN까지 맞으면 관리자 토큰', async () => {
  const h = make();
  const step1 = await padLogin(h, { password: 'pad-pass', room: 0 });
  assert.equal(step1.status, 200);
  assert.equal(step1.body.needPin, true);
  assert.equal(step1.body.token, undefined);
  assert.equal(h.tokens.length, 0);
  // 비밀번호가 틀리면 PIN 단계로 안 감
  assert.equal((await padLogin(h, { password: 'nope', room: 0 }, '4.4.4.4')).status, 401);
  // PIN 틀림
  const badPin = await padLogin(h, { password: 'pad-pass', room: 0, pin: '000000' });
  assert.equal(badPin.status, 401);
  assert.equal(badPin.body.error, 'WRONG_PIN');
  const ok = await padLogin(h, { password: 'pad-pass', room: 0, pin: '123456' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.role, 'admin');
  assert.deepEqual(h.tokens.at(-1), ['admin-pad.platform6', { admin: true, store: 'platform6' }]);
});
test('패드 비밀번호가 아직 없으면 503 안내', async () => {
  const r = await padLogin(make({ account: { pin: '123456' } }), { password: 'x', room: 1 });
  assert.equal(r.status, 503);
});
test('관리자 웹 로그인: 매장 아이디 + webPassword (없으면 PIN)', async () => {
  const h = make();
  const r = await webLogin(h, 'web-pass');
  assert.equal(r.status, 200);
  assert.deepEqual(h.tokens.at(-1), ['admin-web.platform6', { admin: true, store: 'platform6' }]);
  assert.equal((await webLogin(h, '123456', '2.2.2.2')).status, 401);
  assert.equal((await webLogin(h, 'pad-pass', '3.3.3.3')).status, 401);
  assert.equal((await webLogin(make({ account: { pin: '123456', padPassword: 'p' } }), '123456')).status, 200);
  assert.equal((await webLogin(h, '')).status, 400);
});
test('로그인: 같은 IP에서 5번 틀리면 맞는 비밀번호도 429 (PIN 틀림도 셈)', async () => {
  const h = make();
  for (let i = 0; i < 3; i++) assert.equal((await padLogin(h, { password: 'x', room: 1 })).status, 401);
  for (let i = 0; i < 2; i++) assert.equal((await padLogin(h, { password: 'pad-pass', room: 0, pin: '0' })).status, 401);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 })).status, 429);
  assert.equal((await webLogin(h, 'web-pass')).status, 429);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 }, '9.9.9.9')).status, 200);
});
test('로그인: IP를 바꿔 가며 틀려도 전체 30번이면 잠금', async () => {
  const h = make();
  for (let i = 0; i < 30; i++) await padLogin(h, { password: 'x', room: 1 }, `10.0.0.${i}`);
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 }, '10.0.1.1')).status, 429);
});
test('로그인 성공하면 그 IP의 실패 기록 초기화', async () => {
  const h = make();
  for (let i = 0; i < 4; i++) await padLogin(h, { password: 'x', room: 1 });
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 })).status, 200);
  for (let i = 0; i < 4; i++) await padLogin(h, { password: 'x', room: 1 });
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 })).status, 200);
});
test('비밀번호 바꾸기: 관리자만, 해시로 저장, 바뀐 값으로 로그인', async () => {
  const h = make();
  const call = (body, token = 'admin-token') => h(req('POST', '/api/store/passwords', { body, token }));
  assert.equal((await call({ padPassword: 'new-pad' }, 'pad-token')).status, 403);
  assert.equal((await call({ padPassword: 'new-pad' }, 'old-admin')).status, 403);
  assert.equal((await call({ padPassword: 'abc' })).status, 400);
  assert.equal((await call({ pin: '12ab' })).status, 400);
  assert.equal((await call({ webPassword: 'short' })).status, 400);
  assert.equal((await call({})).status, 400);
  const r = await call({ padPassword: 'new-pad', pin: '987654', webPassword: 'new-web-pass' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.changed.sort(), ['padPassword', 'pin', 'webPassword']);
  const acc = h.stores.stores.get('platform6').account;
  assert.match(acc.padPasswordHash, /^scrypt\$/);
  assert.equal(acc.padPassword, undefined); // 글자 값은 지움
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 })).status, 401);
  assert.equal((await padLogin(h, { password: 'new-pad', room: 1 })).status, 200);
  assert.equal((await padLogin(h, { password: 'new-pad', room: 0, pin: '987654' })).status, 200);
  assert.equal((await webLogin(h, 'new-web-pass')).status, 200);
});
test('예전 데이터 옮기기: 예전 비밀번호 확인 후 한 번만', async () => {
  const h = make();
  const call = (body, ip = '5.5.5.5') => h(req('POST', '/api/admin/migrate-legacy', { token: null, ip,
    body: { legacyPassword: 'old-web', storeId: 'new-store', storeName: '새 매장', padPassword: 'pad-1234', ...body } }));
  assert.equal((await call({ legacyPassword: 'wrong' })).status, 401);
  assert.equal((await call({ padPassword: '12' })).status, 400);
  const ok = await call({});
  assert.equal(ok.status, 200);
  const acc = h.stores.stores.get('new-store').account;
  assert.equal(acc.pin, '111111'); // 예전 PIN·웹 비밀번호를 그대로 가져감
  assert.equal(acc.webPassword, 'old-web');
  assert.equal((await padLogin(h, { storeId: 'new-store', password: 'pad-1234', room: 1 })).status, 200);
  assert.equal((await call({})).status, 409); // 두 번째는 막음
  assert.equal((await call({ storeId: 'another-store' })).body.error, 'ALREADY_MIGRATED'); // 다른 아이디로도 한 번만
});
const SIGNUP = { storeId: 'new-cafe', storeName: '새 보드카페', ownerName: '김사장', phone: '010-1234-5678', webPassword: 'owner-pass-1', agree: true };
const signup = (h, body = {}, ip = '7.7.7.7') => h(req('POST', '/api/stores/signup', { token: null, ip, body: { ...SIGNUP, ...body } }));
const ops = (h, method, path, { body, query, token = 'ops-token' } = {}) => h(req(method, path, { body, query, token }));

test('가입: 입력 검사, 쓰는 아이디·예약 아이디 막음, 아이디 확인', async () => {
  const h = make();
  assert.equal((await signup(h, { storeId: 'ab' })).status, 400);
  assert.equal((await signup(h, { storeId: 'ops' })).body.error, 'RESERVED_ID');
  assert.equal((await signup(h, { phone: 'abc' })).status, 400);
  assert.equal((await signup(h, { webPassword: 'short' })).status, 400);
  assert.equal((await signup(h, { agree: false })).body.error, 'NO_AGREE');
  assert.equal((await signup(h, { storeId: 'platform6' }, '8.8.8.8')).body.error, 'ID_TAKEN');
  const check = (id) => h(req('GET', '/api/stores/check-id', { token: null, query: { id } }));
  assert.equal((await check('platform6')).body.available, false);
  assert.equal((await check('New-Cafe')).body.available, true);
  assert.equal((await check('admin')).status, 400);
  const ok = await signup(h, {}, '9.9.9.9');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.status, 'pending');
  const s = h.stores.stores.get('new-cafe');
  assert.equal(s.profile.phone, '010-1234-5678');
  assert.match(s.account.webPasswordHash, /^scrypt\$/);
});
test('가입: 같은 IP는 1시간에 3번까지', async () => {
  const h = make();
  for (let i = 0; i < 3; i++) await signup(h, { storeId: `cafe-${i}` });
  assert.equal((await signup(h, { storeId: 'cafe-9' })).status, 429);
});
test('승인 전엔 로그인 막힘(비밀번호가 맞을 때만 알려 줌) → 운영자 승인 → 로그인', async () => {
  const h = make();
  await signup(h);
  assert.equal((await webLogin(h, 'wrong-pass', '1.1.1.1', 'new-cafe')).status, 401); // 틀리면 그냥 틀림
  const pending = await webLogin(h, 'owner-pass-1', '1.1.1.2', 'new-cafe');
  assert.equal(pending.status, 403);
  assert.equal(pending.body.error, 'PENDING');
  // 손님·관리자는 운영자 API 못 씀
  assert.equal((await ops(h, 'POST', '/api/ops/store-status', { token: 'admin-token', body: { storeId: 'new-cafe', status: 'active' } })).status, 403);
  assert.equal((await ops(h, 'POST', '/api/ops/store-status', { body: { storeId: 'new-cafe', status: 'active' } })).status, 200);
  const ok = await webLogin(h, 'owner-pass-1', '1.1.1.3', 'new-cafe');
  assert.equal(ok.status, 200);
  assert.deepEqual(h.tokens.at(-1), ['admin-web.new-cafe', { admin: true, store: 'new-cafe' }]);
  // 패드 비밀번호는 아직 없음 → 매장 설정에서 만들라고
  assert.equal((await padLogin(h, { storeId: 'new-cafe', password: 'x', room: 1 }, '1.1.1.4')).status, 503);
});
test('운영자: 로그인, 매장 목록(승인 대기가 위), 정지하면 로그인 끊고 API 막음, 승인 대기만 삭제', async () => {
  const h = make();
  assert.equal((await h(req('POST', '/api/ops/login', { token: null, body: { password: 'nope' } }))).status, 401);
  const login = await h(req('POST', '/api/ops/login', { token: null, ip: '2.2.2.2', body: { password: 'ops-password-1' } }));
  assert.equal(login.status, 200);
  assert.deepEqual(h.tokens.at(-1), ['ops', { ops: true }]);
  await signup(h);
  const list = await ops(h, 'GET', '/api/ops/stores');
  assert.deepEqual(list.body.stores.map((s) => [s.id, s.status]), [['new-cafe', 'pending'], ['platform6', 'active']]);
  assert.equal((await ops(h, 'POST', '/api/ops/store-status', { body: { storeId: 'platform6', status: 'pending' } })).status, 400);
  assert.equal((await ops(h, 'POST', '/api/ops/store-delete', { body: { storeId: 'platform6' } })).status, 409);
  // 정지
  assert.equal((await ops(h, 'POST', '/api/ops/store-status', { body: { storeId: 'platform6', status: 'suspended' } })).status, 200);
  assert.deepEqual(h.revoked, ['platform6']);
  const blocked = await h(req('GET', '/api/bgg/search', { query: { q: '카탄' } }));
  assert.equal(blocked.body.error, 'SUSPENDED');
  assert.equal((await padLogin(h, { password: 'pad-pass', room: 1 })).body.error, 'SUSPENDED');
  // 다시 열기
  await ops(h, 'POST', '/api/ops/store-status', { body: { storeId: 'platform6', status: 'active' } });
  assert.equal((await h(req('GET', '/api/bgg/search', { query: { q: '카탄' } }))).status, 200);
  // 승인 대기 매장 삭제
  assert.equal((await ops(h, 'POST', '/api/ops/store-delete', { body: { storeId: 'new-cafe' } })).status, 200);
  assert.equal(h.stores.stores.has('new-cafe'), false);
});
test('운영자 비밀번호가 없으면 503, 바꾸면 해시로', async () => {
  assert.equal((await make({ opsAccount: null })(req('POST', '/api/ops/login', { token: null, body: { password: 'x' } }))).status, 503);
  const h = make();
  assert.equal((await ops(h, 'POST', '/api/ops/password', { body: { password: 'short' } })).status, 400);
  assert.equal((await ops(h, 'POST', '/api/ops/password', { body: { password: 'new-ops-password' } })).status, 200);
  assert.equal((await h(req('POST', '/api/ops/login', { token: null, body: { password: 'new-ops-password' } }))).status, 200);
});
test('이용량: 로그인·BGG·앱 보고가 매장별 하루 기록으로, 운영자 통계로 합계', async () => {
  const h = make();
  await padLogin(h, { password: 'pad-pass', room: 2 });
  await h(req('GET', '/api/bgg/search', { query: { q: '카탄' } }));
  assert.equal((await h(req('POST', '/api/usage/report', { token: 'pad-token', body: { reads: 650 } }))).status, 200);
  assert.equal((await h(req('POST', '/api/usage/report', { token: 'pad-token', body: { reads: -1 } }))).status, 400);
  const r = await ops(h, 'GET', '/api/ops/usage', { query: { days: '7' } });
  assert.equal(r.status, 200);
  const p6 = r.body.stores.find((s) => s.id === 'platform6');
  assert.deepEqual(p6.totals, { logins: 1, bggCalls: 1, clientReads: 650 });
});
test('프로젝트 사용량: Cloud Monitoring 응답 합치기, 실패한 항목은 오류 문구', async () => {
  const fetchImpl = async (url) => {
    const type = decodeURIComponent(new URL(url).searchParams.get('filter'));
    if (type.includes('read_count')) {
      return { ok: true, json: async () => ({ timeSeries: [{ points: [
        { interval: { endTime: '2026-11-04T00:00:00Z' }, value: { int64Value: '1200' } },
        { interval: { endTime: '2026-11-05T00:00:00Z' }, value: { int64Value: '800' } },
      ] }] }) };
    }
    if (type.includes('storage')) return { ok: false, status: 403, json: async () => ({ error: { message: 'Cloud Monitoring API has not been used in project' } }) };
    return { ok: true, json: async () => ({}) };
  };
  const monitoring = createMonitoring({ projectId: 'p', getAccessToken: async () => 't', fetchImpl });
  const r = await ops(make({ monitoring }), 'GET', '/api/ops/project-usage', { query: { days: '7' } });
  assert.equal(r.body.totals.firestoreReads, 2000);
  assert.equal(r.body.days.length, 2);
  assert.match(r.body.errors.storageSentBytes, /Monitoring API가 꺼져/);
});
test('패드 로그아웃 확인: 패드 비밀번호나 PIN이면 OK, 틀리면 401·실패 횟수, 로그인 없으면 401', async () => {
  const h = make();
  const exit = (password, token = 'pad-token', ip = '6.6.6.6') => h(req('POST', '/api/auth/verify-exit', { token, ip, body: { password } }));
  assert.equal((await exit('pad-pass')).status, 200);
  assert.equal((await exit('123456')).status, 200);
  assert.equal((await exit('web-pass')).status, 401); // 관리자 웹 비밀번호는 안 받음
  assert.equal((await exit('')).status, 400);
  assert.equal((await exit('pad-pass', null)).status, 401);
  for (let i = 0; i < 5; i++) await exit('nope', 'pad-token', '6.6.6.7');
  assert.equal((await exit('pad-pass', 'pad-token', '6.6.6.7')).status, 429);
});
test('비밀번호 해시 확인', () => {
  const hash = hashSecret('abcd');
  assert.equal(checkSecret('abcd', { hash }), true);
  assert.equal(checkSecret('abce', { hash }), false);
  assert.equal(checkSecret('abcd', { plain: 'abcd' }), true);
  assert.equal(checkSecret('abcd', {}), null);
  assert.notEqual(hashSecret('abcd'), hash); // 매번 다른 소금
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
  for (const site of ['https://godori-pad.web.app', 'https://godori-ops.web.app', 'https://platform6-boardpad.web.app']) {
    assert.equal((await h(req('OPTIONS', '/api/bgg/search', { origin: site, token: null }))).headers['Access-Control-Allow-Origin'], site);
  }
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
