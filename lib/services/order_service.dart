import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:boardpad/services/admin_session.dart';

/// 주문 보내기가 안 됐을 때 — [message]는 손님 패드에 그대로 보여 줄 문장(번역표 guest_messages.dart 키)
class OrderSendException implements Exception {
  final String message;
  final String? code;
  OrderSendException(this.message, [this.code]);
  @override
  String toString() => message;
}

/// 손님 패드 주문 (147차, 보안 점검) — 서버 functions/src/orders.js 의 POST /api/order/create
///
/// 예전엔 패드가 Firestore orders 에 직접 썼는데(금액·이름까지 패드가 정함), 이제는 메뉴 ID·개수·고른 옵션 이름만 보내고
/// 서버가 메뉴 문서에서 이름·가격을 읽어 주문을 만듦 → 패드를 조작해도 가격을 바꿀 수 없음. 보안 규칙도 직접 만들기를 막음.
class OrderService {
  static const genericError = '주문을 보내지 못했어요. 다시 눌러 주세요.';

  /// [lines]: [{menuId, quantity, options: [{group, name}]}] → 만든 주문 ID
  static Future<String> create({required List<Map<String, dynamic>> lines, required String notes}) async {
    final token = await AdminSession.idToken();
    if (token == null) throw OrderSendException('로그인이 만료됐어요. 다시 로그인해 주세요.', 'UNAUTHORIZED');
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${AdminSession.apiOrigin()}/api/order/create'),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
            body: jsonEncode({'lines': lines, 'notes': notes}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw OrderSendException(genericError);
    }
    Map<String, dynamic>? body;
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    final id = body?['orderId'];
    if (res.statusCode == 200 && id is String && id.isNotEmpty) return id;
    final msg = body?['message']?.toString().trim();
    throw OrderSendException(
      (msg == null || msg.isEmpty || res.statusCode >= 500) ? genericError : msg,
      body?['error']?.toString(),
    );
  }
}
