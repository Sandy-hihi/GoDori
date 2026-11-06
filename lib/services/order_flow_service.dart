import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/models/order_flow.dart';
import 'package:boardpad/services/store_scope.dart';

/// 음식 수령 방식 설정 (stores/{매장}/settings/orderFlow 의 mode, 58차)
/// 문서가 없으면 serve(방으로 가져다 드림). 쓰기는 관리자만(firestore.rules)
class OrderFlowService {
  static DocumentReference<Map<String, dynamic>> get _doc =>
      StoreScope.col('settings').doc('orderFlow');

  static OrderFlow _parse(Map<String, dynamic>? data) => OrderFlow.parse(data?['mode']);

  /// 관리자가 바꾸면 바로 반영 (읽기 실패 시 기본값)
  static Stream<OrderFlow> watch() => _doc.snapshots().map((s) => _parse(s.data())).handleError((_) {});

  static Future<OrderFlow> load() async {
    try {
      return _parse((await _doc.get()).data());
    } catch (_) {
      return OrderFlow.fallback;
    }
  }

  static Future<void> save(OrderFlow flow) {
    return _doc.set({'mode': flow.id, 'updatedAt': FieldValue.serverTimestamp()});
  }
}
