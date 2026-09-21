import 'package:flutter/material.dart';
import 'food_order_screen.dart'; // 음식 주문 화면 불러오기
import 'game_list_screen.dart'; // 게임 목록 화면 불러오기
import 'game_tools_screen.dart'; // 게임 도구 화면 불러오기
import 'event_screen.dart'; // 이벤트 화면 불러오기
import 'notice_screen.dart'; // 공지 화면 불러오기
import '../widgets/custom_app_bar.dart'; // ★ 공통 상단 바 불러오기

class DashboardScreen extends StatefulWidget {
  final int? roomNumber; // 로그인에서 넘겨받을 방 번호

  const DashboardScreen({super.key, this.roomNumber});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchGame() {
    final query = _searchController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameListScreen(initialSearchQuery: query, roomNumber: widget.roomNumber),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), // 전체 배경색 통일
      body: SafeArea(
        child: Column(
          children: [
            // 1. 공통 상단 바 (CustomAppBar 위젯 사용)
            CustomAppBar(
              showBackButton: false,
              showCallButton: true,
              roomNumber: widget.roomNumber,
              centerWidget: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _searchGame(),
                  decoration: InputDecoration(
                    hintText: '게임이름으로 검색하기',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, color: Color(0xFF007E5B)),
                      onPressed: _searchGame,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            
            // 2. 메인 대시보드
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMenuCard(
                              context,
                              '어메이징한\n게임목록',
                              Colors.redAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => GameListScreen(roomNumber: widget.roomNumber)),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildMenuCard(
                              context,
                              '음식\n주문',
                              Colors.white,
                              textColor: Colors.black,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => FoodOrderScreen(roomNumber: widget.roomNumber)),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMenuCard(
                              context,
                              '이용안내',
                              const Color(0xFF2C3E50),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const NoticeScreen()),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildMenuCard(
                              context,
                              '이벤트',
                              const Color(0xFF2C3E50),
                              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EventScreen()),
                );
              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildMenuCard(
                              context,
                              '게임도구',
                              const Color(0xFF2C3E50),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const GameToolsScreen()),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, Color bgColor, {Color textColor = Colors.white, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))
          ],
        ),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor),
          ),
        ),
      ),
    );
  }

}