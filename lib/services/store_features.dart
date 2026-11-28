import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/services/store_scope.dart';

/// 매장별 기능 켜기·끄기 (59차) — Firestore stores/{매장}.features (누구나 읽기, 쓰기는 서버만)
///   adminDashboard  패드 방 번호 0 관리자 대시보드(주문 현황). 사장님이 관리자 웹 '매장 설정'에서 바꿈 (기본 켜짐)
///   tossPos         토스 POS 연동. 운영자 페이지에서만 바꿈, 사장님은 보기만 (기본 꺼짐)
///   stock           재고관리(148차) — 신청한 매장만 운영자가 켬 (기본 꺼짐). 켜지면 관리자 웹 '재고관리' 탭 + 재고 앱
///   p6Sync          월 정액권 앱 게임 연동(149차) — 운영자가 켬 (기본 꺼짐). 켜지면 보드게임 관리 [정액권 앱과 맞추기] + 정액권 앱 신호 받기
/// 서버 쪽 기본값·검사는 functions/src/stores.js FEATURE_DEFAULTS 와 같아야 함
class StoreFeatures {
  final bool adminDashboard;
  final bool tossPos;
  final bool stock;
  final bool p6Sync;

  const StoreFeatures({this.adminDashboard = true, this.tossPos = false, this.stock = false, this.p6Sync = false});

  static const defaults = StoreFeatures();

  factory StoreFeatures.fromStoreData(Map<String, dynamic>? data) {
    final f = data?['features'];
    if (f is! Map) return defaults;
    return StoreFeatures(
      adminDashboard: f['adminDashboard'] is bool ? f['adminDashboard'] as bool : defaults.adminDashboard,
      tossPos: f['tossPos'] is bool ? f['tossPos'] as bool : defaults.tossPos,
      stock: f['stock'] is bool ? f['stock'] as bool : defaults.stock,
      p6Sync: f['p6Sync'] is bool ? f['p6Sync'] as bool : defaults.p6Sync,
    );
  }
}

class StoreFeaturesService {
  /// 마지막으로 받은 값 (84차 — 사이드바가 화면을 옮길 때 '주문 내역' 줄이 깜빡이지 않게 처음 값으로 씀)
  static StoreFeatures? last;

  /// 지금 매장의 기능 설정 (바뀌면 바로 반영, 읽기 실패 시 기본값)
  static Stream<StoreFeatures> watch() => StoreScope.doc
      .snapshots()
      .map((s) => last = StoreFeatures.fromStoreData(s.data()))
      .handleError((_) {});

  static Future<StoreFeatures> load() async {
    try {
      return StoreFeatures.fromStoreData((await StoreScope.doc.get()).data());
    } catch (_) {
      return StoreFeatures.defaults;
    }
  }

  /// 관리자 웹: 패드 관리자 대시보드 켜기·끄기 (서버 /api/store/features). 실패하면 [AdminLoginException]
  static Future<StoreFeatures> setAdminDashboard(bool on) => AdminSession.setStoreFeatures({'adminDashboard': on});
}
