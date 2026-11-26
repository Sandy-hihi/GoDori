'use strict';
// 148차 재고 앱 로그인 — 실행: cd functions && node --test test/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const { createMemoryOps } = require('../src/ops');

const ACCOUNT = { padPassword: 'pad-pass', pin: '123456', webPassword: 'web-pass' };
function make({ stock = true, status = 'active', account = ACCOUNT } = {}) {
  const stores = createMemoryStores({
    platform6: { name: '플랫폼6', status, account: { ...account }, features: stock ? { stock: true } : {} },
  });
  const tokens = [];
  const h = createHandler({
    bgg: {},
    stores,
    ops: createMemoryOps({ password: 'ops-password-1' }),
    verifyIdToken: async (t) => {
      if (t === 'ops-token') return { uid: 'ops', ops: true };
      if (t === 'stock-token') return { uid: 'stock.platform6', stock: true, store: 'platform6' };
      throw new Error('bad token');
    },
    createToken: async (uid, claims) => { tokens.push([uid, claims]); return `custom:${uid}`; },
    attempts: createMemoryAttempts(),
  });
  h.tokens = tokens;
  h.stores = stores;
  return h;
}
const login = (h, password, ip = '1.1.1.1', storeId = 'platform6') => h({
  method: 'POST', path: '/api/auth/stock-login', query: {},
  body: { storeId, password },
  headers: { 'x-forwarded-for': ip },
});

test('재고 앱: 패드 비밀번호 → 직원, 관리자 웹 비밀번호 → 사장님', async () => {
  const h = make();
  const staff = await login(h, 'pad-pass');
  assert.equal(staff.status, 200);
  assert.equal(staff.body.role, 'staff');
  assert.equal(staff.body.storeName, '플랫폼6');
  assert.deepEqual(h.tokens[0], ['stock.platform6', { stock: true, store: 'platform6' }]);
  const owner = await login(h, 'web-pass');
  assert.equal(owner.status, 200);
  assert.equal(owner.body.role, 'owner');
  assert.deepEqual(h.tokens[1], ['stock-owner.platform6', { admin: true, stock: true, store: 'platform6' }]);
  // PIN은 관리자 웹 비밀번호가 있으면 안 됨
  assert.equal((await login(h, '123456')).status, 401);
  // 글자 비밀번호는 로그인에 성공하면 해시로 바뀜(145차와 같게)
  const acc = await h.stores.getAccount('platform6');
  assert.ok(String(acc.padPasswordHash).startsWith('scrypt$'));
  assert.ok(String(acc.webPasswordHash).startsWith('scrypt$'));
});

test('재고 앱: 신청 안 한 매장은 비밀번호가 맞아도 403, 틀리면 401', async () => {
  const h = make({ stock: false });
  const off = await login(h, 'pad-pass');
  assert.equal(off.status, 403);
  assert.equal(off.body.error, 'STOCK_OFF');
  assert.equal(h.tokens.length, 0);
  const wrong = await login(h, 'nope', '2.2.2.2');
  assert.equal(wrong.status, 401);
  assert.equal(wrong.body.error, 'WRONG_PASSWORD');
});

test('재고 앱: 정지 매장 403, 같은 IP 5번 틀리면 잠금, 없는 매장 401', async () => {
  assert.equal((await login(make({ status: 'suspended' }), 'pad-pass')).body.error, 'SUSPENDED');
  const h = make();
  for (let i = 0; i < 5; i++) assert.equal((await login(h, 'x' + i, '3.3.3.3')).status, 401);
  assert.equal((await login(h, 'pad-pass', '3.3.3.3')).status, 429);
  assert.equal((await login(h, 'pad-pass', '4.4.4.4', 'no-such')).status, 401);
});

test('재고 앱: 운영자가 매장 기능 stock 켜기·끄기, 사장님은 못 바꿈', async () => {
  const h = make({ stock: false });
  const r = await h({ method: 'POST', path: '/api/ops/store-features', query: {}, body: { storeId: 'platform6', stock: true }, headers: { authorization: 'Bearer ops-token' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.features.stock, true);
  assert.equal((await login(h, 'pad-pass')).status, 200);
  // 직원 재고 토큰으로 매장 기능을 바꿀 수 없음
  const s = await h({ method: 'POST', path: '/api/store/features', query: {}, body: { stock: true }, headers: { authorization: 'Bearer stock-token' } });
  assert.equal(s.status, 403);
});
