import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'admin_session.dart';
import 'r2_upload.dart';

/// 룰 설명 영상 (Cloudflare R2 저장소) — 서버 코드: functions/src/video.js
///
/// 영상 파일은 R2 버킷에 있고 공개되어 있지 않음. 서버가 몇 시간짜리 임시 주소를 만들어 줌.
///  - 관리자 웹: 올리기 주소 받기 → R2로 직접 PUT(진행률) → 서버에 확인 요청(게임 문서에 기록)
///  - 손님 패드: 재생 주소 받기(1080p·720p) → video_player로 재생
/// Firestore games/{id}.ruleVideo = { q1080: {key, sizeBytes, width, height, fps, durationSec, ...}, q720: {...} }
class RuleVideoException implements Exception {
  final String message;
  final String? code; // R2_NOT_CONNECTED, NO_VIDEO 등
  RuleVideoException(this.message, [this.code]);
  @override
  String toString() => message;
}

/// 재생 주소 묶음
class RuleVideoUrls {
  final Map<String, String> urls; // '1080' / '720' → 주소
  RuleVideoUrls(this.urls);
  bool has(String q) => urls.containsKey(q);
}

class RuleVideoService {
  static const List<String> qualities = ['1080', '720'];

  /// 저장소에 올라간 영상 정보 (없으면 빈 맵). 키: '1080', '720'
  static Map<String, Map<String, dynamic>> videosOf(Map<String, dynamic> game) {
    final rv = game['ruleVideo'];
    final out = <String, Map<String, dynamic>>{};
    if (rv is Map) {
      for (final q in qualities) {
        final v = rv['q$q'];
        if (v is Map && (v['key'] ?? '').toString().isNotEmpty) out[q] = Map<String, dynamic>.from(v);
      }
    }
    return out;
  }

  static bool hasVideo(Map<String, dynamic> game) => videosOf(game).isNotEmpty;

  static String _origin() {
    final base = Uri.base;
    final isHttp = base.scheme == 'http' || base.scheme == 'https';
    final isLocal = base.host == 'localhost' || base.host == '127.0.0.1';
    if (isHttp && !isLocal) return base.origin;
    return AdminSession.deployedOrigin;
  }

  static Future<Map<String, dynamic>> _call(String method, String path, {Map<String, String>? query, Object? body}) async {
    final token = await AdminSession.idToken();
    final headers = {
      if (token != null) 'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
    var uri = Uri.parse('${_origin()}$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    http.Response res;
    try {
      final f = method == 'GET' ? http.get(uri, headers: headers) : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await f.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw RuleVideoException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw RuleVideoException('서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> out = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) out = decoded;
    } catch (_) {}
    if (res.statusCode != 200) {
      final code = out['error']?.toString();
      if (code == 'R2_NOT_CONNECTED') {
        throw RuleVideoException('영상 저장소(Cloudflare R2)가 아직 연결되지 않았어요. "R2 룰 영상 연결 방법.txt"를 봐 주세요.', code);
      }
      if (res.statusCode == 404 && code == 'NOT_FOUND') {
        throw RuleVideoException('서버에 영상 기능이 아직 배포되지 않았어요. (배포.bat 4번 서버 함수 배포)', code);
      }
      throw RuleVideoException(out['message']?.toString() ?? '영상 요청에 실패했어요. (${res.statusCode})', code);
    }
    return out;
  }

  // ── 손님 패드 ──

  /// 재생 주소 받기. countPlay: 재생 횟수에 셀지 (화질 바꿀 때·주소 다시 받을 때는 false)
  static Future<RuleVideoUrls> playUrls(String gameId, {bool countPlay = true}) async {
    await AdminSession.ensureSignedIn(); // 손님 패드는 익명 로그인
    final body = await _call('GET', '/api/video/play-url', query: {'gameId': gameId, if (!countPlay) 'count': '0'});
    final urls = <String, String>{};
    for (final q in qualities) {
      final v = body['q$q'];
      if (v is Map && v['url'] is String) urls[q] = v['url'] as String;
    }
    if (urls.isEmpty) throw RuleVideoException('등록된 룰 영상이 없어요.', 'NO_VIDEO');
    return RuleVideoUrls(urls);
  }

  // ── 관리자 웹 ──

  /// 영상 올리기: 주소 받기 → R2로 PUT → 서버 확인. onProgress: 0.0~1.0
  static Future<Map<String, dynamic>> upload({
    required String gameId,
    required String quality,
    required Uint8List bytes,
    Map<String, dynamic>? meta,
    void Function(double)? onProgress,
  }) async {
    final up = await _call('POST', '/api/video/upload-url', body: {
      'gameId': gameId,
      'quality': quality,
      'size': bytes.length,
      'contentType': 'video/mp4',
    });
    final url = up['uploadUrl'] as String;
    final key = up['key'] as String;
    try {
      await putToStorage(url, bytes, contentType: (up['contentType'] ?? 'video/mp4').toString(), onProgress: onProgress);
    } on R2UploadException catch (e) {
      throw RuleVideoException(e.message);
    }
    final done = await _call('POST', '/api/video/confirm', body: {
      'gameId': gameId,
      'quality': quality,
      'key': key,
      'meta': meta ?? {},
    });
    return Map<String, dynamic>.from((done['video'] as Map?) ?? {});
  }

  /// 영상 지우기. quality: '1080' / '720' / 'all'
  static Future<void> remove(String gameId, {String quality = 'all'}) async {
    await _call('POST', '/api/video/delete', body: {'gameId': gameId, 'quality': quality});
  }
}
