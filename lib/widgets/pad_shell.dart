import 'package:flutter/material.dart';

import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/screens/event_screen.dart';
import 'package:boardpad/screens/food_order_screen.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/screens/game_tools_screen.dart';
import 'package:boardpad/screens/notice_screen.dart';
import 'package:boardpad/services/home_layout_service.dart';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'package:boardpad/widgets/store_brand.dart';

/// 손님 패드 내부 화면(게임 목록·음식 주문·이벤트·이용안내·게임도구·일행과 함께) 공통 틀
///
/// 메인 화면(L 디자인)과 같은 왼쪽 사이드바 + 크림 배경 본문.
/// - 사이드바: 매장 로고(5초 누르면 첫 화면), 홈, 화면 이동 메뉴, 방 번호, 직원 호출, 전화번호
/// - 사이드바 색은 관리자 웹 '홈 화면 꾸미기'의 왼쪽 영역 색을 그대로 씀
/// - 본문: 제목 줄(제목 + 부제 + 오른쪽 부품) → headerBottom(탭·필터 등) → body
/// - rightPanel: 오른쪽에 붙는 고정 영역 (음식 주문의 장바구니)
class PadShell extends StatelessWidget {
  /// 메인 화면(DashboardScreen) 라우트 이름 — 홈 버튼이 여기까지 돌아감 (login_screen.dart에서 붙임)
  static const String homeRouteName = '/home';

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSidebar) PadSidebar(current: current, roomNumber: roomNumber),
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
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kInk)),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15, color: kMuted)),
                              ],
                            ],
                          ),
                        ),
                        if (headerTrailing != null) ...[const SizedBox(width: 16), headerTrailing!],
                      ],
                    ),
                  ),
                  if (headerBottom != null)
                    Padding(padding: const EdgeInsets.fromLTRB(32, 18, 32, 0), child: headerBottom!),
                  const SizedBox(height: 18),
                  Expanded(child: body),
                ],
              ),
            ),
            ?rightPanel,
          ],
        ),
      ),
    );
  }
}

/// 사이드바 메뉴 한 줄
class _NavEntry {
  final String key;
  final String label;
  final IconData icon;
  const _NavEntry(this.key, this.label, this.icon);
}

const List<_NavEntry> _navEntries = [
  _NavEntry('games', '게임 목록', Icons.casino_outlined),
  _NavEntry('food', '음식 주문', Icons.restaurant),
  _NavEntry('tools', '게임도구', Icons.timer_outlined),
  _NavEntry('event', '이벤트', Icons.card_giftcard_outlined),
  _NavEntry('notice', '이용안내', Icons.article_outlined),
];

/// 내부 화면 왼쪽 사이드바
class PadSidebar extends StatefulWidget {
  final String current;
  final int? roomNumber;
  const PadSidebar({super.key, required this.current, this.roomNumber});

  @override
  State<PadSidebar> createState() => _PadSidebarState();
}

class _PadSidebarState extends State<PadSidebar> {
  // 화면을 옮겨도 사이드바 색이 깜빡이지 않게 마지막 값을 기억
  static Color _lastColor = HomeLayout.defaults().sidebarColor;
  late final Stream<HomeLayout> _layout = HomeLayoutService.watch();

  void _goHome() {
    Navigator.popUntil(context, (r) => r.settings.name == PadShell.homeRouteName || r.isFirst);
  }

  void _open(String key) {
    if (key == widget.current) return;
    final page = padPageFor(key, widget.roomNumber);
    if (page == null) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HomeLayout>(
      stream: _layout,
      builder: (context, snap) {
        if (snap.data != null) _lastColor = snap.data!.sidebarColor;
        final color = _lastColor;
        final light = color.computeLuminance() > 0.5;
        final fg = light ? kInk : const Color(0xFFEFE8DC);
        final boxColor = fg.withValues(alpha: light ? 0.07 : 0.09);
        return Container(
          width: HomeLayout.sidebarWidth,
          color: color,
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HoldToExit(
                child: Column(
                  children: [
                    const StoreLogo(size: 56),
                    const SizedBox(height: 8),
                    StoreName(
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _navTile(icon: Icons.home_rounded, label: '홈', fg: fg, selected: false, onTap: _goHome),
              Divider(height: 14, thickness: 1, color: fg.withValues(alpha: 0.12)),
              for (final e in _navEntries)
                _navTile(
                  icon: e.icon,
                  label: e.label,
                  fg: fg,
                  selected: e.key == widget.current,
                  onTap: () => _open(e.key),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(Icons.meeting_room_outlined, size: 18, color: fg.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Text('${widget.roomNumber ?? '-'}번 룸',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => StaffCallService.callStaff(context, widget.roomNumber ?? 0),
                  icon: const Icon(Icons.notifications_active, size: 20),
                  label: const Text('직원 호출', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: StorePhoneText(style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.6)))),
            ],
          ),
        );
      },
    );
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required Color fg,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? kOrange : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 21, color: selected ? Colors.white : fg.withValues(alpha: 0.85)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? Colors.white : fg,
                        )),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
              Text(label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? Colors.white : kBody,
                  )),
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
          indicator: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(24)),
          labelColor: Colors.white,
          unselectedLabelColor: kBody,
          labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
            child: Icon(icon, size: 40, color: kMuted),
          ),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: kMuted)),
        ],
      ),
    );
  }
}

/// 알림 띄우기 (색 통일)
void padSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.removeCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    backgroundColor: error ? const Color(0xFFC0392B) : kInk,
    behavior: SnackBarBehavior.floating,
    width: 460,
    duration: const Duration(seconds: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ));
}
