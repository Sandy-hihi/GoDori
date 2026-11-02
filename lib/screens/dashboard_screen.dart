import 'package:flutter/material.dart';
import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/services/home_layout_service.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/home/home_view.dart';

/// 손님용 메인 화면 — 사장님이 관리자 웹 "홈 화면 꾸미기"에서 저장한 배치대로 그림
/// (저장된 배치가 없으면 기본 배치). 1280×800 기준으로 그린 뒤 기기 화면에 맞춰 늘리거나 줄임
class DashboardScreen extends StatefulWidget {
  final int? roomNumber; // 로그인에서 넘겨받을 방 번호

  const DashboardScreen({super.key, this.roomNumber});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final Stream<HomeLayout> _layoutStream = HomeLayoutService.watch();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: StreamBuilder<HomeLayout>(
          stream: _layoutStream,
          initialData: HomeLayout.defaults(),
          builder: (context, snapshot) {
            final layout = snapshot.data ?? HomeLayout.defaults();
            // 화면 비율에 맞춘 크기로 그린 뒤 확대·축소 → 위아래·양옆 빈 띠 없이 꽉 참
            return LayoutBuilder(
              builder: (context, constraints) {
                final size = HomeLayout.designSizeFor(constraints.biggest);
                // FittedBox를 화면 크기에 딱 맞춰 둬야 기준보다 큰 화면에서도 늘려서 꽉 채움
                // (그냥 두면 작은 화면에서 줄이기만 하고 큰 화면에서는 원래 크기로 그려 빈 곳이 생김)
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: HomeView(layout: layout, roomNumber: widget.roomNumber, size: size),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
