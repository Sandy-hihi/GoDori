import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'admin_session.dart';
import 'store_scope.dart';

/// 매장 통계 보고 (65차) — 운영자 페이지 '매장 통계'(인기 메뉴·인기 게임)용. 서버 코드 functions/src/insights.js
///
///  - 주문: 손님 패드가 주문을 만든 직후 [countOrder] → 서버가 주문 문서를 읽어 메뉴별로 셈 (같은 주문은 한 번만)
///  - 게임: 손님이 게임 상세를 열면 [gameViewed] → 모아서 10분마다(또는 50번 쌓이면) 한 번 보고
///    같은 게임을 30초 안에 다시 연 건 안 셈. 관리자 화면에서 연 건 서버가 받기만 하고 안 셈.
/// 실패해도 손님 화면에는 아무 영향 없음 (주문은 못 센 채로 지나감, 게임 조회는 다음에 다시 보냄)
class InsightService {
  static final Map<String, int> _views = {};
  static final Map<String, DateTime> _lastSeen = {};
  static Timer? _timer;
  static bool _sending = false;

  /// 주문 세기 — 기다리지 않고 부름: `unawaited(InsightService.countOrder(ref.id))`
  static Future<void> countOrder(String orderId) async {
    try {
      await _post('/api/stats/order', {'orderId': orderId});
    } catch (e) {
      debugPrint('주문 통계 보고 실패: $e');
    }
  }

  /// 게임 상세를 열었을 때 (게임 문서 ID)
  static void gameViewed(String? gameId) {
    if (gameId == null || gameId.isEmpty || !StoreScope.isSet) return;
    final now = DateTime.now();
    final prev = _lastSeen[gameId];
    if (prev != null && now.difference(prev) < const Duration(seconds: 30)) return;
    _lastSeen[gameId] = now;
    if (!_views.containsKey(gameId) && _views.length >= 250) return; // 보고가 계속 실패할 때 너무 쌓이지 않게
    _views[gameId] = (_views[gameId] ?? 0) + 1;
    _timer ??= Timer.periodic(const Duration(minutes: 10), (_) => flush());
    if (_views.values.fold<int>(0, (a, b) => a + b) >= 50) flush();
  }

  static Future<void> flush() async {
    if (_sending || _views.isEmpty || !StoreScope.isSet) return;
    final batch = Map<String, int>.from(_views);
    _sending = true;
    try {
      final status = await _post('/api/stats/report', {'gameViews': batch});
      // 200이면 보낸 만큼 빼고, 400(값이 이상함)이면 다시 보내도 소용없어서 버림. 그 밖(네트워크·429·5xx)은 다음에 다시
      if (status == 200 || status == 400) {
        batch.forEach((id, n) {
          final left = (_views[id] ?? 0) - n;
          if (left > 0) {
            _views[id] = left;
          } else {
            _views.remove(id);
          }
        });
      }
    } catch (e) {
      debugPrint('게임 조회 통계 보고 실패(다음에 다시): $e');
    } finally {
      _sending = false;
    }
  }

  static Future<int> _post(String path, Map<String, dynamic> body) async {
    final token = await AdminSession.idToken();
    if (token == null) return 0;
    final res = await http
        .post(
          Uri.parse('${AdminSession.apiOrigin()}$path'),
          headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return res.statusCode;
  }
}
