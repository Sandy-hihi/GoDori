'use strict';
// 149차 월 정액권 앱 → 고도리 게임 맞추기 — 실행: cd functions && node --test test/*.test.js
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const { createP6SyncRoutes, createMemoryP6Data, planSync, signHook } = require('../src/p6-sync');

const NOW = Date.parse('2026-11-26T09:00:00Z');
const httpError = (status, code, message) => Object.assign(new Error(message), { status, code });
const p6 = (id, extra = {}) => ({
  id, name: `게임${id}`, minPlayers: 2, maxPlayers: 4, recommendedPlayers: '3', weight: 1.5, rank: 100,
  createdAt: '2026-09-01T00:00:00Z', isNew: false, genres: ['가족'], picked: false, pickNote: '', pickedAt: null,
  pickRank: null, expansion: false, difficulty: { label: '쉬움' }, geekId: `9${id}`, intro: '',
  imageUrl: `/api/games/${id}/image?v=1`, rulebookImageUrl: null, ...extra,
});
// 5차 가져오기로 들어온 모양 그대로 (정액권과 같은 값)
const godori = (id, extra = {}) => ({
  title: `게임${id}`, genres: ['가족'], genre: '가족', players: '2~4인', minPlayers: 2, maxPlayers: 4, recommendedPlayers: '3',
  weight: 1.5, difficulty: '쉬움', rank: 100, geekId: `9${id}`, expansion: false, isRecommended: false, pickRank: null,
  pickNote: '', pickedAt: null, isAvailable: true, newHidden: true, imageUrl: 'https://old/img', rulebookImageUrl: '',
  timestamp: new Date('2026-09-01T00:00:00Z'), sourceId: `platform6:${id}`, time: '30~60분', videoUrl: 'https://yt', ...extra,
});

function make({ list, games, features = { p6Sync: true }, secret = 'hook-secret' }) {
  const data = createMemoryP6Data({ games, genres: ['가족', '파티'] });
  const fetched = [];
  const fetcher = {
    async json(url) { fetched.push(url); return { games: list() }; },
    async binary(url) { fetched.push(url); return { buffer: Buffer.from('img'), contentType: 'image/png' }; },
  };
  const stores = createMemoryStores({ platform6: { name: '플랫폼6', status: 'active', account: {}, features } });
  const h = createHandler({
    bgg: {}, stores, attempts: createMemoryAttempts(),
    verifyIdToken: async (t) => {
      if (t === 'admin-token') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
      if (t === 'pad-token') return { uid: 'pad.platform6.1', pad: true, room: 1, store: 'platform6' };
      throw new Error('bad');
    },
    createToken: async () => 'x',
    p6sync: createP6SyncRoutes({ data, fetcher, stores, hookSecret: secret, now: () => NOW, httpError }),
  });
  return { h, data, fetched };
}
const sync = (h, dryRun, token = 'admin-token') => h({
  method: 'POST', path: '/api/p6/sync', query: {}, body: { dryRun }, headers: { authorization: `Bearer ${token}` },
});
function hook(h, body, { secret = 'hook-secret', ts = NOW } = {}) {
  const raw = JSON.stringify(body);
  return h({
    method: 'POST', path: '/api/p6/hook', query: {}, body, rawBody: Buffer.from(raw),
    headers: { 'x-godori-timestamp': String(ts), 'x-godori-signature': signHook(secret, String(ts), raw) },
  });
}

test('같은 게임은 그대로, 처음엔 사진 주소만 기록(사진 안 받음), 고도리 칸(소요시간·영상)은 안 건드림', async () => {
  const { h, data, fetched } = make({ list: () => [p6('a'), p6('b')], games: { p6_a: godori('a'), p6_b: godori('b') } });
  const pre = await sync(h, true);
  assert.equal(pre.status, 200);
  assert.equal(pre.body.update.count, 0);
  assert.equal(pre.body.create.count, 0);
  assert.equal(pre.body.baseline, 2);
  assert.equal(pre.body.images, 0);
  const run = await sync(h, false);
  assert.equal(run.body.done, true);
  assert.equal(data.games.get('p6_a').p6Image, 'https://boardtrain-platform6.web.app/api/games/a/image?v=1');
  assert.equal(data.games.get('p6_a').imageUrl, 'https://old/img');
  assert.equal(data.games.get('p6_a').time, '30~60분');
  assert.equal(data.state.images.length, 0);
  assert.ok(fetched.every((u) => !u.includes('/image')));
  // 두 번째는 할 일 없음
  const again = await sync(h, true);
  assert.equal(again.body.todo, 0);
  assert.equal(again.body.unchanged, 2);
});

test('바뀐 칸만 덮어씀 · 새 게임 만들기(사진 복사) · 없어진 게임 숨김 · 새 장르 추가 · 패드 새로고침', async () => {
  let list = [p6('a', { name: '새이름', picked: true, pickRank: 1, pickedAt: '2026-11-20T00:00:00Z', imageUrl: '/api/games/a/image?v=2' }),
    p6('c', { genres: ['협력'], isNew: true, createdAt: '2026-11-25T00:00:00Z' })];
  const games = { p6_a: godori('a', { p6Image: 'https://boardtrain-platform6.web.app/api/games/a/image?v=1' }), p6_b: godori('b') };
  const { h, data } = make({ list: () => list, games });
  const pre = await sync(h, true);
  assert.equal(pre.body.update.count, 1);
  assert.deepEqual(pre.body.update.items[0].fields.sort(), ['매장 추천', '사진', '이름', '추천 순서'].sort());
  assert.equal(pre.body.create.count, 1);
  assert.equal(pre.body.hide.count, 1);
  assert.deepEqual(pre.body.newGenres, ['협력']);
  const run = await sync(h, false);
  assert.equal(run.body.done, true);
  const a = data.games.get('p6_a');
  assert.equal(a.title, '새이름');
  assert.equal(a.isRecommended, true);
  assert.equal(a.videoUrl, 'https://yt');
  assert.ok(a.imageUrl.startsWith('https://img/stores/platform6/game_images/p6_a_'));
  const c = data.games.get('p6_c');
  assert.equal(c.sourceId, 'platform6:c');
  assert.equal(c.isAvailable, true);
  assert.equal(c.newHidden, false);
  assert.ok(c.imageUrl);
  assert.equal(data.games.get('p6_b').isAvailable, false);
  assert.equal(data.games.get('p6_b').p6Removed, true);
  assert.deepEqual(data.state.genres, ['가족', '파티', '협력']);
  assert.equal(data.state.refresh.gamesUpdatedAt, 1);
  // b가 다시 생기면 되살림
  list = [...list, p6('b')];
  await sync(h, true); // 목록 새로 받기
  await sync(h, false);
  assert.equal(data.games.get('p6_b').isAvailable, true);
  assert.equal(data.games.get('p6_b').p6Removed, false);
});

test('고도리에 직접 추가한 게임은 BGG 번호·이름으로 짝지음, 짝 없는 고도리 게임은 그대로', async () => {
  const games = {
    hand1: godori('x', { sourceId: undefined, geekId: '9d', title: '다른이름' }),
    hand2: godori('y', { sourceId: undefined, geekId: null, title: '게임 E' }),
    mine: godori('z', { sourceId: undefined, geekId: '777', title: '고도리만' }),
  };
  const { h, data } = make({ list: () => [p6('d'), p6('e', { geekId: null, name: '게임E' })], games });
  const pre = await sync(h, true);
  assert.equal(pre.body.link.count, 2);
  assert.equal(pre.body.create.count, 0);
  assert.equal(pre.body.godoriOnly, 1);
  await sync(h, false);
  assert.equal(data.games.get('hand1').sourceId, 'platform6:d');
  assert.equal(data.games.get('hand1').title, '게임d');
  assert.equal(data.games.get('hand2').sourceId, 'platform6:e');
  assert.equal(data.games.get('mine').sourceId, undefined);
  assert.equal(data.games.size, 3);
});

test('신호: 서명 확인 · 그 게임만 · gamesChangedAt', async () => {
  const list = [p6('a', { name: '바뀜' }), p6('b', { name: '이것도 바뀜' })];
  const { h, data } = make({ list: () => list, games: { p6_a: godori('a'), p6_b: godori('b') } });
  const bad = await hook(h, { store: 'platform6', ids: ['a'] }, { secret: 'wrong' });
  assert.equal(bad.status, 401);
  const old = await hook(h, { store: 'platform6', ids: ['a'] }, { ts: NOW - 10 * 60 * 1000 });
  assert.equal(old.status, 401);
  const ok = await hook(h, { store: 'platform6', ids: ['a'] });
  assert.equal(ok.status, 200);
  assert.equal(data.games.get('p6_a').title, '바뀜');
  assert.equal(data.games.get('p6_b').title, '게임b');
  assert.equal(data.state.refresh.gamesChangedAt, 1);
  assert.equal(data.state.refresh.gamesUpdatedAt, undefined);
  // 정액권에서 지워진 게임 신호 → 숨김
  const gone = await hook(h, { store: 'platform6', ids: ['zz', 'b'] });
  assert.equal(gone.status, 200);
  assert.equal(data.games.get('p6_b').title, '이것도 바뀜');
});

test('꺼진 매장·관리자 아님·빈 목록은 막음', async () => {
  const off = make({ list: () => [p6('a')], games: {}, features: {} });
  assert.equal((await sync(off.h, true)).status, 403);
  assert.equal((await hook(off.h, { store: 'platform6', ids: ['a'] })).status, 403);
  const on = make({ list: () => [], games: { p6_a: godori('a') } });
  assert.equal((await sync(on.h, true, 'pad-token')).status, 403);
  const empty = await sync(on.h, false);
  assert.equal(empty.status, 502); // 빈 목록이면 전부 숨기지 않게 멈춤
  assert.equal(on.data.games.get('p6_a').isAvailable, true);
  const noSecret = make({ list: () => [p6('a')], games: {}, secret: '' });
  assert.equal((await hook(noSecret.h, { store: 'platform6', ids: ['a'] })).status, 503);
});

test('planSync: 30일 지난 게임은 NEW 표시를 안 봄', () => {
  const plan = planSync({ p6Games: [p6('a', { isNew: true })], games: [{ id: 'p6_a', data: godori('a', { p6Image: 'https://boardtrain-platform6.web.app/api/games/a/image?v=1' }) }], now: NOW });
  assert.equal(plan.actions.length, 0);
});
