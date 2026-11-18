'use strict';
// 손님 패드 자동 번역 (83차) — 메뉴·공지·이벤트의 글을 영어·중국어(간체)·일본어로 번역해 같은 문서에 넣음
//
//   POST /api/translate/sync   (관리자) 그 매장 메뉴 전부 + settings/notices·events 의 글 중 새로 생기거나 바뀐 것만 번역
//        관리자 웹이 메뉴·공지·이벤트를 저장한 뒤, 그리고 로그인한 뒤에 부름 (lib/services/translate_sync.dart)
//        → { ok, menus, notices, events, chars }  (고친 문서 수, 번역에 보낸 글자 수 × 3개 언어)
//
// 엔진: Google Cloud Translation 기본(v2) — 월 50만 자 무료(그 뒤 100만 자당 $20). 함수 서비스 계정 권한으로 부름(비밀값 없음).
//   콘솔에서 'Cloud Translation API'를 켜야 함. ★서비스가 커지면 Claude로 바꿀 후보 — 프로젝트 문서 claude/고도리-서비스-커지면-바꿀-것.md
//
// 저장 모양 (앱 lib/l10n/guest_language.dart guestField 가 translations[언어][칸]을 읽음, 없으면 원문):
//   menus/{id}                 translations: { en: { name }, zh: { name }, ja: { name }, _src }
//   menus/{id}.optionGroups[]  translations: { en: { groupName }, … }   options[]: translations: { en: { name }, … }
//   settings/notices·events.items[]  translations: { en: { title, content }, … }  (사진 글(type image)은 title만)
//   _src = 번역할 때의 원문(JSON). 원문이 같으면 다시 번역하지 않음 — 관리자가 글을 고치면 _src가 달라져 다시 번역됨.
//   settings/categories        translations: { en: { 카테고리: 번역 }, zh, ja }  (104차 — 순서만 바뀌면 다시 번역 안 함)
//   120차: 사장님이 번역을 직접 고치는 화면(관리자 웹 '번역 관리') — 매장마다 고침표 settings/translationOverrides
//     { items: [{ src: 원문, en?, zh?, ja? }] } (최대 1000개). 고정 번역표(GLOSSARY)처럼 쓰임: 같은 원문이 쓰인 모든 곳(메뉴·옵션·
//     카테고리·공지·이벤트)에 들어가고, 구글보다·GLOSSARY보다 먼저. 비운 언어는 GLOSSARY·구글 번역.
//     고침표·GLOSSARY로 넣은 칸은 translations._fixed: ['name' …](카테고리는 이름 목록)로 표시 → 고침을 지우면 다음 번역 때 구글 번역으로 되돌림.
//   그 밖에 모든 매장에서 틀리는 말은 아래 GLOSSARY(고정 번역표)에 추가.

const LANGS = [['en', 'en'], ['zh', 'zh-CN'], ['ja', 'ja']];
const clean = (s) => (typeof s === 'string' ? s.trim() : '');
const srcOf = (fields) => JSON.stringify(fields);

// 고정 번역표 (104차) — 매장이 만든 이름·상품 이름처럼 구글 번역이 틀리는 말(예: 왕메리카노 → 「王メリカノ」).
// 원문이 표에 있으면 구글에 보내지 않고 이 번역을 씀. 띄어쓰기 무시, '뗴'는 '떼'로 봄(메뉴 이름 오타).
// 이미 번역된 메뉴도 표와 다르면 다음 번역 때 표대로 고쳐짐. 사장님이 직접 고치는 화면이 생기기 전까지 여기에 추가.
const GLOSSARY = {
  '왕메리카노': { en: 'Jumbo Americano', zh: '超大杯美式咖啡', ja: 'ジャンボアメリカーノ' },
  '꿀아메리카노': { en: 'Honey Americano', zh: '蜂蜜美式咖啡', ja: 'ハニーアメリカーノ' },
  '바닐라라떼': { en: 'Vanilla Latte', zh: '香草拿铁', ja: 'バニララテ' },
  '초코라떼': { en: 'Chocolate Latte', zh: '巧克力拿铁', ja: 'チョコラテ' },
  '미숫가루라떼': { en: 'Misutgaru (Multigrain) Latte', zh: '韩式五谷粉拿铁', ja: 'ミスッカルラテ（穀物ラテ）' },
  '미숫가루스무디': { en: 'Misutgaru (Multigrain) Smoothie', zh: '韩式五谷粉冰沙', ja: 'ミスッカルスムージー（穀物スムージー）' },
  '복숭아어른스티': { en: 'Grown-up Peach Iced Tea', zh: '成人版桃子冰茶', ja: '大人のピーチアイスティー' },
  '짐빔하이볼': { en: 'Jim Beam Highball', zh: '金宾嗨棒', ja: 'ジムビームハイボール' },
  '청양마요순살치킨': { en: 'Cheongyang Chili Mayo Boneless Chicken', zh: '青阳辣椒蛋黄酱无骨炸鸡', ja: '青陽唐辛子マヨ骨なしチキン' },
  '슈프림순살치킨': { en: 'Supreme Boneless Chicken', zh: '至尊无骨炸鸡', ja: 'シュプリーム骨なしチキン' },
  '팝콘감자': { en: 'Popcorn Fries', zh: '爆米花薯块', ja: 'ポップコーンポテト' },
  '소떡소떡': { en: 'Sotteok Sotteok (Sausage & Rice Cake Skewer)', zh: '香肠年糕串', ja: 'ソトクソトク（ソーセージとトッポッキの串）' },
  '순대강정': { en: 'Sweet & Spicy Fried Sundae', zh: '甜辣炸米肠', ja: 'スンデカンジョン（甘辛揚げスンデ）' },
  '신라면': { en: 'Shin Ramyun', zh: '辛拉面', ja: '辛ラーメン' },
  '진라면': { en: 'Jin Ramen', zh: '真拉面', ja: 'ジンラーメン' },
  '불닭볶음면': { en: 'Buldak Spicy Stir-fried Noodles', zh: '火鸡面', ja: 'ブルダック炒め麺' },
  '짜파게티': { en: 'Chapagetti (Black Bean Noodles)', zh: '炸酱面（Chapagetti）', ja: 'チャパゲティ（ジャージャー麺）' },
  '불닭게티': { en: 'Buldak-Chapagetti', zh: '火鸡炸酱面', ja: 'ブルダックチャパゲティ' },
  '낚지볶음밥': { en: 'Octopus Fried Rice', zh: '章鱼炒饭', ja: 'タコチャーハン' },
  '낙지볶음밥': { en: 'Octopus Fried Rice', zh: '章鱼炒饭', ja: 'タコチャーハン' },
  '홈런볼초코': { en: 'Home Run Ball (Chocolate)', zh: '本垒打泡芙（巧克力）', ja: 'ホームランボール（チョコ）' },
  '홈런볼소금우유': { en: 'Home Run Ball (Salted Milk)', zh: '本垒打泡芙（盐牛奶）', ja: 'ホームランボール（塩ミルク）' },
  '1샷추가': { en: 'Extra shot', zh: '加一份浓缩', ja: 'ショット追加' },
  '샷추가': { en: 'Extra shot', zh: '加浓缩', ja: 'ショット追加' },
  '연하게': { en: 'Light (less coffee)', zh: '淡一点', ja: '薄め' },
  '진하게': { en: 'Strong', zh: '浓一点', ja: '濃いめ' },
  // 카테고리
  '라떼': { en: 'Latte', zh: '拿铁', ja: 'ラテ' },
  '티': { en: 'Tea', zh: '茶', ja: 'ティー' },
  '에이드': { en: 'Ade', zh: '气泡果饮', ja: 'エード' },
  '하이볼': { en: 'Highball', zh: '嗨棒', ja: 'ハイボール' },
  '하이볼/캔맥주': { en: 'Highball / Canned Beer', zh: '嗨棒/罐装啤酒', ja: 'ハイボール／缶ビール' },
  '튀김류': { en: 'Fried Food', zh: '炸物', ja: '揚げ物' },
  '라면/식사류': { en: 'Ramen / Meals', zh: '拉面/简餐', ja: 'ラーメン／お食事' },
  '프라페/쉐이크': { en: 'Frappé / Shake', zh: '冰沙/奶昔', ja: 'フラッペ／シェイク' },
  '프라페/밀크쉐이크': { en: 'Frappé / Milkshake', zh: '冰沙/奶昔', ja: 'フラッペ／ミルクシェイク' },
  '추가메뉴': { en: 'Extras', zh: '加点', ja: '追加メニュー' },
};
const glossKey = (s) => clean(s).replace(/\s+/g, '').replace(/뗴/g, '떼');
const glossaryOf = (s) => GLOSSARY[glossKey(s)] || null;
// 120차: 매장 고침표 + GLOSSARY → fx(원문) = { en?, zh?, ja? } | null (언어마다 고침표가 먼저, 빈 언어는 GLOSSARY)
const MAX_OVERRIDES = 1000;
function makeFixed(overrides) {
  const ovr = new Map();
  for (const it of (Array.isArray(overrides) ? overrides : []).slice(0, MAX_OVERRIDES)) {
    if (!it || typeof it !== 'object') continue;
    const k = glossKey(it.src);
    if (!k) continue;
    const v = {};
    for (const [code] of LANGS) if (clean(it[code])) v[code] = clean(it[code]);
    if (Object.keys(v).length) ovr.set(k, v);
  }
  return (s) => {
    const g = glossaryOf(s);
    const o = ovr.get(glossKey(s));
    if (!g && !o) return null;
    return { ...(g || {}), ...(o || {}) };
  };
}
// 이미 번역된 칸 중 고정 번역(고침표·GLOSSARY)과 다른 게 있으면 true (표에 새로 넣은 말을 기존 메뉴에도 반영)
// 120차: 고정 번역으로 넣었던 칸(_fixed)인데 이제 고정 번역이 없으면(고침을 지움) true → 구글 번역으로 되돌림
function glossaryStale(t, fields, fx = glossaryOf) {
  for (const [k, v] of Object.entries(fields)) {
    const g = fx(v);
    if (!g) {
      if (Array.isArray(t._fixed) && t._fixed.includes(k)) return true;
      continue;
    }
    for (const [code] of LANGS) if (g[code] && (!t[code] || t[code][k] !== g[code])) return true;
  }
  return false;
}

// 번역할 칸 하나 묶음(unit): { obj(새로 만든 사본 — 여기에 translations를 씀), fields: { 칸: 원문 } }
function addUnit(units, obj, raw, fx = glossaryOf) {
  const fields = {};
  for (const [k, v] of Object.entries(raw)) {
    const s = clean(v);
    if (s) fields[k] = s;
  }
  const t = obj.translations;
  if (!Object.keys(fields).length) {
    if (t !== undefined) {
      delete obj.translations; // 글이 지워졌으면 번역도 지움
      units.push({ obj, fields, removeOnly: true });
    }
    return;
  }
  if (!(t && typeof t === 'object' && t._src === srcOf(fields)) || glossaryStale(t, fields, fx)) units.push({ obj, fields });
}

// 메뉴 문서 → { patch 재료(사본), units }
function planMenu(menu, fx = glossaryOf) {
  const doc = { translations: menu.translations };
  const units = [];
  addUnit(units, doc, { name: menu.name }, fx);
  if (Array.isArray(menu.optionGroups)) {
    doc.optionGroups = menu.optionGroups.map((g) => {
      if (!g || typeof g !== 'object') return g;
      const ng = { ...g };
      addUnit(units, ng, { groupName: g.groupName }, fx);
      if (Array.isArray(g.options)) {
        ng.options = g.options.map((o) => {
          if (!o || typeof o !== 'object') return o;
          const no = { ...o };
          addUnit(units, no, { name: o.name }, fx);
          return no;
        });
      }
      return ng;
    });
  }
  return { doc, units };
}

// 공지·이벤트 items → { items(사본), units }
function planItems(items, fx = glossaryOf) {
  const units = [];
  const list = (Array.isArray(items) ? items : []).map((it) => {
    if (!it || typeof it !== 'object') return it;
    const ni = { ...it };
    addUnit(units, ni, it.type === 'image' ? { title: it.title } : { title: it.title, content: it.content }, fx);
    return ni;
  });
  return { items: list, units };
}

// 카테고리 (104차) — settings/categories { list, translations: { en: { 원문: 번역 }, zh, ja } }
// 순서만 바꾸면 다시 번역하지 않음. 없는 이름의 번역은 지움.
function planCategories(doc, fx = glossaryOf) {
  const list = [...new Set((Array.isArray(doc && doc.list) ? doc.list : []).map(clean).filter(Boolean))];
  const old = (doc && typeof doc.translations === 'object' && doc.translations) || {};
  const oldFixed = Array.isArray(old._fixed) ? old._fixed : [];
  const need = list.filter((c) => {
    const g = fx(c);
    if (!g && oldFixed.includes(c)) return true; // 120차: 고침을 지움 → 구글 번역으로
    return LANGS.some(([code]) => {
      const v = old[code] && old[code][c];
      return !(typeof v === 'string' && v.trim()) || (g && g[code] && v !== g[code]);
    });
  });
  const extra = LANGS.some(([code]) => Object.keys(old[code] || {}).some((k) => !list.includes(k)));
  return { list, old, need, changed: need.length > 0 || extra };
}
function applyCategories(p, cache, fx = glossaryOf) {
  if (!p.need.every((c) => cache.has(c))) return null;
  const tr = {};
  for (const [code] of LANGS) {
    tr[code] = {};
    for (const c of p.list) {
      tr[code][c] = p.need.includes(c) ? (cache.get(c)[code] || c) : p.old[code][c];
    }
  }
  const fixed = p.list.filter((c) => fx(c)); // 120차: 고정 번역으로 넣은 카테고리
  if (fixed.length) tr._fixed = fixed;
  return tr;
}

const textsOf = (units) => units.filter((u) => !u.removeOnly).flatMap((u) => Object.values(u.fields));

// cache: Map 원문 → { en, zh, ja }. 하나라도 없으면 false(쓰지 않음)
function applyUnits(units, cache, fx = glossaryOf) {
  for (const u of units) {
    if (u.removeOnly) continue;
    if (!Object.values(u.fields).every((t) => cache.has(t))) return false;
  }
  for (const u of units) {
    if (u.removeOnly) continue;
    const tr = { _src: srcOf(u.fields) };
    for (const [code] of LANGS) {
      tr[code] = {};
      for (const [k, v] of Object.entries(u.fields)) tr[code][k] = cache.get(v)[code] || v;
    }
    const fixed = Object.entries(u.fields).filter(([, v]) => fx(v)).map(([k]) => k); // 120차
    if (fixed.length) tr._fixed = fixed;
    u.obj.translations = tr;
  }
  return true;
}

// Google Cloud Translation 기본(v2) — getAccessToken: 함수 서비스 계정 토큰
function createGoogleTranslator({ getAccessToken, fetchImpl = globalThis.fetch }) {
  return async (texts, target) => {
    const token = await getAccessToken();
    const out = [];
    for (let i = 0; i < texts.length; i += 100) {
      const chunk = texts.slice(i, i + 100);
      const res = await fetchImpl('https://translation.googleapis.com/language/translate/v2', {
        method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json; charset=utf-8' },
        body: JSON.stringify({ q: chunk, source: 'ko', target, format: 'text' }),
      });
      const text = await res.text();
      if (!res.ok) {
        const disabled = /SERVICE_DISABLED|has not been used|is disabled/i.test(text);
        const err = new Error(disabled
          ? 'Cloud Translation API가 꺼져 있어요. (운영자: Google Cloud 콘솔에서 켜기)'
          : `번역 API 오류 (${res.status})`);
        err.detail = text.slice(0, 500);
        throw err;
      }
      const list = (JSON.parse(text).data || {}).translations || [];
      if (list.length !== chunk.length) throw new Error('번역 결과 개수가 맞지 않아요.');
      out.push(...list.map((t) => String(t.translatedText || '')));
    }
    return out;
  };
}

// translator: async (texts[], target) => texts[] (없으면 503)
function createTranslateRoutes({ data, translator = null, httpError }) {
  // 120차: 고정 번역(고침표·GLOSSARY)이 있는 언어는 구글에 안 보냄 → { cache, chars }
  async function translateAll(texts, fx = glossaryOf) {
    const all = [...new Set(texts)];
    const cache = new Map(all.map((t) => [t, { ...(fx(t) || {}) }]));
    let chars = 0;
    for (const [code, target] of LANGS) {
      const need = all.filter((t) => !cache.get(t)[code]);
      if (!need.length) continue;
      const out = await translator(need, target);
      need.forEach((t, i) => { cache.get(t)[code] = out[i]; });
      chars += need.reduce((n, t) => n + t.length, 0);
    }
    return { cache, chars };
  }

  async function syncStore(storeId) {
    const fx = makeFixed(data.getOverrides ? await data.getOverrides(storeId) : []); // 120차: 매장 고침표
    const menus = await data.listMenus(storeId);
    const docs = {};
    for (const id of ['notices', 'events']) docs[id] = await data.getItems(storeId, id);

    const catDoc = data.getCategories ? await data.getCategories(storeId) : null;
    const catPlan = catDoc ? planCategories(catDoc, fx) : null;

    const texts = [];
    if (catPlan) texts.push(...catPlan.need);
    for (const m of menus) texts.push(...textsOf(planMenu(m, fx).units));
    for (const id of Object.keys(docs)) if (docs[id]) texts.push(...textsOf(planItems(docs[id], fx).units));
    const { cache, chars } = await translateAll(texts, fx);

    let categories = 0;
    if (catPlan && catPlan.changed) {
      const wrote = await data.updateCategories(storeId, (fresh) => {
        const p = planCategories(fresh, fx);
        return p.changed ? applyCategories(p, cache, fx) : null;
      });
      if (wrote) categories = 1;
    }

    let menuCount = 0;
    for (const m of menus) {
      if (!planMenu(m, fx).units.length) continue;
      // 저장 직전에 다시 읽어서(트랜잭션) 그사이 관리자가 고친 내용을 덮지 않음 — 원문이 바뀌었으면 다음 번에
      const wrote = await data.updateMenu(storeId, m.id, (fresh) => {
        const p = planMenu(fresh, fx);
        if (!p.units.length || !applyUnits(p.units, cache, fx)) return null;
        const patch = { translations: p.doc.translations === undefined ? null : p.doc.translations };
        if (p.doc.optionGroups !== undefined) patch.optionGroups = p.doc.optionGroups;
        return patch;
      });
      if (wrote) menuCount++;
    }
    const counts = {};
    for (const id of Object.keys(docs)) {
      counts[id] = 0;
      if (!docs[id] || !planItems(docs[id], fx).units.length) continue;
      const wrote = await data.updateItems(storeId, id, (fresh) => {
        const p = planItems(fresh, fx);
        if (!p.units.length || !applyUnits(p.units, cache, fx)) return null;
        return p.items;
      });
      if (wrote) counts[id] = 1;
    }
    return { ok: true, menus: menuCount, notices: counts.notices, events: counts.events, categories, chars };
  }

  async function route(req, path, ctx) {
    if (path === '/api/translate/sync' && req.method === 'POST') {
      const user = await ctx.requireAdmin(req);
      ctx.rate(`translate:${user.store}`, 20, 60 * 1000, '번역 요청');
      if (!translator) throw httpError(503, 'NO_TRANSLATE', '자동 번역이 서버에 연결되지 않았어요.');
      try {
        return await syncStore(user.store);
      } catch (e) {
        if (e && e.status) throw e;
        console.error('[번역] 실패', user.store, e && e.message, e && e.detail);
        throw httpError(502, 'TRANSLATE_FAILED', (e && e.message) || '번역하지 못했어요.');
      }
    }
    throw httpError(404, 'NOT_FOUND', '없는 주소예요.');
  }

  return { route, syncStore };
}

// Firestore 저장소 — updateMenu/updateItems의 mutator(fresh)가 null이면 안 씀
function createFirestoreTranslateData(db) {
  const { FieldValue } = require('firebase-admin/firestore');
  const store = (id) => db.collection('stores').doc(id);
  return {
    async listMenus(s) {
      const snap = await store(s).collection('menus').get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },
    async getItems(s, docId) {
      const d = await store(s).collection('settings').doc(docId).get();
      return d.exists ? d.data().items || [] : null;
    },
    async getCategories(s) {
      const d = await store(s).collection('settings').doc('categories').get();
      return d.exists ? d.data() : null;
    },
    // 120차: 매장 번역 고침표 (관리자 웹 '번역 관리')
    async getOverrides(s) {
      const d = await store(s).collection('settings').doc('translationOverrides').get();
      return d.exists && Array.isArray(d.data().items) ? d.data().items : [];
    },
    // mutator(fresh) → translations 또는 null. list는 건드리지 않음(관리자가 그사이 바꾼 순서 유지)
    async updateCategories(s, mutator) {
      const ref = store(s).collection('settings').doc('categories');
      return db.runTransaction(async (tx) => {
        const d = await tx.get(ref);
        if (!d.exists) return false;
        const translations = mutator(d.data());
        if (!translations) return false;
        tx.update(ref, { translations });
        return true;
      });
    },
    async updateMenu(s, id, mutator) {
      const ref = store(s).collection('menus').doc(id);
      return db.runTransaction(async (tx) => {
        const d = await tx.get(ref);
        if (!d.exists) return false;
        const patch = mutator(d.data());
        if (!patch) return false;
        const update = { ...patch };
        if (update.translations === null) update.translations = FieldValue.delete();
        tx.update(ref, update);
        return true;
      });
    },
    async updateItems(s, docId, mutator) {
      const ref = store(s).collection('settings').doc(docId);
      return db.runTransaction(async (tx) => {
        const d = await tx.get(ref);
        if (!d.exists) return false;
        const items = mutator(d.data().items || []);
        if (!items) return false;
        tx.update(ref, { items });
        return true;
      });
    },
  };
}

// 테스트용 메모리 저장소
function createMemoryTranslateData({ menus = {}, settings = {} } = {}) {
  const m = JSON.parse(JSON.stringify(menus)); // { store: { id: menu } }
  const st = JSON.parse(JSON.stringify(settings)); // { store: { notices: [...], events: [...] } }
  return {
    menus: m, settings: st,
    async listMenus(s) {
      return Object.entries(m[s] || {}).map(([id, v]) => ({ id, ...JSON.parse(JSON.stringify(v)) }));
    },
    async getItems(s, docId) {
      const v = (st[s] || {})[docId];
      return v === undefined ? null : JSON.parse(JSON.stringify(v));
    },
    async updateMenu(s, id, mutator) {
      const cur = (m[s] || {})[id];
      if (!cur) return false;
      const patch = mutator(JSON.parse(JSON.stringify(cur)));
      if (!patch) return false;
      for (const [k, v] of Object.entries(patch)) {
        if (v === null) delete cur[k];
        else cur[k] = v;
      }
      return true;
    },
    async getOverrides(s) {
      const v = (st[s] || {}).translationOverrides;
      return Array.isArray(v) ? JSON.parse(JSON.stringify(v)) : [];
    },
    async getCategories(s) {
      const v = (st[s] || {}).categories;
      return v === undefined ? null : JSON.parse(JSON.stringify(v));
    },
    async updateCategories(s, mutator) {
      const cur = (st[s] || {}).categories;
      if (cur === undefined) return false;
      const translations = mutator(JSON.parse(JSON.stringify(cur)));
      if (!translations) return false;
      cur.translations = translations;
      return true;
    },
    async updateItems(s, docId, mutator) {
      const cur = (st[s] || {})[docId];
      if (cur === undefined) return false;
      const items = mutator(JSON.parse(JSON.stringify(cur)));
      if (!items) return false;
      st[s][docId] = items;
      return true;
    },
  };
}

module.exports = {
  createTranslateRoutes, createGoogleTranslator, createFirestoreTranslateData, createMemoryTranslateData,
  planMenu, planItems, planCategories, LANGS, GLOSSARY, makeFixed, MAX_OVERRIDES,
};
