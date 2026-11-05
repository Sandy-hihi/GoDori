'use strict';
// 매장 계정 (47차) — 여러 매장이 각자 데이터·설정을 갖는 구조
//
// Firestore
//   stores/{storeId}                    { name, status, createdAt }    매장 기본 정보 (누구나 읽기)
//        status: 'pending'(가입 승인 대기) | 'active'(운영 중, 없으면 이걸로 봄) | 'suspended'(정지) | 'rejected'(거절)
//   stores/{storeId}/private/account    { padPassword(Hash), pin(Hash), webPassword(Hash) }  서버만 읽음
//   stores/{storeId}/private/profile    { ownerName, phone, signedUpAt, approvedAt, ... }    가입 정보 (서버만)
//   stores/{storeId}/private/usage      { r2Bytes, r2Files }   룰 영상 저장 용량 (서버만)
//   stores/{storeId}/usageDaily/{날짜}   { date, logins, videoPlays, videoBytesEst, videoUploads, videoUploadBytes,
//                                         bggCalls, aiCalls, clientReads }   하루 이용량 (서버만, 운영자 페이지가 봄)
//   stores/{storeId}/games, menus, orders, staff_calls, settings, videoStats, videoStatsDaily
//
// 매장 아이디 = 로그인 아이디. 영어 소문자·숫자·'-' 3~30자 (예: platform6)
// 비밀번호 3가지
//   padPassword  손님 패드 로그인 (아이디 + 비밀번호 + 방 번호)
//   pin          방 번호 0으로 로그인할 때 한 번 더 묻는 관리자 PIN (숫자)
//   webPassword  관리자 웹 (없으면 pin)
// 콘솔에서 새 매장을 만들 땐 그냥 글자로 넣어도 됨(padPassword 등). 관리자 웹 '매장 설정'에서 바꾸면
// scrypt 해시(…Hash 필드)로 저장하고 글자 필드는 지움.

const crypto = require('crypto');

const STORE_ID_RE = /^[a-z0-9][a-z0-9-]{2,29}$/;
const STATUSES = ['pending', 'active', 'suspended', 'rejected'];
// 가입할 때 못 쓰는 아이디
const RESERVED_IDS = ['ops', 'admin', 'api', 'www', 'root', 'stores', 'store', 'godori', 'test', 'system', 'support', 'help'];
// 하루 이용량에 기록하는 칸 (이 밖의 이름은 무시)
const USAGE_FIELDS = ['logins', 'videoPlays', 'videoBytesEst', 'videoUploads', 'videoUploadBytes', 'bggCalls', 'aiCalls', 'clientReads'];

function seoulDateKey(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(date);
}

function statusOf(account) {
  const s = account && account.status;
  return STATUSES.includes(s) ? s : 'active';
}

// 로그인 막을 때 문구 (비밀번호가 맞은 뒤에만 보여 줌)
function statusError(status) {
  if (status === 'pending') return httpError(403, 'PENDING', '가입 승인을 기다리고 있어요. 승인되면 로그인할 수 있어요.');
  if (status === 'rejected') return httpError(403, 'REJECTED', '가입이 승인되지 않았어요. 운영자에게 문의해 주세요.');
  if (status === 'suspended') return httpError(403, 'SUSPENDED', '이용이 정지된 매장이에요. 운영자에게 문의해 주세요.');
  return null;
}
const MAX_ROOMS = 30; // firestore.rules·앱(RoomSettingsService.maxCount)과 같아야 함
const DEFAULT_ROOMS = 11;

function httpError(status, code, message) {
  const e = new Error(message);
  e.status = status;
  e.code = code;
  return e;
}

function cleanStoreId(v) {
  const id = String(v == null ? '' : v).trim().toLowerCase();
  if (!STORE_ID_RE.test(id)) {
    throw httpError(400, 'INVALID_STORE_ID', '매장 아이디는 영어 소문자·숫자·-로 3~30자예요.');
  }
  return id;
}

function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

const SCRYPT = { N: 16384, r: 8, p: 1 };

function hashSecret(plain) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(String(plain), salt, 32, SCRYPT);
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

// 저장된 값(해시 또는 글자)과 비교. 둘 다 없으면 null (설정 안 됨)
function checkSecret(given, { hash, plain }) {
  if (typeof hash === 'string' && hash.startsWith('scrypt$')) {
    const [, saltHex, hashHex] = hash.split('$');
    try {
      const want = Buffer.from(hashHex, 'hex');
      const got = crypto.scryptSync(String(given), Buffer.from(saltHex, 'hex'), want.length, SCRYPT);
      return want.length > 0 && crypto.timingSafeEqual(want, got);
    } catch (_) {
      return false;
    }
  }
  if (plain != null && String(plain) !== '') return safeEqual(given, String(plain));
  return null;
}

// account 문서에서 비밀번호 종류별로 꺼내기. kind: 'pad' | 'pin' | 'web'(없으면 pin)
function secretOf(account, kind) {
  const a = account || {};
  if (kind === 'pad') return { hash: a.padPasswordHash, plain: a.padPassword };
  if (kind === 'pin') return { hash: a.pinHash, plain: a.pin };
  const hasWeb = (a.webPasswordHash || '') !== '' || (a.webPassword != null && String(a.webPassword) !== '');
  return hasWeb ? { hash: a.webPasswordHash, plain: a.webPassword } : { hash: a.pinHash, plain: a.pin };
}

function parseRoomCount(data) {
  const v = data && data.count;
  const n = typeof v === 'number' ? Math.trunc(v) : parseInt(v, 10);
  return Number.isFinite(n) && n >= 1 && n <= MAX_ROOMS ? n : DEFAULT_ROOMS;
}

// 예전(매장 1곳) 구조에서 옮길 컬렉션
const LEGACY_COLLECTIONS = ['games', 'menus', 'orders', 'staff_calls', 'videoStats', 'videoStatsDaily', 'settings'];

function cleanUsage(fields) {
  const out = {};
  for (const k of USAGE_FIELDS) {
    const n = Number(fields && fields[k]);
    if (Number.isFinite(n) && n !== 0) out[k] = Math.round(n);
  }
  return out;
}

// Firestore용 저장소 (index.js에서 db를 넘김)
function createFirestoreStores(db) {
  const { FieldValue, Timestamp } = require('firebase-admin/firestore');
  const storeRef = (id) => db.collection('stores').doc(id);
  const priv = (id, doc) => storeRef(id).collection('private').doc(doc);
  const iso = (v) => (v && typeof v.toDate === 'function' ? v.toDate().toISOString() : null);
  return {
    async getAccount(storeId) {
      const [store, acc] = await Promise.all([storeRef(storeId).get(), priv(storeId, 'account').get()]);
      if (!store.exists) return null;
      return { ...(acc.exists ? acc.data() : {}), name: String(store.get('name') || ''), status: statusOf(store.data()) };
    },
    async getStatus(storeId) {
      const store = await storeRef(storeId).get();
      return store.exists ? statusOf(store.data()) : null;
    },
    // 가입 신청: 아이디가 비어 있을 때만 만듦 (동시에 같은 아이디로 신청해도 하나만)
    async createSignup({ storeId, name, profile, account }) {
      await db.runTransaction(async (tx) => {
        const ref = storeRef(storeId);
        if ((await tx.get(ref)).exists) throw httpError(409, 'ID_TAKEN', '이미 쓰고 있는 매장 아이디예요. 다른 아이디를 골라 주세요.');
        tx.set(ref, { name, status: 'pending', createdAt: FieldValue.serverTimestamp() });
        tx.set(priv(storeId, 'account'), { ...account, updatedAt: FieldValue.serverTimestamp() });
        tx.set(priv(storeId, 'profile'), { ...profile, signedUpAt: FieldValue.serverTimestamp() });
      });
    },
    async exists(storeId) {
      return (await storeRef(storeId).get()).exists;
    },
    // 운영자 페이지: 전체 매장 (매장마다 문서 3개 읽음)
    async listStores() {
      const snap = await db.collection('stores').get();
      return Promise.all(snap.docs.map(async (d) => {
        const [profile, usage] = await Promise.all([priv(d.id, 'profile').get(), priv(d.id, 'usage').get()]);
        const p = profile.exists ? profile.data() : {};
        const u = usage.exists ? usage.data() : {};
        return {
          id: d.id,
          name: String(d.get('name') || ''),
          status: statusOf(d.data()),
          createdAt: iso(d.get('createdAt')),
          migratedFromLegacy: d.get('migratedFromLegacy') === true,
          ownerName: String(p.ownerName || ''),
          phone: String(p.phone || ''),
          signedUpAt: iso(p.signedUpAt),
          statusChangedAt: iso(p.statusChangedAt),
          r2Bytes: Number(u.r2Bytes || 0),
          r2Files: Number(u.r2Files || 0),
        };
      }));
    },
    async setStatus(storeId, status) {
      const ref = storeRef(storeId);
      if (!(await ref.get()).exists) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      const batch = db.batch();
      batch.update(ref, { status });
      batch.set(priv(storeId, 'profile'), { statusChangedAt: FieldValue.serverTimestamp(), ...(status === 'active' ? { approvedAt: FieldValue.serverTimestamp() } : {}) }, { merge: true });
      await batch.commit();
    },
    // 승인 대기·거절된 매장만 지움 (운영한 적 있는 매장의 데이터는 지우지 않음)
    async deleteSignup(storeId) {
      const ref = storeRef(storeId);
      const doc = await ref.get();
      if (!doc.exists) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      if (!['pending', 'rejected'].includes(statusOf(doc.data()))) {
        throw httpError(409, 'NOT_DELETABLE', '승인 대기·거절된 매장만 지울 수 있어요. 운영 중인 매장은 먼저 정지하세요.');
      }
      const batch = db.batch();
      for (const name of ['account', 'profile', 'usage']) batch.delete(priv(storeId, name));
      batch.delete(ref);
      await batch.commit();
    },
    // 하루 이용량 더하기 (실패해도 요청은 계속 — 부르는 쪽에서 catch)
    async recordUsage(storeId, fields) {
      const inc = cleanUsage(fields);
      if (!Object.keys(inc).length) return;
      const date = seoulDateKey();
      const data = { date };
      for (const [k, v] of Object.entries(inc)) data[k] = FieldValue.increment(v);
      await storeRef(storeId).collection('usageDaily').doc(date).set(data, { merge: true });
    },
    async usageSince(storeId, fromDate) {
      const snap = await storeRef(storeId).collection('usageDaily').where('date', '>=', fromDate).get();
      return snap.docs.map((d) => d.data());
    },
    async addR2Usage(storeId, bytes, files) {
      await priv(storeId, 'usage').set({ r2Bytes: FieldValue.increment(bytes), r2Files: FieldValue.increment(files) }, { merge: true });
    },
    // 룰 영상 저장 용량 다시 세기 (게임 문서를 전부 읽음 — 운영자가 버튼으로만)
    async recountR2(storeId) {
      const snap = await storeRef(storeId).collection('games').get();
      let bytes = 0;
      let files = 0;
      for (const d of snap.docs) {
        const rv = d.get('ruleVideo') || {};
        for (const q of ['q1080', 'q720']) {
          if (rv[q] && rv[q].key) {
            files++;
            bytes += Number(rv[q].sizeBytes || 0);
          }
        }
      }
      await priv(storeId, 'usage').set({ r2Bytes: bytes, r2Files: files, recountedAt: Timestamp.now() });
      return { r2Bytes: bytes, r2Files: files, games: snap.size };
    },
    async getRoomCount(storeId) {
      const doc = await storeRef(storeId).collection('settings').doc('rooms').get();
      return parseRoomCount(doc.exists ? doc.data() : null);
    },
    // fields: { padPasswordHash?, pinHash?, webPasswordHash? } — 같은 종류의 글자 필드는 지움
    async setSecrets(storeId, fields) {
      const update = { updatedAt: FieldValue.serverTimestamp() };
      for (const [k, v] of Object.entries(fields)) {
        update[k] = v;
        update[k.replace(/Hash$/, '')] = FieldValue.delete();
      }
      await storeRef(storeId).collection('private').doc('account').set(update, { merge: true });
    },
    // 예전 데이터(맨 위 컬렉션)를 stores/{storeId}/… 로 복사. 원본은 그대로 둠(백업)
    async migrateLegacy({ storeId, name, account }) {
      const ref = storeRef(storeId);
      // 한 번만: 이미 옮긴 매장이 있으면 막음 (예전 비밀번호로 가짜 매장을 더 만들지 못하게)
      const done = await db.collection('stores').where('migratedFromLegacy', '==', true).limit(1).get();
      if (!done.empty) throw httpError(409, 'ALREADY_MIGRATED', `이미 옮겼어요. (매장 아이디 ${done.docs[0].id})`);
      if ((await ref.get()).exists) throw httpError(409, 'STORE_EXISTS', '이미 있는 매장 아이디예요.');
      const counts = {};
      let batch = db.batch();
      let n = 0;
      const flush = async () => {
        if (n > 0) await batch.commit();
        batch = db.batch();
        n = 0;
      };
      for (const col of LEGACY_COLLECTIONS) {
        const snap = await db.collection(col).get();
        counts[col] = 0;
        for (const doc of snap.docs) {
          if (col === 'settings' && doc.id === 'adminPin') continue; // 비밀번호는 private/account로
          batch.set(ref.collection(col).doc(doc.id), doc.data());
          counts[col]++;
          if (++n >= 400) await flush();
        }
      }
      batch.set(ref.collection('private').doc('account'), { ...account, updatedAt: FieldValue.serverTimestamp() });
      batch.set(ref, { name, status: 'active', createdAt: FieldValue.serverTimestamp(), migratedFromLegacy: true });
      n += 2;
      await flush();
      return counts;
    },
  };
}

// 테스트용: 메모리 저장소
function createMemoryStores(initial = {}) {
  const stores = new Map(Object.entries(initial).map(([k, v]) => [k, { rooms: DEFAULT_ROOMS, ...v }]));
  const usage = []; // [storeId, date, fields]
  return {
    stores,
    usage,
    async getAccount(id) {
      const s = stores.get(id);
      return s ? { ...(s.account || {}), name: s.name || '', status: statusOf(s) } : null;
    },
    async getStatus(id) {
      const s = stores.get(id);
      return s ? statusOf(s) : null;
    },
    async createSignup({ storeId, name, profile, account }) {
      if (stores.has(storeId)) throw httpError(409, 'ID_TAKEN', '이미 쓰고 있는 매장 아이디예요. 다른 아이디를 골라 주세요.');
      stores.set(storeId, { name, status: 'pending', account, profile, rooms: DEFAULT_ROOMS });
    },
    async exists(id) {
      return stores.has(id);
    },
    async listStores() {
      return [...stores.entries()].map(([id, s]) => ({
        id, name: s.name || '', status: statusOf(s), ownerName: (s.profile || {}).ownerName || '',
        phone: (s.profile || {}).phone || '', r2Bytes: s.r2Bytes || 0, r2Files: s.r2Files || 0,
      }));
    },
    async setStatus(id, status) {
      if (!stores.has(id)) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      stores.get(id).status = status;
    },
    async deleteSignup(id) {
      const s = stores.get(id);
      if (!s) throw httpError(404, 'NO_STORE', '없는 매장이에요.');
      if (!['pending', 'rejected'].includes(statusOf(s))) throw httpError(409, 'NOT_DELETABLE', '승인 대기·거절된 매장만 지울 수 있어요.');
      stores.delete(id);
    },
    async recordUsage(id, fields) {
      const inc = cleanUsage(fields);
      if (Object.keys(inc).length) usage.push([id, seoulDateKey(), inc]);
    },
    async usageSince(id, fromDate) {
      const byDate = new Map();
      for (const [sid, date, inc] of usage) {
        if (sid !== id || date < fromDate) continue;
        const d = byDate.get(date) || { date };
        for (const [k, v] of Object.entries(inc)) d[k] = (d[k] || 0) + v;
        byDate.set(date, d);
      }
      return [...byDate.values()];
    },
    async addR2Usage(id, bytes, files) {
      const s = stores.get(id);
      s.r2Bytes = (s.r2Bytes || 0) + bytes;
      s.r2Files = (s.r2Files || 0) + files;
    },
    async recountR2(id) {
      return { r2Bytes: (stores.get(id) || {}).r2Bytes || 0, r2Files: 0, games: 0 };
    },
    async getRoomCount(id) {
      return (stores.get(id) || {}).rooms || DEFAULT_ROOMS;
    },
    async setSecrets(id, fields) {
      const s = stores.get(id);
      s.account = s.account || {};
      for (const [k, v] of Object.entries(fields)) {
        s.account[k] = v;
        delete s.account[k.replace(/Hash$/, '')];
      }
    },
    async migrateLegacy({ storeId, name, account }) {
      if ([...stores.values()].some((s) => s.migrated)) throw httpError(409, 'ALREADY_MIGRATED', '이미 옮겼어요.');
      if (stores.has(storeId)) throw httpError(409, 'STORE_EXISTS', '이미 있는 매장 아이디예요.');
      stores.set(storeId, { name, account, status: 'active', rooms: DEFAULT_ROOMS, migrated: true });
      return { games: 0 };
    },
  };
}

module.exports = {
  STORE_ID_RE,
  STATUSES,
  RESERVED_IDS,
  USAGE_FIELDS,
  seoulDateKey,
  statusOf,
  statusError,
  MAX_ROOMS,
  cleanStoreId,
  hashSecret,
  checkSecret,
  secretOf,
  parseRoomCount,
  safeEqual,
  createFirestoreStores,
  createMemoryStores,
  LEGACY_COLLECTIONS,
};
