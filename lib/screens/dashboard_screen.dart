import 'package:flutter/material.dart';
import 'food_order_screen.dart';
import 'game_list_screen.dart';
import 'game_tools_screen.dart';
import 'event_screen.dart';
import 'notice_screen.dart';
import '../widgets/custom_app_bar.dart';

class DashboardScreen extends StatefulWidget {
  final int? roomNumber;
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
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GameListScreen(initialSearchQuery: query, roomNumber: widget.roomNumber),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── 배경: 기차 내부 사진
          Positioned.fill(
            child: Image.asset(
              'assets/images/train_interior.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.08))),
          SafeArea(
            child: Column(
              children: [
                CustomAppBar(
                  showBackButton: false,
                  showCallButton: true,
                  roomNumber: widget.roomNumber,
                  centerWidget: _buildVintageSearchBar(),
                ),
                // ── 개별 이미지 버튼 영역
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      children: [
                        // 상단: 빨간 티켓(게임목록) + 크림박스(음식주문)
                        Expanded(
                          flex: 52,
                          child: Row(
                            children: [
                              // 게임목록 — 빨간 티켓
                              Expanded(
                                flex: 52,
                                child: GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => GameListScreen(roomNumber: widget.roomNumber))),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset('assets/images/ticket_red.png', fit: BoxFit.fill),
                                      Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6B1111).withOpacity(0.85),
                                                borderRadius: BorderRadius.circular(3),
                                                border: Border.all(color: const Color(0xFFE8C97A).withOpacity(0.7), width: 0.8),
                                              ),
                                              child: const Text('PLATFORM 6 · ADMIT ONE',
                                                style: TextStyle(color: Color(0xFFE8C97A), fontSize: 8.5, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text('어메이징한\n게임목록',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2,
                                                shadows: [Shadow(color: Colors.black87, blurRadius: 8), Shadow(color: Colors.black54, blurRadius: 16)])),
                                            const SizedBox(height: 6),
                                            Text('보드패드와 함께 바로 시작해 볼까요?',
                                              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.9),
                                                shadows: const [Shadow(color: Colors.black87, blurRadius: 5)])),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // 음식주문 — 크림 박스
                              Expanded(
                                flex: 48,
                                child: GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => FoodOrderScreen(roomNumber: widget.roomNumber))),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset('assets/images/cream_box.png', fit: BoxFit.fill),
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(28, 24, 24, 24),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text('음식 주문',
                                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF3B2507))),
                                            SizedBox(height: 6),
                                            Text('맛있는 음식과 함께 즐겨요!',
                                              style: TextStyle(fontSize: 11.5, color: Color(0xFF5C3A1E))),
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
                        const SizedBox(height: 10),
                        // 하단: 기차칸 3개
                        Expanded(
                          flex: 48,
                          child: Row(
                            children: [
                              _buildCarButton(
                                image: 'assets/images/car_a.png',
                                icon: Icons.help_outline_rounded,
                                title: '이용안내',
                                subtitle: 'FAQ/Notice',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticeScreen())),
                              ),
                              const SizedBox(width: 8),
                              _buildCarButton(
                                image: 'assets/images/car_b.png',
                                icon: Icons.casino_rounded,
                                title: '이벤트',
                                subtitle: 'Event',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EventScreen())),
                              ),
                              const SizedBox(width: 8),
                              _buildCarButton(
                                image: 'assets/images/car_c.png',
                                icon: Icons.timer_rounded,
                                title: '게임도구',
                                subtitle: 'Gaming Tools',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GameToolsScreen())),
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
        ],
      ),
    );
  }

  // ── 검색창 (흰색 배경)
  Widget _buildVintageSearchBar() {
    return SizedBox(
      height: 44,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFDDDDDD), width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: _searchController,
          onSubmitted: (_) => _searchGame(),
          style: const TextStyle(color: Color(0xFF333333), fontSize: 13),
          decoration: InputDecoration(
            hintText: '게임이름으로 검색하기',
            hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            suffixIcon: GestureDetector(
              onTap: _searchGame,
              child: const Icon(Icons.search, color: Color(0xFF666666), size: 20),
            ),
          ),
        ),
      ),
    );
  }






  // ── 기차칸 이미지 버튼
  Widget _buildCarButton({
    required String image,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(image, fit: BoxFit.contain, alignment: Alignment.bottomCenter),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.45),
                      border: Border.all(color: const Color(0xFFE8C97A).withOpacity(0.85), width: 1.8),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8)],
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 6), Shadow(color: Colors.black, blurRadius: 12)])),
                  const SizedBox(height: 2),
                  Text(subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 10,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 5)])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


}
