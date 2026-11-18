import 'package:boardpad/l10n/guest_language.dart';
import 'package:flutter/material.dart';
import 'package:boardpad/widgets/home/home_theme.dart';
import 'package:boardpad/widgets/pad_shell.dart';
import 'package:boardpad/widgets/tools/dice_roller.dart';
import 'package:boardpad/widgets/tools/finger_team_picker.dart';
import 'dart:async';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class GameToolsScreen extends StatefulWidget {
  final int? roomNumber;
  const GameToolsScreen({super.key, this.roomNumber});

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
          timer.cancel();
          _startFlash();
          FlutterRingtonePlayer().playAlarm();
          _alarmPlaying = true;
        }
      });
    });
    setState(() => _cdRunning = true);
  }

  void _cdPause() {
    _cdTimer?.cancel();
    setState(() => _cdRunning = false);
  }

  void _cdReset() {
    _cdTimer?.cancel();
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

  String _formatCd(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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

  // ── 카운트다운 화면 ───────────────────────────────────
  Widget _buildCountdown() {
    final Color timeColor = _cdFinished
        ? Colors.redAccent
        : (_flashRed ? Colors.redAccent : kInk);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 시간 표시
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              decoration: BoxDecoration(
                color: _flashRed ? Colors.red.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: GuestText(
                _formatCd(_remainingSeconds),
                style: TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: timeColor, fontFeatures: const []),
              ),
            ),
            if (_cdFinished)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    const GuestText('⏰ 시간 종료!', style: TextStyle(fontSize: 24, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    if (_alarmPlaying)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ElevatedButton.icon(
                          onPressed: _stopAlarm,
                          icon: const Icon(Icons.volume_off),
                          label: const GuestText('알림 끄기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 32),
            // 프리셋 버튼
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _presetBtn('+30초', 30),
                _presetBtn('+1분', 60),
                _presetBtn('+3분', 180),
                _presetBtn('+5분', 300),
                _presetBtn('+10분', 600),
                OutlinedButton.icon(
                  onPressed: _cdRunning ? null : _showTimeInputDialog,
                  icon: const Icon(Icons.edit),
                  label: const GuestText('직접 입력'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    side: const BorderSide(color: kInk),
                    foregroundColor: kInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // 제어 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 초기화
                FloatingActionButton.large(
                  heroTag: 'cd_clear',
                  onPressed: _cdClear,
                  backgroundColor: Colors.grey.shade400,
                  child: const Icon(Icons.delete_outline, size: 32),
                ),
                const SizedBox(width: 24),
                // 리셋 (설정 시간으로)
                FloatingActionButton.large(
                  heroTag: 'cd_reset',
                  onPressed: _cdReset,
                  backgroundColor: Colors.grey.shade600,
                  child: const Icon(Icons.replay, size: 32),
                ),
                const SizedBox(width: 24),
                // 시작 / 일시정지
                FloatingActionButton.large(
                  heroTag: 'cd_play',
                  onPressed: _cdRunning ? _cdPause : _cdStart,
                  backgroundColor: _cdRunning ? Colors.orange : kOrange,
                  child: Icon(_cdRunning ? Icons.pause : Icons.play_arrow, size: 40),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetBtn(String label, int seconds) {
    return ElevatedButton(
      onPressed: _cdRunning ? null : () => _addTime(seconds),
      style: ElevatedButton.styleFrom(
        backgroundColor: kInk,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: GuestText(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  // ── 스탑워치 화면 ─────────────────────────────────────
  Widget _buildStopwatch() => const _StopwatchTab();

  // ── 주사위 탭 ────────────────────────────────────────
  // 126차: 굴러가는 주사위(1~3개) — lib/widgets/tools/dice_roller.dart
  Widget _buildDiceTab() => const DiceRoller();

  // ── 팀 나누기 / 선 뽑기 탭 ──────────────────────────
  bool _isTeamMode = true; // true: 팀 나누기 / false: 선 뽑기

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
    super.dispose();
  }
}

// ── 스탑워치 전용 위젯 (30ms 타이머를 이 위젯 안에서만 관리) ───────────────
class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab();

  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _swTimer;
  bool _swRunning = false;
  final List<String> _laps = [];

  void _swStart() {
    _stopwatch.start();
    _swTimer = Timer.periodic(const Duration(milliseconds: 30), (_) => setState(() {}));
    setState(() => _swRunning = true);
  }

  void _swPause() {
    _stopwatch.stop();
    _swTimer?.cancel();
    setState(() => _swRunning = false);
  }

  void _swReset() {
    _stopwatch.reset();
    _swTimer?.cancel();
    setState(() {
      _swRunning = false;
      _laps.clear();
    });
  }

  void _recordLap() {
    setState(() => _laps.insert(0, _formatSw(_stopwatch.elapsed)));
  }

  String _formatSw(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$m : $s . $ms';
  }

  @override
  void dispose() {
    _swTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 왼쪽: 메인 스탑워치
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: GuestText(
                  _formatSw(_stopwatch.elapsed),
                  style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: kInk),
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.large(
                    heroTag: 'sw_reset',
                    onPressed: _swReset,
                    backgroundColor: Colors.grey.shade500,
                    child: const Icon(Icons.replay, size: 32),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton.large(
                    heroTag: 'sw_play',
                    onPressed: _swRunning ? _swPause : _swStart,
                    backgroundColor: _swRunning ? Colors.orange : kOrange,
                    child: Icon(_swRunning ? Icons.pause : Icons.play_arrow, size: 40),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton.large(
                    heroTag: 'sw_lap',
                    onPressed: _swRunning ? _recordLap : null,
                    backgroundColor: _swRunning ? kInk : Colors.grey.shade300,
                    child: const Icon(Icons.flag, size: 32),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 오른쪽: 랩 기록
        if (_laps.isNotEmpty)
          Container(
            width: 240,
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(
                    color: kInk,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Center(
                    child: GuestText('랩 기록 (${_laps.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _laps.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: kOrange,
                        child: GuestText('${_laps.length - index}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      title: GuestText(_laps[index], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
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
