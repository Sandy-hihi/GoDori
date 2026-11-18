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
  final List<TossCatalogOption> options;

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
            TossCatalogOption(
              id: '${(o as Map)['id'] ?? ''}',
              title: '${o['title'] ?? ''}',
              required: o['required'] == true,
              choices: [
                for (final c in (o['choices'] as List? ?? const []))
                  c is Map
                      ? TossCatalogChoice('${c['id'] ?? ''}', '${c['title'] ?? ''}', c['price'] is num ? (c['price'] as num).toInt() : 0)
                      : TossCatalogChoice('', '$c', 0), // 99차 전 서버
              ],
            ),
        ],
      );
}

/// 포스 상품 옵션 (99차: ID·필수 여부 — 필수 옵션은 메뉴 연결에서 미리 골라 둘 수 있음)
class TossCatalogOption {
  final String id;
  final String title;
  final bool required;
  final List<TossCatalogChoice> choices;
  const TossCatalogOption({required this.id, required this.title, required this.required, required this.choices});
}

class TossCatalogChoice {
  final String id;
  final String title;
  final int price;
  const TossCatalogChoice(this.id, this.title, this.price);
}

/// 메뉴 연결 값 (99차) — '상품ID' 또는 '상품ID:옵션ID=선택ID,…' (서버 functions/src/toss.js parseMapEntry 와 같은 모양)
class TossMenuLink {
  final String itemId;
  final Map<String, String> fixed; // 옵션ID → 선택ID
  const TossMenuLink(this.itemId, [this.fixed = const {}]);

  static TossMenuLink? parse(String? v) {
    if (v == null || v.isEmpty) return null;
    final parts = v.split(':');
    final fixed = <String, String>{};
    if (parts.length > 1) {
      for (final p in parts[1].split(',')) {
        final kv = p.split('=');
        if (kv.length == 2) fixed[kv[0]] = kv[1];
      }
    }
    return TossMenuLink(parts[0], fixed);
  }

  String encode() => fixed.isEmpty ? itemId : '$itemId:${fixed.entries.map((e) => '${e.key}=${e.value}').join(',')}';
}

/// 세트 구성품 (103차) — entry는 메뉴 연결과 같은 모양('상품ID' 또는 '상품ID:옵션ID=선택ID,…'), qty 1~20
///   when: '' = 항상, '옵션ID=선택ID' = 세트에서 그 옵션 선택을 골랐을 때만 (예: [떡볶이] 로제 → 로제 떡볶이)
///   서버 functions/src/toss.js cleanSetMap 과 같은 규칙
class TossSetPart {
  final String entry;
  final int qty;
  final String when;
  const TossSetPart(this.entry, this.qty, [this.when = '']);

  TossSetPart copyWith({String? entry, int? qty, String? when}) => TossSetPart(entry ?? this.entry, qty ?? this.qty, when ?? this.when);

  Map<String, dynamic> toJson() => {'entry': entry, 'qty': qty, if (when.isNotEmpty) 'when': when};

  static Map<String, List<TossSetPart>> mapFrom(Object? raw) => {
        for (final e in ((raw as Map?) ?? const {}).entries)
          '${e.key}': [
            for (final p in (e.value as List? ?? const []))
              if (p is Map) TossSetPart('${p['entry'] ?? ''}', int.tryParse('${p['qty'] ?? 1}') ?? 1, '${p['when'] ?? ''}'),
          ],
      };
}

/// 이름 비교용 (서버 normName 과 같은 규칙): 띄어쓰기·대소문자·괄호 안 무시, 라뗴=라떼, 쉐이크=셰이크, 아이스=ICE
String tossNormName(String s) {
  const alias = {'아이스': 'ice', '차갑게': 'ice', '차가운': 'ice', '핫': 'hot', '따뜻하게': 'hot', '뜨겁게': 'hot', '따뜻한': 'hot'};
  final t = s
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), '')
      .replaceAll('뗴', '떼')
      .replaceAll('쉐이크', '셰이크')
      .replaceAll(RegExp(r'\s+'), '');
  return alias[t] ?? t;
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

  /// 103차: 세트 구성품 표 (포스 세트 상품 ID → 구성품) 통째로 저장. 바뀐 뒤 전체 표
  static Future<Map<String, List<TossSetPart>>> saveSetMap(Map<String, List<TossSetPart>> map) async {
    final r = await _call('POST', '/api/toss/set-map', body: {
      'map': {for (final e in map.entries) e.key: [for (final p in e.value) p.toJson()]},
    });
    return TossSetPart.mapFrom(r['setMap']);
  }

  /// 113차: 포스 상품과 연결 안 된 메뉴를 받을 포스 상품('고도리 기타' 0원 권장). null이면 지움(그 메뉴는 포스 실패)
  /// 115차: 방 현황판 '결제 대기 비우기' — 그 방 결제 대기·주문 내역 비움(정산 표시 없이, 패드는 그대로). 비운 주문 수
  static Future<int> clearRoom(int room) async {
    final r = await _call('POST', '/api/toss/room-clear', body: {'room': room});
    return (r['cleared'] as num?)?.toInt() ?? 0;
  }

  static Future<String?> saveEtcItem(String? itemId) async {
    final r = await _call('POST', '/api/toss/etc-item', body: {'itemId': itemId});
    final v = r['etcItemId'];
    return v == null ? null : '$v';
  }

  /// 메뉴 연결 바꾸기 — 값이 null이면 연결 끊기. 바뀐 뒤 전체 연결표
  static Future<Map<String, String>> saveMenuMap(Map<String, String?> map) async {
    final r = await _call('POST', '/api/toss/menu-map', body: {'map': map});
    return {for (final e in ((r['menuMap'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
  }
}
