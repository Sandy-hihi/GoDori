import 'dart:convert';

import 'package:boardpad/services/admin_session.dart';
import 'package:flutter_test/flutter_test.dart';

// 윈도우 앱은 claims를 안 채워 줘서 토큰(JWT)을 직접 풀어 읽음 (73차)
String _jwt(Map<String, dynamic> payload) {
  String part(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'RS256', 'typ': 'JWT'})}.${part(payload)}.sig';
}

void main() {
  test('패드 토큰의 표시를 읽음 (한글·= 없는 base64url 포함)', () {
    final c = decodeTokenClaims(_jwt({'store': 'platform6', 'pad': true, 'room': 3, 'name': '고도리'}));
    expect(c?['store'], 'platform6');
    expect(c?['pad'], true);
    expect(c?['room'], 3);
    expect(c?['name'], '고도리');
  });

  test('관리자·운영자 표시', () {
    expect(decodeTokenClaims(_jwt({'store': 'platform6', 'admin': true}))?['admin'], true);
    expect(decodeTokenClaims(_jwt({'ops': true}))?['ops'], true);
  });

  test('형식이 이상하면 null', () {
    expect(decodeTokenClaims(null), isNull);
    expect(decodeTokenClaims(''), isNull);
    expect(decodeTokenClaims('a.b'), isNull);
    expect(decodeTokenClaims('a.!!!.c'), isNull);
    expect(decodeTokenClaims('a.${base64Url.encode(utf8.encode('[1,2]'))}.c'), isNull);
  });
}
