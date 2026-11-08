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
//   사장님이 번역을 직접 고치는 화면은 아직 없음(남은 일).

const LANGS = [['en', 'en'], ['zh', 'zh-CN'], ['ja', 'ja']];
const clean = (s) => (typeof s === 'string' ? s.trim() : '');
const srcOf = (fields) => JSON.stringify(fields);

// 번역할 칸 하나 묶음(unit): { obj(새로 만든 사본 — 여기에 translations를 씀), fields: { 칸: 원문 } }
function addUnit(units, obj, raw) {
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
  if (!(t && typeof t === 'object' && t._src === srcOf(fields))) units.push({ obj, fields });
}

// 메뉴 문서 → { patch 재료(사본), units }
function planMenu(menu) {
  const doc = { translations: menu.translations };
  const units = [];
  addUnit(units, doc, { name: menu.name });
  if (Array.isArray(menu.optionGroups)) {
    doc.optionGroups = menu.optionGroups.map((g) => {
      if (!g || typeof g !== 'object') return g;
      const ng = { ...g };
      addUnit(units, ng, { groupName: g.groupName });
      if (Array.isArray(g.options)) {
        ng.options = g.options.map((o) => {
          if (!o || typeof o !== 'object') return o;
          const no = { ...o };
          addUnit(units, no, { name: o.name });
          return no;
        });
      }
      return ng;
    });
  }
  return { doc, units };
}

// 공지·이벤트 items → { items(사본), units }
function planItems(items) {
  const units = [];
  const list = (Array.isArray(items) ? items : []).map((it) => {
    if (!it || typeof it !== 'object') return it;
    const ni = { ...it };
    addUnit(units, ni, it.type === 'image' ? { title: it.title } : { title: it.title, content: it.content });
    return ni;
  });
  return { items: list, units };
}

const textsOf = (units) => units.filter((u) => !u.removeOnly).flatMap((u) => Object.values(u.fields));

// cache: Map 원문 → { en, zh, ja }. 하나라도 없으면 false(쓰지 않음)
function applyUnits(units, cache) {
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
  async function translateAll(texts) {
    const uniq = [...new Set(texts)];
    const cache = new Map(uniq.map((t) => [t, {}]));
    if (!uniq.length) return cache;
    for (const [code, target] of LANGS) {
      const out = await translator(uniq, target);
      uniq.forEach((t, i) => { cache.get(t)[code] = out[i]; });
    }
    return cache;
  }

  async function syncStore(storeId) {
    const menus = await data.listMenus(storeId);
    const docs = {};
    for (const id of ['notices', 'events']) docs[id] = await data.getItems(storeId, id);

    const texts = [];
    for (const m of menus) texts.push(...textsOf(planMenu(m).units));
    for (const id of Object.keys(docs)) if (docs[id]) texts.push(...textsOf(planItems(docs[id]).units));
    const cache = await translateAll(texts);
    const chars = [...cache.keys()].reduce((n, t) => n + t.length, 0) * LANGS.length;

    let menuCount = 0;
    for (const m of menus) {
      if (!planMenu(m).units.length) continue;
      // 저장 직전에 다시 읽어서(트랜잭션) 그사이 관리자가 고친 내용을 덮지 않음 — 원문이 바뀌었으면 다음 번에
      const wrote = await data.updateMenu(storeId, m.id, (fresh) => {
        const p = planMenu(fresh);
        if (!p.units.length || !applyUnits(p.units, cache)) return null;
        const patch = { translations: p.doc.translations === undefined ? null : p.doc.translations };
        if (p.doc.optionGroups !== undefined) patch.optionGroups = p.doc.optionGroups;
        return patch;
      });
      if (wrote) menuCount++;
    }
    const counts = {};
    for (const id of Object.keys(docs)) {
      counts[id] = 0;
      if (!docs[id] || !planItems(docs[id]).units.length) continue;
      const wrote = await data.updateItems(storeId, id, (fresh) => {
        const p = planItems(fresh);
        if (!p.units.length || !applyUnits(p.units, cache)) return null;
        return p.items;
      });
      if (wrote) counts[id] = 1;
    }
    return { ok: true, menus: menuCount, notices: counts.notices, events: counts.events, chars };
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
  planMenu, planItems, LANGS,
};
