import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/services/staff_call_service.dart';

class GameListScreen extends StatefulWidget {
  final String initialSearchQuery;
  final int? roomNumber;

  const GameListScreen({super.key, this.initialSearchQuery = '', this.roomNumber});

  @override
  State<GameListScreen> createState() => _GameListScreenState();
}

class _GameListScreenState extends State<GameListScreen> {
  String selectedTab = '전체';
  String selectedGenre = '전체';
  String searchQuery = '';
  late TextEditingController _searchController;

  String? selectedPlayers;
  String? selectedTime;
  String? selectedDifficulty;

  int currentPage = 1;
  final int itemsPerPage = 10;

  Future<QuerySnapshot>? _gamesFuture;
  StreamSubscription? _refreshSubscription;
  bool _isInitialRefreshLoad = true;

  final List<String> playerOptions = ['2인전용', '2인이상', '3인이상', '4인이상', '5인이상', '6인이상'];
  final List<String> timeOptions = ['15분 이하', '15분 ~ 30분', '30분 ~ 1시간', '1시간 이상'];
  final List<String> difficultyOptions = ['매우쉬움', '쉬움', '보통', '어려움', '매우어려움', '전문'];

  @override
  void initState() {
    super.initState();
    searchQuery = widget.initialSearchQuery;
    _searchController = TextEditingController(text: widget.initialSearchQuery);
    _gamesFuture = _fetchGames();
    _listenForRemoteRefresh();
  }

  // 관리자가 settings/appRefresh 문서의 gamesUpdatedAt을 바꾸면 자동 재로딩
  void _listenForRemoteRefresh() {
    _refreshSubscription = FirebaseFirestore.instance
        .collection('settings')
        .doc('appRefresh')
        .snapshots()
        .listen((doc) {
      if (_isInitialRefreshLoad) {
        _isInitialRefreshLoad = false;
        return;
      }
      if (mounted) {
        setState(() {
          _gamesFuture = _fetchGames();
        });
      }
    });
  }

  // 게임 목록 1회성 읽기 (실시간 구독 없음 → Firestore 읽기 횟수 최소화)
  Future<QuerySnapshot> _fetchGames() {
    return FirebaseFirestore.instance
        .collection('games')
        .where('isAvailable', isEqualTo: true)
        .get();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshSubscription?.cancel();
    super.dispose();
  }

  // 인원 필터 로직: "2인전용" = 최대 2명, "N인이상" = 최대 인원 >= N
  bool _matchesPlayerFilter(String? playersStr, String? filter) {
    if (filter == null) return true;
    if (playersStr == null || playersStr.isEmpty) return true;
    final regex = RegExp(r'(\d+)');
    final matches = regex.allMatches(playersStr).toList();
    if (matches.isEmpty) return true;

    if (filter == '2인전용') {
      final nums = matches.map((m) => int.parse(m.group(1)!)).toList();
      if (nums.length == 1) return nums[0] == 2;
      return nums.first == 2 && nums.last == 2;
    } else {
      final filterNum = int.tryParse(filter.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final maxPlayers = int.parse(matches.last.group(1)!);
      return maxPlayers >= filterNum;
    }
  }

  // 소요시간 문자열을 분(int)으로 변환
  int _parseMinutes(String timeStr) {
    int total = 0;
    final hourMatch = RegExp(r'(\d+)\s*시간').firstMatch(timeStr);
    final minMatch = RegExp(r'(\d+)\s*분').firstMatch(timeStr);
    if (hourMatch != null) total += int.parse(hourMatch.group(1)!) * 60;
    if (minMatch != null) total += int.parse(minMatch.group(1)!);
    return total;
  }

  // 소요시간 범위 필터 로직
  bool _matchesTimeFilter(String? timeStr, String? filter) {
    if (filter == null) return true;
    if (timeStr == null || timeStr.isEmpty) return true;
    final minutes = _parseMinutes(timeStr);
    if (minutes == 0) return true;
    switch (filter) {
      case '15분 이하': return minutes <= 15;
      case '15분 ~ 30분': return minutes > 15 && minutes <= 30;
      case '30분 ~ 1시간': return minutes > 30 && minutes <= 60;
      case '1시간 이상': return minutes > 60;
      default: return true;
    }
  }



  Future<void> _launchVideo(BuildContext context, String? urlString) async {
    if (urlString == null || urlString.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 영상 링크가 없습니다.'), backgroundColor: Colors.orange),
      );
      return;
    }
    String finalUrl = urlString.trim();
    if (!finalUrl.startsWith('http')) finalUrl = 'https://$finalUrl';
    final Uri url = Uri.parse(finalUrl);
    try {
      await launchUrl(url);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('영상을 실행할 수 없습니다. 링크를 확인해주세요.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 공통 상단 바 (초록색)
            Container(
              color: const Color(0xFF00B37E),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ClipOval(child: Image.asset('assets/images/logo.jpg', width: 40, height: 40, fit: BoxFit.cover)),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                            currentPage = 1;
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: '게임이름으로 검색하기',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => StaffCallService.callStaff(context, widget.roomNumber ?? 0),
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('직원 호출', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007E5B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                  const Spacer(),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('플랫폼6 보드카페', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('010-5519-1525', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // 2. 장르 선택 칩 영역 (Firestore 실시간 연동)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('settings').doc('genres').snapshots(),
              builder: (context, genreSnap) {
                final List<String> genreList = (genreSnap.hasData && genreSnap.data!.exists)
                    ? List<String>.from((genreSnap.data!.data() as Map? ?? {})['items'] ?? [])
                    : [];
                final List<String> allGenres = ['전체', ...genreList];
                // 선택된 장르가 목록에 없으면 '전체'로 리셋
                if (!allGenres.contains(selectedGenre)) selectedGenre = '전체';
                return Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('장르', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(width: 16),
                        ...allGenres.map((genre) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(genre),
                            selected: selectedGenre == genre,
                            onSelected: (bool selected) {
                              setState(() {
                                selectedGenre = genre;
                                currentPage = 1;
                              });
                            },
                            selectedColor: const Color(0xFF00B37E),
                            labelStyle: TextStyle(color: selectedGenre == genre ? Colors.white : Colors.black),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        )),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 1),

            // 3. FutureBuilder: 필터바 + 게임 리스트 + 페이지네이션
            // .get() 1회성 읽기 → 실시간 구독 없음, Firestore 읽기 비용 최소화
            // 관리자가 게임을 수정해도 손님 태블릿에서 자동 재읽기 없음
            Expanded(
              child: FutureBuilder<QuerySnapshot>(
                future: _gamesFuture,
                builder: (context, snapshot) {
                  return Column(
                    children: [
                      // 필터 바 (전체/추천 탭 + 3개 드롭다운 + 새로고침 버튼)
                      Container(
                        color: const Color(0xFF2C3E50),
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: [
                            _buildTabButton('전체'),
                            _buildTabButton('추천'),
                            const Spacer(),
                            _buildDropdown('인원', selectedPlayers, playerOptions, (val) {
                              setState(() { selectedPlayers = val; currentPage = 1; });
                            }),
                            const SizedBox(width: 8),
                            _buildDropdown('소요시간', selectedTime, timeOptions, (val) {
                              setState(() { selectedTime = val; currentPage = 1; });
                            }),
                            const SizedBox(width: 8),
                            _buildDropdown('난이도', selectedDifficulty, difficultyOptions, (val) {
                              setState(() { selectedDifficulty = val; currentPage = 1; });
                            }),

                          ],
                        ),
                      ),

                      // 게임 리스트 영역
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Expanded(child: Center(child: CircularProgressIndicator()))
                      else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty)
                        const Expanded(child: Center(child: Text('등록된 보드게임이 없습니다.')))
                      else
                        _buildGameList(snapshot.data!.docs),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 게임 리스트 + 페이지네이션
  Widget _buildGameList(List<QueryDocumentSnapshot> allDocs) {
    // timestamp 기준 내림차순 클라이언트 정렬 (Firestore 복합 인덱스 불필요)
    final sortedDocs = List<QueryDocumentSnapshot>.from(allDocs)
      ..sort((a, b) {
        final aTs = (a.data() as Map<String, dynamic>)['timestamp'];
        final bTs = (b.data() as Map<String, dynamic>)['timestamp'];
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return (bTs as Timestamp).compareTo(aTs as Timestamp);
      });

    // 필터링
    final filteredGames = sortedDocs.where((doc) {
      final game = doc.data() as Map<String, dynamic>;
      // isAvailable 필터는 Firestore 쿼리에서 서버 사이드로 처리됨
      final bool isRecommended = game['isRecommended'] == true;
      final bool matchesTab = selectedTab == '전체' || (selectedTab == '추천' && isRecommended);
      final bool matchesGenre = selectedGenre == '전체' || game['genre'] == selectedGenre;
      final bool matchesSearch = (game['title'] ?? '').toString().toLowerCase().contains(searchQuery.toLowerCase());
      final bool matchesPlayers = _matchesPlayerFilter(game['players']?.toString(), selectedPlayers);
      final bool matchesTime = _matchesTimeFilter(game['time']?.toString(), selectedTime);
      final bool matchesDifficulty = selectedDifficulty == null || game['difficulty'] == selectedDifficulty;

      return matchesTab && matchesGenre && matchesSearch && matchesPlayers && matchesTime && matchesDifficulty;
    }).toList();

    if (filteredGames.isEmpty) {
      return const Expanded(child: Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.grey))));
    }

    final int totalPages = (filteredGames.length + itemsPerPage - 1) ~/ itemsPerPage;
    final int safePage = currentPage > totalPages ? totalPages : currentPage;
    final int startIndex = (safePage - 1) * itemsPerPage;
    final int endIndex = (startIndex + itemsPerPage > filteredGames.length) ? filteredGames.length : startIndex + itemsPerPage;
    final paginatedGames = filteredGames.sublist(startIndex, endIndex);

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16.0),
              itemCount: paginatedGames.length,
              separatorBuilder: (context, index) => const Divider(height: 32),
              itemBuilder: (context, index) {
                final doc = paginatedGames[index];
                final game = doc.data() as Map<String, dynamic>;
                final bool isRecommended = game['isRecommended'] == true;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 썸네일 이미지
                    Stack(
                      children: [
                        Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                          clipBehavior: Clip.hardEdge,
                          child: (hasValidImage(game['imageUrl']))
                              ? CachedNetworkImage(imageUrl: game['imageUrl'], fit: BoxFit.cover, errorWidget: (c,u,e) => const Icon(Icons.image, size: 40, color: Colors.grey))
                              : const Icon(Icons.image, size: 40, color: Colors.grey),
                        ),
                        if (isRecommended)
                          Positioned(
                            top: 4, right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                              child: const Text('추천', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // 게임 정보 텍스트
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(game['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(game['players'] ?? '', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                          const SizedBox(height: 4),
                          Text(game['tags'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.blueAccent)),
                        ],
                      ),
                    ),

                    // 아이콘 정보
                    Row(
                      children: [
                        _buildInfoIcon(Icons.theater_comedy, '게임장르', game['genre'] ?? ''),
                        _buildInfoIcon(Icons.timer, '소요시간', game['time'] ?? ''),
                        _buildInfoIcon(Icons.people, '인원', game['players'] ?? ''),
                        _buildInfoIcon(Icons.star, '난이도', game['difficulty'] ?? ''),
                      ],
                    ),
                    const SizedBox(width: 24),

                    // 설명영상 버튼
                    ElevatedButton.icon(
                      onPressed: () => _launchVideo(context, game['videoUrl']),
                      icon: const Icon(Icons.play_circle_fill),
                      label: const Text('설명영상', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007E5B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // 하단 페이지 번호
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Builder(builder: (context) {
                final int pagesPerBlock = 10;
                final int currentBlock = (safePage - 1) ~/ pagesPerBlock;
                final int startPage = currentBlock * pagesPerBlock + 1;
                final int endPage = (startPage + pagesPerBlock - 1 > totalPages) ? totalPages : startPage + pagesPerBlock - 1;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (startPage > 1)
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.black54),
                        onPressed: () => setState(() => currentPage = startPage - 1),
                      ),
                    Wrap(
                      spacing: 4.0,
                      children: List.generate(endPage - startPage + 1, (index) {
                        int page = startPage + index;
                        return ElevatedButton(
                          onPressed: () => setState(() => currentPage = page),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: safePage == page ? const Color(0xFF00B37E) : Colors.transparent,
                            foregroundColor: safePage == page ? Colors.white : Colors.black87,
                            elevation: 0,
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text('$page', style: TextStyle(fontWeight: safePage == page ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
                        );
                      }),
                    ),
                    if (endPage < totalPages)
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.black54),
                        onPressed: () => setState(() => currentPage = endPage + 1),
                      ),
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }

  // 상단 탭 버튼
  Widget _buildTabButton(String title) {
    bool isSelected = selectedTab == title;
    return GestureDetector(
      onTap: () => setState(() { selectedTab = title; currentPage = 1; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00B37E) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  // 필터 드롭다운 (해제 가능)
  Widget _buildDropdown(String hint, String? currentValue, List<String> items, void Function(String?) onChanged) {
    final safeValue = (currentValue != null && items.contains(currentValue)) ? currentValue : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          hint: Text(hint),
          value: safeValue,
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('전체 $hint')),
            ...items.map((item) => DropdownMenuItem<String?>(value: item, child: Text(item))),
          ],
          onChanged: onChanged,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ),
    );
  }

  // 게임 상세 정보 아이콘
  Widget _buildInfoIcon(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          CircleAvatar(backgroundColor: Colors.grey.shade200, radius: 24, child: Icon(icon, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
