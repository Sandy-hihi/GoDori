import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'admin_session.dart';
import 'store_scope.dart';

/// 앱이 Firestore에서 읽은 문서 수를 세서 서버에 보고 (48차 — 운영자 페이지의 매장별 사용량 추정)
///
/// Firebase는 매장별 사용량을 따로 알려 주지 않아서, 많이 읽는 곳(게임 목록 648개 등)에서 직접 셈.
/// 기기 캐시에서 온 결과는 요금이 안 들어서 안 셈. 15분마다(또는 2000개 넘으면) 한 번 보고 — 보고 1번 = 쓰기 1번.
/// 사용: `StoreScope.col('games').get().metered()` / `.snapshots().metered()`
class UsageMeter {
  static int _reads = 0;
  static Timer? _timer;
  static bool _sending = false;

  static void addReads(int n) {
    if (n <= 0) return;
    _reads += n;
    _timer ??= Timer.periodic(const Duration(minutes: 15), (_) => flush());
    if (_reads >= 2000) flush();
  }

  static Future<void> flush() async {
    if (_sending || _reads == 0 || !StoreScope.isSet) return;
    final n = _reads > 50000 ? 50000 : _reads;
    _sending = true;
    try {
      final token = await AdminSession.idToken();
      if (token == null) return;
      final res = await http
          .post(
            Uri.parse('${AdminSession.apiOrigin()}/api/usage/report'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
            body: jsonEncode({'reads': n}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) _reads -= n;
    } catch (e) {
      debugPrint('사용량 보고 실패(다음에 다시): $e');
    } finally {
      _sending = false;
    }
  }
}

extension MeteredQueryFuture<T> on Future<QuerySnapshot<T>> {
  Future<QuerySnapshot<T>> metered() => then((s) {
        if (!s.metadata.isFromCache) UsageMeter.addReads(s.docs.length);
        return s;
      });
}

extension MeteredQueryStream<T> on Stream<QuerySnapshot<T>> {
  /// 실시간 구독: 처음엔 전체, 그다음엔 바뀐 문서만 요금이 듦
  Stream<QuerySnapshot<T>> metered() => map((s) {
        if (!s.metadata.isFromCache) UsageMeter.addReads(s.docChanges.length);
        return s;
      });
}
