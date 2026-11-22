import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';
import 'package:boardpad/widgets/pad_idle_home.dart';
import 'package:boardpad/widgets/tools/dice_roller.dart';
import 'package:boardpad/widgets/tools/finger_team_picker.dart';
import 'package:boardpad/widgets/tools/timer_widgets.dart';
import 'dart:async';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class GameToolsScreen extends StatefulWidget {
  final int? roomNumber;

  /// 134차: 처음 열 탭 (0 타이머 · 1 주사위 · 2 팀 나누기/선 뽑기) — 홈 '팀 나누기·선 뽑기' 위젯이 2로 엶
  final int initialTab;

  /// 134차: 팀 나누기 탭을 선 뽑기 모드로 열기
  final bool pickFirst;
  const GameToolsScreen({super.key, this.roomNumber, this.initialTab = 0, this.pickFirst = false});

  @override
  State<GameToolsScreen> createState() => _GameToolsScreenState();
}

class _GameToolsScreenState extends State<GameToolsScreen> {

  // 126차: 손가락 팀 나누기(최대 6팀)에서 바로 구분되게 — 주황·파랑·초록·보라·분홍·청록 (예전엔 주황이 두 개)
  static const List<Color> _teamColors = [
    kOrange, Color(0xFF2F6FED), Color(0xFF2E9E5B),
    Color(0xFF8E44D9), Color(0xFFE0457B), Color(0xFF14A3A3),
  ];

  // ── 타이머 공통 ──────────────────────────────────────
  bool _isCountdownMode = true; // true: 카운트다운 / false: 스탑워치

  // ── 카운트다운 ───────────────────────────────────────
  int _totalSeconds = 0;       // 설정된 총 초
  int _remainingSeconds = 0;   // 남은 초
  bool _cdRunning = false;
  bool _cdFinished = false;
  Timer? _cdTimer;
  bool _flashRed = false;
  Timer? _flashTimer;
  bool _alarmPlaying = false;

  void _addTime(int seconds) {
    if (_cdRunning) return;
    setState(() {
      _totalSeconds += seconds;
      _remainingSeconds = _totalSeconds;
      _cdFinished = false;
    });
  }

  void _cdStart() {
    if (_remainingSeconds <= 0) return;
    _cdTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _cdFinished = true;
          _cdRunning = false;
          PadIdleHome.release(this); // 140차
          timer.cancel();
          _startFlash();
          FlutterRingtonePlayer().playAlarm();
          _alarmPlaying = true;
        }
      });
    });
    PadIdleHome.hold(this); // 140차: 타이머가 도는 동안엔 30분 자동 홈으로 가지 않음
    setState(() => _cdRunning = true);
  }

  void _cdPause() {
    _cdTimer?.cancel();
    PadIdleHome.release(this);
    setState(() => _cdRunning = false);
  }

  void _cdReset() {
    _cdTimer?.cancel();
    PadIdleHome.release(this);
    _flashTimer?.cancel();
    FlutterRingtonePlayer().stop();
    setState(() {
      _remainingSeconds = _totalSeconds;
      _cdRunning = false;
      _cdFinished = false;
      _flashRed = false;
      _alarmPlaying = false;
    });
  }

  void _cdClear() {
    _cdTimer?.cancel();
    PadIdleHome.release(this);
    _flashTimer?.cancel();
    FlutterRingtonePlayer().stop();
    setState(() {
      _totalSeconds = 0;
      _remainingSeconds = 0;
      _cdRunning = false;
      _cdFinished = false;
      _flashRed = false;
      _alarmPlaying = false;
    });
  }

  void _stopAlarm() {
    FlutterRingtonePlayer().stop();
    setState(() => _alarmPlaying = false);
  }

  void _startFlash() {
    int count = 0;
    _flashTimer = Timer.periodic(const Duration(milliseconds: 400), (t) {
      setState(() => _flashRed = !_flashRed);
      if (++count >= 10) { t.cancel(); setState(() => _flashRed = false); }
    });
  }

  void _showTimeInputDialog() {
    final minCtrl = TextEditingController();
    final secCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const GuestText('시간 직접 입력', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: guestTr(context, '분'), border: OutlineInputBorder(), suffixText: guestTr(context, '분')),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: secCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: guestTr(context, '초'), border: OutlineInputBorder(), suffixText: guestTr(context, '초')),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const GuestText('취소')),
          ElevatedButton(
            onPressed: () {
              final m = int.tryParse(minCtrl.text) ?? 0;
              final s = int.tryParse(secCtrl.text) ?? 0;
              setState(() {
                _totalSeconds = m * 60 + s;
                _remainingSeconds = _totalSeconds;
                _cdFinished = false;
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kInk, foregroundColor: Colors.white),
            child: const GuestText('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2).toInt(),
      child: PadShell(
        current: 'tools',
        roomNumber: widget.roomNumber,
        title: '게임도구',
        subtitle: '타이머 · 주사위 · 팀 나누기',
        headerBottom: const PadTabBar(
          tabs: [
            Tab(height: 46, child: _ToolTabLabel(Icons.timer, '타이머')),
            Tab(height: 46, child: _ToolTabLabel(Icons.casino, '주사위')),
            Tab(height: 46, child: _ToolTabLabel(Icons.group, '팀 나누기 / 선 뽑기')),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: Colors.white,
              child: TabBarView(
                // 126차: 옆으로 밀어서 탭 바꾸기 끔 — 팀 나누기에서 손가락을 대고 움직여도 탭이 안 넘어가게 (탭은 위 버튼으로)
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildTimerTab(),
                  _buildDiceTab(),
                  _buildTeamTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 타이머 탭 ────────────────────────────────────────
  Widget _buildTimerTab() {
    return Column(
      children: [
        // 카운트다운 / 스탑워치 토글
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModeButton('카운트다운', Icons.hourglass_bottom, true),
              const SizedBox(width: 16),
              _buildModeButton('스탑워치', Icons.timer_outlined, false),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isCountdownMode ? _buildCountdown() : _buildStopwatch(),
        ),
      ],
    );
  }

  Widget _buildModeButton(String label, IconData icon, bool isCountdown) {
    final bool selected = _isCountdownMode == isCountdown;
    return GestureDetector(
      onTap: () => setState(() => _isCountdownMode = isCountdown),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kInk : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 8),
            GuestText(label, style: TextStyle(color: selected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ── 카운트다운 화면 (131차: 원형 띠·둥근 칩·글자 붙은 버튼 — lib/widgets/tools/timer_widgets.dart) ──
  Widget _buildCountdown() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      // 시간이 끝나면 화면 전체가 옅은 빨강으로 깜빡임
      color: _flashRed ? const Color(0xFFFCEBEB) : Colors.white,
      child: LayoutBuilder(builder: (context, box) {
        final ring = (box.maxHeight - 260).clamp(180.0, 340.0).toDouble();
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CountdownRing(
                    remaining: _remainingSeconds,
                    total: _totalSeconds,
                    running: _cdRunning,
                    finished: _cdFinished,
                    size: ring,
                  ),
                  if (_cdFinished && _alarmPlaying)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ElevatedButton.icon(
                        onPressed: _stopAlarm,
                        icon: const Icon(Icons.volume_off),
                        label: const GuestText('알림 끄기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE24B4A),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (label, sec) in const [('+30초', 30), ('+1분', 60), ('+3분', 180), ('+5분', 300), ('+10분', 600)])
                        TimeChip(label: label, onTap: _cdRunning ? null : () => _addTime(sec)),
                      TimeChip(label: '직접 입력', icon: Icons.edit, outlined: true, onTap: _cdRunning ? null : _showTimeInputDialog),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ToolRoundButton(icon: Icons.delete_outline, label: '지우기', onTap: _totalSeconds > 0 ? _cdClear : null),
                      const SizedBox(width: 28),
                      ToolRoundButton(
                        icon: Icons.replay,
                        label: '처음부터',
                        onTap: _totalSeconds > 0 && (_remainingSeconds != _totalSeconds || _cdFinished) ? _cdReset : null,
                      ),
                      const SizedBox(width: 28),
                      ToolRoundButton(
                        icon: _cdRunning ? Icons.pause : Icons.play_arrow,
                        label: _cdRunning ? '일시정지' : '시작',
                        primary: true,
                        onTap: _cdRunning ? _cdPause : (_remainingSeconds > 0 ? _cdStart : null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── 스탑워치 화면 (131차: 초침 다이얼·랩 카드 — timer_widgets.dart StopwatchView) ──
  Widget _buildStopwatch() => const StopwatchView();

  // ── 주사위 탭 ────────────────────────────────────────
  // 126차: 굴러가는 주사위(1~3개) — lib/widgets/tools/dice_roller.dart
  Widget _buildDiceTab() => const DiceRoller();

  // ── 팀 나누기 / 선 뽑기 탭 ──────────────────────────
  late bool _isTeamMode = !widget.pickFirst; // true: 팀 나누기 / false: 선 뽑기

  Widget _buildTeamTab() {
    return Column(
      children: [
        // 모드 토글
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTeamModeButton('팀 나누기', Icons.group, true),
              const SizedBox(width: 16),
              _buildTeamModeButton('선 뽑기', Icons.touch_app, false),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // 126차: 팀 나누기 = 손가락을 꾹 대면 같은 팀끼리 같은 색 원 (lib/widgets/tools/finger_team_picker.dart)
          // 127차: 선 뽑기도 손가락 — 꾹 댄 손가락 중 하나에 불빛 (예전 이름 입력·뽑기 순서 화면은 지움)
          child: FingerTeamPicker(key: ValueKey(_isTeamMode), colors: _teamColors, pickOne: !_isTeamMode),
        ),
      ],
    );
  }

  Widget _buildTeamModeButton(String label, IconData icon, bool isTeam) {
    final bool selected = _isTeamMode == isTeam;
    return GestureDetector(
      onTap: () => setState(() {
        _isTeamMode = isTeam;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kInk : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 8),
            GuestText(label, style: TextStyle(color: selected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cdTimer?.cancel();
    _flashTimer?.cancel();
    FlutterRingtonePlayer().stop();
    PadIdleHome.release(this);
    super.dispose();
  }
}

/// 게임도구 탭 이름 (아이콘 + 글자)
class _ToolTabLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ToolTabLabel(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 20), const SizedBox(width: 6), GuestText(text)],
    );
  }
}
