import 'package:flutter_test/flutter_test.dart';

import 'package:boardpad/services/store_features.dart';

// 149차 월 정액권 앱 게임 연동 — 매장 기능 p6Sync (기본 꺼짐, 운영자가 켬)
void main() {
  test('p6Sync는 기본 꺼짐, 켜면 true', () {
    expect(StoreFeatures.fromStoreData(null).p6Sync, isFalse);
    expect(StoreFeatures.fromStoreData({'features': {'stock': true}}).p6Sync, isFalse);
    expect(StoreFeatures.fromStoreData({'features': {'p6Sync': true}}).p6Sync, isTrue);
    expect(StoreFeatures.fromStoreData({'features': {'p6Sync': 'yes'}}).p6Sync, isFalse);
  });
}
