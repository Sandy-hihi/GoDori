// 플랫폼식스 월정액권 앱(platform6 어플/functions/src/bgg-client.js)에서 그대로 가져온 파일.
// BGG 조회 방식(Apps Script 중계 등)을 바꿀 일이 있으면 두 프로젝트를 같이 고쳐 주세요.
'use strict';
// BoardGameGeek(BGG) XML API2 연동.
//   createHandler({ bgg = createBggClient() })처럼 주입받아 쓰기 때문에, 운영/로컬 개발 서버는
//   실제 BGG를 그대로 쓰고 테스트는 네트워크 없이 고정된 응답을 주는 가짜 클라이언트(test/fake-bgg.js)를 쓴다.
//
//   search(query)              -> [{ id, name, yearPublished, thumbnail }, ...]
//   fetchImage(bggId, {maxBytes}) -> { buffer, contentType, name }  (35차: 썸네일을 먼저 시도하고, 썸네일이 없거나 실패하면 원본으로 대체)
const BGG_BASE = 'https://boardgamegeek.com/xmlapi2';
const SEARCH_LIMIT = 15; // 검색 결과로 보여줄 최대 개수 (thing 배치 조회 URL이 너무 길어지지 않게)
// 30차 배포 후 실제로 겪은 문제: Apps Script 중계(위 30차 주석 참고)는 매번 몇 초씩 걸릴 때가 있는데,
// 15초로는 부족해서 재시도(15초+3초 대기+15초 = 최대 33초)까지 가면 아래 index.js의 함수 자체
// 제한시간(예전 30초)보다 먼저 Firebase Hosting이 504를 돌려줘 버렸다. 그래서 20초로 늘렸었는데(31차),
// 그 다음 재배포에서도 여전히 20초+재시도 20초(최대 43초)를 전부 채우고 타임아웃(AbortError)이
// 났다 — 직접 브라우저로 같은 Apps Script 주소를 열어보면 몇 초 안에 정상 응답이 오는 걸 확인했는데도
// 그랬다(32차). 즉 Apps Script 자체가 항상 느린 게 아니라, Cloud Run의 자동화된 요청에 대해서만
// 가끔 훨씬 오래 걸리는 것으로 보임 — 원인이 명확해질 때까지는 시간을 더 넉넉히 주는 쪽으로 대응.
const FETCH_TIMEOUT_MS = 25_000;
const CONTENT_TYPE_BY_EXT = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp' };
const SUPPORTED_TYPES = new Set(['image/png', 'image/jpeg', 'image/webp']);

function xmlUnescape(s) {
  return String(s || '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/g, '&');
}

function attr(attrsStr, name) {
  const m = new RegExp(`${name}="([^"]*)"`).exec(String(attrsStr || ''));
  return m ? xmlUnescape(m[1]) : null;
}

// 자체닫힘(<tag .../>) 또는 여는/닫는(<tag ...>text</tag>) 태그를 모두 찾는다. (BGG는 둘 다 섞어 쓴다)
function findTag(block, tagName) {
  const re = new RegExp(`<${tagName}\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${tagName}>)`, 'g');
  const out = [];
  let m;
  while ((m = re.exec(String(block || '')))) out.push({ attrs: m[1] || '', text: m[2] !== undefined ? m[2] : null });
  return out;
}

function parseItems(xml) {
  const items = [];
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/g;
  let m;
  while ((m = re.exec(String(xml || '')))) items.push({ id: attr(m[1], 'id'), block: m[2] });
  return items;
}

function primaryName(block) {
  const names = findTag(block, 'name');
  if (!names.length) return null;
  const primary = names.find((n) => attr(n.attrs, 'type') === 'primary') || names[0];
  return attr(primary.attrs, 'value');
}

// 34차: 게임 이름을 한국어로 저장하고 싶다는 요청. BGG XML API에는 "이 언어로 번역해 줘" 같은 기능은
// 없지만, 각 게임의 "다른 이름"(<name type="alternate">) 목록에는 실제 한국어판이 있으면 사용자들이
// 등록해 둔 한글 이름이 섞여 있는 경우가 많다(예: Catan -> "카탄"). 이 목록에서 한글(가-힣)이 포함된
// 이름을 찾아 쓰는 방식으로 "번역"이 아니라 "실제 한국어판/커뮤니티 표기 이름"을 가져온다. 후보가
// 여러 개면(예: "카탄", "카탄: 보드게임의 제왕") 부제가 안 붙은 짧은 쪽이 보통 정식 이름에 가까워서
// 그중 가장 짧은 걸 고른다. 한글 후보가 하나도 없으면(한국어판이 없거나 BGG에 등록이 안 된 경우)
// null을 돌려주고, 호출하는 쪽에서 원래 이름(영문 등)으로 대체한다.
const HANGUL_RE = /[\uAC00-\uD7A3]/;
function koreanAltName(block) {
  const candidates = findTag(block, 'name')
    .filter((n) => attr(n.attrs, 'type') === 'alternate')
    .map((n) => attr(n.attrs, 'value'))
    .filter((v) => v && HANGUL_RE.test(v));
  if (!candidates.length) return null;
  candidates.sort((a, b) => a.length - b.length);
  return candidates[0];
}

// 게임 검색 결과 XML(items/item) -> [{id, name, yearPublished}]. 이름이 없는(파싱 실패) 항목은 뺀다.
function parseSearchXml(xml) {
  return parseItems(xml)
    .filter((it) => it.id)
    .map((it) => {
      const yearTag = findTag(it.block, 'yearpublished')[0];
      const yearValue = yearTag ? Number(attr(yearTag.attrs, 'value')) : null;
      return { id: it.id, name: primaryName(it.block), yearPublished: Number.isFinite(yearValue) ? yearValue : null };
    })
    .filter((it) => it.name);
}

// 게임 상세 XML(thing) -> Map(id -> {id, name, thumbnail, image})
function parseThingXml(xml) {
  const out = new Map();
  for (const it of parseItems(xml)) {
    if (!it.id) continue;
    const thumbTag = findTag(it.block, 'thumbnail')[0];
    const imageTag = findTag(it.block, 'image')[0];
    out.set(it.id, {
      id: it.id,
      name: primaryName(it.block),
      thumbnail: thumbTag && thumbTag.text ? xmlUnescape(thumbTag.text.trim()) : null,
      image: imageTag && imageTag.text ? xmlUnescape(imageTag.text.trim()) : null,
    });
  }
  return out;
}

// 이름이 붙은 <poll name="...">...</poll> 블록 하나를 찾는다. (한 게임 item 안에 poll이 여러 개 있다:
// suggested_numplayers, suggested_playerage, language_dependence 등 — 이름으로 골라야 한다)
function findPollBlock(itemBlock, pollName) {
  const re = /<poll\b([^>]*)>([\s\S]*?)<\/poll>/g;
  let m;
  while ((m = re.exec(String(itemBlock || '')))) {
    if (attr(m[1], 'name') === pollName) return m[2];
  }
  return null;
}

// "추천 인원" 계산: BGG의 "suggested_numplayers" 투표(poll)에서, 인원수(N)별로 Best 투표가
// Recommended·Not Recommended 투표보다 둘 다 많으면 그 N을 추천 인원으로 채택한다. 채택된 게 하나도
// 없으면(투표가 없거나 아무 인원도 Best 우세가 아니면) "인원" 필드와 같은 min-max 범위 문자열로 대체한다.
function parseRecommendedPlayers(itemBlock, minPlayers, maxPlayers) {
  const pollBlock = findPollBlock(itemBlock, 'suggested_numplayers');
  const qualifying = [];
  if (pollBlock) {
    for (const row of findTag(pollBlock, 'results')) {
      const n = attr(row.attrs, 'numplayers');
      if (!n) continue;
      let best = 0;
      let recommended = 0;
      let notRecommended = 0;
      for (const res of findTag(row.text || '', 'result')) {
        const value = attr(res.attrs, 'value');
        const numvotes = Number(attr(res.attrs, 'numvotes')) || 0;
        if (value === 'Best') best = numvotes;
        else if (value === 'Recommended') recommended = numvotes;
        else if (value === 'Not Recommended') notRecommended = numvotes;
      }
      if (best > recommended && best > notRecommended) qualifying.push(n);
    }
  }
  if (qualifying.length) return qualifying.join(', ');
  if (minPlayers == null || maxPlayers == null) return null;
  return minPlayers === maxPlayers ? String(minPlayers) : `${minPlayers}-${maxPlayers}`;
}

// 게임 상세 XML(thing, stats=1) -> Map(id -> 카탈로그에 필요한 모든 필드). parseThingXml보다 더 많이 뽑는다:
// 인원 범위, 추천 인원(투표 기반), 난이도 계산의 기준이 되는 geek weight, 긱 순위(보드게임 종합 랭크,
// "Not Ranked"면 null).
function parseThingFullXml(xml) {
  const out = new Map();
  for (const it of parseItems(xml)) {
    if (!it.id) continue;
    const thumbTag = findTag(it.block, 'thumbnail')[0];
    const imageTag = findTag(it.block, 'image')[0];
    const minTag = findTag(it.block, 'minplayers')[0];
    const maxTag = findTag(it.block, 'maxplayers')[0];
    const minPlayersRaw = minTag ? Number(attr(minTag.attrs, 'value')) : NaN;
    const maxPlayersRaw = maxTag ? Number(attr(maxTag.attrs, 'value')) : NaN;
    const minPlayers = Number.isFinite(minPlayersRaw) ? minPlayersRaw : null;
    const maxPlayers = Number.isFinite(maxPlayersRaw) ? maxPlayersRaw : null;
    // 플레이 시간(분) — BGG 박스 기준. 0이나 없는 값은 null
    const minutes = (tagName) => {
      const t = findTag(it.block, tagName)[0];
      const v = t ? Number(attr(t.attrs, 'value')) : NaN;
      return Number.isFinite(v) && v > 0 ? v : null;
    };

    let weight = null;
    let rank = null;
    const statsTag = findTag(it.block, 'statistics')[0];
    const ratingsTag = statsTag && statsTag.text ? findTag(statsTag.text, 'ratings')[0] : null;
    const ratingsText = ratingsTag ? ratingsTag.text : null;
    if (ratingsText) {
      const weightTag = findTag(ratingsText, 'averageweight')[0];
      const w = weightTag ? Number(attr(weightTag.attrs, 'value')) : NaN;
      weight = Number.isFinite(w) && w > 0 ? w : null; // 0은 "집계된 평가 없음"이라 저장하지 않는다

      const ranksTag = findTag(ratingsText, 'ranks')[0];
      const firstRank = ranksTag && ranksTag.text ? findTag(ranksTag.text, 'rank')[0] : null;
      if (firstRank) {
        const rv = attr(firstRank.attrs, 'value');
        const rn = rv && rv !== 'Not Ranked' ? Number(rv) : NaN;
        rank = Number.isFinite(rn) ? rn : null;
      }
    }

    const bggName = primaryName(it.block);
    out.set(it.id, {
      id: it.id,
      // 34차: 한글 이름이 BGG에 있으면 그걸 우선 저장하고(koreanAltName), 없으면 원래 이름(보통 영문)을 쓴다.
      name: koreanAltName(it.block) || bggName,
      bggName, // 항상 BGG 원어 이름 — 관리자 화면에서 "원래 이름"으로 참고 표시할 때 씀 (34차)
      thumbnail: thumbTag && thumbTag.text ? xmlUnescape(thumbTag.text.trim()) : null,
      image: imageTag && imageTag.text ? xmlUnescape(imageTag.text.trim()) : null,
      minPlayers,
      maxPlayers,
      recommendedPlayers: parseRecommendedPlayers(it.block, minPlayers, maxPlayers),
      weight,
      rank,
      minPlayTime: minutes('minplaytime'),
      maxPlayTime: minutes('maxplaytime'),
      playingTime: minutes('playingtime'),
    });
  }
  return out;
}

// content-type 헤더가 없거나 못 알아보는 값이면 이미지 주소 확장자로 짐작한다. (우리 이미지 파이프라인은
// png/jpeg/webp만 받으므로 그 셋으로만 정규화 — 그 외 형식이면 null을 돌려줘서 호출한 쪽이 다음 후보로 넘어가게 한다)
function normalizeContentType(headerType, url) {
  const t = String(headerType || '').split(';')[0].trim().toLowerCase();
  if (SUPPORTED_TYPES.has(t)) return t;
  const ext = String(url || '').split('?')[0].split('.').pop().toLowerCase();
  return CONTENT_TYPE_BY_EXT[ext] || null;
}

function bggError(code, message) {
  const e = new Error(message || code);
  e.code = code;
  return e;
}

// 28차: BGG가 2025년부터 XML API에 "애플리케이션 등록 + Authorization: Bearer <token>"을 사실상
// 필수로 요구하기 시작했다는 게 밝혀졌다(https://boardgamegeek.com/using_the_xml_api) — 토큰 없이는
// 401. 다만 28차 당시 "토큰만 있으면 Cloud Run에서 직접 나가도 된다"고 판단한 건 성급했다: 29~30차에
// GCP 로그/relay.log로 직접 확인해 보니, Cloud Run과 매장 컴퓨터 양쪽 모두 토큰이 있어도 Cloudflare의
// "확인 중입니다" 자동 통과 화면(JS 챌린지)에 막혔다 — 이건 IP나 토큰과 무관하게, 자바스크립트를
// 실행 못 하는 평범한 프로그램의 요청이라서 생기는 문제였다. 그래서 토큰은 여전히 필요하지만(직접
// 호출 시 아래처럼 헤더에 붙인다), 실제 운영에서는 이 파일 아래쪽의 fetchViaAppsScript(30차, 이
// 챌린지를 만난 적 없는 Google Apps Script를 통해 나감)를 relay로 함께 써야 한다 — index.js 참고.
const BGG_REQUEST_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  Accept: 'application/xml,text/xml,*/*',
};

function withAuth(headers, token) {
  return token ? { ...headers, Authorization: `Bearer ${token}` } : headers;
}

async function directFetch(url, opts, token) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  try {
    const headers = withAuth({ ...BGG_REQUEST_HEADERS, ...(opts && opts.headers) }, token);
    return await fetch(url, { ...opts, headers, signal: ctrl.signal });
  } catch (e) {
    throw bggError('BGG_UNAVAILABLE', e && e.message);
  } finally {
    clearTimeout(t);
  }
}

// (현재는 기본적으로 쓰이지 않음 — 27차 기록 참고) 매장 컴퓨터에서 돌아가는 relay.js의
// `/proxy?u=<원래 URL>` 엔드포인트로 대신 요청한다. 중계 프로그램이 매장 컴퓨터의 인터넷으로 실제
// BGG 요청을 수행해서 그 응답을 그대로 돌려준다. token이 있으면 relay.js가 그대로 BGG로 전달할 수
// 있게 Authorization 헤더도 함께 보낸다. (30차: 매장 컴퓨터의 IP도 Cloudflare 확인 화면에 막힌다는
// 게 확인되면서 아래 fetchViaAppsScript로 대체됨 — 코드는 참고용으로 남겨 둔다.)
async function fetchViaRelay(relayInfo, targetUrl, opts, token) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  const proxyUrl = `${String(relayInfo.url).replace(/\/+$/, '')}/proxy?u=${encodeURIComponent(targetUrl)}`;
  try {
    const headers = withAuth({ ...(opts && opts.headers), 'x-relay-key': relayInfo.secret }, token);
    return await fetch(proxyUrl, { ...opts, headers, signal: ctrl.signal });
  } catch (e) {
    throw bggError('BGG_UNAVAILABLE', e && e.message);
  } finally {
    clearTimeout(t);
  }
}

// 30차: Cloud Run에서 나가는 요청도, 매장 컴퓨터(relay.js)에서 나가는 요청도 결국 BGG의 Cloudflare가
// "확인 중입니다" 자동 통과 화면(사람이 실제 브라우저로 열면 저절로 풀리지만, 평범한 프로그램의
// 요청은 절대 통과 못 하는 화면)으로 막는다는 게 relay.log로 확인됐다. 반면 Google Apps Script(구글
// 자체 서버에서 요청을 대신 보내주는 무료 서비스)로 같은 요청을 보내면 이 화면 자체가 뜨지 않는다는
// 걸 직접 확인했다 — 그래서 매장 컴퓨터를 계속 켜 둘 필요가 없는 이 방식으로 바꿨다.
// Apps Script 웹 앱은 요청 헤더를 읽을 수 없어서 비밀키(secret)를 쿼리 파라미터로 보내고, BGG 토큰은
// Apps Script 코드 안에 미리 넣어 두므로 여기서는 Authorization 헤더를 보낼 필요가 없다. 또 원본
// 응답(특히 이미지 같은 바이너리)을 있는 그대로 돌려줄 수 없어서, Apps Script가
// { status, contentType, bodyBase64 } 형태의 JSON으로 감싸서 응답하면 여기서 다시 풀어(base64
// 디코딩) fetch()의 Response처럼 흉내 낸 객체를 만들어 돌려준다.
async function fetchViaAppsScript(relayInfo, targetUrl) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
  const sep = String(relayInfo.url).includes('?') ? '&' : '?';
  const proxyUrl = `${relayInfo.url}${sep}key=${encodeURIComponent(relayInfo.secret)}&u=${encodeURIComponent(targetUrl)}`;
  try {
    // 32차: Cloud Run에서 이 Apps Script 주소로 나가는 요청이 (아무 헤더도 없이 보냈더니) 가끔
    // 20초 넘게 응답이 없다가 타임아웃되는 게 관찰됨 — 같은 주소를 실제 브라우저로 열면 항상
    // 빠르게 응답이 왔다. 원인은 아직 확실하지 않지만(Apps Script 쪽의 자동화 요청 처리 방식 차이로
    // 추정), 브라우저처럼 보이는 User-Agent를 붙여서 차이가 있는지 시도해본다 — 밑져야 본전인 낮은
    // 위험의 변경.
    const res = await fetch(proxyUrl, {
      signal: ctrl.signal,
      redirect: 'follow',
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      },
    });
    if (!res.ok) return res; // Apps Script 자체가 안 열림(배포 문제 등) — JSON도 못 받은 상태
    let data;
    try {
      data = await res.json();
    } catch (e) {
      throw bggError('BGG_UNAVAILABLE', 'Apps Script 응답을 해석할 수 없음: ' + (e && e.message));
    }
    const buf = Buffer.from(data.bodyBase64 || '', 'base64');
    return {
      ok: data.status >= 200 && data.status < 300,
      status: data.status,
      headers: { get: (name) => (String(name).toLowerCase() === 'content-type' ? data.contentType || null : null) },
      text: async () => buf.toString('utf8'),
      arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength),
    };
  } catch (e) {
    if (e && e.code) throw e; // 이미 bggError로 감싼 경우 그대로
    throw bggError('BGG_UNAVAILABLE', e && e.message);
  } finally {
    clearTimeout(t);
  }
}

// 중계 프로그램이 최근에 등록한 주소가 이 시간(ms)보다 오래되면 "꺼져있다"고 본다 — 죽은 주소로 매번
// 타임아웃까지 기다리지 않고 바로 명확한 오류(BGG_RELAY_OFFLINE)를 주기 위함. app.js의 상태 조회
// 라우트도 같은 기준을 쓴다.
const RELAY_STALE_MS = 3 * 60 * 1000;

// 상세 조회(stats=1)는 한 번에 여러 id를 묶어서(최대 10개씩) 부른다 — BGG API 예절 + 성능.
// BGG는 요청이 몰리면 XML 대신 본문에 "Rate limit exceeded" 텍스트를 돌려줄 때가 있어서, 그런 경우
// 한 번 더(3초 쉬고) 재시도한다. 배치 사이에는 2초씩 쉬어서 연속 요청을 스스로 늦춘다.
const DETAIL_BATCH_SIZE = 10;
const RATE_LIMIT_RETRY_DELAY_MS = 3000;
const BATCH_THROTTLE_DELAY_MS = 2000;
const RELAY_CACHE_MS = 15_000; // 중계 주소를 매 요청마다 다시 조회하지 않도록 짧게 캐시
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// token: BGG 애플리케이션 토큰(boardgamegeek.com/applications에서 발급, 28차). relay가 없을 때(직접
// 호출)만 여기서 Authorization 헤더에 붙인다 — Apps Script 중계는 토큰을 자기 안에 미리 넣어 두므로
// 필요 없다.
// relay: 생략하면 항상 BGG로 직접 나간다(토큰만 있으면 되지만, 30차 기준 Cloud Run에서 나가는 요청은
// Cloudflare 확인 화면에 막혀서 사실상 못 씀). { resolve } 형태로 넘기면 그 resolve()가 돌려주는
// { url, secret, transport } 정보로 중계를 거쳐 나간다 — transport가 'appsscript'면 Google Apps
// Script 중계(30차, 기본), 아니면(또는 생략) 매장 컴퓨터의 relay.js 중계(26/27차, 현재 쓰지 않지만
// 코드는 남겨 둠)로 나간다. resolve()가 null/오류를 주면 시도조차 하지 않고 BGG_RELAY_OFFLINE을
// 바로 던진다.
function createBggClient({ relay, token } = {}) {
  let relayCache = null; // { info, at }

  async function currentRelayInfo() {
    const t = Date.now();
    if (relayCache && t - relayCache.at < RELAY_CACHE_MS) return relayCache.info;
    let info = null;
    try {
      info = await relay.resolve();
    } catch {
      info = null;
    }
    relayCache = { info, at: t };
    return info;
  }

  async function doFetch(url, opts) {
    if (!relay) return directFetch(url, opts, token);
    const info = await currentRelayInfo();
    if (!info) throw bggError('BGG_RELAY_OFFLINE', '중계 프로그램이 연결되어 있지 않음');
    if (info.transport === 'appsscript') return fetchViaAppsScript(info, url);
    return fetchViaRelay(info, url, opts, token);
  }

  // doFetch를 감싸서, 첫 시도가 (타임아웃/네트워크 오류로) 예외를 던지거나, 응답이 실패(!ok)이거나,
  // isRetryableBody(text)가 true(예: 레이트리밋 문구)면 한 번만 더 재시도한다. 콜드 스타트 직후의 일시적인
  // 연결 지연/실패를 흡수하기 위한 것 — 둘 다 실패하면 마지막 결과(또는 예외)를 그대로 위로 넘긴다.
  // (단, 중계 프로그램 자체가 꺼져있는 경우는 재시도해도 소용없으니 바로 던진다.)
  async function fetchBggWithRetry(url, { isRetryableBody } = {}) {
    for (let attempt = 0; ; attempt++) {
      const isLastAttempt = attempt >= 1;
      let res;
      try {
        res = await doFetch(url);
      } catch (e) {
        if (isLastAttempt || e.code === 'BGG_RELAY_OFFLINE') throw e;
        await sleep(RATE_LIMIT_RETRY_DELAY_MS);
        continue;
      }
      if (!res.ok) {
        if (isLastAttempt) return { res, text: '' };
        await sleep(RATE_LIMIT_RETRY_DELAY_MS);
        continue;
      }
      const text = await res.text();
      if (isRetryableBody && isRetryableBody(text) && !isLastAttempt) {
        await sleep(RATE_LIMIT_RETRY_DELAY_MS);
        continue;
      }
      return { res, text };
    }
  }

  async function fetchDetailBatchXml(ids) {
    const url = `${BGG_BASE}/thing?id=${ids.join(',')}&stats=1`;
    const { res, text } = await fetchBggWithRetry(url, { isRetryableBody: (t) => t.includes('Rate limit exceeded') });
    if (!res.ok) throw bggError('BGG_UNAVAILABLE', `thing ${res.status}`);
    return text;
  }

  return {
    kind: 'http',
    async search(query) {
      const q = String(query || '').trim();
      if (!q) return [];
      const searchUrl = `${BGG_BASE}/search?type=boardgame,boardgameexpansion&query=${encodeURIComponent(q)}`;
      const { res, text: searchXml } = await fetchBggWithRetry(searchUrl);
      if (!res.ok) throw bggError('BGG_UNAVAILABLE', `search ${res.status}`);
      const found = parseSearchXml(searchXml).slice(0, SEARCH_LIMIT);
      if (!found.length) return [];
      // 목록에 썸네일을 같이 보여주기 위해, 후보들의 상세 정보를 한 번에 묶어서 조회한다.
      const thingUrl = `${BGG_BASE}/thing?id=${found.map((f) => f.id).join(',')}&stats=0`;
      const { res: thingRes, text: thingXml } = await fetchBggWithRetry(thingUrl);
      const things = thingRes.ok ? parseThingXml(thingXml) : new Map();
      return found.map((f) => ({ id: f.id, name: f.name, yearPublished: f.yearPublished, thumbnail: (things.get(f.id) || {}).thumbnail || null }));
    },
    async fetchImage(bggId, { maxBytes = Infinity } = {}) {
      const id = String(bggId || '').trim();
      if (!/^\d+$/.test(id)) throw bggError('BGG_NOT_FOUND', '잘못된 BGG id');
      const thingUrl = `${BGG_BASE}/thing?id=${id}&stats=0`;
      const { res: thingRes, text: thingXml } = await fetchBggWithRetry(thingUrl);
      if (!thingRes.ok) throw bggError('BGG_UNAVAILABLE', `thing ${thingRes.status}`);
      const t = parseThingXml(thingXml).get(id);
      if (!t) throw bggError('BGG_NOT_FOUND', 'BGG 게임을 찾을 수 없음');
      // 35차: 원본(t.image)을 먼저 받아보고 너무 크면 그제서야 썸네일로 넘어가던 순서를 뒤집었다.
      // 이 앱은 어디서도 사진을 48~64px보다 크게 보여주지 않는데(목록 썸네일·상세 오버레이 전부 작음),
      // BGG 원본은 흔히 1.5MB(IMAGE_MAX_BYTES) 상한을 넘는 박스아트 사진이라 원본을 먼저 시도하면
      // Apps Script 중계(30차)로 큰 이미지를 base64로 왕복하느라 시간을 많이 쓰고, 그마저도 상한
      // 초과로 버려지고 나서야 썸네일을 다시 요청하는 이중 왕복이 됐다 — "사진이 안 불러와진다"는
      // 보고(35차)의 실제 원인이 이거였다(느린 원본 왕복 도중 타임아웃). 화면에 필요한 건 항상
      // 썸네일 크기라 아예 썸네일을 먼저 시도하고, 썸네일이 없거나 실패할 때만 원본으로 넘어간다.
      const candidates = [t.thumbnail, t.image].filter(Boolean);
      if (!candidates.length) throw bggError('BGG_NO_IMAGE', '등록된 사진 없음');

      let lastCode = 'BGG_NO_IMAGE';
      for (const url of candidates) {
        let imgRes;
        try {
          imgRes = await doFetch(url);
        } catch {
          lastCode = 'BGG_UNAVAILABLE';
          continue;
        }
        if (!imgRes.ok) {
          lastCode = 'BGG_UNAVAILABLE';
          continue;
        }
        const buffer = Buffer.from(await imgRes.arrayBuffer());
        if (buffer.length > maxBytes) {
          lastCode = 'BGG_IMAGE_TOO_LARGE'; // 이 후보는 너무 큼 -> 다음 후보(보통 더 작은 썸네일)로
          continue;
        }
        const contentType = normalizeContentType(imgRes.headers.get('content-type'), url);
        if (!contentType) {
          lastCode = 'BGG_IMAGE_UNSUPPORTED_TYPE';
          continue;
        }
        return { buffer, contentType, name: t.name };
      }
      throw bggError(lastCode, lastCode);
    },
    // 단일 게임 상세(인원/추천 인원/weight/순위 등, 카탈로그용) 조회.
    async fetchDetails(bggId) {
      const id = String(bggId || '').trim();
      if (!/^\d+$/.test(id)) throw bggError('BGG_NOT_FOUND', '잘못된 BGG id');
      const text = await fetchDetailBatchXml([id]);
      const d = parseThingFullXml(text).get(id);
      if (!d) throw bggError('BGG_NOT_FOUND', 'BGG 게임을 찾을 수 없음');
      return d;
    },
    // 대용량 추가용: geek ID 여러 개를 한 번에(10개씩 묶어서, 배치 사이 쉬어가며) 조회.
    // 반환: Map(id -> 상세). BGG에 없는 id는 그냥 맵에 없다(호출한 쪽에서 실패로 처리).
    async fetchDetailsBatch(bggIds) {
      const ids = Array.from(
        new Set((bggIds || []).map((x) => String(x || '').trim()).filter((x) => /^\d+$/.test(x)))
      );
      const out = new Map();
      for (let i = 0; i < ids.length; i += DETAIL_BATCH_SIZE) {
        const chunk = ids.slice(i, i + DETAIL_BATCH_SIZE);
        const text = await fetchDetailBatchXml(chunk);
        for (const [k, v] of parseThingFullXml(text)) out.set(k, v);
        if (i + DETAIL_BATCH_SIZE < ids.length) await sleep(BATCH_THROTTLE_DELAY_MS);
      }
      return out;
    },
  };
}

module.exports = {
  createBggClient,
  parseSearchXml,
  parseThingXml,
  parseThingFullXml,
  parseRecommendedPlayers,
  RELAY_STALE_MS,
};
