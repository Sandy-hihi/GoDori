import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boardpad/services/store_info_service.dart';
import 'package:boardpad/utils/game_meta.dart';
import 'package:boardpad/services/store_scope.dart';
import 'package:boardpad/services/admin_session.dart';
import 'package:boardpad/screens/login_screen.dart';

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

/// 보이는 버튼과 로고 연타가 같은 인증·로그아웃 절차를 사용합니다.
class PadLogoutActions {
  const PadLogoutActions();

  Future<void> verifyPassword(String password) =>
      AdminSession.verifyExit(password);
  Future<void> signOut() => AdminSession.signOutPad();
}

Future<void> showPadLogout(
  BuildContext context, {
  int? roomNumber,
  PadLogoutActions actions = const PadLogoutActions(),
}) async {
  final navigator = Navigator.of(context);
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ExitDialog(roomNumber: roomNumber, actions: actions),
  );
  if (ok != true || !context.mounted) return;
  await actions.signOut();
  if (!context.mounted) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

/// 손님용 패드의 방 번호를 다시 입력하기 위한 직원용 버튼.
class PadLogoutButton extends StatefulWidget {
  final int? roomNumber;
  final Color? foregroundColor;
  final bool enabled;
  final PadLogoutActions actions;

  const PadLogoutButton({
    super.key,
    this.roomNumber,
    this.foregroundColor,
    this.enabled = true,
    this.actions = const PadLogoutActions(),
  });

  @override
  State<PadLogoutButton> createState() => _PadLogoutButtonState();
}

class _PadLogoutButtonState extends State<PadLogoutButton> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await showPadLogout(
        context,
        roomNumber: widget.roomNumber,
        actions: widget.actions,
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: widget.enabled && !_opening ? _open : null,
    style: TextButton.styleFrom(
      foregroundColor: widget.foregroundColor,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    icon: const Icon(Icons.logout, size: 18),
    label: const Text('로그아웃 · 방 변경', style: TextStyle(fontSize: 12)),
  );
}

/// 빠르게 10번 누르면 '패드 로그아웃' 창 (55·56차)
/// 예전(47차)엔 5초 누르기로 바로 로그아웃 → 손님이 무심코 로고를 오래 누르고 있다가 로그아웃되는 일이 잦아서
/// 56차부터 빠르게 10번(누르는 사이 0.7초 안) + 패드 비밀번호(직원용) 또는 관리자 PIN을 넣어야 로그아웃됨.
/// 30초 동안 입력이 없으면 창이 저절로 닫힘. 창 바깥 누르기는 창이 뜨고 2초 뒤부터만 닫힘(연타가 넘쳐도 창이 유지되게, 62차).
class HoldToExit extends StatefulWidget {
  final Widget child;
  const HoldToExit({super.key, required this.child});

  @override
  State<HoldToExit> createState() => _HoldToExitState();
}

class _HoldToExitState extends State<HoldToExit> {
  static const _tapsNeeded = 10;
  static const _maxGap = Duration(milliseconds: 700);

  int _taps = 0;
  DateTime? _lastTap;
  bool _dialogOpen = false;

  void _onTap() {
    if (_dialogOpen) return;
    final now = DateTime.now();
    final last = _lastTap;
    _taps = (last != null && now.difference(last) <= _maxGap) ? _taps + 1 : 1;
    _lastTap = now;
    if (_taps >= _tapsNeeded) {
      _taps = 0;
      _lastTap = null;
      _askExit();
    }
  }

  Future<void> _askExit() async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    // 62차: 연타하다 11·12번째 터치가 창 바깥(어두운 배경)에 닿으면 창이 바로 닫혀서 다시 10번을 눌러야 했음
    // → 창이 뜬 뒤 2초 동안은 바깥을 눌러도 안 닫힘(_ExitDialog의 PopScope), 2초 뒤부터는 바깥을 누르면 닫힘
    try {
      await showPadLogout(context);
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listener: 누르는 순간 바로 셈(GestureDetector의 탭 판정·더블탭 대기 없이)
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _onTap(),
      child: widget.child,
    );
  }
}

/// 패드 로그아웃 확인 창 — 맞으면 true로 닫힘
class _ExitDialog extends StatefulWidget {
  final int? roomNumber;
  final PadLogoutActions actions;
  const _ExitDialog({this.roomNumber, required this.actions});

  @override
  State<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends State<_ExitDialog> {
  final _controller = TextEditingController();
  Timer? _idle;
  Timer? _armTimer;
  bool _checking = false;
  bool _outsideCloses = false; // 62차: 창이 뜨고 2초 뒤부터 바깥을 누르면 닫힘
  String? _error;

  /// 창이 뜬 뒤 이 시간 동안은 바깥 터치(연타가 넘친 것)를 무시
  static const outsideGrace = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _resetIdle();
    _armTimer = Timer(outsideGrace, () {
      if (mounted) setState(() => _outsideCloses = true);
    });
  }

  // 30초 동안 아무 입력이 없으면 닫힘 (손님이 잘못 눌러 띄운 경우)
  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 30), () {
      if (mounted && !_checking) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _armTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pw = _controller.text.trim();
    if (pw.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.actions.verifyPassword(pw);
      if (mounted) Navigator.of(context).pop(true);
    } on AdminLoginException catch (e) {
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _checking = false;
        _error = e.message;
      });
      _resetIdle();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 바깥 터치·뒤로 가기는 maybePop → canPop이 false면 무시. '닫기'·'로그아웃' 버튼(Navigator.pop)은 언제나 됨
    return PopScope(
      canPop: _outsideCloses && !_checking,
      child: _dialog(context),
    );
  }

  Widget _dialog(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '패드 로그아웃',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.roomNumber != null) ...[
              Text(
                '현재 방: ${widget.roomNumber}번',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            const Text(
              '방 번호를 바꾸려면 로그아웃한 뒤 다시 로그인하세요.\n직원이 패드 비밀번호 또는 관리자 PIN을 입력해 주세요.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              enabled: !_checking,
              onChanged: (_) => _resetIdle(),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '비밀번호 또는 PIN',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _error,
                errorMaxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E2B3C),
          ),
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('로그아웃'),
        ),
      ],
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

/// `settings/<docId>` 문서의 items 중 첫 번째 항목 제목 (공지: notices, 이벤트: events)
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
      stream: StoreScope.col('settings').doc(docId).snapshots(),
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
const List<String> homePlayerOptions = [
  '2인전용',
  '2인이상',
  '3인이상',
  '4인이상',
  '5인이상',
  '6인이상',
];

/// settings/genres 문서의 장르 목록
Future<List<String>> loadGenres() async {
  try {
    final doc = await StoreScope.col('settings').doc('genres').get();
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
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
                  return const Text(
                    '선택할 항목이 없어요.',
                    style: TextStyle(color: Colors.grey),
                  );
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: list.map((value) {
                    return ActionChip(
                      avatar: showDifficultyColors
                          ? CircleAvatar(
                              backgroundColor: difficultyColor(value),
                              radius: 7,
                            )
                          : null,
                      label: Text(value, style: const TextStyle(fontSize: 17)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
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
