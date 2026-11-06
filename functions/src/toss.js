'use strict';
// 토스 POS 연동 (64차) — 토스플레이스 Open API
//   문서: https://docs.tossplace.com/guide/pos-integration/open-api/intro.html
//   기본 주소 https://open-api.tossplace.com/api-public/openapi/v1, 헤더 x-access-key · x-secret-key · User-Agent(없으면 403 차단)
//   응답 { resultType: 'SUCCESS', success } / { resultType: 'FAIL', error: { errorCode, reason } }
//   매장(가맹점)마다 호출 제한 초당 10번(최대 100번 몰아서) — 넘으면 429
//
// 이 파일
//   createTossClient   진짜 토스 서버 호출 (키가 생기면 index.js에서 TOSS_ENABLED = true)
//   createFakeToss     가짜 토스 서버 — 키 없이 개발·시연용. 매장의 고도리 메뉴로 가짜 포스 상품을 만들고,
//                      문서에 적힌 거부 조건(없는 상품·품절·옵션 개수·같은 orderKey)을 흉내 냄
//   buildTossOrder     고도리 주문 문서 → 토스 '주문 생성' 요청 본문
//   verifyWebhook      웹훅 서명 확인 (HMAC-SHA256, 'v1=' + hex)
//
// ★ 진짜 키로 확인 전이라 추측한 부분: 임의 상품(AD_HOC)의 item.category 모양({ title }), 오류 코드 이름,
//   상품 목록 응답이 배열인지. 키를 받으면 테스트 가맹점에서 먼저 확인할 것.

const crypto = require('crypto');

const TOSS_BASE_URL = 'https://open-api.tossplace.com/api-public/openapi/v1';
const USER_AGENT = 'godori/1.0 (+https://godori-pad.web.app)';
const ORDER_KEY_PREFIX = 'godori-';

class TossError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

// ── 진짜 토스 서버 ──
function createTossClient({ accessKey, secretKey, fetchImpl = fetch, baseUrl = TOSS_BASE_URL, timeoutMs = 15000, sleep }) {
  const wait = sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));

  async function request(method, path, { query, body } = {}, retried = false) {
    const url = new URL(baseUrl + path);
    for (const [k, v] of Object.entries(query || {})) if (v != null) url.searchParams.set(k, String(v));
    let res;
    try {
      res = await fetchImpl(url.toString(), {
        method,
        headers: {
          'x-access-key': accessKey,
          'x-secret-key': secretKey,
          'content-type': 'application/json',
          'user-agent': USER_AGENT,
        },
        body: body == null ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      throw new TossError(502, 'TOSS_UNREACHABLE', '토스 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch (_) {}
    if (res.status === 429 && !retried) {
      // 매장별 호출 제한 — 한 번만 잠깐 기다렸다 다시
      const reset = Number(res.headers.get && res.headers.get('x-ratelimit-reset'));
      const ms = Number.isFinite(reset) ? Math.min(2000, Math.max(200, reset - Date.now())) : 1000;
      await wait(ms);
      return request(method, path, { query, body }, true);
    }
    if (res.ok && json && json.resultType === 'SUCCESS') return json.success;
    const err = (json && json.error) || {};
    const eventId = res.headers.get ? res.headers.get('x-toss-event-id') : null;
    if (eventId) console.warn('[토스] 실패', method, path, res.status, err.errorCode, 'x-toss-event-id', eventId);
    if (!json && res.status === 403) {
      throw new TossError(403, 'TOSS_BLOCKED', '토스 서버가 요청을 막았어요(HTML 403). User-Agent·호출 IP를 확인해야 해요.');
    }
    throw new TossError(res.status || 502, String(err.errorCode || `HTTP_${res.status}`),
      String(err.reason || `토스 서버 오류 (${res.status})`));
  }

  const m = (merchantId) => `/merchants/${encodeURIComponent(String(merchantId))}`;
  return {
    mode: 'live',
    getMerchant: (merchantId) => request('GET', m(merchantId)),
    async listCatalogItems(merchantId) {
      const all = [];
      for (let page = 1; page <= 20; page++) {
        const got = await request('GET', `${m(merchantId)}/catalog/items`, { query: { page, size: 500 } });
        const list = Array.isArray(got) ? got : (got && (got.items || got.content || got.list)) || [];
        all.push(...list);
        if (list.length < 500) break;
      }
      return all;
    },
    createOrder: (merchantId, body, { printOrderSheet = false } = {}) =>
      request('POST', `${m(merchantId)}/order/orders`, { query: { printOrderSheet }, body }),
  };
}

// ── 가짜 토스 서버 (개발용) ──
// 15자리 hex → 10진 숫자 글자 (토스 ID 형식 \d{1,19}에 맞춤, 같은 입력이면 항상 같은 값)
function numericId(seed) {
  const hex = crypto.createHash('sha1').update(String(seed)).digest('hex').slice(0, 15);
  return BigInt('0x' + hex).toString();
}

const asInt = (v) => {
  const n = typeof v === 'number' ? v : parseInt(String(v == null ? '' : v), 10);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};

// 고도리 메뉴 [{ id, name, price, category, isSoldOut, optionGroups: [{ groupName, isRequired, options: [{ name, price }] }] }]
// → 토스 카탈로그 상품 모양
function fakeCatalogFromMenus(menus) {
  return (menus || []).map((menu) => {
    const groups = Array.isArray(menu.optionGroups) ? menu.optionGroups : [];
    const name = String(menu.name || '이름 없음');
    return {
      id: numericId(`item:${menu.id}`),
      title: name,
      category: { id: numericId(`cat:${menu.category || ''}`), title: String(menu.category || '') },
      price: { title: name, priceType: 'FIXED', priceUnit: 1, priceValue: asInt(menu.price) },
      state: menu.isSoldOut === true ? 'SOLD_OUT' : 'ON_SALE',
      enabled: true,
      options: groups.map((g, gi) => ({
        id: numericId(`opt:${menu.id}:${gi}`),
        title: String(g.groupName || `옵션 ${gi + 1}`),
        required: g.isRequired === true,
        minChoices: g.isRequired === true ? 1 : 0,
        maxChoices: 1,
        choices: (Array.isArray(g.options) ? g.options : []).map((o, oi) => ({
          id: numericId(`choice:${menu.id}:${gi}:${oi}`),
          title: String(o.name || ''),
          priceValue: asInt(o.price),
          state: 'ON_SALE',
        })),
      })),
    };
  });
}

// sandbox: { catalog: async (merchantId) => items, addOrder: async (merchantId, order) => (같은 orderKey면 throw), merchant: async (merchantId) => {...} }
function createFakeToss({ sandbox, now = () => Date.now() }) {
  const fail = (code, message) => new TossError(400, code, message);
  return {
    mode: 'fake',
    async getMerchant(merchantId) {
      return (await sandbox.merchant(merchantId)) || { id: merchantId, name: '가짜 포스' };
    },
    listCatalogItems: (merchantId) => sandbox.catalog(merchantId),
    async createOrder(merchantId, body, { printOrderSheet = false } = {}) {
      const order = body && body.order;
      if (!order || !order.orderKey) throw fail('INVALID_REQUEST', 'orderKey가 없어요.');
      if (!Array.isArray(body.payments)) throw fail('INVALID_REQUEST', 'payments가 없어요.');
      if (!Array.isArray(order.lineItems) || !order.lineItems.length) throw fail('INVALID_REQUEST', '주문 내역이 없어요.');
      const items = new Map((await sandbox.catalog(merchantId)).map((i) => [String(i.id), i]));
      for (const li of order.lineItems) {
        if (!(li.quantity >= 1 && li.quantity <= 999)) throw fail('INVALID_REQUEST', '수량은 1~999개예요.');
        if (li.targetType !== 'ITEM') continue; // 임의 상품은 검사 없음
        const item = items.get(String(li.targetId));
        if (!item) throw fail('CATALOG_ITEM_NOT_FOUND', `포스에 없는 상품이에요. (${li.targetId})`);
        if (item.state === 'SOLD_OUT') throw fail('CATALOG_ITEM_SOLD_OUT', `포스에서 품절인 상품이에요: ${item.title}`);
        const choices = li.optionChoices || [];
        for (const opt of item.options || []) {
          const picked = choices.filter((c) => String(c.optionId) === String(opt.id)).length;
          if (picked < (opt.minChoices || 0) || (opt.maxChoices && picked > opt.maxChoices)) {
            throw fail('INVALID_OPTION_CHOICE_COUNT', `옵션 '${opt.title}' 선택 개수가 맞지 않아요. (${item.title})`);
          }
        }
        for (const c of choices) {
          const opt = (item.options || []).find((o) => String(o.id) === String(c.optionId));
          const choice = opt && (opt.choices || []).find((x) => String(x.id) === String(c.optionChoiceId));
          if (!choice) throw fail('CATALOG_OPTION_NOT_FOUND', `포스에 없는 옵션이에요. (${item.title})`);
          if (choice.state === 'SOLD_OUT') throw fail('CATALOG_OPTION_SOLD_OUT', `포스에서 품절인 옵션이에요: ${choice.title}`);
        }
      }
      // 운영자 페이지에서 읽기 쉽게: 포스 상품 옵션은 ID만 오므로 가짜 포스에 저장할 때 옵션 이름을 붙여 둠
      const lineItems = order.lineItems.map((li) => {
        if (li.targetType !== 'ITEM') return li;
        const item = items.get(String(li.targetId));
        return {
          ...li,
          optionChoices: (li.optionChoices || []).map((c) => {
            const opt = (item.options || []).find((o) => String(o.id) === String(c.optionId));
            const choice = (opt.choices || []).find((x) => String(x.id) === String(c.optionChoiceId));
            return { ...c, title: choice.title };
          }),
        };
      });
      const created = {
        id: numericId(`order:${merchantId}:${order.orderKey}`),
        merchantId,
        source: 'OPEN_API',
        orderState: 'OPENED',
        orderKey: order.orderKey,
        orderNumber: order.orderNumber || null,
        createdAt: new Date(now()).toISOString(),
        lineItems,
        memo: order.memo || null,
        chargePrice: order.chargePrice,
        payments: [],
        printOrderSheet: printOrderSheet === true,
      };
      await sandbox.addOrder(merchantId, created); // 같은 orderKey면 sandbox가 DUPLICATED_ORDER_KEY
      return created;
    },
  };
}

// ── 고도리 주문 → 토스 주문 생성 요청 ──
// order: Firestore 주문 문서 { room '#3', price, notes, lines: [{ menuId, name, category, basePrice, quantity, options: [{ group, name, price }] }] }
// menuMap: { 고도리 메뉴 ID: 토스 상품 ID }   catalogById: Map(토스 상품 ID → 상품)
// → { body: { order, payments: [] }, warnings: [문구] }   (결제는 손님이 카운터 포스에서 → payments 비움)
function buildTossOrder({ storeId, orderId, order, menuMap = {}, catalogById = new Map(), nowIso = new Date().toISOString() }) {
  const lines = Array.isArray(order.lines) ? order.lines : [];
  if (!lines.length) {
    throw new TossError(400, 'NO_LINES', '예전 패드에서 들어온 주문이라 포스로 보낼 수 없어요. 포스에 직접 입력해 주세요.');
  }
  if (lines.length > 100) throw new TossError(400, 'TOO_MANY_LINES', '한 주문에 메뉴가 100줄을 넘어요.');
  const warnings = [];
  let total = 0;
  const lineItems = lines.map((line) => {
    const name = String(line.name || '이름 없음').slice(0, 100);
    const base = Math.max(0, asInt(line.basePrice));
    const quantity = Math.min(999, Math.max(1, asInt(line.quantity)));
    const options = (Array.isArray(line.options) ? line.options : []).slice(0, 25);
    total += (base + options.reduce((s, o) => s + Math.max(0, asInt(o.price)), 0)) * quantity;
    const itemPrice = { title: name, priceType: 'FIXED', priceUnit: 1, priceValue: base, isTaxFree: false, taxInclusive: true };

    const itemId = menuMap[line.menuId];
    const item = itemId ? catalogById.get(String(itemId)) : null;
    if (itemId && !item) warnings.push(`'${name}'에 연결한 포스 상품이 포스에 없어요 — 이름만 보냈어요.`);
    if (item) {
      const picked = [];
      let allFound = true;
      for (const o of options) {
        const opt = (item.options || []).find((x) => x.title === o.group && (x.choices || []).some((c) => c.title === o.name))
          || (item.options || []).find((x) => (x.choices || []).some((c) => c.title === o.name));
        const choice = opt && opt.choices.find((c) => c.title === o.name);
        if (!choice) {
          allFound = false;
          break;
        }
        picked.push({ optionId: String(opt.id), optionChoiceId: String(choice.id), price: Math.max(0, asInt(o.price)), quantity: 1 });
      }
      if (allFound) {
        const posPrice = item.price && item.price.priceValue;
        if (posPrice != null && asInt(posPrice) !== base) warnings.push(`'${name}' 가격이 포스(${posPrice}원)와 고도리(${base}원)가 달라요.`);
        return { diningOption: 'HERE', targetType: 'ITEM', targetId: String(item.id), itemPrice, quantity, optionChoices: picked };
      }
      warnings.push(`'${name}'의 옵션 이름이 포스 옵션과 달라서 이름만 보냈어요.`);
    }
    // 연결 안 된 메뉴 → 임의 상품(AD_HOC): 포스 매출에는 이 이름으로 잡힘
    return {
      diningOption: 'HERE',
      targetType: 'AD_HOC',
      item: { title: name, category: { title: String(line.category || '고도리 주문').slice(0, 50) } },
      itemPrice,
      quantity,
      optionChoices: options.map((o) => ({
        option: { title: String(o.group || '옵션').slice(0, 50) },
        title: String(o.name || '').slice(0, 50),
        price: Math.max(0, asInt(o.price)),
        quantity: 1,
      })),
    };
  });

  const docTotal = asInt(order.price);
  if (docTotal && docTotal !== total) warnings.push(`합계가 패드(${docTotal}원)와 계산 값(${total}원)이 달라요 — 계산 값으로 보냈어요.`);
  const tax = Math.round(total / 11); // 부가세 포함 가격 기준
  const room = String(order.room || '').replace(/^#/, '');
  const notes = String(order.notes || '').trim();
  const memo = [`[고도리] ${room ? `${room}번 방` : '패드 주문'}`, notes && notes !== '추가사항 없음' ? `요청: ${notes}` : '']
    .filter(Boolean).join(' · ');
  return {
    warnings,
    body: {
      order: {
        orderKey: orderKeyOf(storeId, orderId),
        orderNumber: (room ? `${room}번 방` : '패드').slice(0, 64),
        lineItems,
        chargePrice: {
          listPrice: total, discountAmount: 0, tipAmount: 0, serviceChargeAmount: 0,
          taxAmount: tax, supplyAmount: total - tax, taxExemptAmount: 0, totalAmount: total,
        },
        memo: memo.slice(0, 1000),
        openedAt: nowIso,
      },
      payments: [],
    },
  };
}

const orderKeyOf = (storeId, orderId) => `${ORDER_KEY_PREFIX}${storeId}-${orderId}`;

// 'godori-<매장>-<주문ID>' → { storeId, orderId } (매장 아이디에 '-'가 있어도 마지막 '-' 뒤가 주문 ID)
function parseOrderKey(key) {
  const m = /^godori-([a-z0-9][a-z0-9-]{2,29})-([A-Za-z0-9]{1,40})$/.exec(String(key || ''));
  return m ? { storeId: m[1], orderId: m[2] } : null;
}

// 웹훅 서명: HMAC-SHA256(secret, `${x-toss-timestamp}.${원본 본문}`) → 'v1=' + hex
function signWebhook(secret, timestamp, rawBody) {
  const mac = crypto.createHmac('sha256', String(secret));
  mac.update(`${timestamp}.`);
  mac.update(Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody == null ? '' : rawBody), 'utf8'));
  return `v1=${mac.digest('hex')}`;
}

function verifyWebhook({ secret, headers, rawBody, now = Date.now(), toleranceMs = 5 * 60 * 1000 }) {
  const ts = String(headers['x-toss-timestamp'] || '');
  const sig = String(headers['x-toss-signature'] || '');
  if (!secret || !/^\d{10,16}$/.test(ts) || !sig) return false;
  if (Math.abs(now - Number(ts)) > toleranceMs) return false;
  const want = Buffer.from(signWebhook(secret, ts, rawBody));
  return sig.split(',').map((s) => s.trim()).some((s) => {
    const got = Buffer.from(s);
    return got.length === want.length && crypto.timingSafeEqual(got, want);
  });
}

// 관리자 웹 메뉴 연결 화면에 보낼 모양 (필요한 칸만)
function catalogView(items) {
  return (items || []).map((i) => ({
    id: String(i.id),
    title: String(i.title || ''),
    category: (i.category && i.category.title) || '',
    price: i.price && i.price.priceValue != null ? asInt(i.price.priceValue) : null,
    soldOut: i.state === 'SOLD_OUT',
    enabled: i.enabled !== false,
    options: (i.options || []).map((o) => ({
      title: String(o.title || ''),
      choices: (o.choices || []).map((c) => String(c.title || '')),
    })),
  }));
}

module.exports = {
  TOSS_BASE_URL,
  USER_AGENT,
  TossError,
  createTossClient,
  createFakeToss,
  fakeCatalogFromMenus,
  numericId,
  buildTossOrder,
  orderKeyOf,
  parseOrderKey,
  signWebhook,
  verifyWebhook,
  catalogView,
};
