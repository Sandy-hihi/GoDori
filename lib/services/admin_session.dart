import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'store_scope.dart';

/// 로그인 실패 이유 (화면에 그대로 보여 줄 문장)
class AdminLoginException implements Exception {
  final String message;
  AdminLoginException(this.message);
  @override
  String toString() => message;
}

/// 로그인된 상태 (토큰에 붙은 표시에서 읽음)
class PadSession {
  final String store;
  final bool isAdmin;
  final int room; // 손님 패드 방 번호 (관리자는 0)
  const PadSession({required this.store, required this.isAdmin, required this.room});
}

/// 패드 로그인 결과: PIN이 더 필요하거나(방 번호 0), 로그인 완료
class StoreLoginResult {
  final bool needPin;
  final PadSession? session;
  const StoreLoginResult._(this.needPin, this.session);
}

/// 지난번 로그인 화면에 쓴 값 (비밀번호는 저장하지 않음)
class LoginPrefs {
  final String storeId;
  final int? room;
  final bool autoLogin; // 다음에 앱을 켤 때 로그인 화면 없이 바로 들어갈지
  const LoginPrefs({this.storeId = '', this.room, this.autoLogin = false});
}

/// 고도리 로그인 (Firebase Authentication, 47차부터 매장별)
///
/// - 손님 패드: 매장 아이디 + 패드 비밀번호 + 방 번호 → 토큰 { pad: true, store, room }
/// - 방 번호 0: 비밀번호가 맞으면 관리자 PIN을 한 번 더 물음 → 토큰 { admin: true, store }
/// - 관리자 웹: 매장 아이디 + 관리자 웹 비밀번호 → 토큰 { admin: true, store }
/// 비밀번호 확인은 서버 함수(/api/auth/*)가 함 (stores/{매장}/private/account 는 앱에서 읽을 수 없음).
///
/// 자동 로그인: Firebase가 로그인 상태를 기기에 저장해 둠(비밀번호는 저장 안 함).
/// 앱이 켜질 때 [restore]로 그 상태를 읽고, '자동 로그인'을 켜 두었으면 바로 그 방 화면으로 감.
class AdminSession {
  /// 배포된 사이트 주소. 내 컴퓨터(localhost)·윈도우/안드로이드 앱에서는 여기 서버를 부릅니다.
  static const String deployedOrigin = 'https://godori-pad.web.app'; // 49차: 예전 platform6-boardpad.web.app

  static const _kStoreId = 'login.storeId';
  static const _kRoom = 'login.room';
  static const _kAuto = 'login.autoLogin';

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// 서버 함수 주소 (사용량 보고 등 다른 서비스에서도 씀)
  static String apiOrigin() => _origin();

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

  static final _storeIdRe = RegExp(r'^[a-z0-9][a-z0-9-]{2,29}$');

  static PadSession? _sessionFrom(Map<String, dynamic>? claims) {
    final store = claims?['store'];
    if (store is! String || !_storeIdRe.hasMatch(store)) return null;
    if (claims?['admin'] == true) return PadSession(store: store, isAdmin: true, room: 0);
    final room = claims?['room'];
    if (claims?['pad'] == true && room is num && room >= 1) {
      return PadSession(store: store, isAdmin: false, room: room.toInt());
    }
    return null;
  }

  /// 기기에 저장된 로그인을 불러옴. 매장 로그인이 아니면(예전 익명 로그인 등) 로그아웃하고 null.
  /// 인터넷이 없어도 저장된 토큰으로 읽음
  static Future<PadSession?> restore() async {
    final user = await _currentUser();
    if (user == null) return null;
    PadSession? s;
    try {
      s = _sessionFrom((await user.getIdTokenResult()).claims);
    } catch (e) {
      debugPrint('로그인 정보 읽기 실패: $e');
    }
    if (s == null) {
      await signOut();
      return null;
    }
    StoreScope.set(s.store);
    return s;
  }

  /// 지금 로그인한 사용자가 이 매장 관리자인지
  static Future<bool> isAdmin() async => (await restore())?.isAdmin ?? false;

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {String? idToken}) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${_origin()}$path'),
            headers: {
              'content-type': 'application/json',
              if (idToken != null) 'authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw AdminLoginException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw AdminLoginException('로그인 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> out = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) out = decoded;
    } catch (_) {}
    if (res.statusCode != 200) {
      final msg = out['message']?.toString();
      if (res.statusCode == 404 && msg == null) {
        throw AdminLoginException('로그인 서버가 아직 배포되지 않았어요. (실행 파일의 "서버 함수 배포"를 먼저 해 주세요)');
      }
      throw AdminLoginException(msg ?? '요청을 처리하지 못했어요. (${res.statusCode})');
    }
    return out;
  }

  static Future<PadSession> _signIn(Map<String, dynamic> body) async {
    final token = body['token'];
    if (token is! String || token.isEmpty) throw AdminLoginException('로그인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    try {
      await _auth.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      debugPrint('signInWithCustomToken 실패: ${e.code} ${e.message}');
      throw AdminLoginException('로그인하지 못했어요. 잠시 후 다시 시도해 주세요. (${e.code})');
    }
    final s = await restore();
    if (s == null) throw AdminLoginException('로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.');
    StoreScope.set(s.store, name: body['storeName']?.toString());
    return s;
  }

  /// 패드 로그인. room 0이면 처음엔 pin 없이 불러서 needPin을 받고, PIN을 받아 다시 부름
  static Future<StoreLoginResult> storeLogin({
    required String storeId,
    required String password,
    required int room,
    String? pin,
  }) async {
    final body = await _post('/api/auth/store-login', {
      'storeId': storeId.trim().toLowerCase(),
      'password': password,
      'room': room,
      'pin': ?pin,
    });
    if (body['needPin'] == true) return const StoreLoginResult._(true, null);
    return StoreLoginResult._(false, await _signIn(body));
  }

  /// 관리자 웹 로그인
  static Future<PadSession> webLogin({required String storeId, required String password}) async {
    final body = await _post('/api/auth/login', {'storeId': storeId.trim().toLowerCase(), 'password': password});
    return _signIn(body);
  }

  /// 가입 화면: 매장 아이디를 쓸 수 있는지. 형식이 틀리면 [AdminLoginException]
  static Future<bool> isStoreIdAvailable(String storeId) async {
    http.Response res;
    try {
      res = await http
          .get(Uri.parse('${_origin()}/api/stores/check-id').replace(queryParameters: {'id': storeId.trim().toLowerCase()}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw AdminLoginException('서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode != 200) throw AdminLoginException(body['message']?.toString() ?? '아이디를 확인하지 못했어요.');
    return body['available'] == true;
  }

  /// 사장님 가입 신청 → 운영자 승인 대기 (48차)
  static Future<void> signup({
    required String storeId,
    required String storeName,
    required String ownerName,
    required String phone,
    required String webPassword,
  }) async {
    await _post('/api/stores/signup', {
      'storeId': storeId.trim().toLowerCase(),
      'storeName': storeName.trim(),
      'ownerName': ownerName.trim(),
      'phone': phone.trim(),
      'webPassword': webPassword,
      'agree': true,
    });
  }

  /// 관리자 웹 '매장 설정': 비밀번호 바꾸기 (비운 칸은 안 바꿈). 바뀐 종류 목록을 돌려줌
  static Future<List<String>> changePasswords({String? padPassword, String? pin, String? webPassword}) async {
    final token = await idToken();
    if (token == null) throw AdminLoginException('로그인이 풀렸어요. 다시 로그인해 주세요.');
    final body = await _post('/api/store/passwords', {
      'padPassword': ?padPassword,
      'pin': ?pin,
      'webPassword': ?webPassword,
    }, idToken: token);
    final changed = body['changed'];
    return changed is List ? changed.map((e) => e.toString()).toList() : const [];
  }

  /// 패드 로그아웃 전 확인 (55차) — 패드 비밀번호 또는 관리자 PIN. 틀리면 [AdminLoginException]
  static Future<void> verifyExit(String password) async {
    final token = await idToken();
    if (token == null) return; // 이미 로그인이 풀린 상태면 그냥 로그아웃해도 됨
    await _post('/api/auth/verify-exit', {'password': password}, idToken: token);
  }

  /// 손님 기능(주문·호출·영상) 전에 로그인돼 있는지 확인
  static Future<void> ensureSignedIn() async {
    if (_auth.currentUser != null && StoreScope.isSet) return;
    if (await restore() != null) return;
    throw AdminLoginException('로그인이 풀렸어요. 직원에게 패드 로그인을 부탁해 주세요.');
  }

  static Future<void> signOut() async {
    StoreScope.clear();
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

  // ── 로그인 화면 값 기억 ──

  static Future<LoginPrefs> loadPrefs({String prefix = ''}) async {
    try {
      final p = await SharedPreferences.getInstance();
      return LoginPrefs(
        storeId: p.getString('$prefix$_kStoreId') ?? '',
        room: p.getInt('$prefix$_kRoom'),
        autoLogin: p.getBool('$prefix$_kAuto') ?? false,
      );
    } catch (_) {
      return const LoginPrefs();
    }
  }

  static Future<void> savePrefs({required String storeId, int? room, bool? autoLogin, String prefix = ''}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$prefix$_kStoreId', storeId);
      if (room != null) await p.setInt('$prefix$_kRoom', room);
      if (autoLogin != null) await p.setBool('$prefix$_kAuto', autoLogin);
    } catch (_) {}
  }
}
