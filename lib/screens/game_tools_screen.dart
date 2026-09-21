import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class GameToolsScreen extends StatefulWidget {
  const GameToolsScreen({super.key});

  @override
  State<GameToolsScreen> createState() => _GameToolsScreenState();
}

class _GameToolsScreenState extends State<GameToolsScreen> {

  static const List<Color> _teamColors = [
    Color(0xFF00B37E), Colors.blueAccent, Colors.orangeAccent,
    Colors.purpleAccent, Colors.redAccent, Colors.teal,
    Colors.pinkAccent, Colors.indigo, Colors.amber, Colors.cyan,
  ];

  // ── 주사위 ──────────────────────────────────────────
  int diceNumber = 1;
  void _rollDice() => setState(() => diceNumber = Random().nextInt(6) + 1);

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
        title: const Text('시간 직접 입력', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: minCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '분', border: OutlineInputBorder(), suffixText: '분'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: secCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '초', border: OutlineInputBorder(), suffixText: '초'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C3E50), foregroundColor: Colors.white),
            child: const Text('확인'),
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
  void initState() {
    super.initState();
    _syncControllers(_playerCount);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        body: SafeArea(
          child: Column(
            children: [
              // 상단 바
              Container(
                color: const Color(0xFF00B37E),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    ClipOval(child: Image.asset('assets/images/logo.jpg', width: 40, height: 40, fit: BoxFit.cover)),
                    const SizedBox(width: 16),
                    const Text('게임 도구', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const Spacer(),
                  ],
                ),
              ),
              // 도구 선택 탭
              Container(
                color: const Color(0xFF2C3E50),
                child: const TabBar(
                  indicatorColor: Color(0xFF00B37E),
                  indicatorWeight: 4,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  tabs: [
                    Tab(icon: Icon(Icons.timer), text: '타이머'),
                    Tab(icon: Icon(Icons.casino), text: '주사위'),
                    Tab(icon: Icon(Icons.group), text: '팀 나누기 / 선 뽑기'),
                  ],
                ),
              ),
              // 탭 내용
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTimerTab(),
                    _buildDiceTab(),
                    _buildTeamTab(),
                  ],
                ),
              ),
            ],
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
          color: selected ? const Color(0xFF2C3E50) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ── 카운트다운 화면 ───────────────────────────────────
  Widget _buildCountdown() {
    final Color timeColor = _cdFinished
        ? Colors.redAccent
        : (_flashRed ? Colors.redAccent : const Color(0xFF2C3E50));

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
              child: Text(
                _formatCd(_remainingSeconds),
                style: TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: timeColor, fontFeatures: const []),
              ),
            ),
            if (_cdFinished)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    const Text('⏰ 시간 종료!', style: TextStyle(fontSize: 24, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    if (_alarmPlaying)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ElevatedButton.icon(
                          onPressed: _stopAlarm,
                          icon: const Icon(Icons.volume_off),
                          label: const Text('알림 끄기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  label: const Text('직접 입력'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    side: const BorderSide(color: Color(0xFF2C3E50)),
                    foregroundColor: const Color(0xFF2C3E50),
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
                  backgroundColor: _cdRunning ? Colors.orange : const Color(0xFF00B37E),
                  child: Icon(_cdRunning ? Icons.pause : Icons.play_arrow, size: 40),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '🔄 리셋: 설정 시간으로 복귀   🗑 초기화: 전체 지우기',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
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
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  // ── 스탑워치 화면 ─────────────────────────────────────
  Widget _buildStopwatch() => const _StopwatchTab();

  // ── 주사위 탭 ────────────────────────────────────────
  Widget _buildDiceTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.black12, width: 4),
            ),
            child: Center(child: Text('$diceNumber', style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _rollDice,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              backgroundColor: const Color(0xFF00B37E),
            ),
            child: const Text('주사위 굴리기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── 팀 나누기 / 선 뽑기 탭 ──────────────────────────
  bool _isTeamMode = true; // true: 팀 나누기 / false: 선 뽑기

  // 공통 - 이름 입력
  final List<TextEditingController> _nameControllers = [];
  int _playerCount = 4;

  // 팀 나누기
  int _teamCount = 2;
  List<List<String>> _teamResult = [];

  // 선 뽑기
  List<String> _drawOrder = [];
  List<String> _remainingPool = [];
  bool _drawFinished = false;

  void _syncControllers(int count) {
    while (_nameControllers.length < count) {
      _nameControllers.add(TextEditingController());
    }
    while (_nameControllers.length > count) {
      _nameControllers.last.dispose();
      _nameControllers.removeLast();
    }
  }

  List<String> _getPlayerNames() {
    return List.generate(_playerCount, (i) {
      final text = _nameControllers[i].text.trim();
      return text.isEmpty ? '${i + 1}번' : text;
    });
  }

  void _divideTeams() {
    final players = List<String>.from(_getPlayerNames())..shuffle(Random());
    final result = List.generate(_teamCount, (_) => <String>[]);
    for (int i = 0; i < players.length; i++) {
      result[i % _teamCount].add(players[i]);
    }
    setState(() => _teamResult = result);
  }

  void _initDraw() {
    setState(() {
      _drawOrder = [];
      _remainingPool = List<String>.from(_getPlayerNames())..shuffle(Random());
      _drawFinished = false;
    });
  }

  void _drawNext() {
    if (_remainingPool.isEmpty) return;
    setState(() {
      _drawOrder.add(_remainingPool.removeAt(0));
      if (_remainingPool.isEmpty) _drawFinished = true;
    });
  }

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
              _buildTeamModeButton('선 뽑기', Icons.casino, false),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isTeamMode ? _buildTeamDivide() : _buildDraw(),
        ),
      ],
    );
  }

  Widget _buildTeamModeButton(String label, IconData icon, bool isTeam) {
    final bool selected = _isTeamMode == isTeam;
    return GestureDetector(
      onTap: () => setState(() {
        _isTeamMode = isTeam;
        _teamResult = [];
        _drawOrder = [];
        _remainingPool = [];
        _drawFinished = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C3E50) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  // ── 팀 나누기 화면 ───────────────────────────────────
  Widget _buildTeamDivide() {
    return Row(
      children: [
        // 왼쪽: 설정 패널
        Container(
          width: 320,
          color: Colors.white,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('인원 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildCountRow('총 인원', _playerCount, 2, 20, (v) => setState(() { _playerCount = v; _syncControllers(v); _teamResult = []; })),
              const SizedBox(height: 8),
              _buildCountRow('팀 수', _teamCount, 2, 10, (v) => setState(() { _teamCount = v; _teamResult = []; })),
              const SizedBox(height: 20),
              const Text('이름 입력 (선택)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('비워두면 번호로 자동 부여', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _playerCount,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _nameControllers[i],
                      decoration: InputDecoration(
                        labelText: '${i + 1}번째 참가자',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF2C3E50),
                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                      onChanged: (_) => setState(() => _teamResult = []),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _teamCount > _playerCount ? null : _divideTeams,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('랜덤 팀 배분', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B37E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (_teamCount > _playerCount)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('⚠ 팀 수가 인원보다 많습니다', style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 오른쪽: 결과
        Expanded(
          child: _teamResult.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('인원과 팀 수를 설정하고 랜덤 팀 배분을 눌러주세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, color: Colors.grey)),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _teamResult.length <= 3 ? _teamResult.length : 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: _teamResult.length,
                    itemBuilder: (context, i) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _teamColors[i % _teamColors.length], width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8)],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _teamColors[i % _teamColors.length],
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                              ),
                              child: Text('${i + 1}팀', textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _teamResult[i].length,
                                itemBuilder: (context, j) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.person, color: _teamColors[i % _teamColors.length], size: 18),
                                      const SizedBox(width: 8),
                                      Text(_teamResult[i][j], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── 선 뽑기 화면 ─────────────────────────────────────
  Widget _buildDraw() {
    return Row(
      children: [
        // 왼쪽: 설정 패널
        Container(
          width: 320,
          color: Colors.white,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('인원 설정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildCountRow('총 인원', _playerCount, 2, 20, (v) => setState(() { _playerCount = v; _syncControllers(v); _drawOrder = []; _remainingPool = []; _drawFinished = false; })),
              const SizedBox(height: 20),
              const Text('이름 입력 (선택)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Text('비워두면 번호로 자동 부여', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _playerCount,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _nameControllers[i],
                      decoration: InputDecoration(
                        labelText: '${i + 1}번째 참가자',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF2C3E50),
                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _initDraw,
                  icon: const Icon(Icons.refresh),
                  label: const Text('뽑기 초기화', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2C3E50),
                    side: const BorderSide(color: Color(0xFF2C3E50), width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 오른쪽: 뽑기 화면
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // 뽑기 버튼 영역
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8)],
                  ),
                  child: _drawFinished
                      ? Column(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF00B37E), size: 60),
                            const SizedBox(height: 8),
                            const Text('모든 순서가 결정됐습니다!',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00B37E))),
                          ],
                        )
                      : (_remainingPool.isEmpty && _drawOrder.isEmpty)
                          ? Column(
                              children: [
                                const Icon(Icons.touch_app, size: 60, color: Colors.grey),
                                const SizedBox(height: 8),
                                const Text('초기화 후 뽑기 시작 버튼을 눌러주세요',
                                    style: TextStyle(fontSize: 18, color: Colors.grey)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _initDraw,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('뽑기 시작', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2C3E50),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Text('남은 인원: ${_remainingPool.length}명',
                                    style: const TextStyle(fontSize: 16, color: Colors.grey)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _drawNext,
                                  icon: const Icon(Icons.casino, size: 28),
                                  label: const Text('다음 순서 뽑기!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00B37E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                                  ),
                                ),
                              ],
                            ),
                ),
                const SizedBox(height: 24),
                // 뽑힌 순서 목록
                if (_drawOrder.isNotEmpty)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8)],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2C3E50),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: const Text('뽑힌 순서', textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _drawOrder.length,
                              itemBuilder: (context, i) {
                                final rank = i + 1;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey.shade400 : (rank == 3 ? Colors.brown.shade300 : const Color(0xFF2C3E50))),
                                    child: Text('$rank', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(_drawOrder[i], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  subtitle: Text('$rank번째'),
                                );
                              },
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
      ],
    );
  }

  Widget _buildCountRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        const Spacer(),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
          color: const Color(0xFF2C3E50),
        ),
        SizedBox(
          width: 40,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
          color: const Color(0xFF2C3E50),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _cdTimer?.cancel();
    _flashTimer?.cancel();
    FlutterRingtonePlayer().stop();
    for (final c in _nameControllers) { c.dispose(); }
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
                child: Text(
                  _formatSw(_stopwatch.elapsed),
                  style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
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
                    backgroundColor: _swRunning ? Colors.orange : const Color(0xFF00B37E),
                    child: Icon(_swRunning ? Icons.pause : Icons.play_arrow, size: 40),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton.large(
                    heroTag: 'sw_lap',
                    onPressed: _swRunning ? _recordLap : null,
                    backgroundColor: _swRunning ? const Color(0xFF2C3E50) : Colors.grey.shade300,
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
                    color: Color(0xFF2C3E50),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Center(
                    child: Text('랩 기록 (${_laps.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _laps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF00B37E),
                        child: Text('${_laps.length - index}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(_laps[index], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
