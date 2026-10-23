import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_info_service.dart';
import 'package:boardpad/utils/game_meta.dart';

/// 메인 화면 시안들이 같이 쓰는 작은 위젯·함수 모음

/// 현재 시각을 주기적으로 갱신해서 그려주는 위젯
class LiveClock extends StatefulWidget {
  final Widget Function(BuildContext context, DateTime now) builder;
  const LiveClock({super.key, required this.builder});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// 오후 11:47
String formatTimeKo(DateTime t) {
  final ampm = t.hour < 12 ? '오전' : '오후';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$ampm $h:${t.minute.toString().padLeft(2, '0')}';
}

/// 23:47
String formatTime24(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 10월 23일 (금)
String formatDateKo(DateTime t) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${t.month}월 ${t.day}일 (${days[t.weekday - 1]})';
}

/// 5초 동안 누르고 있으면 첫 화면(역할 선택)으로 돌아가는 영역
/// — 기존 상단 바의 매장 이름 영역과 같은 동작
class HoldToExit extends StatefulWidget {
  final Widget child;
  const HoldToExit({super.key, required this.child});

  @override
  State<HoldToExit> createState() => _HoldToExitState();
}

class _HoldToExitState extends State<HoldToExit> {
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
    });
  }

  void _cancel() => _timer?.cancel();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _start(),
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      child: widget.child,
    );
  }
}

/// 매장 전화번호 (settings/storeInfo). 없으면 아무것도 안 그림
class StorePhoneText extends StatelessWidget {
  final TextStyle style;
  const StorePhoneText({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: StoreInfoService.phoneNumber(),
      builder: (context, snapshot) {
        final phone = snapshot.data ?? '';
        if (phone.isEmpty) return const SizedBox.shrink();
        return Text(phone, style: style);
      },
    );
  }
}

/// settings/<docId> 문서의 items 중 첫 번째 항목 제목 (공지: notices, 이벤트: events)
class LatestItemTitle extends StatelessWidget {
  final String docId;
  final String emptyText;
  final TextStyle style;
  final int maxLines;

  const LatestItemTitle({
    super.key,
    required this.docId,
    required this.emptyText,
    required this.style,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc(docId).snapshots(),
      builder: (context, snapshot) {
        String title = '';
        final data = snapshot.data?.data();
        if (data is Map<String, dynamic>) {
          final items = data['items'];
          if (items is List && items.isNotEmpty && items.first is Map) {
            title = ((items.first as Map)['title'] ?? '').toString();
          }
        }
        return Text(
          title.isEmpty ? emptyText : title,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// 게임 목록의 인원 필터 값 (게임 목록 화면의 playerOptions와 같아야 함)
const List<String> homePlayerOptions = ['2인전용', '2인이상', '3인이상', '4인이상', '5인이상', '6인이상'];

/// settings/genres 문서의 장르 목록
Future<List<String>> loadGenres() async {
  try {
    final doc = await FirebaseFirestore.instance.collection('settings').doc('genres').get();
    final items = (doc.data() ?? {})['items'];
    if (items is List) return items.map((e) => e.toString()).toList();
  } catch (_) {}
  return [];
}

/// 필터 값 하나를 고르는 아래쪽 시트. 고르면 onPick이 불림
Future<void> showFilterPicker({
  required BuildContext context,
  required String title,
  required Future<List<String>> options,
  required void Function(String value) onPick,
  bool showDifficultyColors = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            FutureBuilder<List<String>>(
              future: options,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return const Text('선택할 항목이 없어요.', style: TextStyle(color: Colors.grey));
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: list.map((value) {
                    return ActionChip(
                      avatar: showDifficultyColors
                          ? CircleAvatar(backgroundColor: difficultyColor(value), radius: 7)
                          : null,
                      label: Text(value, style: const TextStyle(fontSize: 17)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: const StadiumBorder(),
                      onPressed: () {
                        Navigator.pop(ctx);
                        onPick(value);
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
