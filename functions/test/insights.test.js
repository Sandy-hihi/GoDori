'use strict';
// 매장 통계 (65차) — 인기 메뉴·인기 게임
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const { createMemoryInsights, createInsightRoutes, summarizeOrder, seoulHour } = require('../src/insights');

const line = (menuId, name, basePrice, quantity, options = [], category = '음료') => ({ menuId, name, category, basePrice, quantity, options });
const ORDER = {
  room: '#3', price: '14000', notes: '얼음 적게', status: 'pending', items: ['x'],
  lines: [
    line('m1', '아메리카노', 3000, 2, [{ group: '온도', name: 'ICE', price: 500 }]),
    line('m2', '감자튀김', 5000, 1, [], '음식'),
    line('', '쿠키', 2000, 1, [], '디저트'),
  ],
};

test('summarizeOrder: 메뉴별 개수·금액·옵션, lines 없으면 주문 금액만', () => {
  const s = summarizeOrder(ORDER);
  assert.equal(s.items, 4);
  assert.equal(s.revenue, 3500 * 2 + 5000 + 2000);
  assert.deepEqual(s.menus.m1, { name: '아메리카노', category: '음료', qty: 2, revenue: 7000, options: { '온도: ICE': 2 } });
  assert.equal(s.menus['n_쿠키'].qty, 1); // 메뉴 ID 없으면 이름으로
  const old = summarizeOrder({ room: '#1', items: ['a x 1'], price: '4500' });
  assert.deepEqual(old, { menus: {}, items: 0, revenue: 4500 });
  // 이상한 값은 건너뜀
  const bad = summarizeOrder({ lines: [line('m1', '', 1000, 1), line('m2', '라면', 1000, 0), line('m3', 'a.b/c', '4,500', 1), null] });
  assert.equal(bad.items, 1);
  assert.equal(bad.menus.m3.revenue, 4500);
});

test('seoulHour: 한국 시간', () => {
  assert.equal(seoulHour(Date.UTC(2026, 10, 5, 15, 30)), '0'); // 한국 00:30
  assert.equal(seoulHour(Date.UTC(2026, 10, 5, 5, 0)), '14');
});

const fakeVerify = async (t) => {
  if (t === 'admin') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
  if (t === 'pad3') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
  if (t === 'pad4') return { uid: 'pad.platform6.4', pad: true, store: 'platform6', room: 4 };
  if (t === 'cafe2') return { uid: 'pad.cafe2.1', pad: true, store: 'cafe2', room: 1 };
  if (t === 'ops') return { uid: 'ops', ops: true };
  throw new Error('bad');
};

function make() {
  const stores = createMemoryStores({
    platform6: { name: '플랫폼6', account: {} },
    cafe2: { name: '두번째', account: {} },
    waiting: { name: '대기', account: {}, status: 'pending' },
  });
  const data = createMemoryInsights({
    orders: {
      platform6: { o1: { ...ORDER }, o2: { ...ORDER, room: '#4' }, o3: { room: '#3', items: ['a x 1'], price: '4500' } },
      cafe2: { c1: { room: '#1', items: ['x'], price: '6000', lines: [line('zz', '아메 리카노', 3000, 2)] } },
    },
    games: { platform6: { g1: '스플렌더', g2: '루미큐브' }, cafe2: { k9: '스플렌더' } },
    video: { platform6: [{ date: '2026-11-06', plays: 3, games: { g2: 3 } }, { date: '2026-01-01', plays: 9, games: { g1: 9 } }] },
  });
  const t = Date.UTC(2026, 10, 6, 5, 0); // 한국 11-06 14시
  const now = () => t;
  const insights = createInsightRoutes({ data, stores, now, httpError: (status, code, message) => Object.assign(new Error(message), { status, code }) });
  const h = createHandler({ bgg: {}, stores, verifyIdToken: fakeVerify, createToken: async () => 'x', attempts: createMemoryAttempts(), insights, now });
  const call = (method, path, { token, body, query } = {}) =>
    h({ method, path, query: query || {}, body, headers: token ? { authorization: `Bearer ${token}` } : {} });
  return { call, data };
}

test('패드 주문 세기: 자기 방만, 한 번만', async () => {
  const { call, data } = make();
  assert.equal((await call('POST', '/api/stats/order', { body: { orderId: 'o1' } })).status, 401);
  assert.equal((await call('POST', '/api/stats/order', { token: 'admin', body: { orderId: 'o1' } })).status, 403);
  assert.equal((await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'o2' } })).body.error, 'OTHER_ROOM');
  assert.equal((await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'nope' } })).status, 404);
  assert.equal((await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'a/b' } })).status, 400);
  const r = await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'o1' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.counted, true);
  assert.equal((await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'o1' } })).body.counted, false);
  assert.equal((await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'o3' } })).body.counted, true); // 예전 주문(lines 없음)
  const d = data.daily.get('platform6/2026-11-06');
  assert.equal(d.orders, 2);
  assert.equal(d.revenue, 14000 + 4500);
  assert.equal(d.hours['14'], 2);
  assert.equal(d.menus.m1.qty, 2);
  assert.equal(d.room, undefined); // 방 번호·요청 사항은 저장 안 함
});

test('게임 상세 조회 보고: 패드만 세고 값 검사', async () => {
  const { call, data } = make();
  assert.equal((await call('POST', '/api/stats/report', { token: 'pad3', body: { gameViews: { g1: 2, g2: 1 } } })).status, 200);
  assert.equal((await call('POST', '/api/stats/report', { token: 'pad4', body: { gameViews: { g1: 1 } } })).status, 200);
  const ign = await call('POST', '/api/stats/report', { token: 'admin', body: { gameViews: { g1: 5 } } });
  assert.equal(ign.body.ignored, true);
  assert.equal((await call('POST', '/api/stats/report', { token: 'pad3', body: { gameViews: { 'a.b': 1 } } })).status, 400);
  assert.equal((await call('POST', '/api/stats/report', { token: 'pad3', body: { gameViews: { g1: 9999 } } })).status, 400);
  assert.equal((await call('POST', '/api/stats/report', { token: 'pad3', body: { gameViews: [1] } })).status, 400);
  const d = data.daily.get('platform6/2026-11-06');
  assert.deepEqual(d.gameViews, { g1: 3, g2: 1 });
  assert.equal(d.views, 4);
});

test('운영자: 매장별·전체 매장 통계', async () => {
  const { call } = make();
  await call('POST', '/api/stats/order', { token: 'pad3', body: { orderId: 'o1' } });
  await call('POST', '/api/stats/order', { token: 'cafe2', body: { orderId: 'c1' } });
  await call('POST', '/api/stats/report', { token: 'pad3', body: { gameViews: { g1: 2 } } });
  await call('POST', '/api/stats/report', { token: 'cafe2', body: { gameViews: { k9: 4 } } });

  assert.equal((await call('GET', '/api/ops/insights', { token: 'admin', query: { storeId: 'platform6' } })).status, 403);
  assert.equal((await call('GET', '/api/ops/insights', { token: 'ops', query: { storeId: 'nope' } })).status, 404);

  const one = await call('GET', '/api/ops/insights', { token: 'ops', query: { storeId: 'platform6', days: '7' } });
  assert.equal(one.status, 200);
  const b = one.body;
  assert.equal(b.from, '2026-10-31');
  assert.equal(b.summary.orders, 1);
  assert.equal(b.summary.videoPlays, 3); // 기간 밖(1월) 재생은 빠짐
  assert.deepEqual(b.menus.map((m) => [m.name, m.qty]), [['아메리카노', 2], ['감자튀김', 1], ['쿠키', 1]]);
  assert.deepEqual(b.menus[0].options, [{ name: '온도: ICE', qty: 2 }]);
  assert.deepEqual(b.games.map((g) => [g.title, g.views, g.plays]), [['루미큐브', 0, 3], ['스플렌더', 2, 0]]);
  assert.equal(b.hours[14], 1);

  const all = await call('GET', '/api/ops/insights', { token: 'ops', query: { storeId: 'all' } });
  assert.equal(all.status, 200);
  assert.equal(all.body.storeCount, 2); // 승인 대기 매장은 빠짐
  assert.equal(all.body.summary.orders, 2);
  const americano = all.body.menus[0];
  assert.equal(americano.qty, 4); // '아메 리카노'도 같은 메뉴로 합침
  assert.equal(americano.stores, 2);
  const splendor = all.body.games.find((g) => g.title === '스플렌더');
  assert.equal(splendor.views, 6);
  assert.equal(splendor.stores, 2);
});

test('통계 서버가 없으면 503', async () => {
  const stores = createMemoryStores({ platform6: { name: 'p', account: {} } });
  const h = createHandler({ bgg: {}, stores, verifyIdToken: fakeVerify, createToken: async () => 'x', attempts: createMemoryAttempts() });
  const r = await h({ method: 'POST', path: '/api/stats/order', query: {}, body: { orderId: 'o1' }, headers: { authorization: 'Bearer pad3' } });
  assert.equal(r.status, 503);
});
