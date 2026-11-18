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
  TossError, createTossClient, buildTossOrder, fakeCatalogFromMenus, signWebhook, verifyWebhook, parseOrderKey, orderKeyOf, parseMapEntry, normName,
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

test('buildTossOrder: 포스에서 필수 옵션으로 묶인 메뉴 — 옵션을 골라 둔 연결 (99차)', () => {
  // 실제 매장 포스: '에이드' 한 상품 + 필수 옵션 [Only Ice: ICE] [에이드: 레모네이드·자몽에이드…] [당도: 기본·더 달게]
  const ade = {
    id: '500', title: '에이드', price: { priceValue: 4500 }, state: 'ON_SALE',
    options: [
      { id: '51', title: 'Only Ice', minChoices: 1, maxChoices: 1, choices: [{ id: '511', title: 'ICE', priceValue: 0 }] },
      { id: '52', title: '에이드', minChoices: 1, maxChoices: 1, choices: [{ id: '521', title: '레모네이드', priceValue: 0 }, { id: '522', title: '자몽에이드', priceValue: 300 }] },
      { id: '53', title: '당도', minChoices: 1, maxChoices: 1, choices: [{ id: '531', title: '기본', priceValue: 0 }, { id: '532', title: '더 달게', priceValue: 0 }] },
    ],
  };
  const cat = new Map([['500', ade]]);
  const order = { room: '#2', price: '9600', notes: '', lines: [line('a1', '자몽 에이드', 4800, 2, [{ group: '얼음', name: '아이스', price: 0 }, { group: '당도', name: '더달게', price: 0 }])] };
  // 자몽에이드 고정 + 고도리 옵션 '아이스'→ICE, '더달게'→더 달게 (띄어쓰기·영한 표기 무시)
  const r = buildTossOrder({ storeId: 's', orderId: 'o', order, menuMap: { a1: '500:52=522' }, catalogById: cat });
  const li = r.body.order.lineItems[0];
  assert.equal(li.targetType, 'ITEM');
  assert.deepEqual(li.optionChoices.map((c) => c.optionChoiceId), ['522', '511', '532']);
  assert.equal(li.itemPrice.priceValue, 4500); // 4800 - 고정 옵션 300 → 합계는 고도리 그대로
  assert.equal(r.body.order.chargePrice.totalAmount, 9600);
  assert.deepEqual(r.warnings, []);
  // 필수 옵션(당도)이 빠지면 이름만 + 안내
  const o2 = { ...order, lines: [line('a1', '자몽 에이드', 4800, 2, [{ group: '얼음', name: '아이스', price: 0 }])] };
  const r2 = buildTossOrder({ storeId: 's', orderId: 'o', order: o2, menuMap: { a1: '500:52=522' }, catalogById: cat });
  assert.equal(r2.body.order.lineItems[0].targetType, 'AD_HOC');
  assert.match(r2.warnings[0], /필수 옵션 '당도'/);
  // 골라 둔 옵션이 포스에서 사라지면 이름만
  const r3 = buildTossOrder({ storeId: 's', orderId: 'o', order, menuMap: { a1: '500:52=999' }, catalogById: cat });
  assert.equal(r3.body.order.lineItems[0].targetType, 'AD_HOC');
  // 연결 값 모양
  assert.deepEqual(parseMapEntry('500:52=522,53=531'), { itemId: '500', fixed: [{ optionId: '52', choiceId: '522' }, { optionId: '53', choiceId: '531' }] });
  assert.equal(parseMapEntry('500:52'), null);
  assert.equal(normName(' 왕메리카노(32oz) '), normName('왕메리카노'));
  assert.equal(normName('바닐라 라뗴'), normName('바닐라라떼'));
});

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
function make({ tossOn = true, webhookSecret = 'whsec', orders = {}, live = null } = {}) {
  const stores = createMemoryStores({ platform6: { name: '플랫폼6', account: {}, features: { tossPos: tossOn } } });
  const data = createMemoryTossData({ menus: { platform6: MENUS }, orders: { platform6: orders } });
  let t = 1_800_000_000_000;
  const now = () => t;
  const toss = createTossRoutes({
    data, stores, webhookSecret, now, live,
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

test('포스 주문 확인 (95차): 가짜 포스는 저장된 주문에서, 진짜는 주문 키 조회 — 없음·오류도 표시', async () => {
  const { call } = make({ orders: { a: ORDER, b: { ...ORDER } } });
  assert.equal((await call('GET', '/api/ops/toss/lookup', { token: 'ops', query: { storeId: 'platform6' } })).body.error, 'TOSS_NOT_LINKED');
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  assert.equal((await call('GET', '/api/ops/toss/lookup', { token: 'admin', query: { storeId: 'platform6' } })).status, 403);
  const r = await call('GET', '/api/ops/toss/lookup', { token: 'ops', query: { storeId: 'platform6' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.mode, 'fake');
  assert.equal(r.body.results.length, 1);
  assert.equal(r.body.results[0].found, true);
  assert.equal(r.body.results[0].toss.orderState, 'OPENED');
  assert.equal(r.body.results[0].toss.orderNumber, '3번 방');

  // 진짜: 첫 주문은 토스에 있음, 둘째는 404
  const calls = [];
  const live = {
    mode: 'live',
    listCatalogItems: async () => [],
    createOrder: async (mid, body) => ({ id: `t-${body.order.orderKey}` }),
    getOrderByKey: async (mid, key) => {
      calls.push([mid, key]);
      if (key.endsWith('-b')) throw Object.assign(new Error('없는 주문'), { status: 404, code: 'ORDER_NOT_FOUND' });
      return { id: '999', orderState: 'OPENED', source: 'OPEN_API', orderNumber: '3번 방', chargePrice: { totalAmount: 11500 }, lineItems: [{}, {}] };
    },
  };
  const m = make({ orders: { a: ORDER, b: { ...ORDER } }, live });
  await m.call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  await m.call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  m.tick(1000);
  await m.call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'b' } });
  const lr = await m.call('GET', '/api/ops/toss/lookup', { token: 'ops', query: { storeId: 'platform6' } });
  assert.equal(lr.status, 200);
  assert.equal(lr.body.mode, 'live');
  assert.deepEqual(lr.body.results.map((x) => [x.orderId, x.found]), [['b', false], ['a', true]]);
  assert.equal(lr.body.results[0].code, 'ORDER_NOT_FOUND');
  assert.equal(lr.body.results[1].toss.totalAmount, 11500);
  assert.deepEqual(calls.map((c) => c[0]), ['738910', '738910']);
  assert.equal(calls[1][1], 'godori-platform6-a');
});

test('포스 플러그인 신호 (96차): 로그인 없이 저장, 크기 줄임, 운영자만 목록 — 연결된 매장 표시', async () => {
  const { call, data } = make();
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  // 가맹점 ID 없는 'boot'·오류 신호 — 저장 없이 기록만
  const boot = await call('POST', '/api/toss/plugin/hello', { body: { stage: 'boot', version: '0.1.1', errors: ['merchant: x'] } });
  assert.equal(boot.status, 200);
  assert.equal(boot.body.saved, false);
  assert.equal(data.plugins.size, 0);
  const tables = Array.from({ length: 400 }, (_, i) => ({ id: i + 1, hallId: 7, title: `기본홀${i + 1}`, hasOrder: i === 0 }));
  const r = await call('POST', '/api/toss/plugin/hello', {
    body: { merchantId: 738910, merchantName: '테스트보겜카', serial: '26BP0000WP01528', version: '0.1.0',
      halls: [{ id: 7, title: '기본홀' }], tables, tableError: '' },
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.linkedStore, null); // 가짜 make()에는 live 클라이언트가 없어 연결이 안 됨
  const saved = data.plugins.get('738910');
  assert.equal(saved.tables.length, 300);
  assert.equal(saved.tables[0].hasOrder, true);
  assert.equal(saved.serial, '26BP0000WP01528');
  assert.equal(saved.count, 1);
  assert.deepEqual(saved.errors, []);
  assert.equal((await call('GET', '/api/ops/toss/plugins', { token: 'admin' })).status, 403);
  const list = await call('GET', '/api/ops/toss/plugins', { token: 'ops' });
  assert.equal(list.status, 200);
  assert.equal(list.body.plugins.length, 1);
  assert.equal(list.body.plugins[0].merchantId, '738910');

  // 진짜로 연결된 매장이면 linkedStore
  const live = { mode: 'live', listCatalogItems: async () => [], createOrder: async () => ({ id: '1' }) };
  const m = make({ live });
  await m.call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  const r2 = await m.call('POST', '/api/toss/plugin/hello', { body: { merchantId: '738910', tableError: 'x'.repeat(500) } });
  assert.equal(r2.body.linkedStore, 'platform6');
  assert.equal(m.data.plugins.get('738910').tableError.length, 200);
  const l2 = await m.call('GET', '/api/ops/toss/plugins', { token: 'ops' });
  assert.equal(l2.body.plugins[0].linkedStore, 'platform6');
});

test('포스 플러그인 2단계 (100차): 기기 승인 → 패드 주문 대기 → 플러그인이 가져가 테이블에 넣음 → 포스 완료로 방 정산', async () => {
  const catalog = fakeCatalogFromMenus(MENUS);
  const live = { mode: 'live', listCatalogItems: async () => catalog, createOrder: async () => { throw new Error('Open API로 보내면 안 됨'); } };
  // 플러그인은 포스 상품과 연결된 메뉴만 넣음 → 쿠키(연결할 포스 상품 없음) 뺀 주문
  const PORDER = { ...ORDER, lines: ORDER.lines.slice(0, 2), price: '9000' };
  const { call, data, tick } = make({ live, orders: { a: PORDER, b: { ...PORDER, price: '5000' }, c: { ...PORDER, room: '#4' } } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: { m1: catalog[0].id, m2: catalog[1].id } } });
  // 가짜 포스엔 플러그인 못 씀, 진짜에서만
  assert.equal((await call('POST', '/api/ops/toss/config', { token: 'ops', body: { storeId: 'platform6', via: 'x' } })).status, 400);
  assert.equal((await call('POST', '/api/ops/toss/config', { token: 'ops', body: { storeId: 'platform6', via: 'plugin' } })).status, 200);
  assert.equal((await call('GET', '/api/ops/toss/overview', { token: 'ops' })).body.links.platform6.via, 'plugin');

  // 패드 주문 → 서버에 대기
  const q = await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  assert.equal(q.body.tossPos.state, 'queued');
  assert.equal((await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } })).body.already, true);
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'b' } });

  // 기기 등록: 첫 신호에 열쇠, 승인 전엔 주문 못 받음
  const dev = { merchantId: 738910, serial: 'POS1', version: '0.2.0' };
  // 예전 플러그인(0.1.x — 열쇠를 저장 못 함) 신호로는 기기를 등록하지 않음
  const old = await call('POST', '/api/toss/plugin/hello', { body: { ...dev, version: '0.1.2' } });
  assert.equal(old.body.deviceToken, undefined);
  assert.deepEqual(await data.getPluginDevices('738910'), {});
  const h1 = await call('POST', '/api/toss/plugin/hello', { body: { ...dev } });
  assert.equal(h1.body.approved, false);
  assert.ok(h1.body.deviceToken);
  const token = h1.body.deviceToken;
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } })).status, 403);
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token: 'nope' } })).status, 403);
  const pl = await call('GET', '/api/ops/toss/plugins', { token: 'ops' });
  assert.equal(pl.body.plugins[0].devices.POS1.approved, false);
  assert.equal(pl.body.plugins[0].devices.POS1.tokenHash, undefined);
  assert.equal((await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'POS1', approved: true } })).status, 200);
  const h2 = await call('POST', '/api/toss/plugin/hello', { body: { ...dev, token } });
  assert.equal(h2.body.approved, true);
  assert.equal(h2.body.deviceToken, undefined);
  assert.equal(h2.body.via, 'plugin');
  // 승인된 기기는 열쇠 없이 다시 등록 못 함
  const h3 = await call('POST', '/api/toss/plugin/hello', { body: { ...dev } });
  assert.equal(h3.body.deviceToken, undefined);
  assert.ok(h3.body.deviceProblem);

  // 가져가기 — 다른 포스는 같은 주문을 못 받음
  const p1 = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } });
  assert.equal(p1.status, 200);
  assert.deepEqual(p1.body.orders.map((o) => o.orderId).sort(), ['a', 'b']);
  const oa = p1.body.orders.find((o) => o.orderId === 'a');
  assert.equal(oa.room, 3);
  assert.equal(oa.orderKey, 'godori-platform6-a');
  assert.equal(oa.lineItems[0].item.id, Number(catalog[0].id));
  assert.equal(oa.lineItems[0].quantity.value, 1);
  assert.equal(oa.lineItems[0].optionChoices.length, 2);
  assert.equal(oa.lineItems[1].item.title, '감자튀김');
  // 포스 SDK 검사: category는 {id: 숫자, title}
  assert.equal(String(oa.lineItems[0].item.category.id), String(fakeCatalogFromMenus(MENUS)[0].category.id)); // 안전한 정수면 숫자(가짜 포스 ID는 커서 문자열)
  assert.equal(oa.lineItems[0].item.category.title, '음료');
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } })).body.orders.length, 0);

  // 결과: a는 새 주문, b는 같은 테이블 열린 주문에 덧붙임, 남의 주문엔 못 씀
  const ack = (body) => call('POST', '/api/toss/plugin/ack', { body: { ...dev, token, ...body } });
  assert.equal((await ack({ orderId: 'c', ok: true, posOrderId: '9' })).status, 409);
  assert.equal((await ack({ orderId: 'a', ok: true, posOrderId: '777', tableId: 963261, tableTitle: '기본홀03', posAmount: 11500 })).status, 200);
  assert.equal((await ack({ orderId: 'b', ok: true, posOrderId: '777', tableId: 963261, tableTitle: '기본홀03', appended: true })).status, 200);
  assert.equal((await ack({ orderId: 'a', ok: true, posOrderId: '777' })).body.already, true);
  const ta = (await data.getOrder('platform6', 'a')).tossPos;
  assert.equal(ta.state, 'sent');
  assert.equal(ta.mode, 'plugin');
  assert.equal(ta.tableTitle, '기본홀03');
  assert.equal(ta.claimedAtMs, undefined);
  assert.deepEqual(data.rooms.get('platform6/3').open, ['a', 'b']);

  // 실패하면 failed, 관리자가 다시 보내면 다시 대기
  await call('POST', '/api/toss/send-order', { token: 'pad4', body: { orderId: 'c' } });
  const p2 = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } });
  assert.deepEqual(p2.body.orders.map((o) => o.orderId), ['c']);
  await ack({ orderId: 'c', ok: false, code: 'NO_TABLE', error: '4번 방에 맞는 테이블이 없어요.' });
  assert.equal((await data.getOrder('platform6', 'c')).tossPos.state, 'failed');
  assert.equal((await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: 'c' } })).body.tossPos.state, 'queued');
  // 가져간 뒤 답이 없으면 1분 30초 뒤 다시 가져갈 수 있음
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } })).body.orders.length, 1);
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } })).body.orders.length, 0);
  tick(91 * 1000);
  assert.equal((await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } })).body.orders.length, 1);

  // 포스 주문 완료(남은 금액 0) → 그 포스 주문에 들어간 고도리 주문 둘 다 결제 → 방 정산
  const ev = (body) => call('POST', '/api/toss/plugin/event', { body: { ...dev, token, ...body } });
  // 113차: 열린 주문 신호는 그 포스 주문의 고도리 주문을 찾되(줄·일부 결제 확인) 정산은 안 함
  const opened = (await ev({ posOrderId: '777', orderState: 'OPENED' })).body;
  assert.equal(opened.matched, 2);
  assert.equal(opened.cancelled, 0);
  const done = await ev({ posOrderId: '777', orderState: 'COMPLETED', unpaid: 0 });
  assert.equal(done.body.matched, 2);
  assert.equal(done.body.settled, true);
  assert.ok(data.rooms.get('platform6/3').settledAt);
  assert.equal((await data.getOrder('platform6', 'b')).tossPos.posState, 'COMPLETED');

  // 기기 지우기 → 다시 열쇠 받고 승인 전
  await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'POS1', remove: true } });
  const h4 = await call('POST', '/api/toss/plugin/hello', { body: { ...dev } });
  assert.ok(h4.body.deviceToken);
  assert.equal(h4.body.approved, false);
});

test('포스 플러그인: 결제 없이 완료(남은 금액 있음)는 결제로 안 봄, 취소도 정산 아님', async () => {
  const live = { mode: 'live', listCatalogItems: async () => fakeCatalogFromMenus(MENUS), createOrder: async () => ({ id: '1' }) };
  const cat = fakeCatalogFromMenus(MENUS);
  const { call, data } = make({ live, orders: { a: { ...ORDER, lines: ORDER.lines.slice(0, 1), price: '4000' } } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: { m1: cat[0].id } } });
  await call('POST', '/api/ops/toss/config', { token: 'ops', body: { storeId: 'platform6', via: 'plugin' } });
  const dev = { merchantId: '738910', serial: 'P', version: '0.2.0' };
  const token = (await call('POST', '/api/toss/plugin/hello', { body: dev })).body.deviceToken;
  await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'P', approved: true } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } });
  await call('POST', '/api/toss/plugin/ack', { body: { ...dev, token, orderId: 'a', ok: true, posOrderId: '5' } });
  const r = await call('POST', '/api/toss/plugin/event', { body: { ...dev, token, posOrderId: '5', orderState: 'COMPLETED', unpaid: 3000 } });
  assert.equal(r.body.settled, false);
  assert.equal((await data.getOrder('platform6', 'a')).tossPos.posState, 'CANCELLED');
  assert.ok(!data.rooms.get('platform6/3').settledAt);
});

test('포스 플러그인: 포스 상품과 연결 안 된 메뉴가 있으면 가져갈 때 바로 실패(포스 SDK가 상품 ID를 요구)', async () => {
  const live = { mode: 'live', listCatalogItems: async () => fakeCatalogFromMenus(MENUS), createOrder: async () => ({ id: '1' }) };
  const { call, data } = make({ live, orders: { a: ORDER } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  await call('POST', '/api/ops/toss/config', { token: 'ops', body: { storeId: 'platform6', via: 'plugin' } });
  const dev = { merchantId: '738910', serial: 'P', version: '0.2.1' };
  const token = (await call('POST', '/api/toss/plugin/hello', { body: dev })).body.deviceToken;
  await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'P', approved: true } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  const p = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } });
  assert.equal(p.body.orders.length, 0);
  const t = (await data.getOrder('platform6', 'a')).tossPos;
  assert.equal(t.state, 'failed');
  assert.equal(t.code, 'NOT_MAPPED');
  assert.match(t.error, /아메리카노, 감자튀김|감자튀김/);
});

test('세트 구성품 (103차): 관리자가 세트 → 구성품 저장 → 포스 플러그인이 poll 때 받음(번호가 같으면 안 보냄)', async () => {
  const live = { mode: 'live', listCatalogItems: async () => fakeCatalogFromMenus(MENUS), createOrder: async () => ({ id: '1' }) };
  const { call } = make({ live });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  const dev = { merchantId: '738910', serial: 'P', version: '0.3.0' };
  const token = (await call('POST', '/api/toss/plugin/hello', { body: dev })).body.deviceToken;
  await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'P', approved: true } });
  const save = (map) => call('POST', '/api/toss/set-map', { token: 'admin', body: { map } });
  // 잘못된 값
  assert.equal((await save({ abc: [{ entry: '1', qty: 1 }] })).status, 400);
  assert.equal((await save({ 500: [{ entry: '500', qty: 1 }] })).status, 400);
  assert.equal((await save({ 500: [{ entry: '11', qty: 0 }] })).status, 400);
  assert.equal((await save({ 500: [{ entry: 'x', qty: 1 }] })).status, 400);
  assert.equal((await call('POST', '/api/toss/set-map', { token: 'pad3', body: { map: {} } })).status, 403);
  // 저장: 떡볶이 닭껍질 세트(500) → 떡볶이(11, 옵션 7=71) 1개 + 닭껍질튀김(12) 2개, 구성품 없는 세트는 빠짐
  const ok = await save({ 500: [{ entry: '11:7=71', qty: 1 }, { entry: '12', qty: 2 }], 501: [] });
  assert.equal(ok.status, 200);
  assert.deepEqual(Object.keys(ok.body.setMap), ['500']);
  assert.deepEqual((await call('GET', '/api/toss/status', { token: 'admin' })).body.setMap['500'][1], { entry: '12', qty: 2 });
  // 플러그인 방식이 아니어도(직원이 포스에서 직접 누른 세트) 구성표는 받음
  const p1 = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token } });
  assert.equal(p1.status, 200);
  assert.deepEqual(p1.body.sets, [{ setId: 500, parts: [{ itemId: 11, qty: 1, choices: [{ id: 71, quantity: 1 }] }, { itemId: 12, qty: 2, choices: [] }] }]);
  assert.ok(p1.body.setMapRev > 0);
  const p2 = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token, setMapRev: p1.body.setMapRev } });
  assert.equal(p2.body.sets, undefined);
  // 옵션 조건 (세트에서 [떡볶이] 로제 → 로제 떡볶이)
  assert.equal((await save({ 500: [{ entry: '12', qty: 1, when: '7' }] })).status, 400);
  const w = await save({ 500: [{ entry: '12', qty: 1 }, { entry: '13', qty: 1, when: '8=81' }, { entry: '14', qty: 1, when: '8=82' }] });
  assert.equal(w.status, 200);
  assert.deepEqual(w.body.setMap['500'][1], { entry: '13', qty: 1, when: '8=81' });
  const pw = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token, setMapRev: p1.body.setMapRev } });
  assert.deepEqual(pw.body.sets[0].parts.map((x) => x.whenChoice), [undefined, 81, 82]);
  // 비우기 → 빈 목록을 다시 보냄
  await call('POST', '/api/toss/set-map', { token: 'admin', body: { map: {} } });
  const p3 = await call('POST', '/api/toss/plugin/poll', { body: { ...dev, token, setMapRev: p1.body.setMapRev } });
  assert.deepEqual(p3.body.sets, []);
});

// 113차: 토스 포스 플러그인 3단계 — 줄만 지움·일부 결제·테이블 옮기기/합치기·연결 안 된 메뉴(기타 상품)·포스 품절 따라가기·알림
async function pluginSetup({ orders, menuMap, menus } = {}) {
  const catalog = fakeCatalogFromMenus(menus || MENUS);
  const live = { mode: 'live', listCatalogItems: async () => catalog, createOrder: async () => ({ id: '1' }) };
  const ctx = make({ live, orders });
  const { call } = ctx;
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'live', merchantId: '738910' } });
  await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: menuMap || { m1: catalog[0].id, m2: catalog[1].id } } });
  await call('POST', '/api/ops/toss/config', { token: 'ops', body: { storeId: 'platform6', via: 'plugin' } });
  const dev = { merchantId: '738910', serial: 'P', version: '0.4.0' };
  const token = (await call('POST', '/api/toss/plugin/hello', { body: dev })).body.deviceToken;
  await call('POST', '/api/ops/toss/plugin-device', { token: 'ops', body: { merchantId: '738910', serial: 'P', approved: true } });
  const poll = (body = {}) => call('POST', '/api/toss/plugin/poll', { body: { ...dev, token, ...body } });
  const ack = (body) => call('POST', '/api/toss/plugin/ack', { body: { ...dev, token, ...body } });
  const ev = (body) => call('POST', '/api/toss/plugin/event', { body: { ...dev, token, ...body } });
  return { ...ctx, catalog, poll, ack, ev };
}

test('113차: 포스에서 고도리 주문 줄을 모두 지우면 그 주문만 취소, 일부 결제는 방에 표시 → 다 내면 정산·표시 지움', async () => {
  const PO = { ...ORDER, lines: ORDER.lines.slice(0, 2), price: '9000' };
  const { call, data, poll, ack, ev } = await pluginSetup({ orders: { a: PO, b: { ...PO, price: '5000' } } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'b' } });
  assert.equal((await poll()).body.orders.length, 2);
  await ack({ orderId: 'a', ok: true, posOrderId: '777', lineIds: ['L1', 'L2'] });
  await ack({ orderId: 'b', ok: true, posOrderId: '777', appended: true, lineIds: ['L3', 'L4'] });
  assert.deepEqual((await data.getOrder('platform6', 'a')).tossPos.lineIds, ['L1', 'L2']);
  // b의 줄 하나만 지움 → 남은 줄 수만 표시
  let r = (await ev({ posOrderId: '777', orderState: 'OPENED', lineIds: ['L1', 'L2', 'L3'], paid: 0, unpaid: 14000 })).body;
  assert.equal(r.partial, 1);
  assert.equal((await data.getOrder('platform6', 'b')).tossPos.linesLeft, 1);
  // a의 줄을 모두 지움 → a만 취소, 방 결제 대기에서 빠짐
  r = (await ev({ posOrderId: '777', orderState: 'OPENED', lineIds: ['L3'], paid: 0, unpaid: 5000 })).body;
  assert.equal(r.cancelled, 1);
  const ta = (await data.getOrder('platform6', 'a')).tossPos;
  assert.equal(ta.posState, 'CANCELLED');
  assert.ok(ta.posReason);
  assert.deepEqual(data.rooms.get('platform6/3').open, ['b']);
  assert.equal(data.rooms.get('platform6/3').cycle.find((e) => e.id === 'a').state, 'cancelled');
  // 일부 결제
  r = (await ev({ posOrderId: '777', orderState: 'OPENED', lineIds: ['L3'], paid: 3000, unpaid: 2000 })).body;
  assert.equal(r.partialPaid, true);
  assert.deepEqual({ ...data.rooms.get('platform6/3').posPayment, at: undefined }, { paid: 3000, unpaid: 2000, posOrderId: '777', at: undefined });
  // 다 냄 → b 결제, 정산, 일부 결제 표시 지움. 이미 줄 지움으로 취소한 a는 그대로 취소
  const done = (await ev({ posOrderId: '777', orderState: 'COMPLETED', unpaid: 0 })).body;
  assert.equal(done.settled, true);
  assert.equal(data.rooms.get('platform6/3').posPayment, null);
  assert.equal((await data.getOrder('platform6', 'a')).tossPos.posState, 'CANCELLED');
  assert.equal((await data.getOrder('platform6', 'b')).tossPos.posState, 'COMPLETED');
});

test('113차: 포스 테이블 옮기기·합치기 → 고도리 주문 테이블·포스 주문 번호를 따라감, 합친 주문이 끝나면 정산', async () => {
  const PO = { ...ORDER, lines: ORDER.lines.slice(0, 1), price: '4000' };
  const { call, data, poll, ack, ev } = await pluginSetup({ orders: { a: PO } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  await poll();
  await ack({ orderId: 'a', ok: true, posOrderId: '10', tableId: 1, tableTitle: '기본홀03', lineIds: ['X1'] });
  assert.equal((await ev({ kind: 'move', posOrderId: '10', toTableId: 2, toTableTitle: '기본홀05' })).body.matched, 1);
  assert.equal((await data.getOrder('platform6', 'a')).tossPos.tableTitle, '기본홀05');
  assert.equal((await ev({ kind: 'merge', fromPosOrderId: '10' })).status, 400);
  assert.equal((await ev({ kind: 'merge', fromPosOrderId: '10', toPosOrderId: '20', toTableId: 3, toTableTitle: '기본홀07' })).body.matched, 1);
  const t = (await data.getOrder('platform6', 'a')).tossPos;
  assert.equal(t.posOrderId, '20');
  assert.equal(t.mergedFrom, '10');
  assert.equal(t.lineIds, undefined); // 합치면 줄 추적은 그만둠
  // 합쳐진(없어진) 예전 포스 주문의 취소 신호는 이제 아무 주문에도 안 걸림
  assert.equal((await ev({ posOrderId: '10', orderState: 'CANCELLED' })).body.matched, 0);
  const done = (await ev({ posOrderId: '20', orderState: 'COMPLETED', unpaid: 0 })).body;
  assert.equal(done.matched, 1);
  assert.equal(done.settled, true);
});

test('114차: 자리이동·합석이면 방도 테이블을 따라감 — 원래 방은 비우고(패드 처음 화면) 결제 대기·주문 내역·주문 방 번호를 옮김', async () => {
  const PO = { ...ORDER, lines: ORDER.lines.slice(0, 1), price: '4000' };
  const { call, data, poll, ack, ev } = await pluginSetup({ orders: { a: PO, b: { ...PO, room: '#2' }, c: { ...PO, room: '#5' }, d: { ...PO, status: 'preparing' } } });
  for (const [id, pad] of [['a', 'pad3'], ['b', 'admin'], ['c', 'admin']]) {
    await call('POST', '/api/toss/send-order', { token: pad, body: { orderId: id } });
  }
  await poll();
  await ack({ orderId: 'a', ok: true, posOrderId: '30', tableTitle: '기본홀03' });
  await ack({ orderId: 'b', ok: true, posOrderId: '20', tableTitle: '기본홀02' });
  await ack({ orderId: 'c', ok: true, posOrderId: '50', tableTitle: '기본홀05' });
  // 자리이동: 3번 방(기본홀03) → 기본홀07
  const mv = (await ev({ kind: 'move', posOrderId: '30', toTableId: 7, toTableTitle: '기본홀07' })).body;
  assert.equal(mv.toRoom, 7);
  // 114차 2: 포스로 안 간 같은 방 주문(d — 준비 중)도 같이 옮김
  assert.deepEqual(mv.movedRooms, [{ from: 3, orders: 2, calls: 0, emptied: true }]);
  assert.equal((await data.getOrder('platform6', 'd')).room, '#7');
  const r3 = data.rooms.get('platform6/3');
  assert.deepEqual(r3.open, []);
  assert.deepEqual(r3.cycle, []);
  assert.ok(r3.settledAt); // 3번 방 패드 → 처음 화면
  assert.equal(r3.movedTo, 7);
  assert.deepEqual(data.rooms.get('platform6/7').open, ['a']);
  assert.equal(data.rooms.get('platform6/7').cycle[0].id, 'a');
  assert.equal((await data.getOrder('platform6', 'a')).room, '#7');
  // 합석: 5번 방 주문을 2번 방 주문에 합침 → 합친 주문이 있던 2번 방으로
  const mg = (await ev({ kind: 'merge', fromPosOrderId: '50', toPosOrderId: '20', toTableId: 2, toTableTitle: '기본홀02' })).body;
  assert.equal(mg.toRoom, 2);
  assert.deepEqual(data.rooms.get('platform6/2').open.sort(), ['b', 'c']);
  assert.ok(data.rooms.get('platform6/5').settledAt);
  // 합친 주문 결제 → 2번 방 정산(두 주문 다 결제)
  const done = (await ev({ posOrderId: '20', orderState: 'COMPLETED', unpaid: 0 })).body;
  assert.equal(done.matched, 2);
  assert.equal(done.settled, true);
  // 카운터처럼 방 번호를 모르는 테이블로 옮기면 방은 그대로
  const cnt = (await ev({ kind: 'move', posOrderId: '30', toTableId: 99, toTableTitle: '카운터' })).body;
  assert.equal(cnt.toRoom, null);
  assert.equal((await data.getOrder('platform6', 'a')).room, '#7');
});

test('113차: 연결 안 된 메뉴 — 기타 상품을 정하면 그 상품 줄(값 0)+메모로, 안 정하면 예전처럼 실패', async () => {
  const { call, data, catalog, poll } = await pluginSetup({ orders: { a: ORDER, b: ORDER } });
  // 기타 상품 없음 → 쿠키 때문에 실패
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  assert.equal((await poll()).body.orders.length, 0);
  assert.equal((await data.getOrder('platform6', 'a')).tossPos.code, 'NOT_MAPPED');
  // 기타 상품 정하기 (라면 상품을 기타로 씀 — 시험용)
  assert.equal((await call('POST', '/api/toss/etc-item', { token: 'admin', body: { itemId: 'x' } })).status, 400);
  assert.equal((await call('POST', '/api/toss/etc-item', { token: 'pad3', body: { itemId: '1' } })).status, 403);
  const etc = catalog[2];
  assert.equal((await call('POST', '/api/toss/etc-item', { token: 'admin', body: { itemId: etc.id } })).status, 200);
  assert.equal((await call('GET', '/api/toss/status', { token: 'admin' })).body.etcItemId, String(etc.id));
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'b' } });
  const p = (await poll()).body.orders;
  assert.equal(p.length, 1);
  const cookie = p[0].lineItems[2];
  assert.equal(String(cookie.item.id), String(Number.isSafeInteger(Number(etc.id)) ? Number(etc.id) : etc.id));
  assert.equal(cookie.chargePrice.value, 0);
  assert.equal(cookie.memo, '쿠키 2500원');
  assert.ok(p[0].warnings.some((w) => /쿠키/.test(w) && /2500원/.test(w)));
  // 지우기
  assert.equal((await call('POST', '/api/toss/etc-item', { token: 'admin', body: { itemId: null } })).body.etcItemId, null);
});

test('113차: 포스 품절 → 고도리 메뉴 posSoldOut (1분마다, 바뀐 것만), 플러그인 알림 저장', async () => {
  const menus = MENUS.map((m) => ({ ...m, optionGroups: [...m.optionGroups] }));
  const { call, data, poll, tick, catalog } = await pluginSetup({ menus });
  // 라면(m3) 포스 상품은 품절 — m3를 그 상품에 연결
  await call('POST', '/api/toss/menu-map', { token: 'admin', body: { map: { m3: catalog[2].id } } });
  tick(61 * 1000);
  await poll({ notes: ['세트 구성품 줄이 남았어요', ''] });
  const m3 = (await data.listMenus('platform6')).find((m) => m.id === 'm3');
  assert.equal(m3.posSoldOut, true);
  assert.deepEqual((await call('GET', '/api/toss/status', { token: 'admin' })).body.posSoldOutMenus, ['m3']);
  const notes = (await call('GET', '/api/ops/toss/plugins', { token: 'ops' })).body.plugins[0].notes;
  assert.deepEqual(notes.map((n) => n.text), ['세트 구성품 줄이 남았어요']);
  // 포스에서 다시 판매 → 1분 뒤 풀림
  catalog[2].state = 'ON_SALE';
  await poll();
  assert.equal((await data.listMenus('platform6')).find((m) => m.id === 'm3').posSoldOut, true); // 1분 안 지남
  tick(61 * 1000);
  await poll();
  assert.equal((await data.listMenus('platform6')).find((m) => m.id === 'm3').posSoldOut, false);
});

test('방 결제 대기 비우기 (102차): 운영자만, 남은 방 목록 → 비우면 open·cycle 비고 정산 표시는 없음', async () => {
  const { call, data } = make({ orders: { a: ORDER, b: { ...ORDER, room: '#4' } } });
  await call('POST', '/api/ops/toss/link', { token: 'ops', body: { storeId: 'platform6', mode: 'fake' } });
  await call('POST', '/api/toss/send-order', { token: 'pad3', body: { orderId: 'a' } });
  await call('POST', '/api/toss/send-order', { token: 'pad4', body: { orderId: 'b' } });
  assert.equal((await call('GET', '/api/ops/toss/rooms', { token: 'admin', query: { storeId: 'platform6' } })).status, 403);
  const list = await call('GET', '/api/ops/toss/rooms', { token: 'ops', query: { storeId: 'platform6' } });
  assert.deepEqual(list.body.rooms.map((r) => [r.room, r.open]), [[3, 1], [4, 1]]);
  assert.equal(list.body.rooms[0].orders[0].id, 'a');
  assert.equal((await call('POST', '/api/ops/toss/room-clear', { token: 'ops', body: { storeId: 'platform6', room: 'x' } })).status, 400);
  const c = await call('POST', '/api/ops/toss/room-clear', { token: 'ops', body: { storeId: 'platform6', room: 3 } });
  assert.equal(c.body.cleared, 1);
  const r3 = data.rooms.get('platform6/3');
  assert.deepEqual(r3.open, []);
  assert.deepEqual(r3.cycle, []);
  assert.ok(!r3.settledAt);
  const after = await call('GET', '/api/ops/toss/rooms', { token: 'ops', query: { storeId: 'platform6' } });
  assert.deepEqual(after.body.rooms.map((r) => r.room), [4]);
});

test('웹훅 비밀값이 없으면 503', async () => {
  const { call } = make({ webhookSecret: '' });
  assert.equal((await call('POST', '/api/toss/webhook', { body: {}, rawBody: Buffer.from('{}') })).status, 503);
});

test('114차 2: 단체손님 — 묶인 테이블의 방들을 roomStatus.group에 (표시만), 풀면 지움', async () => {
  const { call, data } = await pluginSetup({ orders: {} });
  const dev = { merchantId: '738910', serial: 'P', version: '0.4.1' };
  const hello = (tables) => call('POST', '/api/toss/plugin/hello', { body: { ...dev, tables } });
  const T = (id, title, groupId) => ({ id, hallId: 1, title, ...(groupId != null ? { groupId } : {}) });
  await hello([T(1, '기본홀01'), T(2, '기본홀02', 9), T(3, '기본홀03', 9), T(4, '카운터', 8), T(5, '기본홀05', 8)]);
  assert.deepEqual(data.rooms.get('platform6/2').group, { id: 9, rooms: [2, 3] });
  // 115차: 토스 묶음 색도 같이 (바뀌면 다시 씀)
  await hello([T(1, '기본홀01'), { ...T(2, '기본홀02', 9), groupColor: '#E05297' }, { ...T(3, '기본홀03', 9), groupColor: '#E05297' }, T(4, '카운터', 8), T(5, '기본홀05', 8)]);
  assert.deepEqual(data.rooms.get('platform6/3').group, { id: 9, rooms: [2, 3], color: '#E05297' });
  await hello([T(1, '기본홀01'), T(2, '기본홀02', 9), T(3, '기본홀03', 9), T(4, '카운터', 8), T(5, '기본홀05', 8)]);
  assert.deepEqual(data.rooms.get('platform6/3').group, { id: 9, rooms: [2, 3] });
  // 카운터 + 5번: 방 번호를 아는 건 5번뿐이어도 묶음 표시
  assert.deepEqual(data.rooms.get('platform6/5').group, { id: 8, rooms: [5] });
  assert.equal(data.rooms.get('platform6/1'), undefined);
  // 풂 → 지움
  await hello([T(1, '기본홀01'), T(2, '기본홀02'), T(3, '기본홀03'), T(4, '카운터'), T(5, '기본홀05')]);
  assert.equal(data.rooms.get('platform6/2').group, null);
  assert.equal(data.rooms.get('platform6/5').group, null);
});

test('115차: 합석해서 포스가 줄 ID를 새로 만들어도 취소로 보지 않음(금액 그대로) · 줄 수가 줄면 예전처럼 취소', async () => {
  const PO = { ...ORDER, lines: ORDER.lines.slice(0, 1), price: '3500' };
  const { call, data, poll, ack, ev } = await pluginSetup({ orders: { a: { ...PO, room: '#1' }, b: { ...PO, room: '#2' } } });
  for (const id of ['a', 'b']) await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: id } });
  await poll();
  await ack({ orderId: 'a', ok: true, posOrderId: '10', tableTitle: '기본홀01', lineIds: ['L1'] });
  await ack({ orderId: 'b', ok: true, posOrderId: '20', tableTitle: '기본홀02', lineIds: ['L2'] });
  await ev({ posOrderId: '10', orderState: 'OPENED', paid: 0, unpaid: 3500, lineIds: ['L1'] });
  await ev({ posOrderId: '20', orderState: 'OPENED', paid: 0, unpaid: 3500, lineIds: ['L2'] });
  // 1번을 2번에 합석 → 포스가 합친 주문 줄을 새 ID로
  await ev({ kind: 'merge', fromPosOrderId: '10', toPosOrderId: '20', toTableId: 2, toTableTitle: '기본홀02' });
  const r = (await ev({ posOrderId: '20', orderState: 'OPENED', paid: 0, unpaid: 7000, lineIds: ['N1', 'N2'] })).body;
  assert.equal(r.cancelled, 0);
  assert.deepEqual(data.rooms.get('platform6/2').open.sort(), ['a', 'b']);
  assert.equal((await data.getOrder('platform6', 'b')).tossPos.lineIds, undefined); // 줄 추적은 그만둠
  assert.notEqual((await data.getOrder('platform6', 'a')).tossPos.posState, 'CANCELLED');
  const done = (await ev({ posOrderId: '20', orderState: 'COMPLETED', unpaid: 0 })).body;
  assert.equal(done.settled, true);
});

test('115차: 1번·2번 손님 자리 맞교환 — 각자 주문이 서로 바뀐 방으로, 두 방 패드 모두 처음 화면 · 관리자 결제 대기 비우기', async () => {
  const PO = { ...ORDER, lines: ORDER.lines.slice(0, 1), price: '3500' };
  const { call, data, poll, ack, ev } = await pluginSetup({ orders: { a: { ...PO, room: '#1' }, b: { ...PO, room: '#2' } } });
  for (const id of ['a', 'b']) await call('POST', '/api/toss/send-order', { token: 'admin', body: { orderId: id } });
  await poll();
  await ack({ orderId: 'a', ok: true, posOrderId: '10', tableTitle: '기본홀01' });
  await ack({ orderId: 'b', ok: true, posOrderId: '20', tableTitle: '기본홀02' });
  const m1 = (await ev({ kind: 'move', posOrderId: '10', toTableId: 2, toTableTitle: '기본홀02' })).body;
  assert.deepEqual(m1.movedRooms, [{ from: 1, orders: 1, calls: 0, emptied: true }]);
  const m2 = (await ev({ kind: 'move', posOrderId: '20', toTableId: 1, toTableTitle: '기본홀01' })).body;
  assert.deepEqual(m2.movedRooms, [{ from: 2, orders: 1, calls: 0, emptied: false }]);
  assert.equal((await data.getOrder('platform6', 'a')).room, '#2');
  assert.equal((await data.getOrder('platform6', 'b')).room, '#1');
  assert.deepEqual(data.rooms.get('platform6/1').open, ['b']);
  assert.deepEqual(data.rooms.get('platform6/2').open, ['a']);
  assert.ok(data.rooms.get('platform6/1').settledAt && data.rooms.get('platform6/2').settledAt); // 두 패드 처음 화면
  // 관리자 방 현황판 '결제 대기 비우기'
  assert.equal((await call('POST', '/api/toss/room-clear', { token: 'pad3', body: { room: 2 } })).status, 403);
  const c = await call('POST', '/api/toss/room-clear', { token: 'admin', body: { room: 2 } });
  assert.equal(c.body.cleared, 1);
  assert.equal(c.body.orders, 1); // 116차: 진행 중 주문(a)도 완료로
  assert.deepEqual(data.rooms.get('platform6/2').open, []);
  assert.equal((await data.getOrder('platform6', 'a')).status, 'completed');
  assert.ok(data.rooms.get('platform6/2').settledAt);
});
