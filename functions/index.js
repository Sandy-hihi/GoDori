'use strict';
// Firebase Cloud Functions 진입점. Hosting이 "/api/**" 요청을 이 함수(api)로 넘겨 준다. (firebase.json)
// 매장 로그인(/api/auth/*, 47차)과 BGG 조회(/api/bgg/*), 룰 설명 영상(/api/video/*, Cloudflare R2)을 처리한다.
// 배포 전에 BGG 비밀값 3개를 등록해야 한다 — 고도리 폴더의 "BGG 비밀값 등록.ps1" 참고.
//   BGG_APPS_SCRIPT_URL : BGG 중계용 Google Apps Script 주소 (월정액권 앱과 같은 것)
//   BGG_RELAY_SECRET    : 그 중계의 비밀키
//   BGG_APP_TOKEN       : BGG API 토큰 (중계를 못 쓸 때 직접 호출용)
// AI 게임 추천은 비밀값 1개가 더 필요하다 — "AI 비밀값 등록.ps1" 참고.
//   ANTHROPIC_API_KEY   : Claude API 키. 비어 있으면 AI 없이 규칙으로만 추천한다.
const { onRequest } = require('firebase-functions/https');
const { onSchedule } = require('firebase-functions/scheduler');
const { defineSecret } = require('firebase-functions/params');

const BGG_APP_TOKEN = defineSecret('BGG_APP_TOKEN');
const BGG_RELAY_SECRET = defineSecret('BGG_RELAY_SECRET');
const BGG_APPS_SCRIPT_URL = defineSecret('BGG_APPS_SCRIPT_URL');
// AI 게임 추천(ai, dailyPicks 함수) 사용 여부. 지금은 꺼 둠 — 코드는 남겨 두고 배포만 안 함.
// 다시 켜려면 true로 바꾸고, firebase.json에 "/api/ai/**" → ai 경로를 "/api/**" 앞에 되살리고,
// 앱의 kAiRecommendEnabled(lib/models/home_layout.dart)도 true로.
// 꺼 두면 ANTHROPIC_API_KEY 비밀값도 선언하지 않음 (선언만 있어도 배포할 때 키를 물어봄)
const AI_ENABLED = false;
const ANTHROPIC_API_KEY = AI_ENABLED ? defineSecret('ANTHROPIC_API_KEY') : null;

// ── 룰 설명 영상 저장소 (Cloudflare R2) ──
// 처음엔 꺼 둠(false) → 영상 API가 "아직 연결되지 않았어요"(503)로 답함. 켜는 순서는
// 고도리 폴더의 "R2 룰 영상 연결 방법.txt" 참고:
//   1) Cloudflare에서 R2 버킷·API 토큰 만들기  2) "R2 비밀값 등록.ps1"로 키 2개 등록
//   3) 아래 R2_ACCOUNT_ID에 계정 ID 넣고 R2_ENABLED = true  4) 배포.bat 4번(서버 함수 배포)
// 비밀값(R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY)은 선언만 있어도 배포할 때 값이 있어야 해서 스위치로 켜고 끔.
// 계정 ID·버킷 이름은 비밀이 아님(임시 주소에도 들어감).
const R2_ENABLED = true;
const R2_ACCOUNT_ID = '32fc10eaf11157e570fe820dd557c5af'; // Cloudflare 대시보드 → R2 → 오른쪽 "Account ID" (32자리 영문·숫자)
const R2_BUCKET = 'godori-rule-videos';
const R2_ACCESS_KEY_ID = R2_ENABLED ? defineSecret('R2_ACCESS_KEY_ID') : null;
const R2_SECRET_ACCESS_KEY = R2_ENABLED ? defineSecret('R2_SECRET_ACCESS_KEY') : null;

// ── 토스 POS 연동 (64차, 토스플레이스 Open API) ──
// 키가 없어도 '가짜 포스'(운영자 페이지에서 매장을 가짜로 연결)로 개발·시연할 수 있음.
// 진짜로 켜는 순서는 고도리 폴더의 "토스 POS 연결 방법.txt":
//   1) 토스플레이스 개발자센터에서 앱(API)·키·웹훅 만들기  2) "토스 비밀값 등록.ps1"로 3개 등록
//   3) 아래 TOSS_ENABLED = true  4) 배포.bat 4번
// 비밀값은 선언만 있어도 배포할 때 값이 있어야 해서 R2처럼 스위치로 켜고 끔.
const TOSS_ENABLED = true; // 68차: 토스플레이스 키·웹훅 비밀값 등록 끝 (11-06)
const TOSS_ACCESS_KEY = TOSS_ENABLED ? defineSecret('TOSS_ACCESS_KEY') : null;
const TOSS_SECRET_KEY = TOSS_ENABLED ? defineSecret('TOSS_SECRET_KEY') : null;
const TOSS_WEBHOOK_SECRET = TOSS_ENABLED ? defineSecret('TOSS_WEBHOOK_SECRET') : null;

// ── 자동 번역 (83차, Google Cloud Translation 기본 v2) ──
// 메뉴·공지·이벤트 글을 영어·중국어·일본어로 (src/translate.js). 비밀값 없이 함수 서비스 계정 권한으로 부름.
// 켜기 전에 Google Cloud 콘솔에서 'Cloud Translation API'를 사용 설정해야 함(꺼져 있으면 관리자 웹 저장은 되고 번역만 실패).
// 월 50만 자 무료. ★서비스가 커지면 Claude 번역으로 바꿀 후보 (프로젝트 문서 claude/고도리-서비스-커지면-바꿀-것.md)
const TRANSLATE_ENABLED = true;

const REGION = 'asia-northeast3'; // 서울

let db = null;
function getDb() {
  if (db) return db;
  const { initializeApp, getApps } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  if (!getApps().length) initializeApp();
  db = getFirestore();
  return db;
}

function getAdminAuth() {
  getDb(); // 앱 초기화
  const { getAuth } = require('firebase-admin/auth');
  return getAuth();
}

let handle = null;
function getHandle() {
  if (handle) return handle;
  const { createBggClient } = require('./src/bgg-client');
  const { createHandler } = require('./src/app');
  const { createFirestoreAttempts } = require('./src/attempts');
  const { createVideoApi } = require('./src/video');
  const { createR2Storage } = require('./src/r2');
  const { createFirestoreStores } = require('./src/stores');
  const { createFirestoreOps, createMonitoring } = require('./src/ops');
  const { createTossClient } = require('./src/toss');
  const { createTossRoutes } = require('./src/toss-routes');
  const { createFirestoreTossData } = require('./src/toss-data');
  const { createFirestoreInsights, createInsightRoutes } = require('./src/insights');
  const { createTranslateRoutes, createGoogleTranslator, createFirestoreTranslateData } = require('./src/translate');

  const db = getDb();
  const storesData = createFirestoreStores(db);
  const url = (BGG_APPS_SCRIPT_URL.value() || '').trim();
  const secret = (BGG_RELAY_SECRET.value() || '').trim();

  handle = createHandler({
    bgg: createBggClient({
      token: (BGG_APP_TOKEN.value() || '').trim(),
      relay: url && secret ? { resolve: async () => ({ url, secret, transport: 'appsscript' }) } : undefined,
    }),
    // 매장 계정 (stores/{매장}/private/account — 서버만 읽음, 보안 규칙이 앱의 읽기를 막음)
    stores: storesData,
    // 토스 POS 연동 (64차): 키가 없으면 가짜 포스만
    toss: createTossRoutes({
      data: createFirestoreTossData(db),
      stores: storesData,
      live: TOSS_ENABLED
        ? createTossClient({ accessKey: TOSS_ACCESS_KEY.value().trim(), secretKey: TOSS_SECRET_KEY.value().trim() })
        : null,
      webhookSecret: TOSS_ENABLED ? TOSS_WEBHOOK_SECRET.value().trim() : '',
      httpError: (status, code, message) => Object.assign(new Error(message), { status, code }),
    }),
    // 매장 통계 (65차): 패드 주문·게임 상세 조회를 stores/{매장}/statsDaily 에 셈 → 운영자 페이지 '매장 통계'
    insights: createInsightRoutes({
      data: createFirestoreInsights(db),
      stores: storesData,
      httpError: (status, code, message) => Object.assign(new Error(message), { status, code }),
    }),
    // 자동 번역 (83차): 관리자 웹이 저장한 뒤 /api/translate/sync
    translate: createTranslateRoutes({
      data: createFirestoreTranslateData(db),
      translator: TRANSLATE_ENABLED
        ? createGoogleTranslator({
            getAccessToken: async () => {
              const { applicationDefault } = require('firebase-admin/app');
              return (await applicationDefault().getAccessToken()).access_token;
            },
          })
        : null,
      httpError: (status, code, message) => Object.assign(new Error(message), { status, code }),
    }),
    // 운영자 페이지 (48차): _ops/account, 프로젝트 전체 사용량(Cloud Monitoring)
    ops: createFirestoreOps(db),
    monitoring: createMonitoring({
      projectId: process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'platform6-boardpad',
      getAccessToken: async () => {
        const { applicationDefault } = require('firebase-admin/app');
        return (await applicationDefault().getAccessToken()).access_token;
      },
    }),
    // 정지·거절한 매장: 패드(pad.<매장>.1~30)·관리자 로그인의 갱신 토큰 취소 (없는 사용자는 건너뜀)
    revokeStoreTokens: async (storeId) => {
      const auth = getAdminAuth();
      const uids = [`admin-web.${storeId}`, `admin-pad.${storeId}`];
      for (let i = 1; i <= 30; i++) uids.push(`pad.${storeId}.${i}`);
      await Promise.all(uids.map((uid) => auth.revokeRefreshTokens(uid).catch(() => {})));
    },
    // 예전(매장 1곳) 관리자 비밀번호 — '매장 데이터 옮기기'를 할 때만 확인용으로 읽음
    getLegacySecrets: async () => {
      const doc = await db.collection('settings').doc('adminPin').get();
      const d = doc.data() || {};
      return { pin: String(d.pin || ''), webPassword: String(d.webPassword || '') };
    },
    verifyIdToken: (idToken) => getAdminAuth().verifyIdToken(idToken),
    // 고정 사용자 ID로 로그인: 패드 pad.<매장>.<방>, 관리자 admin-pad.<매장> / admin-web.<매장>
    // 토큰에 붙는 표시(store, pad, room, admin)가 보안 규칙의 근거. 토큰이 갱신돼도 그대로 남음
    // (토큰 발급에는 함수 서비스 계정에 "서비스 계정 토큰 생성자" 권한이 필요 — 32차에 설정함)
    createToken: (uid, claims) => getAdminAuth().createCustomToken(uid, claims),
    attempts: createFirestoreAttempts(db),
    video: createVideoApi({
      storage: R2_ENABLED
        ? createR2Storage({
            accountId: R2_ACCOUNT_ID,
            bucket: R2_BUCKET,
            accessKeyId: R2_ACCESS_KEY_ID.value(),
            secretAccessKey: R2_SECRET_ACCESS_KEY.value(),
          })
        : null,
      games: createGameStore(db),
      shared: createSharedVideos(db),
      stats: createVideoStats(db),
    }),
  });
  return handle;
}

// 게임 문서의 룰 영상 칸 (stores/{매장}/games/{id}.ruleVideo.q1080 / q720)
function createGameStore(db) {
  const { FieldValue, FieldPath } = require('firebase-admin/firestore');
  const game = (storeId, gameId) => db.collection('stores').doc(storeId).collection('games').doc(gameId);
  return {
    async get(storeId, gameId) {
      const doc = await game(storeId, gameId).get();
      return doc.exists ? doc.data() : null;
    },
    // 93차: 영상이 있는 게임 (운영자 '매장 영상을 공용으로 옮기기' — 가끔 한 번이라 전체를 읽음)
    async listWithVideo(storeId) {
      const snap = await db.collection('stores').doc(storeId).collection('games').get();
      return snap.docs
        .map((d) => ({ id: d.id, ...d.data() }))
        .filter((g) => g.ruleVideo && (g.ruleVideo.q1080 || g.ruleVideo.q720));
    },
    async setRuleVideo(storeId, gameId, field, info) {
      // 패드 게임 목록에 바로 반영하려면 관리자 웹의 '손님 앱 새로고침' (영상마다 자동으로 하면 패드 읽기 비용이 커짐)
      await game(storeId, gameId).update(new FieldPath('ruleVideo', field), info == null ? FieldValue.delete() : info);
    },
  };
}

// 92차 공용 룰 영상 기록: shared/ruleVideos { videos: { <BGG 번호>: { title, q1080, q720, updatedAt } }, updatedAt }
// 서버만 씀. 앱(패드·관리자 웹)은 firestore.rules로 읽기만 — 패드 게임 목록(game_catalog.dart)이 하루 1번 같이 읽음
// 재생 때마다 읽지 않게 1분 기억 (운영자가 바꾸면 그 인스턴스는 바로 비움)
function createSharedVideos(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  const ref = db.collection('shared').doc('ruleVideos');
  let cache = null;
  let cacheAt = 0;
  async function all() {
    if (cache && Date.now() - cacheAt < 60 * 1000) return cache;
    const doc = await ref.get();
    cache = (doc.exists && doc.get('videos')) || {};
    cacheAt = Date.now();
    return cache;
  }
  return {
    async get(bggId) {
      const v = (await all())[bggId];
      return v ? { ...v } : null;
    },
    async set(bggId, field, info, title) {
      await db.runTransaction(async (tx) => {
        const doc = await tx.get(ref);
        const videos = { ...((doc.exists && doc.get('videos')) || {}) };
        const e = { ...(videos[bggId] || { title: '' }) };
        if (title) e.title = title;
        if (info == null) delete e[field];
        else e[field] = info;
        if (!e.q1080 && !e.q720) delete videos[bggId];
        else videos[bggId] = { ...e, updatedAt: new Date() };
        tx.set(ref, { videos, updatedAt: FieldValue.serverTimestamp() });
      });
      cache = null;
    },
    async list() {
      cache = null;
      return all();
    },
  };
}

// 재생 통계 (서버만 씀, 관리자만 읽음 — firestore.rules)
//   stores/{매장}/usageDaily/{날짜}  videoPlays·videoBytesEst (48차, 운영자 이용 통계) · private/usage r2Bytes·r2Files
//   stores/{매장}/videoStats/{gameId}          { gameId, title, plays, lastPlayedAt }
//   stores/{매장}/videoStatsDaily/{YYYY-MM-DD} { date, plays, games: { <gameId>: 횟수 } }   한국 날짜 기준
function createVideoStats(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  return {
    async recordPlay(storeId, gameId, title, bytesEst = 0) {
      const date = seoulDateKey();
      const store = db.collection('stores').doc(storeId);
      const batch = db.batch();
      batch.set(
        store.collection('usageDaily').doc(date),
        { date, videoPlays: FieldValue.increment(1), videoBytesEst: FieldValue.increment(Math.round(bytesEst) || 0) },
        { merge: true }
      );
      batch.set(
        store.collection('videoStats').doc(gameId),
        { gameId, title, plays: FieldValue.increment(1), lastPlayedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      batch.set(
        store.collection('videoStatsDaily').doc(date),
        { date, plays: FieldValue.increment(1), games: { [gameId]: FieldValue.increment(1) } },
        { merge: true }
      );
      await batch.commit();
    },
    // 올리기: 하루 기록(올린 수·용량) + 매장 R2 저장 용량 (바꾼 거면 예전 파일 크기만큼 뺌)
    async recordUpload(storeId, bytes, oldBytes) {
      const date = seoulDateKey();
      const store = db.collection('stores').doc(storeId);
      const batch = db.batch();
      batch.set(store.collection('usageDaily').doc(date),
        { date, videoUploads: FieldValue.increment(1), videoUploadBytes: FieldValue.increment(bytes) }, { merge: true });
      batch.set(store.collection('private').doc('usage'),
        { r2Bytes: FieldValue.increment(bytes - (oldBytes || 0)), r2Files: FieldValue.increment(oldBytes == null ? 1 : 0) }, { merge: true });
      await batch.commit();
    },
    async recordRemove(storeId, bytes) {
      await db.collection('stores').doc(storeId).collection('private').doc('usage')
        .set({ r2Bytes: FieldValue.increment(-bytes), r2Files: FieldValue.increment(-1) }, { merge: true });
    },
  };
}

// Express 스타일 요청을 우리 핸들러 형식으로 바꿔 부르고 응답을 돌려줌
async function serve(handler, req, res) {
  const headers = {};
  for (const [k, v] of Object.entries(req.headers || {})) headers[k.toLowerCase()] = Array.isArray(v) ? v[0] : v;
  const out = await handler({
    method: req.method,
    path: req.path,
    query: req.query || {},
    headers,
    body: req.body,
    rawBody: req.rawBody, // 토스 웹훅 서명 확인용 원본 본문 (64차)
  });
  res.status(out.status);
  for (const [k, v] of Object.entries(out.headers || {})) res.set(k, v);
  if (out.body == null) res.end();
  else res.json(out.body);
}

exports.api = onRequest(
  {
    region: REGION,
    secrets: [
      BGG_APP_TOKEN, BGG_RELAY_SECRET, BGG_APPS_SCRIPT_URL,
      ...(R2_ENABLED ? [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY] : []),
      ...(TOSS_ENABLED ? [TOSS_ACCESS_KEY, TOSS_SECRET_KEY, TOSS_WEBHOOK_SECRET] : []),
    ],
    maxInstances: 3, // 요청 폭주 시 비용 상한
    timeoutSeconds: 120, // BGG 중계가 느릴 때 재시도까지 기다릴 수 있게
    memory: '256MiB',
  },
  (req, res) => serve(getHandle(), req, res)
);

// ── AI 게임 추천 ──

function makeLlm() {
  const { callClaude, DEFAULT_MODEL } = require('./src/ai');
  const apiKey = (ANTHROPIC_API_KEY.value() || '').trim();
  if (!apiKey) return null; // 키가 없으면 규칙 추천만
  const model = (process.env.AI_MODEL || DEFAULT_MODEL).trim();
  return ({ system, user }) => callClaude({ apiKey, model, system, user });
}

async function loadAvailableGames() {
  const snap = await getDb().collection('games').where('isAvailable', '==', true).get();
  return new Map(snap.docs.map((d) => [d.id, d.data()]));
}

let aiHandle = null;
function getAiHandle() {
  if (aiHandle) return aiHandle;
  const { createAiHandler } = require('./src/ai');
  aiHandle = createAiHandler({ loadGames: loadAvailableGames, llm: makeLlm() });
  return aiHandle;
}

// 손님 패드의 "우리 테이블 맞춤 추천" (Hosting이 /api/ai/** 를 이 함수로 넘김)
const aiFunction = AI_ENABLED && onRequest(
  {
    region: REGION,
    secrets: [ANTHROPIC_API_KEY],
    maxInstances: 3,
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  (req, res) => serve(getAiHandle(), req, res)
);

function seoulDateKey(date = new Date()) {
  // 한국 시간 기준 날짜 (YYYY-MM-DD)
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(date);
}

// 매일 오전 10시(한국 시간)에 "오늘의 추천 게임"을 골라 settings/aiPicks 에 저장
const dailyPicksFunction = AI_ENABLED && onSchedule(
  {
    region: REGION,
    schedule: 'every day 10:00',
    timeZone: 'Asia/Seoul',
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  async () => {
    const { dailyPicks } = require('./src/ai');
    const db = getDb();

    // 홈 화면 배치의 AI 위젯 설정에서 "추천에서 뺄 게임"을 읽음
    let exclude = [];
    try {
      const layout = (await db.collection('settings').doc('homeLayout').get()).data() || {};
      for (const w of Array.isArray(layout.widgets) ? layout.widgets : []) {
        if (w && w.type === 'aiPick' && w.options && Array.isArray(w.options.exclude)) {
          exclude = exclude.concat(w.options.exclude.map(String));
        }
      }
    } catch (e) {
      console.warn('[오늘의 추천] 배치 읽기 실패', e && e.message);
    }

    const result = await dailyPicks({
      games: await loadAvailableGames(),
      llm: makeLlm(),
      dateKey: seoulDateKey(),
      exclude,
      count: 4,
    });
    const { FieldValue } = require('firebase-admin/firestore');
    await db.collection('settings').doc('aiPicks').set({ ...result, generatedAt: FieldValue.serverTimestamp() });
    console.log(`[오늘의 추천] ${result.date} ${result.source} ${result.picks.map((p) => p.title).join(', ')}`);
  }
);

if (AI_ENABLED) {
  exports.ai = aiFunction;
  exports.dailyPicks = dailyPicksFunction;
}
