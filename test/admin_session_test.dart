import 'dart:convert';
import 'dart:async';

import 'package:boardpad/services/admin_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// JWT 서명은 Firebase가 검증합니다. 이 테스트는 SDK 결과의 claims 복원만 검사합니다.
String idToken(Object? payload) {
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  return 'header.$encoded.signature';
}

class TestTokenResult extends Fake implements IdTokenResult {
  @override
  final Map<String, dynamic>? claims;
  @override
  final String? token;

  TestTokenResult({this.claims, this.token});
}

class TestUser extends Fake implements User {
  final IdTokenResult tokenResult;
  Object? tokenError;

  TestUser({Map<String, dynamic>? claims, String? token})
    : tokenResult = TestTokenResult(claims: claims, token: token);

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    final error = tokenError;
    if (error != null) throw error;
    return tokenResult;
  }
}

void main() {
  group('로그인 복원 오류 처리', () {
    test('통신 실패 뒤 저장된 사용자를 유지하고 재시도할 수 있다', () async {
      var signOutCount = 0;
      final user = TestUser(
        token: idToken({'store': 'platform6', 'pad': true, 'room': 2}),
      )..tokenError = FirebaseAuthException(code: 'network-request-failed');
      Future<void> invalidate() async {
        signOutCount++;
      }

      await expectLater(
        AdminSession.restoreUser(user, onInvalidSession: invalidate),
        throwsA(isA<SessionRestoreException>()),
      );
      expect(signOutCount, 0);
      user.tokenError = null;
      final session = await AdminSession.restoreUser(
        user,
        onInvalidSession: invalidate,
      );
      expect(session?.room, 2);
      expect(signOutCount, 0);
    });

    test('시간 초과도 저장된 로그인을 지우지 않는다', () async {
      var signedOut = false;
      final user = TestUser()..tokenError = TimeoutException('offline');
      await expectLater(
        AdminSession.restoreUser(
          user,
          onInvalidSession: () async {
            signedOut = true;
          },
        ),
        throwsA(isA<SessionRestoreException>()),
      );
      expect(signedOut, isFalse);
    });

    test('취소되거나 삭제된 사용자 인증은 정리한다', () async {
      for (final code in [
        'user-disabled',
        'user-not-found',
        'invalid-user-token',
        'user-token-expired',
      ]) {
        var signedOut = false;
        final user = TestUser()..tokenError = FirebaseAuthException(code: code);
        final session = await AdminSession.restoreUser(
          user,
          onInvalidSession: () async {
            signedOut = true;
          },
        );
        expect(session, isNull);
        expect(signedOut, isTrue);
      }
    });

    test('매장 권한이 없는 토큰은 로그인으로 유지하지 않는다', () async {
      var signedOut = false;
      final session = await AdminSession.restoreUser(
        TestUser(token: idToken({'sub': 'anonymous'})),
        onInvalidSession: () async {
          signedOut = true;
        },
      );
      expect(session, isNull);
      expect(signedOut, isTrue);
    });
  });

  group('API 오류 안내', () {
    Matcher messageContaining(String text) => isA<AdminLoginException>().having(
      (e) => e.message,
      'message',
      contains(text),
    );

    test('프록시 404를 서버 미배포로 단정하지 않는다', () {
      expect(
        () => AdminSession.decodeApiResponse(http.Response('NOT_FOUND', 404)),
        throwsA(messageContaining('API 경로')),
      );
    });

    test('서버가 반환한 비밀번호 오류를 보존한다', () {
      final response = http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'error': 'WRONG_PASSWORD',
            'message': '아이디 또는 비밀번호가 올바르지 않습니다.',
          }),
        ),
        401,
      );
      expect(
        () => AdminSession.decodeApiResponse(response),
        throwsA(messageContaining('아이디 또는 비밀번호')),
      );
    });

    test('서버 장애는 별도 안내한다', () {
      expect(
        () => AdminSession.decodeApiResponse(http.Response('Bad Gateway', 502)),
        throwsA(messageContaining('서버에 문제가')),
      );
    });

    test('200이어도 HTML이나 잘못된 JSON이면 배포 연결 문제를 안내한다', () {
      for (final body in ['<html>Login</html>', 'not-json', '[]', 'null']) {
        expect(
          () => AdminSession.decodeApiResponse(http.Response(body, 200)),
          throwsA(messageContaining('올바른 응답')),
        );
      }
    });

    test('정상 JSON 응답은 그대로 반환한다', () {
      expect(
        AdminSession.decodeApiResponse(http.Response('{"needPin":true}', 200)),
        {'needPin': true},
      );
    });
  });

  group('Firebase 로그인 토큰 claims 복원', () {
    test('Windows처럼 claims가 없어도 SDK ID 토큰의 손님 방을 읽는다', () async {
      final claims = await tokenClaimsOf(
        TestUser(
          token: idToken({'store': 'platform6', 'pad': true, 'room': 2}),
        ),
      );
      expect(claims, {'store': 'platform6', 'pad': true, 'room': 2});
    });

    test('claims가 빈 맵인 Windows 결과도 처리한다', () async {
      final claims = await tokenClaimsOf(
        TestUser(
          claims: {},
          token: idToken({'store': 'platform6', 'pad': true, 'room': 11}),
        ),
      );
      expect(claims?['room'], 11);
    });

    test('Windows 관리자 ID 토큰의 권한을 읽는다', () async {
      final claims = await tokenClaimsOf(
        TestUser(token: idToken({'store': 'platform6', 'admin': true})),
      );
      expect(claims, {'store': 'platform6', 'admin': true});
    });

    test('SDK가 claims를 제공하면 토큰을 디코딩할 필요가 없다', () async {
      final claims = await tokenClaimsOf(
        TestUser(
          claims: {'store': 'platform6', 'pad': true, 'room': 3},
          token: 'not-needed',
        ),
      );
      expect(claims?['room'], 3);
    });

    test('SDK claims를 대체 토큰의 관리자 권한으로 바꾸지 않는다', () async {
      final claims = await tokenClaimsOf(
        TestUser(
          claims: {'store': 'platform6', 'pad': true, 'room': 2},
          token: idToken({'store': 'platform6', 'admin': true}),
        ),
      );
      expect(claims, {'store': 'platform6', 'pad': true, 'room': 2});
    });

    test('없거나 손상된 토큰에서 claims를 만들지 않는다', () async {
      for (final token in <String?>[
        null,
        '',
        'not-a-jwt',
        'header.!.signature',
        'header.${base64Url.encode([255])}.signature',
        'header.${base64Url.encode(utf8.encode('not-json'))}.signature',
        idToken(null),
        idToken([]),
        idToken('text'),
      ]) {
        expect(await tokenClaimsOf(TestUser(token: token)), isNull);
      }
    });

    test('일반 Firebase 토큰에 매장 권한을 임의로 추가하지 않는다', () async {
      final claims = await tokenClaimsOf(
        TestUser(token: idToken({'sub': 'anonymous-user'})),
      );
      expect(claims, {'sub': 'anonymous-user'});
      expect(claims?.containsKey('pad'), isFalse);
      expect(claims?.containsKey('admin'), isFalse);
    });
  });
}
