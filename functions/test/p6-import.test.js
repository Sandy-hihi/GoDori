'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { createP6Importer, toBoardpadGame } = require('../src/p6-import');
const { createHandler } = require('../src/app');

const P6 = [
  { id: 'b', name: '카탄', minPlayers: 3, maxPlayers: 4, recommendedPlayers: '4', weight: 2.29, rank: 600, genres: ['가족', '전략'], picked: true, pickNote: '입문 추천', pickRank: 1, pickedAt: '2026-10-01T00:00:00.000Z', expansion: false, isNew: false, difficulty: { label: '어려움' }, geekId: '13', imageUrl: '/api/games/b/image?v=1', createdAt: '2026-09-01T00:00:00.000Z' },
  { id: 'a', name: '할리갈리', minPlayers: 2, maxPlayers: 6, genres: ['파티'], isNew: true, imageUrl: null, createdAt: '2026-10-10T00:00:00.000Z' },
  { id: 'c', name: '사진깨짐', minPlayers: 2, maxPlayers: 2, genres: ['2인', '없는장르'], imageUrl: '/api/games/c/image?v=1' },
];
function fakes() {
  const saved = { games: {}, images: {}, genres: null, backups: [] };
  const store = {
    async backupAndClearGames(name) { saved.backups.push(name); return { backedUp: 5 }; },
    async setGenres(list) { saved.genres = list; },
    async putGame(id, data) { saved.games[id] = data; },
    async saveImage(path) { saved.images[path] = true; return `https://img/${path}`; },
  };
  const fetcher = {
    async json() { return { games: P6 }; },
    async binary(url) { if (url.includes('/c/')) throw new Error('404'); return { buffer: Buffer.from('x'), contentType: 'image/png' }; },
  };
  return { saved, importer: createP6Importer({ store, fetcher, now: () => new Date('2026-10-14T14:30:00Z') }) };
}

test('필드 변환', () => {
  const g = toBoardpadGame(P6[0]);
  assert.equal(g.title, '카탄');
  assert.deepEqual(g.genres, ['가족', '전략']);
  assert.equal(g.genre, '가족');
  assert.equal(g.players, '3~4인');
  assert.equal(g.difficulty, '어려움');
  assert.equal(g.isRecommended, true);
  assert.equal(g.pickRank, 1);
  assert.equal(g.newHidden, true);
  assert.ok(g.timestamp instanceof Date);
  assert.deepEqual(toBoardpadGame(P6[2]).genres, ['2인']);
  assert.equal(toBoardpadGame(P6[2]).players, '2인');
});
test('start: 백업 이름(한국 시간)·장르 교체', async () => {
  const { saved, importer } = fakes();
  const r = await importer.start();
  assert.equal(r.total, 3);
  assert.equal(r.backup, 'games_backup_20261014_2330');
  assert.equal(r.backedUp, 5);
  assert.equal(saved.genres.length, 8);
});
test('batch: id 순서로 나눠 가져오고, 사진 실패해도 게임은 등록', async () => {
  const { saved, importer } = fakes();
  const r1 = await importer.batch(0, 2);
  assert.deepEqual(r1.results.map((x) => x.name), ['할리갈리', '카탄']);
  assert.equal(r1.done, false);
  const r2 = await importer.batch(2, 2);
  assert.equal(r2.done, true);
  assert.equal(r2.results[0].ok, true);
  assert.equal(r2.results[0].photo, false);
  assert.equal(saved.games.p6_b.imageUrl, 'https://img/game_images/p6_b.png');
  assert.equal(Object.keys(saved.games).length, 3);
});
test('API: 확인 문구 없으면 거절, 비밀번호 필요', async () => {
  const { importer } = fakes();
  const h = createHandler({ bgg: {}, importer, getAdminPassword: async () => '123456' });
  const mk = (path, body, pw = '123456') => ({ method: 'POST', path, query: {}, body, headers: pw ? { 'x-admin-password': pw } : {} });
  assert.equal((await h(mk('/api/import/p6/start', {}, null))).status, 401);
  assert.equal((await h(mk('/api/import/p6/start', {}))).status, 400);
  const ok = await h(mk('/api/import/p6/start', { confirm: '교체' }));
  assert.equal(ok.status, 200);
  const b = await h(mk('/api/import/p6/batch', { offset: 0, limit: 10 }));
  assert.equal(b.status, 200);
  assert.equal(b.body.results.length, 3);
});
