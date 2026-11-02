import 'package:flutter/material.dart';
import 'package:boardpad/screens/admin_web_login_screen.dart';
import 'package:boardpad/services/admin_session.dart';

/// currentScreen: 'menu' | 'game' | 'event' | 'notice' | 'home' | 'store'
class AdminSidebar extends StatelessWidget {
  final String currentScreen;
  final void Function(String screen) onNavigate;

  const AdminSidebar({super.key, required this.currentScreen, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
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
          _buildItem(Icons.restaurant_menu, '음식 메뉴 관리', 'menu'),
          _buildItem(Icons.casino, '보드게임 관리', 'game'),
          _buildItem(Icons.campaign, '이벤트 관리', 'event'),
          _buildItem(Icons.info_outline, '공지 관리', 'notice'),
          _buildItem(Icons.dashboard_customize_outlined, '홈 화면 꾸미기', 'home'),
          _buildItem(Icons.storefront_outlined, '매장 설정', 'store'),
          const Spacer(),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white54),
            title: const Text('로그아웃', style: TextStyle(color: Colors.white54)),
            onTap: () async {
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
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }

  Widget _buildItem(IconData icon, String label, String screen) {
    final bool selected = currentScreen == screen;
    return ListTile(
      leading: Icon(icon, color: selected ? Colors.white : Colors.white54),
      title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white54)),
      selected: selected,
      selectedTileColor: Colors.white12,
      onTap: selected ? () {} : () => onNavigate(screen),
    );
  }
}
