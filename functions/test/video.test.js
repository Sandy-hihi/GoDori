'use strict';
// 룰 영상 API(/api/video/*)와 R2 임시 주소 서명 확인. 실행: cd functions && node --test test/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createVideoApi, MAX_BYTES } = require('../src/video');
const { presignUrl, createR2Storage } = require('../src/r2');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');

// 'admin-token' = platform6 관리자, 'guest-token' = platform6 3번 방 패드(손님),
// 'other-admin' = 다른 매장 관리자, 'anon-token' = 예전 익명 로그인(매장 없음)
const fakeVerify = async (t) => {
  if (t === 'admin-token') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
  if (t === 'guest-token') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
  if (t === 'other-admin') return { uid: 'admin-web.other-store', admin: true, store: 'other-store' };
  if (t === 'anon-token') return { uid: 'anon123' };
  if (t === 'ops-token') return { uid: 'ops', ops: true };
  throw new Error('bad token');
};

// 가짜 R2: 올린 파일을 Map에 둠
function fakeStorage() {
  const files = new Map();
  const removed = [];
  return {
    files,
    removed,
    uploadUrl: (key, ct, exp) => `https://r2.test/PUT/${key}?ct=${ct}&exp=${exp}`,
    downloadUrl: (key, exp) => `https://r2.test/GET/${key}?exp=${exp}`,
    async head(key) { return files.has(key) ? { size: files.get(key), contentType: 'video/mp4' } : null; },
    async remove(key) { removed.push(key); files.delete(key); },
  };
}

function fakeGames() {
  const docs = new Map([['g1', { title: '카탄' }], ['g2', { title: '스플렌더' }]]);
  // 게임은 platform6 매장에만 있음
  return {
    docs,
    async get(store, id) { return store === 'platform6' && docs.has(id) ? JSON.parse(JSON.stringify(docs.get(id))) : null; },
    async setRuleVideo(store, id, field, info) {
      assert.equal(store, 'platform6');
      const d = docs.get(id);
      d.ruleVideo = d.ruleVideo || {};
      if (info == null) delete d.ruleVideo[field];
      else d.ruleVideo[field] = info;
    },
  };
}

function setup({ connected = true } = {}) {
  const storage = connected ? fakeStorage() : null;
  const games = fakeGames();
  const plays = [];
  let t = 1793700000000;
  const video = createVideoApi({ storage, games, stats: { recordPlay: async (store, id, title) => plays.push([store, id, title]) }, now: () => t++ });
  const h = createHandler({
    bgg: {},
    stores: createMemoryStores({ platform6: { name: '플랫폼6' }, 'other-store': { name: '다른 매장' } }),
    verifyIdToken: fakeVerify,
    createToken: async () => 'x',
    attempts: createMemoryAttempts(),
    video,
  });
  return { h, storage, games, plays };
}

const req = (method, path, { query = {}, body, token = 'admin-token' } = {}) => ({
  method, path, query, body,
  headers: token ? { authorization: `Bearer ${token}` } : {},
});

async function upload(ctx, gameId, quality, size = 1000, meta = {}) {
  const r = await ctx.h(req('POST', '/api/video/upload-url', { body: { gameId, quality, size, contentType: 'video/mp4' } }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  ctx.storage.files.set(r.body.key, size); // 관리자 웹이 PUT 했다고 침
  const c = await ctx.h(req('POST', '/api/video/confirm', { body: { gameId, quality, key: r.body.key, meta } }));
  return { up: r, c };
}

test('영상 API: 로그인 없으면 401, 손님은 업로드 403', async () => {
  const { h } = setup();
  assert.equal((await h(req('POST', '/api/video/upload-url', { token: null, body: {} }))).status, 401);
  assert.equal((await h(req('POST', '/api/video/upload-url', { token: 'guest-token', body: { gameId: 'g1', quality: '1080', size: 10 } }))).status, 403);
  assert.equal((await h(req('POST', '/api/video/delete', { token: 'guest-token', body: { gameId: 'g1' } }))).status, 403);
  assert.equal((await h(req('GET', '/api/video/play-url', { token: null, query: { gameId: 'g1' } }))).status, 401);
  // 예전 익명 로그인은 다시 로그인하라고
  const anon = await h(req('GET', '/api/video/play-url', { token: 'anon-token', query: { gameId: 'g1' } }));
  assert.equal(anon.status, 403);
  assert.equal(anon.body.error, 'RELOGIN');
});

test('영상 API: 다른 매장 관리자는 이 매장 게임을 못 건드림', async () => {
  const ctx = setup();
  await upload(ctx, 'g1', '1080');
  const other = (path, body) => ctx.h(req('POST', path, { token: 'other-admin', body }));
  assert.equal((await other('/api/video/upload-url', { gameId: 'g1', quality: '1080', size: 10 })).status, 404);
  const r = await other('/api/video/delete', { gameId: 'g1' });
  assert.equal(r.status, 200); // 그 매장엔 게임이 없어서 아무것도 안 지움
  assert.ok(ctx.games.docs.get('g1').ruleVideo.q1080);
  assert.equal((await ctx.h(req('GET', '/api/video/play-url', { token: 'other-admin', query: { gameId: 'g1' } }))).status, 404);
});

test('영상 API: R2 연결 전이면 503 (권한 확인은 먼저)', async () => {
  const { h } = setup({ connected: false });
  const r = await h(req('POST', '/api/video/upload-url', { body: { gameId: 'g1', quality: '1080', size: 10 } }));
  assert.equal(r.status, 503);
  assert.equal(r.body.error, 'R2_NOT_CONNECTED');
  assert.equal((await h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }))).status, 503);
  assert.equal((await h(req('POST', '/api/video/upload-url', { token: 'guest-token', body: {} }))).status, 403);
});

test('업로드 주소: 입력 검사', async () => {
  const { h } = setup();
  const up = (body) => h(req('POST', '/api/video/upload-url', { body }));
  assert.equal((await up({ gameId: 'g1', quality: '480', size: 10 })).status, 400);
  assert.equal((await up({ gameId: 'a/b', quality: '1080', size: 10 })).status, 400);
  assert.equal((await up({ gameId: 'g1', quality: '1080', size: 0 })).status, 400);
  assert.equal((await up({ gameId: 'g1', quality: '1080', size: MAX_BYTES + 1 })).status, 413);
  assert.equal((await up({ gameId: 'g1', quality: '1080', size: 10, contentType: 'video/webm' })).status, 415);
  assert.equal((await up({ gameId: 'nope', quality: '1080', size: 10 })).status, 404);
  const ok = await up({ gameId: 'g1', quality: '1080', size: 10 });
  assert.equal(ok.status, 200);
  assert.match(ok.body.key, /^rule-videos\/platform6\/g1\/\d+_1080\.mp4$/);
  assert.equal(ok.body.contentType, 'video/mp4');
});

test('올리기 → 확인 → 게임 문서에 기록, 바꾸면 예전 파일 삭제', async () => {
  const ctx = setup();
  const first = await upload(ctx, 'g1', '1080', 5000, { width: 1920, height: 1080, fps: 30, durationSec: 480, videoCodec: 'avc1' });
  assert.equal(first.c.status, 200, JSON.stringify(first.c.body));
  const rv = ctx.games.docs.get('g1').ruleVideo.q1080;
  assert.equal(rv.key, first.up.body.key);
  assert.equal(rv.sizeBytes, 5000); // 크기는 저장소에서 확인한 값
  assert.equal(rv.fps, 30);
  const second = await upload(ctx, 'g1', '1080', 6000);
  assert.equal(second.c.status, 200);
  assert.deepEqual(ctx.storage.removed, [first.up.body.key]);
  assert.equal(ctx.games.docs.get('g1').ruleVideo.q1080.key, second.up.body.key);
});

test('확인: 안 올라간 파일 404, 다른 게임·화질 키는 400', async () => {
  const ctx = setup();
  const r = await ctx.h(req('POST', '/api/video/upload-url', { body: { gameId: 'g1', quality: '1080', size: 10 } }));
  const key = r.body.key;
  assert.equal((await ctx.h(req('POST', '/api/video/confirm', { body: { gameId: 'g1', quality: '1080', key } }))).status, 404);
  ctx.storage.files.set(key, 10);
  assert.equal((await ctx.h(req('POST', '/api/video/confirm', { body: { gameId: 'g2', quality: '1080', key } }))).status, 400);
  assert.equal((await ctx.h(req('POST', '/api/video/confirm', { body: { gameId: 'g1', quality: '720', key } }))).status, 400);
  assert.equal((await ctx.h(req('POST', '/api/video/confirm', { body: { gameId: 'g1', quality: '1080', key: 'rule-videos/g1/../x' } }))).status, 400);
  // 매장 없는 예전 모양 키도 새로 기록하는 건 안 됨
  assert.equal((await ctx.h(req('POST', '/api/video/confirm', { body: { gameId: 'g1', quality: '1080', key: 'rule-videos/g1/1793700000000_1080.mp4' } }))).status, 400);
});

test('재생 주소: 손님 패드도 받음, 1080·720 둘 다, 재생 횟수 기록', async () => {
  const ctx = setup();
  await upload(ctx, 'g1', '1080', 10, { width: 1920, height: 1080 });
  await upload(ctx, 'g1', '720', 10, { width: 1280, height: 720 });
  const r = await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }));
  assert.equal(r.status, 200);
  assert.match(r.body.q1080.url, /GET\/rule-videos\/platform6\/g1\/.*_1080\.mp4/);
  assert.match(r.body.q720.url, /_720\.mp4/);
  assert.equal(r.body.q720.height, 720);
  assert.deepEqual(ctx.plays, [['platform6', 'g1', '카탄']]);
  // count=0(화질 바꿀 때 다시 받기)은 안 셈
  await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1', count: '0' } }));
  assert.equal(ctx.plays.length, 1);
  // 영상 없는 게임 404
  assert.equal((await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g2' } }))).status, 404);
});

test('재생 기록이 실패해도 재생 주소는 줌 (예전 키 모양도 재생됨)', async () => {
  const storage = fakeStorage();
  const games = fakeGames();
  games.docs.get('g1').ruleVideo = { q1080: { key: 'rule-videos/g1/1_1080.mp4' } };
  const video = createVideoApi({ storage, games, stats: { recordPlay: async () => { throw new Error('db down'); } } });
  const r = await video.playUrl({ gameId: 'g1' }, 'platform6');
  assert.ok(r.q1080.url);
});

test('삭제: 화질 하나 또는 전부', async () => {
  const ctx = setup();
  const a = await upload(ctx, 'g1', '1080');
  const b = await upload(ctx, 'g1', '720');
  let r = await ctx.h(req('POST', '/api/video/delete', { body: { gameId: 'g1', quality: '720' } }));
  assert.equal(r.status, 200);
  assert.deepEqual(ctx.storage.removed, [b.up.body.key]);
  assert.ok(ctx.games.docs.get('g1').ruleVideo.q1080);
  r = await ctx.h(req('POST', '/api/video/delete', { body: { gameId: 'g1' } }));
  assert.equal(r.status, 200);
  assert.deepEqual(ctx.storage.removed, [b.up.body.key, a.up.body.key]);
  assert.deepEqual(ctx.games.docs.get('g1').ruleVideo, {});
});

test('손님 재생 요청은 1분에 30번까지', async () => {
  const ctx = setup();
  await upload(ctx, 'g1', '1080');
  for (let i = 0; i < 30; i++) {
    assert.equal((await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1', count: '0' } }))).status, 200);
  }
  assert.equal((await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }))).status, 429);
});

test('R2 임시 주소 모양 (서명은 AWS 공식 서명기와 같음을 별도로 확인함)', () => {
  const url = new URL(presignUrl({
    method: 'PUT', accountId: 'acc', bucket: 'b', key: 'rule-videos/한글 ID/1_1080.mp4',
    accessKeyId: 'AK', secretAccessKey: 'SK', expiresIn: 3600, headers: { 'Content-Type': 'video/mp4' },
    now: new Date('2026-11-03T10:15:30Z'),
  }));
  assert.equal(url.host, 'acc.r2.cloudflarestorage.com');
  assert.equal(url.pathname, '/b/rule-videos/%ED%95%9C%EA%B8%80%20ID/1_1080.mp4');
  assert.equal(url.searchParams.get('X-Amz-Credential'), 'AK/20261103/auto/s3/aws4_request');
  assert.equal(url.searchParams.get('X-Amz-SignedHeaders'), 'content-type;host');
  assert.equal(url.searchParams.get('X-Amz-Expires'), '3600');
  assert.match(url.searchParams.get('X-Amz-Signature'), /^[0-9a-f]{64}$/);
});

test('R2 저장소: 설정이 비면 null(연결 안 됨), HEAD 404면 null', async () => {
  assert.equal(createR2Storage({ accountId: '', bucket: 'b', accessKeyId: 'a', secretAccessKey: 's' }), null);
  const calls = [];
  const s = createR2Storage({
    accountId: 'acc', bucket: 'b', accessKeyId: 'a', secretAccessKey: 's',
    fetchImpl: async (url, opt) => {
      calls.push(opt.method);
      if (opt.method === 'HEAD') return { status: 404, ok: false, headers: new Map() };
      return { status: 204, ok: true, headers: new Map() };
    },
  });
  assert.equal(await s.head('rule-videos/x/1_1080.mp4'), null);
  await s.remove('rule-videos/x/1_1080.mp4');
  assert.deepEqual(calls, ['HEAD', 'DELETE']);
});

// ── 92차: 공용 룰 영상 보관함 ──
function setupShared() {
  const { createMemoryOps } = require('../src/ops');
  const { createMemorySharedVideos } = require('../src/video');
  const storage = fakeStorage();
  const games = fakeGames();
  games.docs.get('g1').geekId = '13'; // 카탄 BGG 13
  games.docs.get('g2').geekId = '148228'; // 스플렌더
  const shared = createMemorySharedVideos();
  const plays = [];
  let t = 1793700000000;
  const video = createVideoApi({ storage, games, shared, stats: { recordPlay: async (s, id, title, b) => plays.push([s, id, title, b]) }, now: () => t++ });
  const h = createHandler({
    ops: createMemoryOps({ password: 'ops-password-1' }),
    bgg: {},
    stores: createMemoryStores({ platform6: { name: '플랫폼6' }, 'other-store': { name: '다른 매장' } }),
    verifyIdToken: fakeVerify,
    createToken: async () => 'x',
    attempts: createMemoryAttempts(),
    video,
  });
  return { h, storage, games, shared, plays };
}

async function sharedUpload(ctx, bggId, quality, size = 2000, title = '카탄') {
  const r = await ctx.h(req('POST', '/api/ops/shared-video/upload-url', { token: 'ops-token', body: { bggId, quality, size, contentType: 'video/mp4' } }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  ctx.storage.files.set(r.body.key, size);
  const c = await ctx.h(req('POST', '/api/ops/shared-video/confirm', { token: 'ops-token', body: { bggId, quality, key: r.body.key, title, meta: { width: 1920, height: 1080 } } }));
  return { up: r, c };
}

test('공용 영상: 운영자만 올리고, 매장 영상이 없으면 같은 BGG 번호의 공용 영상을 재생', async () => {
  const ctx = setupShared();
  // 운영자 아니면 못 올림
  const no = await ctx.h(req('POST', '/api/ops/shared-video/upload-url', { token: 'admin-token', body: { bggId: '13', quality: '1080', size: 10, contentType: 'video/mp4' } }));
  assert.equal(no.status, 403);
  // BGG 번호 검사
  const bad = await ctx.h(req('POST', '/api/ops/shared-video/upload-url', { token: 'ops-token', body: { bggId: 'abc', quality: '1080', size: 10, contentType: 'video/mp4' } }));
  assert.equal(bad.status, 400);

  const { up, c } = await sharedUpload(ctx, '13', '1080');
  assert.equal(c.status, 200, JSON.stringify(c.body));
  assert.match(up.body.key, /^rule-videos\/_shared\/13\/\d+_1080\.mp4$/);
  assert.equal(ctx.shared.map.get('13').title, '카탄');

  // 다른 BGG 번호 폴더의 키로 확인하면 거절
  const wrong = await ctx.h(req('POST', '/api/ops/shared-video/confirm', { token: 'ops-token', body: { bggId: '148228', quality: '1080', key: up.body.key } }));
  assert.equal(wrong.status, 400);

  // 패드: 카탄(g1)은 매장 영상이 없어도 공용 영상으로 재생
  const play = await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }));
  assert.equal(play.status, 200, JSON.stringify(play.body));
  assert.equal(play.body.shared, true);
  assert.ok(play.body.q1080.url.includes('rule-videos/_shared/13/'));
  assert.deepEqual(ctx.plays.at(-1).slice(0, 3), ['platform6', 'g1', '카탄']);
  // 스플렌더(g2)는 공용 영상도 없음
  assert.equal((await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g2' } }))).status, 404);

  // 매장 영상이 생기면 매장 영상이 먼저
  const own = await upload(ctx, 'g1', '1080');
  assert.equal(own.c.status, 200, JSON.stringify(own.c.body));
  const play2 = await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }));
  assert.equal(play2.body.shared, undefined);
  assert.ok(play2.body.q1080.url.includes('rule-videos/platform6/g1/'));

  // 목록·다시 올리면 예전 파일 지움·지우기
  const list = await ctx.h(req('GET', '/api/ops/shared-video/list', { token: 'ops-token' }));
  assert.equal(list.status, 200);
  assert.equal(list.body.videos.length, 1);
  assert.equal(list.body.videos[0].bggId, '13');
  assert.equal(list.body.totalBytes, 2000);
  const again = await sharedUpload(ctx, '13', '1080', 3000, '');
  assert.equal(again.c.status, 200);
  assert.ok(ctx.storage.removed.includes(up.body.key));
  assert.equal(ctx.shared.map.get('13').title, '카탄'); // 이름을 비워 보내면 원래 이름 유지
  const del = await ctx.h(req('POST', '/api/ops/shared-video/delete', { token: 'ops-token', body: { bggId: '13', quality: 'all' } }));
  assert.equal(del.status, 200);
  assert.equal(ctx.shared.map.has('13'), false);
  assert.ok(ctx.storage.removed.includes(again.up.body.key));
});

test('공용 영상: 매장 영상을 공용으로 옮기기 (93차) — 미리 보기, BGG 번호 없음·이미 있음은 건너뜀, 파일은 그대로', async () => {
  const ctx = setupShared();
  ctx.games.docs.set('g3', { title: '번호 없는 게임' });
  ctx.games.listWithVideo = async (store) =>
    store === 'platform6' ? [...ctx.games.docs.entries()].map(([id, d]) => ({ id, ...JSON.parse(JSON.stringify(d)) })).filter((g) => g.ruleVideo && (g.ruleVideo.q1080 || g.ruleVideo.q720)) : [];
  // 매장 영상: 카탄(g1) 1080·720, 스플렌더(g2) 1080, 번호 없는 게임(g3) 1080
  const k1 = (await upload(ctx, 'g1', '1080', 1000)).up.body.key;
  await upload(ctx, 'g1', '720', 500);
  await upload(ctx, 'g2', '1080', 800);
  await upload(ctx, 'g3', '1080', 300);
  // 스플렌더는 이미 공용 영상이 있음
  await sharedUpload(ctx, '148228', '1080', 900, '스플렌더');
  const removedBefore = ctx.storage.removed.length;

  const ops = (body) => ctx.h(req('POST', '/api/ops/shared-video/move-store', { token: 'ops-token', body }));
  assert.equal((await ctx.h(req('POST', '/api/ops/shared-video/move-store', { token: 'admin-token', body: { storeId: 'platform6' } }))).status, 403);
  const dry = await ops({ storeId: 'platform6' });
  assert.equal(dry.status, 200, JSON.stringify(dry.body));
  assert.equal(dry.body.dryRun, true);
  assert.deepEqual(dry.body.moved.map((m) => m.gameId), ['g1']);
  assert.deepEqual(dry.body.moved[0].qualities, ['1080', '720']);
  assert.deepEqual(dry.body.skipped.map((s) => s.gameId).sort(), ['g2', 'g3']);
  assert.ok(ctx.games.docs.get('g1').ruleVideo.q1080, '미리 보기는 아무것도 안 바꿈');
  assert.equal(ctx.shared.map.has('13'), false);

  const run = await ops({ storeId: 'platform6', dryRun: false });
  assert.equal(run.status, 200, JSON.stringify(run.body));
  assert.equal(ctx.shared.map.get('13').q1080.key, k1); // 같은 파일을 그대로 가리킴
  assert.ok(ctx.shared.map.get('13').q720);
  assert.equal(ctx.games.docs.get('g1').ruleVideo.q1080, undefined);
  assert.ok(ctx.games.docs.get('g2').ruleVideo.q1080, '건너뛴 게임은 매장 영상 그대로');
  assert.equal(ctx.storage.removed.length, removedBefore, '파일은 하나도 안 지움');
  // 옮긴 뒤에도 패드 재생은 됨 (공용으로)
  const play = await ctx.h(req('GET', '/api/video/play-url', { token: 'guest-token', query: { gameId: 'g1' } }));
  assert.equal(play.status, 200);
  assert.equal(play.body.shared, true);
  assert.ok(play.body.q1080.url.includes(k1));
  // 한 번 더 돌리면 옮길 것 없음
  const again = await ops({ storeId: 'platform6', dryRun: false });
  assert.equal(again.body.moved.length, 0);
  });
