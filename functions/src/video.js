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
// 영상 규격(41차): 1080p 30fps H.264 + AAC, MP4. 720p 파일은 선택(있으면 패드가 버퍼링 때 720p로 바꿔 틂).
// R2 설정이 없으면(아직 Cloudflare 연결 전) 모든 영상 API가 503 R2_NOT_CONNECTED.

const MAX_BYTES = 700 * 1024 * 1024; // 8분 1080p ≈ 250MB. 여유 있게 700MB까지
const UPLOAD_EXPIRES = 60 * 60; // 올리기 임시 주소 1시간 (올리기 "시작"까지만 유효하면 됨)
const PLAY_EXPIRES = 4 * 60 * 60; // 재생 임시 주소 4시간
const QUALITIES = ['1080', '720'];
const KEY_PREFIX = 'rule-videos/';

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
 */
function createVideoApi({ storage, games, stats = null, now = () => Date.now() }) {
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

  async function uploadUrl(body, storeId) {
    needStorage();
    needStore(storeId);
    const gameId = cleanGameId(body.gameId);
    const quality = cleanQuality(body.quality);
    const size = Number(body.size);
    if (!Number.isFinite(size) || size <= 0) throw httpError(400, 'INVALID_SIZE', '파일 크기를 확인해 주세요.');
    if (size > MAX_BYTES) {
      throw httpError(413, 'TOO_LARGE', `영상이 너무 커요. ${Math.round(MAX_BYTES / 1024 / 1024)}MB 이하로 만들어 주세요.`);
    }
    const contentType = String(body.contentType || 'video/mp4').toLowerCase();
    if (contentType !== 'video/mp4') throw httpError(415, 'NOT_MP4', 'MP4 영상만 올릴 수 있어요.');
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
    const prefix = `${KEY_PREFIX}${storeId}/${gameId}/`;
    const rest = key.startsWith(prefix) ? key.slice(prefix.length) : '';
    if (!new RegExp(`^\\d{10,16}_${quality}\\.mp4$`).test(rest)) {
      throw httpError(400, 'INVALID_KEY', '올린 파일 정보가 올바르지 않아요. 다시 올려 주세요.');
    }
    const game = await needGame(storeId, gameId);
    const head = await storage.head(key);
    if (!head) throw httpError(404, 'UPLOAD_MISSING', '영상이 저장소에 올라가지 않았어요. 다시 올려 주세요.');
    if (head.size > MAX_BYTES) {
      await storage.remove(key).catch(() => {});
      throw httpError(413, 'TOO_LARGE', '영상이 너무 커요.');
    }

    const meta = body.meta && typeof body.meta === 'object' ? body.meta : {};
    const info = {
      key,
      sizeBytes: head.size,
      width: num(meta.width, 10000),
      height: num(meta.height, 10000),
      fps: num(meta.fps, 1000),
      durationSec: num(meta.durationSec, 24 * 3600),
      videoCodec: typeof meta.videoCodec === 'string' ? meta.videoCodec.slice(0, 20) : null,
      uploadedAt: new Date(now()),
    };
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
    const rv = game.ruleVideo || {};
    const out = { expiresIn: PLAY_EXPIRES };
    for (const q of QUALITIES) {
      const v = rv[`q${q}`];
      if (v && typeof v.key === 'string' && v.key.startsWith(KEY_PREFIX)) {
        out[`q${q}`] = { url: storage.downloadUrl(v.key, PLAY_EXPIRES), width: v.width || null, height: v.height || null };
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

  return { uploadUrl, confirm, remove, playUrl };
}

module.exports = { createVideoApi, MAX_BYTES, PLAY_EXPIRES, UPLOAD_EXPIRES };
