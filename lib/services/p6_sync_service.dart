import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:boardpad/services/admin_session.dart';

/// 월 정액권 앱 → 고도리 게임 맞추기 (149차) — 서버 functions/src/p6-sync.js POST /api/p6/sync
///   preview(): 무엇이 바뀌는지만 봄   run(): 실제로 맞춤 (서버가 80초 안에 다 못 하면 done false → 다시 부름)
/// 정액권 앱이 원본, 고도리는 읽어서 반영만. 매장 기능 features.p6Sync(운영자가 켬)인 매장만.
class P6SyncException implements Exception {
  final String message;
  P6SyncException(this.message);
  @override
  String toString() => message;
}

class P6SyncService {
  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final token = await AdminSession.idToken();
    if (token == null) throw P6SyncException('로그인이 풀렸어요. 다시 로그인해 주세요.');
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AdminSession.apiOrigin()}/api/p6/sync'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 115));
    } on TimeoutException {
      throw P6SyncException('서버 응답이 너무 늦어요. 잠시 후 다시 눌러 주세요.');
    } catch (_) {
      throw P6SyncException('서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> out = {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) out = d;
    } catch (_) {}
    if (res.statusCode != 200) {
      if (res.statusCode == 404 && out['message'] == null) {
        throw P6SyncException('서버에 아직 이 기능이 없어요. 서버 함수(배포 4번)를 먼저 배포해 주세요.');
      }
      throw P6SyncException(out['message']?.toString() ?? '맞추지 못했어요. (${res.statusCode})');
    }
    return out;
  }

  static Future<Map<String, dynamic>> preview() => _post({'dryRun': true});
  static Future<Map<String, dynamic>> run() => _post({'dryRun': false});
}
