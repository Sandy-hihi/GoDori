'use strict';
// 월 정액권 앱 → 고도리 게임 맞추기 (149차)
//
// 월 정액권 앱(boardtrain-platform6, 다른 Firebase 프로젝트)이 게임의 '원본'. 고도리는 그 공개 게임 목록
// (P6_ORIGIN/api/public/games, 로그인 불필요)을 읽어 매장 games 에 반영만 함 — 정액권 앱 쪽으로는 아무것도 안 씀.
// 매장 기능 features.p6Sync(운영자가 켬, 기본 꺼짐)인 매장만. 지금은 플랫폼6 한 곳.
//
//   POST /api/p6/sync   (관리자) { dryRun: true }  → 미리보기(무엇이 바뀌는지)
//                                 { dryRun: false } → 맞추기. 80초 안에 다 못 하면 { done: false } → 관리자 웹이 다시 부름
//                       끝나면 settings/appRefresh.gamesUpdatedAt(패드 바로 다시 받기)
//   POST /api/p6/hook   (정액권 앱 서버가 부름, 로그인 없음 — 서명 확인) { store, ids: [정액권 게임 ID …] }
//                       헤더 x-godori-timestamp(밀리초) · x-godori-signature = hex(HMAC-SHA256(비밀값, `${timestamp}.${원본 본문}`))
//                       → 그 게임들만 다시 맞춤(목록에서 없어졌으면 숨김). 끝나면 settings/appRefresh.gamesChangedAt
//                       (패드는 이 값이 바뀌면 10분 조용할 때까지 기다렸다 한 번만 다시 받음 — game_catalog.dart, 읽기 비용 줄이기)
//
// 맞추는 규칙:
//  · 짝짓기: 고도리 문서 sourceId 'platform6:<정액권 ID>' (또는 문서 ID p6_<ID> — 5차 가져오기) →
//    없으면 고도리에 직접 추가했던(짝 없는) 게임 중 같은 BGG 번호(+확장판 여부) 하나 → 같은 이름(띄어쓰기·대소문자 무시) 하나 → 새로 만듦(p6_<ID>)
//  · 정액권 앱 값으로 덮어쓰는 칸: SYNC_FIELDS (이름·장르·인원·추천 인원·weight·난이도·순위·BGG 번호·확장판·매장 추천·추천 순서·한마디·추천한 때·한 줄 소개)
//    + NEW 표시(newHidden — 등록 30일 안의 게임만 봄) + 사진·룰북(정액권 사진 주소의 ?v= 가 바뀌었을 때만 복사)
//  · 고도리에만 있는 칸은 그대로: 소요시간(time)·태그·룰 영상·유튜브 링크·이용 가능(isAvailable)·등록 시각 등
//  · 정액권 앱에서 없어진 게임: 지우지 않고 isAvailable false + p6Removed true(손님 화면에서 숨김). 다시 생기면 되살림
//  · 고도리에만 있는 게임(짝 없음): 건드리지 않음
//  · 처음 맞출 때 이미 사진이 있는 게임은 사진을 받지 않고 정액권 사진 주소만 기록(p6Image) — 그 뒤 바뀔 때만 복사
//  · 정액권 장르가 고도리 장르 목록(settings/genres.items)에 없으면 뒤에 붙임

const crypto = require('crypto');

const P6_ORIGIN = 'https://boardtrain-platform6.web.app';
const SOURCE_PREFIX = 'platform6:';
const DOC_PREFIX = 'p6_';
const LIST_CACHE_MS = 60 * 1000;
const RUN_BUDGET_MS = 80 * 1000; // api 함수 제한 120초 안에서
const HOOK_MAX_IDS = 100;
const HOOK_TOLERANCE_MS = 5 * 60 * 1000;
const IMAGE_MAX_BYTES = 8 * 1024 * 1024;
const NEW_WINDOW_MS = 30 * 24 * 60 * 60 * 1000; // 고도리 isNewGame 과 같음
const LIST_MAX = 200; // 미리보기 목록 길이
const IMAGE_EXT = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

// 화면에 보여 줄 칸 이름
const FIELD_LABELS = {
  title: '이름', genres: '장르', players: '인원', minPlayers: '인원', maxPlayers: '인원', recommendedPlayers: '추천 인원',
  weight: '난이도(weight)', difficulty: '난이도', rank: 'BGG 순위', geekId: 'BGG 번호', expansion: '확장판',
  isRecommended: '매장 추천', pickRank: '추천 순서', pickNote: '추천 한마디', pickedAt: '매장 추천', intro: '한 줄 소개',
  newHidden: 'NEW 표시', imageUrl: '사진', rulebookImageUrl: '룰북 이미지',
};
const SYNC_FIELDS = ['title', 'genres', 'genre', 'players', 'minPlayers', 'maxPlayers', 'recommendedPlayers', 'weight',
  'difficulty', 'rank', 'geekId', 'expansion', 'isRecommended', 'pickRank', 'pickNote', 'pickedAt', 'intro'];

const DIFFICULTY_BUCKETS = [[1.3, '매우쉬움'], [1.6, '쉬움'], [2.1, '보통'], [2.6, '어려움'], [3.1, '매우어려움']];
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
const num = (v) => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const str = (v) => (v == null ? '' : String(v)).trim();
function msOf(v) {
  if (v == null || v === '') return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v === 'number') return v;
  const t = Date.parse(String(v));
  return Number.isNaN(t) ? null : t;
}
const normTitle = (s) => str(s).replace(/\s+/g, '').toLowerCase();

// 정액권 게임 1개 → 고도리 칸 (SYNC_FIELDS)
function p6Fields(g) {
  const genres = Array.isArray(g.genres) ? g.genres.map(str).filter(Boolean) : [];
  const minPlayers = num(g.minPlayers);
  const maxPlayers = num(g.maxPlayers);
  const weight = num(g.weight);
  const picked = Boolean(g.picked);
  const pickedAt = picked && msOf(g.pickedAt) != null ? new Date(msOf(g.pickedAt)) : null;
  return {
    title: str(g.name),
    genres,
    genre: genres[0] || '',
    players: playersText(minPlayers, maxPlayers),
    minPlayers,
    maxPlayers,
    recommendedPlayers: str(g.recommendedPlayers) || null,
    weight,
    difficulty: str(g.difficulty && g.difficulty.label) || difficultyLabel(weight),
    rank: num(g.rank),
    geekId: str(g.geekId) || null,
    expansion: Boolean(g.expansion),
    isRecommended: picked,
    pickRank: picked ? num(g.pickRank) : null,
    pickNote: str(g.pickNote),
    pickedAt,
    intro: str(g.intro),
  };
}

function sameValue(a, b) {
  if (a instanceof Date || b instanceof Date || (a && typeof a.toMillis === 'function') || (b && typeof b.toMillis === 'function')) {
    const x = msOf(a);
    const y = msOf(b);
    if (x == null || y == null) return x === y;
    return Math.floor(x / 1000) === Math.floor(y / 1000);
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => sameValue(v, b[i]));
  }
  if ((a == null || a === '') && (b == null || b === '')) return true;
  if (typeof a === 'number' || typeof b === 'number') return num(a) === num(b);
  return a === b;
}

function absUrl(u) {
  const s = str(u);
  if (!s) return '';
  if (/^https?:\/\//i.test(s)) return s;
  return P6_ORIGIN + (s.startsWith('/') ? s : `/${s}`);
}

// 정액권 목록 + 고도리 게임 → 할 일
//   p6Games: 공개 목록의 게임들   games: [{ id, data }] (고도리 그 매장 games 전부, 또는 hook 때는 관련 문서만)
//   onlyIds: hook 때 다시 볼 정액권 ID들 (없으면 전체)   now: 밀리초   genres: 고도리 장르 목록
function planSync({ p6Games, games, onlyIds = null, now = Date.now(), genres = [] }) {
  const p6ById = new Map();
  for (const g of p6Games) if (g && g.id && str(g.name)) p6ById.set(String(g.id), g);
  const wanted = onlyIds ? new Set(onlyIds.map(String)) : null;

  // 고도리 쪽 짝
  const linked = new Map(); // 정액권 ID → { id, data }
  const free = []; // 짝 없는 고도리 게임
  for (const doc of games) {
    const src = str(doc.data.sourceId);
    let pid = null;
    if (src.startsWith(SOURCE_PREFIX)) pid = src.slice(SOURCE_PREFIX.length);
    else if (doc.id.startsWith(DOC_PREFIX)) pid = doc.id.slice(DOC_PREFIX.length);
    if (pid && !linked.has(pid)) linked.set(pid, doc);
    else free.push(doc);
  }
  const usedFree = new Set();
  function findFree(f) {
    const pickOne = (list) => (list.length === 1 ? list[0] : null);
    if (f.geekId) {
      const hit = pickOne(free.filter((d) => !usedFree.has(d.id) && str(d.data.geekId) === f.geekId
        && Boolean(d.data.expansion) === f.expansion));
      if (hit) return hit;
    }
    const t = normTitle(f.title);
    if (!t) return null;
    return pickOne(free.filter((d) => !usedFree.has(d.id) && normTitle(d.data.title) === t));
  }

  const actions = [];
  const summary = { unchanged: 0, baseline: 0 };
  const genreList = Array.isArray(genres) ? genres.map(str).filter(Boolean) : [];
  const newGenres = [];

  for (const [pid, g] of p6ById) {
    if (wanted && !wanted.has(pid)) continue;
    const f = p6Fields(g);
    for (const x of f.genres) if (!genreList.includes(x) && !newGenres.includes(x)) newGenres.push(x);
    const image = absUrl(g.imageUrl);
    const rulebook = absUrl(g.rulebookImageUrl);
    let doc = linked.get(pid);
    let link = false;
    if (!doc) {
      doc = findFree(f);
      if (doc) {
        usedFree.add(doc.id);
        link = true;
      }
    }
    if (!doc) {
      const created = msOf(g.createdAt);
      actions.push({
        type: 'create', p6Id: pid, docId: DOC_PREFIX + pid, name: f.title,
        data: {
          ...f,
          newHidden: !g.isNew,
          bggName: null, time: '', tags: '', videoUrl: '', isAvailable: true,
          imageUrl: '', rulebookImageUrl: '',
          timestamp: new Date(created != null ? created : now),
          sourceId: SOURCE_PREFIX + pid,
        },
        image: image || null, rulebook: rulebook || null,
      });
      continue;
    }
    const d = doc.data;
    const patch = {};
    const changed = new Set();
    for (const k of SYNC_FIELDS) {
      if (!sameValue(d[k], f[k])) {
        patch[k] = f[k];
        if (FIELD_LABELS[k]) changed.add(FIELD_LABELS[k]);
      }
    }
    // NEW 표시는 등록 30일 안의 게임만 (오래된 게임은 어차피 NEW가 아님)
    const ts = msOf(d.timestamp);
    if (ts != null && now - ts < NEW_WINDOW_MS && Boolean(d.newHidden) !== !g.isNew) {
      patch.newHidden = !g.isNew;
      changed.add(FIELD_LABELS.newHidden);
    }
    if (link) patch.sourceId = SOURCE_PREFIX + pid;
    if (d.p6Removed === true) {
      patch.p6Removed = false;
      patch.isAvailable = true;
    }
    let getImage = null;
    let getRulebook = null;
    let baseline = false;
    if (image && str(d.p6Image) !== image) {
      if (!str(d.p6Image) && str(d.imageUrl)) {
        patch.p6Image = image; // 처음: 지금 사진을 그대로 두고 주소만 기록
        baseline = true;
      } else {
        getImage = image;
        changed.add(FIELD_LABELS.imageUrl);
      }
    }
    if (rulebook && str(d.p6Rulebook) !== rulebook) {
      if (!str(d.p6Rulebook) && str(d.rulebookImageUrl)) {
        patch.p6Rulebook = rulebook;
        baseline = true;
      } else {
        getRulebook = rulebook;
        changed.add(FIELD_LABELS.rulebookImageUrl);
      }
    }
    if (!Object.keys(patch).length && !getImage && !getRulebook) {
      summary.unchanged++;
      continue;
    }
    if (baseline && !changed.size && !link && d.p6Removed !== true) summary.baseline++;
    actions.push({
      type: d.p6Removed === true ? 'restore' : link ? 'link' : changed.size ? 'update' : 'quiet',
      p6Id: pid, docId: doc.id, name: f.title, godoriName: str(d.title),
      fields: [...changed], patch, image: getImage, rulebook: getRulebook,
    });
  }

  // 정액권 앱에서 없어진 게임 → 숨김
  for (const [pid, doc] of linked) {
    if (p6ById.has(pid)) continue;
    if (wanted && !wanted.has(pid)) continue;
    if (doc.data.p6Removed === true) continue;
    actions.push({
      type: 'hide', p6Id: pid, docId: doc.id, name: str(doc.data.title),
      patch: { isAvailable: false, p6Removed: true },
    });
  }

  const godoriOnly = wanted ? 0 : free.filter((d) => !usedFree.has(d.id)).length;
  return { actions, unchanged: summary.unchanged, baseline: summary.baseline, godoriOnly, newGenres, genreList, p6Count: p6ById.size };
}

function previewOf(plan, games) {
  const pick = (type, fn) => plan.actions.filter((a) => a.type === type).map(fn);
  const cap = (list) => ({ count: list.length, items: list.slice(0, LIST_MAX) });
  return {
    p6Count: plan.p6Count,
    godoriCount: games.length,
    create: cap(pick('create', (a) => ({ name: a.name, image: !!a.image }))),
    update: cap(pick('update', (a) => ({ name: a.name, fields: a.fields }))),
    link: cap(pick('link', (a) => ({ name: a.name, godoriName: a.godoriName, fields: a.fields }))),
    hide: cap(pick('hide', (a) => ({ name: a.name }))),
    restore: cap(pick('restore', (a) => ({ name: a.name }))),
    images: plan.actions.filter((a) => a.image || a.rulebook).length,
    baseline: plan.baseline,
    unchanged: plan.unchanged,
    godoriOnly: plan.godoriOnly,
    newGenres: plan.newGenres,
    todo: plan.actions.length,
  };
}

function signHook(secret, timestamp, rawBody) {
  return crypto.createHmac('sha256', secret).update(`${timestamp}.`).update(rawBody || '').digest('hex');
}
function verifyHook({ secret, headers, rawBody, now = Date.now() }) {
  const ts = String(headers['x-godori-timestamp'] || '');
  const sig = String(headers['x-godori-signature'] || '').trim().toLowerCase();
  if (!secret || !/^\d{10,16}$/.test(ts) || !/^[0-9a-f]{64}$/.test(sig)) return false;
  if (Math.abs(now - Number(ts)) > HOOK_TOLERANCE_MS) return false;
  const want = Buffer.from(signHook(secret, ts, rawBody));
  const got = Buffer.from(sig);
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

// data: createFirestoreP6Data / createMemoryP6Data   fetcher: { json(url), binary(url) }   stores: 매장 계정(features 확인)
// hookSecret: 정액권 앱과 나눠 가진 비밀값(없으면 hook 503)
function createP6SyncRoutes({ data, fetcher, stores, hookSecret = '', now = () => Date.now(), httpError }) {
  let cache = null;
  async function listP6Games(fresh = false) {
    if (!fresh && cache && now() - cache.at < LIST_CACHE_MS) return cache.games;
    let d;
    try {
      d = await fetcher.json(`${P6_ORIGIN}/api/public/games?t=${now()}`); // ?t= — 호스팅 캐시를 피함
    } catch (e) {
      throw httpError(502, 'P6_FETCH_FAILED', `월 정액권 앱 게임 목록을 받지 못했어요. (${(e && e.message) || '연결 실패'})`);
    }
    const games = d && Array.isArray(d.games) ? d.games.filter((g) => g && g.id && str(g.name)) : null;
    if (!games) throw httpError(502, 'P6_BAD_LIST', '월 정액권 앱 게임 목록 모양이 예상과 달라요.');
    if (!games.length) throw httpError(502, 'P6_EMPTY', '월 정액권 앱 게임 목록이 비어 있어요. 숨기기 사고를 막으려고 멈췄어요.');
    games.sort((a, b) => String(a.id).localeCompare(String(b.id)));
    cache = { at: now(), games };
    return games;
  }

  async function requireOn(storeId) {
    const acc = await stores.getAccount(storeId);
    if (!acc || !acc.features || acc.features.p6Sync !== true) {
      throw httpError(403, 'P6_SYNC_OFF', '월 정액권 앱 연동이 꺼져 있어요. 운영자에게 요청해 주세요.');
    }
  }

  async function copyImage(storeId, url, pid, kind) {
    let img;
    try {
      img = await fetcher.binary(url);
    } catch (e) {
      throw new Error(`사진을 받지 못했어요 (${(e && e.message) || '연결 실패'})`);
    }
    const ext = IMAGE_EXT[img.contentType];
    if (!ext) throw new Error(`사진 형식이 이상해요 (${img.contentType || '모름'})`);
    if (!img.buffer || !img.buffer.length || img.buffer.length > IMAGE_MAX_BYTES) throw new Error('사진 크기가 이상해요');
    const path = `stores/${storeId}/${kind === 'rulebook' ? 'rulebook_images' : 'game_images'}/p6_${pid}_${now()}.${ext}`;
    return data.saveImage(path, img.buffer, img.contentType);
  }

  async function applyAction(storeId, a) {
    if (a.type === 'create') {
      const doc = { ...a.data };
      if (a.image) {
        try {
          doc.imageUrl = await copyImage(storeId, a.image, a.p6Id, 'image');
          doc.p6Image = a.image;
        } catch (e) {
          a.warn = e.message; // 사진 없이라도 만듦 — 다음 맞추기 때 다시 받음
        }
      }
      if (a.rulebook) {
        try {
          doc.rulebookImageUrl = await copyImage(storeId, a.rulebook, a.p6Id, 'rulebook');
          doc.p6Rulebook = a.rulebook;
        } catch (e) {
          a.warn = e.message;
        }
      }
      await data.createGame(storeId, a.docId, doc);
      return;
    }
    const patch = { ...a.patch };
    if (a.image) {
      try {
        patch.imageUrl = await copyImage(storeId, a.image, a.p6Id, 'image');
        patch.p6Image = a.image;
      } catch (e) {
        a.warn = e.message;
      }
    }
    if (a.rulebook) {
      try {
        patch.rulebookImageUrl = await copyImage(storeId, a.rulebook, a.p6Id, 'rulebook');
        patch.p6Rulebook = a.rulebook;
      } catch (e) {
        a.warn = e.message;
      }
    }
    if (Object.keys(patch).length) await data.updateGame(storeId, a.docId, patch);
  }

  async function runActions(storeId, plan, started) {
    let applied = 0;
    const errors = [];
    const warnings = [];
    for (const a of plan.actions) {
      if (now() - started > RUN_BUDGET_MS) break;
      try {
        await applyAction(storeId, a);
        applied++;
        if (a.warn) warnings.push({ name: a.name, message: a.warn });
      } catch (e) {
        applied++; // 다음 부름에서 다시 계획하므로 건너뜀으로 셈
        errors.push({ name: a.name, message: (e && e.message) || '저장 실패' });
        console.warn('[정액권 연동] 실패', storeId, a.docId, e && e.message);
      }
    }
    if (plan.newGenres.length) await data.setGenres(storeId, [...plan.genreList, ...plan.newGenres]);
    return { applied, errors, warnings, done: applied >= plan.actions.length };
  }

  async function sync(req, ctx) {
    const user = await ctx.requireAdmin(req);
    ctx.rate(`p6sync:${user.store}`, 20, 60 * 1000, '정액권 앱 맞추기');
    await requireOn(user.store);
    const started = now();
    const body = req.body || {};
    const dryRun = body.dryRun !== false;
    const [p6Games, games, genres] = await Promise.all([listP6Games(dryRun) /* 미리보기는 새로, 맞추기는 방금 본 목록(1분 기억) */, data.listGames(user.store), data.getGenres(user.store)]);
    const plan = planSync({ p6Games, games, now: now(), genres });
    const preview = previewOf(plan, games);
    if (dryRun) return { ok: true, dryRun: true, ...preview, last: await data.getState(user.store) };
    const r = await runActions(user.store, plan, started);
    if (r.done) {
      if (plan.actions.length || plan.newGenres.length) await data.bumpRefresh(user.store, 'gamesUpdatedAt');
      await data.setState(user.store, {
        lastSyncAt: new Date(now()), lastSource: 'button',
        lastSummary: { create: preview.create.count, update: preview.update.count + preview.link.count, hide: preview.hide.count, restore: preview.restore.count },
      });
    }
    return { ok: true, dryRun: false, done: r.done, applied: r.applied, todo: plan.actions.length, errors: r.errors, warnings: r.warnings };
  }

  async function hook(req, ctx) {
    if (!hookSecret) throw httpError(503, 'P6_NO_SECRET', '연동 비밀값이 아직 등록되지 않았어요.');
    ctx.rate('p6hook', 120, 60 * 1000, '정액권 앱 신호');
    if (!verifyHook({ secret: hookSecret, headers: req.headers, rawBody: req.rawBody, now: now() })) {
      throw httpError(401, 'BAD_SIGNATURE', '서명이 맞지 않아요.');
    }
    const body = req.body || {};
    const storeId = str(body.store);
    if (!/^[a-z0-9][a-z0-9-]{2,29}$/.test(storeId)) throw httpError(400, 'INVALID_STORE', '매장 아이디가 올바르지 않아요.');
    const ids = Array.isArray(body.ids) ? [...new Set(body.ids.map(str).filter((x) => /^[A-Za-z0-9_-]{1,64}$/.test(x)))] : [];
    if (!ids.length) throw httpError(400, 'NO_IDS', '바뀐 게임 ID가 없어요.');
    if (ids.length > HOOK_MAX_IDS) throw httpError(400, 'TOO_MANY_IDS', `한 번에 ${HOOK_MAX_IDS}개까지예요.`);
    await requireOn(storeId);
    const started = now();
    const p6Games = await listP6Games(true);
    // 읽기 줄이기: 짝인 문서만 먼저, 짝 없는 새 게임이 있을 때만 전체를 읽어 이름·BGG 번호로 짝을 찾음
    let games = await data.getLinked(storeId, ids);
    const known = new Set(games.map((d) => str(d.data.sourceId).replace(SOURCE_PREFIX, '') || d.id.replace(DOC_PREFIX, '')));
    const p6Ids = new Set(p6Games.map((g) => String(g.id)));
    if (ids.some((id) => p6Ids.has(id) && !known.has(id))) games = await data.listGames(storeId);
    const plan = planSync({ p6Games, games, onlyIds: ids, now: now(), genres: await data.getGenres(storeId) });
    const r = await runActions(storeId, plan, started);
    if (plan.actions.length || plan.newGenres.length) await data.bumpRefresh(storeId, 'gamesChangedAt');
    await data.setState(storeId, { lastHookAt: new Date(now()), lastHookIds: ids.slice(0, 20), lastHookApplied: r.applied });
    console.log('[정액권 연동] 신호', storeId, ids.length, '개 →', r.applied, '개 반영', r.errors.length ? r.errors : '');
    return { ok: true, applied: r.applied, todo: plan.actions.length, done: r.done, errors: r.errors };
  }

  async function route(req, path, ctx) {
    if (path === '/api/p6/sync' && req.method === 'POST') return sync(req, ctx);
    if (path === '/api/p6/hook' && req.method === 'POST') return hook(req, ctx);
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  return { route, listP6Games };
}

// Firestore·Storage 저장소
function createFirestoreP6Data(db, getBucket) {
  const { Timestamp, FieldValue } = require('firebase-admin/firestore');
  const store = (s) => db.collection('stores').doc(s);
  const toFs = (obj) => {
    const out = {};
    for (const [k, v] of Object.entries(obj)) out[k] = v instanceof Date ? Timestamp.fromDate(v) : v;
    return out;
  };
  return {
    async listGames(s) {
      const snap = await store(s).collection('games').get();
      return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
    },
    async getLinked(s, ids) {
      const col = store(s).collection('games');
      const out = new Map();
      const refs = ids.map((id) => col.doc(DOC_PREFIX + id));
      if (refs.length) for (const d of await db.getAll(...refs)) if (d.exists) out.set(d.id, d.data());
      for (let i = 0; i < ids.length; i += 30) {
        const snap = await col.where('sourceId', 'in', ids.slice(i, i + 30).map((id) => SOURCE_PREFIX + id)).get();
        for (const d of snap.docs) out.set(d.id, d.data());
      }
      return [...out].map(([id, data]) => ({ id, data }));
    },
    async createGame(s, id, doc) {
      await store(s).collection('games').doc(id).set(toFs(doc));
    },
    async updateGame(s, id, patch) {
      await store(s).collection('games').doc(id).set(toFs(patch), { merge: true });
    },
    async getGenres(s) {
      const d = await store(s).collection('settings').doc('genres').get();
      const items = d.exists ? d.get('items') : null;
      return Array.isArray(items) ? items : [];
    },
    async setGenres(s, list) {
      await store(s).collection('settings').doc('genres').set({ items: list }, { merge: true });
    },
    async bumpRefresh(s, field) {
      await store(s).collection('settings').doc('appRefresh').set({ [field]: FieldValue.serverTimestamp() }, { merge: true });
    },
    async getState(s) {
      const d = await store(s).collection('private').doc('p6Sync').get();
      if (!d.exists) return null;
      const x = d.data();
      const iso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : null);
      return { lastSyncAt: iso(x.lastSyncAt), lastSource: x.lastSource || null, lastSummary: x.lastSummary || null, lastHookAt: iso(x.lastHookAt) };
    },
    async setState(s, fields) {
      await store(s).collection('private').doc('p6Sync').set(toFs(fields), { merge: true });
    },
    async saveImage(path, buffer, contentType) {
      const bucket = getBucket();
      const token = crypto.randomUUID();
      await bucket.file(path).save(buffer, {
        resumable: false,
        contentType,
        metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } },
      });
      return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
    },
  };
}

// 정액권 앱에서 받기 (Node 22 fetch)
const p6Fetcher = {
  async json(url) {
    const res = await fetch(url, { headers: { Accept: 'application/json', 'Cache-Control': 'no-cache' } });
    if (!res.ok) throw new Error(`응답 ${res.status}`);
    return res.json();
  },
  async binary(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`응답 ${res.status}`);
    const contentType = String(res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
    return { buffer: Buffer.from(await res.arrayBuffer()), contentType };
  },
};

// 테스트용 메모리 저장소
function createMemoryP6Data({ games = {}, genres = [] } = {}) {
  const g = new Map(Object.entries(games).map(([id, d]) => [id, { ...d }]));
  const state = { genres: [...genres], refresh: {}, private: {}, images: [] };
  return {
    games: g,
    state,
    async listGames() { return [...g].map(([id, data]) => ({ id, data: { ...data } })); },
    async getLinked(_s, ids) {
      const want = new Set(ids);
      return [...g].filter(([id, d]) => want.has(id.replace(DOC_PREFIX, '')) || want.has(str(d.sourceId).replace(SOURCE_PREFIX, '')))
        .map(([id, data]) => ({ id, data: { ...data } }));
    },
    async createGame(_s, id, doc) { g.set(id, { ...doc }); },
    async updateGame(_s, id, patch) { g.set(id, { ...(g.get(id) || {}), ...patch }); },
    async getGenres() { return [...state.genres]; },
    async setGenres(_s, list) { state.genres = [...list]; },
    async bumpRefresh(_s, field) { state.refresh[field] = (state.refresh[field] || 0) + 1; },
    async getState() { return state.private.lastSyncAt ? { ...state.private } : null; },
    async setState(_s, f) { Object.assign(state.private, f); },
    async saveImage(path) { state.images.push(path); return `https://img/${path}`; },
  };
}

module.exports = {
  createP6SyncRoutes, createFirestoreP6Data, createMemoryP6Data, p6Fetcher, planSync, p6Fields, signHook, verifyHook,
  P6_ORIGIN, SYNC_FIELDS,
};
