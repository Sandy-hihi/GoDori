import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:boardpad/services/admin_session.dart';

/// 토스 POS 연동 (64차) — 서버 functions/src/toss-routes.js 의 /api/toss/*
///   주문 보내기(패드가 주문 직후 자동, 관리자는 '다시 보내기'), 연결 상태, 포스 상품 목록, 메뉴 연결표
/// 실패하면 [TossPosException] (화면에 그대로 보여 줄 문장)
class TossPosException implements Exception {
  final String message;
  TossPosException(this.message);
  @override
  String toString() => message;
}

/// 포스 상품 (관리자 웹 메뉴 연결 화면용)
class TossCatalogItem {
  final String id;
  final String title;
  final String category;
  final int? price;
  final bool soldOut;
  final List<({String title, List<String> choices})> options;

  const TossCatalogItem({
    required this.id,
    required this.title,
    required this.category,
    required this.price,
    required this.soldOut,
    required this.options,
  });

  factory TossCatalogItem.fromJson(Map<String, dynamic> j) => TossCatalogItem(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        category: '${j['category'] ?? ''}',
        price: j['price'] is num ? (j['price'] as num).toInt() : null,
        soldOut: j['soldOut'] == true,
        options: [
          for (final o in (j['options'] as List? ?? const []))
            (
              title: '${(o as Map)['title'] ?? ''}',
              choices: [for (final c in (o['choices'] as List? ?? const [])) '$c'],
            ),
        ],
      );
}

class TossPosService {
  static Future<Map<String, dynamic>> _call(String method, String path, {Object? body}) async {
    final token = await AdminSession.idToken();
    if (token == null) throw TossPosException('로그인이 풀렸어요. 다시 로그인해 주세요.');
    final uri = Uri.parse('${AdminSession.apiOrigin()}$path');
    final headers = {'content-type': 'application/json', 'authorization': 'Bearer $token'};
    http.Response res;
    try {
      final f = method == 'GET' ? http.get(uri, headers: headers) : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await f.timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw TossPosException('서버 응답이 늦어요. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw TossPosException('서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.');
    }
    Map<String, dynamic> out = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) out = decoded;
    } catch (_) {}
    if (res.statusCode != 200) {
      if (res.statusCode == 404 && out['message'] == null) {
        throw TossPosException('서버에 토스 POS 기능이 아직 배포되지 않았어요. (배포.bat 4번)');
      }
      throw TossPosException(out['message']?.toString() ?? '요청을 처리하지 못했어요. (${res.statusCode})');
    }
    return out;
  }

  /// 주문을 포스로 보내기 → 서버가 주문 문서의 tossPos 칸에 결과를 적음({state: sent|failed, error…})
  static Future<Map<String, dynamic>> sendOrder(String orderId) async {
    final r = await _call('POST', '/api/toss/send-order', body: {'orderId': orderId});
    return Map<String, dynamic>.from((r['tossPos'] as Map?) ?? const {});
  }

  /// 연결 상태: {enabled, linked, mode('fake'|'live'), merchantName, menuMap{메뉴ID: 상품ID}, failed[...]}
  static Future<Map<String, dynamic>> status() => _call('GET', '/api/toss/status');

  static Future<List<TossCatalogItem>> catalog() async {
    final r = await _call('GET', '/api/toss/catalog');
    return [for (final i in (r['items'] as List? ?? const [])) TossCatalogItem.fromJson(Map<String, dynamic>.from(i as Map))];
  }

  /// 메뉴 연결 바꾸기 — 값이 null이면 연결 끊기. 바뀐 뒤 전체 연결표
  static Future<Map<String, String>> saveMenuMap(Map<String, String?> map) async {
    final r = await _call('POST', '/api/toss/menu-map', body: {'map': map});
    return {for (final e in ((r['menuMap'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
  }
}
