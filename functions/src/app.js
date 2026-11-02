'use strict';
// 고도리 관리자 웹이 쓰는 BGG(보드게임긱) 조회 API.
// 게임 데이터 저장은 지금처럼 앱(Flutter)이 Firestore/Storage에 직접 하고, 이 서버는 BGG에서
// 정보·사진을 "가져오는" 일만 한다. (BGG는 브라우저에서 직접 부를 수 없어서 서버가 대신 부른다)
//
//   GET  /api/health              상태 확인 (로그인 불필요)
//   POST /api/auth/login          { kind: 'pad'|'web', password } -> { token }  관리자 로그인 (로그인 불필요)
//   GET  /api/bgg/search?q=이름     이름으로 검색 -> { results: [{ id, name, yearPublished, thumbnail }] }
//   GET  /api/bgg/lookup?id=13     geek ID 상세 -> { geekId, name, bggName, minPlayers, maxPlayers, recommendedPlayers, weight, rank, difficulty }
//   GET  /api/bgg/image?id=13      사진 -> { dataUrl, contentType }
//   POST /api/bgg/details          { ids: [...] } 여러 개 상세(대용량 추가용, 한 번에 최대 30개) -> { games: [...], missing: [...] }
//
// 관리자 로그인 흐름 (Firebase Authentication)
//   1) 앱이 PIN(태블릿) 또는 비밀번호(관리자 웹)를 /api/auth/login 으로 보냄
//   2) 서버가 Firestore settings/adminPin 의 값과 비교 (이 문서는 보안 규칙상 앱에서 읽을 수 없음)
//   3) 맞으면 admin: true 표시가 붙은 Firebase 커스텀 토큰을 돌려줌 -> 앱이 signInWithCustomToken
//   4) 이후 Firestore/Storage 보안 규칙은 request.auth.token.admin == true 로 관리자를 구별
// 모든 /api/bgg/* 요청은 Authorization: Bearer <Firebase ID 토큰> 헤더가 필요하고, 그 토큰에 admin 표시가 있어야 한다.

const crypto = require('crypto');

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

function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
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

// 로컬 개발(flutter run -d chrome = localhost)과 배포된 관리자 웹에서만 다른 주소로 부를 수 있게 허용
const ALLOWED_ORIGIN_RE = /^(https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?|https:\/\/platform6-boardpad\.(web\.app|firebaseapp\.com))$/;

// 요청한 쪽 IP (Hosting을 거치면 x-forwarded-for 맨 앞이 손님 IP). 위조될 수 있어서 전체 제한도 같이 둔다.
function clientIp(headers) {
  const xff = String(headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xff || 'unknown';
}

// getAdminSecrets: async () => ({ pin, webPassword })   Firestore settings/adminPin
// verifyIdToken:   async (idToken) => 디코딩된 토큰 (틀리면 throw)
// createAdminToken: async (kind) => 커스텀 토큰 문자열
// attempts:        로그인 실패 기록 (src/attempts.js)
function createHandler({ bgg, getAdminSecrets, verifyIdToken, createAdminToken, attempts, now = () => Date.now() }) {
  const limit = createLimiter(now);

  async function requireAdmin(req) {
    const m = /^Bearer\s+(.+)$/i.exec(String(req.headers.authorization || ''));
    if (!m) throw httpError(401, 'UNAUTHORIZED', '관리자 로그인이 필요해요. 다시 로그인해 주세요.');
    let decoded;
    try {
      decoded = await verifyIdToken(m[1].trim());
    } catch (_) {
      throw httpError(401, 'UNAUTHORIZED', '로그인이 만료됐어요. 다시 로그인해 주세요.');
    }
    if (!decoded || decoded.admin !== true) throw httpError(403, 'FORBIDDEN', '관리자만 쓸 수 있어요.');
  }

  async function login(req) {
    const body = req.body || {};
    const kind = body.kind === 'web' ? 'web' : 'pad';
    const given = typeof body.password === 'string' ? body.password.trim() : '';
    if (!given) throw httpError(400, 'EMPTY_PASSWORD', '비밀번호를 입력해 주세요.');
    if (given.length > 100) throw httpError(400, 'INVALID_PASSWORD', '비밀번호가 너무 길어요.');

    const ip = clientIp(req.headers);
    for (const l of LOGIN_LIMITS) {
      if (await attempts.isLocked(l.key(ip), l.max, l.windowMs)) {
        throw httpError(429, 'TOO_MANY', '비밀번호를 너무 많이 틀렸어요. 잠시 뒤에 다시 시도해 주세요.');
      }
    }

    const secrets = (await getAdminSecrets()) || {};
    const pin = String(secrets.pin || '');
    const web = String(secrets.webPassword || '');
    const expected = kind === 'web' ? (web || pin) : pin;
    if (!expected) throw httpError(503, 'NO_PASSWORD', '관리자 비밀번호가 설정되어 있지 않아요. (Firestore settings/adminPin)');

    if (!safeEqual(given, expected)) {
      for (const l of LOGIN_LIMITS) await attempts.recordFail(l.key(ip), l.windowMs);
      throw httpError(401, 'WRONG_PASSWORD', kind === 'web' ? '비밀번호가 올바르지 않습니다.' : 'PIN이 올바르지 않습니다.');
    }
    await attempts.reset(LOGIN_LIMITS[0].key(ip));
    return { token: await createAdminToken(kind) };
  }

  function rate(key, max, windowMs) {
    if (!limit(key, max, windowMs)) throw httpError(429, 'TOO_MANY', 'BGG 요청이 너무 잦아요. 잠시 후 다시 시도해 주세요.');
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
      if (path === '/api/auth/login' && req.method === 'POST') return reply(200, await login(req));

      if (path.startsWith('/api/bgg/')) {
        await requireAdmin(req);
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
