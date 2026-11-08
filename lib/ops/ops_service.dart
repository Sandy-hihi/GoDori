import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../services/admin_session.dart';

class OpsException implements Exception {
  final String message;
  OpsException(this.message);
  @override
  String toString() => message;
}

/// 운영자 페이지 서버 호출 (48차) — 서버 코드 functions/src/app.js opsRoute
///
/// 사장님 관리자 웹과 같은 사이트(/ops)라서, 로그인이 섞이지 않게 Firebase 앱을 따로('ops') 띄움.
/// 운영자 토큰 { ops: true }은 매장 데이터에 직접 못 들어가고 이 API로만 일함.
class OpsService {
  static FirebaseAuth? _auth;

  static Future<FirebaseAuth> _authInstance() async {
    if (_auth != null) return _auth!;
    FirebaseApp app;
    try {
      app = Firebase.app('ops');
    } catch (_) {
      app = await Firebase.initializeApp(name: 'ops', options: DefaultFirebaseOptions.currentPlatform);
    }
    return _auth = FirebaseAuth.instanceFor(app: app);
  }

  /// 저장된 운영자 로그인이 있는지
  static Future<bool> restore() async {
    final auth = await _authInstance();
    var user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (user == null) return false;
    try {
      final claims = await tokenClaimsOf(user); // 윈도우 앱에서도 읽히게 (admin_session.dart)
      if (claims?['ops'] == true) return true;
    } catch (_) {}
    await auth.signOut();
    return false;
  }

  static Future<void> login(String password) async {
    final body = await _call('POST', '/api/ops/login', body: {'password': password}, auth: false);
    final token = body['token'];
    if (token is! String) throw OpsException('로그인하지 못했어요.');
    await (await _authInstance()).signInWithCustomToken(token);
  }

  static Future<void> logout() async => (await _authInstance()).signOut();

  static Future<Map<String, dynamic>> _call(String method, String path,
      {Map<String, String>? query, Object? body, bool auth = true}) async {
    String? token;
    if (auth) {
      token = await (await _authInstance()).currentUser?.getIdToken();
      if (token == null) throw OpsException('다시 로그인해 주세요.');
    }
    var uri = Uri.parse('${AdminSession.apiOrigin()}$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = {'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token'};
    http.Response res;
    try {
      final f = method == 'GET' ? http.get(uri, headers: headers) : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await f.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw OpsException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw OpsException('서버에 연결하지 못했어요.');
    }
    Map<String, dynamic> out = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) out = decoded;
    } catch (_) {}
    if (res.statusCode != 200) {
      if (res.statusCode == 404 && out['message'] == null) throw OpsException('서버에 운영자 기능이 아직 배포되지 않았어요. (배포.bat 4번)');
      throw OpsException(out['message']?.toString() ?? '요청을 처리하지 못했어요. (${res.statusCode})');
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> stores() async {
    final r = await _call('GET', '/api/ops/stores');
    return [for (final s in (r['stores'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
  }

  static Future<void> setStatus(String storeId, String status) =>
      _call('POST', '/api/ops/store-status', body: {'storeId': storeId, 'status': status});

  /// 매장 기능 켜기·끄기 (59차) — { adminDashboard?, tossPos? } → 바뀐 뒤 전체 값
  static Future<Map<String, dynamic>> setFeatures(String storeId, Map<String, bool> fields) async {
    final r = await _call('POST', '/api/ops/store-features', body: {'storeId': storeId, ...fields});
    return Map<String, dynamic>.from((r['features'] as Map?) ?? const {});
  }

  // ── 토스 POS 연결 (64차) ──
  static Future<Map<String, dynamic>> tossOverview() => _call('GET', '/api/ops/toss/overview');

  static Future<void> tossLink(String storeId, String mode, {String? merchantId}) =>
      _call('POST', '/api/ops/toss/link', body: {'storeId': storeId, 'mode': mode, 'merchantId': ?merchantId});

  static Future<void> tossUnlink(String storeId) => _call('POST', '/api/ops/toss/unlink', body: {'storeId': storeId});

  static Future<void> tossConfig(String storeId, {required bool printOrderSheet}) =>
      _call('POST', '/api/ops/toss/config', body: {'storeId': storeId, 'printOrderSheet': printOrderSheet});

  static Future<List<Map<String, dynamic>>> tossFakeOrders(String storeId) async {
    final r = await _call('GET', '/api/ops/toss/fake-orders', query: {'storeId': storeId});
    return [for (final o in (r['orders'] as List? ?? const [])) Map<String, dynamic>.from(o as Map)];
  }

  /// 가짜 포스에서 '결제 완료' 흉내 (81차) → 그 방 패드 주문이 다 끝나면 패드 언어가 기본으로
  static Future<Map<String, dynamic>> tossFakeComplete(String storeId, Map<String, dynamic> order) =>
      _call('POST', '/api/ops/toss/fake-complete',
          body: {'storeId': storeId, 'orderKey': order['orderKey'], 'id': order['id']});

  static Future<void> deleteSignup(String storeId) => _call('POST', '/api/ops/store-delete', body: {'storeId': storeId});

  static Future<Map<String, dynamic>> usage(int days) => _call('GET', '/api/ops/usage', query: {'days': '$days'});

  /// 매장 통계 (65차) — storeId: 매장 아이디 또는 'all'(운영 중인 매장 전체). 인기 메뉴·게임·시간대별 주문
  static Future<Map<String, dynamic>> insights(String storeId, int days) =>
      _call('GET', '/api/ops/insights', query: {'storeId': storeId, 'days': '$days'});

  static Future<Map<String, dynamic>> projectUsage(int days) =>
      _call('GET', '/api/ops/project-usage', query: {'days': '$days'});

  static Future<Map<String, dynamic>> recountR2(String storeId) =>
      _call('POST', '/api/ops/recount-r2', body: {'storeId': storeId});

  static Future<void> changePassword(String password) => _call('POST', '/api/ops/password', body: {'password': password});
}
