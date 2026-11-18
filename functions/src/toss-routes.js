'use strict';
// 토스 POS 연동 API (64차) — app.js가 /api/toss/* 와 /api/ops/toss/* 를 여기로 넘김
//
//   POST /api/toss/webhook        토스가 보내는 웹훅 (로그인 없음, 서명 확인) — 앱 설치·주문 상태
//   POST /api/toss/plugin/hello   (96차, 로그인 없음) 토스 포스 플러그인(toss-plugin/)이 켜질 때·10분마다 보내는 신호
//                                 { merchantId, merchantName, serial, version, halls[], tables[], tableError, errors[], stage, reason } → _tossPlugin/{merchantId}
//                                 가맹점 ID가 없는 신호(플러그인 0.1.1 'boot'·오류)는 저장 없이 기록만 '[토스 플러그인] boot 가맹점 없음 …'
//                                 ★지금은 누구나 보낼 수 있음(시험용 — 저장만 하고 주문·결제는 안 건드림). 주문을 넘기기 전에 매장별 키를 붙일 것
//   POST /api/toss/plugin/poll    (100차, 포스 플러그인 — 승인된 기기 열쇠) { merchantId, serial, token } → { orders[], pollMs }
//                                 이 가맹점에 연결된 매장(via 'plugin')의 대기 주문을 가져감(한 포스만 — claimed)
//   POST /api/toss/plugin/ack     (100차) { …, orderId, ok, posOrderId, tableId, tableTitle, appended, posAmount, error } 포스에 넣은 결과
//                                 113차 lineIds: 이 고도리 주문이 포스 주문에 만든 줄 ID (포스에서 그 줄만 지웠는지 알아보려고)
//   POST /api/toss/plugin/event   (100차) { …, posOrderId, orderState, paymentState, unpaid } 포스 주문이 끝남(완료·취소) → 방 정산
//                                 113차: 열린 주문도 { …, paid, unpaid, lineIds } — 일부 결제(방 posPayment)·고도리 줄을 모두 지움(그 주문 취소)
//                                 113차 kind 'move' { posOrderId, toTableId, toTableTitle } / 'merge' { fromPosOrderId, toPosOrderId, toTableId, toTableTitle }
//                                   — 포스에서 테이블을 옮기거나 합침 → 고도리 주문의 테이블·포스 주문 번호를 따라 바꿈
//                                   114차: ★방도 테이블을 따라감 — 옮긴 테이블 이름의 방 번호(기본홀03 = 3번 방, 합석은 합친 주문이 있던 방)로
//                                   결제 대기·주문 내역·주문 문서 room을 옮기고, 원래 방이 비면 그 방 패드는 처음 화면·기본 언어로(settledAt)
//   113차 poll: body.notes[] = 플러그인 알림(세트 구성품 줄이 남음 등) → _tossPlugin/{가맹점}.notes. 1분마다 포스 상품 품절을 고도리 메뉴 posSoldOut으로
//   POST /api/toss/etc-item       (113차, 관리자) { itemId | null } 포스 상품과 연결 안 된 메뉴를 받을 포스 상품('고도리 기타' 0원 권장)
//                                 → 그 줄은 이 상품으로 넣고 줄 메모에 원래 메뉴 이름·옵션·값 (포스가 상품 값으로 계산 — 직원이 금액 확인)
//   POST /api/toss/send-order     (패드·관리자) { orderId }  주문을 포스로 보내기. 패드는 주문 직후 자동, 관리자는 '다시 보내기'
//                                 100차: via 'plugin' 매장은 서버에 'queued'로 두고 포스 플러그인이 가져감
//   GET  /api/toss/status         (관리자) 연결 상태·메뉴 연결표·보내기 실패한 주문
//   GET  /api/toss/catalog        (관리자) 포스 상품 목록 (메뉴 연결 화면용)
//   POST /api/toss/menu-map       (관리자) { map: { 고도리 메뉴 ID: 토스 상품 ID | '상품ID:옵션ID=선택ID,…' (99차) | null } }
//   POST /api/toss/set-map        (103차, 관리자) { map: { 포스 세트 상품 ID: [{ entry: '상품ID[:옵션ID=선택ID,…]', qty }] } } 통째로 바꿈
//                                 → 포스 플러그인이 poll 때 받아서(setMapRev가 바뀌었을 때만) 세트가 든 포스 주문에 구성품을 0원 줄로 덧붙임
//                                   (토스가 구성품 재고를 줄이게 — 토스 API로는 재고를 직접 못 바꿈)
//   GET  /api/ops/toss/overview   (운영자) 매장별 연결 상태 + 토스 '앱 설치' 매장 목록 + 진짜 키 등록 여부
//   POST /api/ops/toss/link       (운영자) { storeId, mode: 'fake' | 'live', merchantId? }  매장 ↔ 포스 연결
//   POST /api/ops/toss/unlink     (운영자) { storeId }
//   GET  /api/ops/toss/lookup     (운영자) ?storeId=  최근 포스로 보낸 주문 5건을 토스(또는 가짜 포스)에서 주문 키로 다시 조회 (95차)
//   GET  /api/ops/toss/plugins    (운영자) 포스 플러그인 신호 목록 + 어느 매장과 연결된 가맹점인지 (96차)
//   POST /api/ops/toss/config     (운영자) { storeId, printOrderSheet?, via?: 'plugin' | 'api' } (100차 via — 실제 포스에 주문을 넣는 길)
//   POST /api/ops/toss/plugin-device (100차, 운영자) { merchantId, serial, approved: true|false } 또는 { …, remove: true }
//   GET  /api/ops/toss/rooms?storeId=   (102차, 운영자) 결제 대기 주문이 남은 방 목록
//   POST /api/ops/toss/room-clear { storeId, room }  (102차, 운영자) 그 방 결제 대기·주문 내역 비우기(정산 표시 없이 — 패드는 그대로)
//   GET  /api/ops/toss/fake-orders?storeId=   (운영자) 가짜 포스에 들어온 주문
//   POST /api/ops/toss/fake-complete  (운영자) { storeId, orderKey, id }  가짜 포스에서 '결제 완료' 흉내 (81차 — 진짜는 주문 완료 웹훅)
//
// 방 결제 끝 (81차): 포스로 보낸 주문을 stores/{매장}/roomStatus/{방}.open 에 넣고, 완료·취소 웹훅이 오면 뺌.
//   목록이 비고 그사이 완료(COMPLETED)가 있었으면 settledAt → 그 방 패드가 로그인 때 고른 언어로 돌아감.
//   (방 이용료는 카운터 포스에서 따로 받아서 모름 — '패드로 시킨 주문이 다 결제됐는지' 기준)
//
// 보내기 조건: 매장 features.tossPos(59차, 운영자가 켬) + private/tossPos 연결(가짜 또는 진짜) + 주문에 lines(64차 패드)
// 가짜 연결(mode 'fake'): merchantId 'fake-<매장>', 상품은 그 매장 고도리 메뉴로 만든 가짜 포스 상품 (src/toss.js)

const {
  TossError, createFakeToss, fakeCatalogFromMenus, buildTossOrder, parseOrderKey, orderKeyOf, verifyWebhook, catalogView, parseMapEntry,
  pluginLineItems, cleanSetMap, setMapForPlugin, posSoldOutScan, posSoldOutOptionKeys,
} = require('./toss');
const { cycleEntry, CLAIM_TIMEOUT_MS } = require('./toss-data');
const crypto = require('crypto');

const PLUGIN_POLL_MS = 3000; // 100차: 포스 플러그인이 주문을 물어보는 간격 (폴링 — 웹소켓은 커지면 바꿀 것 23번)
const PLUGIN_IDLE_MS = 30000; // 플러그인으로 보내지 않는 매장·승인 전 기기
const HELLO_UNLINKED_MAX = 60; // 120차: 연결 안 된 가맹점 hello — 전체 10분 60번
const MAX_PENDING_DEVICES = 5; // 120차: 가맹점당 승인 전 기기 최대 수
const MAX_DEVICES = 20; // 120차: 가맹점당 기기 최대 수(승인된 것 포함)
const tooManyDevices = (devices) => {
  const list = Object.values(devices || {});
  return list.length >= MAX_DEVICES || list.filter((d) => !d || d.approved !== true).length >= MAX_PENDING_DEVICES;
};
const SOLD_OUT_SYNC_MS = 60 * 1000; // 113차: 포스 품절 → 고도리 메뉴 posSoldOut 확인 간격
const sha = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

const FAKE_PREFIX = 'fake-';
const CATALOG_CACHE_MS = 60 * 1000;
const ORDER_EVENTS = {
  'order.order.accepted.v1': 'ACCEPTED',
  'order.order.declined.v1': 'DECLINED',
  'order.order.expired.v1': 'EXPIRED',
  'order.order.opened.v1': 'OPENED',
  'order.order.completed.v1': 'COMPLETED',
  'order.order.cancelled.v1': 'CANCELLED',
};

// 주문이 끝난 상태 — 방 결제 대기 목록에서 뺌 (COMPLETED만 '결제 완료'로 셈)
const TERMINAL = new Set(['COMPLETED', 'CANCELLED', 'DECLINED', 'EXPIRED']);
// 114차: 포스 테이블 이름 → 방 번호 (플러그인 pickTable의 반대: 'N번방'·'방N'·'N번'·'roomN'·'N' → 없으면 이름 끝 숫자). 카운터 등은 null
function roomFromTableTitle(title) {
  const s = String(title || '').replace(/\s+/g, '').toLowerCase();
  const m = /^(?:(\d{1,3})번방?|방(\d{1,3})|room(\d{1,3})|(\d{1,3}))$/.exec(s);
  if (m) return Number(m[1] || m[2] || m[3] || m[4]) || null;
  const end = /(\d{1,3})$/.exec(s);
  return end ? Number(end[1]) || null : null;
}
const roomOf = (order) => {
  const m = /^#(\d{1,3})$/.exec(String((order && order.room) || ''));
  return m ? Number(m[1]) : null;
};

// data: src/toss-data.js   live: 진짜 토스 클라이언트(키 없으면 null)   webhookSecret: 웹훅 비밀값(없으면 웹훅 503)
function createTossRoutes({ data, stores, live = null, webhookSecret = '', now = () => Date.now(), httpError }) {
  const fake = createFakeToss({
    now,
    sandbox: {
      merchant: async (mid) => ({ id: mid, name: '가짜 포스(개발용)' }),
      catalog: async (mid) => fakeCatalogFromMenus(await data.listMenus(String(mid).slice(FAKE_PREFIX.length))),
      addOrder: (mid, order) => data.addFakeOrder(mid, order),
    },
  });

  function clientFor(cfg) {
    if (cfg.mode === 'fake') return fake;
    if (!live) throw httpError(503, 'TOSS_NO_KEYS', '토스 키가 아직 서버에 등록되지 않았어요. (운영자: 토스 비밀값 등록 후 배포)');
    return live;
  }

  // 포스 상품 목록 — 같은 가맹점이면 1분 기억 (주문마다 토스를 부르지 않게). 가짜는 메뉴가 바로 반영되게 기억 안 함
  const catalogCache = new Map();
  async function catalogOf(cfg, { fresh = false } = {}) {
    const key = `${cfg.mode}:${cfg.merchantId}`;
    const hit = catalogCache.get(key);
    if (!fresh && cfg.mode !== 'fake' && hit && now() - hit.at < CATALOG_CACHE_MS) return hit.items;
    const items = await clientFor(cfg).listCatalogItems(cfg.merchantId);
    catalogCache.set(key, { items, at: now() });
    return items;
  }

  const tossFail = (e) => {
    if (e instanceof TossError) return httpError(e.status === 429 ? 429 : 502, e.code, `토스: ${e.message}`);
    return e;
  };

  async function linkedConfig(storeId) {
    const account = await stores.getAccount(storeId);
    if (!account || !account.features || account.features.tossPos !== true) {
      throw httpError(409, 'TOSS_OFF', '이 매장은 토스 POS 연동을 쓰지 않아요. (운영자 페이지에서 켜야 해요)');
    }
    const cfg = await data.getConfig(storeId);
    if (!cfg || !cfg.merchantId) throw httpError(409, 'TOSS_NOT_LINKED', '아직 포스와 연결되지 않았어요. 운영자에게 연결을 요청해 주세요.');
    return cfg;
  }

  // 81차: 포스로 들어간 주문을 그 방 결제 대기 목록에 (실패해도 주문 보내기는 성공으로)
  // 84차: 손님 패드 '주문 내역'용 요약도 같이 (roomStatus.cycle)
  async function trackOpen(storeId, order, orderId) {
    const room = roomOf(order);
    if (room == null) return;
    try {
      await data.openRoomOrder(storeId, room, orderId, cycleEntry(orderId, order, new Date(now()).toISOString()));
    } catch (e) {
      console.error('[토스] 방 결제 목록', storeId, orderId, e);
    }
  }

  // 포스 주문 상태 반영 (웹훅·가짜 포스 '결제 완료') → 끝난 상태면 방 목록에서 빼고 정산 여부 돌려줌
  async function applyOrderEvent(storeId, orderId, order, state, atIso, reason = '') {
    await data.setOrderToss(storeId, orderId, { posState: state, posStateAt: atIso, ...(reason ? { posReason: reason } : {}) });
    const room = roomOf(order);
    if (!TERMINAL.has(state) || room == null) return { settled: false, open: null };
    const r = await data.closeRoomOrder(storeId, room, orderId, { paid: state === 'COMPLETED', atIso });
    // 125차: 방 결제가 다 끝나면(정산) 그 방에서 아직 서빙 완료를 안 누른 음식 주문도 '완료'로
    //   (보드게임 카페는 나갈 때 결제 — 사용자 결정. 먼저 결제하고 나중에 받는 주문도 주문현황에서 빠짐)
    if (r && r.settled === true) {
      try {
        const n = await data.completeRoomOrders(storeId, room, atIso);
        if (n) console.log(`[토스] ${storeId} ${room}번 방 정산 — 서빙 안 한 주문 ${n}건 완료로`);
      } catch (e) {
        console.error('[토스] 정산 뒤 주문 완료 실패', storeId, room, e);
      }
    }
    return r;
  }

  // ── 주문 보내기 ──
  async function sendOrder(user, orderId) {
    const cfg = await linkedConfig(user.store);
    if (cfg.mode === 'live' && cfg.via === 'plugin') return queueForPlugin(user, orderId);
    const claim = await data.claimOrder(user.store, orderId, now());
    if (!claim.order) throw httpError(404, 'NO_ORDER', '없는 주문이에요.');
    if (user.pad === true && claim.order.room !== `#${Number(user.room)}`) {
      throw httpError(403, 'FORBIDDEN', '이 방의 주문이 아니에요.');
    }
    if (!claim.ok) {
      const t = claim.order.tossPos || {};
      return { ok: t.state === 'sent', already: true, tossPos: t };
    }
    const nowIso = new Date(now()).toISOString();
    try {
      const catalog = await catalogOf(cfg);
      const { body, warnings } = buildTossOrder({
        storeId: user.store,
        orderId,
        order: claim.order,
        menuMap: cfg.menuMap || {},
        catalogById: new Map(catalog.map((i) => [String(i.id), i])),
        nowIso,
      });
      const created = await clientFor(cfg).createOrder(cfg.merchantId, body, { printOrderSheet: cfg.printOrderSheet === true });
      const patch = {
        state: 'sent', mode: cfg.mode, posOrderId: String((created && created.id) || ''), sentAt: nowIso,
        warnings, code: undefined, error: undefined, failedAt: undefined,
      };
      await data.setOrderToss(user.store, orderId, patch, { countAttempt: true });
      await trackOpen(user.store, claim.order, orderId);
      return { ok: true, tossPos: patch };
    } catch (e) {
      const known = e instanceof TossError || (e && e.status && e.code);
      if (!known) console.error('[토스] 보내기 오류', user.store, orderId, e);
      // 같은 orderKey = 이미 포스에 들어간 주문 (예: 응답을 못 받은 채 다시 보냄) → 보낸 것으로 봄
      if (e && e.code === 'DUPLICATED_ORDER_KEY') {
        const patch = { state: 'sent', mode: cfg.mode, sentAt: nowIso, warnings: ['포스에 이미 들어가 있던 주문이에요.'] };
        await data.setOrderToss(user.store, orderId, patch, { countAttempt: true });
        await trackOpen(user.store, claim.order, orderId);
        return { ok: true, tossPos: patch };
      }
      const patch = {
        state: 'failed', mode: cfg.mode, failedAt: nowIso,
        code: String((e && e.code) || 'ERROR'),
        error: known ? String(e.message) : '포스로 보내지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      await data.setOrderToss(user.store, orderId, patch, { countAttempt: true });
      return { ok: false, tossPos: patch };
    }
  }

  // 100차: 포스 플러그인으로 보내는 매장 — 서버에 'queued'로 두면 포스 플러그인이 가져가서 방에 연결된 테이블에 넣음
  async function queueForPlugin(user, orderId) {
    const order = await data.getOrder(user.store, orderId);
    if (!order) throw httpError(404, 'NO_ORDER', '없는 주문이에요.');
    if (user.pad === true && order.room !== `#${Number(user.room)}`) throw httpError(403, 'FORBIDDEN', '이 방의 주문이 아니에요.');
    const t = order.tossPos || {};
    if (['sent', 'queued', 'claimed'].includes(t.state)) return { ok: true, already: true, tossPos: t };
    const nowIso = new Date(now()).toISOString();
    if (!Array.isArray(order.lines) || !order.lines.length) {
      const patch = { state: 'failed', mode: 'plugin', failedAt: nowIso, code: 'NO_LINES', error: '예전 패드에서 들어온 주문이라 포스로 보낼 수 없어요. 포스에 직접 입력해 주세요.' };
      await data.setOrderToss(user.store, orderId, patch, { countAttempt: true });
      return { ok: false, tossPos: patch };
    }
    const patch = {
      state: 'queued', mode: 'plugin', queuedAt: nowIso,
      code: undefined, error: undefined, failedAt: undefined, claimedBy: undefined, claimedAtMs: undefined,
    };
    await data.setOrderToss(user.store, orderId, patch);
    return { ok: true, queued: true, tossPos: patch };
  }

  // ── 포스 플러그인 (100차) ──
  // 기기 = 가맹점 + 포스 시리얼. 처음 신호(hello) 때 서버가 열쇠(token)를 주고, 운영자가 승인해야 주문을 받음.
  // (플러그인 코드는 공개 저장소라 코드 안에 비밀값을 둘 수 없음 → 기기마다 받은 열쇠 + 운영자 승인)
  const authCache = new Map(); // `${merchantId}:${serial}:${sha(token)}` → { approved, at }
  async function pluginDevice(body) {
    const merchantId = String(body.merchantId == null ? '' : body.merchantId);
    const serial = cleanText(body.serial, 40);
    if (!/^\d{1,19}$/.test(merchantId) || !serial) throw httpError(400, 'INVALID_PLUGIN', '가맹점·포스 기기 정보가 없어요.');
    const token = String(body.token || '').slice(0, 100);
    const dev = (await data.getPluginDevices(merchantId))[serial] || null;
    const ok = !!(dev && token && dev.tokenHash === sha(token));
    return { merchantId, serial, dev, ok, approved: ok && dev.approved === true };
  }
  async function pluginAuth(body) {
    const key = `${body.merchantId}:${body.serial}:${sha(body.token || '')}`;
    const hit = authCache.get(key);
    let auth;
    if (hit && now() - hit.at < 30 * 1000) {
      auth = hit.auth;
    } else {
      auth = await pluginDevice(body);
      authCache.set(key, { auth, at: now() });
    }
    if (!auth.approved) throw httpError(403, 'PLUGIN_NOT_APPROVED', '운영자 승인 전인 포스 기기예요.');
    return auth;
  }
  const linkCache = new Map(); // merchantId → { v: { storeId, cfg } | null, at }
  async function pluginStore(merchantId, { fresh = false } = {}) {
    const hit = linkCache.get(merchantId);
    if (!fresh && hit && now() - hit.at < 30 * 1000) return hit.v;
    let v = null;
    for (const s of await stores.listStores()) {
      const cfg = await data.getConfig(s.id);
      if (cfg && cfg.mode === 'live' && String(cfg.merchantId) === merchantId) {
        v = { storeId: s.id, cfg };
        break;
      }
    }
    linkCache.set(merchantId, { v, at: now() });
    return v;
  }

  // 103차: 세트 구성표 — 플러그인이 가진 번호(setMapRev)와 다를 때만 보냄
  function setsFor(cfg, body) {
    const rev = Number(cfg.setMapRev) || 0;
    if (Number(body.setMapRev) === rev) return {};
    return { setMapRev: rev, sets: setMapForPlugin(cfg.setMap || {}) };
  }

  // 113차: 연결 안 된 메뉴 줄(AD_HOC) → '고도리 기타' 포스 상품 줄 (값 0 — 포스는 상품 값으로 계산, 메모에 원래 값)
  function etcLine(li, etc, warnings) {
    if (li.targetType === 'ITEM') return li;
    const opts = li.optionChoices || [];
    const unit = Math.max(0, Number(li.itemPrice && li.itemPrice.priceValue) || 0) + opts.reduce((s, c) => s + Math.max(0, Number(c.price) || 0), 0);
    const name = String((li.item && li.item.title) || '');
    const optText = opts.map((c) => `${c.title}${Number(c.price) ? `+${Number(c.price)}` : ''}`).join(', ');
    warnings.push(`'${name}'은(는) 포스 상품과 연결되지 않아 '${etc.title}'(으)로 넣었어요 — 포스에서 금액(${unit * li.quantity}원)을 확인해 주세요.`);
    return {
      diningOption: 'HERE', targetType: 'ITEM', targetId: String(etc.id),
      itemPrice: { ...(li.itemPrice || {}), title: String(etc.title || ''), priceValue: 0 },
      quantity: li.quantity, optionChoices: [],
      memo: `${name}${optText ? ` (${optText})` : ''} ${unit}원`,
    };
  }

  // 113차: 포스 플러그인 알림 저장
  async function saveNotes(merchantId, raw) {
    const notes = (Array.isArray(raw) ? raw : []).slice(0, 10).map((n) => cleanText(n, 200)).filter(Boolean);
    if (!notes.length) return;
    const at = new Date(now()).toISOString();
    await data.addPluginNotes(merchantId, notes.map((text) => ({ at, text })));
    console.log(`[토스 플러그인] 가맹점 ${merchantId} 알림: ${notes.join(' | ')}`);
  }

  // 113차: 포스 품절 → 고도리 메뉴 posSoldOut (메뉴 연결된 포스 상품 기준, 1분마다, 바뀐 메뉴만 씀)
  //   토스는 품절을 바꾸는 API가 없어서 반대 방향(고도리 → 포스)은 못 함
  const soldOutSyncAt = new Map(); // storeId → ms
  async function syncPosSoldOut(storeId, cfg) {
    const t = now();
    if (t - (soldOutSyncAt.get(storeId) || 0) < SOLD_OUT_SYNC_MS) return;
    soldOutSyncAt.set(storeId, t);
    try {
      const catalog = await catalogOf(cfg);
      // 120차: 골라 둔 필수 선택(예: 에이드 › 자몽)이 품절이어도 그 메뉴 품절 + 옵션 선택지 품절은 menus/{id}.posSoldOutOptions
      const scan = posSoldOutScan(cfg.menuMap, catalog);
      const next = scan.menus;
      const before = (Array.isArray(cfg.posSoldOutMenus) ? cfg.posSoldOutMenus.map(String) : []).sort();
      if (before.join(',') !== next.join(',')) {
        const changes = {};
        for (const id of next) if (!before.includes(id)) changes[id] = true;
        for (const id of before) if (!next.includes(id)) changes[id] = false;
        await data.setMenusPosSoldOut(storeId, changes);
        await data.patchConfig(storeId, { posSoldOutMenus: next });
        cfg.posSoldOutMenus = next;
        console.log(`[토스] 포스 품절 → 고도리 ${storeId}: 품절 ${next.length}개 (바뀐 메뉴 ${Object.keys(changes).length}개)`);
      }
      // 선택지 품절: 바뀐 메뉴만 고도리 메뉴 옵션 이름으로 다시 계산 (바뀐 게 있을 때만 메뉴를 읽음)
      const sigOf = (list) => new Map((list || []).map((s) => [String(s).split(':')[0], String(s)]));
      const prev = sigOf(Array.isArray(cfg.posSoldOutChoices) ? cfg.posSoldOutChoices : []);
      const cur = sigOf(scan.choiceSig);
      const changedIds = [...new Set([...prev.keys(), ...cur.keys()])].filter((id) => prev.get(id) !== cur.get(id));
      if (changedIds.length) {
        const byId = new Map(catalog.map((i) => [String(i.id), i]));
        const menus = new Map((await data.listMenus(storeId)).map((m) => [String(m.id), m]));
        const optChanges = {};
        for (const id of changedIds) {
          const menu = menus.get(id);
          if (!menu) continue;
          const e = parseMapEntry((cfg.menuMap || {})[id]);
          optChanges[id] = cur.has(id) && e ? posSoldOutOptionKeys(menu, cfg.menuMap[id], byId.get(e.itemId)) : [];
        }
        await data.setMenusPosSoldOutOptions(storeId, optChanges);
        await data.patchConfig(storeId, { posSoldOutChoices: scan.choiceSig });
        cfg.posSoldOutChoices = scan.choiceSig;
        console.log(`[토스] 포스 선택지 품절 → 고도리 ${storeId}: 바뀐 메뉴 ${Object.keys(optChanges).length}개`);
      }
    } catch (e) {
      console.error('[토스] 포스 품절 확인 실패', storeId, e && e.message ? e.message : e);
    }
  }

  async function pluginPoll(body, ctx) {
    const auth = await pluginAuth(body);
    ctx.rate(`toss-plugin-poll:${auth.merchantId}:${auth.serial}`, 60, 60 * 1000, '포스 플러그인 주문 확인');
    await saveNotes(auth.merchantId, body.notes);
    const link = await pluginStore(auth.merchantId);
    if (!link) return { orders: [], pollMs: PLUGIN_IDLE_MS, idle: true };
    if (link.cfg.via !== 'plugin') return { orders: [], pollMs: PLUGIN_IDLE_MS, idle: true, ...setsFor(link.cfg, body) };
    const { storeId, cfg } = link;
    await syncPosSoldOut(storeId, cfg);
    const nowMs = now();
    const nowIso = new Date(nowMs).toISOString();
    const waiting = (await data.listPluginOrders(storeId))
      .filter((o) => {
        const t = o.tossPos || {};
        return t.state === 'queued' || nowMs - (Number(t.claimedAtMs) || 0) > CLAIM_TIMEOUT_MS;
      })
      .sort((a, b) => String((a.tossPos || {}).queuedAt || '').localeCompare(String((b.tossPos || {}).queuedAt || '')))
      .slice(0, 5);
    const out = [];
    let catalogById = null;
    for (const o of waiting) {
      const order = await data.claimPluginOrder(storeId, o.id, auth.serial, nowMs);
      if (!order) continue;
      try {
        if (!catalogById) catalogById = new Map((await catalogOf(cfg)).map((i) => [String(i.id), i]));
        const { body: built, warnings } = buildTossOrder({ storeId, orderId: o.id, order, menuMap: cfg.menuMap || {}, catalogById, nowIso });
        // 113차: 연결 안 된 메뉴 → 관리자가 정한 '고도리 기타' 포스 상품 줄 + 메모(원래 이름·옵션·값). 포스는 그 상품 값으로 계산
        const etc = cfg.etcItemId ? catalogById.get(String(cfg.etcItemId)) : null;
        const lines = etc ? built.order.lineItems.map((li) => etcLine(li, etc, warnings)) : built.order.lineItems;
        // 포스 플러그인은 포스 상품 ID 없는 줄(연결 안 된 메뉴·옵션 이름이 달라 이름만 보내는 줄)을 받지 않음 (SDK가 item.id 숫자를 요구)
        const unmapped = lines.filter((li) => li.targetType !== 'ITEM').map((li) => (li.item && li.item.title) || '?');
        if (unmapped.length) {
          throw new TossError(400, 'NOT_MAPPED', `포스 상품과 연결되지 않은 메뉴가 있어요: ${unmapped.join(', ')}`
            + `${warnings.length ? ` (${warnings.join(' / ')})` : ''} — 관리자 웹 토스 POS 설정 '메뉴 연결'에서 연결한 뒤 다시 보내 주세요.`
            + `${cfg.etcItemId && !etc ? ' (연결 안 된 메뉴를 받을 포스 상품이 포스에 없어요)' : ''}`);
        }
        out.push({
          orderId: o.id, orderKey: built.order.orderKey, room: roomOf(order), memo: built.order.memo,
          price: built.order.chargePrice ? built.order.chargePrice.totalAmount : null,
          lineItems: pluginLineItems(lines, catalogById), warnings,
        });
      } catch (e) {
        const known = e instanceof TossError || (e && e.status && e.code);
        if (!known) console.error('[토스 플러그인] 주문 만들기 오류', storeId, o.id, e);
        await data.setOrderToss(storeId, o.id, {
          state: 'failed', mode: 'plugin', failedAt: nowIso, code: String((e && e.code) || 'ERROR'),
          error: known ? String(e.message) : '포스로 보낼 주문을 만들지 못했어요.', claimedBy: undefined, claimedAtMs: undefined,
        }, { countAttempt: true });
      }
    }
    return { orders: out, pollMs: PLUGIN_POLL_MS, ...setsFor(cfg, body) };
  }

  async function pluginAck(body, ctx) {
    const auth = await pluginAuth(body);
    ctx.rate(`toss-plugin-ack:${auth.merchantId}`, 120, 60 * 1000, '포스 플러그인 결과');
    const link = await pluginStore(auth.merchantId);
    if (!link) throw httpError(409, 'TOSS_NOT_LINKED', '이 가맹점과 연결된 매장이 없어요.');
    const orderId = String(body.orderId || '');
    if (!/^[A-Za-z0-9]{1,40}$/.test(orderId)) throw httpError(400, 'INVALID_ORDER', '주문 ID가 올바르지 않아요.');
    const order = await data.getOrder(link.storeId, orderId);
    if (!order) throw httpError(404, 'NO_ORDER', '없는 주문이에요.');
    const t = order.tossPos || {};
    if (t.state === 'sent') return { ok: true, already: true };
    if (t.state !== 'claimed' || t.claimedBy !== auth.serial) throw httpError(409, 'NOT_YOURS', '이 포스가 가져간 주문이 아니에요.');
    const nowIso = new Date(now()).toISOString();
    const warnings = (Array.isArray(body.warnings) ? body.warnings : []).slice(0, 10).map((w) => cleanText(w, 200)).filter(Boolean);
    if (body.ok === true) {
      const posOrderId = cleanText(body.posOrderId, 40);
      if (!posOrderId) throw httpError(400, 'NO_POS_ORDER', '포스 주문 ID가 없어요.');
      // 113차: 이 주문이 만든 포스 줄 ID (포스에서 그 줄을 지웠는지 알아보려고)
      const lineIds = (Array.isArray(body.lineIds) ? body.lineIds : []).slice(0, 100).map((x) => cleanText(x, 60)).filter(Boolean);
      const patch = {
        state: 'sent', mode: 'plugin', posOrderId, sentAt: nowIso, tableId: cleanNum(body.tableId), tableTitle: cleanText(body.tableTitle, 40),
        appended: body.appended === true, warnings, claimedAtMs: undefined, ...(lineIds.length ? { lineIds } : {}),
      };
      await data.setOrderToss(link.storeId, orderId, patch, { countAttempt: true });
      await trackOpen(link.storeId, order, orderId);
      console.log(`[토스 플러그인] 주문 ${link.storeId}/${orderId} ${order.room || ''} → 포스 주문 ${posOrderId} 테이블 ${patch.tableTitle || '-'}`
        + `${patch.appended ? ' (열린 주문에 덧붙임)' : ''} · 고도리 ${order.price || '?'}원 / 포스 ${cleanNum(body.posAmount) == null ? '?' : cleanNum(body.posAmount)}원`
        + `${warnings.length ? ` · ${warnings.join(' | ')}` : ''}`);
      return { ok: true };
    }
    const patch = {
      state: 'failed', mode: 'plugin', failedAt: nowIso, code: cleanText(body.code, 40) || 'PLUGIN_FAILED',
      error: cleanText(body.error, 200) || '포스에 주문을 넣지 못했어요.', warnings, claimedBy: undefined, claimedAtMs: undefined,
    };
    await data.setOrderToss(link.storeId, orderId, patch, { countAttempt: true });
    console.log(`[토스 플러그인] 주문 ${link.storeId}/${orderId} 실패: ${patch.code} ${patch.error}`);
    return { ok: true };
  }

  // 포스 주문이 끝나면(완료·취소) 그 포스 주문에 들어간 고도리 주문을 모두 정리 → 방 정산
  async function pluginEvent(body, ctx) {
    const auth = await pluginAuth(body);
    ctx.rate(`toss-plugin-event:${auth.merchantId}`, 120, 60 * 1000, '포스 플러그인 신호');
    const link = await pluginStore(auth.merchantId);
    if (!link) return { ok: true, matched: 0 };
    const nowIso = new Date(now()).toISOString();
    const kind = cleanText(body.kind, 10) || 'state';
    if (kind === 'move' || kind === 'merge') return pluginMoveEvent(link.storeId, kind, body, nowIso);
    if (kind === 'bills') return syncRoomBills(link.storeId, link.cfg, body.bills, nowIso); // 117차
    const posOrderId = cleanText(body.posOrderId, 40);
    if (!posOrderId) throw httpError(400, 'NO_POS_ORDER', '포스 주문 ID가 없어요.');
    const orderState = cleanText(body.orderState, 20);
    const unpaid = Math.max(0, Number(body.unpaid) || 0);
    const paid = Math.max(0, Number(body.paid) || 0);
    // 113차: 아직 열린 포스 주문 — 일부 결제(나눠 내기)·고도리 줄만 지움
    if (orderState === 'OPENED' || orderState === 'REQUESTED') {
      const list = await data.findOrdersByPosOrder(link.storeId, posOrderId);
      if (!list.length) return { ok: true, matched: 0 };
      const present = Array.isArray(body.lineIds) ? new Set(body.lineIds.map((x) => String(x))) : null;
      let cancelled = 0;
      let partial = 0;
      // 115차: 줄이 '지워졌는지'는 포스 주문 줄 수가 줄었을 때만 봄 — 합석하면 포스가 줄 ID를 새로 만들어서
      //   예전 줄 ID가 다 안 보여도 줄 수는 늘어남(→ 취소로 잘못 보던 것: 합석하면 금액이 꼬임). 그때는 줄 추적만 그만둠
      const live = list.filter((o) => !TERMINAL.has((o.tossPos || {}).posState));
      const known = new Set(live.flatMap((o) => (Array.isArray((o.tossPos || {}).lineIds) ? o.tossPos.lineIds.map(String) : [])));
      const counts = live.map((o) => (o.tossPos || {}).posLineCount).filter((n) => Number.isInteger(n));
      const prevCount = counts.length ? Math.max(...counts) : known.size;
      const shrank = present != null && present.size < prevCount;
      for (const o of live) {
        const t = o.tossPos || {};
        if (!present) continue;
        const patch = {};
        if (t.posLineCount !== present.size) patch.posLineCount = present.size;
        if (Array.isArray(t.lineIds) && t.lineIds.length) {
          const left = t.lineIds.filter((id) => present.has(String(id)));
          if (left.length < t.lineIds.length && !shrank) {
            patch.lineIds = undefined;
            patch.linesLeft = undefined;
          } else if (!left.length) {
            await applyOrderEvent(link.storeId, o.id, o, 'CANCELLED', nowIso, LINES_GONE);
            cancelled++;
            continue;
          } else if (left.length < t.lineIds.length && t.linesLeft !== left.length) {
            patch.linesLeft = left.length;
            partial++;
          }
        }
        if (Object.keys(patch).length) await data.setOrderToss(link.storeId, o.id, patch);
      }
      // 일부 결제: 결제된 돈이 있고 남은 돈도 있으면 그 방에 표시 (다 내면 COMPLETED로 와서 정산 때 지움)
      let rooms = 0;
      if (paid > 0 && unpaid > 0) {
        for (const r of [...new Set(list.map((o) => roomOf(o)).filter((x) => x != null))]) {
          await data.setRoomPayment(link.storeId, r, { paid, unpaid, posOrderId, at: nowIso });
          rooms++;
        }
      }
      if (cancelled || partial || rooms) {
        console.log(`[토스 플러그인] 포스 주문 ${posOrderId} 열림 — 고도리 주문 취소 ${cancelled} · 일부 줄 지움 ${partial}`
          + `${rooms ? ` · 일부 결제 ${paid}원(남은 ${unpaid}원)` : ''}`);
      }
      return { ok: true, matched: list.length, cancelled, partial, partialPaid: rooms > 0 };
    }
    // 완료인데 남은 금액이 있으면(결제 없이 테이블만 비움 등) 결제로 보지 않음
    const state = orderState === 'CANCELLED' ? 'CANCELLED' : orderState === 'COMPLETED' ? (unpaid > 0 ? 'CANCELLED' : 'COMPLETED') : null;
    if (!state) return { ok: true, matched: 0 };
    const list = await data.findOrdersByPosOrder(link.storeId, posOrderId);
    let settled = false;
    for (const o of list) {
      const t = o.tossPos || {};
      if (t.posState === state) continue;
      if (t.posState === 'CANCELLED' && t.posReason) continue; // 113차: 포스에서 줄을 지워 이미 취소한 주문
      const r = await applyOrderEvent(link.storeId, o.id, o, state, nowIso);
      settled = settled || r.settled === true;
    }
    console.log(`[토스 플러그인] 포스 주문 ${posOrderId} ${orderState}(남은 ${unpaid}원) → 고도리 주문 ${list.length}건 ${state}${settled ? ' · 방 정산' : ''}`);
    return { ok: true, matched: list.length, settled };
  }

  // 113차: 포스에서 테이블 옮기기·합치기 — 고도리 주문의 테이블(·합치면 포스 주문 번호)을 따라 바꿈. 방 번호·정산은 그대로
  //   합치면 줄 ID가 바뀔 수 있어서 줄 추적(lineIds)은 그만둠
  const LINES_GONE = '포스에서 이 주문 줄을 모두 지웠어요.';
  async function pluginMoveEvent(storeId, kind, body, nowIso) {
    const from = cleanText(kind === 'merge' ? body.fromPosOrderId : body.posOrderId, 40);
    const to = cleanText(body.toPosOrderId, 40);
    if (!from || (kind === 'merge' && !to)) throw httpError(400, 'NO_POS_ORDER', '포스 주문 ID가 없어요.');
    const list = await data.findOrdersByPosOrder(storeId, from);
    const table = { tableId: cleanNum(body.toTableId), tableTitle: cleanText(body.toTableTitle, 40) };
    // 118차: 합석하면 포스가 원래 주문에 '취소'를 먼저 보낼 때가 있음(합석 신호보다 먼저 와서 취소로 처리됨 → 합친 방 금액이 모자람)
    //   → 합치기 신호가 오면 10분 안에 포스 취소로 처리된 그 주문들을 되살림(줄 지움으로 취소된 것은 그대로)
    let revived = 0;
    if (kind === 'merge') {
      for (const o of list) {
        const t = o.tossPos || {};
        const at = Date.parse(t.posStateAt || '');
        if (t.posState !== 'CANCELLED' || t.posReason === LINES_GONE || !(now() - at < 10 * 60 * 1000)) continue;
        await data.setOrderToss(storeId, o.id, { posState: 'OPENED', posStateAt: nowIso, posReason: undefined, revivedAt: nowIso });
        o.tossPos = { ...t, posState: 'OPENED', posReason: undefined };
        const room = roomOf(o);
        if (room != null) await data.openRoomOrder(storeId, room, o.id, cycleEntry(o.id, o, nowIso), { revive: true });
        revived++;
      }
    }
    // 114차: 옮겨 갈 방 — 합석이면 합친 포스 주문에 이미 있는 고도리 주문의 방, 없으면(또는 자리이동) 테이블 이름의 방 번호
    let toRoom = null;
    if (kind === 'merge') {
      const there = (await data.findOrdersByPosOrder(storeId, to)).map((o) => roomOf(o)).filter((r) => r != null);
      if (there.length) toRoom = there[0];
    }
    if (toRoom == null) toRoom = roomFromTableTitle(table.tableTitle);
    for (const o of list) {
      await data.setOrderToss(storeId, o.id, kind === 'merge'
        ? { ...table, posOrderId: to, mergedFrom: from, mergedAt: nowIso, lineIds: undefined, linesLeft: undefined, posLineCount: undefined }
        : { ...table, movedAt: nowIso });
    }
    // 114차 2: 토스처럼 — 옮긴 테이블의 방 정보를 새 방으로(결제 대기·주문 내역·그 방 주문, 방이 비면 확인 안 한 호출도)
    // 115차: 옮기는 건 이 포스 주문의 고도리 주문 + 포스로 안 간 그 방 주문만 — 다른 포스 주문(맞교환한 손님)은 그대로
    const fromRooms = new Set();
    for (const o of list) {
      const r = roomOf(o);
      if (r == null || toRoom == null || r === toRoom) continue;
      fromRooms.add(r);
    }
    const movedRooms = [];
    for (const fromRoom of fromRooms) {
      const r = await data.moveWholeRoom(storeId, fromRoom, toRoom, nowIso, list.map((o) => o.id));
      movedRooms.push({ from: fromRoom, orders: r.orders, calls: r.calls, emptied: r.emptied });
    }
    console.log(`[토스 플러그인] 포스 ${kind === 'merge' ? `주문 합치기${body.guessed === true ? '(추정 — 합석 신호 없이)' : ''} ${from} → ${to}` : `테이블 옮기기 ${from}`}`
      + ` → ${table.tableTitle || table.tableId || '?'}${toRoom != null ? `(${toRoom}번 방)` : ''} · 고도리 주문 ${list.length}건`
      + `${revived ? ` · 취소로 처리됐던 ${revived}건 되살림` : ''}`
      + `${movedRooms.length ? ` · 방 옮김 ${movedRooms.map((m) => `${m.from}→${toRoom}(주문 ${m.orders}건${m.calls ? `·호출 ${m.calls}건` : ''}${m.emptied ? '' : ' · 원래 방에 다른 손님 남음'})`).join(', ')}` : ''}`);
    return { ok: true, matched: list.length, toRoom, movedRooms, revived };
  }

  // ── 웹훅 ──
  async function webhook(req) {
    if (!webhookSecret) throw httpError(503, 'TOSS_NO_WEBHOOK_SECRET', '웹훅 비밀값이 아직 등록되지 않았어요.');
    if (!verifyWebhook({ secret: webhookSecret, headers: req.headers, rawBody: req.rawBody, now: now() })) {
      throw httpError(401, 'BAD_SIGNATURE', '서명이 맞지 않아요.');
    }
    const ev = req.body && typeof req.body === 'object' ? req.body : {};
    const id = String(req.headers['x-toss-webhook-id'] || ev.id || '');
    const type = String(ev.type || '');
    if (!id || !type) throw httpError(400, 'BAD_EVENT', '이벤트 형식이 아니에요.');
    if (!(await data.recordWebhook(id, type))) return { ok: true, duplicate: true };
    const d = ev.data || {};
    const merchantId = String(ev.merchantId == null ? '' : ev.merchantId);

    if (type === 'app.installation.created.v1') {
      const m = d.merchant || {};
      await data.saveInstallation(merchantId || String(m.id), {
        name: String(m.name || ''),
        businessNumber: String(m.businessNumber || ''),
        installedAt: String(ev.createdAt || new Date(now()).toISOString()),
        removedAt: null,
      });
    } else if (/^app\.installation\..*(deleted|removed|uninstalled)/.test(type)) {
      await data.saveInstallation(merchantId, { removedAt: String(ev.createdAt || new Date(now()).toISOString()) });
    } else if (ORDER_EVENTS[type]) {
      const key = parseOrderKey(d.orderKey);
      if (key) {
        const cfg = await data.getConfig(key.storeId);
        // 그 매장에 연결된 가맹점에서 온 이벤트만 (다른 가맹점이 같은 모양 키를 보내도 무시)
        const order = cfg && String(cfg.merchantId) === merchantId ? await data.getOrder(key.storeId, key.orderId) : null;
        if (order) {
          await applyOrderEvent(key.storeId, key.orderId, order, ORDER_EVENTS[type],
            String(ev.createdAt || new Date(now()).toISOString()),
            d.declinedReason ? String(d.declinedReason).slice(0, 200) : '');
        }
      }
    }
    return { ok: true };
  }

  const cleanMenuId = (v) => {
    const s = String(v == null ? '' : v);
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(s)) throw httpError(400, 'INVALID_MENU', '메뉴 ID가 올바르지 않아요.');
    return s;
  };

  // 96차: 포스 플러그인 신호 — 크기를 줄여서 저장만 함
  const cleanText = (v, max) => String(v == null ? '' : v).replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max);
  const cleanNum = (v) => (Number.isSafeInteger(Number(v)) ? Number(v) : null);
  // 114차 2: 단체손님 묶음 → 방 번호 묶음. 테이블 2개 이상 묶였고 방 번호를 아는 테이블이 있을 때만
  //   private/tossPos.roomGroups = [{room, id, rooms}] (배열 — merge로 저장해도 지난 값이 안 섞이게), 바뀐 방만 roomStatus.group 씀
  async function syncRoomGroups(storeId, cfg, tables) {
    const byGroup = new Map();
    for (const t of tables) if (t.groupId != null) byGroup.set(t.groupId, [...(byGroup.get(t.groupId) || []), t]);
    const next = [];
    for (const [id, ts] of byGroup) {
      if (ts.length < 2) continue;
      const rooms = [...new Set(ts.map((t) => roomFromTableTitle(t.title)).filter((r) => r != null))].sort((a, b) => a - b);
      const color = (ts.find((t) => t.groupColor) || {}).groupColor || '';
      for (const room of rooms) next.push({ room, id, rooms, ...(color ? { color } : {}) });
    }
    next.sort((a, b) => a.room - b.room);
    const prev = Array.isArray(cfg.roomGroups) ? cfg.roomGroups : [];
    const key = (g) => `${g.room}:${g.id}:${(g.rooms || []).join(',')}:${g.color || ''}`;
    if (prev.map(key).join('|') === next.map(key).join('|')) return false;
    const changes = {};
    for (const g of prev) changes[g.room] = null;
    for (const g of next) changes[g.room] = { id: g.id, rooms: g.rooms, ...(g.color ? { color: g.color } : {}) };
    for (const g of prev) {
      const n = next.find((x) => x.room === g.room);
      if (n && key(n) === key(g)) delete changes[g.room];
    }
    await data.setRoomGroups(storeId, changes);
    await data.patchConfig(storeId, { roomGroups: next });
    cfg.roomGroups = next;
    return true;
  }

  // 117차: 포스 계산서 — 테이블마다 열린 포스 주문 합계·결제 전 금액(직원이 포스에서 직접 넣은 메뉴 포함) → 방 번호별로 합쳐
  //   roomStatus/{방}.posBill {total, paid, unpaid, tables, at} (바뀐 방만, 없어지면 null). 지난 값은 private/tossPos.roomBills(배열)
  async function syncRoomBills(storeId, cfg, raw, nowIso) {
    const list = (Array.isArray(raw) ? raw : []).slice(0, 100);
    const byRoom = new Map();
    for (const b of list) {
      const room = roomFromTableTitle(cleanText(b && b.tableTitle, 40));
      if (room == null) continue;
      const cur = byRoom.get(room) || { room, total: 0, paid: 0, unpaid: 0, tables: [] };
      cur.total += Math.max(0, Math.round(Number(b.total) || 0));
      cur.paid += Math.max(0, Math.round(Number(b.paid) || 0));
      cur.unpaid += Math.max(0, Math.round(Number(b.unpaid) || 0));
      cur.tables.push(cleanText(b.tableTitle, 40));
      byRoom.set(room, cur);
    }
    const next = [...byRoom.values()].filter((b) => b.total > 0 || b.unpaid > 0).sort((a, b) => a.room - b.room);
    const prev = Array.isArray(cfg.roomBills) ? cfg.roomBills : [];
    const key = (b) => `${b.room}:${b.total}:${b.paid}:${b.unpaid}:${(b.tables || []).join(',')}`;
    const changes = {};
    for (const b of prev) if (!next.some((x) => x.room === b.room)) changes[b.room] = null;
    for (const b of next) {
      const p = prev.find((x) => x.room === b.room);
      if (!p || key(p) !== key(b)) changes[b.room] = { total: b.total, paid: b.paid, unpaid: b.unpaid, tables: b.tables, at: nowIso };
    }
    const rooms = Object.keys(changes);
    if (rooms.length) {
      await data.setRoomBills(storeId, changes);
      await data.patchConfig(storeId, { roomBills: next });
      cfg.roomBills = next;
    }
    // 125차: 포스 테이블이 빈 방 — 결제 대기에 주문 문서가 없는 주문(관리자 패드에서 지움 등)이 남아 있으면 빼기
    //   (주문 문서가 없으면 포스 결제·취소 신호가 와도 찾을 수 없어 방이 영영 '결제 대기'로 남음)
    let pruned = 0;
    for (const r of rooms.filter((x) => changes[x] === null)) {
      try {
        const n = await data.pruneMissingOrders(storeId, Number(r), nowIso);
        if (n) console.log(`[토스 플러그인] ${storeId} ${r}번 방 포스 테이블이 비어 — 지워진 주문 ${n}건을 결제 대기에서 뺌`);
        pruned += n;
      } catch (e) {
        console.error('[토스] 지워진 주문 정리 실패', storeId, r, e);
      }
    }
    return { ok: true, rooms: rooms.length, pruned };
  }

  async function pluginHello(body, ctx) {
    const list = (v, max) => (Array.isArray(v) ? v.slice(0, max) : []);
    const stage = cleanText(body.stage, 20) || 'hello';
    const reason = cleanText(body.reason, 20);
    const errors = list(body.errors, 10).map((e) => cleanText(e, 200)).filter(Boolean);
    const merchantId = String(body.merchantId == null ? '' : body.merchantId);
    // 0.1.1: 켜지자마자 보내는 'boot'·오류 신호는 가맹점 ID가 없음 — 저장하지 않고 기록만
    if (!/^\d{1,19}$/.test(merchantId)) {
      ctx.rate('toss-plugin:none', 60, 10 * 60 * 1000, '포스 플러그인 신호');
      console.log(`[토스 플러그인] ${stage}${reason ? `(${reason})` : ''} 가맹점 없음 v${cleanText(body.version, 20) || '?'}`
        + `${errors.length ? ` · 오류: ${errors.join(' | ')}` : ''}`);
      return { ok: true, saved: false, at: new Date(now()).toISOString() };
    }
    ctx.rate(`toss-plugin:${merchantId}`, 30, 10 * 60 * 1000, '포스 플러그인 신호');
    const halls = list(body.halls, 50).map((h) => ({ id: cleanNum(h && h.id), title: cleanText(h && h.title, 40) }));
    const tables = list(body.tables, 300).map((t) => ({
      id: cleanNum(t && t.id), hallId: cleanNum(t && t.hallId), title: cleanText(t && t.title, 40), hasOrder: !!(t && t.hasOrder),
      ...(t && cleanNum(t.groupId) != null ? { groupId: cleanNum(t.groupId) } : {}), // 114차: 단체손님(테이블 묶기)
      ...(t && t.groupColor ? { groupColor: cleanText(t.groupColor, 20) } : {}), // 115차: 토스 묶음 색
      ...(t && Array.isArray(t.groupTableIds) ? { groupTableIds: t.groupTableIds.slice(0, 20).map((v) => cleanNum(v)) } : {}), // 118차: 기록용
    }));
    // 114차: 묶인 테이블 — 기록에만 ('단체손님 묶음 7: 기본홀01, 기본홀02')
    const groups = new Map();
    for (const t of tables) if (t.groupId != null) groups.set(t.groupId, [...(groups.get(t.groupId) || []), `${t.title}${t.groupTableIds ? `[${t.groupTableIds.join(',')}]` : ''}`]);
    const info = {
      merchantName: cleanText(body.merchantName, 60),
      serial: cleanText(body.serial, 40),
      version: cleanText(body.version, 20),
      halls, tables,
      tableError: cleanText(body.tableError, 200),
      errors,
    };
    const link = await pluginStore(merchantId, { fresh: true });
    const linkedStore = link ? link.storeId : null;
    // 120차: hello 횟수 제한 — 어느 매장과도 연결 안 된 가맹점 신호는 전체 합쳐 10분 60번까지
    //   (공개 저장소라 주소를 알 수 있음 — 아무 가맹점 번호로 마구 보내 기록·기기가 쌓이지 않게. 가맹점마다 10분 30번은 위에서)
    if (!link) ctx.rate('toss-plugin:unlinked', HELLO_UNLINKED_MAX, 10 * 60 * 1000, '포스 플러그인 신호');
    await data.savePluginHello(merchantId, info);
    // 114차 2: 단체손님 — 묶인 테이블의 방들을 roomStatus/{방}.group에 (방 현황판이 같은 색 테두리로 표시만)
    if (link && !info.tableError && tables.length) {
      try {
        await syncRoomGroups(link.storeId, link.cfg, tables);
      } catch (e) {
        console.log(`[토스 플러그인] 단체손님 표시 저장 실패: ${e && e.message}`);
      }
    }
    // 100차: 기기 등록 — 처음 보는 포스(또는 승인 전에 열쇠를 잃은 포스)에 새 열쇠를 줌. 운영자가 승인해야 주문을 받음
    let deviceToken;
    let approved = false;
    let deviceProblem = '';
    // 열쇠를 저장하지 못하는 예전 플러그인(0.1.x)의 신호로는 기기를 등록하지 않음 (100차 시험: 0.1.2 신호로 만든 기기를
    // 승인했더니 0.2.0은 열쇠가 없어 '승인됐는데 열쇠가 안 맞음'에 걸림)
    const canKeepToken = /^(\d+)\.(\d+)/.test(info.version) && !/^0\.[01]\./.test(info.version);
    if (info.serial && canKeepToken) {
      const auth = await pluginDevice({ merchantId, serial: info.serial, token: body.token });
      const at = new Date(now()).toISOString();
      if (auth.ok) {
        approved = auth.approved;
        await data.setPluginDevice(merchantId, info.serial, { lastSeenAt: at, version: info.version });
      } else if (!auth.dev && tooManyDevices(await data.getPluginDevices(merchantId))) {
        // 120차: 처음 보는 기기인데 이 가맹점에 승인 전 기기가 이미 많음 → 새로 만들지 않음 (가짜 시리얼로 기기가 쌓이지 않게)
        deviceProblem = `승인 전 기기가 너무 많아요(최대 ${MAX_PENDING_DEVICES}대) — 운영자 페이지 [포스 플러그인]에서 안 쓰는 기기를 지워 주세요.`;
        console.warn(`[토스 플러그인] 가맹점 ${merchantId} 새 기기 ${info.serial} 거절 — 승인 전 기기가 너무 많음`);
      } else if (!auth.dev || auth.dev.approved !== true) {
        deviceToken = crypto.randomBytes(24).toString('hex');
        await data.setPluginDevice(merchantId, info.serial, {
          tokenHash: sha(deviceToken), approved: false, firstSeenAt: (auth.dev && auth.dev.firstSeenAt) || at, lastSeenAt: at, version: info.version,
        });
      } else {
        deviceProblem = '승인된 기기인데 열쇠가 맞지 않아요 — 운영자 페이지에서 이 기기를 지우고 다시 승인해 주세요.';
      }
    }
    console.log(`[토스 플러그인] 가맹점 ${merchantId}(${info.merchantName}) 매장 ${linkedStore || '-'} 포스 ${info.serial || '-'} v${info.version || '?'}`
      + ` 홀 ${halls.length} · 테이블 ${tables.length}${info.tableError ? ` · 테이블 오류: ${info.tableError}` : ''}`
      + ` · 기기 ${approved ? '승인됨' : deviceToken ? '새 열쇠(승인 전)' : deviceProblem ? '열쇠 안 맞음' : '승인 전'}`
      + ` · 보내기 ${link && link.cfg.via === 'plugin' ? '플러그인' : '안 함'}`
      + `${groups.size ? ` · 단체손님 묶음 ${[...groups].map(([g, ts]) => `${g}: ${ts.join(', ')}`).join(' / ')}` : ''}`
      + `${errors.length ? ` · 오류: ${errors.join(' | ')}` : ''}${reason ? ` (${reason})` : ''}`);
    return {
      ok: true, linkedStore, at: new Date(now()).toISOString(), approved, ...(deviceToken ? { deviceToken } : {}),
      ...(deviceProblem ? { deviceProblem } : {}), via: link && link.cfg.via === 'plugin' ? 'plugin' : 'api',
      pollMs: approved && link && link.cfg.via === 'plugin' ? PLUGIN_POLL_MS : PLUGIN_IDLE_MS,
    };
  }

  // 관리자·패드 API — ctx: app.js의 requireStoreUser 등
  async function route(req, path, ctx) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    if (path === '/api/toss/webhook' && req.method === 'POST') return webhook(req);
    if (path === '/api/toss/plugin/hello' && req.method === 'POST') return pluginHello(body, ctx);
    if (path === '/api/toss/plugin/poll' && req.method === 'POST') return pluginPoll(body, ctx);
    if (path === '/api/toss/plugin/ack' && req.method === 'POST') return pluginAck(body, ctx);
    if (path === '/api/toss/plugin/event' && req.method === 'POST') return pluginEvent(body, ctx);

    if (path === '/api/toss/send-order' && req.method === 'POST') {
      const user = await ctx.requireStoreUser(req);
      ctx.rate(`toss-send:${user.store}`, 60, 60 * 1000, '포스 보내기');
      const orderId = String(body.orderId || '');
      if (!/^[A-Za-z0-9]{1,40}$/.test(orderId)) throw httpError(400, 'INVALID_ORDER', '주문 ID가 올바르지 않아요.');
      return sendOrder(user, orderId);
    }

    const user = await ctx.requireAdmin(req);
    ctx.rate(`toss-admin:${user.store}`, 60, 60 * 1000, '포스 요청');

    if (path === '/api/toss/status' && req.method === 'GET') {
      const account = await stores.getAccount(user.store);
      const cfg = (await data.getConfig(user.store)) || {};
      const failed = (await data.listFailedOrders(user.store)).map((o) => ({
        id: o.id, room: o.room || '', time: o.time || '', price: o.price || '', items: o.items || [],
        error: (o.tossPos || {}).error || '', failedAt: (o.tossPos || {}).failedAt || null,
      })).sort((a, b) => String(b.failedAt).localeCompare(String(a.failedAt)));
      return {
        enabled: !!(account && account.features && account.features.tossPos),
        linked: !!cfg.merchantId,
        mode: cfg.mode || null,
        merchantName: cfg.merchantName || '',
        printOrderSheet: cfg.printOrderSheet === true,
        menuMap: cfg.menuMap || {},
        setMap: cfg.setMap || {},
        etcItemId: cfg.etcItemId || null, // 113차
        posSoldOutMenus: Array.isArray(cfg.posSoldOutMenus) ? cfg.posSoldOutMenus : [], // 113차
        failed,
      };
    }
    if (path === '/api/toss/catalog' && req.method === 'GET') {
      const cfg = await linkedConfig(user.store);
      try {
        return { mode: cfg.mode, items: catalogView(await catalogOf(cfg, { fresh: true })) };
      } catch (e) {
        throw tossFail(e);
      }
    }
    if (path === '/api/toss/menu-map' && req.method === 'POST') {
      await linkedConfig(user.store);
      const map = body.map && typeof body.map === 'object' ? body.map : null;
      if (!map || !Object.keys(map).length || Object.keys(map).length > 500) throw httpError(400, 'NOTHING', '바꿀 연결이 없어요.');
      const clean = {};
      for (const [k, v] of Object.entries(map)) {
        // 99차: '상품ID' 또는 '상품ID:옵션ID=선택ID,…' (필수 옵션을 미리 골라 둔 연결)
        const itemId = v == null || v === '' ? null : String(v);
        if (itemId != null && !parseMapEntry(itemId)) throw httpError(400, 'INVALID_ITEM', '포스 상품 ID가 올바르지 않아요.');
        clean[cleanMenuId(k)] = itemId;
      }
      await data.setMenuMap(user.store, clean);
      return { ok: true, menuMap: ((await data.getConfig(user.store)) || {}).menuMap || {} };
    }
    // 113차: 연결 안 된 메뉴를 받을 포스 상품
    // 115차: 관리자 방 현황판 비우기 → 116차 '방 비우기': 결제 대기·주문 내역 + 진행 중 주문은 완료로 + 호출 확인 + 그 방 패드 처음 화면
    //   (운영자 /api/ops/toss/room-clear는 예전대로 결제 대기만 — 패드 그대로)
    if (path === '/api/toss/room-clear' && req.method === 'POST') {
      const room = Number(body.room);
      if (!Number.isInteger(room) || room < 1 || room > 999) throw httpError(400, 'INVALID_ROOM', '방 번호를 확인해 주세요.');
      const r = await data.resetRoom(user.store, room, new Date(now()).toISOString());
      console.log(`[토스] 관리자 방 비우기 ${user.store} ${room}번 방 — 결제 대기 ${r.open.length}건(${r.open.join(', ')}) · 진행 중 주문 완료 ${r.orders}건 · 호출 확인 ${r.calls}건`);
      return { ok: true, cleared: r.open.length, orders: r.orders, calls: r.calls };
    }
    if (path === '/api/toss/etc-item' && req.method === 'POST') {
      await linkedConfig(user.store);
      const v = body.itemId == null || body.itemId === '' ? null : String(body.itemId);
      if (v != null && !/^\d{1,19}$/.test(v)) throw httpError(400, 'INVALID_ITEM', '포스 상품 ID가 올바르지 않아요.');
      await data.patchConfig(user.store, { etcItemId: v });
      linkCache.clear();
      return { ok: true, etcItemId: v };
    }
    if (path === '/api/toss/set-map' && req.method === 'POST') {
      await linkedConfig(user.store);
      let clean;
      try {
        clean = cleanSetMap(body.map);
      } catch (e) {
        if (e instanceof TossError) throw httpError(400, e.code, e.message);
        throw e;
      }
      const before = (await data.getConfig(user.store)) || {};
      await data.setSetMap(user.store, clean, Math.max(now(), (Number(before.setMapRev) || 0) + 1));
      linkCache.clear(); // 포스 플러그인이 다음 확인 때 바로 받게
      return { ok: true, setMap: ((await data.getConfig(user.store)) || {}).setMap || {} };
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  // 운영자 API (app.js가 requireOps를 먼저 확인함)
  async function opsRoute(req, path) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const { cleanStoreId } = require('./stores');
    if (path === '/api/ops/toss/overview' && req.method === 'GET') {
      const list = await stores.listStores();
      const links = {};
      for (const s of list) {
        const cfg = await data.getConfig(s.id);
        if (cfg && cfg.merchantId) {
          links[s.id] = {
            mode: cfg.mode, merchantId: String(cfg.merchantId), merchantName: cfg.merchantName || '',
            printOrderSheet: cfg.printOrderSheet === true, mapped: Object.keys(cfg.menuMap || {}).length,
            via: cfg.via === 'plugin' ? 'plugin' : 'api',
          };
        }
      }
      return { liveReady: !!live, webhookReady: !!webhookSecret, links, installations: await data.listInstallations() };
    }
    if (path === '/api/ops/toss/link' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      if (!(await stores.exists(storeId))) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      const before = (await data.getConfig(storeId)) || {};
      let cfg;
      if (body.mode === 'fake') {
        cfg = { mode: 'fake', merchantId: `${FAKE_PREFIX}${storeId}`, merchantName: '가짜 포스(개발용)' };
      } else if (body.mode === 'live') {
        const merchantId = String(body.merchantId || '');
        if (!/^\d{1,19}$/.test(merchantId)) throw httpError(400, 'INVALID_MERCHANT', '토스 가맹점 ID(숫자)를 확인해 주세요.');
        const inst = (await data.listInstallations()).find((i) => String(i.merchantId) === merchantId);
        if (!inst && !live) throw httpError(400, 'NOT_INSTALLED', '이 가맹점에서 고도리 앱을 설치한 기록이 없어요.');
        cfg = { mode: 'live', merchantId, merchantName: (inst && inst.name) || '', businessNumber: (inst && inst.businessNumber) || '' };
      } else {
        throw httpError(400, 'INVALID_MODE', "mode는 'fake' 또는 'live'예요.");
      }
      // 가맹점이 바뀌면 메뉴 연결표는 다른 포스 상품 ID라 비움
      const sameMerchant = String(before.merchantId || '') === cfg.merchantId;
      await data.setConfig(storeId, {
        ...cfg,
        printOrderSheet: before.printOrderSheet === true,
        menuMap: sameMerchant ? before.menuMap || {} : {},
        ...(sameMerchant && cfg.mode === 'live' && before.via === 'plugin' ? { via: 'plugin' } : {}),
        linkedAt: new Date(now()).toISOString(),
      });
      return { ok: true, store: storeId, ...cfg, menuMapCleared: !sameMerchant && Object.keys(before.menuMap || {}).length > 0 };
    }
    if (path === '/api/ops/toss/unlink' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      await data.clearConfig(storeId);
      return { ok: true };
    }
    if (path === '/api/ops/toss/config' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      const patch = {};
      if (body.printOrderSheet !== undefined) {
        if (typeof body.printOrderSheet !== 'boolean') throw httpError(400, 'INVALID', 'printOrderSheet는 true/false예요.');
        patch.printOrderSheet = body.printOrderSheet;
      }
      if (body.via !== undefined) {
        if (body.via !== 'plugin' && body.via !== 'api') throw httpError(400, 'INVALID', "via는 'plugin' 또는 'api'예요.");
        patch.via = body.via;
      }
      if (!Object.keys(patch).length) throw httpError(400, 'NOTHING', '바꿀 설정이 없어요.');
      const cfg = await data.getConfig(storeId);
      if (!cfg) throw httpError(409, 'TOSS_NOT_LINKED', '먼저 포스와 연결해 주세요.');
      if (patch.via === 'plugin' && cfg.mode !== 'live') throw httpError(409, 'NOT_LIVE', '실제 포스에 연결된 매장에서만 플러그인으로 보낼 수 있어요.');
      await data.patchConfig(storeId, patch);
      linkCache.clear();
      return { ok: true };
    }
    // 95차: 포스 화면에 주문이 안 보일 때 — 토스 서버에 그 주문이 정말 있는지 주문 키로 확인
    if (path === '/api/ops/toss/lookup' && req.method === 'GET') {
      const storeId = cleanStoreId((req.query || {}).storeId);
      const cfg = await data.getConfig(storeId);
      if (!cfg || !cfg.merchantId) throw httpError(409, 'TOSS_NOT_LINKED', '먼저 포스와 연결해 주세요.');
      const sent = await data.listSentOrders(storeId, 5);
      const fakeList = cfg.mode === 'fake' ? await data.listFakeOrders(cfg.merchantId) : null;
      const results = [];
      for (const o of sent) {
        const t = o.tossPos || {};
        const orderKey = orderKeyOf(storeId, o.id);
        const row = {
          orderId: o.id, room: o.room || '', time: o.time || '', price: o.price || '', items: o.items || [],
          sentAt: t.sentAt || null, sentMode: t.mode || '', posOrderId: t.posOrderId || '', posState: t.posState || '', orderKey,
        };
        if (t.mode && t.mode !== cfg.mode) {
          results.push({ ...row, found: null, note: `지금 연결(${cfg.mode})과 다른 포스(${t.mode})로 보낸 주문이라 조회하지 않았어요.` });
          continue;
        }
        try {
          const got = fakeList
            ? fakeList.find((f) => f.orderKey === orderKey) || null
            : await clientFor(cfg).getOrderByKey(cfg.merchantId, orderKey);
          if (!got) {
            results.push({ ...row, found: false, code: 'NOT_FOUND', error: '포스에 이 주문이 없어요.' });
          } else {
            results.push({
              ...row, found: true,
              toss: {
                id: String(got.id || ''), orderState: got.orderState || '', source: got.source || '', orderNumber: got.orderNumber || '',
                createdAt: got.createdAt || null, openedAt: got.openedAt || null, totalAmount: got.chargePrice ? got.chargePrice.totalAmount : null,
                lineItems: (got.lineItems || []).length, memo: got.memo || '',
              },
            });
          }
        } catch (e) {
          const notFound = e && (e.status === 404 || /NOT_FOUND/i.test(String(e.code)));
          results.push({ ...row, found: notFound ? false : null, code: String((e && e.code) || 'ERROR'), error: String((e && e.message) || e) });
        }
      }
      return { mode: cfg.mode, merchantId: String(cfg.merchantId), merchantName: cfg.merchantName || '', results };
    }
    // 96차: 포스 플러그인 신호
    if (path === '/api/ops/toss/plugins' && req.method === 'GET') {
      const links = {};
      for (const s of await stores.listStores()) {
        const cfg = await data.getConfig(s.id);
        if (cfg && cfg.mode === 'live' && cfg.merchantId) links[String(cfg.merchantId)] = s.id;
      }
      // 100차: 기기 열쇠(tokenHash)는 빼고 보냄
      return {
        plugins: (await data.listPluginHellos()).map((p) => ({
          ...p,
          devices: Object.fromEntries(Object.entries(p.devices || {}).map(([serial, d]) => {
            const { tokenHash, ...rest } = d || {};
            return [serial, { ...rest, hasToken: !!tokenHash }];
          })),
          linkedStore: links[String(p.merchantId)] || null,
        })),
      };
    }
    if (path === '/api/ops/toss/plugin-device' && req.method === 'POST') {
      const merchantId = String(body.merchantId == null ? '' : body.merchantId);
      const serial = cleanText(body.serial, 40);
      if (!/^\d{1,19}$/.test(merchantId) || !serial) throw httpError(400, 'INVALID', '가맹점·기기 번호를 확인해 주세요.');
      const devices = await data.getPluginDevices(merchantId);
      if (!devices[serial]) throw httpError(404, 'NO_DEVICE', '신호를 보낸 적 없는 기기예요.');
      if (body.remove === true) await data.setPluginDevice(merchantId, serial, null);
      else if (typeof body.approved === 'boolean') await data.setPluginDevice(merchantId, serial, { approved: body.approved });
      else throw httpError(400, 'INVALID', 'approved(true/false) 또는 remove가 필요해요.');
      authCache.clear();
      return { ok: true };
    }
    // 102차: 방 결제 대기 — 끝나지 않는 주문(예: 95차 Open API 시험 주문)이 남아 방이 정산되지 않을 때 운영자가 비움
    if (path === '/api/ops/toss/rooms' && req.method === 'GET') {
      const storeId = cleanStoreId((req.query || {}).storeId);
      const list = await data.listRooms(storeId);
      const rooms = [];
      for (const r of list) {
        const open = Array.isArray(r.open) ? r.open.map(String) : [];
        const cycle = Array.isArray(r.cycle) ? r.cycle : [];
        if (!open.length && !cycle.length) continue;
        const orders = [];
        for (const id of open.slice(0, 20)) {
          const o = await data.getOrder(storeId, id);
          const t = (o && o.tossPos) || {};
          orders.push({
            id, time: (o && o.time) || '', price: (o && o.price) || '', items: (o && o.items) || [],
            mode: t.mode || '', state: t.state || '', posState: t.posState || '', sentAt: t.sentAt || null, tableTitle: t.tableTitle || '',
          });
        }
        rooms.push({ room: Number(r.room) || r.room, open: open.length, cycle: cycle.length, orders, settledAt: r.settledAt || null });
      }
      rooms.sort((a, b) => Number(a.room) - Number(b.room));
      return { rooms };
    }
    if (path === '/api/ops/toss/room-clear' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      const room = Number(body.room);
      if (!Number.isInteger(room) || room < 1 || room > 999) throw httpError(400, 'INVALID_ROOM', '방 번호를 확인해 주세요.');
      const r = await data.clearRoom(storeId, room);
      console.log(`[토스] 운영자 방 결제 대기 비움 ${storeId} ${room}번 방 — 주문 ${r.open.length}건(${r.open.join(', ')})`);
      return { ok: true, cleared: r.open.length };
    }
    if (path === '/api/ops/toss/fake-orders' && req.method === 'GET') {
      const storeId = cleanStoreId((req.query || {}).storeId);
      return { orders: await data.listFakeOrders(`${FAKE_PREFIX}${storeId}`) };
    }
    if (path === '/api/ops/toss/fake-complete' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      const cfg = await data.getConfig(storeId);
      if (!cfg || cfg.mode !== 'fake') throw httpError(409, 'NOT_FAKE', '가짜 포스로 연결된 매장에서만 쓸 수 있어요.');
      const key = parseOrderKey(body.orderKey);
      if (!key || key.storeId !== storeId) throw httpError(400, 'INVALID_ORDER_KEY', '주문 키가 올바르지 않아요.');
      const order = await data.getOrder(storeId, key.orderId);
      if (!order) throw httpError(404, 'NO_ORDER', '없는 주문이에요.');
      const atIso = new Date(now()).toISOString();
      const r = await applyOrderEvent(storeId, key.orderId, order, 'COMPLETED', atIso);
      const fid = String(body.id == null ? '' : body.id);
      if (/^\d{1,19}$/.test(fid)) await data.markFakeOrder(cfg.merchantId, fid, { posState: 'COMPLETED', completedAt: atIso });
      return { ok: true, settled: r.settled === true, open: r.open };
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  return { route, opsRoute, sendOrder, clearCatalogCache: () => catalogCache.clear() };
}

module.exports = { createTossRoutes, FAKE_PREFIX };
