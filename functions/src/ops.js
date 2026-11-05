'use strict';
// 운영자(나) 계정 + Google Cloud 프로젝트 전체 사용량 (48차)
//
// 운영자 계정: Firestore _ops/account { password(처음엔 콘솔에서 글자로) | passwordHash }
//   _ops 컬렉션은 보안 규칙상 앱에서 읽고 쓸 수 없음 (서버만)
// 운영자 토큰: uid 'ops', { ops: true } — 매장 데이터에는 직접 못 들어가고 /api/ops/* 로만 일함
//
// 프로젝트 전체 사용량: Cloud Monitoring API (monitoring.googleapis.com) — Firestore 읽기·쓰기·삭제,
// 서버 함수(api) 요청 수, Firebase Storage 내보낸 데이터. 하루 단위(UTC). 매장별로는 안 나뉨.
// 함수 서비스 계정 권한(기본 Compute 서비스 계정 = 편집자)으로 읽음. API가 꺼져 있으면 오류 문구로 알려 줌.

function createFirestoreOps(db) {
  const ref = db.collection('_ops').doc('account');
  return {
    async getAccount() {
      const doc = await ref.get();
      return doc.exists ? doc.data() : null;
    },
    async setPasswordHash(passwordHash) {
      const { FieldValue } = require('firebase-admin/firestore');
      await ref.set({ passwordHash, password: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    },
  };
}

function createMemoryOps(account = null) {
  const state = { account };
  return {
    state,
    async getAccount() {
      return state.account;
    },
    async setPasswordHash(passwordHash) {
      state.account = { passwordHash };
    },
  };
}

const METRICS = [
  { key: 'firestoreReads', type: 'firestore.googleapis.com/document/read_count' },
  { key: 'firestoreWrites', type: 'firestore.googleapis.com/document/write_count' },
  { key: 'firestoreDeletes', type: 'firestore.googleapis.com/document/delete_count' },
  // 2세대 서버 함수는 Cloud Run 서비스 'api'
  { key: 'functionRequests', type: 'run.googleapis.com/request_count', extra: 'resource.labels.service_name="api"' },
  { key: 'storageSentBytes', type: 'storage.googleapis.com/network/sent_bytes_count' },
];

// getAccessToken: async () => 'ya29...'   fetchImpl: fetch
function createMonitoring({ projectId, getAccessToken, fetchImpl = fetch, now = () => Date.now() }) {
  async function series(metric, days, token) {
    const end = new Date(now());
    const start = new Date(now() - days * 86400 * 1000);
    const filter = `metric.type="${metric.type}"${metric.extra ? ` AND ${metric.extra}` : ''}`;
    const params = new URLSearchParams({
      filter,
      'interval.startTime': start.toISOString(),
      'interval.endTime': end.toISOString(),
      'aggregation.alignmentPeriod': '86400s',
      'aggregation.perSeriesAligner': 'ALIGN_SUM',
      'aggregation.crossSeriesReducer': 'REDUCE_SUM',
      view: 'FULL',
    });
    const url = `https://monitoring.googleapis.com/v3/projects/${encodeURIComponent(projectId)}/timeSeries?${params}`;
    const res = await fetchImpl(url, { headers: { authorization: `Bearer ${token}` } });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = (body && body.error && body.error.message) || `HTTP ${res.status}`;
      const e = new Error(msg);
      e.status = res.status;
      throw e;
    }
    const byDay = {};
    for (const ts of body.timeSeries || []) {
      for (const p of ts.points || []) {
        const day = String((p.interval && (p.interval.endTime || p.interval.startTime)) || '').slice(0, 10);
        const v = p.value || {};
        const n = Number(v.int64Value != null ? v.int64Value : v.doubleValue || 0);
        if (day) byDay[day] = (byDay[day] || 0) + (Number.isFinite(n) ? n : 0);
      }
    }
    return byDay;
  }

  return {
    // -> { days: [{ date, firestoreReads, ... }], totals: {...}, errors: { key: 문구 } }
    async summary(days) {
      const token = await getAccessToken();
      const results = await Promise.allSettled(METRICS.map((m) => series(m, days, token)));
      const dayMap = new Map();
      const totals = {};
      const errors = {};
      results.forEach((r, i) => {
        const key = METRICS[i].key;
        if (r.status === 'rejected') {
          const msg = String((r.reason && r.reason.message) || r.reason);
          errors[key] = /has not been used|is disabled|SERVICE_DISABLED/i.test(msg)
            ? 'Cloud Monitoring API가 꺼져 있어요. 콘솔에서 켜 주세요: https://console.cloud.google.com/apis/library/monitoring.googleapis.com'
            : msg.slice(0, 200);
          return;
        }
        totals[key] = 0;
        for (const [date, n] of Object.entries(r.value)) {
          const d = dayMap.get(date) || { date };
          d[key] = n;
          dayMap.set(date, d);
          totals[key] += n;
        }
      });
      return { days: [...dayMap.values()].sort((a, b) => a.date.localeCompare(b.date)), totals, errors };
    },
  };
}

module.exports = { createFirestoreOps, createMemoryOps, createMonitoring, METRICS };
