import 'package:flutter/material.dart';
import 'package:boardpad/screens/notice_screen.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';

/// 이벤트 (settings/events) — 관리자 웹 '이벤트 관리'에서 등록
class EventScreen extends StatelessWidget {
  final int? roomNumber;
  const EventScreen({super.key, this.roomNumber});

  @override
  Widget build(BuildContext context) {
    return PadShell(
      current: 'event',
      roomNumber: roomNumber,
      title: '이벤트',
      subtitle: '지금 진행 중인 이벤트예요',
      body: const PadPostList(
        docId: 'events',
        icon: Icons.card_giftcard_outlined,
        accent: kOrange,
        emptyText: '지금 진행 중인 이벤트가 없어요.',
      ),
    );
  }
}
