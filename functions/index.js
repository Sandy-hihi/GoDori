'use strict';
// Firebase Cloud Functions 진입점. Hosting이 "/api/**" 요청을 이 함수(api)로 넘겨 준다. (firebase.json)
// 관리자 로그인(/api/auth/login)과 BGG 조회(/api/bgg/*), 룰 설명 영상(/api/video/*, Cloudflare R2)을 처리한다.
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
const R2_ENABLED = false;
const R2_ACCOUNT_ID = ''; // Cloudflare 대시보드 → R2 → 오른쪽 "Account ID" (32자리 영문·숫자)
const R2_BUCKET = 'godori-rule-videos';
const R2_ACCESS_KEY_ID = R2_ENABLED ? defineSecret('R2_ACCESS_KEY_ID') : null;
const R2_SECRET_ACCESS_KEY = R2_ENABLED ? defineSecret('R2_SECRET_ACCESS_KEY') : null;

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

  const db = getDb();
  const url = (BGG_APPS_SCRIPT_URL.value() || '').trim();
  const secret = (BGG_RELAY_SECRET.value() || '').trim();

  handle = createHandler({
    bgg: createBggClient({
      token: (BGG_APP_TOKEN.value() || '').trim(),
      relay: url && secret ? { resolve: async () => ({ url, secret, transport: 'appsscript' }) } : undefined,
    }),
    // 관리자 PIN/비밀번호는 서버에서만 읽음 (보안 규칙이 앱의 읽기를 막음)
    getAdminSecrets: async () => {
      const doc = await db.collection('settings').doc('adminPin').get();
      const d = doc.data() || {};
      return { pin: String(d.pin || ''), webPassword: String(d.webPassword || '') };
    },
    verifyIdToken: (idToken) => getAdminAuth().verifyIdToken(idToken),
    // 태블릿/관리자 웹 각각 고정 사용자 ID로 로그인. admin: true 가 보안 규칙의 isAdmin() 근거
    // (토큰 발급에는 함수 서비스 계정에 "서비스 계정 토큰 생성자" 권한이 필요 — 설정 안내 참고)
    createAdminToken: (kind) =>
      getAdminAuth().createCustomToken(kind === 'web' ? 'admin-web' : 'admin-pad', { admin: true }),
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
      stats: createVideoStats(db),
    }),
  });
  return handle;
}

// 게임 문서의 룰 영상 칸 (games/{id}.ruleVideo.q1080 / q720)
function createGameStore(db) {
  const { FieldValue, FieldPath } = require('firebase-admin/firestore');
  return {
    async get(gameId) {
      const doc = await db.collection('games').doc(gameId).get();
      return doc.exists ? doc.data() : null;
    },
    async setRuleVideo(gameId, field, info) {
      // 패드 게임 목록에 바로 반영하려면 관리자 웹의 '손님 앱 새로고침' (영상마다 자동으로 하면 패드 읽기 비용이 커짐)
      await db.collection('games').doc(gameId).update(new FieldPath('ruleVideo', field), info == null ? FieldValue.delete() : info);
    },
  };
}

// 재생 통계 (서버만 씀, 관리자만 읽음 — firestore.rules)
//   videoStats/{gameId}        { gameId, title, plays, lastPlayedAt }
//   videoStatsDaily/{YYYY-MM-DD} { date, plays, games: { <gameId>: 횟수 } }   한국 날짜 기준
function createVideoStats(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  return {
    async recordPlay(gameId, title) {
      const date = seoulDateKey();
      const batch = db.batch();
      batch.set(
        db.collection('videoStats').doc(gameId),
        { gameId, title, plays: FieldValue.increment(1), lastPlayedAt: FieldValue.serverTimestamp() },
        { merge: true }
      );
      batch.set(
        db.collection('videoStatsDaily').doc(date),
        { date, plays: FieldValue.increment(1), games: { [gameId]: FieldValue.increment(1) } },
        { merge: true }
      );
      await batch.commit();
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
  });
  res.status(out.status);
  for (const [k, v] of Object.entries(out.headers || {})) res.set(k, v);
  if (out.body == null) res.end();
  else res.json(out.body);
}

exports.api = onRequest(
  {
    region: REGION,
    secrets: [BGG_APP_TOKEN, BGG_RELAY_SECRET, BGG_APPS_SCRIPT_URL, ...(R2_ENABLED ? [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY] : [])],
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
