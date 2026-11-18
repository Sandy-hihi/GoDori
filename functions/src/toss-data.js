'use strict';
// 토스 POS 연동 저장소 (64차) — 전부 서버만 읽고 씀 (firestore.rules에 없는 경로·private은 앱에서 막힘)
//
//   stores/{매장}/private/tossPos   { mode: 'fake'|'live', merchantId, merchantName, businessNumber?, linkedAt,
//                                     printOrderSheet, menuMap: { 고도리 메뉴 ID: 토스 상품 ID } }
//   stores/{매장}/orders/{주문}.tossPos  { state: 'sending'|'sent'|'failed', mode, posOrderId, sentAt, failedAt,
//                                        code, error, warnings[], attempts, posState(웹훅: ACCEPTED·DECLINED·COMPLETED·CANCELLED…), posStateAt }
//        100차 포스 플러그인으로 보내는 매장(private/tossPos.via == 'plugin'): state 'queued'(서버에 대기) → 'claimed'(포스 플러그인이
//        가져감 — claimedBy 포스 시리얼, claimedAtMs) → 'sent'(mode 'plugin', posOrderId = 포스 주문 ID, tableId·tableTitle, appended)
//        · 'failed'. 같은 테이블에 열린 주문이 있으면 그 주문에 덧붙여서(addMenu) 여러 고도리 주문이 같은 posOrderId를 가짐
//   _tossInstallations/{merchantId}  토스 '앱 설치' 웹훅으로 받은 매장 { merchantId, name, businessNumber, installedAt, removedAt? }
//   _tossWebhooks/{x-toss-webhook-id}  같은 웹훅 두 번 처리 안 하게 { type, at }
//   _tossSandbox/{가짜 merchantId}/orders/{id}  가짜 포스에 들어온 주문 (운영자 페이지에서 봄, 81차: posState·completedAt)
//   _tossPlugin/{merchantId}  (96차) 토스 포스 플러그인이 보낸 '살아 있어요' 신호 { merchantName, serial, version, halls[], tables[],
//                              tableError, lastSeenAt, count } — 포스 기계가 여러 대면 serial만 마지막 것
//                              100차 devices: { 포스 시리얼: { tokenHash, approved, firstSeenAt, lastSeenAt, version } } — 운영자가 승인한 기기만 주문을 받음
//   stores/{매장}/roomStatus/{방 번호}  (81차) { open: [포스로 보낸 뒤 아직 안 끝난 주문 ID], paidInCycle, settledAt(ISO),
//                                        cycle: [이번 손님 주문 요약 — 84차 손님 패드 '주문 내역'] }
//        — 서버만 씀, 그 방 패드·관리자는 읽기(firestore.rules). open이 비고 그사이 결제 완료가 있었으면 settledAt을 새로 씀
//          → 그 방 패드가 로그인 때 고른 언어로 돌아감 (order_ready_overlay.dart)
//        cycle 항목 { id, at(ISO), price, items[], lines[{ menuId, name, quantity, options[이름] }], state: 'open'|'paid'|'cancelled' }
//          포스로 들어간 주문을 넣고, 완료 웹훅이면 paid·취소면 cancelled로 표시. 정산 끝(settledAt)이면 비움
//        113차 posPayment: { paid, unpaid, posOrderId, at } — 포스에서 일부만 결제됨(나눠 내기 등). 정산 끝이면 null

const SENDING_TIMEOUT_MS = 60 * 1000; // 'sending'으로 남은 채 1분이 지나면 다시 보낼 수 있음
const CLAIM_TIMEOUT_MS = 90 * 1000; // 100차: 포스 플러그인이 가져간 뒤 1분 30초 답이 없으면 다른 포스(또는 다시)가 가져갈 수 있음
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
    // 103차: 세트 구성품 표 통째로 바꾸기 (rev = 바꾼 시각 ms — 포스 플러그인이 바뀐 걸 알아보는 번호)
    async setSetMap(storeId, setMap, rev) {
      await cfgRef(storeId).update({ setMap, setMapRev: rev, updatedAt: FieldValue.serverTimestamp() });
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
    // 96차: 포스 플러그인 신호
    async savePluginHello(merchantId, info) {
      await db.collection('_tossPlugin').doc(String(merchantId)).set(
        { ...info, lastSeenAt: FieldValue.serverTimestamp(), count: FieldValue.increment(1) }, { merge: true });
    },
    async listPluginHellos() {
      const snap = await db.collection('_tossPlugin').get();
      return snap.docs.map((d) => ({ merchantId: d.id, ...plain(d.data()) }));
    },
    // 100차: 플러그인 기기(포스 시리얼)별 { tokenHash, approved, firstSeenAt, lastSeenAt } — _tossPlugin/{merchantId}.devices
    async getPluginDevices(merchantId) {
      const d = await db.collection('_tossPlugin').doc(String(merchantId)).get();
      return (d.exists && d.data().devices) || {};
    },
    async setPluginDevice(merchantId, serial, patch) {
      const ref = db.collection('_tossPlugin').doc(String(merchantId));
      if (patch == null) {
        await ref.set({ devices: { [serial]: FieldValue.delete() } }, { merge: true });
        return;
      }
      await ref.set({ devices: { [serial]: patch } }, { merge: true });
    },
    // 100차: 포스 플러그인이 가져갈 주문 (queued, 또는 가져갔는데 답이 없는 claimed)
    async listPluginOrders(storeId, limit = 20) {
      const snap = await store(storeId).collection('orders').where('tossPos.state', 'in', ['queued', 'claimed']).limit(limit).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },
    // 한 포스만 가져가게 — queued거나, claimed인데 CLAIM_TIMEOUT_MS 넘게 답이 없으면 가져감
    async claimPluginOrder(storeId, orderId, serial, nowMs) {
      return db.runTransaction(async (tx) => {
        const ref = orderRef(storeId, orderId);
        const d = await tx.get(ref);
        if (!d.exists) return null;
        const t = d.data().tossPos || {};
        const free = t.state === 'queued' || (t.state === 'claimed' && nowMs - (Number(t.claimedAtMs) || 0) > CLAIM_TIMEOUT_MS);
        if (!free) return null;
        tx.update(ref, { 'tossPos.state': 'claimed', 'tossPos.claimedBy': String(serial), 'tossPos.claimedAtMs': nowMs });
        return d.data();
      });
    },
    async findOrdersByPosOrder(storeId, posOrderId) {
      const snap = await store(storeId).collection('orders').where('tossPos.posOrderId', '==', String(posOrderId)).limit(50).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },
    // 113차: 포스에서 일부만 결제된 방 (패드 '주문 내역'·관리자 방 현황판에 보임) — null이면 지움
    async setRoomPayment(storeId, room, payment) {
      await roomRef(storeId, room).set({ posPayment: payment, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    },
    // 114차: 자리이동·합석 — 두 방 문서를 한 번에 + 주문 문서의 방 번호(room '#N')도 바꿈
    async moveRoomOrders(storeId, fromRoom, toRoom, orderIds, atIso) {
      return db.runTransaction(async (tx) => {
        const fRef = roomRef(storeId, fromRoom);
        const tRef = roomRef(storeId, toRoom);
        const [f, t] = await Promise.all([tx.get(fRef), tx.get(tRef)]);
        const r = moveRoom(f.exists ? f.data() : {}, t.exists ? t.data() : {}, orderIds, atIso, toRoom);
        tx.set(fRef, { ...r.fromUpdate, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        tx.set(tRef, { ...r.toUpdate, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        for (const id of orderIds) {
          tx.update(orderRef(storeId, id), { room: `#${Number(toRoom)}`, 'tossPos.movedFromRoom': Number(fromRoom), 'tossPos.movedRoomAt': atIso });
        }
        return { emptied: r.emptied, moved: r.moved };
      });
    },
    // 114차 2: 방 전체 옮기기 — 결제 대기·주문 내역 + 그 방 주문(주문 내역에 있는 것 + 아직 손님에게 안 간 것)
    //   + 확인 안 한 직원 호출까지 새 방으로 (방 현황판·관리자 패드 주문현황·패드 주문 내역이 모두 새 방으로)
    async moveWholeRoom(storeId, fromRoom, toRoom, atIso, moveIds) {
      const col = store(storeId).collection('orders');
      const callsCol = store(storeId).collection('staff_calls');
      const roomTag = `#${Number(fromRoom)}`;
      return db.runTransaction(async (tx) => {
        const fRef = roomRef(storeId, fromRoom);
        const tRef = roomRef(storeId, toRoom);
        const [f, t, active, calls] = await Promise.all([
          tx.get(fRef), tx.get(tRef),
          tx.get(col.where('status', 'in', ['pending', 'preparing', 'ready'])), // 진행 중 주문만(적음) — 방은 아래에서 거름(색인 없이)
          tx.get(callsCol.where('isAcknowledged', '==', false)),
        ]);
        const fd = f.exists ? f.data() : {};
        const want = new Set((moveIds || []).map(String));
        const cand = new Set([...want, ...active.docs.filter((d) => d.data().room === roomTag).map((d) => d.id)]);
        for (const id of Array.isArray(fd.open) ? fd.open : []) cand.add(String(id));
        for (const e of Array.isArray(fd.cycle) ? fd.cycle : []) if (e && e.id != null) cand.add(String(e.id));
        const refs = [...cand].map((id) => col.doc(id));
        const docs = refs.length ? await tx.getAll(...refs) : [];
        const moving = pickMovable(docs.filter((d) => d.exists).map((d) => ({ id: d.id, ...d.data() })), roomTag, want);
        const r = moveRoom(fd, t.exists ? t.data() : {}, [...new Set([...moving, ...want])], atIso, toRoom, { resetFrom: true });
        tx.set(fRef, { ...r.fromUpdate, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        tx.set(tRef, { ...r.toUpdate, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        for (const id of moving) {
          tx.update(col.doc(id), { room: `#${Number(toRoom)}`, 'tossPos.movedFromRoom': Number(fromRoom), 'tossPos.movedRoomAt': atIso });
        }
        let callsMoved = 0;
        if (r.emptied) {
          for (const c of calls.docs) {
            if (Number(c.data().roomNumber) !== Number(fromRoom)) continue;
            tx.update(c.ref, { roomNumber: Number(toRoom) });
            callsMoved++;
          }
        }
        return { emptied: r.emptied, moved: r.moved, orders: moving.length, calls: callsMoved };
      });
    },
    // 114차 2: 단체손님 표시 — {방: {id, rooms} | null}
    async setRoomGroups(storeId, changes) {
      const keys = Object.keys(changes);
      if (!keys.length) return;
      const batch = db.batch();
      for (const r of keys) batch.set(roomRef(storeId, r), { group: changes[r], updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      await batch.commit();
    },
    // 113차: 포스 품절 따라가기 — menus/{id}.posSoldOut (손으로 켠 isSoldOut과 따로). 지운 메뉴는 건너뜀
    async setMenusPosSoldOut(storeId, changes) {
      const ids = Object.keys(changes);
      if (!ids.length) return 0;
      const refs = ids.map((id) => store(storeId).collection('menus').doc(id));
      const docs = await db.getAll(...refs);
      const batch = db.batch();
      let n = 0;
      docs.forEach((d, i) => {
        if (!d.exists) return;
        batch.update(refs[i], { posSoldOut: changes[ids[i]] === true });
        n++;
      });
      if (n) await batch.commit();
      return n;
    },
    // 113차: 포스 플러그인이 보낸 알림(세트 구성품 줄이 남음 등) — _tossPlugin/{가맹점}.notes 최근 20개
    async addPluginNotes(merchantId, notes) {
      const ref = db.collection('_tossPlugin').doc(String(merchantId));
      await db.runTransaction(async (tx) => {
        const d = await tx.get(ref);
        const cur = d.exists && Array.isArray(d.data().notes) ? d.data().notes : [];
        tx.set(ref, { notes: [...cur, ...notes].slice(-20) }, { merge: true });
      });
    },
    // 102차: 운영자 '방 결제 대기' — 방마다 결제 대기 주문 수
    async listRooms(storeId) {
      const snap = await store(storeId).collection('roomStatus').get();
      return snap.docs.map((d) => ({ room: d.id, ...plain(d.data()) }));
    },
    // 결제 대기·주문 내역 비우기 (정산 표시는 안 함 — 패드는 그대로)
    async clearRoom(storeId, room) {
      const ref = roomRef(storeId, room);
      const d = await ref.get();
      const before = d.exists ? d.data() : {};
      await ref.set({ open: [], paidInCycle: false, cycle: [], posPayment: null, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { open: Array.isArray(before.open) ? before.open.map(String) : [] };
    },
    // 116차: 관리자 방 현황판 '방 비우기' — 결제 대기·주문 내역 비움 + 그 방 진행 중 주문은 완료로 + 확인 안 한 호출은 확인으로
    //   + settledAt(그 방 패드가 처음 화면·기본 언어로)
    async resetRoom(storeId, room, atIso) {
      const ref = roomRef(storeId, room);
      const [d, orders, calls] = await Promise.all([
        ref.get(),
        store(storeId).collection('orders').where('status', 'in', ['pending', 'preparing', 'ready']).get(), // 방은 아래에서 거름(색인 없이)
        store(storeId).collection('staff_calls').where('isAcknowledged', '==', false).get(),
      ]);
      const before = d.exists ? d.data() : {};
      const batch = db.batch();
      batch.set(ref, {
        open: [], cycle: [], paidInCycle: false, posPayment: null, movedTo: null, settledAt: atIso, updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      const mine = orders.docs.filter((o) => o.data().room === `#${Number(room)}`);
      for (const o of mine) batch.update(o.ref, { status: 'completed', clearedByRoomResetAt: atIso });
      let callCount = 0;
      for (const c of calls.docs) {
        if (Number(c.data().roomNumber) !== Number(room)) continue;
        batch.update(c.ref, { isAcknowledged: true });
        callCount++;
      }
      await batch.commit();
      return { open: Array.isArray(before.open) ? before.open.map(String) : [], orders: mine.length, calls: callCount };
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
// 114차: 포스 자리이동·합석 — 주문을 다른 방으로 옮김 (결제 대기 open·주문 내역 cycle·일부 결제 posPayment)
//   옮긴 뒤 원래 방에 결제 대기가 하나도 안 남으면 그 방은 비움 + settledAt(=그 방 패드가 처음 화면·기본 언어로) + movedTo
//   114차 2: ids가 null이면 방 전체(결제 대기·주문 내역 모두) — 토스처럼 자리를 옮기면 그 방 정보가 다 넘어감
//   115차 resetFrom: 원래 방에 다른 손님(다른 포스 주문)이 남아도 그 방 패드는 처음 화면으로(settledAt) — 맞교환
function moveRoom(from, to, ids, atIso, toRoom, { resetFrom = false } = {}) {
  const fOpen = Array.isArray(from.open) ? from.open.map(String) : [];
  const fCycle = Array.isArray(from.cycle) ? from.cycle : [];
  const idset = new Set(ids == null ? [...fOpen, ...fCycle.filter((e) => e && e.id != null).map((e) => String(e.id))] : ids.map(String));
  const tOpen = Array.isArray(to.open) ? to.open.map(String) : [];
  const tCycle = Array.isArray(to.cycle) ? to.cycle : [];
  const moving = fOpen.filter((id) => idset.has(id));
  const movingCycle = fCycle.filter((e) => e && idset.has(String(e.id)));
  const restOpen = fOpen.filter((id) => !idset.has(id));
  const toUpdate = {
    open: [...tOpen, ...moving.filter((id) => !tOpen.includes(id))],
    cycle: [...tCycle, ...movingCycle.filter((e) => !tCycle.some((x) => x && String(x.id) === String(e.id)))].slice(-CYCLE_MAX),
    paidInCycle: to.paidInCycle === true || (from.paidInCycle === true && moving.length > 0),
  };
  if (from.posPayment && !to.posPayment) toUpdate.posPayment = from.posPayment;
  if (ids == null && to.movedTo != null) toUpdate.movedTo = null; // 다시 손님이 들어온 방
  const emptied = restOpen.length === 0;
  const fromUpdate = emptied
    ? { open: [], cycle: [], paidInCycle: false, posPayment: null, settledAt: atIso, movedTo: toRoom == null ? null : Number(toRoom), movedAt: atIso }
    : { open: restOpen, cycle: fCycle.filter((e) => !(e && idset.has(String(e.id)))), ...(resetFrom ? { settledAt: atIso } : {}) };
  return { fromUpdate, toUpdate, emptied, moved: moving.length + movingCycle.length };
}

// 115차: 방 옮기기 때 같이 옮길 주문 — 원래 방(room '#N')에 있고, 이 포스 주문의 고도리 주문(want)이거나 포스로 안 간 주문
//   (다른 포스 주문에 들어간 주문 = 그 방에 남은/맞교환한 다른 손님 → 그대로). 포스로 안 간 주문은 진행 중인 것만
function pickMovable(orders, roomTag, want) {
  const out = [];
  for (const o of orders) {
    if (String(o.room || '') !== roomTag) continue;
    const pos = o.tossPos && o.tossPos.posOrderId;
    if (want.has(String(o.id)) || (!pos && ['pending', 'preparing', 'ready'].includes(o.status))) out.push(String(o.id));
  }
  return out;
}

function closeRoom(cur, orderId, paid, atIso) {
  const open = Array.isArray(cur.open) ? cur.open.map(String) : [];
  if (!open.includes(String(orderId))) return { settled: false, open: open.length, update: null };
  const rest = open.filter((x) => x !== String(orderId));
  const paidInCycle = cur.paidInCycle === true || paid === true;
  const settled = rest.length === 0 && paidInCycle;
  const update = { open: rest, paidInCycle: settled ? false : paidInCycle };
  if (settled) update.settledAt = atIso;
  if (settled) update.posPayment = null; // 113차: 일부 결제 표시도 지움
  if (settled) update.movedTo = null; // 114차: '…번 방으로 옮김' 표시도
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
  const plugins = new Map(); // merchantId -> 플러그인 신호 (96차)
  const rooms = new Map(); // `${store}/${room}` -> { open, paidInCycle, settledAt }
  return {
    configs, ordersMap, installs, sandbox, menus, rooms, plugins,
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
    async setSetMap(s, setMap, rev) {
      configs.set(s, { ...(configs.get(s) || {}), setMap: JSON.parse(JSON.stringify(setMap)), setMapRev: rev });
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
    async savePluginHello(mid, info) {
      const cur = plugins.get(String(mid)) || {};
      plugins.set(String(mid), { ...cur, ...JSON.parse(JSON.stringify(info)), lastSeenAt: new Date().toISOString(), count: (cur.count || 0) + 1 });
    },
    async listPluginHellos() {
      return [...plugins.entries()].map(([merchantId, v]) => ({ merchantId, ...v }));
    },
    async getPluginDevices(mid) {
      return JSON.parse(JSON.stringify((plugins.get(String(mid)) || {}).devices || {}));
    },
    async setPluginDevice(mid, serial, patch) {
      const cur = plugins.get(String(mid)) || {};
      const devices = { ...(cur.devices || {}) };
      if (patch == null) delete devices[serial];
      else devices[serial] = { ...(devices[serial] || {}), ...JSON.parse(JSON.stringify(patch)) };
      plugins.set(String(mid), { ...cur, devices });
    },
    async listPluginOrders(s) {
      return [...ordersMap.entries()]
        .filter(([k, v]) => k.startsWith(`${s}/`) && v.tossPos && ['queued', 'claimed'].includes(v.tossPos.state))
        .map(([k, v]) => ({ id: k.split('/')[1], ...JSON.parse(JSON.stringify(v)) }));
    },
    async claimPluginOrder(s, o, serial, nowMs) {
      const order = ordersMap.get(`${s}/${o}`);
      if (!order) return null;
      const t = order.tossPos || {};
      const free = t.state === 'queued' || (t.state === 'claimed' && nowMs - (Number(t.claimedAtMs) || 0) > CLAIM_TIMEOUT_MS);
      if (!free) return null;
      order.tossPos = { ...t, state: 'claimed', claimedBy: String(serial), claimedAtMs: nowMs };
      return JSON.parse(JSON.stringify(order));
    },
    async listRooms(s) {
      return [...rooms.entries()].filter(([k]) => k.startsWith(`${s}/`))
        .map(([k, v]) => ({ room: k.split('/')[1], ...JSON.parse(JSON.stringify(v)) }));
    },
    async resetRoom(s, r, atIso) {
      const k = `${s}/${r}`;
      const cur = rooms.get(k) || {};
      rooms.set(k, { ...cur, open: [], cycle: [], paidInCycle: false, posPayment: null, movedTo: null, settledAt: atIso });
      let n = 0;
      for (const [key, o] of ordersMap.entries()) {
        if (key.startsWith(`${s}/`) && o.room === `#${Number(r)}` && ['pending', 'preparing', 'ready'].includes(o.status)) {
          o.status = 'completed';
          n++;
        }
      }
      return { open: Array.isArray(cur.open) ? cur.open.map(String) : [], orders: n, calls: 0 };
    },
    async clearRoom(s, r) {
      const k = `${s}/${r}`;
      const cur = rooms.get(k) || {};
      rooms.set(k, { ...cur, open: [], paidInCycle: false, cycle: [], posPayment: null });
      return { open: Array.isArray(cur.open) ? cur.open.map(String) : [] };
    },
    async findOrdersByPosOrder(s, posOrderId) {
      return [...ordersMap.entries()]
        .filter(([k, v]) => k.startsWith(`${s}/`) && v.tossPos && String(v.tossPos.posOrderId) === String(posOrderId))
        .map(([k, v]) => ({ id: k.split('/')[1], ...JSON.parse(JSON.stringify(v)) }));
    },
    async setRoomPayment(s, r, payment) {
      const k = `${s}/${r}`;
      rooms.set(k, { ...(rooms.get(k) || { open: [] }), posPayment: payment == null ? null : { ...payment } });
    },
    async moveRoomOrders(s, fromRoom, toRoom, orderIds, atIso) {
      const fk = `${s}/${fromRoom}`;
      const tk = `${s}/${toRoom}`;
      const f = rooms.get(fk) || { open: [] };
      const t = rooms.get(tk) || { open: [] };
      const r = moveRoom(f, t, orderIds, atIso, toRoom);
      rooms.set(fk, { ...f, ...JSON.parse(JSON.stringify(r.fromUpdate)) });
      rooms.set(tk, { ...t, ...JSON.parse(JSON.stringify(r.toUpdate)) });
      for (const id of orderIds) {
        const o = ordersMap.get(`${s}/${id}`);
        if (!o) continue;
        o.room = `#${Number(toRoom)}`;
        o.tossPos = { ...(o.tossPos || {}), movedFromRoom: Number(fromRoom), movedRoomAt: atIso };
      }
      return { emptied: r.emptied, moved: r.moved };
    },
    async moveWholeRoom(s, fromRoom, toRoom, atIso, moveIds) {
      const fk = `${s}/${fromRoom}`;
      const tk = `${s}/${toRoom}`;
      const f = rooms.get(fk) || { open: [] };
      const t = rooms.get(tk) || { open: [] };
      const roomTag = `#${Number(fromRoom)}`;
      const want = new Set((moveIds || []).map(String));
      const all = [...ordersMap.entries()].filter(([k]) => k.startsWith(`${s}/`)).map(([k, o]) => ({ id: k.split('/')[1], ...o }));
      const moving = pickMovable(all, roomTag, want);
      const r = moveRoom(f, t, [...new Set([...moving, ...want])], atIso, toRoom, { resetFrom: true });
      rooms.set(fk, { ...f, ...JSON.parse(JSON.stringify(r.fromUpdate)) });
      rooms.set(tk, { ...t, ...JSON.parse(JSON.stringify(r.toUpdate)) });
      for (const id of moving) {
        const o = ordersMap.get(`${s}/${id}`);
        o.room = `#${Number(toRoom)}`;
        o.tossPos = { ...(o.tossPos || {}), movedFromRoom: Number(fromRoom), movedRoomAt: atIso };
      }
      return { emptied: r.emptied, moved: r.moved, orders: moving.length, calls: 0 };
    },
    async setRoomGroups(s, changes) {
      for (const r of Object.keys(changes)) {
        const k = `${s}/${r}`;
        rooms.set(k, { ...(rooms.get(k) || { open: [] }), group: changes[r] == null ? null : JSON.parse(JSON.stringify(changes[r])) });
      }
    },
    async setMenusPosSoldOut(s, changes) {
      let n = 0;
      for (const m of menus[s] || []) {
        if (Object.prototype.hasOwnProperty.call(changes, m.id)) {
          m.posSoldOut = changes[m.id] === true;
          n++;
        }
      }
      return n;
    },
    async addPluginNotes(mid, notes) {
      const cur = plugins.get(String(mid)) || {};
      plugins.set(String(mid), { ...cur, notes: [...(cur.notes || []), ...JSON.parse(JSON.stringify(notes))].slice(-20) });
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

module.exports = { createFirestoreTossData, createMemoryTossData, SENDING_TIMEOUT_MS, CLAIM_TIMEOUT_MS, cycleEntry, CYCLE_MAX, moveRoom };
