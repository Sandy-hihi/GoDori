'use strict';
// 손님 패드 주문 만들기 (147차) — 가격·이름·수량은 서버가 메뉴 문서로 계산
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const { createOrderRoutes, createMemoryOrders, seoulTime, MSG } = require('../src/orders');

const fakeVerify = async (t) => {
  if (t === 'admin') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
  if (t === 'pad3') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
  if (t === 'pad12') return { uid: 'pad.platform6.12', pad: true, store: 'platform6', room: 12 };
  if (t === 'cafe2') return { uid: 'pad.cafe2.1', pad: true, store: 'cafe2', room: 1 };
  if (t === 'wait') return { uid: 'pad.waiting.1', pad: true, store: 'waiting', room: 1 };
  throw new Error('bad');
};

const MENUS = {
  platform6: {
    m1: {
      name: '아메리카노', category: '커피', price: 3000,
      optionGroups: [
        { groupName: '온도', isRequired: true, options: [{ name: 'HOT', price: 0 }, { name: 'ICE', price: 500 }] },
        { groupName: '추가', maxSelect: 2, options: [{ name: '샷 추가', price: 500 }, { name: '시럽', price: 300 }, { name: '바닐라', price: 700, soldOut: true }] },
      ],
      posSoldOutOptions: ['추가|헤이즐넛'],
    },
    m2: { name: '감자튀김', category: '음식', price: '5000' },
    m3: { name: '라면', category: '음식', price: 4500, isSoldOut: true },
    m4: { name: '치킨', category: '음식', price: 18000, posSoldOut: true },
  },
  cafe2: { c1: { name: '쿠키', category: '디저트', price: 2000 } },
};

function make({ rooms = null, flow = null } = {}) {
  const stores = createMemoryStores({
    platform6: { name: '플랫폼6', account: {} },
    cafe2: { name: '두번째', account: {} },
    waiting: { name: '대기', account: {}, status: 'pending' },
  });
  const data = createMemoryOrders({ menus: MENUS, rooms, flow });
  const t = Date.UTC(2026, 10, 24, 6, 7); // 한국 11-24 15:07
  const httpError = (status, code, message) => Object.assign(new Error(message), { status, code });
  const orders = createOrderRoutes({ data, now: () => t, httpError });
  const h = createHandler({ bgg: {}, stores, verifyIdToken: fakeVerify, createToken: async () => 'x', attempts: createMemoryAttempts(), orders, now: () => t });
  const call = (body, token = 'pad3') =>
    h({ method: 'POST', path: '/api/order/create', query: {}, body, headers: token ? { authorization: `Bearer ${token}` } : {} });
  return { call, data };
}

const opt = (group, name) => ({ group, name });

test('주문: 가격·이름·카테고리는 메뉴 문서로, 방·시각·수령 방식은 서버가', async () => {
  const { call, data } = make({ flow: 'pickup' });
  const r = await call({
    lines: [
      { menuId: 'm1', quantity: 2, options: [opt('온도', 'ICE'), opt('추가', '샷 추가'), opt('추가', '시럽')],
        // 패드가 보낸 이름·가격은 무시
        name: '스테이크', basePrice: 1, price: 1 },
      { menuId: 'm2', quantity: 1 },
    ],
    notes: '  얼음 적게  ',
    price: '1', room: '#9', status: 'completed',
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.price, (3000 + 500 + 500 + 300) * 2 + 5000);
  const o = data.orders.get(r.body.orderId);
  assert.equal(o.storeId, 'platform6');
  assert.equal(o.room, '#3');
  assert.equal(o.time, '15시 07분');
  assert.equal(o.price, '13600');
  assert.deepEqual(o.items, ['아메리카노 (ICE, 샷 추가, 시럽) x 2', '감자튀김 x 1']);
  assert.equal(o.notes, '얼음 적게');
  assert.equal(o.status, 'pending');
  assert.equal(o.flow, 'pickup');
  assert.equal(o.roomColor, 0xFFC2365A);
  assert.deepEqual(o.lines[0], {
    menuId: 'm1', name: '아메리카노', category: '커피', basePrice: 3000, quantity: 2,
    options: [{ group: '온도', name: 'ICE', price: 500 }, { group: '추가', name: '샷 추가', price: 500 }, { group: '추가', name: '시럽', price: 300 }],
  });
  assert.deepEqual(o.lines[1], { menuId: 'm2', name: '감자튀김', category: '음식', basePrice: 5000, quantity: 1, options: [] });
});

test('주문: 그룹 이름 없이 보낸 옵션·옵션 순서는 메뉴 그룹 순서로, 요청 없으면 기본 문구, 수령 방식 이상하면 서빙', async () => {
  const { call, data } = make({ flow: 'drone' });
  const r = await call({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('추가', '시럽'), { name: 'HOT' }] }] });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const o = data.orders.get(r.body.orderId);
  assert.deepEqual(o.items, ['아메리카노 (HOT, 시럽) x 1']);
  assert.equal(o.price, '3300');
  assert.equal(o.notes, '추가사항 없음');
  assert.equal(o.flow, 'serve');
});

test('주문: 수량·줄·옵션이 이상하면 400', async () => {
  const { call, data } = make();
  const bad = async (body) => {
    const r = await call(body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.body.error, 'INVALID_ORDER');
    assert.equal(r.body.message, MSG.invalid);
  };
  for (const q of [0, -3, 1.5, '2', 100, null]) await bad({ lines: [{ menuId: 'm2', quantity: q }] });
  await bad({ lines: [] });
  await bad({ lines: 'm2' });
  await bad({ lines: Array.from({ length: 51 }, () => ({ menuId: 'm2', quantity: 1 })) });
  await bad({ lines: [{ menuId: 'a/b', quantity: 1 }] });
  await bad({ lines: [{ menuId: 'm2', quantity: 1 }], notes: 5 });
  // 한 그룹에 최대 개수 넘김(온도는 1개) · 같은 선택지 두 번
  await bad({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('온도', 'HOT'), opt('온도', 'ICE')] }] });
  await bad({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('온도', 'HOT'), opt('추가', '시럽'), opt('추가', '시럽')] }] });
  await bad({ lines: [{ menuId: 'm1', quantity: 1, options: 'HOT' }] });
  assert.equal(data.orders.size, 0);
});

test('주문: 없는 메뉴·없는 옵션·필수 옵션 빠짐 409 MENU_CHANGED, 품절 409 SOLD_OUT', async () => {
  const { call, data } = make();
  const code = async (body, status, error) => {
    const r = await call(body);
    assert.equal(r.status, status, JSON.stringify(body));
    assert.equal(r.body.error, error);
  };
  await code({ lines: [{ menuId: 'nope', quantity: 1 }] }, 409, 'MENU_CHANGED');
  await code({ lines: [{ menuId: 'c1', quantity: 1 }] }, 409, 'MENU_CHANGED'); // 다른 매장 메뉴
  await code({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('온도', '미지근')] }] }, 409, 'MENU_CHANGED');
  await code({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('추가', '시럽')] }] }, 409, 'MENU_CHANGED'); // 온도 필수
  await code({ lines: [{ menuId: 'm3', quantity: 1 }] }, 409, 'SOLD_OUT');
  await code({ lines: [{ menuId: 'm4', quantity: 1 }] }, 409, 'SOLD_OUT');
  await code({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('온도', 'HOT'), opt('추가', '바닐라')] }] }, 409, 'SOLD_OUT');
  MENUS.platform6.m1.optionGroups[1].options.push({ name: '헤이즐넛', price: 500 });
  await code({ lines: [{ menuId: 'm1', quantity: 1, options: [opt('온도', 'HOT'), opt('추가', '헤이즐넛')] }] }, 409, 'SOLD_OUT');
  MENUS.platform6.m1.optionGroups[1].options.pop();
  assert.equal(data.orders.size, 0);
});

test('주문: 손님 패드만, 방 개수 밖 방은 403, 승인 대기 매장은 막힘, 로그인 없으면 401', async () => {
  const { call } = make({ rooms: 10 });
  assert.equal((await call({ lines: [{ menuId: 'm2', quantity: 1 }] }, null)).status, 401);
  const admin = await call({ lines: [{ menuId: 'm2', quantity: 1 }] }, 'admin');
  assert.equal(admin.status, 403);
  assert.equal(admin.body.error, 'FORBIDDEN');
  const room = await call({ lines: [{ menuId: 'm2', quantity: 1 }] }, 'pad12');
  assert.equal(room.status, 403);
  assert.equal(room.body.error, 'ROOM');
  assert.equal((await call({ lines: [{ menuId: 'c1', quantity: 1 }] }, 'wait')).status, 403);
  // 다른 매장 패드는 자기 매장 메뉴로
  const c = await call({ lines: [{ menuId: 'c1', quantity: 3 }] }, 'cafe2');
  assert.equal(c.status, 200);
  assert.equal(c.body.price, 6000);
  // 방 설정이 없으면 11개까지
  assert.equal((await make().call({ lines: [{ menuId: 'm2', quantity: 1 }] }, 'pad12')).status, 403);
});

test('주문: 같은 방에서 1분에 20번 넘게 보내면 429', async () => {
  const { call } = make();
  for (let i = 0; i < 20; i++) assert.equal((await call({ lines: [{ menuId: 'm2', quantity: 1 }] })).status, 200);
  assert.equal((await call({ lines: [{ menuId: 'm2', quantity: 1 }] })).status, 429);
});

test('seoulTime: 한국 시각 모양', () => {
  assert.equal(seoulTime(Date.UTC(2026, 10, 24, 15, 5)), '0시 05분');
  assert.equal(seoulTime(Date.UTC(2026, 10, 24, 14, 59)), '23시 59분');
});
