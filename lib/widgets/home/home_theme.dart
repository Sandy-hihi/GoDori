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

void homeGo(BuildContext context, Widget page) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
              Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
              if (sub != null)
                Text(sub!,
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
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: titleColor)),
        ),
        if (chevron) Icon(Icons.chevron_right, color: titleColor.withValues(alpha: 0.4)),
      ],
    );
  }
}
