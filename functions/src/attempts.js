'use strict';
// 관리자 로그인(PIN/비밀번호) 실패 횟수 기록. 무차별 대입을 막기 위해 서버 인스턴스가 여러 개여도
// 같이 보이도록 Firestore(_authLimits 컬렉션)에 저장한다. 이 컬렉션은 보안 규칙상 앱에서 읽고 쓸 수 없고
// 서버(Admin SDK)만 접근한다.
//
// 공통 모양: { isLocked(key, max, windowMs), recordFail(key, windowMs), reset(key) }

// 테스트·로컬용: 메모리에만 저장
function createMemoryAttempts(now = () => Date.now()) {
  const store = new Map();
  const recent = (key, windowMs) => (store.get(key) || []).filter((t) => now() - t < windowMs);
  return {
    async isLocked(key, max, windowMs) {
      return recent(key, windowMs).length >= max;
    },
    async recordFail(key, windowMs) {
      const list = recent(key, windowMs);
      list.push(now());
      store.set(key, list);
    },
    async reset(key) {
      store.delete(key);
    },
  };
}

const MAX_KEEP = 100; // 문서 하나에 보관하는 실패 기록 최대 개수

function docId(key) {
  // Firestore 문서 ID에 '/'를 쓸 수 없어서 바꿈
  return String(key).replace(/[^A-Za-z0-9:._-]/g, '_').slice(0, 200) || 'unknown';
}

function createFirestoreAttempts(db, now = () => Date.now()) {
  const col = db.collection('_authLimits');
  return {
    async isLocked(key, max, windowMs) {
      const snap = await col.doc(docId(key)).get();
      const fails = (snap.exists && Array.isArray(snap.get('fails'))) ? snap.get('fails') : [];
      return fails.filter((t) => now() - t < windowMs).length >= max;
    },
    async recordFail(key, windowMs) {
      const ref = col.doc(docId(key));
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const fails = (snap.exists && Array.isArray(snap.get('fails'))) ? snap.get('fails') : [];
        const kept = fails.filter((t) => now() - t < windowMs).slice(-(MAX_KEEP - 1));
        kept.push(now());
        tx.set(ref, { fails: kept });
      });
    },
    async reset(key) {
      await col.doc(docId(key)).delete();
    },
  };
}

module.exports = { createMemoryAttempts, createFirestoreAttempts };
