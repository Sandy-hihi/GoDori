'use strict';
// 월정액권 앱(boardtrain-platform6)의 게임 목록을 보드패드로 옮기기.
// 월정액권 앱의 공개 게임 목록(/api/public/games, 로그인 불필요)과 게임 사진을 서버가 받아서
// 보드패드 Firestore(games)와 Storage(game_images/)에 넣는다.
//
//  start(): 기존 보드패드 게임을 games_backup_<날짜시각> 컬렉션에 복사 → games 비움 → 장르 목록 교체
//           (기존 사진 파일은 지우지 않음 — 백업 문서의 사진 주소가 계속 살아 있게)
//  batch(offset, limit): 월정액권 게임 offset부터 limit개를 사진과 함께 등록 (같은 문서 ID로 덮어써서 다시 해도 안전)

const P6_ORIGIN = 'https://boardtrain-platform6.web.app';
const P6_GENRES = ['파티', '가족', '전략', '추상전략', '추리', '머미', '2인', '협력'];
const BATCH_MAX = 25;

const DIFFICULTY_BUCKETS = [
  [1.3, '매우쉬움'],
  [1.6, '쉬움'],
  [2.1, '보통'],
  [2.6, '어려움'],
  [3.1, '매우어려움'],
];
function difficultyLabel(weight) {
  if (weight == null || !Number.isFinite(weight) || weight <= 0) return '';
  for (const [max, label] of DIFFICULTY_BUCKETS) if (weight < max) return label;
  return '전문';
}
function playersText(min, max) {
  if (min == null && max == null) return '';
  if (min == null || max == null || min === max) return `${min ?? max}인`;
  return `${min}~${max}인`;
}
const IMAGE_EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

// 월정액권 게임 1개 -> 보드패드 games 문서 (timestamp/pickedAt은 Date로 — 저장할 때 Firestore Timestamp가 됨)
function toBoardpadGame(g) {
  const genres = P6_GENRES.filter((x) => (g.genres || []).includes(x));
  const num = (v) => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
  const minPlayers = num(g.minPlayers);
  const maxPlayers = num(g.maxPlayers);
  const weight = num(g.weight);
  const created = g.createdAt && !Number.isNaN(Date.parse(g.createdAt)) ? new Date(g.createdAt) : null;
  return {
    title: String(g.name || '').trim(),
    genres,
    genre: genres[0] || '',
    players: playersText(minPlayers, maxPlayers),
    difficulty: (g.difficulty && g.difficulty.label) || difficultyLabel(weight),
    minPlayers,
    maxPlayers,
    recommendedPlayers: g.recommendedPlayers ? String(g.recommendedPlayers) : null,
    weight,
    rank: num(g.rank),
    geekId: g.geekId ? String(g.geekId) : null,
    bggName: null,
    time: '',
    tags: '',
    videoUrl: '',
    pickNote: String(g.pickNote || ''),
    expansion: Boolean(g.expansion),
    isAvailable: true,
    isRecommended: Boolean(g.picked),
    pickRank: num(g.pickRank),
    pickedAt: g.picked && g.pickedAt && !Number.isNaN(Date.parse(g.pickedAt)) ? new Date(g.pickedAt) : null,
    // 월정액권 앱에서 NEW로 보이던 게임만 NEW 유지
    newHidden: !g.isNew,
    imageUrl: '',
    rulebookImageUrl: '',
    timestamp: created || new Date(0),
    sourceId: `platform6:${g.id}`,
  };
}

// store: { backupAndClearGames(name) -> {backedUp}, setGenres(list), putGame(id, data), saveImage(path, buffer, contentType) -> url }
// fetcher: { json(url), binary(url) -> { buffer, contentType } }
function createP6Importer({ store, fetcher, now = () => new Date() }) {
  async function listP6Games() {
    const d = await fetcher.json(`${P6_ORIGIN}/api/public/games`);
    const games = (d && Array.isArray(d.games) ? d.games : []).filter((g) => g && g.id && g.name);
    // 항상 같은 순서로 (offset으로 나눠 가져오기 때문에)
    games.sort((a, b) => String(a.id).localeCompare(String(b.id)));
    return games;
  }

  async function start() {
    const games = await listP6Games();
    if (!games.length) {
      const e = new Error('월정액권 앱에서 게임 목록을 받지 못했어요.');
      e.status = 502;
      throw e;
    }
    const t = now();
    const pad = (n) => String(n).padStart(2, '0');
    // 한국 시간 기준 이름
    const k = new Date(t.getTime() + 9 * 3600 * 1000);
    const backup = `games_backup_${k.getUTCFullYear()}${pad(k.getUTCMonth() + 1)}${pad(k.getUTCDate())}_${pad(k.getUTCHours())}${pad(k.getUTCMinutes())}`;
    const { backedUp } = await store.backupAndClearGames(backup);
    await store.setGenres(P6_GENRES);
    return { total: games.length, backup, backedUp, genres: P6_GENRES };
  }

  async function batch(offset, limit) {
    const off = Math.max(0, Number(offset) || 0);
    const lim = Math.min(BATCH_MAX, Math.max(1, Number(limit) || 10));
    const games = await listP6Games();
    const slice = games.slice(off, off + lim);
    const results = [];
    for (const g of slice) {
      const id = `p6_${g.id}`;
      const data = toBoardpadGame(g);
      let photo = false;
      if (g.imageUrl) {
        try {
          const img = await fetcher.binary(`${P6_ORIGIN}${g.imageUrl}`);
          const ext = IMAGE_EXT[img.contentType];
          if (ext) {
            data.imageUrl = await store.saveImage(`game_images/${id}.${ext}`, img.buffer, img.contentType);
            photo = true;
          }
        } catch (e) {
          console.warn('[가져오기] 사진 실패', g.name, e && e.message);
        }
      }
      try {
        await store.putGame(id, data);
        results.push({ name: data.title, ok: true, photo, hadPhoto: Boolean(g.imageUrl) });
      } catch (e) {
        console.error('[가져오기] 저장 실패', g.name, e);
        results.push({ name: data.title, ok: false, photo: false, hadPhoto: Boolean(g.imageUrl) });
      }
    }
    return { total: games.length, offset: off, next: off + slice.length, done: off + slice.length >= games.length, results };
  }

  return { start, batch };
}

module.exports = { createP6Importer, toBoardpadGame, P6_GENRES };
