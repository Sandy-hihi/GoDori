'use strict';
// 토스 POS 연동 저장소 (64차) — 전부 서버만 읽고 씀 (firestore.rules에 없는 경로·private은 앱에서 막힘)
//
//   stores/{매장}/private/tossPos   { mode: 'fake'|'live', merchantId, merchantName, businessNumber?, linkedAt,
//                                     printOrderSheet, menuMap: { 고도리 메뉴 ID: 토스 상품 ID } }
//   stores/{매장}/orders/{주문}.tossPos  { state: 'sending'|'sent'|'failed', mode, posOrderId, sentAt, failedAt,
//                                        code, error, warnings[], attempts, posState(웹훅: ACCEPTED·DECLINED·COMPLETED·CANCELLED…), posStateAt }
//   _tossInstallations/{merchantId}  토스 '앱 설치' 웹훅으로 받은 매장 { merchantId, name, businessNumber, installedAt, removedAt? }
//   _tossWebhooks/{x-toss-webhook-id}  같은 웹훅 두 번 처리 안 하게 { type, at }
//   _tossSandbox/{가짜 merchantId}/orders/{id}  가짜 포스에 들어온 주문 (운영자 페이지에서 봄, 81차: posState·completedAt)
//   stores/{매장}/roomStatus/{방 번호}  (81차) { open: [포스로 보낸 뒤 아직 안 끝난 주문 ID], paidInCycle, settledAt(ISO),
//                                        cycle: [이번 손님 주문 요약 — 84차 손님 패드 '주문 내역'] }
//        — 서버만 씀, 그 방 패드·관리자는 읽기(firestore.rules). open이 비고 그사이 결제 완료가 있었으면 settledAt을 새로 씀
//          → 그 방 패드가 로그인 때 고른 언어로 돌아감 (order_ready_overlay.dart)
//        cycle 항목 { id, at(ISO), price, items[], lines[{ menuId, name, quantity, options[이름] }], state: 'open'|'paid'|'cancelled' }
//          포스로 들어간 주문을 넣고, 완료 웹훅이면 paid·취소면 cancelled로 표시. 정산 끝(settledAt)이면 비움

const SENDING_TIMEOUT_MS = 60 * 1000; // 'sending'으로 남은 채 1분이 지나면 다시 보낼 수 있음
const CYCLE_MAX = 100; // 방 하나의 '주문 내역'에 남기는 최대 주문 수 (문서 크기 제한 대비)

function dupKeyError() {
  const { TossError } = require('./toss');
  return new TossError(400, 'DUPLICATED_ORDER_KEY', '이미 포스로 보낸 주문이에요. (같은 orderKey)');
}

function createFirestoreTossData(db) {
  const { FieldValue, Timestamp } = require('firebase-admin/firestore');
  const store = (id) => db.collection('stores').doc(id);
  const cfgRef = (id) => store(id).collection('private').doc('tossPos');
  const orderRef = (s, o) => store(s).collection('orders').doc(o);
  const roomRef = (s, r) => store(s).collection('roomStatus').doc(String(r));
  const iso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v || null);
  const plain = (obj) => {
    const out = {};
    for (const [k, v] of Object.entries(obj || {})) out[k] = v && typeof v.toDate === 'function' ? v.toDate().toISOString() : v;
    return out;
  };
  return {
    async getConfig(storeId) {
      const d = await cfgRef(storeId).get();
      return d.exists ? plain(d.data()) : null;
    },
    async setConfig(storeId, cfg) {
      await cfgRef(storeId).set({ ...cfg, updatedAt: FieldValue.serverTimestamp() });
    },
    async patchConfig(storeId, patch) {
      await cfgRef(storeId).set({ ...patch, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    },
    async clearConfig(storeId) {
      await cfgRef(storeId).delete();
    },
    async setMenuMap(storeId, map) {
      const update = { updatedAt: FieldValue.serverTimestamp() };
      for (const [menuId, itemId] of Object.entries(map)) {
        update[`menuMap.${menuId}`] = itemId == null ? FieldValue.delete() : itemId;
      }
      await cfgRef(storeId).update(update);
    },
    async getOrder(storeId, orderId) {
      const d = await orderRef(storeId, orderId).get();
      return d.exists ? d.data() : null;
    },
    // 보내기 시작 표시 — 이미 보냈거나 다른 요청이 보내는 중이면 { ok: false, order }
    async claimOrder(storeId, orderId, nowMs) {
      return db.runTransaction(async (tx) => {
        const ref = orderRef(storeId, orderId);
        const d = await tx.get(ref);
        if (!d.exists) return { ok: false, order: null };
        const order = d.data();
        const t = order.tossPos || {};
        const startedAt = t.startedAt && typeof t.startedAt.toMillis === 'function' ? t.startedAt.toMillis() : 0;
        if (t.state === 'sent' || (t.state === 'sending' && nowMs - startedAt < SENDING_TIMEOUT_MS)) return { ok: false, order };
        tx.update(ref, { 'tossPos.state': 'sending', 'tossPos.startedAt': Timestamp.fromMillis(nowMs) });
        return { ok: true, order };
      });
    },
    async setOrderToss(storeId, orderId, patch, { countAttempt = false } = {}) {
      const update = {};
      for (const [k, v] of Object.entries(patch)) update[`tossPos.${k}`] = v === undefined ? FieldValue.delete() : v;
      if (countAttempt) update['tossPos.attempts'] = FieldValue.increment(1);
      await orderRef(storeId, orderId).update(update);
    },
    async listFailedOrders(storeId, limit = 30) {
      const snap = await store(storeId).collection('orders').where('tossPos.state', '==', 'failed').limit(limit).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },
    // 95차: 포스로 보낸 주문 중 최근 것 (운영자 '포스 주문 확인') — 색인 없이 50개 읽어 보낸 시각순
    async listSentOrders(storeId, limit = 5) {
      const snap = await store(storeId).collection('orders').where('tossPos.state', '==', 'sent').limit(50).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => String((b.tossPos || {}).sentAt || '').localeCompare(String((a.tossPos || {}).sentAt || '')))
        .slice(0, limit);
    },
    async listMenus(storeId) {
      const snap = await store(storeId).collection('menus').get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },
    // 처음 받은 웹훅이면 true
    async recordWebhook(id, type) {
      try {
        await db.collection('_tossWebhooks').doc(String(id)).create({ type: String(type || ''), at: FieldValue.serverTimestamp() });
        return true;
      } catch (e) {
        if (e && (e.code === 6 || /ALREADY_EXISTS/i.test(String(e.message)))) return false;
        throw e;
      }
    },
    async saveInstallation(merchantId, info) {
      await db.collection('_tossInstallations').doc(String(merchantId)).set(info, { merge: true });
    },
    async listInstallations() {
      const snap = await db.collection('_tossInstallations').get();
      return snap.docs.map((d) => ({ merchantId: d.id, ...plain(d.data()) }));
    },
    async addFakeOrder(merchantId, order) {
      const ref = db.collection('_tossSandbox').doc(String(merchantId)).collection('orders').doc(String(order.id));
      try {
        await ref.create({ ...order, savedAt: FieldValue.serverTimestamp() });
      } catch (e) {
        if (e && (e.code === 6 || /ALREADY_EXISTS/i.test(String(e.message)))) throw dupKeyError();
        throw e;
      }
    },
    async markFakeOrder(merchantId, id, patch) {
      await db.collection('_tossSandbox').doc(String(merchantId)).collection('orders').doc(String(id)).set(patch, { merge: true });
    },
    // 81차: 방 결제 대기 목록 (84차: entry가 있으면 '주문 내역' cycle에도)
    async openRoomOrder(storeId, room, orderId, entry = null) {
      if (!entry) {
        await roomRef(storeId, room).set(
          { open: FieldValue.arrayUnion(String(orderId)), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        return;
      }
      await db.runTransaction(async (tx) => {
        const ref = roomRef(storeId, room);
        const d = await tx.get(ref);
        const update = openRoom(d.exists ? d.data() : {}, orderId, entry);
        tx.set(ref, { ...update, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      });
    },
    async closeRoomOrder(storeId, room, orderId, { paid = false, atIso } = {}) {
      return db.runTransaction(async (tx) => {
        const ref = roomRef(storeId, room);
        const d = await tx.get(ref);
        const r = closeRoom(d.exists ? d.data() : {}, orderId, paid, atIso);
        if (r.update) tx.set(ref, { ...r.update, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        return { settled: r.settled, open: r.open };
      });
    },
    async listFakeOrders(merchantId, limit = 30) {
      const snap = await db.collection('_tossSandbox').doc(String(merchantId)).collection('orders')
        .orderBy('savedAt', 'desc').limit(limit).get();
      return snap.docs.map((d) => {
        const o = d.data();
        return { ...o, savedAt: iso(o.savedAt) };
      });
    },
  };
}

// 84차: 주문 문서 → '주문 내역' 요약 (손님 패드가 roomStatus 문서 하나만 읽으면 되게)
function cycleEntry(orderId, order, atIso) {
  const o = order || {};
  const lines = (Array.isArray(o.lines) ? o.lines : []).slice(0, 50).map((l) => ({
    menuId: String((l && l.menuId) || ''),
    name: String((l && l.name) || ''),
    quantity: Math.max(1, Math.trunc(Number(l && l.quantity) || 1)),
    options: (Array.isArray(l && l.options) ? l.options : []).slice(0, 25)
      .map((x) => String((x && typeof x === 'object' ? x.name : x) || '')).filter(Boolean),
  }));
  return {
    id: String(orderId),
    at: String(atIso || ''),
    price: String(o.price == null ? '' : o.price),
    items: (Array.isArray(o.items) ? o.items : []).slice(0, 50).map(String),
    lines,
    state: 'open',
  };
}

// 방 결제 대기 목록에 주문 하나를 넣음 (+ cycle에 요약, 같은 주문은 한 번만)
function openRoom(cur, orderId, entry) {
  const open = Array.isArray(cur.open) ? cur.open.map(String) : [];
  const update = { open: open.includes(String(orderId)) ? open : [...open, String(orderId)] };
  if (entry) {
    const cycle = Array.isArray(cur.cycle) ? cur.cycle : [];
    if (!cycle.some((e) => e && String(e.id) === String(orderId))) update.cycle = [...cycle, entry].slice(-CYCLE_MAX);
  }
  return update;
}

// 방 결제 대기 목록에서 주문 하나를 뺌 — 목록이 비고 그사이 결제 완료(paid)가 한 번이라도 있었으면 정산 끝
// 84차: cycle에서 그 주문을 결제됨(paid)/취소(cancelled)로 표시, 정산 끝이면 cycle 비움
function closeRoom(cur, orderId, paid, atIso) {
  const open = Array.isArray(cur.open) ? cur.open.map(String) : [];
  if (!open.includes(String(orderId))) return { settled: false, open: open.length, update: null };
  const rest = open.filter((x) => x !== String(orderId));
  const paidInCycle = cur.paidInCycle === true || paid === true;
  const settled = rest.length === 0 && paidInCycle;
  const update = { open: rest, paidInCycle: settled ? false : paidInCycle };
  if (settled) update.settledAt = atIso;
  if (settled) {
    update.cycle = [];
  } else if (Array.isArray(cur.cycle)) {
    update.cycle = cur.cycle.map((e) => (e && String(e.id) === String(orderId)
      ? { ...e, state: paid === true ? 'paid' : 'cancelled' } : e));
  }
  return { settled, open: rest.length, update };
}

// 테스트용 메모리 저장소
function createMemoryTossData({ menus = {}, orders = {} } = {}) {
  const configs = new Map();
  const ordersMap = new Map(); // `${store}/${id}` -> order
  for (const [store, list] of Object.entries(orders)) for (const [id, o] of Object.entries(list)) ordersMap.set(`${store}/${id}`, JSON.parse(JSON.stringify(o)));
  const webhooks = new Set();
  const installs = new Map();
  const sandbox = new Map(); // merchantId -> [order]
  const rooms = new Map(); // `${store}/${room}` -> { open, paidInCycle, settledAt }
  return {
    configs, ordersMap, installs, sandbox, menus, rooms,
    async getConfig(s) {
      return configs.has(s) ? JSON.parse(JSON.stringify(configs.get(s))) : null;
    },
    async setConfig(s, cfg) {
      configs.set(s, JSON.parse(JSON.stringify(cfg)));
    },
    async patchConfig(s, patch) {
      configs.set(s, { ...(configs.get(s) || {}), ...patch });
    },
    async clearConfig(s) {
      configs.delete(s);
    },
    async setMenuMap(s, map) {
      const c = configs.get(s) || {};
      c.menuMap = { ...(c.menuMap || {}) };
      for (const [k, v] of Object.entries(map)) {
        if (v == null) delete c.menuMap[k];
        else c.menuMap[k] = v;
      }
      configs.set(s, c);
    },
    async getOrder(s, o) {
      const v = ordersMap.get(`${s}/${o}`);
      return v ? JSON.parse(JSON.stringify(v)) : null;
    },
    async claimOrder(s, o, nowMs) {
      const order = ordersMap.get(`${s}/${o}`);
      if (!order) return { ok: false, order: null };
      const t = order.tossPos || {};
      if (t.state === 'sent' || (t.state === 'sending' && nowMs - (t.startedAt || 0) < SENDING_TIMEOUT_MS)) return { ok: false, order };
      order.tossPos = { ...t, state: 'sending', startedAt: nowMs };
      return { ok: true, order: JSON.parse(JSON.stringify(order)) };
    },
    async setOrderToss(s, o, patch, { countAttempt = false } = {}) {
      const order = ordersMap.get(`${s}/${o}`);
      const t = { ...(order.tossPos || {}) };
      for (const [k, v] of Object.entries(patch)) {
        if (v === undefined) delete t[k];
        else t[k] = v;
      }
      if (countAttempt) t.attempts = (t.attempts || 0) + 1;
      order.tossPos = t;
    },
    async listFailedOrders(s) {
      return [...ordersMap.entries()]
        .filter(([k, v]) => k.startsWith(`${s}/`) && v.tossPos && v.tossPos.state === 'failed')
        .map(([k, v]) => ({ id: k.split('/')[1], ...v }));
    },
    async listSentOrders(s, limit = 5) {
      return [...ordersMap.entries()]
        .filter(([k, v]) => k.startsWith(`${s}/`) && v.tossPos && v.tossPos.state === 'sent')
        .map(([k, v]) => ({ id: k.split('/')[1], ...JSON.parse(JSON.stringify(v)) }))
        .sort((a, b) => String(b.tossPos.sentAt || '').localeCompare(String(a.tossPos.sentAt || '')))
        .slice(0, limit);
    },
    async listMenus(s) {
      return (menus[s] || []).map((m) => ({ ...m }));
    },
    async recordWebhook(id) {
      if (webhooks.has(id)) return false;
      webhooks.add(id);
      return true;
    },
    async saveInstallation(mid, info) {
      installs.set(String(mid), { ...(installs.get(String(mid)) || {}), ...info });
    },
    async listInstallations() {
      return [...installs.entries()].map(([merchantId, v]) => ({ merchantId, ...v }));
    },
    async addFakeOrder(mid, order) {
      const list = sandbox.get(String(mid)) || [];
      if (list.some((o) => o.orderKey === order.orderKey)) throw dupKeyError();
      list.unshift(order);
      sandbox.set(String(mid), list);
    },
    async listFakeOrders(mid) {
      return [...(sandbox.get(String(mid)) || [])];
    },
    async markFakeOrder(mid, id, patch) {
      const f = (sandbox.get(String(mid)) || []).find((o) => String(o.id) === String(id));
      if (f) Object.assign(f, patch);
    },
    async openRoomOrder(s, r, o, entry = null) {
      const k = `${s}/${r}`;
      const cur = rooms.get(k) || { open: [] };
      rooms.set(k, { ...cur, ...openRoom(cur, o, entry) });
    },
    async closeRoomOrder(s, r, o, { paid = false, atIso } = {}) {
      const k = `${s}/${r}`;
      const cur = rooms.get(k) || { open: [] };
      const res = closeRoom(cur, o, paid, atIso);
      if (res.update) rooms.set(k, { ...cur, ...res.update });
      return { settled: res.settled, open: res.open };
    },
  };
}

module.exports = { createFirestoreTossData, createMemoryTossData, SENDING_TIMEOUT_MS, cycleEntry, CYCLE_MAX };
