import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';
import 'package:boardpad/widgets/rule_video_player.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/usage_meter.dart';

class GameListScreen extends StatefulWidget {
  final String initialSearchQuery;
  final int? roomNumber;
  // 메인 화면 바로가기에서 미리 걸어 둘 필터 (없으면 전체)
  final String? initialTab;
  final String? initialGenre;
  final String? initialPlayers;
  final String? initialDifficulty;

  const GameListScreen({
    super.key,
    this.initialSearchQuery = '',
    this.roomNumber,
    this.initialTab,
    this.initialGenre,
    this.initialPlayers,
    this.initialDifficulty,
  });

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

  // ── 가나다순 인피니티 스크롤(끝에서 다시 처음으로) + 왼쪽 초성 줄 ──
  final ScrollController _scroll = ScrollController();
  List<String> _railGroups = []; // 지금 목록에 있는 초성 (순서대로)
  Map<String, int> _groupFirstRow = {}; // 초성 → 처음 나오는 줄 번호 (한 바퀴 안)
  List<String> _rowGroup = []; // 줄 번호 → 그 줄 첫 게임의 초성
  double _cycleH = 0; // 한 바퀴(전체 게임 + '처음으로' 표시) 높이
  // 스크롤 중 바뀌는 값은 따로 두어 목록 전체를 다시 그리지 않음 (부드러운 스크롤)
  final ValueNotifier<String?> _currentGroup = ValueNotifier(null);
  final ValueNotifier<bool> _railVisible = ValueNotifier(false);
  bool _railHeld = false; // 초성 줄을 누르고 있는 동안은 숨기지 않음
  bool _jumping = false;
  Timer? _railTimer;

  // 필터·정렬 결과 보관 (데이터나 필터가 바뀔 때만 다시 계산)
  Object? _sortedKey;
  List<Map<String, dynamic>> _sortedGames = [];
  List<String> _sortedGroups = [];

  static const double _cardH = 300;
  static const double _gap = 16;
  static const double _rowStride = _cardH + _gap;
  static const double _loopMarkH = 72;

  Future<QuerySnapshot>? _gamesFuture;
  StreamSubscription? _refreshSubscription;
  bool _isInitialRefreshLoad = true;
  late final Stream<DocumentSnapshot> _genreStream =
      StoreScope.col('settings').doc('genres').snapshots();

  final List<String> playerOptions = ['2인전용', '2인이상', '3인이상', '4인이상', '5인이상', '6인이상'];
  final List<String> timeOptions = ['15분 이하', '15분 ~ 30분', '30분 ~ 1시간', '1시간 이상'];
  final List<String> difficultyOptions = ['매우쉬움', '쉬움', '보통', '어려움', '매우어려움', '전문'];

  @override
  void initState() {
    super.initState();
    searchQuery = widget.initialSearchQuery;
    selectedTab = widget.initialTab ?? '전체';
    selectedGenre = widget.initialGenre ?? '전체';
    selectedPlayers = widget.initialPlayers;
    selectedDifficulty = widget.initialDifficulty;
    _searchController = TextEditingController(text: widget.initialSearchQuery);
    _gamesFuture = _fetchGames();
    _listenForRemoteRefresh();
  }

  // 관리자가 settings/appRefresh 문서의 gamesUpdatedAt을 바꾸면 자동 재로딩
  void _listenForRemoteRefresh() {
    _refreshSubscription = StoreScope.col('settings')
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
    return StoreScope.col('games').where('isAvailable', isEqualTo: true).get().metered();
  }

  @override
  void dispose() {
    _railTimer?.cancel();
    _scroll.dispose();
    _currentGroup.dispose();
    _railVisible.dispose();
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
      case '15분 이하':
        return minutes <= 15;
      case '15분 ~ 30분':
        return minutes > 15 && minutes <= 30;
      case '30분 ~ 1시간':
        return minutes > 30 && minutes <= 60;
      case '1시간 이상':
        return minutes > 60;
      default:
        return true;
    }
  }

  // 룰 영상: 매장 영상이 있으면 앱 안에서, 없으면 유튜브 (rule_video_player.dart)
  Future<void> _launchVideo(BuildContext context, Map<String, dynamic> game) => openRuleVideo(context, game);

  // 필터·검색이 바뀌면 목록 맨 위로
  void _resetPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  // 스크롤 위치 → 지금 맨 위 줄의 초성 (몇 바퀴째든 한 바퀴 안 위치로)
  void _updateCurrentGroup() {
    if (_jumping || _rowGroup.isEmpty || _cycleH <= 0 || !_scroll.hasClients) return;
    final within = (_scroll.offset + 24) % _cycleH;
    final row = (within / _rowStride).floor().clamp(0, _rowGroup.length - 1).toInt();
    _currentGroup.value = _rowGroup[row];
  }

  // 스크롤하면 초성 줄을 보여 주고, 멈추고 1.2초 뒤 숨김
  void _showRail() {
    _railTimer?.cancel();
    _railVisible.value = true;
    _railTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && !_railHeld) _railVisible.value = false;
    });
  }

  // 초성을 누르면 지금 바퀴 안에서 그 초성의 첫 게임 줄로 이동
  void _jumpToGroup(String g, {bool animate = true}) {
    final row = _groupFirstRow[g];
    if (row == null || _cycleH <= 0 || !_scroll.hasClients) return;
    _currentGroup.value = g;
    final base = (_scroll.offset / _cycleH).floor() * _cycleH;
    final target = base + row * _rowStride;
    if (!animate) {
      _scroll.jumpTo(target);
      return;
    }
    _jumping = true;
    _scroll
        .animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)
        .whenComplete(() => _jumping = false);
  }

  // 필터 + 가나다순 정렬 (같은 데이터·같은 필터면 이전 결과 재사용)
  void _sortAndFilter(QuerySnapshot data) {
    // docs는 부를 때마다 새 목록이라, 받아 온 결과(QuerySnapshot) 자체로 같은지 봄
    final key = Object.hash(identityHashCode(data), selectedTab, selectedGenre, searchQuery, selectedPlayers,
        selectedTime, selectedDifficulty);
    if (key == _sortedKey) return;
    _sortedKey = key;

    // _docId: 룰 영상(R2) 재생 주소를 서버에서 받을 때 씀
    final filtered = data.docs.map((d) => <String, dynamic>{...d.data() as Map<String, dynamic>, '_docId': d.id}).where((game) {
      // isAvailable 필터는 Firestore 쿼리에서 서버 사이드로 처리됨
      final bool isRecommended = game['isRecommended'] == true;
      final bool matchesTab = selectedTab == '전체' || (selectedTab == '추천' && isRecommended);
      final bool matchesGenre = selectedGenre == '전체' || gameGenres(game).contains(selectedGenre); // 장르 여러 개 지원
      final bool matchesSearch = (game['title'] ?? '').toString().toLowerCase().contains(searchQuery.toLowerCase());
      final bool matchesPlayers = _matchesPlayerFilter(game['players']?.toString(), selectedPlayers);
      final bool matchesTime = _matchesTimeFilter(game['time']?.toString(), selectedTime);
      final bool matchesDifficulty = selectedDifficulty == null || game['difficulty'] == selectedDifficulty;
      return matchesTab && matchesGenre && matchesSearch && matchesPlayers && matchesTime && matchesDifficulty;
    }).toList();

    // 가나다순: 초성 묶음(ㄱ~ㅎ, 영문, 숫자·기호) 순서 → 같은 묶음 안에서는 이름순
    final titles = [for (final g in filtered) (g['title'] ?? '').toString().trim()];
    final groups = [for (final t in titles) initialGroupOf(t)];
    final order = List<int>.generate(filtered.length, (i) => i)
      ..sort((a, b) {
        final ga = initialGroups.indexOf(groups[a]), gb = initialGroups.indexOf(groups[b]);
        if (ga != gb) return ga.compareTo(gb);
        return titles[a].toLowerCase().compareTo(titles[b].toLowerCase());
      });
    _sortedGames = [for (final i in order) filtered[i]];
    _sortedGroups = [for (final i in order) groups[i]];
  }

  bool get _hasFilters =>
      selectedPlayers != null ||
      selectedTime != null ||
      selectedDifficulty != null ||
      selectedGenre != '전체' ||
      searchQuery.isNotEmpty;

  void _clearFilters() {
    setState(() {
      selectedPlayers = null;
      selectedTime = null;
      selectedDifficulty = null;
      selectedGenre = '전체';
      searchQuery = '';
      _searchController.clear();
      _resetPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PadShell(
      current: 'games',
      roomNumber: widget.roomNumber,
      title: '게임 목록',
      subtitle: '눌러서 자세히 보고, 룰 영상도 볼 수 있어요',
      headerTrailing: _searchBox(),
      headerBottom: _filters(),
      body: FutureBuilder<QuerySnapshot>(
        future: _gamesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kOrange));
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const PadEmpty(icon: Icons.casino_outlined, text: '등록된 보드게임이 없어요.');
          }
          return _buildGameList(snapshot.data!);
        },
      ),
    );
  }

  // 오른쪽 위 검색창
  Widget _searchBox() {
    return SizedBox(
      width: 340,
      height: 50,
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() {
          searchQuery = value;
          _resetPage();
        }),
        style: const TextStyle(fontSize: 16, color: kInk),
        decoration: InputDecoration(
          hintText: '게임 이름으로 검색',
          hintStyle: const TextStyle(color: kMuted),
          prefixIcon: const Icon(Icons.search, color: kMuted),
          suffixIcon: searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: kMuted),
                  onPressed: () => setState(() {
                    searchQuery = '';
                    _searchController.clear();
                    _resetPage();
                  }),
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: const BorderSide(color: kLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: const BorderSide(color: kOrange, width: 2),
          ),
        ),
      ),
    );
  }

  // 전체/추천 + 인원·시간·난이도 + 장르
  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PadPill(
              label: '전체',
              icon: Icons.apps_rounded,
              selected: selectedTab == '전체',
              onTap: () => setState(() {
                selectedTab = '전체';
                _resetPage();
              }),
            ),
            const SizedBox(width: 8),
            PadPill(
              label: '직원 추천',
              icon: Icons.star_rounded,
              selected: selectedTab == '추천',
              onTap: () => setState(() {
                selectedTab = '추천';
                _resetPage();
              }),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 28, color: kLine),
            const SizedBox(width: 16),
            _buildDropdown('인원', Icons.people_alt_outlined, selectedPlayers, playerOptions, (val) {
              setState(() {
                selectedPlayers = val;
                _resetPage();
              });
            }),
            const SizedBox(width: 8),
            _buildDropdown('소요시간', Icons.schedule, selectedTime, timeOptions, (val) {
              setState(() {
                selectedTime = val;
                _resetPage();
              });
            }),
            const SizedBox(width: 8),
            _buildDropdown('난이도', Icons.signal_cellular_alt, selectedDifficulty, difficultyOptions, (val) {
              setState(() {
                selectedDifficulty = val;
                _resetPage();
              });
            }),
            const Spacer(),
            if (_hasFilters)
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('필터 초기화', style: TextStyle(fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(foregroundColor: kMuted),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 장르 (Firestore 실시간 연동)
        StreamBuilder<DocumentSnapshot>(
          stream: _genreStream,
          builder: (context, genreSnap) {
            final List<String> genreList = (genreSnap.hasData && genreSnap.data!.exists)
                ? List<String>.from((genreSnap.data!.data() as Map? ?? {})['items'] ?? [])
                : [];
            final List<String> allGenres = ['전체', ...genreList];
            // 선택된 장르가 목록에 없으면 '전체'로 리셋
            if (!allGenres.contains(selectedGenre)) selectedGenre = '전체';
            return SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final genre in allGenres)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _genreChip(genre),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _genreChip(String genre) {
    final selected = selectedGenre == genre;
    return Material(
      color: selected ? kOrange.withValues(alpha: 0.14) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? kOrange : Colors.transparent)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() {
          selectedGenre = genre;
          _resetPage();
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            genre == '전체' ? '# 모든 장르' : '# $genre',
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? kOrange : kBody,
            ),
          ),
        ),
      ),
    );
  }

  // 게임 카드 목록 — 가나다순, 끝까지 내리면 다시 처음부터 (끝없이 반복)
  Widget _buildGameList(QuerySnapshot data) {
    _sortAndFilter(data);
    final games = _sortedGames;
    final gameGroups = _sortedGroups;

    if (games.isEmpty) {
      return const PadEmpty(icon: Icons.search_off, text: '조건에 맞는 게임이 없어요.\n필터를 바꿔 보세요.');
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 10),
          child: Row(
            children: [
              Text('${games.length}개의 게임 · 가나다순',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kMuted)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const padL = 32.0, padR = 32.0;
              final usable = constraints.maxWidth - padL - padR;
              final cols = ((usable + _gap) / (300 + _gap)).floor().clamp(2, 6).toInt();
              final cardW = (usable - _gap * (cols - 1)) / cols;
              final cacheW = (cardW * MediaQuery.devicePixelRatioOf(context)).round();

              // 줄 ↔ 초성 표 (초성 줄 이동·표시에 씀). 한 바퀴 = 게임 줄들 + '처음으로' 표시 한 줄
              final rows = (games.length / cols).ceil();
              _rowGroup = [for (var r = 0; r < rows; r++) gameGroups[r * cols]];
              _groupFirstRow = {};
              for (var i = 0; i < games.length; i++) {
                _groupFirstRow.putIfAbsent(gameGroups[i], () => i ~/ cols);
              }
              _railGroups = [for (final g in initialGroups) if (_groupFirstRow.containsKey(g)) g];
              _cycleH = rows * _rowStride + _loopMarkH;
              if (_currentGroup.value == null || !_groupFirstRow.containsKey(_currentGroup.value)) {
                // 그리는 중에는 값을 바꾸면 안 되어서 다음 프레임에 바꿈
                final first = _railGroups.first;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _currentGroup.value = first;
                });
              }
              final n = rows + 1;

              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (note) {
                      if (note.metrics.axis == Axis.vertical && note is ScrollUpdateNotification) {
                        _updateCurrentGroup();
                        _showRail();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(left: padL, right: padR),
                      // 아래 몇 줄을 미리 만들어 두어 사진이 늦게 뜨는 걸 줄임
                      // (cacheExtent는 Flutter 3.44부터 '사용 중단 예정' 안내가 뜨지만 지금 버전에서 정상 동작함.
                      //  새 scrollCacheExtent로 바꿨다가 이 PC의 Flutter 3.47.7에서 빌드가 깨져서 되돌림)
                      cacheExtent: _rowStride * 3,
                      // itemCount 없음 → 끝없이 이어짐. 줄 높이를 미리 알려 줘서 위치 계산이 정확·가벼움
                      itemExtentBuilder: (index, _) => index % n == rows ? _loopMarkH : _rowStride,
                      itemBuilder: (context, index) {
                        final r = index % n;
                        if (r == rows) return _LoopMark(firstGroup: _railGroups.first);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var k = 0; k < cols; k++) ...[
                                if (k > 0) const SizedBox(width: _gap),
                                Expanded(
                                  child: r * cols + k < games.length
                                      ? _GameCard(
                                          game: games[r * cols + k],
                                          imageCacheWidth: cacheW,
                                          onTap: () => _showDetail(games[r * cols + k]),
                                          onVideo: () =>
                                              _launchVideo(context, games[r * cols + k]),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // 왼쪽 초성 줄 — 스크롤할 때만 보임 (이 부분만 다시 그림)
                  Positioned(
                    left: 4,
                    top: 0,
                    bottom: 12,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _railVisible,
                      builder: (context, visible, _) => IgnorePointer(
                        ignoring: !visible,
                        child: AnimatedOpacity(
                          opacity: visible ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: ValueListenableBuilder<String?>(
                            valueListenable: _currentGroup,
                            builder: (context, current, _) => _InitialRail(
                              groups: _railGroups,
                              current: current,
                              onPick: (g, {bool animate = true}) {
                                _jumpToGroup(g, animate: animate);
                                _showRail();
                              },
                              onHold: (held) {
                                _railHeld = held;
                                _showRail();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // 필터 드롭다운 (해제 가능) — 고르면 진하게
  Widget _buildDropdown(
      String hint, IconData icon, String? currentValue, List<String> items, void Function(String?) onChanged) {
    final safeValue = (currentValue != null && items.contains(currentValue)) ? currentValue : null;
    final active = safeValue != null;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: active ? kInk : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: active ? kInk : kLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: active ? Colors.white : kBody),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              hint: Text(hint, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBody)),
              value: safeValue,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              iconEnabledColor: active ? Colors.white : kBody,
              selectedItemBuilder: (context) => [
                Center(child: Text('전체 $hint')),
                ...items.map((item) => Center(
                      child: Text(item,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    )),
              ],
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('전체 $hint', style: const TextStyle(color: kInk))),
                ...items.map((item) => DropdownMenuItem<String?>(
                      value: item,
                      child: Text(item, style: const TextStyle(color: kInk)),
                    )),
              ],
              onChanged: onChanged,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
        ],
      ),
    );
  }

  // 게임 상세 팝업
  void _showDetail(Map<String, dynamic> game) {
    final title = (game['title'] ?? '').toString();
    final imageUrl = game['imageUrl']?.toString();
    final difficulty = (game['difficulty'] ?? '').toString();
    final note = (game['pickNote'] ?? '').toString().trim();
    final tags = (game['tags'] ?? '').toString().trim();
    final genres = gameGenres(game);
    final hasVideo = hasRuleVideo(game);
    final ownVideo = hasStoreRuleVideo(game);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 820,
          height: 460,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: ColoredBox(
                  color: Colors.white,
                  child: hasValidImage(imageUrl)
                      ? AppNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.contain,
                          errorWidget: (c, u, e) => const Icon(Icons.casino_outlined, size: 60, color: kMuted),
                        )
                      : const Icon(Icons.casino_outlined, size: 60, color: kMuted),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _GameBadges(game: game),
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: kMuted),
                          ),
                        ],
                      ),
                      if (genres.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(genres.map((g) => '#$g').join('  '),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kOrange)),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _infoBox(Icons.people_alt_outlined, '인원', (game['players'] ?? '').toString()),
                          _infoBox(Icons.schedule, '소요시간', (game['time'] ?? '').toString()),
                          _infoBox(Icons.signal_cellular_alt, '난이도', difficulty,
                              dot: difficulty.isEmpty ? null : difficultyColor(difficulty)),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: kCreamCard, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.format_quote_rounded, color: kOrange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(note,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 15, height: 1.4, color: kInk)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(tags,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: kMuted)),
                      ],
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: () => _launchVideo(ctx, game),
                          icon: const Icon(Icons.play_circle_fill),
                          label: Text(!hasVideo ? '룰 영상 준비 중' : (ownVideo ? '매장 룰 설명 영상 보기' : '룰 설명 영상 보기 (유튜브)'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          style: FilledButton.styleFrom(
                            backgroundColor: hasVideo ? kOrange : kMuted,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBox(IconData icon, String label, String value, {Color? dot}) {
    return Container(
      width: 128,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: kMuted),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
          const SizedBox(height: 4),
          Row(
            children: [
              if (dot != null) ...[
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(value.isEmpty ? '-' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 추천·NEW·확장판 배지 줄 (없으면 빈 칸)
class _GameBadges extends StatelessWidget {
  final Map<String, dynamic> game;
  const _GameBadges({required this.game});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (game['isRecommended'] == true) _badge('직원 추천', kOrange, Icons.star_rounded),
      if (isNewGame(game)) _badge('NEW', kBlue, null),
      if (game['expansion'] == true) _badge('확장판', kPurple, null),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 6, children: badges),
    );
  }

  static Widget _badge(String text, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 2)],
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }
}

/// 게임 카드 하나
class _GameCard extends StatelessWidget {
  final Map<String, dynamic> game;
  final VoidCallback onTap;
  final VoidCallback onVideo;
  final int? imageCacheWidth;
  const _GameCard({required this.game, required this.onTap, required this.onVideo, this.imageCacheWidth});

  @override
  Widget build(BuildContext context) {
    final imageUrl = game['imageUrl']?.toString();
    final difficulty = (game['difficulty'] ?? '').toString();
    final players = (game['players'] ?? '').toString();
    final time = (game['time'] ?? '').toString();
    final genres = gameGenres(game);
    final hasVideo = hasRuleVideo(game);

    return HomeCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: const Color(0xFFF1ECE2),
                  child: hasValidImage(imageUrl)
                      ? AppNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: imageCacheWidth,
                          errorWidget: (c, u, e) => const Icon(Icons.casino_outlined, size: 44, color: kMuted),
                        )
                      : const Icon(Icons.casino_outlined, size: 44, color: kMuted),
                ),
                Positioned(left: 12, top: 12, child: _GameBadges(game: game)),
                if (hasVideo)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: onVideo,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 2),
                              Text('룰 영상',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((game['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                const SizedBox(height: 2),
                Text(genres.isEmpty ? ' ' : genres.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: kMuted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (players.isNotEmpty) _meta(Icons.people_alt_outlined, players),
                    if (time.isNotEmpty) _meta(Icons.schedule, time),
                    if (difficulty.isNotEmpty)
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: difficultyColor(difficulty), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(difficulty,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBody)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kMuted),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kBody)),
          ),
        ],
      ),
    );
  }
}

// ── 초성 묶음 ──

/// 초성 줄 순서: ㄱ~ㅎ(된소리는 예사소리에 합침), 영문(A), 숫자·기호(#)
const List<String> initialGroups = ['ㄱ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ', 'A', '#'];

// 한글 음절의 19개 초성 → 묶음 (ㄲ→ㄱ, ㄸ→ㄷ, ㅃ→ㅂ, ㅆ→ㅅ, ㅉ→ㅈ)
const List<String> _choseongGroup = [
  'ㄱ', 'ㄱ', 'ㄴ', 'ㄷ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅂ', 'ㅅ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ', //
];
// 따로 쓴 자음 글자(ㄱ, ㄲ, ㄳ … ㅎ: U+3131~U+314E) → 묶음
const String _jamoGroup = 'ㄱㄱㄱㄴㄴㄴㄷㄷㄹㄹㄹㄹㄹㄹㄹㄹㅁㅂㅂㅂㅅㅅㅇㅈㅈㅊㅋㅌㅍㅎ';

/// 게임 이름 첫 글자의 초성 묶음
String initialGroupOf(String title) {
  if (title.isEmpty) return '#';
  final c = title.runes.first;
  if (c >= 0xAC00 && c <= 0xD7A3) return _choseongGroup[(c - 0xAC00) ~/ 588];
  if (c >= 0x3131 && c <= 0x314E) return _jamoGroup[c - 0x3131];
  if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) return 'A';
  return '#';
}

/// 왼쪽 초성 줄. 누르면 그 초성으로 이동, 줄을 쓸어내리면 손가락 아래 초성으로 바로 이동
class _InitialRail extends StatelessWidget {
  final List<String> groups;
  final String? current;
  final void Function(String group, {bool animate}) onPick;
  final void Function(bool held) onHold;

  const _InitialRail({required this.groups, required this.current, required this.onPick, required this.onHold});

  static const double _itemH = 32;

  void _pickAt(double dy) {
    if (groups.isEmpty) return;
    final i = (dy / _itemH).floor().clamp(0, groups.length - 1).toInt();
    onPick(groups[i], animate: false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onHold(true),
        onTapUp: (d) {
          final i = (d.localPosition.dy - 6) ~/ _itemH;
          if (i >= 0 && i < groups.length) onPick(groups[i]);
          onHold(false);
        },
        onTapCancel: () => onHold(false),
        onVerticalDragStart: (d) {
          onHold(true);
          _pickAt(d.localPosition.dy - 6);
        },
        onVerticalDragUpdate: (d) => _pickAt(d.localPosition.dy - 6),
        onVerticalDragEnd: (_) => onHold(false),
        onVerticalDragCancel: () => onHold(false),
        child: Container(
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 3))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final g in groups)
                SizedBox(
                  height: _itemH,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: g == current ? kOrange : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        g,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: g == current ? FontWeight.w800 : FontWeight.w600,
                          color: g == current ? Colors.white : kBody,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 한 바퀴 끝 '처음부터 다시' 표시
class _LoopMark extends StatelessWidget {
  final String firstGroup;
  const _LoopMark({required this.firstGroup});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        children: [
          const Expanded(child: Divider(color: kLine, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.replay_rounded, size: 18, color: kMuted),
                const SizedBox(width: 6),
                Text('$firstGroup부터 다시',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kMuted)),
              ],
            ),
          ),
          const Expanded(child: Divider(color: kLine, thickness: 1)),
        ],
      ),
    );
  }
}
