'use strict';
// Firebase Cloud Functions 진입점. Hosting이 "/api/**" 요청을 이 함수(api)로 넘겨 준다. (firebase.json)
// 배포 전에 BGG 비밀값 3개를 등록해야 한다 — 보드패드 폴더의 "BGG 비밀값 등록.ps1" 참고.
//   BGG_APPS_SCRIPT_URL : BGG 중계용 Google Apps Script 주소 (월정액권 앱과 같은 것)
//   BGG_RELAY_SECRET    : 그 중계의 비밀키
//   BGG_APP_TOKEN       : BGG API 토큰 (중계를 못 쓸 때 직접 호출용)
const { onRequest } = require('firebase-functions/https');
const { defineSecret } = require('firebase-functions/params');

const BGG_APP_TOKEN = defineSecret('BGG_APP_TOKEN');
const BGG_RELAY_SECRET = defineSecret('BGG_RELAY_SECRET');
const BGG_APPS_SCRIPT_URL = defineSecret('BGG_APPS_SCRIPT_URL');

let handle = null;
function getHandle() {
  if (handle) return handle;
  const { initializeApp } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  const { createBggClient } = require('./src/bgg-client');
  const { createHandler } = require('./src/app');

  initializeApp();
  const db = getFirestore();
  const url = (BGG_APPS_SCRIPT_URL.value() || '').trim();
  const secret = (BGG_RELAY_SECRET.value() || '').trim();

  handle = createHandler({
    bgg: createBggClient({
      token: (BGG_APP_TOKEN.value() || '').trim(),
      relay: url && secret ? { resolve: async () => ({ url, secret, transport: 'appsscript' }) } : undefined,
    }),
    getAdminPassword: async () => {
      const doc = await db.collection('settings').doc('adminPin').get();
      const d = doc.data() || {};
      return String(d.webPassword || d.pin || '');
    },
  });
  return handle;
}

exports.api = onRequest(
  {
    region: 'asia-northeast3', // 서울
    secrets: [BGG_APP_TOKEN, BGG_RELAY_SECRET, BGG_APPS_SCRIPT_URL],
    maxInstances: 3, // 요청 폭주 시 비용 상한
    timeoutSeconds: 120, // BGG 중계가 느릴 때 재시도까지 기다릴 수 있게
    memory: '256MiB',
  },
  async (req, res) => {
    const headers = {};
    for (const [k, v] of Object.entries(req.headers || {})) headers[k.toLowerCase()] = Array.isArray(v) ? v[0] : v;
    const out = await getHandle()({
      method: req.method,
      path: req.path,
      query: req.query || {},
      headers,
      body: req.body,
    });
    res.status(out.status);
    for (const [k, v] of Object.entries(out.headers || {})) res.set(k, v);
    if (out.body == null) res.end();
    else res.json(out.body);
  }
);
