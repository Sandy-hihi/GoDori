import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'admin_session.dart';
import 'package:boardpad/utils/game_meta.dart';

/// BGG(보드게임긱) 조회. 브라우저에서 BGG를 직접 부를 수 없어서 보드패드 서버 함수(/api/bgg/...)를 거칩니다.
/// (서버 코드: functions/src/app.js)
class BggException implements Exception {
  final String message;
  final int status;
  BggException(this.message, [this.status = 0]);

  @override
  String toString() => message;
}

class BggSearchResult {
  final String id;
  final String name;
  final int? yearPublished;
  final String? thumbnail;

  BggSearchResult({required this.id, required this.name, this.yearPublished, this.thumbnail});

  factory BggSearchResult.fromJson(Map<String, dynamic> j) => BggSearchResult(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        yearPublished: (j['yearPublished'] as num?)?.toInt(),
        thumbnail: j['thumbnail'] as String?,
      );
}

class BggGameInfo {
  final String geekId;
  final String name;
  final String? bggName; // 한글 이름을 채웠을 때 BGG 원래 이름 (확인용)
  final int minPlayers;
  final int maxPlayers;
  final String? recommendedPlayers;
  final double? weight;
  final int? rank;
  // BGG 플레이 시간(분). 서버를 새로 배포하기 전에는 null
  final int? minPlayTime;
  final int? maxPlayTime;
  final int? playingTime;

  BggGameInfo({
    required this.geekId,
    required this.name,
    this.bggName,
    required this.minPlayers,
    required this.maxPlayers,
    this.recommendedPlayers,
    this.weight,
    this.rank,
    this.minPlayTime,
    this.maxPlayTime,
    this.playingTime,
  });

  factory BggGameInfo.fromJson(Map<String, dynamic> j) => BggGameInfo(
        geekId: j['geekId'].toString(),
        name: (j['name'] ?? '').toString(),
        bggName: j['bggName'] as String?,
        minPlayers: (j['minPlayers'] as num).toInt(),
        maxPlayers: (j['maxPlayers'] as num).toInt(),
        recommendedPlayers: j['recommendedPlayers'] as String?,
        weight: (j['weight'] as num?)?.toDouble(),
        rank: (j['rank'] as num?)?.toInt(),
        minPlayTime: (j['minPlayTime'] as num?)?.toInt(),
        maxPlayTime: (j['maxPlayTime'] as num?)?.toInt(),
        playingTime: (j['playingTime'] as num?)?.toInt(),
      );

  /// 소요시간 글자 ("30분", "30~60분"). BGG에 시간이 없으면 null
  String? get playTimeText => playTimeTextOf(minPlayTime, maxPlayTime, playingTime);
}

class BggImage {
  final Uint8List bytes;
  final String contentType;
  BggImage(this.bytes, this.contentType);

  String get extension => contentType == 'image/png' ? 'png' : (contentType == 'image/webp' ? 'webp' : 'jpg');
}

class BggDetailsResult {
  final List<BggGameInfo> games;
  final List<String> missing;
  BggDetailsResult(this.games, this.missing);
}

class BggService {
  /// 배포된 관리자 웹 주소. 내 컴퓨터에서 실행(localhost)할 때는 여기 서버를 부릅니다.
  static const String deployedOrigin = 'https://platform6-boardpad.web.app';
  static const Duration _timeout = Duration(seconds: 110);

  static String _origin() {
    final base = Uri.base;
    final isHttp = base.scheme == 'http' || base.scheme == 'https';
    final isLocal = base.host == 'localhost' || base.host == '127.0.0.1';
    if (isHttp && !isLocal) return base.origin;
    return deployedOrigin;
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('${_origin()}$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  static Map<String, String> get _headers => {
        'x-admin-password': AdminSession.password ?? '',
        'content-type': 'application/json',
      };

  static Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response res;
    try {
      res = await request().timeout(_timeout);
    } on TimeoutException {
      throw BggException('BGG 응답이 너무 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw BggException('BGG 조회 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode != 200) {
      final msg = body['message']?.toString();
      if (res.statusCode == 404 && msg == null) {
        throw BggException('BGG 조회 서버가 아직 배포되지 않았어요. (실행 파일의 "서버 함수 배포"를 먼저 해 주세요)', 404);
      }
      throw BggException(msg ?? 'BGG 조회 중 오류가 났어요. (${res.statusCode})', res.statusCode);
    }
    return body;
  }

  static Future<List<BggSearchResult>> search(String query) async {
    final body = await _send(() => http.get(_uri('/api/bgg/search', {'q': query}), headers: _headers));
    final list = (body['results'] as List?) ?? [];
    return list.map((e) => BggSearchResult.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<BggGameInfo> lookup(String geekId) async {
    final body = await _send(() => http.get(_uri('/api/bgg/lookup', {'id': geekId}), headers: _headers));
    return BggGameInfo.fromJson(body);
  }

  static Future<BggImage> image(String geekId) async {
    final body = await _send(() => http.get(_uri('/api/bgg/image', {'id': geekId}), headers: _headers));
    final dataUrl = (body['dataUrl'] ?? '').toString();
    final comma = dataUrl.indexOf(',');
    if (comma < 0) throw BggException('BGG 사진을 읽지 못했어요.');
    return BggImage(base64Decode(dataUrl.substring(comma + 1)), (body['contentType'] ?? 'image/jpeg').toString());
  }

  /// 여러 개 상세 조회 (서버 제한: 한 번에 30개)
  static Future<BggDetailsResult> details(List<String> geekIds) async {
    final body = await _send(() => http.post(_uri('/api/bgg/details'), headers: _headers, body: jsonEncode({'ids': geekIds})));
    final games = ((body['games'] as List?) ?? []).map((e) => BggGameInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    final missing = ((body['missing'] as List?) ?? []).map((e) => e.toString()).toList();
    return BggDetailsResult(games, missing);
  }
}
