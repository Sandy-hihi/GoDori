'use strict';
// 룰 설명 영상 API (영상 파일은 Cloudflare R2에 있음 — src/r2.js)
//
//   POST /api/video/upload-url  (관리자) { gameId, quality: '1080'|'720', size, contentType }
//        -> { uploadUrl, key, contentType, expiresIn }   관리자 웹이 이 주소로 파일을 직접 PUT
//   POST /api/video/confirm     (관리자) { gameId, quality, key, meta: { width, height, fps, durationSec, videoCodec } }
//        -> { video }   올라간 파일을 확인하고 games/{gameId}.ruleVideo.q1080(또는 q720)에 기록, 예전 파일은 지움
//   POST /api/video/delete      (관리자) { gameId, quality: '1080'|'720'|'all' } -> { ok }
//   GET  /api/video/play-url?gameId=..&count=1  (로그인한 패드·관리자)
//        -> { q1080: { url, width, height }, q720: {...}, expiresIn }   재생용 임시 주소. count=0이면 재생 횟수 안 셈
//
// 47차부터 매장별: 게임 문서는 stores/{매장}/games/{gameId}, 새로 올리는 파일 키는 rule-videos/<매장>/<게임>/…
// (그 전에 올린 rule-videos/<게임>/… 키도 재생·삭제는 그대로 됨)
//
// 92차 공용 영상 보관함: 운영자가 BGG 번호 기준으로 한 번만 올리면 모든 매장이 같이 씀 (매장마다 같은 영상을 따로 저장하지 않게)
//   파일 키 rule-videos/_shared/<BGG 번호>/<시각>_<화질>.mp4  ('_'는 매장 아이디에 못 쓰는 글자라 매장 폴더와 안 겹침)
//   기록 Firestore shared/ruleVideos { videos: { <BGG 번호>: { title, q1080, q720, updatedAt } }, updatedAt } (서버만 씀, 로그인한 앱은 읽기)
//   재생: 매장 영상(games.ruleVideo)이 있으면 그것, 없으면 그 게임 geekId의 공용 영상
//   POST /api/ops/shared-video/upload-url { bggId, quality, size, contentType } · confirm { bggId, quality, key, meta, title } · delete { bggId, quality }
//   GET  /api/ops/shared-video/list  (운영자, app.js opsRoute)
//
// 영상 규격(41차): 1080p 30fps H.264 + AAC, MP4. 720p 파일은 선택(있으면 패드가 버퍼링 때 720p로 바꿔 틂).
// R2 설정이 없으면(아직 Cloudflare 연결 전) 모든 영상 API가 503 R2_NOT_CONNECTED.

const MAX_BYTES = 700 * 1024 * 1024; // 8분 1080p ≈ 250MB. 여유 있게 700MB까지
const UPLOAD_EXPIRES = 60 * 60; // 올리기 임시 주소 1시간 (올리기 "시작"까지만 유효하면 됨)
const PLAY_EXPIRES = 4 * 60 * 60; // 재생 임시 주소 4시간
const QUALITIES = ['1080', '720'];
const KEY_PREFIX = 'rule-videos/';
const SHARED_PREFIX = `${KEY_PREFIX}_shared/`;
const BGG_ID_RE = /^\d{1,9}$/;

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function cleanGameId(v) {
  const id = String(v == null ? '' : v).trim();
  // Firestore 문서 ID 규칙: '/' 불가, '.'·'..' 불가, 1500바이트 이하 (여기선 150자로 제한)
  if (!id || id.length > 150 || id.includes('/') || id === '.' || id === '..' || /[\u0000-\u001f]/.test(id)) {
    throw httpError(400, 'INVALID_GAME_ID', '게임 ID가 올바르지 않아요.');
  }
  return id;
}

function cleanQuality(v, { allowAll = false } = {}) {
  const q = String(v == null ? '' : v).trim();
  if (QUALITIES.includes(q) || (allowAll && q === 'all')) return q;
  throw httpError(400, 'INVALID_QUALITY', '화질은 1080 또는 720이어야 해요.');
}

function cleanBggId(v) {
  const id = String(v == null ? '' : v).trim();
  if (!BGG_ID_RE.test(id)) throw httpError(400, 'INVALID_BGG_ID', 'BGG 번호(숫자)를 확인해 주세요.');
  return id;
}

// 게임 문서의 BGG 번호 (없거나 이상하면 null)
function bggIdOf(game) {
  const id = String((game && game.geekId) == null ? '' : game.geekId).trim();
  return BGG_ID_RE.test(id) ? id : null;
}

const num = (v, max) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 && n <= max ? n : null;
};

/**
 * storage: createR2Storage(...) 결과 또는 null(연결 안 됨)
 * games:   { get(storeId, gameId) -> 문서 데이터|null, setRuleVideo(storeId, gameId, 'q1080'|'q720', info|null) }
 * stats:   { recordPlay(storeId, gameId, title, bytesEst), recordUpload?(storeId, bytes, oldBytes), recordRemove?(storeId, bytes) }  (선택)
 *          bytesEst = 처음 여는 화질 파일 크기(전송량 추정용), upload/remove는 매장별 R2 저장 용량 기록용
 * 모든 함수의 storeId는 로그인 토큰의 매장 (app.js가 넘김)
 * shared:  공용 영상 기록 (92차, 없으면 공용 영상 안 씀)
 *          { get(bggId) -> { title, q1080?, q720? }|null, set(bggId, 'q1080'|'q720', info|null, title), list() -> { <bggId>: entry } }
 */
function createVideoApi({ storage, games, shared = null, stats = null, now = () => Date.now() }) {
  function needStorage() {
    if (!storage) throw httpError(503, 'R2_NOT_CONNECTED', '영상 저장소(Cloudflare R2)가 아직 연결되지 않았어요.');
  }

  function needStore(storeId) {
    if (typeof storeId !== 'string' || !/^[a-z0-9][a-z0-9-]{2,29}$/.test(storeId)) {
      throw httpError(403, 'RELOGIN', '매장 아이디로 다시 로그인해 주세요.');
    }
    return storeId;
  }

  async function needGame(storeId, gameId) {
    const g = await games.get(storeId, gameId);
    if (!g) throw httpError(404, 'GAME_NOT_FOUND', '게임을 찾을 수 없어요.');
    return g;
  }

  function needShared() {
    if (!shared) throw httpError(503, 'NO_SHARED', '공용 영상 기능이 연결되지 않았어요.');
  }

  // 올리기 전 검사 (매장·공용 같이 씀) → { quality, contentType }
  function checkUpload(body) {
    const quality = cleanQuality(body.quality);
    const size = Number(body.size);
    if (!Number.isFinite(size) || size <= 0) throw httpError(400, 'INVALID_SIZE', '파일 크기를 확인해 주세요.');
    if (size > MAX_BYTES) {
      throw httpError(413, 'TOO_LARGE', `영상이 너무 커요. ${Math.round(MAX_BYTES / 1024 / 1024)}MB 이하로 만들어 주세요.`);
    }
    const contentType = String(body.contentType || 'video/mp4').toLowerCase();
    if (contentType !== 'video/mp4') throw httpError(415, 'NOT_MP4', 'MP4 영상만 올릴 수 있어요.');
    return { quality, contentType };
  }

  // 올라간 파일 확인 (키 모양 → 저장소 HEAD → 크기) → 저장할 정보
  async function checkUploaded(key, prefix, quality, metaBody) {
    const rest = key.startsWith(prefix) ? key.slice(prefix.length) : '';
    if (!new RegExp(`^\\d{10,16}_${quality}\\.mp4$`).test(rest)) {
      throw httpError(400, 'INVALID_KEY', '올린 파일 정보가 올바르지 않아요. 다시 올려 주세요.');
    }
    const head = await storage.head(key);
    if (!head) throw httpError(404, 'UPLOAD_MISSING', '영상이 저장소에 올라가지 않았어요. 다시 올려 주세요.');
    if (head.size > MAX_BYTES) {
      await storage.remove(key).catch(() => {});
      throw httpError(413, 'TOO_LARGE', '영상이 너무 커요.');
    }
    const meta = metaBody && typeof metaBody === 'object' ? metaBody : {};
    return {
      key,
      sizeBytes: head.size,
      width: num(meta.width, 10000),
      height: num(meta.height, 10000),
      fps: num(meta.fps, 1000),
      durationSec: num(meta.durationSec, 24 * 3600),
      videoCodec: typeof meta.videoCodec === 'string' ? meta.videoCodec.slice(0, 20) : null,
      uploadedAt: new Date(now()),
    };
  }

  async function uploadUrl(body, storeId) {
    needStorage();
    needStore(storeId);
    const gameId = cleanGameId(body.gameId);
    const { quality, contentType } = checkUpload(body);
    await needGame(storeId, gameId);
    const key = `${KEY_PREFIX}${storeId}/${gameId}/${now()}_${quality}.mp4`;
    return { uploadUrl: storage.uploadUrl(key, contentType, UPLOAD_EXPIRES), key, contentType, expiresIn: UPLOAD_EXPIRES };
  }

  async function confirm(body, storeId) {
    needStorage();
    needStore(storeId);
    const gameId = cleanGameId(body.gameId);
    const quality = cleanQuality(body.quality);
    const key = String(body.key || '');
    // 다른 매장·다른 게임·다른 화질 칸에 남의 파일을 끼워 넣지 못하게 키 모양을 확인
    const game = await needGame(storeId, gameId);
    const info = await checkUploaded(key, `${KEY_PREFIX}${storeId}/${gameId}/`, quality, body.meta);
    const head = { size: info.sizeBytes };
    const field = `q${quality}`;
    const old = game.ruleVideo && game.ruleVideo[field] && game.ruleVideo[field].key;
    await games.setRuleVideo(storeId, gameId, field, info);
    if (stats && stats.recordUpload) {
      const oldBytes = old && old !== key ? Number(game.ruleVideo[field].sizeBytes || 0) : null;
      await stats.recordUpload(storeId, head.size, oldBytes).catch((e) => console.warn('[영상] 용량 기록 실패', e && e.message));
    }
    if (old && old !== key) {
      await storage.remove(old).catch((e) => console.warn('[영상] 예전 파일 삭제 실패', old, e && e.message));
    }
    return { video: { ...info, uploadedAt: info.uploadedAt.toISOString() } };
  }

  async function remove(body, storeId) {
    needStorage();
    needStore(storeId);
    const gameId = cleanGameId(body.gameId);
    const quality = cleanQuality(body.quality || 'all', { allowAll: true });
    const game = await games.get(storeId, gameId);
    const rv = (game && game.ruleVideo) || {};
    const fields = quality === 'all' ? QUALITIES.map((q) => `q${q}`) : [`q${quality}`];
    for (const f of fields) {
      const key = rv[f] && rv[f].key;
      if (game && rv[f]) {
        await games.setRuleVideo(storeId, gameId, f, null);
        if (stats && stats.recordRemove) {
          await stats.recordRemove(storeId, Number(rv[f].sizeBytes || 0)).catch((e) => console.warn('[영상] 용량 기록 실패', e && e.message));
        }
      }
      if (key) await storage.remove(key).catch((e) => console.warn('[영상] 파일 삭제 실패', key, e && e.message));
    }
    return { ok: true };
  }

  async function playUrl(query, storeId) {
    needStorage();
    needStore(storeId);
    const gameId = cleanGameId(query.gameId);
    const game = await needGame(storeId, gameId);
    let rv = game.ruleVideo || {};
    const out = urlsOf(rv, { expiresIn: PLAY_EXPIRES });
    // 92차: 매장 영상이 없으면 같은 BGG 번호의 공용 영상
    if (!out.q1080 && !out.q720 && shared) {
      const bggId = bggIdOf(game);
      const entry = bggId ? await shared.get(bggId) : null;
      if (entry) {
        urlsOf(entry, out);
        if (out.q1080 || out.q720) {
          rv = entry;
          out.shared = true;
        }
      }
    }
    if (!out.q1080 && !out.q720) throw httpError(404, 'NO_VIDEO', '등록된 룰 영상이 없어요.');
    if (stats && String(query.count) !== '0') {
      try {
        const first = rv.q1080 || rv.q720 || {};
        await stats.recordPlay(storeId, gameId, String(game.title || ''), Number(first.sizeBytes || 0));
      } catch (e) {
        console.warn('[영상] 재생 기록 실패', gameId, e && e.message); // 기록이 안 돼도 재생은 됨
      }
    }
    return out;
  }

  // 저장 정보 { q1080, q720 } → 재생 주소를 out에 넣음
  function urlsOf(rv, out) {
    for (const q of QUALITIES) {
      const v = rv && rv[`q${q}`];
      if (v && typeof v.key === 'string' && v.key.startsWith(KEY_PREFIX)) {
        out[`q${q}`] = { url: storage.downloadUrl(v.key, PLAY_EXPIRES), width: v.width || null, height: v.height || null };
      }
    }
    return out;
  }

  // ── 공용 영상 보관함 (92차, 운영자만 — app.js opsRoute) ──

  async function sharedUploadUrl(body) {
    needStorage();
    needShared();
    const bggId = cleanBggId(body.bggId);
    const { quality, contentType } = checkUpload(body);
    const key = `${SHARED_PREFIX}${bggId}/${now()}_${quality}.mp4`;
    return { uploadUrl: storage.uploadUrl(key, contentType, UPLOAD_EXPIRES), key, contentType, expiresIn: UPLOAD_EXPIRES };
  }

  async function sharedConfirm(body) {
    needStorage();
    needShared();
    const bggId = cleanBggId(body.bggId);
    const quality = cleanQuality(body.quality);
    const title = String(body.title == null ? '' : body.title).replace(/\s+/g, ' ').trim().slice(0, 100);
    const info = await checkUploaded(String(body.key || ''), `${SHARED_PREFIX}${bggId}/`, quality, body.meta);
    const field = `q${quality}`;
    const entry = await shared.get(bggId);
    const old = entry && entry[field] && entry[field].key;
    await shared.set(bggId, field, info, title || (entry && entry.title) || '');
    if (old && old !== info.key) {
      await storage.remove(old).catch((e) => console.warn('[공용 영상] 예전 파일 삭제 실패', old, e && e.message));
    }
    return { video: { ...info, uploadedAt: info.uploadedAt.toISOString() } };
  }

  async function sharedRemove(body) {
    needStorage();
    needShared();
    const bggId = cleanBggId(body.bggId);
    const quality = cleanQuality(body.quality || 'all', { allowAll: true });
    const entry = (await shared.get(bggId)) || {};
    const fields = quality === 'all' ? QUALITIES.map((q) => `q${q}`) : [`q${quality}`];
    for (const f of fields) {
      const key = entry[f] && entry[f].key;
      if (entry[f]) await shared.set(bggId, f, null);
      if (key) await storage.remove(key).catch((e) => console.warn('[공용 영상] 파일 삭제 실패', key, e && e.message));
    }
    return { ok: true };
  }

  async function sharedList() {
    needShared();
    const map = (await shared.list()) || {};
    const iso = (d) => (d && typeof d.toDate === 'function' ? d.toDate() : d instanceof Date ? d : null);
    const out = [];
    let bytes = 0;
    for (const [bggId, e] of Object.entries(map)) {
      const item = { bggId, title: (e && e.title) || '' };
      for (const q of QUALITIES) {
        const v = e && e[`q${q}`];
        if (v && v.key) {
          const at = iso(v.uploadedAt);
          item[`q${q}`] = { sizeBytes: Number(v.sizeBytes || 0), width: v.width || null, height: v.height || null,
            durationSec: v.durationSec || null, uploadedAt: at ? at.toISOString() : null };
          bytes += Number(v.sizeBytes || 0);
        }
      }
      if (item.q1080 || item.q720) out.push(item);
    }
    out.sort((a, b) => a.title.localeCompare(b.title) || a.bggId.localeCompare(b.bggId));
    return { videos: out, totalBytes: bytes, connected: !!storage };
  }

  // 93차: 한 매장이 올린 영상을 공용 보관함으로 옮김 { storeId, dryRun(기본 true — 미리 보기만) }
  //   파일은 R2에 그대로 두고 기록만 옮김(복사 비용 없음): shared에 같은 키로 적고 → 게임 문서의 ruleVideo를 지움.
  //   BGG 번호(geekId)가 없거나, 그 BGG 번호의 공용 영상이 이미 있으면 건너뜀(매장 영상으로 남음).
  async function moveStoreToShared(body) {
    needStorage();
    needShared();
    if (!games.listWithVideo) throw httpError(503, 'NO_LIST', '게임 목록 기능이 연결되지 않았어요.');
    const storeId = needStore(String(body.storeId == null ? '' : body.storeId).trim());
    const dryRun = body.dryRun !== false;
    const list = await games.listWithVideo(storeId); // [{ id, title, geekId, ruleVideo }]
    const moved = [];
    const skipped = [];
    const taken = new Set();
    for (const g of list) {
      const rv = (g && g.ruleVideo) || {};
      const fields = QUALITIES.map((q) => `q${q}`)
        .filter((f) => rv[f] && typeof rv[f].key === 'string' && rv[f].key.startsWith(KEY_PREFIX));
      if (!fields.length) continue;
      const bggId = bggIdOf(g);
      const item = {
        gameId: g.id,
        title: String(g.title || ''),
        bggId,
        qualities: fields.map((f) => f.slice(1)),
        sizeBytes: fields.reduce((n, f) => n + Number(rv[f].sizeBytes || 0), 0),
      };
      if (!bggId) {
        skipped.push({ ...item, reason: 'BGG 번호 없음' });
        continue;
      }
      if (taken.has(bggId) || (await shared.get(bggId))) {
        skipped.push({ ...item, reason: '이 BGG 번호의 공용 영상이 이미 있음' });
        continue;
      }
      taken.add(bggId);
      if (!dryRun) {
        for (const f of fields) {
          await shared.set(bggId, f, rv[f], item.title); // 공용에 먼저 적고 (영상이 비는 순간이 없게)
          await games.setRuleVideo(storeId, g.id, f, null); // 매장 기록을 지움 (파일은 안 지움)
          if (stats && stats.recordRemove) {
            await stats.recordRemove(storeId, Number(rv[f].sizeBytes || 0)).catch((e) => console.warn('[영상] 용량 기록 실패', e && e.message));
          }
        }
      }
      moved.push(item);
    }
    return { dryRun, storeId, moved, skipped };
  }

  return { uploadUrl, confirm, remove, playUrl, sharedUploadUrl, sharedConfirm, sharedRemove, sharedList, moveStoreToShared };
}

// 메모리 공용 영상 기록 (테스트·로컬 개발용) — Firestore 쪽은 index.js createSharedVideos
function createMemorySharedVideos() {
  const map = new Map();
  return {
    map,
    async get(bggId) { return map.has(bggId) ? JSON.parse(JSON.stringify(map.get(bggId))) : null; },
    async set(bggId, field, info, title) {
      const e = map.get(bggId) || { title: '' };
      if (title) e.title = title;
      if (info == null) delete e[field];
      else e[field] = info;
      if (!e.q1080 && !e.q720) map.delete(bggId);
      else map.set(bggId, e);
    },
    async list() { return Object.fromEntries(map); },
  };
}

module.exports = { createVideoApi, createMemorySharedVideos, MAX_BYTES, PLAY_EXPIRES, UPLOAD_EXPIRES, SHARED_PREFIX };
