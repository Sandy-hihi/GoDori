import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/screens/food_order_screen.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/services/ai_service.dart';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'ai_recommend_dialog.dart';
import 'home_theme.dart';

/// 격자 위젯 하나 그리기
Widget buildGridWidget(BuildContext context, GridItem item, int? roomNumber) {
  final o = item.options;
  switch (item.type) {
    case 'gameList':
      return _PhotoCard(
        image: 'assets/images/ui_games.jpg',
        title: '게임 목록 보기',
        subtitle: '장르·인원·난이도로 찾고 룰 영상까지',
        background: const Color(0xFFEEF3FA),
        titleColor: const Color(0xFF1D2A44),
        subColor: const Color(0xFF56627A),
        accent: kBlue,
        onTap: () => openHomeTarget(context, 'games', roomNumber),
      );
    case 'foodOrder':
      return _PhotoCard(
        image: 'assets/images/ui_food.jpg',
        title: '음식 주문하기',
        subtitle: '커피·하이볼·튀김을 자리에서 바로',
        background: kCreamCard,
        titleColor: kInk,
        subColor: const Color(0xFF6F665B),
        accent: kOrange,
        onTap: () => openHomeTarget(context, 'food', roomNumber),
      );
    case 'aiPick':
      if (!kAiRecommendEnabled) return const SizedBox.shrink(); // AI 추천 꺼 둠 (home_layout.dart)
      return AiPickWidget(
        roomNumber: roomNumber,
        count: _optInt(o, 'count', 3).clamp(2, 4).toInt(),
        showAsk: o['showAsk'] != false,
        exclude: _optList(o, 'exclude'),
        tall: item.h >= 6,
      );
    case 'search':
      return _SearchWidget(roomNumber: roomNumber, thin: item.h == 1);
    case 'finder':
      return _FinderWidget(roomNumber: roomNumber, thin: item.h == 1);
    case 'recommended':
      if (item.h == 1) {
        // 얇은 크기: 흰 알약 버튼 (찾아보기 버튼들과 같은 모양)
        return HomePillButton(
          icon: Icons.star_rounded,
          iconColor: const Color(0xFFE0A21B),
          label: '추천 게임',
          onTap: () => openHomeTarget(context, 'recommended', roomNumber),
        );
      }
      return HomeShortcutTile(
        icon: Icons.star_rounded,
        iconColor: const Color(0xFFE0A21B),
        iconBg: Colors.white,
        color: const Color(0xFFFFF4D6),
        label: '추천 게임',
        sub: '직원이 고른 게임',
        onTap: () => openHomeTarget(context, 'recommended', roomNumber),
      );
    case 'menuPick':
      return _MenuPickWidget(menuId: _optStr(o, 'menuId'), roomNumber: roomNumber);
    case 'clock':
      if (item.w >= 2) {
        // 가로로 긴 시계: 아이콘 왼쪽, 날짜·시각 오른쪽 (얇으면 여백을 줄임)
        return HomeCard(
          padding: item.h == 1 ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8) : const EdgeInsets.all(18),
          child: LiveClock(
            builder: (context, now) => Row(
              children: [
                const Icon(Icons.schedule, size: 30, color: kInk),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(formatDateKo(now), style: const TextStyle(fontSize: 13, color: kMuted)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(formatTimeKo(now),
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kInk)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return HomeCard(
        child: LiveClock(
          builder: (context, now) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.schedule, size: 26, color: kInk),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDateKo(now), style: const TextStyle(fontSize: 12, color: kMuted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatTimeKo(now),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    case 'room':
      return HomeCard(
        color: const Color(0xFF2A2420),
        padding: item.h == 1 ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8) : const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('지금 이용 중인 방', style: TextStyle(fontSize: 12, color: Color(0xA6F4EBDC))),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${roomNumber ?? '-'}번 룸',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFFF4EBDC))),
            ),
          ],
        ),
      );
    case 'staffCall':
      return HomeCard(
        color: kOrange,
        padding: item.h == 1 ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6) : const EdgeInsets.all(18),
        onTap: () => StaffCallService.callStaff(context, roomNumber ?? 0),
        child: item.w >= 2
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_active, color: Colors.white, size: 34),
                  SizedBox(width: 12),
                  Text('직원 호출', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.notifications_active, color: Colors.white, size: 30),
                  Text('직원 호출', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
              ),
      );
    case 'notice':
      return HomeCard(
        onTap: () => openHomeTarget(context, 'notice', roomNumber),
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeCardHeader(icon: Icons.campaign_outlined, title: '공지사항'),
            SizedBox(height: 10),
            Flexible(
              child: LatestItemTitle(
                docId: 'notices',
                emptyText: '등록된 공지가 없어요',
                style: TextStyle(fontSize: 15, color: kBody, height: 1.5),
              ),
            ),
          ],
        ),
      );
    case 'event':
      if (item.w == 1) {
        return HomeShortcutTile(
          icon: Icons.card_giftcard_outlined,
          iconColor: kPurple,
          iconBg: Colors.white,
          color: kPurpleBg,
          textColor: const Color(0xFF2E2346),
          label: '이벤트',
          onTap: () => openHomeTarget(context, 'event', roomNumber),
        );
      }
      return HomeCard(
        color: kPurpleBg,
        onTap: () => openHomeTarget(context, 'event', roomNumber),
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeCardHeader(
                icon: Icons.card_giftcard_outlined, iconColor: kPurple, title: '진행 중인 이벤트', titleColor: Color(0xFF2E2346)),
            SizedBox(height: 10),
            Flexible(
              child: LatestItemTitle(
                docId: 'events',
                emptyText: '진행 중인 이벤트가 없어요',
                style: TextStyle(fontSize: 15, color: Color(0xFF4E4466), height: 1.5),
              ),
            ),
          ],
        ),
      );
    case 'fee':
      return _FeeWidget(rows: _optRows(o));
    case 'info':
      return HomeShortcutTile(
        icon: Icons.article_outlined,
        label: '이용안내',
        onTap: () => openHomeTarget(context, 'notice', roomNumber),
      );
    case 'wifi':
      return HomeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(Icons.wifi, color: Color(0xFFB5751E), size: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_optStr(o, 'ssid') ?? '와이파이 이름',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
                Text(_optStr(o, 'password') ?? '비밀번호를 입력해 주세요',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6F665B))),
              ],
            ),
          ],
        ),
      );
    case 'qr':
      return HomeCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: HomeQr(url: _optStr(o, 'url'))),
            const SizedBox(height: 6),
            Text(_optStr(o, 'label') ?? '리뷰 남기기',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kInk)),
          ],
        ),
      );
    case 'tools':
      return HomeShortcutTile(
        icon: Icons.timer_outlined,
        iconColor: const Color(0xFF0277BD),
        iconBg: const Color(0xFFE3F2FB),
        label: '게임도구',
        onTap: () => openHomeTarget(context, 'tools', roomNumber),
      );
    case 'timer':
      return _TimerWidget(defaultMinutes: _optInt(o, 'minutes', 5).clamp(1, 99).toInt());
    case 'dice':
      return const _DiceWidget();
    case 'banner':
      return _BannerWidget(
        imageUrl: _optStr(o, 'imageUrl'),
        caption: _optStr(o, 'caption'),
        link: _optStr(o, 'link'),
        roomNumber: roomNumber,
      );
    case 'greeting':
      // 배경 없는 인사말 (작은 줄 + 큰 줄)
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((_optStr(o, 'small') ?? '').isNotEmpty)
                Text(_optStr(o, 'small')!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, color: kBody)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_optStr(o, 'text') ?? '인사말을 입력해 주세요',
                    maxLines: 1, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kInk)),
              ),
            ],
          ),
        ),
      );
    case 'memo':
      return HomeCard(
        color: const Color(0xFFFFF4D6),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sticky_note_2_outlined, color: Color(0xFFB5751E), size: 22),
            const SizedBox(height: 8),
            Flexible(
              child: Text(_optStr(o, 'text') ?? '안내 문구를 입력해 주세요',
                  overflow: TextOverflow.fade,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5, color: kInk)),
            ),
          ],
        ),
      );
  }
  return const SizedBox.shrink();
}

// ── 옵션 읽기 ──
String? _optStr(Map<String, dynamic> o, String key) {
  final s = o[key]?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

int _optInt(Map<String, dynamic> o, String key, int fallback) {
  final v = o[key];
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

List<String> _optList(Map<String, dynamic> o, String key) {
  final v = o[key];
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

List<({String label, String value})> _optRows(Map<String, dynamic> o) {
  final v = o['rows'];
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((r) => (label: (r['label'] ?? '').toString(), value: (r['value'] ?? '').toString()))
      .where((r) => r.label.isNotEmpty || r.value.isNotEmpty)
      .toList();
}

/// QR 코드 (주소가 없으면 자리 표시)
class HomeQr extends StatelessWidget {
  final String? url;
  const HomeQr({super.key, this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const Center(child: Icon(Icons.qr_code_2, size: 72, color: Color(0xFFCFC8BB)));
    }
    return QrImageView(
      data: url!,
      padding: EdgeInsets.zero,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: kInk),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: kInk),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final String image, title, subtitle;
  final Color background, titleColor, subColor, accent;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.image,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.titleColor,
    required this.subColor,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x143C2814), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Image.asset(image, fit: BoxFit.cover)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1, color: titleColor)),
                          ),
                          const SizedBox(height: 4),
                          Text(subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: subColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 48,
                      height: 48,
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
    );
  }
}

class _SearchWidget extends StatefulWidget {
  final int? roomNumber;
  final bool thin; // 반 칸 높이: 제목 없이 흰 검색창만
  const _SearchWidget({this.roomNumber, this.thin = false});

  @override
  State<_SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<_SearchWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    homeGo(context, GameListScreen(roomNumber: widget.roomNumber, initialSearchQuery: _controller.text.trim()));
  }

  Widget _field() {
    return Row(
      children: [
        const Icon(Icons.search, color: kInk, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 15, color: kInk),
            decoration: const InputDecoration(
              hintText: '게임 이름으로 검색',
              hintStyle: TextStyle(color: Color(0xFF9A958C)),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        IconButton(
          onPressed: _search,
          icon: const Icon(Icons.arrow_forward, color: kInk, size: 20),
          tooltip: '검색',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thin) {
      return Center(
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(left: 18, right: 6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
          child: _field(),
        ),
      );
    }
    return HomeCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('어떤 게임 찾으세요?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 12),
          Container(
            height: 50,
            padding: const EdgeInsets.only(left: 18, right: 6),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(25)),
            child: Row(
              children: [
                const Icon(Icons.search, color: kInk, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _search(),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 15, color: kInk),
                    decoration: const InputDecoration(
                      hintText: '게임 이름으로 검색',
                      hintStyle: TextStyle(color: Color(0xFF9A958C)),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward, color: kInk),
                  tooltip: '검색',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinderWidget extends StatelessWidget {
  final int? roomNumber;
  final bool thin; // 반 칸 높이: 제목 없이 흰 알약 버튼 3개 (격자 간격과 같은 16)
  const _FinderWidget({this.roomNumber, this.thin = false});

  void _open(BuildContext context, {String? genre, String? players, String? difficulty}) {
    homeGo(
      context,
      GameListScreen(
        roomNumber: roomNumber,
        initialGenre: genre,
        initialPlayers: players,
        initialDifficulty: difficulty,
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap, {Widget? leading}) {
    return Expanded(
      child: Material(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 6)],
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    if (thin) {
      void pickPlayers() => showFilterPicker(
            context: context,
            title: '몇 명이서 하세요?',
            options: Future.value(homePlayerOptions),
            onPick: (v) => _open(context, players: v),
          );
      void pickGenre() => showFilterPicker(
            context: context,
            title: '어떤 장르가 좋으세요?',
            options: loadGenres(),
            onPick: (v) => _open(context, genre: v),
          );
      void pickDifficulty() => showFilterPicker(
            context: context,
            title: '난이도를 골라 주세요',
            options: Future.value(difficultyLabels),
            showDifficultyColors: true,
            onPick: (v) => _open(context, difficulty: v),
          );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: HomePillButton(icon: Icons.people_alt_outlined, label: '인원별', onTap: pickPlayers)),
          const SizedBox(width: 16),
          Expanded(child: HomePillButton(icon: Icons.sell_outlined, label: '장르별', onTap: pickGenre)),
          const SizedBox(width: 16),
          Expanded(
            child: HomePillButton(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [dot(const Color(0xFF23AC3A)), dot(const Color(0xFFF29700)), dot(const Color(0xFFD80051))],
              ),
              label: '난이도별',
              onTap: pickDifficulty,
            ),
          ),
        ],
      );
    }
    return HomeCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('이렇게 찾아보세요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 12),
          Row(
            children: [
              _button(
                '인원별',
                () => showFilterPicker(
                  context: context,
                  title: '몇 명이서 하세요?',
                  options: Future.value(homePlayerOptions),
                  onPick: (v) => _open(context, players: v),
                ),
              ),
              const SizedBox(width: 8),
              _button(
                '장르별',
                () => showFilterPicker(
                  context: context,
                  title: '어떤 장르가 좋으세요?',
                  options: loadGenres(),
                  onPick: (v) => _open(context, genre: v),
                ),
              ),
              const SizedBox(width: 8),
              _button(
                '난이도별',
                () => showFilterPicker(
                  context: context,
                  title: '난이도를 골라 주세요',
                  options: Future.value(difficultyLabels),
                  showDifficultyColors: true,
                  onPick: (v) => _open(context, difficulty: v),
                ),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [dot(const Color(0xFF23AC3A)), dot(const Color(0xFFF29700)), dot(const Color(0xFFD80051))],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuPickWidget extends StatelessWidget {
  final String? menuId;
  final int? roomNumber;
  const _MenuPickWidget({this.menuId, this.roomNumber});

  @override
  Widget build(BuildContext context) {
    if (menuId == null) {
      return const HomeCard(
        color: kCreamCard,
        child: Center(
          child: Text('관리자 화면에서 추천 메뉴를 골라 주세요',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: kMuted)),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('menus').doc(menuId).snapshots(),
      builder: (context, snapshot) {
        final m = snapshot.data?.data();
        final name = (m?['name'] ?? '').toString();
        final price = m?['price'];
        final priceText = price == null ? '' : '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';
        final imageUrl = m?['imageUrl']?.toString();
        final soldOut = m?['isSoldOut'] == true || m?['isSoldOut'] == 'true';
        return Material(
          color: kCreamCard,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: soldOut
                ? null
                : () => homeGo(context, FoodOrderScreen(roomNumber: roomNumber, initialMenuId: menuId)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 132,
                  child: hasValidImage(imageUrl)
                      ? AppNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => Image.asset('assets/images/ui_food.jpg', fit: BoxFit.cover),
                        )
                      : Image.asset('assets/images/ui_food.jpg', fit: BoxFit.cover),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(soldOut ? '오늘의 추천 메뉴 · 품절' : '오늘의 추천 메뉴',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kOrange)),
                        const SizedBox(height: 4),
                        Text(name.isEmpty ? '메뉴를 불러오는 중' : name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                        if (priceText.isNotEmpty)
                          Text(priceText, style: const TextStyle(fontSize: 15, color: Color(0xFF6F665B))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeeWidget extends StatelessWidget {
  final List<({String label, String value})> rows;
  const _FeeWidget({required this.rows});

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('요금 안내', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text('관리자 화면에서 요금표를 입력해 주세요', style: TextStyle(fontSize: 14, color: kMuted))
          else
            for (final r in rows.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, color: kBody)),
                    ),
                    Text(r.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatefulWidget {
  final int defaultMinutes;
  const _TimerWidget({required this.defaultMinutes});

  @override
  State<_TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<_TimerWidget> {
  late int _total = widget.defaultMinutes * 60;
  late int _left = _total;
  Timer? _timer;
  bool _done = false;
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  bool get _running => _timer != null;

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _timer = null);
      return;
    }
    if (_left <= 0) _left = _total;
    setState(() {
      _done = false;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _left--;
          if (_left <= 0) {
            _left = 0;
            _timer?.cancel();
            _timer = null;
            _done = true;
            _player.play(AssetSource('sounds/ddingdong.mp3'));
          }
        });
      });
    });
  }

  void _adjust(int minutes) {
    if (_running) return;
    setState(() {
      _total = (_total + minutes * 60).clamp(60, 99 * 60).toInt();
      _left = _total;
      _done = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_left ~/ 60).toString().padLeft(2, '0');
    final ss = (_left % 60).toString().padLeft(2, '0');
    return HomeCard(
      color: _done ? const Color(0xFFFFE9D6) : Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_done ? '시간 끝!' : '타이머',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _done ? kOrange : const Color(0xFF0277BD))),
          FittedBox(
            child: Text('$mm:$ss',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: kInk, letterSpacing: 1)),
          ),
          Row(
            children: [
              _small(Icons.remove, '1분 줄이기', () => _adjust(-1)),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  onPressed: _toggle,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0277BD),
                    minimumSize: const Size(0, 40),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_running ? '멈춤' : '시작', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 6),
              _small(Icons.add, '1분 늘리기', () => _adjust(1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _small(IconData icon, String tip, VoidCallback onTap) {
    return SizedBox(
      width: 36,
      height: 40,
      child: IconButton(
        onPressed: _running ? null : onTap,
        icon: Icon(icon, size: 18),
        tooltip: tip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: kBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _DiceWidget extends StatefulWidget {
  const _DiceWidget();

  @override
  State<_DiceWidget> createState() => _DiceWidgetState();
}

class _DiceWidgetState extends State<_DiceWidget> {
  final _random = Random();
  int _value = 5;
  int _spin = 0;

  void _roll() => setState(() {
        _value = _random.nextInt(6) + 1;
        _spin++;
      });

  // 3×3 칸 중 점이 찍히는 자리
  static const Map<int, List<int>> _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      onTap: _roll,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Expanded(
            child: AnimatedRotation(
              turns: _spin * 0.25,
              duration: const Duration(milliseconds: 250),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: kInk, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 0; i < 9; i++)
                        Center(
                          child: (_pips[_value] ?? const []).contains(i)
                              ? Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(color: kInk, shape: BoxShape.circle))
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
            child: const Text('눌러서 굴리기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
          ),
        ],
      ),
    );
  }
}

class _BannerWidget extends StatelessWidget {
  final String? imageUrl;
  final String? caption;
  final String? link;
  final int? roomNumber;

  const _BannerWidget({this.imageUrl, this.caption, this.link, this.roomNumber});

  @override
  Widget build(BuildContext context) {
    final target = (link == null || link == 'none') ? null : link;
    return Material(
      color: const Color(0xFF3A322C),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: target == null ? null : () => openHomeTarget(context, target, roomNumber),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasValidImage(imageUrl))
              AppNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover)
            else
              const Center(child: Icon(Icons.image_outlined, color: Color(0x66FFFFFF), size: 48)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x99000000)],
                  stops: [0.35, 1],
                ),
              ),
            ),
            if (caption != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Text(caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 오늘의 추천 게임 (AI). 오늘 AI 추천이 없으면 직원 추천 게임으로 대신
class AiPickWidget extends StatelessWidget {
  final int? roomNumber;
  final int count;
  final bool showAsk;
  final List<String> exclude;
  final bool tall;

  const AiPickWidget({
    super.key,
    this.roomNumber,
    this.count = 3,
    this.showAsk = true,
    this.exclude = const [],
    this.tall = false,
  });

  static const _thumbColors = [kBlue, Color(0xFF23AC3A), kOrange, Color(0xFF6B3FC4)];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kInk,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: kAmber, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('오늘의 추천 게임',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFF4EBDC))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0x2EF0B35A), borderRadius: BorderRadius.circular(10)),
                  child: const Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kAmber)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<AiPick>?>(
                stream: AiService.todayPicks(),
                builder: (context, snapshot) {
                  final aiPicks = snapshot.data?.where((p) => !exclude.contains(p.gameId)).toList();
                  if (aiPicks != null && aiPicks.isNotEmpty) return _list(context, aiPicks.take(count).toList());
                  return FutureBuilder<List<AiPick>>(
                    future: AiService.staffPicks(count, exclude: exclude),
                    builder: (context, staff) {
                      final picks = staff.data ?? const [];
                      if (staff.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: kAmber, strokeWidth: 2));
                      }
                      if (picks.isEmpty) {
                        return const Center(
                          child: Text('추천 게임을 준비하고 있어요',
                              style: TextStyle(fontSize: 14, color: Color(0xA6F4EBDC))),
                        );
                      }
                      return _list(context, picks);
                    },
                  );
                },
              ),
            ),
            if (showAsk) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: () => showAiRecommendDialog(context, roomNumber: roomNumber, count: 3, exclude: exclude),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAmber,
                    foregroundColor: kInk,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('우리 테이블 맞춤 추천받기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<AiPick> picks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < picks.length; i++)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => homeGo(context, GameListScreen(roomNumber: roomNumber, initialSearchQuery: picks[i].title)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ColoredBox(
                          color: _thumbColors[i % _thumbColors.length],
                          child: hasValidImage(picks[i].imageUrl)
                              ? AppNetworkImage(imageUrl: picks[i].imageUrl!, fit: BoxFit.cover)
                              : const Icon(Icons.casino_outlined, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(picks[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFF4EBDC))),
                          Text(picks[i].reason,
                              maxLines: tall ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xA6F4EBDC))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
