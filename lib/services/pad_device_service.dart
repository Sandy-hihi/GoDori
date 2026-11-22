import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:boardpad/services/store_scope.dart';

/// 매장 태블릿 설정 (142차) — stores/{매장}/settings/padDevice
///   autoLaunch: 태블릿이 켜지면 고도리 자동 실행 (기본 꺼짐) — 관리자 웹 '매장 설정'에서 켜고 끔(쓰기는 관리자만, firestore.rules)
/// 패드(안드로이드 앱)는 이 값을 받아 태블릿에 저장해 둠([applyToDevice]) → 태블릿이 켜질 때 BootReceiver.kt가 그 값을 봄.
/// 웹(크롬)으로 켠 패드에는 해당 없음.
class PadDeviceService {
  static DocumentReference<Map<String, dynamic>> get _doc => StoreScope.col('settings').doc('padDevice');

  static bool parseAutoLaunch(Map<String, dynamic>? data) => data?['autoLaunch'] == true;

  /// 관리자 웹: 지금 값 (읽기 실패 시 꺼짐)
  static Stream<bool> watchAutoLaunch() =>
      _doc.snapshots().map((s) => parseAutoLaunch(s.data())).handleError((_) {});

  static Future<void> saveAutoLaunch(bool on) =>
      _doc.set({'autoLaunch': on, 'updatedAt': FieldValue.serverTimestamp()});

  static const _channel = MethodChannel('kr.godori.pad/device');

  /// 안드로이드 앱에서만 (웹·윈도우 앱은 해당 없음)
  static bool get deviceSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 태블릿에 저장 — 켜면 '켜질 때 자동 실행' + 기본 홈 앱으로 고를 수 있게, 끄면 둘 다 안 함 (MainActivity.kt)
  static Future<void> applyToDevice(bool on) async {
    if (!deviceSupported) return;
    try {
      await _channel.invokeMethod<void>('setAutoLaunch', {'on': on});
    } catch (e) {
      debugPrint('PadDeviceService: $e');
    }
  }
}
