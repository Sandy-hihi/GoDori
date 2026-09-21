import 'package:flutter/material.dart';

/// currentScreen: 'menu' | 'game' | 'event' | 'notice'
class AdminSidebar extends StatelessWidget {
  final String currentScreen;
  final void Function(String screen) onNavigate;

  const AdminSidebar({super.key, required this.currentScreen, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: const Color(0xFF1E2B3C),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Text('보드패드 관리자',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const Divider(color: Colors.white24),
          _buildItem(Icons.restaurant_menu, '음식 메뉴 관리', 'menu'),
          _buildItem(Icons.casino, '보드게임 관리', 'game'),
          _buildItem(Icons.campaign, '이벤트 관리', 'event'),
          _buildItem(Icons.info_outline, '공지 관리', 'notice'),
        ],
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
