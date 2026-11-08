'use strict';
// 고도리 관리자 웹이 쓰는 BGG(보드게임긱) 조회 API.
// 게임 데이터 저장은 지금처럼 앱(Flutter)이 Firestore/Storage에 직접 하고, 이 서버는 BGG에서
// 정보·사진을 "가져오는" 일만 한다. (BGG는 브라우저에서 직접 부를 수 없어서 서버가 대신 부른다)
//
//   GET  /api/health              상태 확인 (로그인 불필요)
//   POST /api/auth/store-login    { storeId, password, room, pin? } -> { token, role, store, room } | { needPin }  패드 로그인 (47차)
//   POST /api/auth/login          { storeId, password } -> { token }  관리자 웹 로그인
//   POST /api/store/passwords     (관리자) { padPassword?, pin?, webPassword? }  매장 비밀번호 바꾸기
//   POST /api/admin/migrate-legacy { legacyPassword, storeId, storeName, padPassword }  예전 데이터를 매장으로 복사 (한 번)
//   GET  /api/stores/check-id?id=  아이디 쓸 수 있는지 / POST /api/stores/signup  사장님 가입 신청 (48차, 승인 대기로 만들어짐)
//   POST /api/usage/report        (패드·관리자) { reads }  앱이 센 Firestore 읽기 수 보고
//   POST /api/auth/verify-exit    (패드·관리자) { password }  패드 로그아웃 전 확인 — 패드 비밀번호 또는 관리자 PIN (55차)
//   POST /api/store/features      (관리자) { adminDashboard }  패드 관리자 대시보드 켜기·끄기 (59차, tossPos는 운영자만)
//   /api/ops/*                    운영자 페이지 (로그인, 매장 목록·승인·정지·삭제, 이용 통계) — 아래 opsRoute
//   GET  /api/bgg/search?q=이름     이름으로 검색 -> { results: [{ id, name, yearPublished, thumbnail }] }
//   GET  /api/bgg/lookup?id=13     geek ID 상세 -> { geekId, name, bggName, minPlayers, maxPlayers, recommendedPlayers, weight, rank, difficulty }
//   GET  /api/bgg/image?id=13      사진 -> { dataUrl, contentType }
//   POST /api/bgg/details          { ids: [...] } 여러 개 상세(대용량 추가용, 한 번에 최대 30개) -> { games: [...], missing: [...] }
//   /api/video/*                   룰 설명 영상(Cloudflare R2) — 자세한 건 src/video.js
//   /api/toss/*, /api/ops/toss/*   토스 POS 연동 (64차) — 자세한 건 src/toss-routes.js
//   /api/stats/*, /api/ops/insights  매장 통계 — 인기 메뉴·인기 게임 (65차) — 자세한 건 src/insights.js
//   /api/translate/sync           (관리자) 메뉴·공지·이벤트 자동 번역 (83차) — 자세한 건 src/translate.js
//
// 로그인 흐름 (Firebase Authentication, 47차부터 매장별)
//   1) 패드: 매장 아이디 + 패드 비밀번호 + 방 번호(관리자는 0 → PIN 한 번 더) / 관리자 웹: 매장 아이디 + 비밀번호
//   2) 서버가 stores/{매장}/private/account 와 비교 (보안 규칙상 앱에서 읽을 수 없음)
//   3) 맞으면 커스텀 토큰: 패드 { pad: true, store, room } / 관리자 { admin: true, store } -> 앱이 signInWithCustomToken
//      (Firebase가 로그인을 기기에 저장해서 다음에 켤 때 자동 로그인)
//   4) Firestore/Storage 보안 규칙은 token.store 가 그 매장인지, admin·pad·room 으로 권한을 나눔
// /api/bgg/* 와 영상 올리기·지우기는 그 매장 관리자만, /api/video/play-url 은 그 매장 패드·관리자.

const crypto = require('crypto');
const { STORE_ID_RE, MAX_ROOMS, RESERVED_IDS, STATUSES, cleanStoreId, hashSecret, checkSecret, secretOf, safeEqual, statusError, seoulDateKey, OWNER_FEATURES, cleanFeatures } = require('./stores');

const MIN = 60 * 1000;
const IMAGE_MAX_BYTES = 1.5 * 1024 * 1024;
const DETAILS_MAX_IDS = 30;
// 로그인 실패 제한: 같은 IP 15분에 5번, 전체 1시간에 30번 틀리면 잠시 잠금
const LOGIN_LIMITS = [
  { key: (ip) => `ip:${ip}`, max: 5, windowMs: 15 * MIN },
  { key: () => 'global', max: 30, windowMs: 60 * MIN },
];

// 난이도: BGG geek weight 구간 (월정액권 앱과 같은 기준·색 — 매장 난이도 스티커 색)
const DIFFICULTY_BUCKETS = [
  { max: 1.3, label: '매우쉬움', color: '#00a1e9' },
  { max: 1.6, label: '쉬움', color: '#23ac3a' },
  { max: 2.1, label: '보통', color: '#f29700' },
  { max: 2.6, label: '어려움', color: '#ea5417' },
  { max: 3.1, label: '매우어려움', color: '#d80051' },
];
const DIFFICULTY_EXPERT = { label: '전문', color: '#231917' };
function difficultyFromWeight(weight) {
  if (weight == null || !Number.isFinite(weight)) return null;
  for (const b of DIFFICULTY_BUCKETS) if (weight < b.max) return { label: b.label, color: b.color };
  return { ...DIFFICULTY_EXPERT };
}

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function bggFail(e) {
  const code = e && e.code;
  if (code === 'BGG_NOT_FOUND') return httpError(404, code, 'BGG에서 게임을 찾을 수 없어요.');
  if (code === 'BGG_NO_IMAGE') return httpError(422, code, '이 게임은 BGG에 등록된 사진이 없어요. 사진을 직접 올려 주세요.');
  if (code === 'BGG_IMAGE_TOO_LARGE') return httpError(413, code, 'BGG 사진 용량이 너무 커요. 사진을 직접 올려 주세요.');
  if (code === 'BGG_IMAGE_UNSUPPORTED_TYPE') return httpError(415, code, '지원하지 않는 사진 형식이에요. 사진을 직접 올려 주세요.');
  if (code === 'BGG_RELAY_OFFLINE') return httpError(503, code, 'BGG 중계 설정이 없어요. BGG 비밀값 등록을 먼저 해 주세요.');
  console.error('[BGG 연결 실패]', e && e.message, e);
  return httpError(502, 'BGG_UNAVAILABLE', 'BGG(보드게임긱)에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
}

function detailView(d) {
  return {
    geekId: String(d.id),
    name: d.name,
    bggName: d.bggName && d.bggName !== d.name ? d.bggName : null,
    minPlayers: d.minPlayers,
    maxPlayers: d.maxPlayers,
    recommendedPlayers: d.recommendedPlayers || null,
    weight: d.weight ?? null,
    rank: d.rank ?? null,
    difficulty: difficultyFromWeight(d.weight),
    // 플레이 시간(분, BGG 박스 기준) — 관리자 웹이 소요시간 글자로 바꿔 저장
    minPlayTime: d.minPlayTime ?? null,
    maxPlayTime: d.maxPlayTime ?? null,
    playingTime: d.playingTime ?? null,
  };
}

// 인스턴스 안에서만 세는 간단한 횟수 제한 (함수 인스턴스 수 자체도 index.js에서 제한함)
function createLimiter(now) {
  const hits = new Map();
  return function limit(key, max, windowMs) {
    const t = now();
    const list = (hits.get(key) || []).filter((x) => t - x < windowMs);
    if (list.length >= max) {
      hits.set(key, list);
      return false;
    }
    list.push(t);
    hits.set(key, list);
    return true;
  };
}

// 로컬 개발(flutter run -d chrome = localhost)과 배포된 사이트(관리자 웹 godori-pad, 운영자 godori-ops, 예전 platform6-boardpad)에서만 허용 (49차)
const ALLOWED_ORIGIN_RE = /^(https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?|https:\/\/(platform6-boardpad|godori-pad|godori-ops)\.(web\.app|firebaseapp\.com))$/;

// 요청한 쪽 IP (Hosting을 거치면 x-forwarded-for 맨 앞이 손님 IP). 위조될 수 있어서 전체 제한도 같이 둔다.
function clientIp(headers) {
  const xff = String(headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xff || 'unknown';
}

// stores:           매장 계정 (src/stores.js createFirestoreStores / createMemoryStores)
// getLegacySecrets: async () => ({ pin, webPassword })   예전 settings/adminPin (데이터 옮기기 확인용)
// verifyIdToken:    async (idToken) => 디코딩된 토큰 (틀리면 throw)
// createToken:      async (uid, claims) => 커스텀 토큰 문자열
// attempts:         로그인 실패 기록 (src/attempts.js)
// video:            룰 영상 API (src/video.js createVideoApi). 없으면 /api/video/* 는 503
// ops:              운영자 계정 (src/ops.js)   monitoring: 프로젝트 전체 사용량 (src/ops.js createMonitoring, 없으면 안내)
// revokeStoreTokens: async (storeId) => 그 매장 패드·관리자 로그인 끊기 (정지·거절할 때)
// toss:             토스 POS 연동 API (src/toss-routes.js createTossRoutes). 없으면 /api/toss/* 는 503
// insights:         매장 통계 API (src/insights.js createInsightRoutes, 65차). 없으면 /api/stats/* 는 503
// translate:        자동 번역 API (src/translate.js createTranslateRoutes, 83차). 없으면 /api/translate/* 는 503
function createHandler({
  bgg, stores, getLegacySecrets = async () => ({}), verifyIdToken, createToken, attempts, video = null,
  ops = null, monitoring = null, revokeStoreTokens = async () => {}, now = () => Date.now(), toss = null, insights = null,
  translate = null,
}) {
  const limit = createLimiter(now);

  // 매장 상태(운영 중인지) — 요청마다 문서를 읽지 않게 1분 기억
  const statusCache = new Map();
  async function storeStatus(storeId) {
    const hit = statusCache.get(storeId);
    if (hit && now() - hit.at < MIN) return hit.status;
    const status = await stores.getStatus(storeId);
    statusCache.set(storeId, { status, at: now() });
    return status;
  }

  // 이용량 기록은 실패해도 요청은 그대로
  function recordUsage(storeId, fields) {
    return Promise.resolve()
      .then(() => stores.recordUsage(storeId, fields))
      .catch((e) => console.warn('[이용량] 기록 실패', storeId, e && e.message));
  }

  // 로그인한 사용자의 토큰 확인 -> 디코딩된 토큰
  async function requireUser(req) {
    const m = /^Bearer\s+(.+)$/i.exec(String(req.headers.authorization || ''));
    if (!m) throw httpError(401, 'UNAUTHORIZED', '로그인이 필요해요. 다시 로그인해 주세요.');
    let decoded;
    try {
      decoded = await verifyIdToken(m[1].trim());
    } catch (_) {
      throw httpError(401, 'UNAUTHORIZED', '로그인이 만료됐어요. 다시 로그인해 주세요.');
    }
    if (!decoded) throw httpError(401, 'UNAUTHORIZED', '로그인이 필요해요. 다시 로그인해 주세요.');
    return decoded;
  }

  // 매장 아이디로 로그인한 패드·관리자 (예전 익명 로그인·매장 없는 관리자 토큰은 다시 로그인)
  async function requireStoreUser(req) {
    const decoded = await requireUser(req);
    if (typeof decoded.store !== 'string' || !STORE_ID_RE.test(decoded.store)) {
      throw httpError(403, 'RELOGIN', '매장 아이디로 다시 로그인해 주세요.');
    }
    const status = await storeStatus(decoded.store);
    if (status === null) throw httpError(403, 'RELOGIN', '없는 매장이에요. 다시 로그인해 주세요.');
    const blocked = statusError(status);
    if (blocked) throw blocked;
    return decoded;
  }

  async function requireOps(req) {
    const decoded = await requireUser(req);
    if (decoded.ops !== true) throw httpError(403, 'FORBIDDEN', '운영자만 쓸 수 있어요.');
    return decoded;
  }

  async function requireAdmin(req) {
    const decoded = await requireStoreUser(req);
    if (decoded.admin !== true) throw httpError(403, 'FORBIDDEN', '관리자만 쓸 수 있어요.');
    return decoded;
  }

  // ── 로그인 실패 제한 (같은 IP 15분 5번, 전체 1시간 30번) ──
  async function checkLock(ip) {
    for (const l of LOGIN_LIMITS) {
      if (await attempts.isLocked(l.key(ip), l.max, l.windowMs)) {
        throw httpError(429, 'TOO_MANY', '비밀번호를 너무 많이 틀렸어요. 잠시 뒤에 다시 시도해 주세요.');
      }
    }
  }
  async function fail(ip, code, message) {
    for (const l of LOGIN_LIMITS) await attempts.recordFail(l.key(ip), l.windowMs);
    return httpError(401, code, message);
  }

  function textField(v, what, max = 100) {
    const s = typeof v === 'string' ? v.trim() : '';
    if (!s) throw httpError(400, 'EMPTY_PASSWORD', `${what}을 입력해 주세요.`);
    if (s.length > max) throw httpError(400, 'INVALID_PASSWORD', `${what}이 너무 길어요.`);
    return s;
  }

  // 아이디·비밀번호 확인 (틀리면 어느 쪽이 틀렸는지 알려 주지 않음)
  async function checkStorePassword(ip, storeId, given, kind) {
    const account = await stores.getAccount(storeId);
    const ok = account ? checkSecret(given, secretOf(account, kind)) : false;
    if (ok === null) {
      throw httpError(503, 'NO_PASSWORD',
        kind === 'pad' ? '이 매장은 패드 비밀번호가 아직 없어요. 관리자 웹 → 매장 설정에서 만들어 주세요.'
                       : '이 매장은 관리자 비밀번호가 설정되어 있지 않아요.');
    }
    if (!ok) throw await fail(ip, 'WRONG_PASSWORD', '아이디 또는 비밀번호가 올바르지 않습니다.');
    // 비밀번호가 맞은 뒤에만 승인 대기·정지 여부를 알려 줌
    const blocked = statusError(account.status);
    if (blocked) throw blocked;
    return account;
  }

  // 손님 패드 로그인: { storeId, password, room, pin? }
  //   room 1~방 개수 → 그 방 손님 패드 토큰 { pad: true, store, room }
  //   room 0 → 비밀번호가 맞으면 { needPin: true } → pin까지 보내면 관리자 토큰 { admin: true, store }
  async function storeLogin(req) {
    const body = req.body || {};
    const storeId = cleanStoreId(body.storeId);
    const password = textField(body.password, '비밀번호');
    const room = Number(body.room);
    if (!Number.isInteger(room) || room < 0 || room > MAX_ROOMS) {
      throw httpError(400, 'INVALID_ROOM', '방 번호를 확인해 주세요. (관리자는 0)');
    }
    const ip = clientIp(req.headers);
    await checkLock(ip);
    const account = await checkStorePassword(ip, storeId, password, 'pad');

    if (room === 0) {
      // 59차: 매장이 패드 관리자 대시보드를 끈 경우 (비밀번호가 맞은 뒤에만 알려 줌)
      if (account.features && account.features.adminDashboard === false) {
        throw httpError(403, 'DASHBOARD_OFF', '이 매장은 패드 관리자 대시보드(방 번호 0)를 쓰지 않아요. 주문 관리는 관리자 웹에서 해 주세요.');
      }
      const pin = typeof body.pin === 'string' ? body.pin.trim() : '';
      if (!pin) return { needPin: true, store: storeId, storeName: account.name };
      if (pin.length > 20) throw httpError(400, 'INVALID_PASSWORD', 'PIN이 너무 길어요.');
      const ok = checkSecret(pin, secretOf(account, 'pin'));
      if (ok === null) throw httpError(503, 'NO_PIN', '이 매장은 관리자 PIN이 설정되어 있지 않아요.');
      if (!ok) throw await fail(ip, 'WRONG_PIN', 'PIN이 올바르지 않습니다.');
      await attempts.reset(LOGIN_LIMITS[0].key(ip));
      await recordUsage(storeId, { logins: 1 });
      return { role: 'admin', store: storeId, storeName: account.name, room: 0,
        token: await createToken(`admin-pad.${storeId}`, { admin: true, store: storeId }) };
    }

    const count = await stores.getRoomCount(storeId);
    if (room > count) throw httpError(400, 'INVALID_ROOM', `이 매장의 방 번호는 1~${count}번이에요. (관리자는 0)`);
    await attempts.reset(LOGIN_LIMITS[0].key(ip));
    await recordUsage(storeId, { logins: 1 });
    return { role: 'pad', store: storeId, storeName: account.name, room,
      token: await createToken(`pad.${storeId}.${room}`, { pad: true, store: storeId, room }) };
  }

  // 관리자 웹 로그인: { storeId, password } — webPassword (없으면 PIN)
  async function webLogin(req) {
    const body = req.body || {};
    const storeId = cleanStoreId(body.storeId);
    const password = textField(body.password, '비밀번호');
    const ip = clientIp(req.headers);
    await checkLock(ip);
    const account = await checkStorePassword(ip, storeId, password, 'web');
    await attempts.reset(LOGIN_LIMITS[0].key(ip));
    await recordUsage(storeId, { logins: 1 });
    return { role: 'admin', store: storeId, storeName: account.name,
      token: await createToken(`admin-web.${storeId}`, { admin: true, store: storeId }) };
  }

  // ── 가입 (48차) ──
  // 같은 IP 1시간 3번, 전체 하루 30번까지 신청 (실패 기록 저장소를 횟수 세기에 같이 씀)
  const SIGNUP_LIMITS = [
    { key: (ip) => `signup:${ip}`, max: 3, windowMs: 60 * MIN },
    { key: () => 'signup:global', max: 30, windowMs: 24 * 60 * MIN },
  ];

  function checkNewId(raw) {
    const storeId = cleanStoreId(raw);
    if (RESERVED_IDS.includes(storeId)) throw httpError(400, 'RESERVED_ID', '이 아이디는 쓸 수 없어요. 다른 아이디를 골라 주세요.');
    return storeId;
  }

  async function checkId(req) {
    rate(`checkid:${clientIp(req.headers)}`, 30, MIN, '아이디 확인');
    const storeId = checkNewId((req.query || {}).id);
    return { id: storeId, available: !(await stores.exists(storeId)) };
  }

  // { storeId, storeName, ownerName, phone, webPassword, agree } → 승인 대기 매장
  async function signup(req) {
    const body = req.body || {};
    const storeId = checkNewId(body.storeId);
    const name = String(body.storeName || '').trim();
    const ownerName = String(body.ownerName || '').trim();
    const phone = String(body.phone || '').trim();
    const webPassword = String(body.webPassword || '').trim();
    if (!name || name.length > 40) throw httpError(400, 'INVALID_NAME', '매장 이름을 1~40자로 입력해 주세요.');
    if (!ownerName || ownerName.length > 30) throw httpError(400, 'INVALID_OWNER', '사장님 이름을 입력해 주세요.');
    if (!/^[0-9+\-\s()]{9,20}$/.test(phone)) throw httpError(400, 'INVALID_PHONE', '연락처를 확인해 주세요. (승인 연락용)');
    if (webPassword.length < 8 || webPassword.length > 100) throw httpError(400, 'INVALID_PASSWORD', '관리자 웹 비밀번호는 8자 이상으로 정해 주세요.');
    if (body.agree !== true) throw httpError(400, 'NO_AGREE', '가입 승인 연락을 위한 이름·연락처 저장에 동의해 주세요.');
    const ip = clientIp(req.headers);
    for (const l of SIGNUP_LIMITS) {
      if (await attempts.isLocked(l.key(ip), l.max, l.windowMs)) {
        throw httpError(429, 'TOO_MANY', '가입 신청이 너무 많아요. 잠시 뒤에 다시 시도해 주세요.');
      }
    }
    for (const l of SIGNUP_LIMITS) await attempts.recordFail(l.key(ip), l.windowMs);
    await stores.createSignup({
      storeId,
      name,
      profile: { ownerName, phone },
      account: { webPasswordHash: hashSecret(webPassword) },
    });
    return { ok: true, store: storeId, status: 'pending' };
  }

  // ── 패드 로그아웃 확인 (55차): 홈 왼쪽 위를 길게 누르면 묻는 비밀번호 — 패드 비밀번호 또는 관리자 PIN ──
  // 손님이 우연히 길게 눌러 로그아웃되지 않게. 틀리면 로그인과 같은 실패 횟수에 셈
  async function verifyExit(req) {
    const user = await requireStoreUser(req);
    const given = textField((req.body || {}).password, '비밀번호');
    const ip = clientIp(req.headers);
    await checkLock(ip);
    const account = (await stores.getAccount(user.store)) || {};
    const ok = checkSecret(given, secretOf(account, 'pad')) === true || checkSecret(given, secretOf(account, 'pin')) === true;
    if (!ok) throw await fail(ip, 'WRONG_PASSWORD', '비밀번호가 올바르지 않습니다.');
    await attempts.reset(LOGIN_LIMITS[0].key(ip));
    return { ok: true };
  }

  // ── 매장 기능 켜기·끄기 (59차) — 사장님은 adminDashboard만, tossPos는 운영자 페이지에서 ──
  async function setStoreFeatures(req) {
    const user = await requireAdmin(req);
    rate(`features:${user.store}`, 20, MIN, '설정 변경');
    const fields = cleanFeatures(req.body, OWNER_FEATURES);
    return { ok: true, store: user.store, features: await stores.setFeatures(user.store, fields) };
  }

  // ── 앱이 센 Firestore 읽기 보고 (매장별 사용량 추정용) ──
  async function usageReport(req) {
    const user = await requireStoreUser(req);
    rate(`usage:${user.uid || 'unknown'}`, 20, 60 * MIN, '사용량 보고');
    const reads = Math.trunc(Number((req.body || {}).reads));
    if (!Number.isFinite(reads) || reads < 0 || reads > 50000) throw httpError(400, 'INVALID', '보고 값이 올바르지 않아요.');
    if (reads > 0) await recordUsage(user.store, { clientReads: reads });
    return { ok: true };
  }

  // ── 운영자 페이지 (48차) ──
  async function opsRoute(req, path) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    if (!ops) throw httpError(503, 'NO_OPS', '운영자 기능이 연결되지 않았어요.');

    if (path === '/api/ops/login' && req.method === 'POST') {
      const given = textField(body.password, '비밀번호');
      const ip = clientIp(req.headers);
      await checkLock(ip);
      const acc = (await ops.getAccount()) || {};
      const ok = checkSecret(given, { hash: acc.passwordHash, plain: acc.password });
      if (ok === null) throw httpError(503, 'NO_PASSWORD', '운영자 비밀번호가 없어요. Firebase 콘솔 → Firestore에 _ops/account 문서(password 필드)를 만들어 주세요.');
      if (!ok) throw await fail(ip, 'WRONG_PASSWORD', '비밀번호가 올바르지 않습니다.');
      await attempts.reset(LOGIN_LIMITS[0].key(ip));
      return { token: await createToken('ops', { ops: true }) };
    }

    await requireOps(req);
    rate('ops', 120, MIN, '운영자 요청');

    if (path === '/api/ops/stores' && req.method === 'GET') {
      const list = await stores.listStores();
      const order = { pending: 0, active: 1, suspended: 2, rejected: 3 };
      list.sort((a, b) => (order[a.status] - order[b.status]) || String(a.id).localeCompare(String(b.id)));
      return { stores: list };
    }
    if (path === '/api/ops/store-status' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      const status = String(body.status || '');
      if (!STATUSES.includes(status) || status === 'pending') throw httpError(400, 'INVALID_STATUS', '상태는 active·suspended·rejected 중 하나예요.');
      await stores.setStatus(storeId, status);
      statusCache.delete(storeId);
      if (status !== 'active') {
        // 이미 로그인한 패드·관리자도 끊기 (토큰 갱신이 막혀 1시간 안에 로그아웃, 규칙은 바로 막음)
        await Promise.resolve(revokeStoreTokens(storeId)).catch((e) => console.warn('[운영] 로그인 끊기 실패', storeId, e && e.message));
      }
      return { ok: true, store: storeId, status };
    }
    // 59차: 매장 기능 켜기·끄기 { storeId, adminDashboard?, tossPos? }
    if (path === '/api/ops/store-features' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      const fields = cleanFeatures(body);
      return { ok: true, store: storeId, features: await stores.setFeatures(storeId, fields) };
    }
    if (path === '/api/ops/store-delete' && req.method === 'POST') {
      const storeId = cleanStoreId(body.storeId);
      await stores.deleteSignup(storeId);
      statusCache.delete(storeId);
      return { ok: true };
    }
    if (path === '/api/ops/usage' && req.method === 'GET') {
      const days = Math.min(90, Math.max(1, Math.trunc(Number((req.query || {}).days)) || 30));
      const from = seoulDateKey(new Date(now() - (days - 1) * 86400 * 1000));
      const list = await stores.listStores();
      const out = [];
      for (const s of list) {
        const rows = await stores.usageSince(s.id, from);
        const totals = {};
        for (const r of rows) for (const [k, v] of Object.entries(r)) if (k !== 'date' && typeof v === 'number') totals[k] = (totals[k] || 0) + v;
        out.push({ id: s.id, name: s.name, status: s.status, r2Bytes: s.r2Bytes, r2Files: s.r2Files, totals, days: rows.sort((a, b) => String(a.date).localeCompare(String(b.date))) });
      }
      return { from, days, stores: out };
    }
    if (path === '/api/ops/project-usage' && req.method === 'GET') {
      const days = Math.min(90, Math.max(1, Math.trunc(Number((req.query || {}).days)) || 30));
      if (!monitoring) return { days: [], totals: {}, errors: { all: '프로젝트 사용량 연결이 없어요.' } };
      try {
        return await monitoring.summary(days);
      } catch (e) {
        return { days: [], totals: {}, errors: { all: String((e && e.message) || e).slice(0, 200) } };
      }
    }
    if (path === '/api/ops/recount-r2' && req.method === 'POST') {
      return stores.recountR2(cleanStoreId(body.storeId));
    }
    if (path === '/api/ops/password' && req.method === 'POST') {
      const v = String(body.password || '').trim();
      if (v.length < 10 || v.length > 100) throw httpError(400, 'INVALID_PASSWORD', '운영자 비밀번호는 10자 이상으로 정해 주세요.');
      await ops.setPasswordHash(hashSecret(v));
      return { ok: true };
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  // 관리자 웹 '매장 설정': 비밀번호 바꾸기 { padPassword?, pin?, webPassword? }
  async function setPasswords(req) {
    const user = await requireAdmin(req);
    rate(`pw:${user.store}`, 10, MIN, '비밀번호 변경');
    const body = req.body || {};
    const fields = {};
    if (body.padPassword != null) {
      const v = String(body.padPassword).trim();
      if (v.length < 4 || v.length > 50) throw httpError(400, 'INVALID_PASSWORD', '패드 비밀번호는 4~50자로 정해 주세요.');
      fields.padPasswordHash = hashSecret(v);
    }
    if (body.pin != null) {
      const v = String(body.pin).trim();
      if (!/^\d{4,10}$/.test(v)) throw httpError(400, 'INVALID_PIN', '관리자 PIN은 숫자 4~10자리로 정해 주세요.');
      fields.pinHash = hashSecret(v);
    }
    if (body.webPassword != null) {
      const v = String(body.webPassword).trim();
      if (v.length < 6 || v.length > 100) throw httpError(400, 'INVALID_PASSWORD', '관리자 웹 비밀번호는 6자 이상으로 정해 주세요.');
      fields.webPasswordHash = hashSecret(v);
    }
    if (!Object.keys(fields).length) throw httpError(400, 'NOTHING', '바꿀 비밀번호를 입력해 주세요.');
    await stores.setSecrets(user.store, fields);
    return { ok: true, changed: Object.keys(fields).map((k) => k.replace(/Hash$/, '')) };
  }

  // 예전(매장 1곳) 데이터를 새 매장으로 복사: { legacyPassword, storeId, storeName, padPassword }
  // legacyPassword = 예전 관리자 웹 비밀번호(없으면 예전 PIN). 딱 한 번만 됨 ("매장 데이터 옮기기.ps1")
  async function migrateLegacy(req) {
    const body = req.body || {};
    const storeId = cleanStoreId(body.storeId);
    const given = textField(body.legacyPassword, '예전 관리자 비밀번호');
    const name = String(body.storeName || '').trim().slice(0, 40);
    const padPassword = String(body.padPassword || '').trim();
    if (padPassword.length < 4 || padPassword.length > 50) throw httpError(400, 'INVALID_PASSWORD', '패드 비밀번호는 4~50자로 정해 주세요.');
    const ip = clientIp(req.headers);
    await checkLock(ip);
    const legacy = (await getLegacySecrets()) || {};
    const pin = String(legacy.pin || '');
    const expected = String(legacy.webPassword || '') || pin;
    if (!expected) throw httpError(503, 'NO_PASSWORD', '예전 관리자 비밀번호(settings/adminPin)가 없어요.');
    if (!safeEqual(given, expected)) throw await fail(ip, 'WRONG_PASSWORD', '예전 관리자 비밀번호가 올바르지 않습니다.');
    const account = { padPasswordHash: hashSecret(padPassword) };
    if (pin) account.pin = pin;
    if (legacy.webPassword) account.webPassword = String(legacy.webPassword);
    const copied = await stores.migrateLegacy({ storeId, name, account });
    return { ok: true, store: storeId, copied };
  }

  function rate(key, max, windowMs, what = 'BGG 요청') {
    if (!limit(key, max, windowMs)) throw httpError(429, 'TOO_MANY', `${what}이 너무 잦아요. 잠시 후 다시 시도해 주세요.`);
  }

  async function videoRoute(req, path) {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    if (path === '/api/video/play-url' && req.method === 'GET') {
      const user = await requireStoreUser(req);
      rate(`play:${user.uid || 'unknown'}`, 30, MIN, '영상 요청');
      rate('play', 600, MIN, '영상 요청');
      if (!video) throw httpError(503, 'R2_NOT_CONNECTED', '영상 저장소가 아직 연결되지 않았어요.');
      return video.playUrl(req.query || {}, user.store);
    }
    const routes = {
      '/api/video/upload-url': 'uploadUrl',
      '/api/video/confirm': 'confirm',
      '/api/video/delete': 'remove',
    };
    if (routes[path] && req.method === 'POST') {
      const user = await requireAdmin(req);
      rate(`video-admin:${user.store}`, 120, MIN, '영상 요청');
      if (!video) throw httpError(503, 'R2_NOT_CONNECTED', '영상 저장소가 아직 연결되지 않았어요.');
      return video[routes[path]](body, user.store);
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  // req: { method, path, query: {k:v}, headers: {소문자 키}, body }
  // 반환: { status, headers, body }
  async function handle(req) {
    const origin = req.headers.origin || '';
    const cors = {};
    if (origin && ALLOWED_ORIGIN_RE.test(origin)) {
      cors['Access-Control-Allow-Origin'] = origin;
      cors['Vary'] = 'Origin';
      cors['Access-Control-Allow-Headers'] = 'content-type, authorization';
      cors['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
      cors['Access-Control-Max-Age'] = '3600';
    }
    const reply = (status, body) => ({ status, headers: { ...cors, 'Cache-Control': 'no-store' }, body });

    if (req.method === 'OPTIONS') return reply(204, null);
    const path = String(req.path || '').replace(/\/+$/, '');

    try {
      if (path === '/api/health' && req.method === 'GET') return reply(200, { ok: true });
      if (path === '/api/auth/store-login' && req.method === 'POST') return reply(200, await storeLogin(req));
      if (path === '/api/auth/login' && req.method === 'POST') return reply(200, await webLogin(req));
      if (path === '/api/store/passwords' && req.method === 'POST') return reply(200, await setPasswords(req));
      if (path === '/api/admin/migrate-legacy' && req.method === 'POST') return reply(200, await migrateLegacy(req));
      if (path === '/api/stores/check-id' && req.method === 'GET') return reply(200, await checkId(req));
      if (path === '/api/stores/signup' && req.method === 'POST') return reply(200, await signup(req));
      if (path === '/api/usage/report' && req.method === 'POST') return reply(200, await usageReport(req));
      if (path === '/api/auth/verify-exit' && req.method === 'POST') return reply(200, await verifyExit(req));
      if (path === '/api/store/features' && req.method === 'POST') return reply(200, await setStoreFeatures(req));
      // 65차: 매장 통계 — 패드가 주문·게임 조회를 보고, 운영자가 매장별 인기 메뉴·게임을 봄
      if (path.startsWith('/api/stats/')) {
        if (!insights) throw httpError(503, 'NO_INSIGHTS', '매장 통계가 서버에 연결되지 않았어요.');
        return reply(200, await insights.route(req, path, { requireStoreUser, rate }));
      }
      // 83차: 자동 번역 — 관리자 웹이 메뉴·공지·이벤트를 저장한 뒤 부름
      if (path.startsWith('/api/translate/')) {
        if (!translate) throw httpError(503, 'NO_TRANSLATE', '자동 번역이 서버에 연결되지 않았어요.');
        return reply(200, await translate.route(req, path, { requireAdmin, rate }));
      }
      if (path === '/api/ops/insights') {
        await requireOps(req);
        rate('ops', 120, MIN, '운영자 요청');
        if (!insights) throw httpError(503, 'NO_INSIGHTS', '매장 통계가 서버에 연결되지 않았어요.');
        return reply(200, await insights.opsRoute(req, path));
      }
      if (path.startsWith('/api/ops/toss/')) {
        await requireOps(req);
        rate('ops', 120, MIN, '운영자 요청');
        if (!toss) throw httpError(503, 'NO_TOSS', '토스 POS 연동이 서버에 연결되지 않았어요.');
        return reply(200, await toss.opsRoute(req, path));
      }
      if (path.startsWith('/api/ops/')) return reply(200, await opsRoute(req, path));
      if (path.startsWith('/api/toss/')) {
        if (!toss) throw httpError(503, 'NO_TOSS', '토스 POS 연동이 서버에 연결되지 않았어요.');
        return reply(200, await toss.route(req, path, { requireStoreUser, requireAdmin, rate }));
      }

      if (path.startsWith('/api/video/')) return reply(200, await videoRoute(req, path));

      if (path.startsWith('/api/bgg/')) {
        const user = await requireAdmin(req);
        await recordUsage(user.store, { bggCalls: 1 });
      }

      if (path === '/api/bgg/search' && req.method === 'GET') {
        const q = String(req.query.q || '').trim().slice(0, 60);
        if (!q) throw httpError(400, 'EMPTY_QUERY', '검색어를 입력해 주세요.');
        rate('search', 20, MIN);
        try {
          return reply(200, { results: await bgg.search(q) });
        } catch (e) {
          throw bggFail(e);
        }
      }

      if (path === '/api/bgg/lookup' && req.method === 'GET') {
        const id = String(req.query.id || '').trim();
        if (!/^\d+$/.test(id)) throw httpError(400, 'INVALID_BGG_ID', 'BGG geek ID는 숫자로 입력해 주세요.');
        rate('lookup', 30, MIN);
        let d;
        try {
          d = await bgg.fetchDetails(id);
        } catch (e) {
          throw bggFail(e);
        }
        if (!d.name || !Number.isFinite(d.minPlayers) || !Number.isFinite(d.maxPlayers)) {
          throw httpError(422, 'BGG_INCOMPLETE', '이 게임은 BGG에 인원 정보가 없어요. 직접 입력해 주세요.');
        }
        return reply(200, detailView(d));
      }

      if (path === '/api/bgg/image' && req.method === 'GET') {
        const id = String(req.query.id || '').trim();
        if (!/^\d+$/.test(id)) throw httpError(400, 'INVALID_BGG_ID', 'BGG geek ID를 확인해 주세요.');
        rate('image', 60, MIN);
        let img;
        try {
          img = await bgg.fetchImage(id, { maxBytes: IMAGE_MAX_BYTES });
        } catch (e) {
          throw bggFail(e);
        }
        return reply(200, {
          contentType: img.contentType,
          dataUrl: `data:${img.contentType};base64,${Buffer.from(img.buffer).toString('base64')}`,
        });
      }

      if (path === '/api/bgg/details' && req.method === 'POST') {
        const raw = Array.isArray(req.body && req.body.ids) ? req.body.ids : [];
        const ids = Array.from(new Set(raw.map((x) => String(x || '').trim()).filter((x) => /^\d+$/.test(x))));
        if (!ids.length) throw httpError(400, 'INVALID_BGG_ID', 'geek ID가 없어요.');
        if (ids.length > DETAILS_MAX_IDS) throw httpError(400, 'TOO_MANY_IDS', `한 번에 ${DETAILS_MAX_IDS}개까지만 조회할 수 있어요.`);
        rate('details', 15, MIN);
        let map;
        try {
          map = await bgg.fetchDetailsBatch(ids);
        } catch (e) {
          throw bggFail(e);
        }
        const games = [];
        const missing = [];
        for (const id of ids) {
          const d = map.get(id);
          if (!d || !d.name || !Number.isFinite(d.minPlayers) || !Number.isFinite(d.maxPlayers)) missing.push(id);
          else games.push(detailView(d));
        }
        return reply(200, { games, missing });
      }

      throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
    } catch (e) {
      const status = e.status || 500;
      if (status === 500) console.error('[API 오류]', e);
      return reply(status, { error: e.code || 'INTERNAL', message: status === 500 ? '서버 오류가 났어요.' : e.message });
    }
  }

  return handle;
}

module.exports = { createHandler, difficultyFromWeight };
