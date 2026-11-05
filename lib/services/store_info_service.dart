import 'package:boardpad/services/store_scope.dart';

/// 매장 정보(전화번호 등)를 Firestore `settings/storeInfo` 문서에서 읽어옵니다.
/// 소스코드에 개인정보를 남기지 않기 위해 기본값을 두지 않습니다.
/// Firebase 콘솔에서 settings/storeInfo 문서에 `phoneNumber` 필드(문자열)를 만들어 주세요.
class StoreInfoService {
  static Future<String>? _phoneFuture;
  static String? _phoneStore; // 어느 매장 번호를 기억 중인지 (매장이 바뀌면 다시 읽음)

  /// 앱 실행 중 한 번만 읽고 결과를 재사용합니다. (실패 시 다음 호출 때 다시 시도)
  static Future<String> phoneNumber() {
    if (!StoreScope.isSet) return Future.value('');
    if (_phoneStore != StoreScope.id) {
      _phoneStore = StoreScope.id;
      _phoneFuture = null;
    }
    return _phoneFuture ??= _loadPhoneNumber();
  }

  static Future<String> _loadPhoneNumber() async {
    try {
      final doc = await StoreScope.col('settings')
          .doc('storeInfo')
          .get();
      final value = doc.data()?['phoneNumber'];
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // 네트워크 오류 등 — 아래에서 빈 값 반환
    }
    _phoneFuture = null;
    return '';
  }
}
