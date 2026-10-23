import 'package:flutter/material.dart';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'food_order_screen.dart';
import 'game_list_screen.dart';
import 'game_tools_screen.dart';
import 'event_screen.dart';
import 'notice_screen.dart';

/// 손님용 메인 화면 — L 시안 (사이드바 + 사진 카드, 밝은 테마)
class DashboardScreen extends StatefulWidget {
  final int? roomNumber; // 로그인에서 넘겨받을 방 번호

  const DashboardScreen({super.key, this.roomNumber});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

const _ink = Color(0xFF26211C);
const _bg = Color(0xFFF4F0E8);
const _side = Color(0xFF2A2420);
const _sideText = Color(0xFFEFE8DC);
const _orange = Color(0xFFE2711D);
const _blue = Color(0xFF2459A8);
const _muted = Color(0xFF7A7266);

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _openGames({String? tab, String? genre, String? players, String? difficulty, String query = ''}) {
    _go(GameListScreen(
      roomNumber: widget.roomNumber,
      initialSearchQuery: query,
      initialTab: tab,
      initialGenre: genre,
      initialPlayers: players,
      initialDifficulty: difficulty,
    ));
  }

  String get _room => widget.roomNumber?.toString() ?? '-';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 28, 30, 26),
                child: Column(
                  children: [
                    _buildGreeting(),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _PhotoCard(
                                          image: 'assets/images/ui_food.jpg',
                                          title: '음식 주문하기',
                                          subtitle: '커피·하이볼·튀김을 자리에서 바로',
                                          background: const Color(0xFFFFF7EA),
                                          titleColor: _ink,
                                          subColor: const Color(0xFF6F665B),
                                          accent: _orange,
                                          shadow: const Color(0x143C2814),
                                          onTap: () => _go(FoodOrderScreen(roomNumber: widget.roomNumber)),
                                        ),
                                      ),
                                      const SizedBox(width: 18),
                                      Expanded(
                                        child: _PhotoCard(
                                          image: 'assets/images/ui_games.jpg',
                                          title: '게임 목록 보기',
                                          subtitle: '장르·인원·난이도로 찾고 룰 영상까지',
                                          background: const Color(0xFFEEF3FA),
                                          titleColor: const Color(0xFF1D2A44),
                                          subColor: const Color(0xFF56627A),
                                          accent: _blue,
                                          shadow: const Color(0x141E325A),
                                          onTap: () => _openGames(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(height: 60, child: _buildQuickRow()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(width: 262, child: _buildRightPanel()),
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

  // ── 왼쪽 사이드바 ──
  Widget _buildSidebar() {
    return Container(
      width: 196,
      color: _side,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
      child: Column(
        children: [
          HoldToExit(
            child: Column(
              children: [
                ClipOval(child: Image.asset('assets/images/logo.jpg', width: 76, height: 76, fit: BoxFit.cover)),
                const SizedBox(height: 10),
                const Text('플랫폼6 보드카페',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _sideText)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _navItem(Icons.home_rounded, '홈', selected: true, onTap: () {}),
          _navItem(Icons.card_giftcard_outlined, '이벤트', onTap: () => _go(const EventScreen())),
          _navItem(Icons.timer_outlined, '게임도구', onTap: () => _go(const GameToolsScreen())),
          _navItem(Icons.article_outlined, '이용안내', onTap: () => _go(const NoticeScreen())),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton.icon(
              onPressed: () => StaffCallService.callStaff(context, widget.roomNumber ?? 0),
              icon: const Icon(Icons.notifications_active),
              label: const Text('직원 호출', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const StorePhoneText(style: TextStyle(fontSize: 12, color: Color(0x8CEFE8DC))),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool selected = false, required VoidCallback onTap}) {
    final fg = selected ? _side : _sideText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? const Color(0xFFF4EBDC) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(width: 12),
                  Text(label,
                      style: TextStyle(
                          fontSize: 17, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 인사말 + 검색 ──
  Widget _buildGreeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('안녕하세요!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, color: _ink)),
              SizedBox(height: 4),
              Text('오늘도 즐거운 게임 시간 보내세요',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: _ink)),
            ],
          ),
        ),
        Container(
          width: 300,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [BoxShadow(color: Color(0x0F3C2814), blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: _ink, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (value) => _openGames(query: value.trim()),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 16, color: _ink),
                  decoration: const InputDecoration(
                    hintText: '게임 이름으로 검색',
                    hintStyle: TextStyle(color: Color(0xFF9A958C)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 바로가기 버튼 줄 ──
  Widget _buildQuickRow() {
    return Row(
      children: [
        Expanded(
          child: _quickButton(
            const Icon(Icons.star_rounded, color: _ink, size: 22),
            '추천 게임',
            () => _openGames(tab: '추천'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _quickButton(
            const Icon(Icons.groups_outlined, color: _ink, size: 22),
            '인원별',
            () => showFilterPicker(
              context: context,
              title: '몇 명이서 하세요?',
              options: Future.value(homePlayerOptions),
              onPick: (v) => _openGames(players: v),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _quickButton(
            const Icon(Icons.sell_outlined, color: _ink, size: 22),
            '장르별',
            () => showFilterPicker(
              context: context,
              title: '어떤 장르가 좋으세요?',
              options: loadGenres(),
              onPick: (v) => _openGames(genre: v),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _quickButton(
            const _DifficultyDots(),
            '난이도별',
            () => showFilterPicker(
              context: context,
              title: '난이도를 골라 주세요',
              options: Future.value(difficultyLabels),
              showDifficultyColors: true,
              onPick: (v) => _openGames(difficulty: v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickButton(Widget leading, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      ),
    );
  }

  // ── 오른쪽 정보 카드 ──
  Widget _buildRightPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: LiveClock(
            builder: (context, now) => Row(
              children: [
                const Icon(Icons.schedule, size: 34, color: _ink),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDateKo(now), style: const TextStyle(fontSize: 13, color: _muted)),
                    Text(formatTimeKo(now),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _ink)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(color: _side, borderRadius: BorderRadius.circular(22)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('지금 이용 중인 방', style: TextStyle(fontSize: 13, color: Color(0xA6F4EBDC))),
              Text('$_room번 룸',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Color(0xFFF4EBDC))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _infoCard(
            icon: Icons.campaign_outlined,
            iconColor: _orange,
            title: '공지사항',
            background: Colors.white,
            titleColor: _ink,
            body: const LatestItemTitle(
              docId: 'notices',
              emptyText: '등록된 공지가 없어요',
              maxLines: 3,
              style: TextStyle(fontSize: 15, color: Color(0xFF5C554B), height: 1.5),
            ),
            onTap: () => _go(const NoticeScreen()),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _infoCard(
            icon: Icons.card_giftcard_outlined,
            iconColor: const Color(0xFF6B3FC4),
            title: '진행 중인 이벤트',
            background: const Color(0xFFEFE7FB),
            titleColor: const Color(0xFF2E2346),
            body: const LatestItemTitle(
              docId: 'events',
              emptyText: '진행 중인 이벤트가 없어요',
              maxLines: 3,
              style: TextStyle(fontSize: 15, color: Color(0xFF4E4466), height: 1.5),
            ),
            onTap: () => _go(const EventScreen()),
          ),
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color background,
    required Color titleColor,
    required Widget body,
    required VoidCallback onTap,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: titleColor)),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF9A958C)),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// 사진이 위, 제목이 아래에 있는 큰 카드
class _PhotoCard extends StatelessWidget {
  final String image, title, subtitle;
  final Color background, titleColor, subColor, accent, shadow;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.titleColor,
    required this.subColor,
    required this.accent,
    required this.shadow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Material(
          color: background,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Image.asset(image, fit: BoxFit.cover)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 18, 22, 22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(title,
                                  style: TextStyle(
                                      fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: titleColor)),
                            ),
                            const SizedBox(height: 6),
                            Text(subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, color: subColor)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_forward, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DifficultyDots extends StatelessWidget {
  const _DifficultyDots();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [dot(const Color(0xFF23AC3A)), dot(const Color(0xFFF29700)), dot(const Color(0xFFD80051))],
    );
  }
}
