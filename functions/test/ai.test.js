'use strict';
// 실행: cd functions && node --test test/*.test.js   (네트워크 없이 가짜 AI로 확인)
const test = require('node:test');
const assert = require('node:assert');
const { createAiHandler, recommend, dailyPicks, scoreGame, parseAsk, parsePicks } = require('../src/ai');

const GAMES = new Map([
  ['g1', { title: '할리갈리', players: '2~6인', time: '15분', difficulty: '매우쉬움', genres: ['파티', '순발력'], isRecommended: true }],
  ['g2', { title: '카탄', players: '3~4인', time: '1시간', difficulty: '어려움', genres: ['전략'] }],
  ['g3', { title: '팬데믹', players: '2~4인', time: '45분', difficulty: '보통', genres: ['협력'] }],
  ['g4', { title: '레지스탕스', players: '5~10인', time: '30분', difficulty: '쉬움', genres: ['블러핑'] }],
  ['g5', { title: '스플렌더', players: '2~4인', time: '30분', difficulty: '쉬움', genres: ['전략', '경제'], isRecommended: true }],
  ['g6', { title: '', players: '2~4인' }], // 이름 없는 게임은 후보에서 빠짐
]);

const ask = (over = {}) => parseAsk({ players: 4, experience: 'sometimes', moods: [], time: 'any', count: 3, ...over });

test('입력 검사', () => {
  assert.equal(parseAsk({ players: 1, experience: 'first', time: 'any' }), null);
  assert.equal(parseAsk({ players: 4, experience: 'hacker', time: 'any' }), null);
  assert.equal(parseAsk({ players: 4, experience: 'first', time: '999' }), null);
  const a = parseAsk({ players: '4', experience: 'first', time: '30', moods: ['party', 'evil', 'party'], count: 9 });
  assert.deepEqual(a.moods, ['party']);
  assert.equal(a.count, 4);
});

test('인원이 안 맞으면 후보에서 빠짐', () => {
  assert.equal(scoreGame(GAMES.get('g2'), ask({ players: 2 })), null);
  assert.equal(scoreGame(GAMES.get('g4'), ask({ players: 4 })), null);
  assert.ok(scoreGame(GAMES.get('g4'), ask({ players: 6 })));
});

test('30분 이내면 긴 게임은 빠짐', () => {
  assert.equal(scoreGame(GAMES.get('g2'), ask({ time: '30' })), null);
});

test('AI 없이 규칙으로 추천', async () => {
  const out = await recommend({ ask: ask({ moods: ['party'] }), games: GAMES, llm: null });
  assert.equal(out.source, 'rules');
  assert.ok(out.picks.slice(0, 2).some((p) => p.gameId === 'g1')); // 파티 게임이 위쪽에
  assert.ok(out.picks.every((p) => p.title));
});

test('AI가 없는 게임 ID를 말해도 걸러냄', async () => {
  const llm = async () => '설명 {"picks":[{"gameId":"없는게임","reason":"x"},{"gameId":"g3","reason":"협력해서 같이 이겨요"}]} 끝';
  const out = await recommend({ ask: ask({ moods: ['coop'] }), games: GAMES, llm });
  assert.equal(out.source, 'ai');
  assert.equal(out.picks[0].gameId, 'g3');
  assert.equal(out.picks[0].reason, '협력해서 같이 이겨요');
  assert.equal(out.picks.length, 3); // 모자란 건 규칙으로 채움
  assert.ok(!out.picks.some((p) => p.gameId === '없는게임'));
});

test('AI 오류면 규칙으로', async () => {
  const llm = async () => {
    throw new Error('timeout');
  };
  const out = await recommend({ ask: ask(), games: GAMES, llm });
  assert.equal(out.source, 'rules');
  assert.equal(out.picks.length, 3);
});

test('제외한 게임은 추천 안 함', async () => {
  const out = await recommend({ ask: ask({ exclude: ['g1', 'g5'] }), games: GAMES, llm: null });
  assert.ok(!out.picks.some((p) => p.gameId === 'g1' || p.gameId === 'g5'));
});

test('parsePicks: 깨진 JSON', () => {
  assert.deepEqual(parsePicks('그냥 글', new Set(['g1']), 3), []);
  assert.deepEqual(parsePicks('{"picks": [', new Set(['g1']), 3), []);
});

test('오늘의 추천: 날짜가 같으면 같은 결과, 직원 추천 우선', async () => {
  const a = await dailyPicks({ games: GAMES, llm: null, dateKey: '2026-10-26', count: 2 });
  const b = await dailyPicks({ games: GAMES, llm: null, dateKey: '2026-10-26', count: 2 });
  assert.deepEqual(a, b);
  assert.deepEqual(a.picks.map((p) => p.gameId).sort(), ['g1', 'g5']);
});

test('HTTP: CORS, 메서드, 횟수 제한', async () => {
  let t = 0;
  const h = createAiHandler({ loadGames: async () => GAMES, llm: null, now: () => t });
  const body = { players: 4, experience: 'first', moods: [], time: 'any' };
  const ok = await h({ method: 'POST', path: '/api/ai/recommend', headers: { origin: 'https://platform6-boardpad.web.app' }, body });
  assert.equal(ok.status, 200);
  assert.equal(ok.headers['Access-Control-Allow-Origin'], 'https://platform6-boardpad.web.app');
  const evil = await h({ method: 'POST', path: '/api/ai/recommend', headers: { origin: 'https://evil.example' }, body });
  assert.equal(evil.headers['Access-Control-Allow-Origin'], undefined);
  assert.equal((await h({ method: 'GET', path: '/api/ai/recommend', headers: {} })).status, 405);
  assert.equal((await h({ method: 'POST', path: '/api/ai/recommend', headers: {}, body: { players: 99 } })).status, 400);
  let last;
  for (let i = 0; i < 25; i++) {
    last = await h({ method: 'POST', path: '/api/ai/recommend', headers: { 'x-forwarded-for': '1.2.3.4' }, body });
  }
  assert.equal(last.status, 429);
});
