import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

/// 매장의 방 개수 (Firestore stores/{매장}/settings/rooms 문서의 count) — 패드 로그인 때 서버도 이 값으로 방 번호를 검사
/// 문서가 없으면 예전과 같이 11개. Firestore 규칙도 같은 문서를 읽어서 주문·직원 호출의 방 번호를 검사함
class RoomSettingsService {
  static const int defaultCount = 11;
  static const int minCount = 1;
  static const int maxCount = 30; // firestore.rules 의 상한과 같아야 함

  static DocumentReference<Map<String, dynamic>> get _doc =>
      StoreScope.col('settings').doc('rooms');

  static int _parse(Map<String, dynamic>? data) {
    final v = data?['count'];
    final n = v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');
    if (n == null || n < minCount || n > maxCount) return defaultCount;
    return n;
  }

  /// 관리자가 바꾸면 바로 반영
  static Stream<int> watchCount() =>
      _doc.snapshots().map((s) => _parse(s.data())).handleError((_) {});

  static Future<int> loadCount() async {
    try {
      return _parse((await _doc.get()).data());
    } catch (_) {
      return defaultCount;
    }
  }

  static Future<void> saveCount(int count) {
    return _doc.set({'count': count, 'updatedAt': FieldValue.serverTimestamp()});
  }
}
