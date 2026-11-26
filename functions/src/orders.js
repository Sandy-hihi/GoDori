'use strict';
// 손님 패드 주문 만들기 (147차, 보안 점검) — 이름·가격·옵션 값을 서버가 메뉴 문서로 다시 계산
//
//   POST /api/order/create  (손님 패드 — 토큰 { pad: true, store, room })
//        { lines: [{ menuId, quantity, options: [{ group, name }] }], notes }  →  { orderId, price }
//
// 예전(~146차)엔 패드가 stores/{매장}/orders 에 직접 썼는데, 보안 규칙은 목록 안의 금액·수량을 검사할 수 없어서
// 패드를 조작하면 '아메리카노 1원'·'수량 -3'·'메뉴 ID는 싼 것, 이름은 비싼 것' 같은 주문을 넣을 수 있었음.
// 이제 패드는 메뉴 ID·개수·고른 옵션 이름만 보내고, 서버가 메뉴 문서에서 이름·카테고리·가격·옵션 값을 읽어
// 예전과 같은 모양의 주문 문서(room·time·price·items·notes·roomColor·status·flow·timestamp·lines)를 만듦.
// 방 번호는 토큰에서, 수령 방식(flow)은 settings/orderFlow 에서. firestore.rules 는 orders create 를 막음.
// 토스 POS 보내기(/api/toss/send-order)·매장 통계(/api/stats/order)는 예전처럼 패드가 주문 ID로 이어서 부름.
//
// 품절: 손으로 켠 품절(isSoldOut)·포스 품절(posSoldOut)·선택지 품절(soldOut, posSoldOutOptions)은 서버도 막음.
//       자동 품절 시간(settings/soldOutSchedule, 112차)은 지금처럼 패드가 확인(서버는 안 봄).

const MAX_LINES = 50;
const MAX_QTY = 99;
const MAX_OPTIONS = 25;
const NOTES_MAX = 300;
const DEFAULT_ROOMS = 11; // firestore.rules roomOk 와 같게 (settings/rooms 가 없으면 11개)
const FLOWS = ['serve', 'pickup', 'pickupPay'];
const ROOM_COLOR = 0xFFC2365A; // 예전 패드 주문과 같은 색
const MENU_ID_RE = /^[A-Za-z0-9_-]{1,100}$/;

// 손님 패드에 보이는 문구 — lib/l10n/guest_messages.dart 에 같은 글자로 번역이 있어야 함
const MSG = {
  invalid: '주문 내용이 올바르지 않아요. 장바구니를 비우고 다시 담아 주세요.',
  changed: '메뉴가 바뀌었어요. 장바구니를 비우고 다시 담아 주세요.',
  soldOut: '품절된 메뉴가 장바구니에 있어요. 빼고 다시 주문해 주세요.',
  room: '이 방 번호로는 주문할 수 없어요. 직원에게 알려 주세요.',
};

// 패드의 _price 와 같게: 정수면 그대로, 숫자 글자면 읽고, 아니면 0
function toInt(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.trunc(v) : 0;
  if (typeof v === 'string' && /^\s*-?\d{1,9}\s*$/.test(v)) return parseInt(v, 10);
  return 0;
}
const str = (v) => (v == null ? '' : String(v));
const same = (a, b) => str(a).trim() === str(b).trim();
const isTrue = (v) => v === true || v === 'true';

// 패드가 예전에 쓰던 '15시 07분' 모양 (한국 시간)
function seoulTime(ms) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Seoul', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(ms));
  const h = Number((parts.find((p) => p.type === 'hour') || {}).value) % 24;
  const m = (parts.find((p) => p.type === 'minute') || {}).value || '00';
  return `${h}시 ${m}분`;
}

// 패드가 보낸 줄 하나 + 메뉴 문서 → { line(주문 lines 한 줄), text(items 한 줄), amount }
function priceLine(raw, menu, err) {
  const quantity = raw.quantity;
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > MAX_QTY) throw err(400, 'INVALID_ORDER', MSG.invalid);
  if (isTrue(menu.isSoldOut) || menu.posSoldOut === true) throw err(409, 'SOLD_OUT', MSG.soldOut);
  const name = str(menu.name).trim() || '이름 없음';
  const base = Math.max(0, toInt(menu.price));
  const groups = Array.isArray(menu.optionGroups) ? menu.optionGroups : [];
  const posOut = Array.isArray(menu.posSoldOutOptions) ? menu.posSoldOutOptions.map(str) : [];

  const asked = raw.options == null ? [] : raw.options;
  if (!Array.isArray(asked) || asked.length > MAX_OPTIONS) throw err(400, 'INVALID_ORDER', MSG.invalid);
  const picks = groups.map(() => []); // 그룹마다 고른 선택지(보낸 순서)
  for (const o of asked) {
    if (!o || typeof o !== 'object' || typeof o.name !== 'string') throw err(400, 'INVALID_ORDER', MSG.invalid);
    // 그룹 이름이 같은 그룹에서 먼저 찾고, 없으면 그 이름의 선택지가 있는 첫 그룹
    const has = (g) => g && Array.isArray(g.options) && g.options.some((x) => x && same(x.name, o.name));
    let gi = groups.findIndex((g) => g && same(g.groupName, o.group) && has(g));
    if (gi < 0 && (o.group == null || o.group === '')) gi = groups.findIndex(has);
    if (gi < 0) throw err(409, 'MENU_CHANGED', MSG.changed);
    const g = groups[gi];
    const opt = g.options.find((x) => x && same(x.name, o.name));
    if (picks[gi].includes(opt)) throw err(400, 'INVALID_ORDER', MSG.invalid);
    if (opt.soldOut === true || posOut.includes(`${str(g.groupName)}|${str(opt.name)}`)) throw err(409, 'SOLD_OUT', MSG.soldOut);
    picks[gi].push(opt);
  }
  groups.forEach((g, gi) => {
    if (!g) return;
    const max = Math.min(99, Math.max(1, toInt(g.maxSelect == null ? 1 : g.maxSelect) || 1));
    if (picks[gi].length > max) throw err(400, 'INVALID_ORDER', MSG.invalid);
    if (g.isRequired === true && picks[gi].length === 0) throw err(409, 'MENU_CHANGED', MSG.changed);
  });

  const options = [];
  groups.forEach((g, gi) => {
    for (const opt of picks[gi]) {
      // 패드와 같게: 옵션 값은 정수만(글자·소수는 0)
      const price = Number.isInteger(opt.price) ? Math.max(0, opt.price) : 0;
      options.push({ group: str(g.groupName), name: str(opt.name), price });
    }
  });
  const unit = base + options.reduce((s, o) => s + o.price, 0);
  const label = options.length ? `${name} (${options.map((o) => o.name).join(', ')})` : name;
  return {
    line: { menuId: raw.menuId, name, category: str(menu.category), basePrice: base, quantity, options },
    text: `${label} x ${quantity}`,
    amount: unit * quantity,
  };
}

// 주문 문서 만들기 (저장 전) — 테스트에서도 씀
function buildOrder({ body, room, menus, flow, nowMs, err }) {
  const lines = body && body.lines;
  if (!Array.isArray(lines) || lines.length < 1 || lines.length > MAX_LINES) throw err(400, 'INVALID_ORDER', MSG.invalid);
  const notesRaw = body.notes == null ? '' : body.notes;
  if (typeof notesRaw !== 'string') throw err(400, 'INVALID_ORDER', MSG.invalid);
  const notes = notesRaw.trim().slice(0, NOTES_MAX);
  const out = [];
  const items = [];
  let total = 0;
  for (const raw of lines) {
    if (!raw || typeof raw !== 'object' || typeof raw.menuId !== 'string' || !MENU_ID_RE.test(raw.menuId)) {
      throw err(400, 'INVALID_ORDER', MSG.invalid);
    }
    const menu = menus.get(raw.menuId);
    if (!menu) throw err(409, 'MENU_CHANGED', MSG.changed);
    const p = priceLine(raw, menu, err);
    out.push(p.line);
    items.push(p.text);
    total += p.amount;
  }
  return {
    room: `#${room}`,
    time: seoulTime(nowMs),
    price: String(total),
    items,
    notes: notes || '추가사항 없음',
    roomColor: ROOM_COLOR,
    status: 'pending',
    flow: FLOWS.includes(flow) ? flow : 'serve',
    lines: out,
  };
}

// data: { getMenus(storeId, ids) → Map(id → 메뉴), getRoomCount(storeId) → 숫자|null, getFlow(storeId) → 글자|null,
//         createOrder(storeId, doc) → 주문 ID (timestamp 는 data 가 서버 시각으로) }
function createOrderRoutes({ data, now = () => Date.now(), httpError }) {
  const err = httpError;

  async function create(req, ctx) {
    const user = await ctx.requireStoreUser(req);
    if (user.pad !== true || typeof user.room !== 'number') throw err(403, 'FORBIDDEN', '손님 패드에서만 주문할 수 있어요.');
    const room = Math.trunc(user.room);
    ctx.rate(`order:${user.store}:${room}`, 20, 60 * 1000, '주문');
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const ids = Array.isArray(body.lines)
      ? [...new Set(body.lines.map((l) => (l && typeof l.menuId === 'string' && MENU_ID_RE.test(l.menuId) ? l.menuId : null)).filter(Boolean))]
      : [];
    if (ids.length > MAX_LINES) throw err(400, 'INVALID_ORDER', MSG.invalid);
    const [menus, count, flow] = await Promise.all([
      ids.length ? data.getMenus(user.store, ids) : new Map(),
      data.getRoomCount(user.store),
      data.getFlow(user.store),
    ]);
    const rooms = Number.isInteger(count) && count >= 1 ? count : DEFAULT_ROOMS;
    if (room < 1 || room > rooms) throw err(403, 'ROOM', MSG.room);
    const doc = buildOrder({ body, room, menus, flow, nowMs: now(), err });
    const orderId = await data.createOrder(user.store, doc);
    return { ok: true, orderId, price: Number(doc.price) };
  }

  async function route(req, path, ctx) {
    if (path === '/api/order/create' && req.method === 'POST') return create(req, ctx);
    throw err(404, 'NOT_FOUND', '없는 주소예요.');
  }

  return { route };
}

function createFirestoreOrders(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  const store = (id) => db.collection('stores').doc(id);
  return {
    async getMenus(storeId, ids) {
      const refs = ids.map((id) => store(storeId).collection('menus').doc(id));
      const snaps = await db.getAll(...refs);
      const map = new Map();
      for (const s of snaps) if (s.exists) map.set(s.id, s.data());
      return map;
    },
    async getRoomCount(storeId) {
      const s = await store(storeId).collection('settings').doc('rooms').get();
      return s.exists ? s.get('count') : null;
    },
    async getFlow(storeId) {
      const s = await store(storeId).collection('settings').doc('orderFlow').get();
      return s.exists ? s.get('mode') : null;
    },
    async createOrder(storeId, doc) {
      const ref = await store(storeId).collection('orders').add({ ...doc, timestamp: FieldValue.serverTimestamp() });
      return ref.id;
    },
  };
}

function createMemoryOrders({ menus = {}, rooms = null, flow = null } = {}) {
  const orders = new Map();
  let n = 0;
  return {
    orders,
    menus,
    async getMenus(storeId, ids) {
      const all = menus[storeId] || {};
      return new Map(ids.filter((id) => all[id]).map((id) => [id, all[id]]));
    },
    async getRoomCount() { return rooms; },
    async getFlow() { return flow; },
    async createOrder(storeId, doc) {
      const id = `o${++n}`;
      orders.set(id, { storeId, ...doc, timestamp: 'server' });
      return id;
    },
  };
}

module.exports = { MSG, seoulTime, buildOrder, createOrderRoutes, createFirestoreOrders, createMemoryOrders };
