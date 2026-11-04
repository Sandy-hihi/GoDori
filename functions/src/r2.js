'use strict';
// Cloudflare R2(룰 설명 영상 저장소) 연결.
// R2는 S3와 같은 방식(AWS 서명 버전 4)으로 부른다. 무거운 AWS SDK 대신 서명만 직접 만든다.
// (서명 결과는 @smithy/signature-v4와 같은지 확인함 — 42차 작업 기록)
//
// 버킷은 공개하지 않는다. 손님 패드·관리자 웹은 서버가 만들어 준 "임시 주소"(presigned URL)로만
// 영상을 올리고(PUT) 본다(GET). 임시 주소는 정해진 시간이 지나면 못 쓴다.
//   주소 모양: https://<계정 ID>.r2.cloudflarestorage.com/<버킷>/<파일 키>?X-Amz-...

const crypto = require('crypto');

const sha256Hex = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
const hmac = (key, s) => crypto.createHmac('sha256', key).update(s, 'utf8').digest();

// RFC 3986 방식 인코딩 (AWS 서명 규칙: A-Z a-z 0-9 - _ . ~ 만 그대로)
function encodeRfc3986(s) {
  return encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

function amzDates(date) {
  const iso = date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, ''); // 20261103T101500Z
  return { amzDate: iso, day: iso.slice(0, 8) };
}

/**
 * 임시 주소 만들기
 * @param {object} o
 * @param {'GET'|'PUT'|'HEAD'|'DELETE'} o.method
 * @param {string} o.accountId  Cloudflare 계정 ID
 * @param {string} o.bucket
 * @param {string} o.key        파일 키 (rule-videos/<게임ID>/<시각>_1080.mp4)
 * @param {string} o.accessKeyId
 * @param {string} o.secretAccessKey
 * @param {number} o.expiresIn  초 (1 ~ 604800)
 * @param {object} [o.headers]  서명에 포함할 헤더 (예: { 'content-type': 'video/mp4' }) — 올릴 때 똑같이 보내야 함
 * @param {Date}   [o.now]
 */
function presignUrl({ method, accountId, bucket, key, accessKeyId, secretAccessKey, expiresIn, headers = {}, now = new Date() }) {
  const host = `${accountId}.r2.cloudflarestorage.com`;
  const region = 'auto';
  const service = 's3';
  const { amzDate, day } = amzDates(now);
  const scope = `${day}/${region}/${service}/aws4_request`;

  const hdrs = { host };
  for (const [k, v] of Object.entries(headers)) hdrs[k.toLowerCase()] = String(v).trim();
  const headerNames = Object.keys(hdrs).sort();
  const signedHeaders = headerNames.join(';');
  const canonicalHeaders = headerNames.map((h) => `${h}:${hdrs[h]}\n`).join('');

  const canonicalUri = '/' + [bucket, ...String(key).split('/')].map(encodeRfc3986).join('/');
  const params = {
    'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
    'X-Amz-Content-Sha256': 'UNSIGNED-PAYLOAD',
    'X-Amz-Credential': `${accessKeyId}/${scope}`,
    'X-Amz-Date': amzDate,
    'X-Amz-Expires': String(Math.floor(expiresIn)),
    'X-Amz-SignedHeaders': signedHeaders,
  };
  const canonicalQuery = Object.keys(params)
    .sort()
    .map((k) => `${encodeRfc3986(k)}=${encodeRfc3986(params[k])}`)
    .join('&');

  const canonicalRequest = [method, canonicalUri, canonicalQuery, canonicalHeaders, signedHeaders, 'UNSIGNED-PAYLOAD'].join('\n');
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, sha256Hex(canonicalRequest)].join('\n');
  const kDate = hmac('AWS4' + secretAccessKey, day);
  const kSigning = hmac(hmac(hmac(kDate, region), service), 'aws4_request');
  const signature = crypto.createHmac('sha256', kSigning).update(stringToSign, 'utf8').digest('hex');

  return `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/**
 * 서버가 쓰는 R2 저장소. 설정이 비어 있으면 null (= 아직 연결 안 됨)
 * fetchImpl은 테스트에서 바꿔 끼우려고 받음
 */
function createR2Storage({ accountId, bucket, accessKeyId, secretAccessKey, fetchImpl = globalThis.fetch }) {
  accountId = String(accountId || '').trim();
  bucket = String(bucket || '').trim();
  accessKeyId = String(accessKeyId || '').trim();
  secretAccessKey = String(secretAccessKey || '').trim();
  if (!accountId || !bucket || !accessKeyId || !secretAccessKey) return null;

  const sign = (method, key, expiresIn, headers) =>
    presignUrl({ method, accountId, bucket, key, accessKeyId, secretAccessKey, expiresIn, headers });

  return {
    /** 올리기용 임시 주소 (PUT, content-type 헤더를 똑같이 보내야 함) */
    uploadUrl: (key, contentType, expiresIn) => sign('PUT', key, expiresIn, { 'content-type': contentType }),
    /** 재생용 임시 주소 (GET) */
    downloadUrl: (key, expiresIn) => sign('GET', key, expiresIn),
    /** 파일 정보. 없으면 null → { size, contentType } */
    async head(key) {
      const res = await fetchImpl(sign('HEAD', key, 60), { method: 'HEAD' });
      if (res.status === 404) return null;
      if (!res.ok) throw new Error(`R2 HEAD ${res.status}`);
      return {
        size: Number(res.headers.get('content-length') || 0),
        contentType: res.headers.get('content-type') || '',
      };
    },
    /** 파일 지우기 (없어도 성공) */
    async remove(key) {
      const res = await fetchImpl(sign('DELETE', key, 60), { method: 'DELETE' });
      if (!res.ok && res.status !== 404) throw new Error(`R2 DELETE ${res.status}`);
    },
  };
}

module.exports = { presignUrl, createR2Storage, encodeRfc3986 };
