'use strict';
// 자동 번역 (83차) — 네트워크 없이: 가짜 번역기 + 메모리 저장소
const test = require('node:test');
const assert = require('node:assert');
const { createHandler } = require('../src/app');
const { createMemoryAttempts } = require('../src/attempts');
const { createMemoryStores } = require('../src/stores');
const {
  createTranslateRoutes, createGoogleTranslator, createMemoryTranslateData, planMenu,
} = require('../src/translate');

// 가짜 번역기: '[en]원문' 처럼 돌려줌 + 몇 번·몇 글자 불렸는지 셈
function fakeTranslator() {
  const calls = [];
  const fn = async (texts, target) => {
    calls.push({ texts: [...texts], target });
    return texts.map((t) => `[${target}]${t}`);
  };
  fn.calls = calls;
  return fn;
}
const httpError = (status, code, message) => Object.assign(new Error(message), { status, code });

const MENUS = {
  platform6: {
    m1: { name: '아메리카노', price: 3500, category: '커피',
      optionGroups: [{ groupName: '온도', isRequired: true, options: [{ name: 'HOT', price: 0 }, { name: '아이스', price: 500 }] }] },
    m2: { name: '레몬 에이드', price: 5000, optionGroups: [] },
  },
};
const SETTINGS = {
  platform6: {
    notices: [{ type: 'text', title: '이용안내', content: '음식물 반입 금지' }, { type: 'image', title: '가격표', content: 'https://x/y.png' }],
    events: [{ type: 'text', title: '새로운 이벤트', content: '' }],
  },
};

test('처음엔 전부 번역, 다시 부르면 아무것도 안 함, 글을 고치면 그것만', async () => {
  const data = createMemoryTranslateData({ menus: MENUS, settings: SETTINGS });
  const tr = fakeTranslator();
  const t = createTranslateRoutes({ data, translator: tr, httpError });

  const r1 = await t.syncStore('platform6');
  assert.deepEqual([r1.menus, r1.notices, r1.events], [2, 1, 1]);
  assert.deepEqual(tr.calls.map((c) => c.target), ['en', 'zh-CN', 'ja']); // 언어마다 한 번에 모아서
  const m1 = data.menus.platform6.m1;
  assert.equal(m1.translations.en.name, '[en]아메리카노');
  assert.equal(m1.translations.zh.name, '[zh-CN]아메리카노');
  assert.equal(m1.translations.ja.name, '[ja]아메리카노');
  assert.equal(m1.optionGroups[0].translations.en.groupName, '[en]온도');
  assert.equal(m1.optionGroups[0].options[1].translations.ja.name, '[ja]아이스');
  assert.equal(m1.optionGroups[0].options[1].price, 500); // 다른 칸은 그대로
  assert.equal(m1.price, 3500);
  const notices = data.settings.platform6.notices;
  assert.equal(notices[0].translations.en.content, '[en]음식물 반입 금지');
  assert.equal(notices[1].translations.en.title, '[en]가격표');
  assert.equal(notices[1].translations.en.content, undefined); // 사진 글은 제목만
  assert.equal(notices[1].content, 'https://x/y.png');
  assert.deepEqual(Object.keys(data.settings.platform6.events[0].translations.en), ['title']); // 빈 내용은 안 보냄
  assert.ok(r1.chars > 0);

  // 다시 부르면 번역 API를 안 부름
  const before = tr.calls.length;
  const r2 = await t.syncStore('platform6');
  assert.deepEqual([r2.menus, r2.notices, r2.events, r2.chars], [0, 0, 0, 0]);
  assert.equal(tr.calls.length, before);

  // 메뉴 이름을 고치면 그 글만 다시 (옵션은 그대로)
  data.menus.platform6.m2.name = '자몽 에이드';
  const r3 = await t.syncStore('platform6');
  assert.equal(r3.menus, 1);
  assert.deepEqual(tr.calls.slice(before).map((c) => c.texts), [['자몽 에이드'], ['자몽 에이드'], ['자몽 에이드']]);
  assert.equal(data.menus.platform6.m2.translations.en.name, '[en]자몽 에이드');

  // 관리자 웹이 옵션 그룹을 새로 저장해 번역이 빠지면 다시 채움
  data.menus.platform6.m1.optionGroups = [{ groupName: '온도', options: [{ name: 'HOT', price: 0 }] }];
  const r4 = await t.syncStore('platform6');
  assert.equal(r4.menus, 1);
  assert.equal(data.menus.platform6.m1.optionGroups[0].options[0].translations.zh.name, '[zh-CN]HOT');
});

test('이름이 지워지면 번역도 지움, 다른 매장은 안 건드림', async () => {
  const data = createMemoryTranslateData({ menus: { ...MENUS, other: { x: { name: '라면' } } }, settings: {} });
  const t = createTranslateRoutes({ data, translator: fakeTranslator(), httpError });
  await t.syncStore('platform6');
  data.menus.platform6.m2.name = '  ';
  await t.syncStore('platform6');
  assert.equal(data.menus.platform6.m2.translations, undefined);
  assert.equal(data.menus.other.x.translations, undefined);
  assert.equal(planMenu(data.menus.platform6.m1).units.length, 0);
});

test('API: 관리자만, 번역기가 없으면 503, 번역 API 오류는 502 + 문구', async () => {
  const fakeVerify = async (tok) => {
    if (tok === 'admin') return { uid: 'admin-web.platform6', admin: true, store: 'platform6' };
    if (tok === 'pad3') return { uid: 'pad.platform6.3', pad: true, store: 'platform6', room: 3 };
    throw new Error('bad');
  };
  const make = (translator) => {
    const stores = createMemoryStores({ platform6: { name: '플랫폼6', account: {} } });
    const data = createMemoryTranslateData({ menus: MENUS, settings: SETTINGS });
    const translate = createTranslateRoutes({ data, translator, httpError });
    const h = createHandler({ bgg: {}, stores, verifyIdToken: fakeVerify, createToken: async () => 'x', attempts: createMemoryAttempts(), translate });
    return (token) => h({ method: 'POST', path: '/api/translate/sync', query: {}, body: {}, headers: token ? { authorization: `Bearer ${token}` } : {} });
  };
  const call = make(fakeTranslator());
  assert.equal((await call()).status, 401);
  assert.equal((await call('pad3')).status, 403);
  const ok = await call('admin');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.menus, 2);
  assert.equal((await make(null)('admin')).status, 503);
  const broken = await make(async () => { throw new Error('Cloud Translation API가 꺼져 있어요. (운영자: Google Cloud 콘솔에서 켜기)'); })('admin');
  assert.equal(broken.status, 502);
  assert.match(broken.body.message, /꺼져 있어요/);
});

test('Google 번역기: 요청 모양·100개씩 나누기·꺼져 있을 때 문구', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    const q = JSON.parse(init.body).q;
    return { ok: true, status: 200, text: async () => JSON.stringify({ data: { translations: q.map((s) => ({ translatedText: `T:${s}` })) } }) };
  };
  const g = createGoogleTranslator({ getAccessToken: async () => 'tok', fetchImpl });
  const texts = Array.from({ length: 150 }, (_, i) => `글${i}`);
  const out = await g(texts, 'ja');
  assert.equal(out.length, 150);
  assert.equal(out[149], 'T:글149');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://translation.googleapis.com/language/translate/v2');
  assert.equal(calls[0].init.headers.authorization, 'Bearer tok');
  assert.deepEqual({ ...calls[0].body, q: calls[0].body.q.length }, { q: 100, source: 'ko', target: 'ja', format: 'text' });

  const off = createGoogleTranslator({
    getAccessToken: async () => 'tok',
    fetchImpl: async () => ({ ok: false, status: 403, text: async () => '{"error":{"status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}' }),
  });
  await assert.rejects(off(['a'], 'en'), /꺼져 있어요/);
});
