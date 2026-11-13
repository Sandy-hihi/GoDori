'use strict';
// 토스 POS 연동 API (64차) — app.js가 /api/toss/* 와 /api/ops/toss/* 를 여기로 넘김
//
//   POST /api/toss/webhook        토스가 보내는 웹훅 (로그인 없음, 서명 확인) — 앱 설치·주문 상태
//   POST /api/toss/send-order     (패드·관리자) { orderId }  주문을 포스로 보내기. 패드는 주문 직후 자동, 관리자는 '다시 보내기'
//   GET  /api/toss/status         (관리자) 연결 상태·메뉴 연결표·보내기 실패한 주문
//   GET  /api/toss/catalog        (관리자) 포스 상품 목록 (메뉴 연결 화면용)
//   POST /api/toss/menu-map       (관리자) { map: { 고도리 메뉴 ID: 토스 상품 ID | null } }
//   GET  /api/ops/toss/overview   (운영자) 매장별 연결 상태 + 토스 '앱 설치' 매장 목록 + 진짜 키 등록 여부
//   POST /api/ops/toss/link       (운영자) { storeId, mode: 'fake' | 'live', merchantId? }  매장 ↔ 포스 연결
//   POST /api/ops/toss/unlink     (운영자) { storeId }
//   GET  /api/ops/toss/lookup     (운영자) ?storeId=  최근 포스로 보낸 주문 5건을 토스(또는 가짜 포스)에서 주문 키로 다시 조회 (95차)
//   POST /api/ops/toss/config     (운영자) { storeId, printOrderSheet }
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
  TossError, createFakeToss, fakeCatalogFromMenus, buildTossOrder, parseOrderKey, orderKeyOf, verifyWebhook, catalogView,
} = require('./toss');
const { cycleEntry } = require('./toss-data');

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
    return data.closeRoomOrder(storeId, room, orderId, { paid: state === 'COMPLETED', atIso });
  }

  // ── 주문 보내기 ──
  async function sendOrder(user, orderId) {
    const cfg = await linkedConfig(user.store);
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

  // 관리자·패드 API — ctx: app.js의 requireStoreUser 등
  async function route(req, path, ctx) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    if (path === '/api/toss/webhook' && req.method === 'POST') return webhook(req);

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
        const itemId = v == null || v === '' ? null : String(v);
        if (itemId != null && !/^\d{1,19}$/.test(itemId)) throw httpError(400, 'INVALID_ITEM', '포스 상품 ID가 올바르지 않아요.');
        clean[cleanMenuId(k)] = itemId;
      }
      await data.setMenuMap(user.store, clean);
      return { ok: true, menuMap: ((await data.getConfig(user.store)) || {}).menuMap || {} };
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
      if (typeof body.printOrderSheet !== 'boolean') throw httpError(400, 'INVALID', 'printOrderSheet는 true/false예요.');
      if (!(await data.getConfig(storeId))) throw httpError(409, 'TOSS_NOT_LINKED', '먼저 포스와 연결해 주세요.');
      await data.patchConfig(storeId, { printOrderSheet: body.printOrderSheet });
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
