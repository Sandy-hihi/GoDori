import 'package:flutter/material.dart';
import 'package:boardpad/screens/admin_web_login_screen.dart';
import 'package:boardpad/screens/admin_menu_manage_screen.dart';
import 'package:boardpad/screens/admin_game_manage_screen.dart';
import 'package:boardpad/screens/admin_event_manage_screen.dart';
import 'package:boardpad/screens/admin_notice_manage_screen.dart';
import 'package:boardpad/screens/admin_home_layout_screen.dart';
import 'package:boardpad/screens/admin_store_settings_screen.dart';
import 'package:boardpad/screens/admin_room_board_screen.dart';
import 'package:boardpad/services/admin_session.dart';

/// currentScreen: 'menu' | 'game' | 'event' | 'notice' | 'home' | 'store' | 'rooms'
/// 112차: 'rooms'(방 현황판)는 사이드바가 직접 엶(AdminSidebar.go) — (룰 영상 통계는 운영자 페이지로 옮김)
/// 예전 화면들의 onNavigate 목록을 고치지 않아도 되게. 새 화면은 onNavigate에 AdminSidebar.go를 넘김
class AdminSidebar extends StatelessWidget {
  final String currentScreen;
  final void Function(String screen) onNavigate;

  const AdminSidebar({super.key, required this.currentScreen, required this.onNavigate});

  static const _selfOpened = {'rooms'};

  /// 관리자 웹 화면 바꾸기 (애니메이션 없이 바꿔 끼움)
  static void go(BuildContext context, String screen) {
    final Widget? target = switch (screen) {
      'menu' => const AdminMenuManageScreen(),
      'game' => const AdminGameManageScreen(),
      'event' => const AdminEventManageScreen(),
      'notice' => const AdminNoticeManageScreen(),
      'home' => const AdminHomeLayoutScreen(),
      'store' => const AdminStoreSettingsScreen(),
      'rooms' => const AdminRoomBoardScreen(),
      _ => null,
    };
    if (target == null) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _open(BuildContext context, String screen) =>
      _selfOpened.contains(screen) ? go(context, screen) : onNavigate(screen);

  // 화면 폭이 이보다 좁으면(폰·아이패드 세로) 글자 없는 아이콘 줄(64px)로 접음 (81차)
  static const double compactBelow = 900;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < compactBelow) return _buildRail(context);
    // ListTile의 선택 배경·클릭 효과가 보이도록 Container(color) 대신 Material로 배경을 칠함
    return Material(
      color: const Color(0xFF1E2B3C),
      child: SizedBox(
      width: 250,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('고도리 관리자',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const Divider(color: Colors.white24),
          // 112차: 메뉴가 늘어서 화면이 낮으면 넘치지 않게 스크롤
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
              _buildItem(Icons.restaurant_menu, '음식 메뉴 관리', 'menu'),
              _buildItem(Icons.casino, '보드게임 관리', 'game'),
              _buildItem(Icons.campaign, '이벤트 관리', 'event'),
              _buildItem(Icons.info_outline, '공지 관리', 'notice'),
              _buildItem(Icons.dashboard_customize_outlined, '홈 화면 꾸미기', 'home'),
              _buildItem(Icons.storefront_outlined, '매장 설정', 'store'),
              const Divider(color: Colors.white24),
              _buildItem(Icons.meeting_room_outlined, '방 현황판', 'rooms'),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white54),
            title: const Text('로그아웃', style: TextStyle(color: Colors.white54)),
            onTap: () => _logout(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await AdminSession.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AdminWebLoginScreen(),
        transitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  // 좁은 화면용: 아이콘만 세로로 (길게 누르면 이름 표시)
  Widget _buildRail(BuildContext context) {
    Widget item(IconData icon, String label, String screen) {
      final bool selected = currentScreen == screen;
      return Tooltip(
        message: label,
        child: Material(
          color: selected ? Colors.white12 : Colors.transparent,
          child: InkWell(
            onTap: selected ? null : () => _open(context, screen),
            child: SizedBox(
              height: 56,
              child: Center(child: Icon(icon, color: selected ? Colors.white : Colors.white54)),
            ),
          ),
        ),
      );
    }

    return Material(
      color: const Color(0xFF1E2B3C),
      child: SizedBox(
        width: 64,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Text('고도리', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                  item(Icons.restaurant_menu, '음식 메뉴 관리', 'menu'),
                  item(Icons.casino, '보드게임 관리', 'game'),
                  item(Icons.campaign, '이벤트 관리', 'event'),
                  item(Icons.info_outline, '공지 관리', 'notice'),
                  item(Icons.dashboard_customize_outlined, '홈 화면 꾸미기', 'home'),
                  item(Icons.storefront_outlined, '매장 설정', 'store'),
                  const Divider(color: Colors.white24, height: 1),
                  item(Icons.meeting_room_outlined, '방 현황판', 'rooms'),
                      ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Tooltip(
                message: '로그아웃',
                child: InkWell(
                  onTap: () => _logout(context),
                  child: const SizedBox(height: 56, child: Center(child: Icon(Icons.logout, color: Colors.white54))),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(IconData icon, String label, String screen) {
    final bool selected = currentScreen == screen;
    return Builder(
      builder: (context) => ListTile(
        leading: Icon(icon, color: selected ? Colors.white : Colors.white54),
        title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white54)),
        selected: selected,
        selectedTileColor: Colors.white12,
        onTap: selected ? () {} : () => _open(context, screen),
      ),
    );
  }
}
