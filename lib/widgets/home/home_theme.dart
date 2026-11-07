import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/screens/event_screen.dart';
import 'package:boardpad/screens/food_order_screen.dart';
import 'package:boardpad/screens/game_list_screen.dart';
import 'package:boardpad/screens/game_tools_screen.dart';
import 'package:boardpad/screens/notice_screen.dart';

/// 홈 화면(L 디자인) 공통 색과 작은 부품

const kInk = Color(0xFF26211C);
const kBg = Color(0xFFF4F0E8);
const kOrange = Color(0xFFE2711D);
const kBlue = Color(0xFF2459A8);
const kMuted = Color(0xFF7A7266);
const kBody = Color(0xFF5C554B);
const kLine = Color(0xFFE6E1D7);
const kPurpleBg = Color(0xFFEFE7FB);
const kPurple = Color(0xFF6B3FC4);
const kCreamCard = Color(0xFFFFF7EA);
const kAmber = Color(0xFFF0B35A);

/// 손님 패드 화면 이동 — 왼쪽 메뉴처럼 애니메이션 없이 바로 바뀜 (덮이며 밀려 들어오는 효과 없음)
Route<T> padRoute<T>(Widget page, {RouteSettings? settings}) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, _, _) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );

void homeGo(BuildContext context, Widget page) {
  Navigator.push(context, padRoute(page));
}

/// 'games' | 'food' | 'recommended' | 'event' | 'notice' | 'tools'
void openHomeTarget(BuildContext context, String target, int? roomNumber) {
  switch (target) {
    case 'games':
      homeGo(context, GameListScreen(roomNumber: roomNumber));
      break;
    case 'recommended':
      homeGo(context, GameListScreen(roomNumber: roomNumber, initialTab: '추천'));
      break;
    case 'food':
      homeGo(context, FoodOrderScreen(roomNumber: roomNumber));
      break;
    case 'event':
      homeGo(context, EventScreen(roomNumber: roomNumber));
      break;
    case 'notice':
      homeGo(context, NoticeScreen(roomNumber: roomNumber));
      break;
    case 'tools':
      homeGo(context, GameToolsScreen(roomNumber: roomNumber));
      break;
  }
}

IconData homeTargetIcon(String target) {
  switch (target) {
    case 'games':
      return Icons.casino_outlined;
    case 'food':
      return Icons.restaurant;
    case 'recommended':
      return Icons.star_rounded;
    case 'event':
      return Icons.card_giftcard_outlined;
    case 'notice':
      return Icons.article_outlined;
    case 'tools':
      return Icons.timer_outlined;
  }
  return Icons.arrow_forward;
}

/// 둥근 카드 (누를 수 있으면 물결 효과)
class HomeCard extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const HomeCard({
    super.key,
    this.color = Colors.white,
    this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 아이콘 + 이름 하나짜리 1×1 바로가기 타일
class HomeShortcutTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? sub;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;

  const HomeShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.iconColor = kInk,
    this.iconBg = kBg,
    this.color = Colors.white,
    this.textColor = kInk,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      color: color,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GuestText(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
              if (sub != null)
                GuestText(sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.65))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 카드 윗줄: 아이콘 + 제목 + 꺾쇠
class HomeCardHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color titleColor;
  final bool chevron;

  const HomeCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor = kOrange,
    this.titleColor = kInk,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: GuestText(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: titleColor)),
        ),
        if (chevron) Icon(Icons.chevron_right, color: titleColor.withValues(alpha: 0.4)),
      ],
    );
  }
}

/// 흰 알약 버튼 (반 칸 높이 위젯용 — 추천 게임·인원별·장르별·난이도별)
class HomePillButton extends StatelessWidget {
  final IconData? icon;
  final Color iconColor;
  final Widget? leading; // 아이콘 대신 넣을 것 (난이도 색 점 등)
  final String label;
  final VoidCallback onTap;

  const HomePillButton({
    super.key,
    this.icon,
    this.iconColor = kInk,
    this.leading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)] else if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GuestText(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
