'use strict';
// 토스 POS 연동 (64차) — 네트워크 없이: 가짜 토스 서버 + 가짜 fetch
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const { createMemoryTossData } = require('../src/toss-data');
const { createTossRoutes } = require('../src/toss-routes');
const {
  TossError, createTossClient, buildTossOrder, fakeCatalogFromMenus, signWebhook, verifyWebhook, parseOrderKey, orderKeyOf,
} = require('../src/toss');

const MENUS = [
  { id: 'm1', name: '아메리카노', price: 3000, category: '음료',
    optionGroups: [{ groupName: '온도', isRequired: true, options: [{ name: 'HOT', price: 0 }, { name: 'ICE', price: 500 }] },
      { groupName: '샷', isRequired: false, options: [{ name: '샷 추가', price: 500 }] }] },
  { id: 'm2', name: '감자튀김', price: 5000, category: '음식', optionGroups: [] },
  { id: 'm3', name: '라면', price: 4500, category: '음식', isSoldOut: true, optionGroups: [] },
];
const line = (menuId, name, basePrice, quantity, options = [], category = '음료') => ({ menuId, name, category, basePrice, quantity, options });
const ORDER = {
  room: '#3', price: '11500', notes: '얼음 적게', status: 'pending',
  items: ['아메리카노 (ICE, 샷 추가) x 1', '감자튀김 x 1', '쿠키 x 1'],
  lines: [
    line('m1', '아메리카노', 3000, 1, [{ group: '온도', name: 'ICE', price: 500 }, { group: '샷', name: '샷 추가', price: 500 }]),
    line('m2', '감자튀김', 5000, 1, [], '음식'),
    line('m9', '쿠키', 2500, 1, [], '디저트'),
  ],
};

test('buildTossOrder: 연결된 메뉴는 포스 상품·옵션 ID로, 나머지는 임의 상품', () => {
  const catalog = fakeCatalogFromMenus(MENUS);
  const americano = catalog[0];
  const { body, warnings } = buildTossOrder({
    storeId: 'platform6', orderId: 'abc123', order: ORDER,
    menuMap: { m1: americano.id }, catalogById: new Map(catalog.map((i) => [i.id, i])), nowIso: '2026-11-06T00:00:00.000Z',
  });
  const o = body.order;
  assert.equal(o.orderKey, 'godori-platform6-abc123');
  assert.equal(o.orderNumber, '3번 방');
  assert.match(o.memo, /3번 방 · 요청: 얼음 적게/);
  assert.deepEqual(body.payments, []);
  assert.equal(o.lineItems[0].targetType, 'ITEM');
  assert.equal(o.lineItems[0].targetId, americano.id);
  assert.deepEqual(o.lineItems[0].optionChoices.map((c) => c.optionChoiceId),
    [americano.options[0].choices[1].id, americano.options[1].choices[0].id]);
  assert.equal(o.lineItems[1].targetType, 'AD_HOC'); // 연결 안 함
  assert.equal(o.lineItems[1].item.title, '감자튀김');
  assert.equal(o.chargePrice.totalAmount, 11500);
  assert.equal(o.chargePrice.taxAmount + o.chargePrice.supplyAmount, 11500);
  assert.deepEqual(warnings, []);
  // 옵션 이름이 다르면 이름만(임의 상품) + 안내
  const odd = { ...ORDER, lines: [line('m1', '아메리카노', 3000, 2, [{ group: '온도', name: '미지근', price: 0 }])], price: '6000' };
  const r2 = buildTossOrder({ storeId: 'platform6', orderId: 'x', order: odd, menuMap: { m1: americano.id }, catalogById: new Map([[americano.id, americano]]) });
  assert.equal(r2.body.order.lineItems[0].targetType, 'AD_HOC');
  assert.equal(r2.warnings.length, 1);
  // 예전 패드 주문(lines 없음)은 못 보냄
  assert.throws(() => buildTossOrder({ storeId: 'platform6', orderId: 'x', order: { room: '#1', items: ['a x 1'] } }), (e) => e.code === 'NO_LINES');
});

test('orderKey 풀기 (매장 아이디에 - 있어도)', () => {
  assert.deepEqual(parseOrderKey(orderKeyOf('new-cafe', 'AbC123')), { storeId: 'new-cafe', orderId: 'AbC123' });
  assert.equal(parseOrderKey('other-1-2'), null);
});

test('웹훅 서명 확인', () => {
  const now = 1_800_000_000_000;
  const raw = Buffer.from('{"id":"w1"}');
  const sig = signWebhook('sec', String(now), raw);
  const h = (ts, s) => ({ 'x-toss-timestamp': String(ts), 'x-toss-signature': s });
  assert.equal(verifyWebhook({ secret: 'sec', headers: h(now, sig), rawBody: raw, now }), true);
  assert.equal(verifyWebhook({ secret: 'sec', headers: h(now, sig), rawBody: Buffer.from('{"id":"w2"}'), now }), false);
  assert.equal(verifyWebhook({ secret: 'other', headers: h(now, sig), rawBody: raw, now }), false);
  assert.equal(verifyWebhook({ secret: 'sec', headers: h(now, sig), rawBody: raw, now: now + 10 * 60 * 1000 }), false); // 오래된 것
  assert.equal(verifyWebhook({ secret: 'sec', headers: {}, rawBody: raw, now }), false);
});

test('진짜 토스 클라이언트: 헤더·성공·실패·429 한 번 재시도', async () => {
  const calls = [];
  const replies = [
    { status: 200, body: { resultType: 'SUCCESS', success: { id: 42, name: '테스트 매장' } } },
    { status: 429, body: { resultType: 'FAIL', error: { errorCode: 'TOO_MANY', reason: 'x' } } },
    { status: 200, body: { resultType: 'SUCCESS', success: [{ id: '1', title: 'A' }] } },
    { status: 400, body: { resultType: 'FAIL', error: { errorCode: 'CATALOG_ITEM_SOLD_OUT', reason: '품절' } } },
  ];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    const r = replies.shift();
    return { status: r.status, ok: r.status < 300, headers: { get: () => null }, text: async () => JSON.stringify(r.body) };
  };
  const c = createTossClient({ accessKey: 'ak', secretKey: 'sk', fetchImpl, sleep: async () => {} });
  assert.equal((await c.getMerchant(42)).name, '테스트 매장');
  assert.equal(calls[0].url, 'https://open-api.tossplace.com/api-public/openapi/v1/merchants/42');
  assert.equal(calls[0].init.headers['x-access-key'], 'ak');
  assert.equal(calls[0].init.headers['x-secret-key'], 'sk');
  assert.match(calls[0].init.headers['user-agent'], /^godori\//);
  assert.deepEqual((await c.listCatalogItems(42)).map((i) => i.title), ['A']); // 429 뒤 재시도
  assert.match(calls[2].url, /catalog\/items\?page=1&size=500$/);
  await assert.rejects(c.createOrder(42, { order: {} }, { printOrderSheet: true }), (e) => e instanceof TossError && e.code === 'CATALOG_ITEM_SOLD_OUT');
  assert.match(calls[3].url, /order\/orders\?printOrderSheet=true$/);
});

// ── API 전체 흐름 ──
const fakeVerify = async (t) => {
  if (t === 'admin') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
  if (t === 'pad3') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
  if (t === 'pad4') return { uid: 'pad.platform6.4', pad: true, store: 'platform6', room: 4 };
  if (t === 'ops') return { uid: 'ops', ops: true };
  throw new Error('bad');
};
function make({ tossOn = true, webhookSecret = 'whsec', orders = {} } = {}) {
  const stores = createMemoryStores({ platform6: { name: '플랫폼6', account: {}, features: { tossPos: tossOn } } });
  const data = createMemoryTossData({ menus: { platform6: MENUS }, orders: { platform6: orders } });
  let t = 1_800_000_000_000;
  const now = () => t;
  const toss = createTossRoutes({
    data, stores, webhookSecret, now,
    httpError: (status, code, message) => Object.assign(new Error(message), { status, code }),
  });
  const h = createHandler({ bgg: {}, stores, verifyIdToken: fakeVerify, createToken: async () => 'x', attempts: createMemoryAttempts(), toss, now });
  const call = (method, path, { token, body, query, headers = {}, rawBody } = {}) =>
    h({ method, path, query: query || {}, body, rawBody, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers } });
  return { h, call, data, stores, tick: (ms) => { t += ms; }, now };
}

test('운영자: 가짜 포스로 연결 → 관리자: 상품 목록·메뉴 연결 → 패드: 주문 보내기', async () => {
  const { call, data } = make({ orders: { o1: ORDER, o2: { ...ORDER, room: '#4' }, o3: { ...ORDER, lines: [line('m3', '라면', 4500, 1, [], '음식')], price: '4500' }, old: { room: '#3', items: ['a x 1'], price: '1' } } });
  // 연결 전
  assert.equal((await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'o1' } })).body.error, 'TOSS_NOT_LINKED');
  assert.equal((await call('POST', '/api/ops/toss/link', { token: 'admin', body: { storeId: 'platform6', mode: 'fake' } })).status, 403);
  const link = await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  assert.equal(link.status, 200);
  assert.equal(link.body.merchantId, 'fake-platform6');
  assert.equal((await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '123' } })).body.error, 'NOT_INSTALLED');

  const cat = await call('GET', '/api/toss/catalog', { token: 'admin' });
  assert.equal(cat.status, 200);
  assert.deepEqual(cat.body.items.map((i) => i.title), ['아메리카노', '감자튀김', '라면']);
  assert.equal(cat.body.items[2].soldOut, true);
  assert.equal((await call('GET', '/api/toss/catalog', { token: 'pad3' })).status, 403);
  const ids = Object.fromEntries(cat.body.items.map((i) => [i.title, i.id]));
  const mm = await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: { m1: ids['아메리카노'], m3: ids['라면'] } } });
  assert.equal(mm.status, 200);
  assert.equal(mm.body.menuMap.m1, ids['아메리카노']);
  assert.equal((await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: { m1: 'abc' } } })).status, 400);

  // 패드 3번: 자기 방 주문 → 보냄
  const sent = await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'o1' } });
  assert.equal(sent.status, 200);
  assert.equal(sent.body.ok, true);
  assert.equal(sent.body.tossPos.state, 'sent');
  const fakeOrders = data.sandbox.get('fake-platform6');
  assert.equal(fakeOrders.length, 1);
  assert.equal(fakeOrders[0].lineItems[0].targetType, 'ITEM');
  assert.deepEqual(fakeOrders[0].lineItems[0].optionChoices.map((c) => c.title), ['ICE', '샷 추가']); // 가짜 포스엔 옵션 이름도 저장
  assert.equal(fakeOrders[0].orderKey, 'godori-platform6-o1');
  // 두 번 보내도 한 번만
  const again = await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: 'o1' } });
  assert.equal(again.body.already, true);
  assert.equal(data.sandbox.get('fake-platform6').length, 1);
  // 다른 방 주문은 패드가 못 보냄
  assert.equal((await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'o2' } })).status, 403);
  // 포스에서 품절 → 실패로 남고 관리자 화면에 보임
  const sold = await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: 'o3' } });
  assert.equal(sold.body.ok, false);
  assert.match(sold.body.tossPos.error, /품절/);
  const old = await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: 'old' } });
  assert.equal(old.body.tossPos.code, 'NO_LINES');
  const status = await call('GET', '/api/toss/status', { token: 'admin' });
  assert.equal(status.body.linked, true);
  assert.equal(status.body.mode, 'fake');
  assert.deepEqual(status.body.failed.map((f) => f.id).sort(), ['o3', 'old']);
  // 가짜 포스 주문은 운영자가 봄
  const fo = await call('GET', '/api/ops/toss/fake-orders', { token: 'ops', query: { storeId: 'platform6' } });
  assert.equal(fo.body.orders.length, 1);
  // 운영자 overview
  const ov = await call('GET', '/api/ops/toss/overview', { token: 'ops' });
  assert.equal(ov.body.links.platform6.mode, 'fake');
  assert.equal(ov.body.links.platform6.mapped, 2);
  assert.equal(ov.body.liveReady, false);
  // 연결 끊기
  await call('POST', '/api/ops/toss/unlink', { token: 'ops', body: { storeId: 'platform6' } });
  assert.equal((await call('GET', '/api/toss/status', { token: 'admin' })).body.linked, false);
});

test('토스 POS 연동이 꺼진 매장은 안 보냄', async () => {
  const { call } = make({ tossOn: false, orders: { o1: ORDER } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  assert.equal((await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'o1' } })).body.error, 'TOSS_OFF');
});

test('웹훅: 서명·중복·앱 설치·주문 상태', async () => {
  const { call, data, now } = make({ orders: { o1: ORDER } });
  const send = (ev, { secret = 'whsec', id = ev.id } = {}) => {
    const raw = Buffer.from(JSON.stringify(ev));
    const ts = String(now());
    return call('POST', '/api/toss/webhook', {
      body: ev, rawBody: raw,
      headers: { 'x-toss-timestamp': ts, 'x-toss-signature': signWebhook(secret, ts, raw), 'x-toss-webhook-id': id },
    });
  };
  const install = { id: 'w1', type: 'app.installation.created.v1', merchantId: 777, createdAt: '2026-11-06T00:00:00Z',
    data: { merchant: { id: 777, name: '플랫폼6 보드카페', businessNumber: '1234567890' } } };
  assert.equal((await send(install, { secret: 'wrong' })).status, 401);
  assert.equal((await send(install)).status, 200);
  assert.equal((await send(install)).body.duplicate, true);
  assert.equal(data.installs.get('777').businessNumber, '1234567890');
  // 설치 기록이 있으면 진짜 연결 가능 (키가 없어도 연결 표시는 됨)
  const link = await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '777' } });
  assert.equal(link.body.merchantName, '플랫폼6 보드카페');
  // 키가 없으면 보내기는 실패로 남음
  const s = await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'o1' } });
  assert.equal(s.body.tossPos.code, 'TOSS_NO_KEYS');
  // 주문 상태 웹훅 → 주문 문서에 표시. 다른 가맹점에서 온 건 무시
  await send({ id: 'w2', type: 'order.order.completed.v1', merchantId: 999, data: { orderKey: 'godori-platform6-o1' } });
  assert.equal((await data.getOrder('platform6', 'o1')).tossPos.posState, undefined);
  await send({ id: 'w3', type: 'order.order.declined.v1', merchantId: 777, createdAt: '2026-11-06T01:00:00Z', data: { orderKey: 'godori-platform6-o1', declinedReason: '재료 소진' } });
  const o = await data.getOrder('platform6', 'o1');
  assert.equal(o.tossPos.posState, 'DECLINED');
  assert.equal(o.tossPos.posReason, '재료 소진');
});

test('방 결제 끝 (81차): 포스로 보낸 그 방 주문이 다 완료되면 settledAt — 가짜 포스 결제 완료·웹훅', async () => {
  const { call, data, tick } = make({ orders: { a: ORDER, b: { ...ORDER }, c: { ...ORDER, room: '#4' } } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  for (const [tok, id] of [['pad3', 'a'], ['pad3', 'b'], ['pad4', 'c']]) {
    assert.equal((await call('POST', '/api/toss/send-order', { token: tok, body: { orderId: id } })).body.ok, true);
  }
  assert.deepEqual(data.rooms.get('platform6/3').open, ['a', 'b']);
  const fakes = Object.fromEntries(data.sandbox.get('fake-platform6').map((o) => [o.orderKey, o.id]));
  const done = (orderId, extra = {}) => call('POST', '/api/ops/toss/fake-complete', {
    token: 'ops', body: { storeId: 'platform6', orderKey: `godori-platform6-${orderId}`, id: fakes[`godori-platform6-${orderId}`], ...extra },
  });
  assert.equal((await call('POST', '/api/ops/toss/fake-complete', { token: 'admin', body: {} })).status, 403);
  assert.equal((await done('a', { orderKey: 'godori-other-store-a' })).body.error, 'INVALID_ORDER_KEY');
  // 한 건만 끝남 → 아직
  const r1 = await done('a');
  assert.equal(r1.body.settled, false);
  assert.equal(r1.body.open, 1);
  assert.equal(data.rooms.get('platform6/3').settledAt, undefined);
  assert.equal(data.sandbox.get('fake-platform6').find((o) => o.orderKey === 'godori-platform6-a').posState, 'COMPLETED');
  assert.equal((await data.getOrder('platform6', 'a')).tossPos.posState, 'COMPLETED');
  // 남은 한 건 → 정산 끝, 다른 방은 그대로
  tick(1000);
  const r2 = await done('b');
  assert.equal(r2.body.settled, true);
  const room3 = data.rooms.get('platform6/3');
  assert.deepEqual(room3.open, []);
  assert.ok(room3.settledAt);
  assert.equal(room3.paidInCycle, false);
  assert.deepEqual(data.rooms.get('platform6/4').open, ['c']);
  // 같은 주문을 또 눌러도 다시 정산하지 않음
  assert.equal((await done('b')).body.settled, false);
  assert.equal(data.rooms.get('platform6/3').settledAt, room3.settledAt);
});

test('주문 내역 (84차): 포스로 들어간 주문은 cycle에, 결제되면 paid, 정산 끝이면 비움', async () => {
  const { call, data } = make({ orders: { a: ORDER, b: { ...ORDER, price: '5000' } } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'b' } });
  // 같은 주문을 다시 보내도 cycle에 한 번만
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  let cycle = data.rooms.get('platform6/3').cycle;
  assert.deepEqual(cycle.map((e) => [e.id, e.state]), [['a', 'open'], ['b', 'open']]);
  assert.equal(cycle[1].price, '5000');
  assert.ok(cycle[0].at);
  assert.ok(cycle[0].lines.length > 0);
  assert.equal(typeof cycle[0].lines[0].name, 'string');
  assert.ok(cycle[0].lines[0].options.every((x) => typeof x === 'string'));
  const fakes = Object.fromEntries(data.sandbox.get('fake-platform6').map((o) => [o.orderKey, o.id]));
  const done = (id) => call('POST', '/api/ops/toss/fake-complete', {
    token: 'ops', body: { storeId: 'platform6', orderKey: `godori-platform6-${id}`, id: fakes[`godori-platform6-${id}`] },
  });
  await done('a'); // 일행 한 명이 먼저 결제 → 결제됨으로 남김
  cycle = data.rooms.get('platform6/3').cycle;
  assert.deepEqual(cycle.map((e) => [e.id, e.state]), [['a', 'paid'], ['b', 'open']]);
  await done('b'); // 다 결제 → 정산 끝, 비움
  assert.deepEqual(data.rooms.get('platform6/3').cycle, []);
});

test('주문 내역: 취소는 cancelled, 요약은 옛 주문(lines 없음)·옵션 객체도 처리', async () => {
  const { cycleEntry, CYCLE_MAX } = require('../src/toss-data');
  const { data } = make();
  const e = (id) => cycleEntry(id, { price: 3000, items: ['아메리카노 x 1'], lines: [{ menuId: 'm1', name: '아메리카노', quantity: '2', options: [{ group: '온도', name: 'ICE', price: 500 }] }] }, 't');
  assert.deepEqual(e('x').lines[0], { menuId: 'm1', name: '아메리카노', quantity: 2, options: ['ICE'] });
  assert.equal(e('x').price, '3000');
  assert.deepEqual(cycleEntry('y', { items: ['라면 x 1'] }, 't').lines, []);
  await data.openRoomOrder('platform6', 3, 'x', e('x'));
  await data.openRoomOrder('platform6', 3, 'y', e('y'));
  await data.closeRoomOrder('platform6', 3, 'x', { paid: false, atIso: 't1' });
  assert.deepEqual(data.rooms.get('platform6/3').cycle.map((c) => c.state), ['cancelled', 'open']);
  // 최대 개수
  for (let i = 0; i < CYCLE_MAX + 5; i++) await data.openRoomOrder('platform6', 5, `o${i}`, e(`o${i}`));
  const c5 = data.rooms.get('platform6/5').cycle;
  assert.equal(c5.length, CYCLE_MAX);
  assert.equal(c5[c5.length - 1].id, `o${CYCLE_MAX + 4}`);
});

test('방 결제 끝: 취소만 있으면 정산 아님, 완료가 섞이면 정산', async () => {
  const { data } = make();
  await data.openRoomOrder('platform6', 3, 'x');
  await data.openRoomOrder('platform6', 3, 'y');
  assert.equal((await data.closeRoomOrder('platform6', 3, 'x', { paid: false, atIso: 't1' })).settled, false);
  assert.equal((await data.closeRoomOrder('platform6', 3, 'y', { paid: false, atIso: 't2' })).settled, false);
  assert.equal(data.rooms.get('platform6/3').settledAt, undefined);
  await data.openRoomOrder('platform6', 3, 'z');
  await data.openRoomOrder('platform6', 3, 'w');
  assert.equal((await data.closeRoomOrder('platform6', 3, 'z', { paid: true, atIso: 't3' })).settled, false);
  assert.equal((await data.closeRoomOrder('platform6', 3, 'w', { paid: false, atIso: 't4' })).settled, true);
  assert.equal(data.rooms.get('platform6/3').settledAt, 't4');
  assert.equal((await data.closeRoomOrder('platform6', 3, 'nope', { paid: true, atIso: 't5' })).settled, false);
});

test('웹훅 비밀값이 없으면 503', async () => {
  const { call } = make({ webhookSecret: '' });
  assert.equal((await call('POST', '/api/toss/webhook', { body: {}, rawBody: Buffer.from('{}') })).status, 503);
});
