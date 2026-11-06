'use strict';
// 매장 통계 (65차) — 매장별로 손님이 많이 주문한 메뉴·많이 찾은 게임. 운영자 페이지 '매장 통계' 탭에서 봄
//
//   POST /api/stats/order      (패드) { orderId }  주문 직후 패드가 부름 → 서버가 주문 문서를 읽어 메뉴별로 셈 (한 주문은 한 번만)
//   POST /api/stats/report     (패드) { gameViews: { 게임 ID: 횟수 } }  손님이 게임 상세를 연 횟수 (패드가 모아서 10분마다)
//   GET  /api/ops/insights?storeId=<매장 아이디 | all>&days=7|30|90   (운영자) 기간 합계 — 인기 메뉴·인기 게임·시간대별 주문
//
// 저장 (전부 서버만 — firestore.rules에 없는 경로라 앱에서는 읽기·쓰기 모두 막힘):
//   stores/{매장}/statsDaily/{YYYY-MM-DD}  (한국 날짜)
//     { date, orders, revenue, items, hours: { '0'~'23': 주문 수 },
//       menus: { <메뉴 키>: { name, category, qty, revenue, orders, options: { '그룹: 옵션': 개수 } } },
//       views, gameViews: { <게임 ID>: 횟수 } }
//     메뉴 키 = 고도리 메뉴 ID (없으면 'n_' + 이름)
//   stores/{매장}/orders/{주문}.statsAt   센 시각 (같은 주문을 두 번 세지 않게)
//   룰 영상 재생은 원래 있던 stores/{매장}/videoStatsDaily (index.js createVideoStats)를 같이 읽음
//
// 주문 문서는 사장님이 주문현황에서 지울 수 있어서, 나중에 모아 세지 않고 들어올 때 바로 셈.
// 방 번호·요청 사항 같은 건 저장하지 않고 메뉴·개수·금액·시간대만 (손님 개인 정보 없음).
// 매출은 패드 주문 금액 기준(카운터에서 직접 받은 주문·할인·취소는 모름).

const { seoulDateKey } = require('./stores');

const MAX_LINES = 100;
const MAX_REPORT_GAMES = 300;
const TOP = 50;
const ID_RE = /^[A-Za-z0-9_-]{1,100}$/;
const ORDER_ID_RE = /^[A-Za-z0-9]{1,40}$/;
const MIN = 60 * 1000;

function num(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : 0;
  const n = Number(String(v == null ? '' : v).replace(/[^0-9.-]/g, ''));
  return Number.isFinite(n) ? n : 0;
}

function text(v, max = 60) {
  return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);
}

// Firestore 맵 키로 써도 안전하게
function safeKey(s) {
  return text(s, 100).replace(/[.\/\[\]`*~#$]/g, '_') || '_';
}

function seoulHour(ms) {
  const h = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Seoul', hour: '2-digit', hourCycle: 'h23' }).format(new Date(ms));
  return String(Number(h) % 24);
}

// 주문 문서 → { menus: { 키: { name, category, qty, revenue, options } }, items, revenue }
// lines(64차 패드 주문)가 없으면 메뉴는 못 세고 주문 수·금액만
function summarizeOrder(order) {
  const lines = Array.isArray(order && order.lines) ? order.lines.slice(0, MAX_LINES) : [];
  const menus = {};
  let items = 0;
  let revenue = 0;
  for (const l of lines) {
    if (!l || typeof l !== 'object') continue;
    const name = text(l.name);
    const qty = Math.trunc(num(l.quantity));
    if (!name || qty < 1 || qty > 999) continue;
    let unit = Math.max(0, num(l.basePrice));
    const optKeys = [];
    for (const o of Array.isArray(l.options) ? l.options.slice(0, 20) : []) {
      if (!o || typeof o !== 'object') continue;
      unit += Math.max(0, num(o.price));
      const on = text(o.name, 40);
      if (on) optKeys.push(safeKey(o.group ? `${text(o.group, 30)}: ${on}` : on));
    }
    if (unit > 1000000) unit = 0; // 이상한 값은 금액에서 뺌
    const id = text(l.menuId, 100);
    const key = ID_RE.test(id) ? id : `n_${safeKey(name)}`;
    const m = menus[key] || (menus[key] = { name, category: text(l.category, 30), qty: 0, revenue: 0, options: {} });
    m.qty += qty;
    m.revenue += unit * qty;
    for (const k of optKeys) m.options[k] = (m.options[k] || 0) + qty;
    items += qty;
    revenue += unit * qty;
  }
  if (!Object.keys(menus).length) revenue = Math.min(10000000, Math.max(0, num(order && order.price)));
  return { menus, items, revenue };
}

// 여러 날의 기록을 합침. rows: statsDaily 문서들, videoRows: videoStatsDaily 문서들
function aggregate(rows, videoRows = []) {
  const summary = { orders: 0, revenue: 0, items: 0, gameViews: 0, videoPlays: 0, activeDays: 0 };
  const hours = new Array(24).fill(0);
  const menus = new Map();
  const games = new Map();
  const daily = new Map();
  const day = (date) => {
    if (!daily.has(date)) daily.set(date, { date, orders: 0, revenue: 0, gameViews: 0, videoPlays: 0 });
    return daily.get(date);
  };
  const game = (id) => {
    if (!games.has(id)) games.set(id, { id, views: 0, plays: 0 });
    return games.get(id);
  };
  const sorted = [...rows].sort((a, b) => String(a.date).localeCompare(String(b.date)));
  for (const r of sorted) {
    const d = day(String(r.date || ''));
    summary.orders += num(r.orders);
    summary.revenue += num(r.revenue);
    summary.items += num(r.items);
    summary.gameViews += num(r.views);
    d.orders += num(r.orders);
    d.revenue += num(r.revenue);
    d.gameViews += num(r.views);
    for (const [h, n] of Object.entries(r.hours || {})) {
      const i = Number(h);
      if (Number.isInteger(i) && i >= 0 && i < 24) hours[i] += num(n);
    }
    for (const [k, m] of Object.entries(r.menus || {})) {
      if (!m || typeof m !== 'object') continue;
      const cur = menus.get(k) || { key: k, name: '', category: '', qty: 0, revenue: 0, orders: 0, options: {} };
      if (m.name) cur.name = String(m.name); // 날짜순이라 마지막(최근) 이름이 남음
      if (m.category) cur.category = String(m.category);
      cur.qty += num(m.qty);
      cur.revenue += num(m.revenue);
      cur.orders += num(m.orders);
      for (const [ok, n] of Object.entries(m.options || {})) cur.options[ok] = (cur.options[ok] || 0) + num(n);
      menus.set(k, cur);
    }
    for (const [id, n] of Object.entries(r.gameViews || {})) game(id).views += num(n);
  }
  for (const v of videoRows) {
    const d = day(String(v.date || ''));
    summary.videoPlays += num(v.plays);
    d.videoPlays += num(v.plays);
    for (const [id, n] of Object.entries(v.games || {})) game(id).plays += num(n);
  }
  for (const d of daily.values()) if (d.orders || d.gameViews || d.videoPlays) summary.activeDays++;
  return { summary, hours, menus, games, daily: [...daily.values()].filter((d) => d.date).sort((a, b) => a.date.localeCompare(b.date)) };
}

function topOptions(options, n = 3) {
  return Object.entries(options || {})
    .map(([name, qty]) => ({ name, qty }))
    .sort((a, b) => b.qty - a.qty || a.name.localeCompare(b.name))
    .slice(0, n);
}

function menuRows(menus, top = TOP) {
  return [...menus.values()]
    .map((m) => ({ key: m.key, name: m.name || '(이름 없음)', category: m.category, qty: m.qty, revenue: m.revenue, orders: m.orders, options: topOptions(m.options) }))
    .sort((a, b) => b.qty - a.qty || b.revenue - a.revenue || a.name.localeCompare(b.name))
    .slice(0, top);
}

function gameRows(games, top = TOP) {
  return [...games.values()]
    .map((g) => ({ id: g.id, views: g.views, plays: g.plays, total: g.views + g.plays }))
    .filter((g) => g.total > 0)
    .sort((a, b) => b.total - a.total || b.views - a.views || a.id.localeCompare(b.id))
    .slice(0, top);
}

// 이름 비교용 (띄어쓰기·대소문자 무시) — 전체 매장 합칠 때
const norm = (s) => String(s || '').replace(/\s+/g, '').toLowerCase();

// ── 저장소 ──

function createFirestoreInsights(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  const store = (id) => db.collection('stores').doc(id);
  const inc = (n) => FieldValue.increment(n);

  function orderPayload(date, hour, s) {
    const data = { date, orders: inc(1), revenue: inc(s.revenue), items: inc(s.items), hours: { [hour]: inc(1) } };
    const menus = {};
    for (const [k, m] of Object.entries(s.menus)) {
      const entry = { name: m.name, category: m.category, qty: inc(m.qty), revenue: inc(m.revenue), orders: inc(1) };
      // 빈 맵을 merge로 쓰면 기존 값을 지워 버려서 있을 때만
      const opts = Object.entries(m.options);
      if (opts.length) entry.options = Object.fromEntries(opts.map(([ok, n]) => [ok, inc(n)]));
      menus[k] = entry;
    }
    if (Object.keys(menus).length) data.menus = menus;
    return data;
  }

  return {
    // decide(order) → 셀 값 { date, hour, stats } (허락 안 되면 throw). 반환 'missing' | 'already' | 'counted'
    async countOrder(storeId, orderId, decide) {
      return db.runTransaction(async (tx) => {
        const ref = store(storeId).collection('orders').doc(orderId);
        const d = await tx.get(ref);
        if (!d.exists) return 'missing';
        const order = d.data();
        const { date, hour, stats } = decide(order);
        if (order.statsAt != null) return 'already';
        tx.update(ref, { statsAt: FieldValue.serverTimestamp() });
        tx.set(store(storeId).collection('statsDaily').doc(date), orderPayload(date, hour, stats), { merge: true });
        return 'counted';
      });
    },
    async addGameViews(storeId, date, views) {
      const gameViews = {};
      let total = 0;
      for (const [id, n] of Object.entries(views)) {
        gameViews[id] = inc(n);
        total += n;
      }
      if (!total) return;
      await store(storeId).collection('statsDaily').doc(date).set({ date, views: inc(total), gameViews }, { merge: true });
    },
    async daysSince(storeId, from) {
      const snap = await store(storeId).collection('statsDaily').where('date', '>=', from).get();
      return snap.docs.map((d) => d.data());
    },
    async videoDaysSince(storeId, from) {
      const snap = await store(storeId).collection('videoStatsDaily').where('date', '>=', from).get();
      return snap.docs.map((d) => d.data());
    },
    // 게임 이름 (상위 몇 개만 읽음). 지운 게임은 룰 영상 통계(videoStats)에 남은 이름으로
    async gameTitles(storeId, ids) {
      if (!ids.length) return {};
      const games = store(storeId).collection('games');
      const docs = await db.getAll(...ids.map((id) => games.doc(id)));
      const out = {};
      const missing = [];
      for (const d of docs) {
        if (d.exists) out[d.id] = String(d.get('title') || '');
        else missing.push(d.id);
      }
      if (missing.length) {
        const vs = store(storeId).collection('videoStats');
        const vdocs = await db.getAll(...missing.map((id) => vs.doc(id)));
        for (const d of vdocs) if (d.exists && d.get('title')) out[d.id] = `${d.get('title')} (지운 게임)`;
      }
      return out;
    },
  };
}

// 테스트용 — orders: { 매장: { 주문 ID: 주문 } }, games: { 매장: { 게임 ID: 이름 } }, video: { 매장: [videoStatsDaily 문서] }
function createMemoryInsights({ orders = {}, games = {}, video = {} } = {}) {
  const daily = new Map(); // `${매장}/${날짜}` → 문서
  const doc = (storeId, date) => {
    const k = `${storeId}/${date}`;
    if (!daily.has(k)) daily.set(k, { storeId, date });
    return daily.get(k);
  };
  const add = (o, k, n) => { o[k] = (o[k] || 0) + n; };
  return {
    orders, daily,
    async countOrder(storeId, orderId, decide) {
      const order = (orders[storeId] || {})[orderId];
      if (!order) return 'missing';
      const { date, hour, stats } = decide(order);
      if (order.statsAt != null) return 'already';
      order.statsAt = new Date().toISOString();
      const d = doc(storeId, date);
      add(d, 'orders', 1);
      add(d, 'revenue', stats.revenue);
      add(d, 'items', stats.items);
      d.hours = d.hours || {};
      add(d.hours, hour, 1);
      for (const [k, m] of Object.entries(stats.menus)) {
        d.menus = d.menus || {};
        const cur = d.menus[k] || (d.menus[k] = { qty: 0, revenue: 0, orders: 0, options: {} });
        cur.name = m.name;
        cur.category = m.category;
        add(cur, 'qty', m.qty);
        add(cur, 'revenue', m.revenue);
        add(cur, 'orders', 1);
        for (const [ok, n] of Object.entries(m.options)) add(cur.options, ok, n);
      }
      return 'counted';
    },
    async addGameViews(storeId, date, views) {
      const d = doc(storeId, date);
      d.gameViews = d.gameViews || {};
      for (const [id, n] of Object.entries(views)) {
        add(d.gameViews, id, n);
        add(d, 'views', n);
      }
    },
    async daysSince(storeId, from) {
      return [...daily.values()].filter((d) => d.storeId === storeId && d.date >= from).map((d) => JSON.parse(JSON.stringify(d)));
    },
    async videoDaysSince(storeId, from) {
      return (video[storeId] || []).filter((d) => d.date >= from);
    },
    async gameTitles(storeId, ids) {
      const g = games[storeId] || {};
      return Object.fromEntries(ids.filter((id) => g[id] != null).map((id) => [id, g[id]]));
    },
  };
}

// ── API ──

// data: 위 저장소   stores: src/stores.js (매장 목록)   httpError(status, code, message)
function createInsightRoutes({ data, stores, now = () => Date.now(), httpError }) {
  async function storeInsights(storeId, from, top = TOP) {
    const [rows, vrows] = await Promise.all([data.daysSince(storeId, from), data.videoDaysSince(storeId, from)]);
    const a = aggregate(rows, vrows);
    const games = gameRows(a.games, top);
    const titles = await data.gameTitles(storeId, games.map((g) => g.id));
    for (const g of games) g.title = titles[g.id] || '(이름 없음)';
    return { summary: a.summary, hours: a.hours, daily: a.daily, menus: menuRows(a.menus, top), games };
  }

  // 전체 매장: 메뉴는 이름, 게임은 게임 이름으로 합침 (매장마다 ID가 달라서). stores = 그 메뉴·게임이 나온 매장 수
  function mergeAll(results) {
    const summary = { orders: 0, revenue: 0, items: 0, gameViews: 0, videoPlays: 0, activeDays: 0 };
    const hours = new Array(24).fill(0);
    const daily = new Map();
    const menus = new Map();
    const games = new Map();
    for (const r of results) {
      for (const k of Object.keys(summary)) summary[k] += num(r.summary[k]);
      r.hours.forEach((n, i) => { hours[i] += n; });
      for (const d of r.daily) {
        const cur = daily.get(d.date) || { date: d.date, orders: 0, revenue: 0, gameViews: 0, videoPlays: 0 };
        for (const k of ['orders', 'revenue', 'gameViews', 'videoPlays']) cur[k] += d[k];
        daily.set(d.date, cur);
      }
      for (const m of r.menus) {
        const k = norm(m.name);
        const cur = menus.get(k) || { key: k, name: m.name, category: m.category, qty: 0, revenue: 0, orders: 0, options: {}, stores: 0 };
        cur.qty += m.qty;
        cur.revenue += m.revenue;
        cur.orders += m.orders;
        cur.stores++;
        for (const o of m.options) cur.options[o.name] = (cur.options[o.name] || 0) + o.qty;
        menus.set(k, cur);
      }
      for (const g of r.games) {
        if (!g.title || g.title === '(이름 없음)') continue;
        const k = norm(g.title.replace(/ \(지운 게임\)$/, ''));
        const cur = games.get(k) || { id: k, title: g.title.replace(/ \(지운 게임\)$/, ''), views: 0, plays: 0, total: 0, stores: 0 };
        cur.views += g.views;
        cur.plays += g.plays;
        cur.total += g.total;
        cur.stores++;
        games.set(k, cur);
      }
    }
    summary.activeDays = [...daily.values()].filter((d) => d.orders || d.gameViews || d.videoPlays).length;
    return {
      summary,
      hours,
      daily: [...daily.values()].sort((a, b) => a.date.localeCompare(b.date)),
      menus: [...menus.values()]
        .map((m) => ({ ...m, options: topOptions(m.options) }))
        .sort((a, b) => b.qty - a.qty || b.revenue - a.revenue || a.name.localeCompare(b.name))
        .slice(0, TOP),
      games: [...games.values()].sort((a, b) => b.total - a.total || b.views - a.views || a.title.localeCompare(b.title)).slice(0, TOP),
    };
  }

  // 패드 쪽 (app.js가 /api/stats/* 를 넘김)
  async function route(req, path, ctx) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};

    if (path === '/api/stats/order' && req.method === 'POST') {
      const user = await ctx.requireStoreUser(req);
      if (user.pad !== true) throw httpError(403, 'PAD_ONLY', '손님 패드에서만 보낼 수 있어요.');
      ctx.rate(`stats-order:${user.uid || 'unknown'}`, 60, MIN, '통계 보고');
      const orderId = String(body.orderId || '');
      if (!ORDER_ID_RE.test(orderId)) throw httpError(400, 'INVALID_ORDER', '주문 ID가 올바르지 않아요.');
      const t = now();
      const result = await data.countOrder(user.store, orderId, (order) => {
        if (String(order.room || '') !== `#${user.room}`) throw httpError(403, 'OTHER_ROOM', '다른 방 주문이에요.');
        return { date: seoulDateKey(new Date(t)), hour: seoulHour(t), stats: summarizeOrder(order) };
      });
      if (result === 'missing') throw httpError(404, 'NO_ORDER', '없는 주문이에요.');
      return { ok: true, counted: result === 'counted' };
    }

    if (path === '/api/stats/report' && req.method === 'POST') {
      const user = await ctx.requireStoreUser(req);
      // 관리자 화면에서 연 건 손님 데이터가 아니라서 받기만 하고 안 셈 (패드가 다시 보내지 않게 200)
      if (user.pad !== true) return { ok: true, ignored: true };
      ctx.rate(`stats-report:${user.uid || 'unknown'}`, 30, 60 * MIN, '통계 보고');
      const raw = body.gameViews;
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw httpError(400, 'INVALID', '보고 값이 올바르지 않아요.');
      const entries = Object.entries(raw);
      if (entries.length > MAX_REPORT_GAMES) throw httpError(400, 'INVALID', '보고 값이 너무 많아요.');
      const views = {};
      for (const [id, n] of entries) {
        const c = Math.trunc(Number(n));
        if (!ID_RE.test(id) || !Number.isFinite(c) || c < 1 || c > 500) throw httpError(400, 'INVALID', '보고 값이 올바르지 않아요.');
        views[id] = c;
      }
      if (Object.keys(views).length) await data.addGameViews(user.store, seoulDateKey(new Date(now())), views);
      return { ok: true };
    }

    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  // 운영자 (app.js가 requireOps 뒤에 넘김)
  async function opsRoute(req, path) {
    if (path === '/api/ops/insights' && req.method === 'GET') {
      const q = req.query || {};
      const days = Math.min(90, Math.max(1, Math.trunc(Number(q.days)) || 30));
      const from = seoulDateKey(new Date(now() - (days - 1) * 86400 * 1000));
      const storeId = String(q.storeId || '');
      const list = await stores.listStores();
      if (storeId === 'all') {
        const active = list.filter((s) => s.status === 'active');
        const results = [];
        for (const s of active) results.push(await storeInsights(s.id, from, 100));
        return { storeId: 'all', name: '전체 매장', storeCount: active.length, from, days, ...mergeAll(results) };
      }
      const s = list.find((x) => x.id === storeId);
      if (!s) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      return { storeId: s.id, name: s.name, storeCount: 1, from, days, ...(await storeInsights(s.id, from)) };
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  return { route, opsRoute };
}

module.exports = {
  createFirestoreInsights, createMemoryInsights, createInsightRoutes, summarizeOrder, aggregate, seoulHour,
};
