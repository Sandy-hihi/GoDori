import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_scope.dart';

/// 매장 정보(전화번호 등)를 Firestore `settings/storeInfo` 문서에서 읽어옵니다.
/// 소스코드에 개인정보를 남기지 않기 위해 기본값을 두지 않습니다.
/// 120차: 관리자 웹 '매장 설정 > 매장 전화번호'에서 `phoneNumber`(문자열)를 바꿈 (예전엔 Firebase 콘솔에서만)
class StoreInfoService {
  static Future<String>? _phoneFuture;
  static String? _phoneStore; // 어느 매장 번호를 기억 중인지 (매장이 바뀌면 다시 읽음)
  static DateTime? _phoneAt; // 120차: 읽은 시각 — 10분 지나면 다시 읽음(관리자 웹에서 바꾸면 패드에도 반영되게)
  static const _maxAge = Duration(minutes: 10);

  /// 전화번호로 쓸 수 있는 글자 (firestore.rules settings/storeInfo와 같게): 숫자·+·괄호·-·띄어쓰기, 20자까지
  static final phonePattern = RegExp(r'^[0-9+() -]{0,20}$');

  /// 읽은 결과를 10분 동안 재사용합니다. (실패 시 다음 호출 때 다시 시도)
  static Future<String> phoneNumber() {
    if (!StoreScope.isSet) return Future.value('');
    final at = _phoneAt;
    if (_phoneStore != StoreScope.id || at == null || DateTime.now().difference(at) > _maxAge) {
      _phoneStore = StoreScope.id;
      _phoneFuture = null;
    }
    if (_phoneFuture == null) _phoneAt = DateTime.now();
    return _phoneFuture ??= _loadPhoneNumber();
  }

  /// 관리자 웹: 지금 저장된 전화번호 (바뀌면 다시 알려 줌)
  static Stream<String> watchPhone() => StoreScope.col('settings').doc('storeInfo').snapshots().map((d) {
        final v = d.data()?['phoneNumber'];
        return v is String ? v : '';
      });

  /// 관리자 웹: 전화번호 저장 (빈칸이면 손님 패드에 안 보임)
  static Future<void> savePhone(String phone) async {
    final v = phone.trim();
    if (!phonePattern.hasMatch(v)) throw ArgumentError('전화번호는 숫자·-·+·괄호로 20자까지 입력해 주세요.');
    await StoreScope.col('settings').doc('storeInfo').set(
      {'phoneNumber': v, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    _phoneFuture = null; // 이 기기에서는 바로 새 값으로
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
