import 'package:boardpad/widgets/store_brand.dart';
import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';

import 'package:boardpad/models/home_layout.dart';
import 'package:boardpad/utils/image_helper.dart';
import 'package:boardpad/widgets/app_network_image.dart';
import 'package:boardpad/services/staff_call_service.dart';
import 'package:boardpad/services/store_features.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/widgets/home_common.dart';
import 'package:boardpad/widgets/pad_shell.dart';

import 'home_grid_widgets.dart';
import 'home_theme.dart';

/// 홈 화면 한 장을 1280×800 기준으로 그림. 손님 화면과 관리자 미리보기가 같이 씀
class HomeView extends StatelessWidget {
  final HomeLayout layout;
  final int? roomNumber;
  final String? highlightId; // 관리자 미리보기에서 선택한 위젯 강조
  final bool highlightSidebar;

  /// 그리는 크기. 관리자 미리보기는 기준 크기(1280×800) 그대로,
  /// 손님 화면은 기기 비율에 맞춘 크기(HomeLayout.designSizeFor)를 넘겨 꽉 차게 그림
  final Size size;

  const HomeView({
    super.key,
    required this.layout,
    this.roomNumber,
    this.highlightId,
    this.highlightSidebar = false,
    this.size = const Size(HomeLayout.designWidth, HomeLayout.designHeight),
  });

  static const EdgeInsets _gridPadding = EdgeInsets.fromLTRB(
    HomeLayout.gridPadH,
    HomeLayout.gridPadV,
    HomeLayout.gridPadH,
    HomeLayout.gridPadV,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ColoredBox(
        color: kBg,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (layout.sidebarVisible)
                  HomeSidebar(
                    layout: layout,
                    roomNumber: roomNumber,
                  ),
                Expanded(
                  child: Padding(padding: _gridPadding, child: _buildGrid()),
                ),
              ],
            ),
            // 왼쪽 영역을 껐을 때도 직원이 패드를 끌 수 있게 왼쪽 위 구석에 숨은 영역
            if (!layout.sidebarVisible)
              const Positioned(right: 16, top: 16, child: GuestLanguageButton()),
            if (!layout.sidebarVisible)
              const Positioned(
                left: 0,
                top: 0,
                width: 72,
                height: 72,
                child: HoldToExit(child: SizedBox.expand()),
              ),
            if (highlightSidebar && layout.sidebarVisible)
              Positioned(
                left: 4,
                top: 4,
                width: HomeLayout.sidebarWidth - 8,
                height: size.height - 8,
                child: IgnorePointer(child: _highlightBox()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _highlightBox() => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: kOrange, width: 5),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(color: Color(0x40E2711D), blurRadius: 0, spreadRadius: 6),
      ],
    ),
  );

  Widget _buildGrid() {
    // 칸 크기는 실제 격자 영역에서 계산 (화면 비율에 따라 가로·세로가 늘어남)
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = HomeLayout.gap;
        final cellW =
            (constraints.maxWidth - gap * (layout.cols - 1)) / layout.cols;
        final cellH =
            (constraints.maxHeight - gap * (HomeLayout.rows - 1)) /
            HomeLayout.rows;
        Rect rectOf(GridItem i) => Rect.fromLTWH(
          i.x * (cellW + gap),
          i.y * (cellH + gap),
          i.w * cellW + (i.w - 1) * gap,
          i.h * cellH + (i.h - 1) * gap,
        );
        return Stack(
          children: [
            for (final item in layout.widgets)
              Positioned.fromRect(
                rect: rectOf(item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    KeyedSubtree(
                      key: ValueKey(
                        '${item.id}-${item.type}-${item.w}x${item.h}',
                      ),
                      child: buildGridWidget(context, item, roomNumber),
                    ),
                    if (item.id == highlightId)
                      IgnorePointer(child: _highlightBox()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 왼쪽 영역
class HomeSidebar extends StatelessWidget {
  final HomeLayout layout;
  final int? roomNumber;

  /// 지금 화면 ('home' = 메인 화면, 내부 화면은 games·food·tools·event·notice 등). 메뉴에서 주황으로 표시
  final String current;

  const HomeSidebar({
    super.key,
    required this.layout,
    this.roomNumber,
    this.current = 'home',
  });

  @override
  Widget build(BuildContext context) {
    final light = layout.sidebarIsLight;
    final fg = light ? kInk : const Color(0xFFEFE8DC);
    // 82차: 언어 버튼은 홈·내부 화면 모두 사이드바의 '직원 호출' 바로 위 (직원 호출이 없으면 맨 아래).
    // 사이드바 메뉴 줄과 같은 모양(사이드바 글자색), 누르면 큰 언어 선택 창
    final language = GuestLanguageButton.sidebar(color: fg);
    final children = <Widget>[];
    var languageAdded = false;
    void addGap() {
      if (children.isNotEmpty && children.last is! Spacer) {
        children.add(const SizedBox(height: 14));
      }
    }

    for (var i = 0; i < layout.sidebarItems.length; i++) {
      final item = layout.sidebarItems[i];
      if (item.type == 'spacer') {
        children.add(const Spacer());
        continue;
      }
      if (item.type == 'staffCall' && !languageAdded) {
        addGap();
        children.add(language);
        languageAdded = true;
      }
      addGap();
      children.add(_buildItem(context, item, fg, light));
    }
    if (!languageAdded) {
      addGap();
      children.add(language);
    }
    return Container(
      width: HomeLayout.sidebarWidth,
      color: layout.sidebarColor,
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    SidebarItem item,
    Color fg,
    bool light,
  ) {
    final o = item.options;
    final boxColor = fg.withValues(alpha: light ? 0.07 : 0.09);
    switch (item.type) {
      case 'logo':
        final logoUrl = (o['imageUrl'] ?? '').toString().trim();
        final storeName = (o['name'] ?? '').toString().trim();
        final hasLogo = hasValidImage(logoUrl);
        // 매장이 로고·이름을 설정했으면 그걸 보여 주고, 둘 다 비었으면 고도리 기본 브랜드 (80차).
        // 어느 경우든 이 자리를 빠르게 10번 누르면 패드 로그아웃 창.
        return HoldToExit(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: (!hasLogo && storeName.isEmpty)
                ? Center(child: GodoriBrand(size: 48, textColor: fg))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasLogo) ...[
                        ClipOval(
                          child: AppNetworkImage(
                            imageUrl: logoUrl,
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorWidget: (c, u, e) =>
                                const SizedBox(width: 76, height: 76),
                          ),
                        ),
                        if (storeName.isNotEmpty) const SizedBox(height: 10),
                      ],
                      if (storeName.isNotEmpty)
                        Text(
                          storeName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: fg,
                          ),
                        ),
                    ],
                  ),
          ),
        );
      case 'room':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GuestText(
                '지금 이용 중인 방',
                style: TextStyle(
                  fontSize: 12,
                  color: fg.withValues(alpha: 0.65),
                ),
              ),
              GuestText(
                '${roomNumber ?? '-'}번 룸',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        );
      case 'staffCall':
        return SizedBox(
          height: 64,
          child: FilledButton.icon(
            onPressed: () =>
                StaffCallService.callStaff(context, roomNumber ?? 0),
            icon: const Icon(Icons.notifications_active),
            label: const GuestText(
              '직원 호출',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      case 'phone':
        return Center(
          child: StorePhoneText(
            style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.6)),
          ),
        );
      case 'clock':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LiveClock(
            builder: (context, now) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GuestText(
                  formatDateKo(now),
                  style: TextStyle(
                    fontSize: 12,
                    color: fg.withValues(alpha: 0.65),
                  ),
                ),
                GuestText(
                  formatTimeKo(now),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        );
      case 'links':
        final raw = o['targets'];
        final targets = raw is List
            ? raw
                  .map((e) => e.toString())
                  .where(linkTargets.containsKey)
                  .toList()
            : const ['event', 'tools', 'notice'];
        // 맨 위에 '홈', 그 아래 사장님이 고른 바로가기. 지금 화면은 주황 (홈·내부 화면 사이드바 공통)
        Widget row(String key, String label, IconData icon) {
          final selected = key == current;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: selected ? kOrange : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => padNavigate(context, key, current, roomNumber),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: selected ? Colors.white : fg,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GuestText(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: selected ? Colors.white : fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget rows(bool tossPos) => Column(
          children: [
            row('home', '홈', Icons.home_rounded),
            for (final t in targets)
              // 84차: '주문 내역'은 토스 POS 연동 매장에서만 (결제 끝나면 비워지는 목록이라)
              if (t != 'orders' || tossPos) row(t, linkTargets[t]!, homeTargetIcon(t)),
          ],
        );
        // 매장 로그인 전(위젯 테스트 등)에는 매장 기능을 못 읽으니 숨김
        if (!targets.contains('orders') || !StoreScope.isSet) return rows(false);
        return StreamBuilder<StoreFeatures>(
          stream: StoreFeaturesService.watch(),
          initialData: StoreFeaturesService.last ?? StoreFeatures.defaults,
          builder: (context, f) => rows(f.data?.tossPos == true),
        );
      case 'note':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: GuestText(
            (o['text'] ?? '안내 문구를 입력해 주세요').toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.45, color: fg),
          ),
        );
      case 'wifi':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wifi, size: 18, color: fg),
                  const SizedBox(width: 6),
                  GuestText(
                    '와이파이',
                    style: TextStyle(
                      fontSize: 12,
                      color: fg.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GuestText(
                (o['ssid'] ?? '와이파이 이름').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              GuestText(
                (o['password'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: fg),
              ),
            ],
          ),
        );
      case 'qr':
        final url = (o['url'] ?? '').toString().trim();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 118,
                height: 118,
                child: HomeQr(url: url.isEmpty ? null : url),
              ),
              const SizedBox(height: 6),
              GuestText(
                (o['label'] ?? '리뷰 남기기').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kInk,
                ),
              ),
            ],
          ),
        );
    }
    return const SizedBox.shrink();
  }
}
