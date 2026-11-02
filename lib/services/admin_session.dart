import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 로그인 실패 이유 (화면에 그대로 보여 줄 문장)
class AdminLoginException implements Exception {
  final String message;
  AdminLoginException(this.message);
  @override
  String toString() => message;
}

/// 고도리 로그인 상태 (Firebase Authentication)
///
/// - 손님 패드: 익명 로그인 → 주문·직원 호출 생성만 가능
/// - 관리자(태블릿 PIN / 관리자 웹 비밀번호): 서버 함수(/api/auth/login)가 PIN을 확인하고
///   admin 표시가 붙은 토큰을 발급 → Firestore·Storage 보안 규칙의 isAdmin() 통과
///
/// PIN·비밀번호는 앱이 읽지 않습니다. (Firestore settings/adminPin 은 서버만 읽을 수 있음)
class AdminSession {
  /// 배포된 사이트 주소. 내 컴퓨터(localhost)·윈도우/안드로이드 앱에서는 여기 서버를 부릅니다.
  static const String deployedOrigin = 'https://platform6-boardpad.web.app';

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static String _origin() {
    final base = Uri.base;
    final isHttp = base.scheme == 'http' || base.scheme == 'https';
    final isLocal = base.host == 'localhost' || base.host == '127.0.0.1';
    if (isHttp && !isLocal) return base.origin;
    return deployedOrigin;
  }

  /// 지금 로그인한 사용자. 웹은 새로고침 직후 저장된 로그인을 불러오는 데 잠깐 걸려서 첫 상태를 기다림
  static Future<User?> _currentUser() async {
    final now = _auth.currentUser;
    if (now != null) return now;
    try {
      return await _auth.authStateChanges().first.timeout(const Duration(seconds: 5));
    } catch (_) {
      return _auth.currentUser;
    }
  }

  /// 지금 로그인한 사용자가 관리자인지 (토큰의 admin 표시로 확인)
  static Future<bool> isAdmin() async {
    final user = await _currentUser();
    if (user == null || user.isAnonymous) return false;
    try {
      final result = await user.getIdTokenResult();
      return result.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 관리자 로그인. kind: 'pad'(태블릿 PIN) 또는 'web'(관리자 웹 비밀번호)
  /// 실패하면 [AdminLoginException]
  static Future<void> login({required String kind, required String password}) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${_origin()}/api/auth/login'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'kind': kind, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw AdminLoginException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw AdminLoginException('로그인 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }

    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    final token = body['token'];
    if (res.statusCode != 200 || token is! String || token.isEmpty) {
      final msg = body['message']?.toString();
      if (res.statusCode == 404 && msg == null) {
        throw AdminLoginException('로그인 서버가 아직 배포되지 않았어요. (실행 파일의 "서버 함수 배포"를 먼저 해 주세요)');
      }
      throw AdminLoginException(msg ?? '로그인하지 못했어요. (${res.statusCode})');
    }

    try {
      // 익명(손님)으로 로그인돼 있었다면 관리자 계정으로 바뀜
      await _auth.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      debugPrint('signInWithCustomToken 실패: ${e.code} ${e.message}');
      throw AdminLoginException('로그인하지 못했어요. 잠시 후 다시 시도해 주세요. (${e.code})');
    }
  }

  /// 손님 패드 상태로 맞춤: 관리자로 로그인돼 있으면 로그아웃하고 익명 로그인.
  /// 인터넷이 없거나 실패해도 앱은 계속 켜지게 에러를 삼킴 (주문은 연결된 뒤 다시 시도)
  static Future<void> ensureGuest() async {
    try {
      final user = await _currentUser();
      if (user != null && user.isAnonymous) return;
      if (user != null) await _auth.signOut();
      await _auth.signInAnonymously().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('익명 로그인 실패: $e');
    }
  }

  /// 손님 기능(주문·호출) 전에 로그인돼 있는지 확인. 앱 시작 때 실패했으면 여기서 다시 시도
  static Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null) return;
    await ensureGuest();
  }

  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  /// 서버 함수(BGG 조회 등)에 보낼 Firebase ID 토큰
  static Future<String?> idToken() async {
    try {
      return await _auth.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }
}
