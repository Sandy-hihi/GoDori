import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:boardpad/services/admin_session.dart';

/// 손님 패드 자동 번역 (83차) — 관리자 웹이 메뉴·공지·이벤트를 저장한 뒤(그리고 로그인한 뒤) 서버에 '바뀐 글 번역해 줘'.
/// 서버 functions/src/translate.js POST /api/translate/sync — 새로 생기거나 바뀐 글만 영어·중국어·일본어로 번역해
/// 같은 문서의 translations 칸에 넣음(손님 패드 guestField가 읽음). 기다리지 않고, 실패해도 저장은 그대로(다음 저장 때 다시).
class TranslateSync {
  static Timer? _timer;

  /// 연달아 여러 번 저장해도 2초 뒤 한 번만 부름
  static void kick() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _run);
  }

  static Future<void> _run() async {
    try {
      final token = await AdminSession.idToken();
      if (token == null) return;
      final res = await http
          .post(
            Uri.parse('${AdminSession.apiOrigin()}/api/translate/sync'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
            body: '{}',
          )
          .timeout(const Duration(seconds: 90));
      debugPrint('자동 번역: ${res.statusCode} ${utf8.decode(res.bodyBytes)}');
    } catch (e) {
      debugPrint('자동 번역 실패(다음 저장 때 다시): $e');
    }
  }
}
