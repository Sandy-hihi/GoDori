import 'dart:convert';

import 'package:boardpad/services/admin_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

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

  TestUser({Map<String, dynamic>? claims, String? token})
    : tokenResult = TestTokenResult(claims: claims, token: token);

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      tokenResult;
}

void main() {
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
