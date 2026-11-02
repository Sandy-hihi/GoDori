'use strict';
// AI 게임 추천 서버
//
//   POST /api/ai/recommend   손님 패드의 "우리 테이블 맞춤 추천"
//        { players: 2~6, experience: first|sometimes|often, moods: [...], time: 30|60|any, count: 2~4, exclude: [gameId] }
//        -> { picks: [{ gameId, title, reason, imageUrl, players, time, difficulty, videoUrl }], source: 'ai' | 'rules' }
//   dailyPicks()             매일 한 번 "오늘의 추천 게임"을 골라 settings/aiPicks 에 저장 (index.js 의 스케줄 함수가 부름)
//
// 원칙
//  - AI에게는 지금 대여 가능한(isAvailable) 게임만 후보로 주고, 돌아온 ID도 후보 안에 있는지 다시 확인한다.
//  - AI 호출이 실패하거나 키가 없으면 규칙 점수(scoreGame)로 고른다. 손님 화면이 비는 일이 없게.
//  - 손님 앱의 규칙(lib/services/ai_service.dart scoreGame)과 같은 기준을 쓴다.

const EXPERIENCE = { first: '처음이에요', sometimes: '가끔 해요', often: '자주 해요' };
const MOODS = { brain: '머리싸움', party: '왁자지껄 파티', coop: '다 같이 협력', bluff: '눈치·심리전', quick: '짧게 여러 판' };
const TIMES = { 30: '30분 이내', 60: '1시간 정도', any: '상관없어요' };
const MOOD_KEYWORDS = {
  brain: ['전략', '두뇌', '추상', '퍼즐', '경제', '엔진'],
  party: ['파티', '순발력', '액션', '단어', '그림', '웃음'],
  coop: ['협력'],
  bluff: ['블러핑', '심리', '추리', '마피아', '정체', '눈치'],
  quick: [],
};

const DEFAULT_MODEL = 'claude-haiku-5-5';
const MAX_CANDIDATES = 25;
const ALLOWED_ORIGIN_RE = /^(https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?|https:\/\/platform6-boardpad\.(web\.app|firebaseapp\.com))$/;

// ── 입력 검사 ──
function parseAsk(body) {
  const b = body && typeof body === 'object' ? body : {};
  const players = Number.parseInt(b.players, 10);
  if (!Number.isInteger(players) || players < 2 || players > 6) return null;
  if (!Object.hasOwn(EXPERIENCE, b.experience)) return null;
  const time = String(b.time ?? 'any');
  if (!Object.hasOwn(TIMES, time)) return null;
  const moods = Array.isArray(b.moods) ? [...new Set(b.moods.map(String))].filter((m) => Object.hasOwn(MOODS, m)) : [];
  const count = Math.min(4, Math.max(2, Number.parseInt(b.count, 10) || 3));
  const exclude = Array.isArray(b.exclude) ? b.exclude.slice(0, 200).map(String) : [];
  return { players, experience: b.experience, moods, time, count, exclude };
}

// ── 게임 데이터 ──
function str(v) {
  const s = v == null ? '' : String(v).trim();
  return s || null;
}

function gameView(id, g) {
  return {
    gameId: id,
    title: str(g.title) || '',
    imageUrl: str(g.imageUrl),
    players: str(g.players),
    time: str(g.time),
    difficulty: str(g.difficulty),
    videoUrl: str(g.videoUrl),
  };
}

function genresOf(g) {
  const list = Array.isArray(g.genres) ? g.genres.map(String) : [];
  if (g.genre) list.push(String(g.genre));
  return [...new Set(list.filter(Boolean))];
}

function playersRange(g) {
  if (typeof g.minPlayers === 'number' && typeof g.maxPlayers === 'number') return { min: g.minPlayers, max: g.maxPlayers };
  const text = String(g.players ?? '');
  const nums = (text.match(/\d+/g) || []).map(Number);
  if (!nums.length) return null;
  if (text.includes('이상')) return { min: nums[0], max: 99 };
  if (nums.length === 1) return { min: nums[0], max: nums[0] };
  return { min: nums[0], max: nums[nums.length - 1] };
}

function minutesOf(g) {
  const text = String(g.time ?? '');
  const hour = text.match(/(\d+)\s*시간/);
  const rest = text.replace(/\d+\s*시간/g, '');
  const nums = (rest.match(/\d+/g) || []).map(Number);
  let total = hour ? Number(hour[1]) * 60 : 0;
  if (nums.length) total += Math.max(...nums);
  return total || null;
}

/** 조건에 안 맞으면 null, 맞으면 { score, reason } */
function scoreGame(g, ask) {
  let score = 0;
  const reasons = [];

  const range = playersRange(g);
  if (range) {
    const p = ask.players;
    const fits = p >= 6 ? range.max >= 6 : p >= range.min && p <= range.max;
    if (!fits) return null;
    score += 3;
    reasons.push(p >= 6 ? '여럿이 함께 하기 좋고' : `${p}명이 하기 좋고`);
  }

  const minutes = minutesOf(g);
  if (minutes) {
    if (ask.time === '30') {
      if (minutes > 45) return null;
      if (minutes <= 30) {
        score += 2;
        reasons.push('30분 안에 끝나요');
      }
    } else if (ask.time === '60') {
      if (minutes > 90) score -= 2;
      if (minutes >= 30 && minutes <= 75) {
        score += 2;
        reasons.push('1시간 안팎이면 충분해요');
      }
    }
    if (ask.moods.includes('quick') && minutes <= 20) {
      score += 2;
      reasons.push('짧게 여러 판 하기 좋아요');
    }
  }

  const diff = String(g.difficulty ?? '');
  if (ask.experience === 'first') {
    if (diff === '매우쉬움' || diff === '쉬움') {
      score += 3;
      reasons.push('처음이어도 금방 배워요');
    }
    if (['어려움', '매우어려움', '전문'].includes(diff)) score -= 4;
  } else if (ask.experience === 'sometimes') {
    if (diff === '쉬움' || diff === '보통') score += 2;
    if (diff === '매우어려움' || diff === '전문') score -= 3;
  } else if (ask.experience === 'often') {
    if (['보통', '어려움', '매우어려움'].includes(diff)) {
      score += 2;
      reasons.push('해 볼 만한 깊이가 있어요');
    }
  }

  const words = [...genresOf(g), String(g.tags ?? '')].join(' ');
  for (const mood of ask.moods) {
    if ((MOOD_KEYWORDS[mood] || []).some((k) => words.includes(k))) {
      score += 2;
      reasons.push(`${MOODS[mood]} 분위기에 맞아요`);
    }
  }
  if (g.isRecommended === true) score += 1;

  return { score, reason: reasons.length ? reasons.slice(0, 2).join(', ') : '조건에 맞는 게임이에요' };
}

// ── AI 호출 ──
function candidateLine(c) {
  const g = c.game;
  const parts = [
    `id=${c.id}`,
    `이름=${str(g.title) || ''}`,
    g.players ? `인원=${g.players}` : null,
    g.time ? `시간=${g.time}` : null,
    g.difficulty ? `난이도=${g.difficulty}` : null,
    genresOf(g).length ? `장르=${genresOf(g).join('/')}` : null,
    g.tags ? `태그=${String(g.tags).slice(0, 60)}` : null,
    g.isRecommended ? '직원추천' : null,
  ].filter(Boolean);
  return `- ${parts.join(' | ')}`;
}

const SYSTEM_PROMPT =
  '너는 보드게임 카페 직원이야. 손님 테이블에 맞는 보드게임을 골라 주는 역할이야. ' +
  '반드시 주어진 후보 목록 안의 게임만 고르고, id는 목록에 적힌 그대로 써. ' +
  '추천 이유는 손님에게 직접 말하듯 친근한 존댓말 한두 문장(60자 이내)으로, 그 게임이 이 테이블 조건에 왜 맞는지 구체적으로 써. ' +
  '게임 규칙이나 수상 경력처럼 목록에 없는 사실은 지어내지 마. ' +
  '답은 JSON 하나만 출력해: {"picks":[{"gameId":"...","reason":"..."}]}';

async function callClaude({ apiKey, model, system, user, fetchImpl = fetch, timeoutMs = 20000 }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model,
        max_tokens: 700,
        system,
        messages: [{ role: 'user', content: user }],
      }),
    });
    if (!res.ok) throw new Error(`AI 응답 오류 ${res.status}`);
    const data = await res.json();
    const text = (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
    return text;
  } finally {
    clearTimeout(timer);
  }
}

/** AI 답에서 후보 안에 있는 것만 골라냄 */
function parsePicks(text, candidateIds, count) {
  const s = String(text || '');
  const start = s.indexOf('{');
  const end = s.lastIndexOf('}');
  if (start < 0 || end <= start) return [];
  let obj;
  try {
    obj = JSON.parse(s.slice(start, end + 1));
  } catch {
    return [];
  }
  const out = [];
  const seen = new Set();
  for (const p of Array.isArray(obj.picks) ? obj.picks : []) {
    const id = String(p && p.gameId != null ? p.gameId : '');
    if (!candidateIds.has(id) || seen.has(id)) continue;
    seen.add(id);
    const reason = String(p.reason || '').replace(/\s+/g, ' ').trim().slice(0, 120);
    out.push({ gameId: id, reason });
    if (out.length >= count) break;
  }
  return out;
}

/** 규칙으로 고르기 (AI 실패 시) */
function rulePicks(scored, count) {
  return scored.slice(0, count).map((c) => ({ gameId: c.id, reason: c.reason }));
}

function rankCandidates(games, ask) {
  const excluded = new Set(ask.exclude);
  const scored = [];
  for (const [id, g] of games) {
    if (excluded.has(id) || !str(g.title)) continue;
    const r = scoreGame(g, ask);
    if (!r) continue;
    scored.push({ id, game: g, score: r.score, reason: r.reason });
  }
  scored.sort((a, b) => b.score - a.score || String(a.game.title).localeCompare(String(b.game.title)));
  return scored;
}

async function recommend({ ask, games, llm }) {
  const scored = rankCandidates(games, ask);
  if (!scored.length) return { picks: [], source: 'rules' };
  const candidates = scored.slice(0, MAX_CANDIDATES);
  const byId = new Map(candidates.map((c) => [c.id, c]));

  let picks = [];
  let source = 'rules';
  if (llm) {
    const user = [
      `테이블 조건: 인원 ${ask.players >= 6 ? '6명 이상' : `${ask.players}명`}, 경험 "${EXPERIENCE[ask.experience]}", ` +
        `분위기 ${ask.moods.length ? ask.moods.map((m) => `"${MOODS[m]}"`).join(', ') : '상관없음'}, 한 판 시간 "${TIMES[ask.time]}"`,
      `추천 개수: ${ask.count}개 (서로 다른 느낌으로)`,
      '후보 게임 (조건에 대략 맞는 순서):',
      ...candidates.map(candidateLine),
    ].join('\n');
    try {
      picks = parsePicks(await llm({ system: SYSTEM_PROMPT, user }), new Set(byId.keys()), ask.count);
      if (picks.length) source = 'ai';
    } catch (e) {
      console.warn('[AI 추천 실패 → 규칙 추천]', e && e.message);
    }
  }
  // AI가 적게 골랐으면 규칙 추천으로 채움
  if (picks.length < ask.count) {
    const have = new Set(picks.map((p) => p.gameId));
    for (const p of rulePicks(candidates, candidates.length)) {
      if (picks.length >= ask.count) break;
      if (!have.has(p.gameId)) picks.push(p);
    }
  }
  return {
    picks: picks.map((p) => ({ ...gameView(p.gameId, byId.get(p.gameId).game), reason: p.reason || byId.get(p.gameId).reason })),
    source,
  };
}

// ── 오늘의 추천 ──
function seededShuffle(list, seedText) {
  let seed = 0;
  for (const ch of seedText) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    seed = (seed * 1103515245 + 12345) >>> 0;
    const j = seed % (i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

async function dailyPicks({ games, llm, dateKey, exclude = [], count = 4 }) {
  const excluded = new Set(exclude);
  const all = [...games].filter(([id, g]) => !excluded.has(id) && str(g.title));
  if (!all.length) return { date: dateKey, picks: [], source: 'rules' };
  // 직원 추천을 앞쪽에 두되 날마다 섞어서 후보 40개
  const recommended = seededShuffle(all.filter(([, g]) => g.isRecommended === true), dateKey);
  const others = seededShuffle(all.filter(([, g]) => g.isRecommended !== true), dateKey);
  const candidates = [...recommended, ...others].slice(0, 40).map(([id, game]) => ({ id, game }));
  const byId = new Map(candidates.map((c) => [c.id, c]));

  let picks = [];
  let source = 'rules';
  if (llm) {
    const user = [
      `오늘(${dateKey}) 매장 패드 첫 화면에 걸 "오늘의 추천 게임" ${count}개를 골라 줘.`,
      '처음 온 손님도 고르기 쉽게, 인원·분위기·난이도가 서로 겹치지 않게 다양하게 골라 줘.',
      '이유는 "이런 테이블에 좋아요"처럼 어떤 손님에게 맞는지 짧게.',
      '후보 게임:',
      ...candidates.map(candidateLine),
    ].join('\n');
    try {
      picks = parsePicks(await llm({ system: SYSTEM_PROMPT, user }), new Set(byId.keys()), count);
      if (picks.length) source = 'ai';
    } catch (e) {
      console.warn('[오늘의 추천 AI 실패 → 규칙]', e && e.message);
    }
  }
  if (picks.length < count) {
    const have = new Set(picks.map((p) => p.gameId));
    for (const c of candidates) {
      if (picks.length >= count) break;
      if (have.has(c.id)) continue;
      picks.push({ gameId: c.id, reason: c.game.isRecommended ? '직원이 추천하는 게임이에요' : '오늘 한번 해 보세요' });
    }
  }
  return {
    date: dateKey,
    picks: picks.map((p) => ({ ...gameView(p.gameId, byId.get(p.gameId).game), reason: p.reason })),
    source,
  };
}

// ── HTTP 처리 ──
function createLimiter(now) {
  const hits = new Map();
  return function limit(key, max, windowMs) {
    const t = now();
    const list = (hits.get(key) || []).filter((x) => t - x < windowMs);
    if (list.length >= max) {
      hits.set(key, list);
      return false;
    }
    list.push(t);
    hits.set(key, list);
    if (hits.size > 5000) hits.clear();
    return true;
  };
}

/**
 * loadGames: () => Promise<Map<id, gameData>>  (대여 가능한 게임만)
 * llm: ({system, user}) => Promise<string> | null
 */
function createAiHandler({ loadGames, llm, now = () => Date.now() }) {
  const limit = createLimiter(now);
  let cache = null;
  async function games() {
    if (cache && now() - cache.at < 5 * 60 * 1000) return cache.games;
    const g = await loadGames();
    cache = { at: now(), games: g };
    return g;
  }

  return async function handle(req) {
    const origin = req.headers.origin || '';
    const cors = {};
    if (origin && ALLOWED_ORIGIN_RE.test(origin)) {
      cors['Access-Control-Allow-Origin'] = origin;
      cors['Vary'] = 'Origin';
      cors['Access-Control-Allow-Headers'] = 'content-type';
      cors['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
      cors['Access-Control-Max-Age'] = '3600';
    }
    const reply = (status, body) => ({ status, headers: { ...cors, 'Cache-Control': 'no-store' }, body });

    if (req.method === 'OPTIONS') return reply(204, null);
    if (req.path !== '/api/ai/recommend') return reply(404, { message: '없는 주소예요.' });
    if (req.method !== 'POST') return reply(405, { message: 'POST로 보내 주세요.' });

    const ip = String(req.headers['x-forwarded-for'] || 'unknown').split(',')[0].trim();
    if (!limit(`ip:${ip}`, 20, 10 * 60 * 1000) || !limit('all', 300, 10 * 60 * 1000)) {
      return reply(429, { message: '추천 요청이 너무 많아요. 잠시 후 다시 시도해 주세요.' });
    }

    const ask = parseAsk(req.body);
    if (!ask) return reply(400, { message: '조건을 다시 골라 주세요.' });

    try {
      const out = await recommend({ ask, games: await games(), llm });
      return reply(200, out);
    } catch (e) {
      console.error('[AI 추천 오류]', e);
      return reply(500, { message: '추천 중 오류가 났어요.' });
    }
  };
}

module.exports = {
  createAiHandler,
  recommend,
  dailyPicks,
  scoreGame,
  parseAsk,
  parsePicks,
  callClaude,
  DEFAULT_MODEL,
};
