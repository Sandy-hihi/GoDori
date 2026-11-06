import 'dart:async';

import 'package:flutter/material.dart';

import 'package:boardpad/services/store_features.dart';

/// 패드 관리자 대시보드(방 번호 0)를 감싸는 문 (59차)
/// 사장님이 관리자 웹 '매장 설정'에서 대시보드를 끄면, 이미 열려 있던 패드 대시보드도 바로 닫음
/// (닫히면 login_screen.dart가 로그아웃함). 새로 여는 건 서버가 막음(/api/auth/store-login → DASHBOARD_OFF)
class AdminPadGate extends StatefulWidget {
  /// 대시보드가 꺼져서 닫혔을 때 Navigator.pop 으로 돌려주는 값
  static const closedByOwner = 'dashboardOff';

  final Widget child;
  const AdminPadGate({super.key, required this.child});

  @override
  State<AdminPadGate> createState() => _AdminPadGateState();
}

class _AdminPadGateState extends State<AdminPadGate> {
  StreamSubscription<StoreFeatures>? _sub;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _sub = StoreFeaturesService.watch().listen((f) {
      if (f.adminDashboard || _closing || !mounted) return;
      _closing = true;
      // 대시보드 위에 떠 있는 창·화면까지 모두 닫고 로그인 화면으로
      final nav = Navigator.of(context);
      nav.popUntil((route) => route.settings.name == _gateRouteName || route.isFirst);
      if (nav.canPop()) nav.pop(AdminPadGate.closedByOwner);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// login_screen.dart가 대시보드를 열 때 붙이는 라우트 이름 (위 popUntil이 여기서 멈춤)
const _gateRouteName = 'admin-pad-dashboard';

/// 패드 관리자 대시보드 라우트 (이름을 붙여 두어야 대시보드가 꺼졌을 때 여기까지 닫힘)
MaterialPageRoute<Object?> adminPadRoute(Widget dashboard) => MaterialPageRoute<Object?>(
      settings: const RouteSettings(name: _gateRouteName),
      builder: (_) => AdminPadGate(child: dashboard),
    );
