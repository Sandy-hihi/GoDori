'use strict';
// p6-import.js가 쓰는 저장소 — 실제 Firestore/Storage (firebase-admin) 구현
const crypto = require('crypto');
const { Timestamp } = require('firebase-admin/firestore');

function createImportStore(db, bucket) {
  return {
    // 기존 게임을 백업 컬렉션으로 복사한 뒤 games를 비움 (사진 파일은 그대로 둠)
    async backupAndClearGames(backupName) {
      const snap = await db.collection('games').get();
      const docs = snap.docs;
      for (let i = 0; i < docs.length; i += 200) {
        const w = db.batch();
        for (const d of docs.slice(i, i + 200)) w.set(db.collection(backupName).doc(d.id), d.data());
        await w.commit();
      }
      for (let i = 0; i < docs.length; i += 400) {
        const w = db.batch();
        for (const d of docs.slice(i, i + 400)) w.delete(d.ref);
        await w.commit();
      }
      await db.collection('settings').doc('importLog').set(
        { lastBackup: backupName, lastBackupCount: docs.length, lastBackupAt: Timestamp.now() },
        { merge: true }
      );
      return { backedUp: docs.length };
    },
    async setGenres(list) {
      await db.collection('settings').doc('genres').set({ items: list });
    },
    async putGame(id, data) {
      const out = { ...data };
      for (const k of ['timestamp', 'pickedAt']) if (out[k] instanceof Date) out[k] = Timestamp.fromDate(out[k]);
      await db.collection('games').doc(id).set(out);
    },
    // Storage에 올리고, 앱(getDownloadURL)과 같은 형태의 다운로드 주소를 만들어 돌려줌
    async saveImage(path, buffer, contentType) {
      const token = crypto.randomUUID();
      await bucket.file(path).save(buffer, {
        resumable: false,
        contentType,
        metadata: { contentType, metadata: { firebaseStorageDownloadTokens: token } },
      });
      return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
    },
  };
}

// 월정액권 앱 주소에서 데이터를 받는 fetcher
const fetcher = {
  async json(url) {
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new Error(`월정액권 앱 응답 ${res.status}`);
    return res.json();
  },
  async binary(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`사진 응답 ${res.status}`);
    const contentType = String(res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
    return { buffer: Buffer.from(await res.arrayBuffer()), contentType };
  },
};

module.exports = { createImportStore, fetcher };
