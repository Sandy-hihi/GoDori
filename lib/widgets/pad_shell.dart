import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/screens/event_screen.dart';
import 'package:boardpad/screens/food_order_screen.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/screens/game_tools_screen.dart';
import 'package:boardpad/screens/notice_screen.dart';
import 'package:boardpad/services/home_layout_service.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/home/home_view.dart';

/// 손님 패드 내부 화면(게임 목록·음식 주문·이벤트·이용안내·게임도구·일행과 함께) 공통 틀
///
/// 메인 화면(L 디자인)과 같은 왼쪽 사이드바 + 크림 배경 본문.
/// - 사이드바: 매장 로고(빠르게 10번 누르면 로그아웃 창 — 비밀번호 확인), 홈, 화면 이동 메뉴, 방 번호, 직원 호출, 전화번호
/// - 사이드바 색은 관리자 웹 '홈 화면 꾸미기'의 왼쪽 영역 색을 그대로 씀
/// - 본문: 제목 줄(제목 + 부제 + 오른쪽 부품) → headerBottom(탭·필터 등) → body
/// - rightPanel: 오른쪽에 붙는 고정 영역 (음식 주문의 장바구니)
class PadShell extends StatelessWidget {
  /// 메인 화면(DashboardScreen) 라우트 이름 — 홈 버튼이 여기까지 돌아감 (login_screen.dart에서 붙임)
  static const String homeRouteName = '/home';

  /// 손님 패드 앱의 Navigator (main.dart MaterialApp.navigatorKey) — 82차: 방 결제가 끝나면
  /// 화면 밖(order_ready_overlay.dart)에서 홈으로 돌려보낼 때 씀
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// 홈 화면까지 돌아감 (위에 뜬 창·내부 화면을 모두 닫음)
  static void goHome() {
    PadShell.navigatorKey.currentState?.popUntil(
      (r) => r.settings.name == PadShell.homeRouteName || r.isFirst,
    );
  }

  /// 지금 화면: 'games' | 'food' | 'tools' | 'event' | 'notice'
  /// ('party'는 일행과 함께 화면이 아직 쓰는 값 — 사이드바 메뉴에서는 뺌)
  final String current;
  final int? roomNumber;
  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget? headerBottom;
  final Widget body;
  final Widget? rightPanel;

  /// false면 사이드바 없이 본문만 (Firebase 없이 도는 위젯 테스트용)
  final bool showSidebar;

  const PadShell({
    super.key,
    required this.current,
    required this.title,
    required this.body,
    this.roomNumber,
    this.subtitle,
    this.headerTrailing,
    this.headerBottom,
    this.rightPanel,
    this.showSidebar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        // 사이드바가 홈과 같은 배율을 쓰도록 화면 전체 크기를 재서 넘겨줌
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSidebar)
                PadSidebar(
                  current: current,
                  roomNumber: roomNumber,
                  screen: constraints.biggest,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 26, 32, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GuestText(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: kInk,
                                  ),
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  GuestText(
                                    subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: kMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 82차: 언어 버튼은 사이드바(직원 호출 위)로 옮김 — 홈과 똑같은 사이드바
                          if (headerTrailing != null) ...[
                            const SizedBox(width: 16),
                            headerTrailing!,
                          ],
                        ],
                      ),
                    ),
                    if (headerBottom != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
                        child: headerBottom!,
                      ),
                    const SizedBox(height: 18),
                    Expanded(child: body),
                  ],
                ),
              ),
              ?rightPanel,
            ],
          ),
        ),
      ),
    );
  }
}

/// 내부 화면 왼쪽 사이드바 — 홈 화면의 왼쪽 영역(HomeSidebar)을 그대로, 홈과 같은 배율로 그림.
/// 사장님이 '홈 화면 꾸미기'에서 정한 요소·색을 따르고, 지금 화면 메뉴를 주황으로 표시.
class PadSidebar extends StatefulWidget {
  final String current;
  final int? roomNumber;
  final Size screen; // 화면 전체 크기 (홈과 같은 배율 계산용)
  const PadSidebar({
    super.key,
    required this.current,
    this.roomNumber,
    required this.screen,
  });

  @override
  State<PadSidebar> createState() => _PadSidebarState();
}

class _PadSidebarState extends State<PadSidebar> {
  // 화면을 옮겨도 깜빡이지 않게 마지막 배치를 기억
  static HomeLayout _last = HomeLayout.defaults();
  late final Stream<HomeLayout> _layout = HomeLayoutService.watch();

  @override
  Widget build(BuildContext context) {
    // 홈 화면(DashboardScreen)과 같은 기준 크기·배율 계산
    final screen = widget.screen;
    final design = HomeLayout.designSizeFor(screen);
    final scale = screen.height / design.height;
    return StreamBuilder<HomeLayout>(
      stream: _layout,
      initialData: _last,
      builder: (context, snap) {
        if (snap.data != null) _last = snap.data!;
        final layout = _last.forPadScreens();
        return SizedBox(
          width: HomeLayout.sidebarWidth * scale,
          height: screen.height,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: HomeLayout.sidebarWidth,
              height: design.height,
              child: HomeSidebar(
                layout: layout,
                roomNumber: widget.roomNumber,
                current: widget.current,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 사이드바 메뉴로 이동 (홈 화면·내부 화면 공통)
/// - current: 지금 화면 키 ('home' = 메인 화면)
/// - target: 'home' | linkTargets 키(games, food, recommended, event, notice, tools)
void padNavigate(
  BuildContext context,
  String target,
  String current,
  int? roomNumber,
) {
  if (target == current) return;
  if (target == 'home') {
    Navigator.popUntil(
      context,
      (r) => r.settings.name == PadShell.homeRouteName || r.isFirst,
    );
    return;
  }
  if (current == 'home') {
    openHomeTarget(context, target, roomNumber); // 홈 위에 쌓기
    return;
  }
  // 내부 화면끼리는 바꿔 끼우기 (쌓이지 않게)
  final page = target == 'recommended'
      ? GameListScreen(roomNumber: roomNumber, initialTab: '추천')
      : padPageFor(target, roomNumber);
  if (page != null) Navigator.pushReplacement(context, padRoute(page));
}

/// 사이드바 메뉴 키 → 화면
Widget? padPageFor(String key, int? roomNumber) {
  switch (key) {
    case 'games':
      return GameListScreen(roomNumber: roomNumber);
    case 'food':
      return FoodOrderScreen(roomNumber: roomNumber);
    case 'tools':
      return GameToolsScreen(roomNumber: roomNumber);
    case 'event':
      return EventScreen(roomNumber: roomNumber);
    case 'notice':
      return NoticeScreen(roomNumber: roomNumber);
  }
  return null;
}

// ── 내부 화면들이 같이 쓰는 작은 부품 ──

/// 알약 모양 선택 버튼 (탭·카테고리·장르)
class PadPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final double fontSize;

  const PadPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kInk : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? kInk : kLine)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: selected ? Colors.white : kBody),
                const SizedBox(width: 6),
              ],
              GuestText(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : kBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TabBar를 알약 모양으로 (DefaultTabController 아래에서 씀)
class PadTabBar extends StatelessWidget {
  final List<Tab> tabs;
  const PadTabBar({super.key, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: kLine),
        ),
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: kInk,
            borderRadius: BorderRadius.circular(24),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: kBody,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 22),
          splashBorderRadius: BorderRadius.circular(24),
          tabs: tabs,
        ),
      ),
    );
  }
}

/// 비어 있을 때 안내
class PadEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const PadEmpty({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, size: 40, color: kMuted),
          ),
          const SizedBox(height: 14),
          GuestText(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, color: kMuted),
          ),
        ],
      ),
    );
  }
}

/// 알림 띄우기 (색 통일)
void padSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.removeCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: GuestText(
        message,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      backgroundColor: error ? const Color(0xFFC0392B) : kInk,
      behavior: SnackBarBehavior.floating,
      width: 460,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
